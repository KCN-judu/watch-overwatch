//! Keeps what an analysis fetched so the next one does not fetch it again.
//!
//! Two things are worth keeping:
//!  - a finished match's detail never changes, so it is kept as long as the player
//!    asked about it (the detail's "allies" and "enemies" are relative to that
//!    player, so it is stored per player);
//!  - a player's competitive ranks for one season: past seasons never change, the
//!    current one is reused for a while.
//!
//! Other players' tokens are never kept: when a cached match still needs a rating that
//! is not cached, the match is fetched again to get the tokens.
use crate::dashen::Mode;
use crate::ir::{MatchDetail, RoleRating};
use std::collections::HashMap;
use std::sync::Mutex;
use std::time::Duration;

/// How long a current-season rating is reused before it is looked up again.
pub const RATINGS_TTL: Duration = Duration::from_secs(24 * 3600);

/// A kept match detail, and the participants who could not be looked up when it was
/// fetched (the upstream gave no token for them), so they are not asked about again.
#[derive(Debug, Clone)]
pub struct CachedDetail {
    pub detail: MatchDetail,
    pub unreachable: Vec<String>,
}

pub trait StrengthCache: Send + Sync + std::fmt::Debug {
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

/// In-memory cache: for tests, and a fallback when the disk cache cannot be opened.
#[derive(Debug, Default)]
pub struct MemoryCache {
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
