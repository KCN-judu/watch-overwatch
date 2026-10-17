//! Orchestrates upstream calls into a complete [`PlayerDataset`]. Transport,
//! caching and credentials stay behind [`Fetcher`]; this module only decides
//! what to ask for and records how complete the answer is.
use crate::dashen::{Endpoint, Mode, normalize};
use crate::ir::*;
use crate::progress::{Progress, report};
use crate::{Catalog, Failure};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::collections::{BTreeMap, HashSet};
use std::future::Future;
use std::sync::Arc;

pub struct Fetched {
    /// Full response envelope.
    pub value: Value,
    pub cached: bool,
}

pub trait Fetcher {
    fn fetch(
        &self,
        endpoint: Endpoint,
        payload: Value,
    ) -> impl Future<Output = Result<Fetched, Failure>> + Send;
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct CollectPlan {
    pub modes: Vec<Mode>,
    /// Season for match lists and the primary career snapshot; `None` is current.
    pub season: Option<u32>,
    /// Additional seasons to snapshot careers for (trend analysis).
    pub career_seasons: Vec<u32>,
    pub max_pages: u32,
    /// Newest matches to fetch full details for.
    pub max_details: usize,
    /// When set, details are chosen per role instead: up to this many of the newest
    /// matches the subject played on each of tank / damage / support (fewer when the
    /// player has fewer). Paging continues, up to `max_pages`, until every role has
    /// enough or the history is exhausted. `max_details` is ignored.
    pub details_per_role: Option<usize>,
    pub hero_board: bool,
    /// Look up each detail participant's competitive career rank (one request per
    /// player, two when the role they played needs a previous-season fallback).
    /// Needed for lobby strength outside competitive, where details carry no ranks.
    pub lobby_ratings: bool,
    pub max_rated_players: usize,
    /// Optional live progress sink; never serialised.
    #[serde(skip)]
    pub progress: Option<Arc<Progress>>,
}

impl Default for CollectPlan {
    fn default() -> Self {
        Self {
            modes: vec![Mode::Competitive, Mode::Quick],
            season: None,
            career_seasons: Vec::new(),
            max_pages: 5,
            max_details: 20,
            details_per_role: None,
            hero_board: true,
            lobby_ratings: false,
            max_rated_players: 60,
            progress: None,
        }
    }
}

impl CollectPlan {
    pub fn validate(&self) -> Result<(), Failure> {
        let season_ok = |s: u32| (1..=100).contains(&s);
        if self.modes.is_empty()
            || !(1..=20).contains(&self.max_pages)
            || self.max_details > 100
            || self
                .details_per_role
                .is_some_and(|n| !(1..=50).contains(&n))
            || self.max_rated_players > 600
            || self.career_seasons.len() > 11
            || self.season.is_some_and(|s| !season_ok(s))
            || !self.career_seasons.iter().all(|s| season_ok(*s))
        {
            return Err(failure(
                "validation",
                "采集范围无效：至少一个模式，1-20 页，最多 100 场详情，最多 11 个赛季。",
            ));
        }
        Ok(())
    }
}

fn failure(kind: &'static str, message: &str) -> Failure {
    Failure {
        kind,
        message: message.into(),
        retry_after_ms: None,
    }
}

fn record(
    endpoint: Endpoint,
    mode: Option<Mode>,
    season: Option<u32>,
    page: Option<u32>,
    match_id: Option<&str>,
    result: &Result<Fetched, Failure>,
) -> FetchRecord {
    FetchRecord {
        endpoint: endpoint.path().into(),
        mode,
        season,
        page,
        match_id: match_id.map(String::from),
        ok: result.is_ok(),
        cached: result.as_ref().is_ok_and(|f| f.cached),
        error_kind: result.as_ref().err().map(|e| e.kind.to_string()),
    }
}

fn with_season(mut payload: Value, season: Option<u32>) -> Value {
    if let Some(season) = season {
        payload["season"] = json!(season);
    }
    payload
}

pub fn career_payload(token: &str, mode: Mode, season: Option<u32>) -> Value {
    with_season(
        json!({"token":token,"gameMode":mode.provider_value()}),
        season,
    )
}
pub fn match_list_payload(token: &str, mode: Mode, season: Option<u32>, page: u32) -> Value {
    with_season(
        json!({"token":token,"gameMode":mode.provider_value(),"page":page}),
        season,
    )
}
pub fn match_info_payload(token: &str, match_id: &str) -> Value {
    json!({"token":token,"matchId":match_id})
}

pub struct MatchPages {
    pub matches: Vec<MatchSummary>,
    pub coverage: ListCoverage,
    pub fetches: Vec<FetchRecord>,
    /// Set when a page failed; earlier pages are still returned.
    pub error: Option<Failure>,
}

/// Pages through one mode's match list. Stops at an empty page, a page that adds
/// no new match ids (the provider repeats its last page), or `max_pages`.
pub async fn match_pages<F: Fetcher>(
    f: &F,
    cat: &Catalog,
    token: &str,
    mode: Mode,
    season: Option<u32>,
    max_pages: u32,
) -> MatchPages {
    let scope = PageScope {
        token,
        mode,
        season,
        max_pages,
    };
    match_pages_until(f, cat, &scope, |_| false, None).await
}

/// True once each playable role has at least `n` matches.
pub fn role_quota_met(matches: &[MatchSummary], n: usize) -> bool {
    Role::PLAYABLE
        .iter()
        .all(|r| matches.iter().filter(|m| m.role == *r).count() >= n)
}

/// Indices of the newest `n` matches per playable role, in list order. `matches`
/// must already be newest first. Matches with no known role are not chosen.
pub fn select_per_role(matches: &[MatchSummary], n: usize) -> Vec<usize> {
    let mut taken = [0usize; 3];
    let mut out = Vec::new();
    for (i, m) in matches.iter().enumerate() {
        if let Some(slot) = Role::PLAYABLE.iter().position(|r| *r == m.role)
            && taken[slot] < n
        {
            taken[slot] += 1;
            out.push(i);
        }
    }
    out
}

/// Which match list to page through.
#[derive(Clone, Copy)]
pub struct PageScope<'a> {
    pub token: &'a str,
    pub mode: Mode,
    pub season: Option<u32>,
    pub max_pages: u32,
}

