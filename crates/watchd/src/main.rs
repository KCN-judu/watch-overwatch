mod background;
mod cli;
mod community;
mod players;
mod service;
mod store;
mod update;
use axum::{
    Json, Router,
    extract::{Request, State},
    http::{StatusCode, header},
    middleware::{self, Next},
    response::{Html, IntoResponse, Response},
    routing::{get, post},
};
use serde::Deserialize;
use service::{PlayerSession, player_view, search_player};
use std::{collections::HashMap, sync::Arc};
use tokio::sync::Mutex;
use watch_core::{
    AccountSecret, Failure, RequestSpec, WatchClient, import_legacy, load_secrets, save_secrets,
};

/// Live progress of running collections, by the id the client chose, with when each began.
pub(crate) type ProgressBook =
    Arc<std::sync::Mutex<HashMap<String, (std::time::Instant, Arc<watch_core::Progress>)>>>;

#[derive(Clone)]
pub(crate) struct AppState {
    client: Arc<WatchClient>,
    sessions: Arc<Mutex<HashMap<String, PlayerSession>>>,
    settings_lock: Arc<Mutex<()>>,
    catalog: Arc<watch_core::Catalog>,
    /// Live progress of running collections, by the id the client chose.
    progress: ProgressBook,
    /// Finished-match details and ranks kept between analyses; `None` if it could not be opened.
    store: Option<Arc<store::LocalStore>>,
    /// Whether this run has checked for a season newer than the catalog (`follow_season`).
    season_checked: Arc<std::sync::atomic::AtomicBool>,
    /// The latest release seen and the download of it (`/api/update/*`).
    updates: update::UpdateBook,
    /// Queries running now, which the background rank job gives way to.
    foreground: Arc<background::Foreground>,
    /// The background rank-snapshot jobs (`/api/ranks/*`).
    rank_jobs: Arc<background::RankJobs>,
}
/// Opens the on-disk local store; without it everything still works, just without reuse.
pub(crate) fn open_store() -> Option<Arc<store::LocalStore>> {
    let dir = watch_core::data_dir().join("cache");
    match store::LocalStore::open(&dir) {
        Ok(c) => Some(Arc::new(c)),
        Err(e) => {
            tracing::warn!("local store unavailable ({}): {e}", dir.display());
            None
        }
    }
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let args: Vec<String> = std::env::args().collect();
    if args.get(1).map(String::as_str) == Some("import-catalog") {
        let path = args
            .get(2)
            .ok_or_else(|| anyhow::anyhow!("Usage: watchd import-catalog <query_tool.json>"))?;
        watch_core::Catalog::import(std::path::Path::new(path))?;
        println!("Imported only hero/map names and current season; account lists were excluded.");
        return Ok(());
    }
    if args.get(1).map(String::as_str) == Some("import-legacy") {
        let path = args
            .get(2)
            .ok_or_else(|| anyhow::anyhow!("Usage: watchd import-legacy <config.py>"))?;
        let count = import_legacy(std::path::Path::new(path))?;
        println!(
            "Imported {count} account(s) into the local secrets file. Token values were not printed."
        );
        return Ok(());
    }
    if args.get(1).map(String::as_str) == Some("apply-update") {
        let (Some(staged), Some(target)) = (args.get(2), args.get(3)) else {
            anyhow::bail!("Usage: watchd apply-update <staged folder> <program folder>");
        };
        return update::run_installer(std::path::Path::new(staged), std::path::Path::new(target));
    }
    if let Some(command) = args
        .get(1)
        .filter(|c| matches!(c.as_str(), "dataset" | "analyze"))
    {
        return cli::run(command, &args[2..]).await;
    }
    tracing_subscriber::fmt().with_env_filter("info").init();
    if std::env::var_os("WATCHD_EXIT_ON_STDIN_EOF").is_some() {
        // A supervising app keeps our stdin open; when it exits or crashes the
        // pipe closes and we go with it instead of lingering as an orphan.
        tokio::spawn(async {
            let mut sink = Vec::new();
            let _ = tokio::io::AsyncReadExt::read_to_end(&mut tokio::io::stdin(), &mut sink).await;
            std::process::exit(0);
        });
    }
    let client = Arc::new(WatchClient::new(load_secrets()?)?);
    let app = Router::new()
        .route("/", get(index))
        .route("/app.css", get(css))
        .route("/app.js", get(js))
        .route("/library.js", get(library_js))
        .route("/icons.js", get(icons_js))
        .route("/vendor/lucide.min.js", get(lucide_js))
        .route("/hero-portraits.json", get(hero_portraits))
        .route("/healthz", get(health))
        .route("/api/state", get(state))
        .route("/api/players", get(players::list).post(players::save))
        .route("/api/request", post(request))
        .route("/api/accounts", post(account))
        .route("/api/player/search", post(search_player))
        .route("/api/player/view", post(player_view))
        .route("/api/player/export", post(service::export_player))
        // The app sends back the match rows it already read, so this body can be larger.
        .route(
            "/api/player/dataset",
            post(service::player_dataset)
                .layer(axum::extract::DefaultBodyLimit::max(2 * 1024 * 1024)),
        )
        .route("/api/player/prepare", post(service::player_prepare))
        .route("/api/player/stored", post(service::player_stored))
        .route("/api/player/growth", post(service::player_growth))
        .route("/api/player/overview", post(service::player_overview))
        .route("/api/player/benchmark", post(service::player_benchmark))
        .route("/api/player/maps", post(service::player_maps))
        .route("/api/player/daily", post(service::player_daily))
        .route("/api/player/people", post(service::player_people))
        .route("/api/player/duo", post(service::player_duo))
        .route("/api/player/ranks", post(service::player_ranks))
        .route("/api/player/stadium", post(service::player_stadium))
        .route("/api/progress", get(service::progress))
        .route("/api/cache", get(service::cache_stats))
        .route("/api/cache/clear", post(service::cache_clear))
        .route("/api/player/replies", post(service::player_replies))
        .route("/api/catalog", get(community::catalog))
        .route("/api/community", post(community::query))
        .route("/api/ranks/start", post(background::start_handler))
        .route("/api/ranks/status", post(background::status_handler))
        .route("/api/update/check", post(update::check))
        .route("/api/update/status", post(update::status))
        .route("/api/update/download", post(update::download))
        .route("/api/update/apply", post(update::apply))
        .layer(axum::extract::DefaultBodyLimit::max(64 * 1024))
        .layer(middleware::from_fn(local_guard));
    let state = AppState {
        client,
        sessions: Arc::new(Mutex::new(HashMap::new())),
        settings_lock: Arc::new(Mutex::new(())),
        catalog: Arc::new(watch_core::Catalog::load()),
        progress: Arc::new(std::sync::Mutex::new(HashMap::new())),
        store: open_store(),
        season_checked: Arc::default(),
        updates: Arc::default(),
        foreground: Arc::default(),
        rank_jobs: Arc::default(),
    };
    tokio::spawn(background::run(state.clone()));
    let app = app
        .layer(middleware::from_fn_with_state(
            state.clone(),
            mark_foreground,
        ))
        .with_state(state);
    let listener = tokio::net::TcpListener::bind(("127.0.0.1", port())).await?;
    tracing::info!("Watch Overwatch: http://127.0.0.1:{}", port());
    axum::serve(listener, app)
        .with_graceful_shutdown(async {
            let _ = tokio::signal::ctrl_c().await;
        })
        .await?;
    Ok(())
}
/// 18180 unless `WATCHD_PORT` overrides it (development, side-by-side builds).
/// The desktop launcher always uses the default.
fn port() -> u16 {
    static PORT: std::sync::OnceLock<u16> = std::sync::OnceLock::new();
    *PORT.get_or_init(|| {
        std::env::var("WATCHD_PORT")
            .ok()
            .and_then(|p| p.parse().ok())
            .unwrap_or(18180)
    })
}
/// Marks every query the app makes as running, so the background rank job waits for it.
/// The job's own progress, the service state and update checks do not count.
async fn mark_foreground(State(s): State<AppState>, req: Request, next: Next) -> Response {
    let path = req.uri().path();
    let quiet = !path.starts_with("/api/")
        || path.starts_with("/api/ranks/")
        || path.starts_with("/api/update/")
        || matches!(path, "/api/state" | "/api/progress" | "/api/cache");
    let _busy = (!quiet).then(|| s.foreground.enter());
    next.run(req).await
}

