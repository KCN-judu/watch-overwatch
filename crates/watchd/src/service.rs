//! Player HTTP handlers. Thin adapters: sessions and caching live here; fetching
//! plans, normalization, analysis and export shapes live in `watch_core`.
use super::{AppState, fail};
use axum::{
    Json,
    extract::State,
    response::{IntoResponse, Response},
};
use serde::Deserialize;
use serde_json::{Map, Value, json};
use std::{
    collections::{BTreeMap, HashMap},
    sync::Arc,
    time::{Duration, Instant},
};
use tokio::sync::Mutex;
use watch_core::{
    Completeness, ExportSource, Failure, ListKey, RequestMetric, RequestSpec, StrengthCache as _,
    WatchClient,
    analysis::{self, AnalysisOptions, Clock, Window},
    collect::{self, CollectPlan, Fetched, Fetcher},
    dashen::{Endpoint, Mode, normalize},
    growth,
    ir::{MatchDetail, MatchSummary},
    summarize, views,
};

type QueryCache = Mutex<HashMap<String, (Instant, RequestMetric, Value)>>;

const SESSION_TTL: Duration = Duration::from_secs(3600);
/// Pages read by multi-page views (summary, sameplay).
const PAGE_LIMIT: u32 = 5;

pub(crate) struct PlayerSession {
    token: String,
    pub identity: Value,
    created: Instant,
    cache: Arc<QueryCache>,
}

fn error(kind: &'static str, message: &str) -> Failure {
    Failure {
        kind,
        message: message.into(),
        retry_after_ms: None,
    }
}

pub(crate) fn redact(mut value: Value) -> Value {
    value = watch_core::sanitize(value);
    match &mut value {
        Value::Object(object) => {
            object.retain(|key, _| {
                !matches!(
                    key.to_ascii_lowercase().as_str(),
                    "token"
                        | "customertoken"
                        | "customer_token"
                        | "traceid"
                        | "cookie"
                        | "authorization"
                )
            });
            for v in object.values_mut() {
                *v = redact(v.take());
            }
        }
        Value::Array(array) => {
            for v in array {
                *v = redact(v.take());
            }
        }
        _ => {}
    }
    value
}

/// Upstream access through one player's short-lived cache.
struct SessionFetcher<'a> {
    client: &'a WatchClient,
    cache: &'a QueryCache,
    fresh: bool,
}

impl Fetcher for SessionFetcher<'_> {
    async fn fetch(&self, endpoint: Endpoint, payload: Value) -> Result<Fetched, Failure> {
        let (_, value, cached) = cached_request(
            self.client,
            self.cache,
            RequestSpec::new(endpoint, payload),
            self.fresh,
        )
        .await?;
        Ok(Fetched { value, cached })
    }
}

struct Session {
    token: String,
    identity: Value,
    cache: Arc<QueryCache>,
}

async fn session(s: &AppState, id: &str, expired: &str) -> Result<Session, Failure> {
    let sessions = s.sessions.lock().await;
    sessions
        .get(id)
        .filter(|p| p.created.elapsed() < SESSION_TTL)
        .map(|p| Session {
            token: p.token.clone(),
            identity: p.identity.clone(),
            cache: p.cache.clone(),
        })
        .ok_or_else(|| error("validation", expired))
}

#[derive(Deserialize)]
pub(crate) struct SearchInput {
    name: String,
}

pub(crate) async fn search_player(
    State(s): State<AppState>,
    Json(input): Json<SearchInput>,
) -> Response {
    let (token, identity) = match collect::search_player(s.client.as_ref(), &input.name).await {
        Ok(found) => found,
        Err(e) => return fail(e).into_response(),
    };
    let id = uuid::Uuid::new_v4().to_string();
    let mut sessions = s.sessions.lock().await;
    sessions.retain(|_, session| session.created.elapsed() < SESSION_TTL);
    if sessions.len() >= 100
        && let Some(oldest) = sessions
            .iter()
            .min_by_key(|(_, p)| p.created)
            .map(|(id, _)| id.clone())
    {
        sessions.remove(&oldest);
    }
    let identity = redact(identity);
    // Remember who this name is, so its stored matches can be shown at once next time.
    if let (Some(store), Some(bnet_id)) = (&s.store, subject_id(&identity)) {
        let canonical = identity["name"].as_str().unwrap_or_default();
        store.remember_player(&[input.name.trim(), canonical], &bnet_id);
    }
    sessions.insert(
        id.clone(),
        PlayerSession {
            token,
            identity: identity.clone(),
            created: Instant::now(),
            cache: Arc::new(Mutex::new(HashMap::new())),
        },
    );
    Json(json!({"session":id,"identity":identity})).into_response()
}

