//! Keeps what was fetched so the next run does not fetch it again.
//!
//! Three things are worth keeping:
//!  - a player's match list, so only matches newer than the newest stored one are
//!    fetched (see [`StoredList`]);
//!  - a finished match's detail never changes, so it is kept as long as the player
//!    asked about it (the detail's "allies" and "enemies" are relative to that
//!    player, so it is stored per player);
//!  - a player's competitive ranks for one season: past seasons never change, the
//!    current one is reused for a while.
//!
//! Other players' tokens are never kept: when a cached match still needs a rating that
//! is not cached, the match is fetched again to get the tokens.
use crate::dashen::Mode;
use crate::ir::{MatchDetail, MatchSummary, RoleRating};
use std::collections::HashMap;
use std::sync::Mutex;
use std::time::Duration;

/// How long a current-season rating is reused before it is looked up again.
pub const RATINGS_TTL: Duration = Duration::from_secs(7 * 24 * 3600);

/// A kept match detail, and the participants who could not be looked up when it was
/// fetched (the upstream gave no token for them), so they are not asked about again.
#[derive(Debug, Clone)]
pub struct CachedDetail {
    pub detail: MatchDetail,
    pub unreachable: Vec<String>,
}

/// A player's match list for one mode and season as kept locally.
#[derive(Debug, Clone, Default)]
pub struct StoredList {
    /// Newest first.
    pub rows: Vec<MatchSummary>,
    /// True when the oldest match the upstream has is among `rows`.
    pub exhausted: bool,
}

/// Which stored list: whose, which mode, which season (`None` is the current one).
#[derive(Debug, Clone, Copy)]
pub struct ListKey<'a> {
    pub subject: &'a str,
    pub mode: Mode,
    pub season: Option<u32>,
}

pub trait StrengthCache: Send + Sync + std::fmt::Debug {
    /// The stored match list. The rows are always a gap-free run starting at the newest
    /// match the last sync saw.
    fn match_list(&self, key: ListKey<'_>) -> StoredList;
    /// Adds rows to the stored list (rows already there are replaced).
    fn put_match_rows(&self, key: ListKey<'_>, rows: &[MatchSummary]);
    /// Records whether the stored list reaches the upstream's oldest match.
    fn set_list_exhausted(&self, key: ListKey<'_>, exhausted: bool);
    /// Forgets the stored list (when it can no longer be shown to be gap-free).
    fn clear_match_list(&self, key: ListKey<'_>);
    /// The detail of `match_id` as seen by `subject` (their bnet id).
    fn detail(&self, mode: Mode, match_id: &str, subject: &str) -> Option<CachedDetail>;
    fn put_detail(&self, subject: &str, detail: &MatchDetail, unreachable: &[String]);
    /// Ranks of one player in one season. `max_age` of `None` never expires.
    fn season_ratings(
        &self,
        bnet_id: &str,
        season: u32,
        max_age: Option<Duration>,
    ) -> Option<Vec<RoleRating>>;
    fn put_season_ratings(&self, bnet_id: &str, season: u32, ratings: &[RoleRating]);
}

/// When the ranks were stored (ms since the epoch), and the ranks.
type StoredRatings = (u128, Vec<RoleRating>);

/// Subject, mode and season of a stored list.
type ListId = (String, Mode, Option<u32>);

/// In-memory cache: for tests, and a fallback when the disk cache cannot be opened.
#[derive(Debug, Default)]
pub struct MemoryCache {
    lists: Mutex<HashMap<ListId, StoredList>>,
    details: Mutex<HashMap<(Mode, String, String), CachedDetail>>,
    ratings: Mutex<HashMap<(String, u32), StoredRatings>>,
}

impl MemoryCache {
    pub fn new() -> Self {
        Self::default()
    }
    /// Forgets every rating but keeps the match details.
    pub fn clear_ratings(&self) {
        if let Ok(mut r) = self.ratings.lock() {
            r.clear();
        }
    }
}

impl StrengthCache for MemoryCache {
    fn match_list(&self, key: ListKey<'_>) -> StoredList {
        let lists = self.lists.lock().ok();
        lists
            .and_then(|l| {
                l.get(&(key.subject.to_owned(), key.mode, key.season))
                    .cloned()
            })
            .unwrap_or_default()
    }
    fn put_match_rows(&self, key: ListKey<'_>, rows: &[MatchSummary]) {
        if let Ok(mut l) = self.lists.lock() {
            let list = l
                .entry((key.subject.to_owned(), key.mode, key.season))
                .or_default();
            for row in rows {
                match list.rows.iter_mut().find(|r| r.id == row.id) {
                    Some(old) => *old = row.clone(),
                    None => list.rows.push(row.clone()),
                }
            }
            list.rows
                .sort_by_key(|m| std::cmp::Reverse(m.started_at_ms));
        }
    }
    fn set_list_exhausted(&self, key: ListKey<'_>, exhausted: bool) {
        if let Ok(mut l) = self.lists.lock() {
            l.entry((key.subject.to_owned(), key.mode, key.season))
                .or_default()
                .exhausted = exhausted;
        }
    }
    fn clear_match_list(&self, key: ListKey<'_>) {
        if let Ok(mut l) = self.lists.lock() {
            l.remove(&(key.subject.to_owned(), key.mode, key.season));
        }
    }
    fn detail(&self, mode: Mode, match_id: &str, subject: &str) -> Option<CachedDetail> {
        self.details
            .lock()
            .ok()?
            .get(&(mode, match_id.to_owned(), subject.to_owned()))
            .cloned()
    }
    fn put_detail(&self, subject: &str, detail: &MatchDetail, unreachable: &[String]) {
        if let Ok(mut d) = self.details.lock() {
            d.insert(
                (detail.mode, detail.id.clone(), subject.to_owned()),
                CachedDetail {
                    detail: detail.clone(),
                    unreachable: unreachable.to_vec(),
                },
            );
        }
    }
    fn season_ratings(
        &self,
        bnet_id: &str,
        season: u32,
        max_age: Option<Duration>,
    ) -> Option<Vec<RoleRating>> {
        let r = self.ratings.lock().ok()?;
        let (at, rows) = r.get(&(bnet_id.to_owned(), season))?;
        let fresh =
            max_age.is_none_or(|age| crate::now_ms().saturating_sub(*at) <= age.as_millis());
        fresh.then(|| rows.clone())
    }
    fn put_season_ratings(&self, bnet_id: &str, season: u32, ratings: &[RoleRating]) {
        if let Ok(mut r) = self.ratings.lock() {
            r.insert(
                (bnet_id.to_owned(), season),
                (crate::now_ms(), ratings.to_vec()),
            );
        }
    }
}
