//! Orchestrates upstream calls into a complete [`PlayerDataset`]. Transport,
//! caching and credentials stay behind [`Fetcher`]; this module only decides
//! what to ask for and records how complete the answer is.
use crate::cache::{CachedDetail, ListKey, StrengthCache};
use crate::dashen::{Endpoint, Mode, normalize};
use crate::ir::*;
use crate::progress::{Progress, report};
use crate::{Catalog, Failure};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::collections::{BTreeMap, HashMap, HashSet};
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
    /// Only these roles (of the roles the subject played) are analysed; empty means all
    /// three. Applies to `details_per_role`: paging and the choice of matches look at
    /// these roles only.
    pub roles: Vec<Role>,
    /// Look current-season ratings up again even if they are cached.
    pub refresh_ratings: bool,
    /// Match-list rows the caller has already read (the app's match page). When not
    /// empty, the list is not fetched again: these rows are the history to choose
    /// from, in their own words, and only their details and ratings are looked up.
    pub known_matches: Vec<MatchSummary>,
    /// With a local store, the list is only read as far as needed: new matches since the
    /// last read, then older ones until every role (of `roles`) has this many, or all of
    /// them when unset. `details_per_role` counts as this when it is unset.
    pub list_quota: Option<usize>,
    /// Keep only the newest this many matches of each mode in the dataset (all when
    /// unset): the exports a user sizes by number of matches.
    pub match_limit: Option<usize>,
    /// Read the player's card and careers too (the profile page needs them). Off for the
    /// callers that only want matches and ranks: it saves a few requests every time.
    pub profile: bool,
    /// Optional live progress sink; never serialised.
    #[serde(skip)]
    pub progress: Option<Arc<Progress>>,
    /// Optional store for finished-match details and ratings; never serialised.
    #[serde(skip)]
    pub cache: Option<Arc<dyn StrengthCache>>,
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
            roles: Vec::new(),
            refresh_ratings: false,
            known_matches: Vec::new(),
            list_quota: None,
            match_limit: None,
            profile: true,
            progress: None,
            cache: None,
        }
    }
}