#[derive(Deserialize)]
pub(crate) struct ViewInput {
    session: String,
    view: String,
    #[serde(default = "sport")]
    mode: String,
    season: Option<u32>,
    #[serde(default = "page_one")]
    page: u32,
    match_id: Option<String>,
    start_season: Option<u32>,
    #[serde(default)]
    fresh: bool,
    #[serde(default = "recent_scope")]
    scope: String,
    second_session: Option<String>,
    #[serde(default)]
    technical: bool,
    #[serde(default = "default_include_teammates")]
    include_teammates: bool,
}
fn default_include_teammates() -> bool {
    true
}
fn recent_scope() -> String {
    "recent".into()
}
fn sport() -> String {
    "sport".into()
}
fn page_one() -> u32 {
    1
}

/// A loaded player view: IR plus the redacted provider payload the UI still reads.
struct ViewResult {
    identity: Value,
    /// Redacted, catalog-enriched provider payload (legacy UI input).
    data: Option<Value>,
    matches: Vec<MatchSummary>,
    /// Typed IR for this view.
    ir: Value,
    /// View-specific fields (`metric`, `cached`, `complete`, `scope`, …).
    extra: Map<String, Value>,
}

impl ViewResult {
    fn new(identity: Value) -> Self {
        Self {
            identity,
            data: None,
            matches: Vec::new(),
            ir: Value::Null,
            extra: Map::new(),
        }
    }
    fn into_json(self) -> Value {
        let mut out = self.extra;
        out.insert("identity".into(), self.identity);
        if let Some(data) = self.data {
            out.insert("data".into(), data);
        }
        out.insert("summary".into(), json!(summarize(&self.matches)));
        out.insert("matches".into(), json!(views(&self.matches)));
        out.insert("ir".into(), self.ir);
        Value::Object(out)
    }
}

pub(crate) async fn player_view(
    State(s): State<AppState>,
    Json(input): Json<ViewInput>,
) -> Response {
    match tokio::time::timeout(Duration::from_secs(45), load_view(&s, &input)).await {
        Ok(Ok(view)) => Json(view.into_json()).into_response(),
        Ok(Err(e)) => fail(e).into_response(),
        Err(_) => fail(error(
            "timeout",
            "完整查询超过 45 秒，请缩小赛季范围后重试。 ",
        ))
        .into_response(),
    }
}

fn ui_payload(s: &AppState, value: &Value) -> Value {
    let mut data = redact(normalize::payload(value).clone());
    s.catalog.enrich(&mut data);
    data
}

