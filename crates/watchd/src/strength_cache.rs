//! On-disk store behind [`StrengthCache`]: each player's match list, finished-match
//! details (with everyone who took part) and per-season ranks, in one SQLite file under
//! the user's data folder.
//!
//! It holds other players' names and bnet ids (they are in the match details) but never
//! any token. Details and ranks stored more than [`KEEP_DAYS`] days ago are dropped when
//! the file opens; match lists are kept, as they are only ever extended.
use rusqlite::{Connection, OptionalExtension, params};
use serde::Serialize;
use std::{path::Path, sync::Mutex, time::Duration};
use watch_core::{
    CachedDetail, ListKey, StoredList, StrengthCache,
    dashen::Mode,
    ir::{MatchDetail, MatchSummary, RoleRating},
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
    /// Matches in the stored match lists.
    pub listed: usize,
    /// Distinct players seen in stored matches.
    pub participants: usize,
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
             CREATE TABLE IF NOT EXISTS match_list(
                 subject TEXT NOT NULL,
                 mode TEXT NOT NULL,
                 season INTEGER NOT NULL,
                 match_id TEXT NOT NULL,
                 started_ms INTEGER,
                 data TEXT NOT NULL,
                 PRIMARY KEY(subject, mode, season, match_id));
             CREATE TABLE IF NOT EXISTS list_state(
                 subject TEXT NOT NULL,
                 mode TEXT NOT NULL,
                 season INTEGER NOT NULL,
                 exhausted INTEGER NOT NULL,
                 PRIMARY KEY(subject, mode, season));
             CREATE TABLE IF NOT EXISTS match_participant(
                 subject TEXT NOT NULL,
                 mode TEXT NOT NULL,
                 match_id TEXT NOT NULL,
                 bnet_id TEXT NOT NULL,
                 side TEXT NOT NULL,
                 name TEXT,
                 role TEXT NOT NULL,
                 PRIMARY KEY(subject, mode, match_id, bnet_id));
             CREATE INDEX IF NOT EXISTS participant_by_player ON match_participant(bnet_id);
             CREATE TABLE IF NOT EXISTS season_ratings(
                 bnet_id TEXT NOT NULL,
                 season INTEGER NOT NULL,
                 fetched_ms INTEGER NOT NULL,
                 data TEXT NOT NULL,
                 PRIMARY KEY(bnet_id, season));",
        )?;
        let cutoff = now_ms().saturating_sub(KEEP_DAYS * 24 * 3600 * 1000) as i64;
        conn.execute("DELETE FROM match_detail WHERE fetched_ms < ?1", [cutoff])?;
        conn.execute(
            "DELETE FROM match_participant WHERE NOT EXISTS (
                 SELECT 1 FROM match_detail d WHERE d.subject = match_participant.subject
                 AND d.mode = match_participant.mode AND d.match_id = match_participant.match_id)",
            [],
        )?;
        conn.execute("DELETE FROM season_ratings WHERE fetched_ms < ?1", [cutoff])?;
        let cache = Self {
            conn: Mutex::new(conn),
            path: path.to_owned(),
        };
        cache.index_participants();
        Ok(cache)
    }

    /// Details stored before the participant index existed are added to it once.
    fn index_participants(&self) {
        let Ok(mut c) = self.conn.lock() else { return };
        let count = |c: &Connection, table: &str| -> i64 {
            c.query_row(&format!("SELECT COUNT(*) FROM {table}"), [], |r| r.get(0))
                .unwrap_or(0)
        };
        if count(&c, "match_participant") > 0 || count(&c, "match_detail") == 0 {
            return;
        }
        let result = (|| -> rusqlite::Result<()> {
            let rows: Vec<(String, String)> = {
                let mut st = c.prepare("SELECT subject, data FROM match_detail")?;
                st.query_map([], |r| Ok((r.get(0)?, r.get(1)?)))?
                    .filter_map(Result::ok)
                    .collect()
            };
            let tx = c.transaction()?;
            for (subject, data) in rows {
                if let Ok(detail) = serde_json::from_str::<MatchDetail>(&data) {
                    insert_participants(&tx, &subject, &detail)?;
                }
            }
            tx.commit()
        })();
        if let Err(e) = result {
            tracing::warn!("strength cache: could not index participants: {e}");
        }
    }

    pub fn stats(&self) -> CacheStats {
        let Ok(c) = self.conn.lock() else {
            return CacheStats {
                matches: 0,
                listed: 0,
                participants: 0,
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
            listed: count("SELECT COUNT(*) FROM match_list"),
            participants: count("SELECT COUNT(DISTINCT bnet_id) FROM match_participant"),
            players: count("SELECT COUNT(DISTINCT bnet_id) FROM season_ratings"),
            bytes: bytes(&file) + bytes(&format!("{file}-wal")),
        }
    }

    /// Forgets everything.
    pub fn clear(&self) {
        if let Ok(c) = self.conn.lock() {
            let _ = c.execute_batch(
                "DELETE FROM match_detail; DELETE FROM season_ratings;
                 DELETE FROM match_list; DELETE FROM list_state;
                 DELETE FROM match_participant; VACUUM;",
            );
        }
    }
}

