use crate::dashen::Endpoint;
use crate::{AccountSecret, SecretsFile};
use reqwest::{Client, Method};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::{
    collections::VecDeque,
    sync::Arc,
    time::{Duration, Instant},
};
use tokio::sync::{Mutex, Semaphore};
use uuid::Uuid;

/// Allowlisted endpoint paths, derived from [`Endpoint`].
pub fn endpoints() -> Vec<&'static str> {
    crate::dashen::endpoint_paths()
}
#[derive(Clone, Deserialize)]
pub struct RequestSpec {
    pub endpoint: String,
    #[serde(default)]
    pub payload: Value,
}
impl RequestSpec {
    pub fn new(endpoint: Endpoint, payload: Value) -> Self {
        Self {
            endpoint: endpoint.path().into(),
            payload,
        }
    }
}
#[derive(Debug, Clone, Serialize)]
pub struct AccountView {
    pub name: String,
    pub status: &'static str,
    pub cooldown_ms: u128,
}
#[derive(Debug, Clone, Serialize)]
pub struct RequestMetric {
    pub id: Uuid,
    pub endpoint: String,
    pub status: String,
    pub status_code: Option<u16>,
    pub queue_ms: u128,
    pub duration_ms: u128,
    pub attempts: u32,
    pub at_ms: u128,
}
#[derive(Debug, Clone, Serialize)]
pub struct Failure {
    pub kind: &'static str,
    pub message: String,
    pub retry_after_ms: Option<u128>,
}
impl std::fmt::Display for Failure {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.message)
    }
}
impl std::error::Error for Failure {}
fn failure(kind: &'static str, message: &str) -> Failure {
    Failure {
        kind,
        message: message.into(),
        retry_after_ms: None,
    }
}
#[derive(Clone)]
pub struct Policy {
    pub concurrency: usize,
    pub capacity: usize,
    pub timeout: Duration,
    pub cooldown: Duration,
    pub rate_window: Duration,
    pub rate: usize,
    pub max_attempts: u32,
}
impl Default for Policy {
    fn default() -> Self {
        Self {
            concurrency: 2,
            capacity: 8,
            timeout: Duration::from_secs(30),
            cooldown: Duration::from_secs(60),
            rate_window: Duration::from_secs(1),
            rate: 5,
            max_attempts: 3,
        }
    }
}
struct AccountState {
    secret: AccountSecret,
    cooldown_until: Instant,
    starts: VecDeque<Instant>,
    generation: u64,
    disabled: bool,
}
struct Pool {
    accounts: Vec<AccountState>,
    next: usize,
}
pub struct WatchClient {
    http: Client,
    pool: Mutex<Pool>,
    gate: Arc<Semaphore>,
    admission: Arc<Semaphore>,
    metrics: Mutex<VecDeque<RequestMetric>>,
    base_url: String,
    policy: Policy,
}
impl WatchClient {
    pub fn new(secrets: SecretsFile) -> anyhow::Result<Self> {
        Self::with_base(
            secrets,
            "https://datamsapi.ds.163.com/v1/a19ld5tool",
            Policy::default(),
        )
    }
    pub fn with_base(secrets: SecretsFile, base: &str, policy: Policy) -> anyhow::Result<Self> {
        secrets.validate()?;
        anyhow::ensure!(
            policy.concurrency > 0
                && policy.capacity >= policy.concurrency
                && policy.rate > 0
                && policy.max_attempts > 0,
            "Invalid scheduling policy"
        );
        let http = Client::builder().connect_timeout(Duration::from_secs(5)).timeout(Duration::from_secs(15)).redirect(reqwest::redirect::Policy::none()).user_agent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/108.0.0.0 Safari/537.36 app/df_client dfVersion/100111").build()?;
        let accounts = secrets
            .accounts
            .into_iter()
            .map(|secret| AccountState {
                secret,
                cooldown_until: Instant::now(),
                starts: VecDeque::new(),
                generation: 0,
                disabled: false,
            })
            .collect();
        Ok(Self {
            http,
            pool: Mutex::new(Pool { accounts, next: 0 }),
            gate: Arc::new(Semaphore::new(policy.concurrency)),
            admission: Arc::new(Semaphore::new(policy.capacity)),
            metrics: Mutex::new(VecDeque::new()),
            base_url: base.into(),
            policy,
        })
    }
    pub async fn replace_accounts(&self, secrets: SecretsFile) -> Result<(), Failure> {
        secrets
            .validate()
            .map_err(|_| failure("validation", "账号信息不完整，或名称重复。"))?;
        *self.pool.lock().await = Pool {
            accounts: secrets
                .accounts
                .into_iter()
                .map(|secret| AccountState {
                    secret,
                    cooldown_until: Instant::now(),
                    starts: VecDeque::new(),
                    generation: 0,
                    disabled: false,
                })
                .collect(),
            next: 0,
        };
        Ok(())
    }
    pub async fn account_views(&self) -> Vec<AccountView> {
        self.pool
            .lock()
            .await
            .accounts
            .iter()
            .map(|a| AccountView {
                name: a.secret.name.clone(),
                status: if a.disabled {
                    "expired"
                } else if a.cooldown_until > Instant::now() {
                    "cooldown"
                } else {
                    "ready"
                },
                cooldown_ms: a
                    .cooldown_until
                    .saturating_duration_since(Instant::now())
                    .as_millis(),
            })
            .collect()
    }
    pub async fn metrics(&self) -> Vec<RequestMetric> {
        self.metrics.lock().await.iter().cloned().collect()
    }
    async fn account(&self) -> Result<(AccountSecret, u64), Failure> {
        loop {
            let wait = {
                let mut pool = self.pool.lock().await;
                if pool.accounts.is_empty() {
                    return Err(failure("no_account", "先在设置中添加大神账号。"));
                }
                let mut wait: Option<Duration> = None;
                let now = Instant::now();
                for offset in 0..pool.accounts.len() {
                    let i = (pool.next + offset) % pool.accounts.len();
                    let a = &mut pool.accounts[i];
                    if a.disabled {
                        continue;
                    }
                    while a
                        .starts
                        .front()
                        .is_some_and(|t| now.duration_since(*t) >= self.policy.rate_window)
                    {
                        a.starts.pop_front();
                    }
                    let until = if a.starts.len() >= self.policy.rate {
                        a.cooldown_until.max(
                            *a.starts.front().expect("nonempty rate window")
                                + self.policy.rate_window,
                        )
                    } else {
                        a.cooldown_until
                    };
                    if until <= now {
                        a.starts.push_back(now);
                        let selected = (a.secret.clone(), a.generation);
                        pool.next = (i + 1) % pool.accounts.len();
                        return Ok(selected);
                    }
                    let delay = until.saturating_duration_since(now);
                    wait = Some(wait.map_or(delay, |w| w.min(delay)));
                }
                wait.ok_or_else(|| failure("auth", "账号凭据已失效，请在设置中更新 token。"))?
            };
            tokio::time::sleep(wait).await;
        }
    }
    async fn cool(
        &self,
        secret: &AccountSecret,
        _generation: u64,
        delay: Duration,
        disabled: bool,
    ) {
        let mut pool = self.pool.lock().await;
        if let Some(a) = pool.accounts.iter_mut().find(|a| {
            a.secret.name == secret.name
                && a.secret.token == secret.token
                && a.secret.role_id == secret.role_id
        }) {
            a.generation += 1;
            a.cooldown_until = a.cooldown_until.max(Instant::now() + delay);
            a.disabled |= disabled;
        }
    }
    pub async fn request(&self, spec: RequestSpec) -> Result<(RequestMetric, Value), Failure> {
        let Some(endpoint) = Endpoint::parse(&spec.endpoint) else {
            return Err(failure("validation", "不支持的接口。"));
        };
        if !spec.payload.is_object() {
            return Err(failure("validation", "请求参数必须是对象。"));
        }
        let started = Instant::now();
        let mut metric = RequestMetric {
            id: Uuid::new_v4(),
            endpoint: spec.endpoint.clone(),
            status: "pending".into(),
            status_code: None,
            queue_ms: 0,
            duration_ms: 0,
            attempts: 0,
            at_ms: now_ms(),
        };
        // The sample player is answered here and never goes upstream (see `demo`).
        #[cfg(any(debug_assertions, feature = "demo"))]
        if let Some(value) = crate::demo::respond(endpoint, &spec.payload) {
            metric.status = "demo".into();
            return Ok((metric, value));
        }
        let result = match self.admission.clone().try_acquire_owned() {
            Err(_) => Err(failure("busy", "请求队列已满，稍后重试。")),
            Ok(_admission) => match tokio::time::timeout(
                self.policy.timeout,
                self.run(endpoint, &spec, started, &mut metric),
            )
            .await
            {
                Err(_) => Err(failure("timeout", "请求超时。请稍后重试，或检查网络。")),
                Ok(result) => result,
            },
        };
        metric.duration_ms = started.elapsed().as_millis();
        metric.status = result
            .as_ref()
            .map(|_| "ok")
            .unwrap_or_else(|e| e.kind)
            .into();
        let mut metrics = self.metrics.lock().await;
        if metrics.len() >= 500 {
            metrics.pop_front();
        }
        metrics.push_back(metric.clone());
        result.map(|value| (metric, value))
    }
    async fn run(
        &self,
        endpoint: Endpoint,
        spec: &RequestSpec,
        started: Instant,
        metric: &mut RequestMetric,
    ) -> Result<Value, Failure> {
        let _gate = self
            .gate
            .acquire()
            .await
            .map_err(|_| failure("shutdown", "服务正在关闭。"))?;
        metric.queue_ms = started.elapsed().as_millis();
        let mut last = failure("network", "无法连接大神服务，请检查网络。 ");
        for attempt in 1..=self.policy.max_attempts {
            let (account, generation) = self.account().await?;
            metric.attempts = attempt;
            let search = endpoint.is_post();
            let mut payload = spec.payload.clone();
            if endpoint.account_in_payload() {
                payload["token"] = json!(account.token);
                payload["roleId"] = json!(account.role_id);
                payload["dts"] = json!(account.dts);
                payload["server"] = json!(account.server);
            }
            let url = format!(
                "{}/{}",
                self.base_url.trim_end_matches('/'),
                endpoint.path()
            );
            let builder = self
                .http
                .request(if search { Method::POST } else { Method::GET }, url)
                .header("GL-Bigdata-Auth-Token", &account.token)
                .header("GL-Bigdata-Dts", account.dts.to_string())
                .header("GL-Bigdata-Role-Id", account.role_id.to_string())
                .header("GL-Bigdata-Server", account.server.to_string())
                .header("GL-ClientType", "60")
                .header("Origin", "https://act.ds.163.com")
                .header("Referer", "https://act.ds.163.com/");
            let response = if search {
                builder.json(&payload)
            } else {
                builder.query(&payload)
            }
            .send()
            .await;
            match response {
                Err(error) => {
                    if !error.is_connect() && !error.is_timeout() {
                        return Err(failure("network", "请求失败，请检查网络与代理设置。"));
                    }
                    last = failure("network", "大神服务连接失败或读取超时。 ");
                }
                Ok(mut response) => {
                    let status = response.status();
                    metric.status_code = Some(status.as_u16());
                    if matches!(status.as_u16(), 401 | 403) {
                        self.cool(&account, generation, self.policy.cooldown, true)
                            .await;
                        last = failure("auth", "账号认证失败，请更新 token。 ");
                        continue;
                    }
                    if status.as_u16() == 429 {
                        let delay = response
                            .headers()
                            .get("retry-after")
                            .and_then(|h| h.to_str().ok())
                            .and_then(|s| s.parse::<u64>().ok())
                            .map(Duration::from_secs)
                            .unwrap_or(self.policy.cooldown);
                        self.cool(&account, generation, delay, false).await;
                        last = Failure {
                            kind: "rate_limited",
                            message: "大神暂时限制了请求频率；请稍后重试。".into(),
                            retry_after_ms: Some(delay.as_millis()),
                        };
                        continue;
                    }
                    if status.is_server_error() {
                        last = failure("upstream", "大神服务暂时不可用，请稍后重试。 ");
                    } else if !status.is_success() {
                        return Err(failure(
                            "upstream",
                            "上游拒绝了请求，请检查玩家和筛选条件。",
                        ));
                    } else {
                        let mut bytes = Vec::new();
                        while let Some(chunk) = response
                            .chunk()
                            .await
                            .map_err(|_| failure("network", "读取响应失败。"))?
                        {
                            if bytes.len() + chunk.len() > 8 * 1024 * 1024 {
                                return Err(failure("response", "上游响应过大。"));
                            }
                            bytes.extend_from_slice(&chunk);
                        }
                        let value: Value = serde_json::from_slice(&bytes)
                            .map_err(|_| failure("response", "上游返回了无法读取的数据。"))?;
                        if value.get("success") == Some(&json!(false))
                            || value.get("ok") == Some(&json!(false))
                            || value.get("code").is_some_and(|c| c != &json!(0))
                        {
                            return Err(failure(
                                "business",
                                "大神未返回有效数据；玩家可能不存在、资料私密或授权已失效。",
                            ));
                        }
                        return Ok(value);
                    }
                }
            }
            if attempt < self.policy.max_attempts {
                tokio::time::sleep(Duration::from_millis(250 * 2u64.pow(attempt - 1))).await;
            }
        }
        Err(last)
    }
}
pub fn now_ms() -> u128 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis()
}