async fn load_view(s: &AppState, input: &ViewInput) -> Result<ViewResult, Failure> {
    let mode = Mode::parse(&input.mode)
        .filter(|_| (1..=100).contains(&input.page))
        .filter(|_| input.season.is_none_or(|n| (1..=100).contains(&n)))
        .ok_or_else(|| error("validation", "无效的赛季、模式或页码。 "))?;
    let player = session(s, &input.session, "玩家会话已过期，请重新查找玩家。 ").await?;
    let token = player.token.as_str();
    let fetcher = SessionFetcher {
        client: &s.client,
        cache: &player.cache,
        fresh: input.fresh,
    };
    let mut view = ViewResult::new(player.identity.clone());
    let (endpoint, payload) = match input.view.as_str() {
        "profile" => (
            mode.career(),
            collect::career_payload(token, mode, input.season),
        ),
        "matches" => (
            mode.match_list(),
            collect::match_list_payload(token, mode, input.season, input.page),
        ),
        "detail" => {
            let id = input
                .match_id
                .as_deref()
                .filter(|id| !id.is_empty() && id.len() < 128)
                .ok_or_else(|| error("validation", "先从列表中选择一场对局。 "))?;
            (mode.match_info(), collect::match_info_payload(token, id))
        }
        "card" => (Endpoint::Card, json!({"token":token})),
        "heroes" => (Endpoint::PlayerHeroBoard, json!({"token":token})),
        "summary" => return summary_view(s, &fetcher, token, mode, input, view).await,
        "sameplay" => return sameplay_view(s, &fetcher, token, mode, input, view).await,
        "history" => return history_view(s, token, mode, input, view).await,
        _ => return Err(error("validation", "未知的玩家视图。 ")),
    };
    // A finished match never changes: one kept locally is not asked for again. The detail
    // comes back at once with the ranks that are already known, and `ratings_pending` says
    // whether the players' ranks are still to be looked up (`/api/player/prepare` with this
    // match's id does that), so the table can be shown first and filled in afterwards.
    if input.view == "detail"
        && !input.fresh
        && let (Some(store), Some(subject), Some(id)) = (
            s.store.as_ref(),
            subject_id(&player.identity),
            input.match_id.as_deref(),
        )
        && let Some(kept) = store.detail(mode, id, &subject)
    {
        let current = s.catalog.current_season;
        let rate = mode != Mode::Stadium;
        let mut detail = kept.detail;
        if rate {
            collect::attach_career_ranks(&mut detail, store.as_ref(), current);
        }
        analysis::attach_fleta(&mut detail);
        view.ir = json!(detail);
        view.extra.insert("cached".into(), json!(true));
        view.extra.insert(
            "ratings_pending".into(),
            json!(rate && !collect::match_prepared(store.as_ref(), mode, id, &subject, current)),
        );
        return Ok(view);
    }
    let (metric, value, cached) = cached_request(
        &s.client,
        &player.cache,
        RequestSpec::new(endpoint, payload),
        input.fresh,
    )
    .await?;
    let raw = normalize::payload(&value);
    let cat = &s.catalog;
    view.matches = normalize::match_list(raw, mode, cat);
    view.ir = match input.view.as_str() {
        "profile" => json!(normalize::career(raw, mode, input.season, cat)),
        "detail" => {
            let subject = subject_id(&player.identity);
            let detail = normalize::match_detail(
                input.match_id.as_deref().unwrap_or_default(),
                raw,
                mode,
                subject.as_deref(),
                cat,
            );
            // Keep it for next time; what an earlier analysis recorded about players who
            // could not be looked up is kept as it was.
            let mut shown = detail.clone();
            analysis::attach_fleta(&mut shown);
            if let (Some(cache), Some(subject)) = (&s.store, subject.as_deref()) {
                let unreachable = cache
                    .detail(mode, &detail.id, subject)
                    .map(|k| k.unreachable)
                    .unwrap_or_default();
                cache.put_detail(subject, &detail, &unreachable);
                if mode != Mode::Stadium {
                    let current = s.catalog.current_season;
                    collect::attach_career_ranks(&mut shown, cache.as_ref(), current);
                    view.extra.insert(
                        "ratings_pending".into(),
                        json!(!collect::match_prepared(
                            cache.as_ref(),
                            mode,
                            &detail.id,
                            subject,
                            current
                        )),
                    );
                }
            }
            json!(shown)
        }
        "card" => json!(normalize::profile(raw)),
        "heroes" => json!(normalize::player_hero_board(raw, cat)),
        _ => json!(view.matches),
    };
    view.data = Some(ui_payload(s, &value));
    view.extra.insert("metric".into(), json!(metric));
    view.extra.insert("cached".into(), json!(cached));
    Ok(view)
}

async fn summary_view(
    s: &AppState,
    f: &SessionFetcher<'_>,
    token: &str,
    mode: Mode,
    input: &ViewInput,
    mut view: ViewResult,
) -> Result<ViewResult, Failure> {
    let window =
        Window::parse(&input.scope).ok_or_else(|| error("validation", "未知的复盘时间范围。 "))?;
    let pages = collect::match_pages(f, &s.catalog, token, mode, input.season, PAGE_LIMIT).await;
    if let Some(e) = pages.error {
        return Err(e);
    }
    let mut rows = pages.matches;
    rows.sort_by_key(|r| std::cmp::Reverse(r.started_at_ms));
    let clock = Clock::now(analysis::REPORT_UTC_OFFSET_MINUTES);
    view.matches = analysis::in_window(&rows, window, clock);
    view.ir = json!(view.matches);
    view.extra
        .insert("complete".into(), json!(pages.coverage.exhausted));
    view.extra.insert("scope".into(), json!(input.scope));
    view.extra
        .insert("timezone".into(), json!(analysis::REPORT_TIMEZONE));
    view.extra.insert("page_limit".into(), json!(PAGE_LIMIT));
    Ok(view)
}