/// Who took part in a match and on which side, findable without opening the detail.
fn insert_participants(
    tx: &rusqlite::Transaction<'_>,
    subject: &str,
    detail: &MatchDetail,
) -> rusqlite::Result<()> {
    for (side, people) in [("ally", &detail.allies), ("enemy", &detail.enemies)] {
        for p in people {
            let Some(id) = p.bnet_id.as_deref() else {
                continue;
            };
            tx.execute(
                "INSERT OR REPLACE INTO match_participant
                 (subject, mode, match_id, bnet_id, side, name, role)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
                params![
                    subject,
                    detail.mode.provider_value(),
                    detail.id,
                    id,
                    side,
                    p.name,
                    p.role.id()
                ],
            )?;
        }
    }
    Ok(())
}

/// The season column: 0 stands for the current season.
fn season_key(season: Option<u32>) -> i64 {
    season.map_or(0, i64::from)
}

fn now_ms() -> u128 {
    watch_core::now_ms()
}

impl StrengthCache for SqliteCache {
    fn match_list(&self, key: ListKey<'_>) -> StoredList {
        let Ok(c) = self.conn.lock() else {
            return StoredList::default();
        };
        let (mode, season) = (key.mode.provider_value(), season_key(key.season));
        let rows = (|| -> rusqlite::Result<Vec<MatchSummary>> {
            let mut st = c.prepare(
                "SELECT data FROM match_list WHERE subject = ?1 AND mode = ?2 AND season = ?3
                 ORDER BY started_ms IS NULL, started_ms DESC",
            )?;
            let rows = st
                .query_map(params![key.subject, mode, season], |r| {
                    r.get::<_, String>(0)
                })?
                .filter_map(Result::ok)
                // A row that no longer parses is skipped; the next read re-fetches the list.
                .filter_map(|d| serde_json::from_str(&d).ok())
                .collect();
            Ok(rows)
        })()
        .unwrap_or_default();
        let exhausted = c
            .query_row(
                "SELECT exhausted FROM list_state WHERE subject = ?1 AND mode = ?2 AND season = ?3",
                params![key.subject, mode, season],
                |r| r.get::<_, i64>(0),
            )
            .optional()
            .ok()
            .flatten()
            .is_some_and(|e| e != 0);
        StoredList { rows, exhausted }
    }

    fn put_match_rows(&self, key: ListKey<'_>, rows: &[MatchSummary]) {
        let Ok(mut c) = self.conn.lock() else { return };
        let (mode, season) = (key.mode.provider_value(), season_key(key.season));
        let result = (|| -> rusqlite::Result<()> {
            let tx = c.transaction()?;
            {
                let mut st = tx.prepare(
                    "INSERT OR REPLACE INTO match_list
                     (subject, mode, season, match_id, started_ms, data)
                     VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
                )?;
                for m in rows {
                    let Ok(data) = serde_json::to_string(m) else {
                        continue;
                    };
                    st.execute(params![
                        key.subject,
                        mode,
                        season,
                        m.id,
                        m.started_at_ms,
                        data
                    ])?;
                }
            }
            tx.commit()
        })();
        if let Err(e) = result {
            tracing::warn!("strength cache: could not store the match list: {e}");
        }
    }

