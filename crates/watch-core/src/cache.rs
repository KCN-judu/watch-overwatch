//! Keeps what was fetched so the next run does not fetch it again.
//!
//! Three things are worth keeping:
//!  - a player's match list, so only matches newer than the newest stored one are
//!    fetched (see [`StoredList`]);
//!  - a finished match's detail never changes, so it is kept as long as the player
//!    asked about it (the detail's "allies" and "enemies" are relative to that
//!    player, so it is stored per player);
//!
//! Players' ranks are not kept apart from the matches: each match keeps the snapshot
//! taken for it (`crate::snapshot`), and within one lookup run (or background job) a
//! player is asked once (`crate::snapshot::Lookups`).
//!
//! Other players' tokens are never kept: when a cached match still needs a rank, the
//! match is fetched again to get the tokens.
use crate::dashen::Mode;
use crate::ir::{MatchDetail, MatchSummary};
use std::collections::HashMap;
use std::sync::Mutex;

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
}

/// Subject, mode and season of a stored list.
type ListId = (String, Mode, Option<u32>);

/// In-memory cache: for tests, and a fallback when the disk cache cannot be opened.
#[derive(Debug, Default)]
pub struct MemoryCache {
    lists: Mutex<HashMap<ListId, StoredList>>,
    details: Mutex<HashMap<(Mode, String, String), CachedDetail>>,
}

impl MemoryCache {
    pub fn new() -> Self {
        Self::default()
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
            let key = (detail.mode, detail.id.clone(), subject.to_owned());
            // A match read again keeps the rank snapshots taken for it before.
            let mut detail = detail.clone();
            if let Some(old) = d.get(&key) {
                crate::snapshot::carry(&mut detail, &old.detail);
            }
            d.insert(
                key,
                CachedDetail {
                    detail,
                    unreachable: unreachable.to_vec(),
                },
            );
        }
    }
}