async fn sameplay_view(
    s: &AppState,
    f: &SessionFetcher<'_>,
    token: &str,
    mode: Mode,
    input: &ViewInput,
    mut view: ViewResult,
) -> Result<ViewResult, Failure> {
    let second = input
        .second_session
        .as_deref()
        .ok_or_else(|| error("validation", "请选择第二名玩家。 "))?;
    let other = session(s, second, "第二名玩家会话已过期。 ").await?;
    let other_fetcher = SessionFetcher {
        client: &s.client,
        cache: &other.cache,
        fresh: input.fresh,
    };
    let mine = collect::match_pages(f, &s.catalog, token, mode, input.season, PAGE_LIMIT).await;
    let theirs = collect::match_pages(
        &other_fetcher,
        &s.catalog,
        &other.token,
        mode,
        input.season,
        PAGE_LIMIT,
    )
    .await;
    if let Some(e) = mine.error.or(theirs.error) {
        return Err(e);
    }
    view.matches = analysis::common_matches(&mine.matches, &theirs.matches);
    view.ir = json!(view.matches);
    view.extra.insert(
        "complete".into(),
        json!(mine.coverage.exhausted && theirs.coverage.exhausted),
    );
    view.extra.insert("page_limit".into(), json!(PAGE_LIMIT));
    view.extra
        .insert("method".into(), json!("match_id_intersection"));
    view.extra.insert("scope".into(), json!("recent"));
    Ok(view)
}

async fn history_view(
    s: &AppState,
    token: &str,
    mode: Mode,
    input: &ViewInput,
    mut view: ViewResult,
) -> Result<ViewResult, Failure> {
    let end = input.season.unwrap_or(s.catalog.current_season);
    let start = input.start_season.unwrap_or(end.saturating_sub(4).max(1));
    if start == 0 || start > end || end - start > 10 {
        return Err(error("validation", "一次查询最多 11 个赛季。 "));
    }
    // Sequential bounded history; every missing season has an explicit error.
    let mut seasons = Vec::new();
    let mut careers = Vec::new();
    for season in start..=end {
        let result = s
            .client
            .request(RequestSpec::new(
                mode.career(),
                collect::career_payload(token, mode, Some(season)),
            ))
            .await;
        match result {
            Ok((metric, value)) => {
                careers.push(normalize::career(
                    normalize::payload(&value),
                    mode,
                    Some(season),
                    &s.catalog,
                ));
                seasons.push(json!({"season":season,"data":redact(normalize::payload(&value).clone()),"metric":metric}));
            }
            Err(e) => seasons.push(json!({"season":season,"error":e})),
        }
    }
    view.ir = json!({"careers":careers,"trend":analysis::season_trend(&careers)});
    view.extra.insert("seasons".into(), Value::Array(seasons));
    Ok(view)
}

/// Fetches details for up to `limit` matches; failures are skipped.
async fn details_for(
    f: &SessionFetcher<'_>,
    s: &AppState,
    token: &str,
    subject: Option<&str>,
    matches: &[MatchSummary],
    limit: usize,
) -> BTreeMap<String, MatchDetail> {
    let mut details = BTreeMap::new();
    for m in matches.iter().filter(|m| !m.id.is_empty()).take(limit) {
        let endpoint = m.kind.mode.match_info();
        if let Ok(v) = f
            .fetch(endpoint, collect::match_info_payload(token, &m.id))
            .await
        {
            details.insert(
                m.id.clone(),
                normalize::match_detail(
                    &m.id,
                    normalize::payload(&v.value),
                    m.kind.mode,
                    subject,
                    &s.catalog,
                ),
            );
        }
    }
    details
}

fn subject_id(identity: &Value) -> Option<String> {
    identity["bnetId"]
        .as_str()
        .map(String::from)
        .or_else(|| identity["bnetId"].as_u64().map(|n| n.to_string()))
}