/// Like [`match_pages`], but also stops as soon as `enough` is satisfied by the
/// matches read so far.
pub async fn match_pages_until<F: Fetcher>(
    f: &F,
    cat: &Catalog,
    scope: &PageScope<'_>,
    enough: impl Fn(&[MatchSummary]) -> bool,
    progress: Option<&Progress>,
) -> MatchPages {
    let PageScope {
        token,
        mode,
        season,
        max_pages,
    } = *scope;
    let mut out = MatchPages {
        matches: Vec::new(),
        coverage: ListCoverage {
            mode,
            season,
            pages_fetched: 0,
            exhausted: false,
        },
        fetches: Vec::new(),
        error: None,
    };
    let mut seen = HashSet::new();
    for page in 1..=max_pages {
        let endpoint = mode.match_list();
        let result = f
            .fetch(endpoint, match_list_payload(token, mode, season, page))
            .await;
        out.fetches.push(record(
            endpoint,
            Some(mode),
            season,
            Some(page),
            None,
            &result,
        ));
        report(progress, |s| {
            s.phase = "list".into();
            s.done = page as usize;
            s.total = max_pages as usize;
            s.note = format!("第 {page} 页");
            s.requests += 1;
            if result.is_err() {
                s.failures += 1;
            }
        });
        let value = match result {
            Ok(v) => v.value,
            Err(e) => {
                out.error = Some(e);
                break;
            }
        };
        out.coverage.pages_fetched = page;
        let rows = normalize::match_list(normalize::payload(&value), mode, cat);
        let before = out.matches.len();
        out.matches.extend(
            rows.into_iter()
                .filter(|m| !m.id.is_empty() && seen.insert(m.id.clone())),
        );
        report(progress, |s| s.matches_found = out.matches.len());
        if out.matches.len() == before {
            out.coverage.exhausted = true;
            break;
        }
        if enough(&out.matches) {
            break;
        }
    }
    out
}

