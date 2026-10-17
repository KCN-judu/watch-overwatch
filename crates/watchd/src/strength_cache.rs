//! On-disk store behind [`StrengthCache`]: finished-match details and per-season
//! ranks, in one SQLite file under the user's data folder.
//!
//! It holds other players' names and bnet ids (they are in the match details) but never
//! any token. Entries stored more than [`KEEP_DAYS`] days ago are dropped when the file opens.
use rusqlite::{Connection, OptionalExtension, params};
use serde::Serialize;
use std::{path::Path, sync::Mutex, time::Duration};
use watch_core::{
    CachedDetail, StrengthCache,
    dashen::Mode,
    ir::{MatchDetail, RoleRating},
};

const KEEP_DAYS: u128 = 180;

#[derive(Debug)]
pub struct SqliteCache {
    conn: Mutex<Connection>,
    path: std::path::PathBuf,
}

#[derive(Debug, Clone, Serialize)]
pub struct CacheStats {
    /// Cached match details.
    pub matches: usize,
    /// Players with at least one cached season of ranks.
    pub players: usize,
    pub bytes: u64,
}

impl SqliteCache {
    pub fn open(path: &Path) -> rusqlite::Result<Self> {
        if let Some(dir) = path.parent() {
            let _ = std::fs::create_dir_all(dir);
        }
        let conn = Connection::open(path)?;
        conn.execute_batch(
            "PRAGMA journal_mode=WAL;
             PRAGMA synchronous=NORMAL;
             CREATE TABLE IF NOT EXISTS match_detail(
                 mode TEXT NOT NULL,
                 match_id TEXT NOT NULL,
                 subject TEXT NOT NULL,
                 fetched_ms INTEGER NOT NULL,
                 unreachable TEXT NOT NULL,
                 data TEXT NOT NULL,
                 PRIMARY KEY(mode, match_id, subject));
             CREATE TABLE IF NOT EXISTS season_ratings(
                 bnet_id TEXT NOT NULL,
                 season INTEGER NOT NULL,
                 fetched_ms INTEGER NOT NULL,
                 data TEXT NOT NULL,
                 PRIMARY KEY(bnet_id, season));",
        )?;
        let cutoff = now_ms().saturating_sub(KEEP_DAYS * 24 * 3600 * 1000) as i64;
        conn.execute("DELETE FROM match_detail WHERE fetched_ms < ?1", [cutoff])?;
        conn.execute("DELETE FROM season_ratings WHERE fetched_ms < ?1", [cutoff])?;
        Ok(Self {
            conn: Mutex::new(conn),
            path: path.to_owned(),
        })
    }

    pub fn stats(&self) -> CacheStats {
        let Ok(c) = self.conn.lock() else {
            return CacheStats {
                matches: 0,
                players: 0,
                bytes: 0,
            };
        };
        let count = |sql: &str| -> usize {
            c.query_row(sql, [], |r| r.get::<_, i64>(0))
                .map_or(0, |n| n.max(0) as usize)
        };
        let bytes = |name: &str| -> u64 {
            std::fs::metadata(self.path.with_file_name(name)).map_or(0, |m| m.len())
        };
        let file = self
            .path
            .file_name()
            .map(|n| n.to_string_lossy().into_owned())
            .unwrap_or_default();
        CacheStats {
            matches: count("SELECT COUNT(*) FROM match_detail"),
            players: count("SELECT COUNT(DISTINCT bnet_id) FROM season_ratings"),
            bytes: bytes(&file) + bytes(&format!("{file}-wal")),
        }
    }

    /// Forgets everything.
    pub fn clear(&self) {
        if let Ok(c) = self.conn.lock() {
            let _ =
                c.execute_batch("DELETE FROM match_detail; DELETE FROM season_ratings; VACUUM;");
        }
    }
}

fn now_ms() -> u128 {
    watch_core::now_ms()
}