async fn build_export(s: &AppState, input: ViewInput) -> Result<Value, Failure> {
    let query = json!({"view":input.view,"mode":input.mode,"season":input.season.unwrap_or(s.catalog.current_season),"page":input.page,"scope":input.scope,"timezone":analysis::REPORT_TIMEZONE});
    let view = tokio::time::timeout(Duration::from_secs(45), load_view(s, &input))
        .await
        .map_err(|_| error("timeout", "完整查询超过 45 秒，请缩小赛季范围后重试。 "))??;
    let details = if input.include_teammates && !view.matches.is_empty() {
        let player = session(s, &input.session, "玩家会话已过期，请重新查找玩家。 ").await?;
        let fetcher = SessionFetcher {
            client: &s.client,
            cache: &player.cache,
            fresh: false,
        };
        let subject = subject_id(&player.identity);
        details_for(
            &fetcher,
            s,
            &player.token,
            subject.as_deref(),
            &view.matches,
            20,
        )
        .await
    } else {
        BTreeMap::new()
    };
    let seasons = view.extra.get("seasons").and_then(Value::as_array);
    let complete = view.extra.get("complete") == Some(&json!(true));
    let completeness = Completeness {
        status: if complete {
            "complete"
        } else if input.view == "matches" {
            "page"
        } else if input.view == "summary" {
            "partial"
        } else {
            "provider_snapshot"
        },
        page_limit: view
            .extra
            .get("page_limit")
            .and_then(Value::as_u64)
            .map(|n| n as u32),
        cached: view.extra.get("cached").and_then(Value::as_bool),
        season_errors: seasons.map_or(0, |a| a.iter().filter(|v| v.get("error").is_some()).count()),
    };
    let provider_data = view
        .data
        .clone()
        .or_else(|| view.extra.get("seasons").cloned())
        .unwrap_or(Value::Null);
    let player_name = view.identity["name"].as_str().map(String::from);
    let document = watch_core::build_export(ExportSource {
        view: &input.view,
        query,
        player_name: player_name.as_deref(),
        matches: &view.matches,
        details: &details,
        summary: json!(summarize(&view.matches)),
        completeness,
        provider_data,
        technical: input.technical,
    });
    Ok(json!(document))
}

pub(crate) async fn export_player(
    State(s): State<AppState>,
    Json(input): Json<ViewInput>,
) -> Response {
    match build_export(&s, input).await {
        Ok(document) => Json(document).into_response(),
        Err(e) => fail(e).into_response(),
    }
}

pub(crate) async fn player_replies(
    State(s): State<AppState>,
    Json(input): Json<ViewInput>,
) -> Response {
    let document = match build_export(&s, input).await {
        Ok(document) => document,
        Err(e) => return fail(e).into_response(),
    };
    let count = document["records"]["matches"]
        .as_array()
        .map_or(0, Vec::len);
    let text = format!(
        "{} · {} 场可用记录 · {}",
        document["records"]["player_name"]
            .as_str()
            .unwrap_or("玩家"),
        count,
        document["completeness"]["status"]
            .as_str()
            .unwrap_or("provider_snapshot")
    );
    Json(json!({"schema_version":"1.1.0","replies":[{"type":"text","data":text},{"type":"image","mime_type":"image/svg+xml","data":watch_core::report_svg(&document)}],"export":document})).into_response()
}

#[derive(Deserialize)]
pub(crate) struct DatasetInput {
    session: String,
    #[serde(default)]
    plan: CollectPlan,
    #[serde(default)]
    analysis: AnalysisOptions,
    #[serde(default)]
    fresh: bool,
    /// Client-chosen id; progress of this collection can be read at `/api/progress`.
    #[serde(default)]
    progress_id: Option<String>,
}

#[derive(Deserialize)]
pub(crate) struct ProgressQuery {
    id: String,
}

/// Live progress of a collection started with a `progress_id`.
pub(crate) async fn progress(
    State(s): State<AppState>,
    axum::extract::Query(q): axum::extract::Query<ProgressQuery>,
) -> Response {
    let found = s
        .progress
        .lock()
        .ok()
        .and_then(|m| m.get(&q.id).map(|(at, p)| (*at, p.clone())));
    match found {
        Some((at, p)) => Json(json!({
            "progress": p.snapshot(),
            "elapsed_ms": at.elapsed().as_millis() as u64,
        }))
        .into_response(),
        None => axum::http::StatusCode::NOT_FOUND.into_response(),
    }
}