impl CollectPlan {
    pub fn validate(&self) -> Result<(), Failure> {
        let season_ok = |s: u32| (1..=100).contains(&s);
        if self.modes.is_empty()
            || !(1..=20).contains(&self.max_pages)
            || self.max_details > 5000
            || self.match_limit.is_some_and(|n| !(1..=5000).contains(&n))
            || self
                .details_per_role
                .is_some_and(|n| !(1..=50).contains(&n))
            || self.max_rated_players > 5000
            || self.roles.iter().any(|r| !Role::PLAYABLE.contains(r))
            || self.known_matches.len() > 300
            || self.list_quota.is_some_and(|n| !(1..=300).contains(&n))
            || self.known_matches.iter().any(|m| m.id.is_empty())
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
    role_quota_met_for(matches, n, &Role::PLAYABLE)
}

/// True once each of `roles` has at least `n` matches.
pub fn role_quota_met_for(matches: &[MatchSummary], n: usize, roles: &[Role]) -> bool {
    roles
        .iter()
        .all(|r| matches.iter().filter(|m| m.role == *r).count() >= n)
}

/// Indices of the newest `n` matches per playable role, in list order. `matches`
/// must already be newest first. Matches with no known role are not chosen.
pub fn select_per_role(matches: &[MatchSummary], n: usize) -> Vec<usize> {
    select_per_role_for(matches, n, &Role::PLAYABLE)
}

/// Like [`select_per_role`], restricted to `roles`.
pub fn select_per_role_for(matches: &[MatchSummary], n: usize, roles: &[Role]) -> Vec<usize> {
    let mut taken = [0usize; 3];
    let mut out = Vec::new();
    for (i, m) in matches.iter().enumerate() {
        if !roles.contains(&m.role) {
            continue;
        }
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
            new_matches: 0,
            total_matches: 0,
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
        out.coverage.total_matches = out.matches.len();
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

/// What to read through the local store.
pub struct SyncScope<'a> {
    pub page: PageScope<'a>,
    /// Whose list it is (their bnet id); the key of the stored list.
    pub subject: &'a str,
    /// Stop reading older matches once every one of these roles has this many.
    pub quota: Option<(usize, &'a [Role])>,
}

/// Fetches one list page into `out`, recording the request. `None` after a failure.
async fn read_list_page<F: Fetcher>(
    f: &F,
    cat: &Catalog,
    scope: &PageScope<'_>,
    page: u32,
    out: &mut MatchPages,
    progress: Option<&Progress>,
) -> Option<Vec<MatchSummary>> {
    let endpoint = scope.mode.match_list();
    let result = f
        .fetch(
            endpoint,
            match_list_payload(scope.token, scope.mode, scope.season, page),
        )
        .await;
    out.fetches.push(record(
        endpoint,
        Some(scope.mode),
        scope.season,
        Some(page),
        None,
        &result,
    ));
    report(progress, |s| {
        s.phase = "list".into();
        s.done = page as usize;
        s.total = scope.max_pages as usize;
        s.note = format!("第 {page} 页");
        s.requests += 1;
        if result.is_err() {
            s.failures += 1;
        }
    });
    match result {
        Ok(v) => {
            out.coverage.pages_fetched += 1;
            let rows = normalize::match_list(normalize::payload(&v.value), scope.mode, cat);
            Some(rows.into_iter().filter(|m| !m.id.is_empty()).collect())
        }
        Err(e) => {
            out.error = Some(e);
            None
        }
    }
}

/// Reads a player's match list through the local store, fetching only what is missing:
///
///  1. page 1 and onward until a page holds a match already stored: those are the new
///     matches (one request when there are none);
///  2. if the store does not yet reach the player's oldest match, older pages from where
///     the store ends, until `quota` is met or the history is exhausted.
///
/// At most `max_pages` pages are fetched per call; `coverage.exhausted` says whether the
/// store is complete. Returns everything stored, newest first. What the store holds is
/// always a gap-free run from the newest match: new matches are only added once they
/// join the stored run, otherwise the store starts over from them.
pub async fn sync_match_list<F: Fetcher>(
    f: &F,
    cat: &Catalog,
    cache: &dyn StrengthCache,
    scope: &SyncScope<'_>,
    progress: Option<&Progress>,
) -> MatchPages {
    let page_scope = &scope.page;
    let key = ListKey {
        subject: scope.subject,
        mode: page_scope.mode,
        season: page_scope.season,
    };
    let max_pages = page_scope.max_pages;
    let stored = cache.match_list(key);
    let had_rows = !stored.rows.is_empty();
    let stored_rows: HashMap<String, MatchSummary> = stored
        .rows
        .iter()
        .map(|m| (m.id.clone(), m.clone()))
        .collect();
    // Rows already stored that a page just read shows differently: a row is only ever
    // written once as new, so what the upstream corrects later has to be picked up here.
    let mut updates: Vec<MatchSummary> = Vec::new();
    let mut exhausted = stored.exhausted;
    let mut rows = stored.rows;
    let mut out = MatchPages {
        matches: Vec::new(),
        coverage: ListCoverage {
            mode: page_scope.mode,
            season: page_scope.season,
            pages_fetched: 0,
            exhausted: false,
            new_matches: 0,
            total_matches: 0,
        },
        fetches: Vec::new(),
        error: None,
    };
    let quota_met = |rows: &[MatchSummary]| {
        scope
            .quota
            .is_some_and(|(n, roles)| role_quota_met_for(rows, n, roles))
    };
    let mut page_size = 0usize;
    let mut added = 0usize;

    // 1. New matches. With nothing stored this is simply reading from the top.
    let mut fresh: Vec<MatchSummary> = Vec::new();
    let mut seen: HashSet<String> = HashSet::new();
    let mut joined = false;
    let mut reached_end = false;
    for page in 1..=max_pages {
        let Some(list) = read_list_page(f, cat, page_scope, page, &mut out, progress).await else {
            break;
        };
        if page == 1 {
            page_size = list.len();
        }
        if list.is_empty() {
            reached_end = true;
            break;
        }
        let overlaps = list.iter().any(|m| stored_rows.contains_key(&m.id));
        let before = fresh.len();
        for m in list {
            match stored_rows.get(&m.id) {
                Some(old) if *old != m => updates.push(m),
                Some(_) => {}
                None => {
                    if seen.insert(m.id.clone()) {
                        fresh.push(m);
                    }
                }
            }
        }
        if !had_rows {
            // Nothing to join: persist as we go, so an interrupted read keeps its pages.
            cache.put_match_rows(key, &fresh[before..]);
            rows.extend_from_slice(&fresh[before..]);
            added += fresh.len() - before;
        }
        report(progress, |s| s.matches_found = rows.len() + fresh.len());
        if overlaps {
            joined = true;
            break;
        }
        if fresh.len() == before {
            // A page of nothing new and nothing stored: the provider repeats its last page.
            reached_end = true;
            break;
        }
        if !had_rows && quota_met(&rows) {
            break;
        }
    }
    // A page that failed before the new matches joined the stored run proves nothing about
    // where they sit, so they are dropped and the store is left as it was.
    let failed_before_joining = had_rows && !joined && out.error.is_some();
    if had_rows && !fresh.is_empty() && !failed_before_joining {
        if !joined {
            // New matches that do not reach the stored run: start over from them.
            cache.clear_match_list(key);
            rows.clear();
            exhausted = false;
        }
        cache.put_match_rows(key, &fresh);
        added += fresh.len();
        rows.extend(fresh);
    }
    if reached_end && !(had_rows && joined) && !failed_before_joining {
        exhausted = true;
    }

    // 2. Older matches, from where the store ends.
    if had_rows && joined && !exhausted && out.error.is_none() && page_size > 0 {
        let mut known: HashSet<String> = rows.iter().map(|m| m.id.clone()).collect();
        // The page that holds the first match the store does not have.
        let mut next = (rows.len() / page_size) as u32 + 1;
        while out.coverage.pages_fetched < max_pages && !quota_met(&rows) {
            let Some(list) = read_list_page(f, cat, page_scope, next, &mut out, progress).await
            else {
                break;
            };
            let mut older: Vec<MatchSummary> = Vec::new();
            for m in list {
                match stored_rows.get(&m.id) {
                    Some(old) if *old != m => updates.push(m),
                    Some(_) => {}
                    None => {
                        if known.insert(m.id.clone()) {
                            older.push(m);
                        }
                    }
                }
            }
            if older.is_empty() {
                exhausted = true;
                break;
            }
            cache.put_match_rows(key, &older);
            added += older.len();
            rows.extend(older);
            report(progress, |s| s.matches_found = rows.len());
            next += 1;
        }
    }
    if !updates.is_empty() {
        cache.put_match_rows(key, &updates);
        for u in updates {
            if let Some(slot) = rows.iter_mut().find(|r| r.id == u.id) {
                *slot = u;
            }
        }
    }
    cache.set_list_exhausted(key, exhausted);
    rows.sort_by_key(|m| std::cmp::Reverse(m.started_at_ms));
    out.coverage.exhausted = exhausted;
    out.coverage.new_matches = added;
    out.coverage.total_matches = rows.len();
    out.matches = rows;
    out
}

/// A participant whose rank has to be looked up, and the roles they played.
struct Unrated {
    id: String,
    /// Known only when the match was fetched in this run.
    token: Option<String>,
    name: Option<String>,
    roles: Vec<Role>,
}

fn note_unrated(
    list: &mut Vec<Unrated>,
    id: String,
    token: Option<String>,
    name: Option<String>,
    role: Role,
) {
    match list.iter_mut().find(|u| u.id == id) {
        Some(u) => {
            if !u.roles.contains(&role) {
                u.roles.push(role);
            }
            if u.token.is_none() {
                u.token = token;
            }
        }
        None => list.push(Unrated {
            id,
            token,
            name,
            roles: vec![role],
        }),
    }
}

/// Participants of a detail who carry no rank in the match and played a known role:
/// the ones whose career rank is needed for lobby strength.
fn rating_needs(detail: &MatchDetail) -> Vec<(String, Option<String>, Role)> {
    detail
        .allies
        .iter()
        .chain(&detail.enemies)
        .filter_map(|p| {
            let id = p.bnet_id.clone()?;
            let ranked = p.rank.as_ref().is_some_and(|r| r.skill_rating.is_some());
            (!ranked && p.role != Role::Unknown).then(|| (id, p.name.clone(), p.role))
        })
        .collect()
}

/// Whether `role`'s rating for this player can be answered from the cache without a request.
fn rating_cached(
    cache: &dyn StrengthCache,
    id: &str,
    role: Role,
    current: u32,
    previous: Option<u32>,
    refresh: bool,
) -> bool {
    if refresh {
        return false;
    }
    match cache.season_ratings(id, current) {
        Some(rows)
            if rows
                .iter()
                .any(|r| r.role == role && r.rank.skill_rating.is_some()) =>
        {
            true
        }
        // The current season has no rank for this role: the previous one decides, and it
        // is either cached or looked up, so only a missing entry needs the network.
        Some(_) => previous.is_none_or(|p| cache.season_ratings(id, p).is_some()),
        None => false,
    }
}

/// The newest `limit` of `rows` (all of them without a limit), newest first.
fn newest(mut rows: Vec<MatchSummary>, limit: Option<usize>) -> Vec<MatchSummary> {
    rows.sort_by_key(|m| std::cmp::Reverse(m.started_at_ms));
    if let Some(n) = limit {
        rows.truncate(n);
    }
    rows
}

/// Whether a match's detail is stored.
pub fn detail_stored(cache: &dyn StrengthCache, mode: Mode, match_id: &str, subject: &str) -> bool {
    cache.detail(mode, match_id, subject).is_some()
}

/// Whether everything the lobby-strength analysis needs from this match is stored: its
/// detail, and a current rank for every participant who can be looked up. Such a match is
/// analysed without a single request.
pub fn match_prepared(
    cache: &dyn StrengthCache,
    mode: Mode,
    match_id: &str,
    subject: &str,
    current: u32,
) -> bool {
    let previous = current.checked_sub(1).filter(|s| *s > 0);
    cache.detail(mode, match_id, subject).is_some_and(|kept| {
        rating_needs(&kept.detail)
            .into_iter()
            .filter(|(id, _, _)| !kept.unreachable.contains(id))
            .all(|(id, _, role)| rating_cached(cache, &id, role, current, previous, false))
    })
}

/// Fills each participant's `career_rank` from the ranks stored for lobby strength, by the
/// same rule the analysis uses ([`PlayerRating::rating_for`]), without any request:
/// players nobody has looked up stay without one.
pub fn attach_career_ranks(detail: &mut MatchDetail, cache: &dyn StrengthCache, current: u32) {
    let previous = current.checked_sub(1).filter(|s| *s > 0);
    for p in detail.allies.iter_mut().chain(detail.enemies.iter_mut()) {
        let ranked = p.rank.as_ref().is_some_and(|r| r.skill_rating.is_some());
        let (Some(id), false) = (p.bnet_id.as_deref(), ranked) else {
            continue;
        };
        let mut roles = Vec::new();
        for season in std::iter::once(current).chain(previous) {
            if let Some(rows) = cache.season_ratings(id, season) {
                merge_ratings(&mut roles, rows, season, current);
            }
        }
        let player = PlayerRating {
            bnet_id: id.to_owned(),
            name: None,
            roles,
        };
        match player.rating_for(p.role) {
            Some((_, RatingFit::SameRole)) => {
                p.career_rank = player.for_role(p.role).map(|r| r.rank.clone());
            }
            Some((best, RatingFit::OtherRoles)) => {
                p.career_rank = Some(Rank {
                    tier: None,
                    division: None,
                    score: None,
                    skill_rating: Some(best.round() as i64),
                    at_ms: None,
                });
                p.career_other_roles = true;
            }
            None => {}
        }
    }
}

/// Adds `rows` (read from, or about to be stored for, season `key`) to a player's
/// ratings: the first rank seen for a role wins, and the season is stated relative to now
/// (`None` is the current season) however long ago it was stored.
fn merge_ratings(ratings: &mut Vec<RoleRating>, rows: Vec<RoleRating>, key: u32, current: u32) {
    for mut r in rows {
        r.season = (key != current).then_some(key);
        if !ratings.iter().any(|x| x.role == r.role) {
            ratings.push(r);
        }
    }
}

/// What reading the player's card and careers gave.
struct ProfilePart {
    fetches: Vec<FetchRecord>,
    card: Option<PlayerProfile>,
    careers: Vec<CareerSnapshot>,
}

/// Reads the card and the career of each mode (nothing when the plan has no profile).
async fn read_profile<F: Fetcher>(
    f: &F,
    cat: &Catalog,
    token: &str,
    plan: &CollectPlan,
) -> ProfilePart {
    let mut part = ProfilePart {
        fetches: Vec::new(),
        card: None,
        careers: Vec::new(),
    };
    if !plan.profile {
        return part;
    }
    let result = f.fetch(Endpoint::Card, json!({"token":token})).await;
    part.fetches
        .push(record(Endpoint::Card, None, None, None, None, &result));
    if let Ok(card) = &result {
        part.card = Some(normalize::profile(normalize::payload(&card.value)));
    }
    let mut seasons = vec![plan.season];
    for s in &plan.career_seasons {
        if !seasons.contains(&Some(*s)) {
            seasons.push(Some(*s));
        }
    }
    for &mode in &plan.modes {
        for &season in &seasons {
            let endpoint = mode.career();
            let result = f.fetch(endpoint, career_payload(token, mode, season)).await;
            part.fetches
                .push(record(endpoint, Some(mode), season, None, None, &result));
            if let Ok(v) = result {
                part.careers.push(normalize::career(
                    normalize::payload(&v.value),
                    mode,
                    season,
                    cat,
                ));
            }
        }
    }
    part
}

/// What reading the match lists gave.
struct ListsPart {
    fetches: Vec<FetchRecord>,
    match_lists: Vec<ListCoverage>,
    matches: Vec<MatchSummary>,
}

/// The match list of every mode of the plan: from the rows the caller already holds, or
/// through the local store when there is one (and `subject` says whose list it is), or by
/// paging the upstream.
async fn read_lists<F: Fetcher>(
    f: &F,
    cat: &Catalog,
    token: &str,
    plan: &CollectPlan,
    roles: &[Role],
    subject: Option<&str>,
) -> ListsPart {
    let mut part = ListsPart {
        fetches: Vec::new(),
        match_lists: Vec::new(),
        matches: Vec::new(),
    };
    let mut seen = HashSet::new();
    if !plan.known_matches.is_empty() {
        // The history is what the caller already read; nothing to page through.
        part.matches.extend(
            plan.known_matches
                .iter()
                .filter(|m| seen.insert(m.id.clone()))
                .cloned(),
        );
        return part;
    }
    for &mode in &plan.modes {
        let pages = if let (Some(cache), Some(subject)) = (plan.cache.as_deref(), subject) {
            // Through the local store: only what is new (and, as needed, older) is fetched.
            let scope = SyncScope {
                page: PageScope {
                    token,
                    mode,
                    season: plan.season,
                    max_pages: plan.max_pages,
                },
                subject,
                quota: plan
                    .list_quota
                    .or(plan.details_per_role)
                    .map(|n| (n, roles)),
            };
            sync_match_list(f, cat, cache, &scope, plan.progress.as_deref()).await
        } else {
            let quota = plan.details_per_role;
            let scope = PageScope {
                token,
                mode,
                season: plan.season,
                max_pages: plan.max_pages,
            };
            match_pages_until(
                f,
                cat,
                &scope,
                |read| quota.is_some_and(|n| role_quota_met_for(read, n, roles)),
                plan.progress.as_deref(),
            )
            .await
        };
        part.fetches.extend(pages.fetches);
        part.match_lists.push(pages.coverage);
        part.matches.extend(
            newest(pages.matches, plan.match_limit)
                .into_iter()
                .filter(|m| seen.insert(m.id.clone())),
        );
    }
    part
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
    let roles: Vec<Role> = if plan.roles.is_empty() {
        Role::PLAYABLE.to_vec()
    } else {
        plan.roles.clone()
    };

    // The card and careers first (they can say who the player is when the identity does
    // not), then the match lists. Asking for them together was tried: the upstream answers
    // one request at a time per account, so it saved nothing.
    let profile_part = read_profile(f, cat, token, plan).await;
    if let Some(card) = &profile_part.card {
        normalize::merge_profile(&mut profile, card.clone());
    }
    let lists_part = read_lists(f, cat, token, plan, &roles, profile.bnet_id.as_deref()).await;
    fetches.extend(profile_part.fetches);
    let careers = profile_part.careers;
    fetches.extend(lists_part.fetches);
    let match_lists = lists_part.match_lists;
    let mut matches = lists_part.matches;
    matches.sort_by_key(|m| std::cmp::Reverse(m.started_at_ms));

    let mut details = BTreeMap::new();
    // Players whose rank is needed, with their token when the match was fetched this run.
    // Memory only; tokens never reach the cache.
    let mut unrated: Vec<Unrated> = Vec::new();
    let cache = plan.cache.as_deref();
    let subject_id = profile.bnet_id.clone();
    let current = cat.current_season;
    let previous = current.checked_sub(1).filter(|s| *s > 0);
    let mut cache_hits = 0usize;
    let chosen: Vec<usize> = if !plan.known_matches.is_empty() {
        // The caller already chose which matches to look up; take them all.
        (0..matches.len()).collect()
    } else {
        match plan.details_per_role {
            Some(n) => select_per_role_for(&matches, n, &roles),
            None => (0..matches.len().min(plan.max_details)).collect(),
        }
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
        let mode = m.kind.mode;
        let map_name = m
            .map
            .as_ref()
            .and_then(|e| e.name.clone())
            .unwrap_or_default();

        // A finished match is the same every time; reuse it when every rating it needs
        // is also at hand. Otherwise fetch it again, to get the participants' tokens.
        if let (Some(cache), Some(subject)) = (cache, subject_id.as_deref())
            && let Some(CachedDetail {
                detail,
                unreachable,
            }) = cache.detail(mode, &m.id, subject)
        {
            let needs: Vec<_> = rating_needs(&detail)
                .into_iter()
                .filter(|(id, _, _)| !unreachable.contains(id))
                .collect();
            let covered = !plan.lobby_ratings
                || needs.iter().all(|(id, _, role)| {
                    rating_cached(cache, id, *role, current, previous, plan.refresh_ratings)
                });
            if covered {
                cache_hits += 1;
                report(plan.progress.as_deref(), |s| {
                    s.done += 1;
                    s.cached += 1;
                    s.note = map_name.clone();
                });
                if plan.lobby_ratings {
                    for (id, name, role) in needs {
                        note_unrated(&mut unrated, id, None, name, role);
                    }
                }
                details.insert(m.id.clone(), detail);
                continue;
            }
        }

        let endpoint = mode.match_info();
        let result = f.fetch(endpoint, match_info_payload(token, &m.id)).await;
        report(plan.progress.as_deref(), |s| {
            s.done += 1;
            s.requests += 1;
            if result.is_err() {
                s.failures += 1;
            }
            s.note = map_name.clone();
        });
        fetches.push(record(
            endpoint,
            Some(mode),
            None,
            None,
            Some(&m.id),
            &result,
        ));
        if let Ok(v) = result {
            let mut detail = normalize::match_detail(
                &m.id,
                normalize::payload(&v.value),
                mode,
                profile.bnet_id.as_deref(),
                cat,
            );
            detail.started_at_ms = detail.started_at_ms.or(m.started_at_ms);
            let mut unreachable = Vec::new();
            if plan.lobby_ratings {
                let tokens = normalize::participant_tokens(normalize::payload(&v.value));
                for (id, name, role) in rating_needs(&detail) {
                    // Without a token the player cannot be looked up.
                    if let Some((_, token, _)) = tokens.iter().find(|t| t.0 == id) {
                        note_unrated(&mut unrated, id, Some(token.clone()), name, role);
                    } else if !unreachable.contains(&id) {
                        unreachable.push(id);
                    }
                }
            }
            if let (Some(cache), Some(subject)) = (cache, subject_id.as_deref()) {
                cache.put_detail(subject, &detail, &unreachable);
            }
            details.insert(m.id.clone(), detail);
        }
    }

    let mut player_ratings = Vec::new();
    let to_rate = unrated.len().min(plan.max_rated_players);
    report(plan.progress.as_deref(), |s| {
        s.phase = "ratings".into();
        s.done = 0;
        s.total = to_rate;
        s.note.clear();
    });
    for u in unrated.into_iter().take(plan.max_rated_players) {
        report(plan.progress.as_deref(), |s| {
            s.done += 1;
            s.note = u.name.clone().unwrap_or_default();
        });
        let mut ratings: Vec<RoleRating> = Vec::new();
        // Current season first; the previous season only fills roles still unrated.
        for season in std::iter::once(None).chain(previous.map(Some)) {
            if u.roles
                .iter()
                .all(|r| ratings.iter().any(|x: &RoleRating| x.role == *r))
            {
                break;
            }
            let key = season.unwrap_or(current);
            let skip_cache = plan.refresh_ratings && season.is_none();
            if let Some(cache) = cache.filter(|_| !skip_cache)
                && let Some(rows) = cache.season_ratings(&u.id, key)
            {
                cache_hits += 1;
                report(plan.progress.as_deref(), |s| s.cached += 1);
                merge_ratings(&mut ratings, rows, key, current);
                continue;
            }
            let Some(player_token) = u.token.as_deref() else {
                continue;
            };
            let endpoint = Mode::Competitive.career();
            let result = f
                .fetch(
                    endpoint,
                    career_payload(player_token, Mode::Competitive, season),
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
                let rows = normalize::role_ratings(normalize::payload(&v.value), season);
                if let Some(cache) = cache {
                    // A season asked for by its number is a finished one: its ranks never change.
                    cache.put_season_ratings(&u.id, key, &rows, season.is_some());
                }
                merge_ratings(&mut ratings, rows, key, current);
            }
        }
        player_ratings.push(PlayerRating {
            bnet_id: u.id,
            name: u.name,
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
            cache_hits,
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