impl StrengthCache for SqliteCache {
    fn detail(&self, mode: Mode, match_id: &str, subject: &str) -> Option<CachedDetail> {
        let c = self.conn.lock().ok()?;
        let (data, unreachable): (String, String) = c
            .query_row(
                "SELECT data, unreachable FROM match_detail
                 WHERE mode = ?1 AND match_id = ?2 AND subject = ?3",
                params![mode.provider_value(), match_id, subject],
                |r| Ok((r.get(0)?, r.get(1)?)),
            )
            .optional()
            .ok()??;
        // A row that no longer parses (the format moved on) is simply a miss.
        Some(CachedDetail {
            detail: serde_json::from_str(&data).ok()?,
            unreachable: serde_json::from_str(&unreachable).unwrap_or_default(),
        })
    }

    fn put_detail(&self, subject: &str, detail: &MatchDetail, unreachable: &[String]) {
        let (Ok(data), Ok(unreachable)) = (
            serde_json::to_string(detail),
            serde_json::to_string(unreachable),
        ) else {
            return;
        };
        if let Ok(c) = self.conn.lock()
            && let Err(e) = c.execute(
                "INSERT OR REPLACE INTO match_detail
                 (mode, match_id, subject, fetched_ms, unreachable, data)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
                params![
                    detail.mode.provider_value(),
                    detail.id,
                    subject,
                    now_ms() as i64,
                    unreachable,
                    data
                ],
            )
        {
            tracing::warn!("strength cache: could not store a match: {e}");
        }
    }

    fn season_ratings(
        &self,
        bnet_id: &str,
        season: u32,
        max_age: Option<Duration>,
    ) -> Option<Vec<RoleRating>> {
        let c = self.conn.lock().ok()?;
        let (at, data): (i64, String) = c
            .query_row(
                "SELECT fetched_ms, data FROM season_ratings WHERE bnet_id = ?1 AND season = ?2",
                params![bnet_id, season],
                |r| Ok((r.get(0)?, r.get(1)?)),
            )
            .optional()
            .ok()??;
        if let Some(age) = max_age
            && now_ms().saturating_sub(at.max(0) as u128) > age.as_millis()
        {
            return None;
        }
        serde_json::from_str(&data).ok()
    }

    fn put_season_ratings(&self, bnet_id: &str, season: u32, ratings: &[RoleRating]) {
        let Ok(data) = serde_json::to_string(ratings) else {
            return;
        };
        if let Ok(c) = self.conn.lock()
            && let Err(e) = c.execute(
                "INSERT OR REPLACE INTO season_ratings (bnet_id, season, fetched_ms, data)
                 VALUES (?1, ?2, ?3, ?4)",
                params![bnet_id, season, now_ms() as i64, data],
            )
        {
            tracing::warn!("strength cache: could not store ratings: {e}");
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use watch_core::ir::{Rank, Role};

    fn rating(role: Role, sr: i64) -> RoleRating {
        RoleRating {
            role,
            season: None,
            rank: Rank {
                tier: None,
                division: None,
                score: None,
                skill_rating: Some(sr),
                at_ms: None,
            },
        }
    }

    #[test]
    fn ratings_round_trip_expire_and_clear() {
        let dir = std::env::temp_dir().join(format!("wo-cache-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let cache = SqliteCache::open(&dir.join("strength.db")).unwrap();
        assert!(cache.season_ratings("1", 25, None).is_none());
        cache.put_season_ratings("1", 25, &[rating(Role::Tank, 2300)]);
        let got = cache.season_ratings("1", 25, None).unwrap();
        assert_eq!(got[0].rank.skill_rating, Some(2300));
        assert!(
            cache
                .season_ratings("1", 25, Some(Duration::from_secs(3600)))
                .is_some()
        );
        // A current-season entry older than its allowed age is a miss; with no limit it stays.
        std::thread::sleep(Duration::from_millis(20));
        assert!(
            cache
                .season_ratings("1", 25, Some(Duration::from_millis(1)))
                .is_none()
        );
        assert!(cache.season_ratings("1", 25, None).is_some());
        // Other seasons and players are separate.
        assert!(cache.season_ratings("1", 24, None).is_none());
        assert!(cache.season_ratings("2", 25, None).is_none());
        let s = cache.stats();
        assert_eq!((s.matches, s.players), (0, 1));
        assert!(s.bytes > 0);
        cache.clear();
        assert_eq!(cache.stats().players, 0);
        drop(cache);
        let _ = std::fs::remove_dir_all(&dir);
    }
}