/// What the strength cache holds.
pub(crate) async fn cache_stats(State(s): State<AppState>) -> Response {
    Json(json!({"store": s.store.as_ref().map(|c| c.stats())})).into_response()
}

/// Empties the strength cache (the next analysis fetches everything again).
pub(crate) async fn cache_clear(State(s): State<AppState>) -> Response {
    if let Some(c) = &s.store {
        c.clear();
    }
    cache_stats(State(s)).await
}

#[derive(Deserialize)]
pub(crate) struct StoredInput {
    name: String,
    #[serde(default = "sport")]
    mode: String,
}

/// What is already stored for a name, with no request to the upstream: the matches read so
/// far and the last profile, shaped like a dataset, so the app can show something while the
/// real read is under way. `known` is false for a name never looked up.
pub(crate) async fn player_stored(
    State(s): State<AppState>,
    Json(input): Json<StoredInput>,
) -> Response {
    let (Some(mode), Some(store)) = (Mode::parse(&input.mode), s.store.as_ref()) else {
        return Json(json!({"known":false})).into_response();
    };
    let Some((bnet_id, profile)) = store.known_player(&input.name) else {
        return Json(json!({"known":false})).into_response();
    };
    let list = store.match_list(ListKey {
        subject: &bnet_id,
        mode,
        season: None,
    });
    let profile: Value = profile
        .and_then(|p| serde_json::from_str(&p).ok())
        .unwrap_or_else(|| json!({"bnet_id": bnet_id, "name": input.name.trim()}));
    let total = list.rows.len();
    Json(json!({
        "known": true,
        "dataset": {
            "generated_at_ms": 0,
            "profile": profile,
            "careers": [],
            "matches": list.rows,
            "hero_boards": [],
            "player_ratings": [],
            "coverage": {
                "match_lists": [{
                    "mode": mode,
                    "season": null,
                    "pages_fetched": 0,
                    "exhausted": list.exhausted,
                    "new_matches": 0,
                    "total_matches": total,
                }],
                "details_requested": 0,
                "details_ok": 0,
                "cache_hits": 0,
                "fetches": [],
            },
        },
    }))
    .into_response()
}

/// Looks up and stores what the lobby-strength analysis needs from `rows`: each match's
/// detail and every participant's rank. Failures only leave the match unprepared.
async fn prepare_matches(
    s: &AppState,
    player: &Session,
    mode: Mode,
    rows: Vec<MatchSummary>,
    ratings: bool,
) {
    let fetcher = SessionFetcher {
        client: &s.client,
        cache: &player.cache,
        fresh: false,
    };
    let plan = CollectPlan {
        modes: vec![mode],
        known_matches: rows,
        max_details: 0,
        hero_board: false,
        profile: false,
        lobby_ratings: ratings,
        max_rated_players: 600,
        cache: s
            .store
            .clone()
            .map(|c| c as std::sync::Arc<dyn watch_core::StrengthCache>),
        ..CollectPlan::default()
    };
    let _ = tokio::time::timeout(
        Duration::from_secs(120),
        collect::collect_player(&fetcher, &s.catalog, &player.token, &player.identity, &plan),
    )
    .await;
}

#[derive(Deserialize)]
pub(crate) struct PrepareInput {
    session: String,
    #[serde(default = "sport")]
    mode: String,
    /// How many of the newest matches to keep ready.
    #[serde(default = "prepare_window")]
    window: usize,
    /// Prepare only this match of the stored list, whatever its place in the queue.
    #[serde(default)]
    match_id: Option<String>,
    /// Also look up the players' ranks (otherwise only each match's detail is kept).
    #[serde(default = "prepare_ratings")]
    ratings: bool,
    /// How many of them to prepare in this call.
    #[serde(default = "prepare_batch")]
    batch: usize,
}

fn prepare_window() -> usize {
    30
}

fn prepare_ratings() -> bool {
    true
}

fn prepare_batch() -> usize {
    3
}