async fn local_guard(req: Request, next: Next) -> Response {
    let host = req
        .headers()
        .get(header::HOST)
        .and_then(|h| h.to_str().ok())
        .unwrap_or("");
    let port = port();
    if host != format!("127.0.0.1:{port}") && host != format!("localhost:{port}") {
        return StatusCode::FORBIDDEN.into_response();
    }
    if req.method() != axum::http::Method::GET {
        if req
            .headers()
            .get("x-watch-client")
            .and_then(|v| v.to_str().ok())
            != Some("watch-overwatch")
        {
            return StatusCode::FORBIDDEN.into_response();
        }
        if let Some(origin) = req.headers().get(header::ORIGIN)
            && ![
                format!("http://127.0.0.1:{port}"),
                format!("http://localhost:{port}"),
            ]
            .iter()
            .any(|allowed| origin.to_str().ok() == Some(allowed.as_str()))
        {
            return StatusCode::FORBIDDEN.into_response();
        }
    }
    let mut response = next.run(req).await;
    response
        .headers_mut()
        .insert(header::CACHE_CONTROL, "no-store".parse().unwrap());
    response.headers_mut().insert(header::CONTENT_SECURITY_POLICY, "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' https:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'".parse().unwrap());
    response
        .headers_mut()
        .insert("x-content-type-options", "nosniff".parse().unwrap());
    response
}
async fn index() -> Html<&'static str> {
    Html(include_str!("../../../ui/index.html"))
}
async fn css() -> impl IntoResponse {
    (
        [(header::CONTENT_TYPE, "text/css; charset=utf-8")],
        include_str!("../../../ui/app.css"),
    )
}
async fn js() -> impl IntoResponse {
    (
        [(
            header::CONTENT_TYPE,
            "application/javascript; charset=utf-8",
        )],
        include_str!("../../../ui/app.js"),
    )
}
async fn health() -> Json<serde_json::Value> {
    Json(serde_json::json!({"ok":true,"service":"watchd","version":env!("CARGO_PKG_VERSION")}))
}
async fn library_js() -> impl IntoResponse {
    (
        [(
            header::CONTENT_TYPE,
            "application/javascript; charset=utf-8",
        )],
        include_str!("../../../ui/library.js"),
    )
}
async fn icons_js() -> impl IntoResponse {
    (
        [(header::CONTENT_TYPE, "text/javascript; charset=utf-8")],
        include_str!("../../../ui/icons.js"),
    )
}
async fn lucide_js() -> impl IntoResponse {
    (
        [(header::CONTENT_TYPE, "text/javascript; charset=utf-8")],
        include_str!("../../../ui/vendor/lucide.min.js"),
    )
}
async fn hero_portraits() -> impl IntoResponse {
    (
        [(header::CONTENT_TYPE, "application/json; charset=utf-8")],
        include_str!("../../../ui/hero-portraits.json"),
    )
}
async fn state(State(s): State<AppState>) -> Json<serde_json::Value> {
    Json(
        serde_json::json!({"accounts":s.client.account_views().await,"metrics":s.client.metrics().await,"endpoints":watch_core::endpoints(),"current_season":s.catalog.current_season.get(),"thresholds":{"group":watch_core::stats::MIN_GROUP_MATCHES,"trend":watch_core::stats::MIN_TREND_MATCHES},"secrets_path":watch_core::secrets_path().display().to_string(),"version":watch_core::update::current_version(),"demo":watch_core::DEMO_AVAILABLE}),
    )
}
pub(crate) fn fail(error: Failure) -> (StatusCode, Json<serde_json::Value>) {
    let status = match error.kind {
        "validation" => StatusCode::BAD_REQUEST,
        "busy" | "rate_limited" => StatusCode::TOO_MANY_REQUESTS,
        "timeout" => StatusCode::GATEWAY_TIMEOUT,
        "no_account" | "auth" => StatusCode::SERVICE_UNAVAILABLE,
        _ => StatusCode::BAD_GATEWAY,
    };
    (status, Json(serde_json::json!({"error":error})))
}
async fn request(State(s): State<AppState>, Json(body): Json<RequestSpec>) -> Response {
    match s.client.request(body).await {
        Ok((metric, value)) => {
            Json(serde_json::json!({"metric":metric,"data":service::redact(value)})).into_response()
        }
        Err(error) => fail(error).into_response(),
    }
}
#[derive(Deserialize)]
struct AccountInput {
    name: String,
    role_id: u64,
    token: String,
    #[serde(default)]
    remove: bool,
}
async fn account(State(s): State<AppState>, Json(body): Json<AccountInput>) -> Response {
    let _settings = s.settings_lock.lock().await;
    let result = (|| -> anyhow::Result<watch_core::SecretsFile> {
        let mut secrets = load_secrets()?;
        if body.remove {
            secrets.accounts.retain(|a| a.name != body.name);
        } else {
            let previous = secrets.accounts.iter().find(|a| a.name == body.name);
            let token = if body.token.is_empty() {
                previous.map(|a| a.token.clone()).unwrap_or_default()
            } else {
                body.token.trim().to_string()
            };
            let next = AccountSecret {
                name: body.name.trim().into(),
                role_id: body.role_id,
                token,
                dts: 2026,
                server: 1,
            };
            secrets.accounts.retain(|a| a.name != next.name);
            secrets.accounts.push(next);
        }
        save_secrets(&secrets)?;
        Ok(secrets)
    })();
    match result {
        Ok(secrets) => match s.client.replace_accounts(secrets).await {
            Ok(()) => Json(serde_json::json!({"ok":true})).into_response(),
            Err(e) => fail(e).into_response(),
        },
        Err(_) => fail(Failure {
            kind: "validation",
            message: "无法保存账号。检查名称、role_id 和 token；确认本地配置目录可写。".into(),
            retry_after_ms: None,
        })
        .into_response(),
    }
}