/// Collects the player's card, careers, match lists, newest match details and
/// hero board. Individual failures are recorded in `coverage` instead of aborting.
pub async fn collect_player<F: Fetcher>(
    f: &F,
    cat: &Catalog,
    token: &str,
    identity: &Value,
    plan: &CollectPlan,
) -> PlayerDataset {
    let mut fetches = Vec::new();
    let mut profile = normalize::profile(identity);

    let result = f.fetch(Endpoint::Card, json!({"token":token})).await;
    fetches.push(record(Endpoint::Card, None, None, None, None, &result));
    if let Ok(card) = &result {
        normalize::merge_profile(
            &mut profile,
            normalize::profile(normalize::payload(&card.value)),
        );
    }

    let mut seasons = vec![plan.season];
    for s in &plan.career_seasons {
        if !seasons.contains(&Some(*s)) {
            seasons.push(Some(*s));
        }
    }
    let mut careers = Vec::new();
    for &mode in &plan.modes {
        for &season in &seasons {
            let endpoint = mode.career();
            let result = f.fetch(endpoint, career_payload(token, mode, season)).await;
            fetches.push(record(endpoint, Some(mode), season, None, None, &result));
            if let Ok(v) = result {
                careers.push(normalize::career(
                    normalize::payload(&v.value),
                    mode,
                    season,
                    cat,
                ));
            }
        }
    }

    let mut match_lists = Vec::new();
    let mut matches = Vec::new();
    let mut seen = HashSet::new();
    for &mode in &plan.modes {
        let quota = plan.details_per_role;
        let scope = PageScope {
            token,
            mode,
            season: plan.season,
            max_pages: plan.max_pages,
        };
        let pages = match_pages_until(
            f,
            cat,
            &scope,
            |read| quota.is_some_and(|n| role_quota_met(read, n)),
            plan.progress.as_deref(),
        )
        .await;
        fetches.extend(pages.fetches);
        match_lists.push(pages.coverage);
        matches.extend(
            pages
                .matches
                .into_iter()
                .filter(|m| seen.insert(m.id.clone())),
        );
    }
    matches.sort_by_key(|m| std::cmp::Reverse(m.started_at_ms));

    let mut details = BTreeMap::new();
    // bnet_id → (token, name, roles played without an in-match rank). Memory only.
    let mut unrated: Vec<(String, String, Option<String>, Vec<Role>)> = Vec::new();
    let chosen: Vec<usize> = match plan.details_per_role {
        Some(n) => select_per_role(&matches, n),
        None => (0..matches.len().min(plan.max_details)).collect(),
    };
    let wanted = chosen.len();
    report(plan.progress.as_deref(), |s| {
        s.phase = "details".into();
        s.done = 0;
        s.total = wanted;
        s.note.clear();
        s.matches_found = matches.len();
    });
    for m in chosen.iter().map(|&i| &matches[i]) {
        let endpoint = m.kind.mode.match_info();
        let result = f.fetch(endpoint, match_info_payload(token, &m.id)).await;
        report(plan.progress.as_deref(), |s| {
            s.done += 1;
            s.requests += 1;
            if result.is_err() {
                s.failures += 1;
            }
            s.note = m
                .map
                .as_ref()
                .and_then(|e| e.name.clone())
                .unwrap_or_default();
        });
        fetches.push(record(
            endpoint,
            Some(m.kind.mode),
            None,
            None,
            Some(&m.id),
            &result,
        ));
        if let Ok(v) = result {
            let mut detail = normalize::match_detail(
                &m.id,
                normalize::payload(&v.value),
                m.kind.mode,
                profile.bnet_id.as_deref(),
                cat,
            );
            detail.started_at_ms = detail.started_at_ms.or(m.started_at_ms);
            if plan.lobby_ratings {
                let tokens = normalize::participant_tokens(normalize::payload(&v.value));
                for p in detail.allies.iter().chain(&detail.enemies) {
                    let Some(id) = p.bnet_id.as_deref() else {
                        continue;
                    };
                    if p.rank.as_ref().is_some_and(|r| r.skill_rating.is_some())
                        || p.role == Role::Unknown
                    {
                        continue;
                    }
                    match unrated.iter_mut().find(|u| u.0 == id) {
                        Some(u) if !u.3.contains(&p.role) => u.3.push(p.role),
                        Some(_) => {}
                        None => {
                            if let Some((_, token, name)) = tokens.iter().find(|t| t.0 == id) {
                                unrated.push((
                                    id.into(),
                                    token.clone(),
                                    name.clone(),
                                    vec![p.role],
                                ));
                            }
                        }
                    }
                }
            }
            details.insert(m.id.clone(), detail);
        }
    }

    let mut player_ratings = Vec::new();
    let previous = cat.current_season.checked_sub(1).filter(|s| *s > 0);
    let to_rate = unrated.len().min(plan.max_rated_players);
    report(plan.progress.as_deref(), |s| {
        s.phase = "ratings".into();
        s.done = 0;
        s.total = to_rate;
        s.note.clear();
    });
    for (bnet_id, player_token, name, roles) in unrated.into_iter().take(plan.max_rated_players) {
        report(plan.progress.as_deref(), |s| {
            s.done += 1;
            s.note = name.clone().unwrap_or_default();
        });
        let mut ratings = Vec::new();
        // Current season first; the previous season only fills roles still unrated.
        for season in std::iter::once(None).chain(previous.map(Some)) {
            if roles
                .iter()
                .all(|r| ratings.iter().any(|x: &RoleRating| x.role == *r))
            {
                break;
            }
            let endpoint = Mode::Competitive.career();
            let result = f
                .fetch(
                    endpoint,
                    career_payload(&player_token, Mode::Competitive, season),
                )
                .await;
            fetches.push(record(
                endpoint,
                Some(Mode::Competitive),
                season,
                None,
                None,
                &result,
            ));
            report(plan.progress.as_deref(), |s| {
                s.requests += 1;
                if result.is_err() {
                    s.failures += 1;
                }
            });
            if let Ok(v) = result {
                for r in normalize::role_ratings(normalize::payload(&v.value), season) {
                    if !ratings.iter().any(|x: &RoleRating| x.role == r.role) {
                        ratings.push(r);
                    }
                }
            }
        }
        player_ratings.push(PlayerRating {
            bnet_id,
            name,
            roles: ratings,
        });
    }

    let mut hero_boards = Vec::new();
    if plan.hero_board {
        let result = f
            .fetch(Endpoint::PlayerHeroBoard, json!({"token":token}))
            .await;
        fetches.push(record(
            Endpoint::PlayerHeroBoard,
            None,
            None,
            None,
            None,
            &result,
        ));
        if let Ok(v) = result {
            hero_boards = normalize::player_hero_board(normalize::payload(&v.value), cat);
        }
    }

    PlayerDataset {
        ir_version: IR_VERSION.into(),
        provider: "netease_dashen".into(),
        generated_at_ms: crate::now_ms() as i64,
        profile,
        careers,
        matches,
        coverage: Coverage {
            match_lists,
            details_requested: wanted,
            details_ok: details.len(),
            fetches,
        },
        details,
        hero_boards,
        player_ratings,
    }
}