/// Prepares a small batch of the newest matches that are not ready for the strength
/// analysis yet, so the cost of looking players up is spread over every update instead of
/// landing on the analysis. Answers how many were prepared and how many are still waiting.
pub(crate) async fn player_prepare(
    State(s): State<AppState>,
    Json(input): Json<PrepareInput>,
) -> Response {
    let Some(mode) = Mode::parse(&input.mode)
        .filter(|m| *m != Mode::Stadium || !input.ratings)
        .filter(|_| (1..=5000).contains(&input.window) && (1..=10).contains(&input.batch))
    else {
        return fail(error("validation", "无效的模式或数量。 ")).into_response();
    };
    let player = match session(&s, &input.session, "玩家会话已过期，请重新查找玩家。 ").await
    {
        Ok(p) => p,
        Err(e) => return fail(e).into_response(),
    };
    let (Some(store), Some(subject)) = (s.store.clone(), subject_id(&player.identity)) else {
        return Json(json!({"prepared":0,"remaining":0,"enabled":false})).into_response();
    };
    let current = s.catalog.current_season;
    let key = ListKey {
        subject: &subject,
        mode,
        season: None,
    };
    let waiting = |store: &crate::store::LocalStore| -> Vec<MatchSummary> {
        store
            .match_list(key)
            .rows
            .into_iter()
            .take(input.window)
            .filter(|m| {
                if input.ratings {
                    !collect::match_prepared(store, mode, &m.id, &subject, current)
                } else {
                    !collect::detail_stored(store, mode, &m.id, &subject)
                }
            })
            .collect()
    };
    let batch: Vec<MatchSummary> = match input.match_id.as_deref() {
        Some(id) => store
            .match_list(key)
            .rows
            .into_iter()
            .filter(|m| m.id == id)
            .collect(),
        None => waiting(&store).into_iter().take(input.batch).collect(),
    };
    let prepared = batch.len();
    if !batch.is_empty() {
        prepare_matches(&s, &player, mode, batch, input.ratings).await;
    }
    let remaining = waiting(&store).len();
    let total = store.match_list(key).rows.len().min(input.window);
    Json(json!({"prepared":prepared,"remaining":remaining,"total":total,"enabled":true}))
        .into_response()
}

#[derive(Deserialize)]
pub(crate) struct GrowthInput {
    session: String,
    #[serde(default = "sport")]
    mode: String,
}

/// The growth measures (survival time, Fleta index, KDA) match by match and their trends
/// (see [`growth`]), from the matches whose detail is already stored on this machine: no
/// request goes to the upstream. `listed` is the matches of the stored list and `stored`
/// those with a detail, so the app can say how much of the history this covers.
pub(crate) async fn player_growth(
    State(s): State<AppState>,
    Json(input): Json<GrowthInput>,
) -> Response {
    let Some(mode) = Mode::parse(&input.mode) else {
        return fail(error("validation", "无效的模式。 ")).into_response();
    };
    let player = match session(&s, &input.session, "玩家会话已过期，请重新查找玩家。 ").await
    {
        Ok(p) => p,
        Err(e) => return fail(e).into_response(),
    };
    let (Some(store), Some(subject)) = (s.store.clone(), subject_id(&player.identity)) else {
        return Json(json!({"enabled":false})).into_response();
    };
    let rows = store
        .match_list(ListKey {
            subject: &subject,
            mode,
            season: None,
        })
        .rows;
    let details: Vec<MatchDetail> = rows
        .iter()
        .filter_map(|m| store.detail(mode, &m.id, &subject))
        .map(|kept| kept.detail)
        .collect();
    let stored = details.len();
    let report = growth::growth(&details);
    Json(json!({
        "enabled": true,
        "listed": rows.len(),
        "stored": stored,
        "report": report,
    }))
    .into_response()
}