    fn set_list_exhausted(&self, key: ListKey<'_>, exhausted: bool) {
        if let Ok(c) = self.conn.lock() {
            let _ = c.execute(
                "INSERT OR REPLACE INTO list_state (subject, mode, season, exhausted)
                 VALUES (?1, ?2, ?3, ?4)",
                params![
                    key.subject,
                    key.mode.provider_value(),
                    season_key(key.season),
                    exhausted as i64
                ],
            );
        }
    }

    fn clear_match_list(&self, key: ListKey<'_>) {
        if let Ok(c) = self.conn.lock() {
            let args = params![
                key.subject,
                key.mode.provider_value(),
                season_key(key.season)
            ];
            let _ = c.execute(
                "DELETE FROM match_list WHERE subject = ?1 AND mode = ?2 AND season = ?3",
                args,
            );
            let _ = c.execute(
                "DELETE FROM list_state WHERE subject = ?1 AND mode = ?2 AND season = ?3",
                args,
            );
        }
    }

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
        let Ok(mut c) = self.conn.lock() else { return };
        let mode = detail.mode.provider_value();
        let result = (|| -> rusqlite::Result<()> {
            let tx = c.transaction()?;
            tx.execute(
                "INSERT OR REPLACE INTO match_detail
                 (mode, match_id, subject, fetched_ms, unreachable, data)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
                params![mode, detail.id, subject, now_ms() as i64, unreachable, data],
            )?;
            insert_participants(&tx, subject, detail)?;
            tx.commit()
        })();
        if let Err(e) = result {
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

    #[test]
    fn match_lists_persist_per_player_mode_and_season_and_can_be_reset() {
        use watch_core::{Catalog, ListKey, dashen::normalize};
        let summary = |id: &str, at: i64| -> MatchSummary {
            let row = serde_json::json!({"matchId": id, "beginTs": at, "roleType": "tank"});
            normalize::match_list(&serde_json::json!([row]), Mode::Quick, &Catalog::default())
                .remove(0)
        };
        let dir = std::env::temp_dir().join(format!("wo-list-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let path = dir.join("strength.db");
        let key = ListKey {
            subject: "1001",
            mode: Mode::Quick,
            season: None,
        };
        {
            let cache = SqliteCache::open(&path).unwrap();
            assert!(cache.match_list(key).rows.is_empty());
            cache.put_match_rows(key, &[summary("a", 10), summary("b", 30), summary("c", 20)]);
            cache.set_list_exhausted(key, true);
        }
        // Reopened: still there, newest first, and the flag survived.
        let cache = SqliteCache::open(&path).unwrap();
        let stored = cache.match_list(key);
        let ids: Vec<_> = stored.rows.iter().map(|m| m.id.as_str()).collect();
        assert_eq!(ids, ["b", "c", "a"]);
        assert!(stored.exhausted);
        // Another player, mode or season has its own list.
        assert!(
            cache
                .match_list(ListKey {
                    subject: "2",
                    ..key
                })
                .rows
                .is_empty()
        );
        assert!(
            cache
                .match_list(ListKey {
                    mode: Mode::Competitive,
                    ..key
                })
                .rows
                .is_empty()
        );
        assert!(
            cache
                .match_list(ListKey {
                    season: Some(24),
                    ..key
                })
                .rows
                .is_empty()
        );
        // Rows are replaced, not doubled.
        cache.put_match_rows(key, &[summary("a", 10)]);
        assert_eq!(cache.match_list(key).rows.len(), 3);
        assert_eq!(cache.stats().listed, 3);
        cache.clear_match_list(key);
        let cleared = cache.match_list(key);
        assert!(cleared.rows.is_empty() && !cleared.exhausted);
        drop(cache);
        let _ = std::fs::remove_dir_all(&dir);
    }
}