/// Direct, uncached transport (CLI and tests). The service wraps its session cache instead.
impl Fetcher for crate::WatchClient {
    async fn fetch(&self, endpoint: Endpoint, payload: Value) -> Result<Fetched, Failure> {
        let (_, value) = self
            .request(crate::RequestSpec::new(endpoint, payload))
            .await?;
        Ok(Fetched {
            value,
            cached: false,
        })
    }
}

/// Normalizes a BattleTag as typed by a user (full-width `＃`, surrounding spaces).
pub fn normalize_battletag(name: &str) -> Option<String> {
    let name = name.trim().replace('＃', "#");
    (!name.is_empty() && name.len() <= 128 && !name.chars().any(char::is_control)).then_some(name)
}

/// Resolves a BattleTag to the player's `customerToken` and the raw identity
/// payload. The token is returned separately so callers can keep it out of
/// anything they persist or display.
pub async fn search_player<F: Fetcher>(f: &F, name: &str) -> Result<(String, Value), Failure> {
    let name = normalize_battletag(name)
        .ok_or_else(|| failure("validation", "请输入战网昵称，例如 Player#12345。"))?;
    let fetched = f
        .fetch(Endpoint::SearchAccount, json!({"name":name}))
        .await?;
    let identity = normalize::payload(&fetched.value).clone();
    let token = identity
        .get("customerToken")
        .and_then(Value::as_str)
        .filter(|t| !t.is_empty())
        .map(String::from)
        .ok_or_else(|| {
            failure(
                "business",
                "未找到玩家，或上游没有返回玩家授权。请使用完整 BattleTag。",
            )
        })?;
    Ok((token, identity))
}