/// Full IR dataset for one player plus its analysis.
pub(crate) async fn player_dataset(
    State(s): State<AppState>,
    Json(input): Json<DatasetInput>,
) -> Response {
    if let Err(e) = input.plan.validate() {
        return fail(e).into_response();
    }
    let player = match session(&s, &input.session, "玩家会话已过期，请重新查找玩家。 ").await
    {
        Ok(p) => p,
        Err(e) => return fail(e).into_response(),
    };
    let fetcher = SessionFetcher {
        client: &s.client,
        cache: &player.cache,
        fresh: input.fresh,
    };
    let mut plan = input.plan.clone();
    plan.cache = s
        .store
        .clone()
        .map(|c| c as std::sync::Arc<dyn watch_core::StrengthCache>);
    // "Refresh" asks the upstream for current-season ranks again, not just for pages.
    plan.refresh_ratings = input.fresh;
    let tracker = input.progress_id.as_ref().map(|id| {
        let p = std::sync::Arc::new(watch_core::Progress::default());
        if let Ok(mut m) = s.progress.lock() {
            m.retain(|_, (at, _)| at.elapsed() < Duration::from_secs(600));
            m.insert(id.clone(), (Instant::now(), p.clone()));
        }
        p
    });
    plan.progress = tracker.clone();
    let collected = tokio::time::timeout(
        Duration::from_secs(180),
        collect::collect_player(&fetcher, &s.catalog, &player.token, &player.identity, &plan),
    )
    .await;
    if let Some(p) = &tracker {
        p.update(|s| s.phase = "finish".into());
    }
    match collected {
        Ok(dataset) => {
            if input.plan.profile
                && let (Some(store), Some(id)) = (&s.store, dataset.profile.bnet_id.as_deref())
                && let Ok(json) = serde_json::to_string(&dataset.profile)
            {
                store.remember_profile(id, &json);
            }
            let analysis = analysis::analyze(&dataset, &input.analysis);
            if let Some(p) = &tracker {
                p.update(|s| s.phase = "done".into());
            }
            Json(json!({"dataset":dataset,"analysis":analysis})).into_response()
        }
        Err(_) => fail(error(
            "timeout",
            "采集超过 180 秒，请减少模式、页数或详情数量。",
        ))
        .into_response(),
    }
}

async fn cached_request(
    client: &WatchClient,
    cache: &QueryCache,
    spec: RequestSpec,
    fresh: bool,
) -> Result<(RequestMetric, Value, bool), Failure> {
    let key = format!("{}:{}", spec.endpoint, spec.payload);
    // One lock per player coalesces identical concurrent page requests. No credentials on disk.
    let mut cache = cache.lock().await;
    if !fresh
        && let Some((_, metric, data)) = cache
            .get(&key)
            .filter(|(at, _, _)| at.elapsed() < Duration::from_secs(30))
    {
        return Ok((metric.clone(), data.clone(), true));
    }
    let (metric, data) = client.request(spec).await?;
    if cache.len() >= 32
        && let Some(oldest) = cache
            .iter()
            .min_by_key(|(_, v)| v.0)
            .map(|(k, _)| k.clone())
    {
        cache.remove(&oldest);
    }
    cache.insert(key, (Instant::now(), metric.clone(), data.clone()));
    Ok((metric, data, false))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn redaction_removes_nested_secrets() {
        let v = redact(
            json!({"token":"secret","data":[{"customerToken":"player-token","name":"test","traceId":"trace"}]}),
        );
        assert_eq!(v, json!({"data":[{"name":"test"}]}));
    }
    #[tokio::test]
    async fn duplicate_views_share_one_upstream_request_and_refresh_bypasses_cache() {
        use axum::{Router, routing::get};
        use watch_core::{AccountSecret, Policy, SecretsFile};
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let base = format!("http://{}", listener.local_addr().unwrap());
        let app = Router::new().route(
            "/customer/queryCountInfo",
            get(|| async { Json(json!({"code":0,"data":{}})) }),
        );
        tokio::spawn(async move {
            axum::serve(listener, app).await.unwrap();
        });
        let client = WatchClient::with_base(
            SecretsFile {
                accounts: vec![AccountSecret {
                    name: "test".into(),
                    role_id: 1,
                    token: "test".into(),
                    dts: 2026,
                    server: 1,
                }],
            },
            &base,
            Policy::default(),
        )
        .unwrap();
        let cache = Mutex::new(HashMap::new());
        let spec = RequestSpec {
            endpoint: "customer/queryCountInfo".into(),
            payload: json!({"token":"test"}),
        };
        let (a, b) = tokio::join!(
            cached_request(&client, &cache, spec.clone(), false),
            cached_request(&client, &cache, spec.clone(), false)
        );
        assert!(!a.unwrap().2);
        assert!(b.unwrap().2);
        assert_eq!(client.metrics().await.len(), 1);
        assert!(!cached_request(&client, &cache, spec, true).await.unwrap().2);
        assert_eq!(client.metrics().await.len(), 2);
    }
}
