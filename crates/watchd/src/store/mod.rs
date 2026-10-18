//! The local store: two SQLite files under the user's data folder.
//!
//!  - `matches.db`: each player's match list, finished-match details (with everyone who
//!    took part) and an index of who took part in which match;
//!  - `ratings.db`: players' competitive ranks, one row per player and season, stamped
//!    with when they were fetched. A row older than [`watch_core::RATINGS_TTL`] counts as
//!    missing and is overwritten by the next lookup.
//!
//! It holds other players' names and bnet ids (they are in the match details) but never
//! any token. Match details stored more than 180 days ago are dropped when the files
//! open, expired ranks too; match lists are kept, as they are only ever extended.
//!
//! How the code is divided, so each kind of side effect has one home:
//!  - [`sql`]: every statement, generated from table declarations; no SQL anywhere else;
//!  - [`db`]: owns the connection, the lock, transactions and failure logging;
//!  - [`matches`], [`ratings`]: typed reads and writes over a connection, nothing else
//!    (no clock, no files);
//!  - [`files`]: paths, sizes and carrying an older store over;
//!  - this module: the [`Clock`] (the only source of time), and the adapter that gives the
//!    collector the [`StrengthCache`] it asks for.
mod db;
mod files;
mod matches;
mod ratings;
mod sql;

use db::Db;
use files::Layout;
use matches::ListId;
use serde::Serialize;
use sql::{SQL, VACUUM};
use std::{path::Path, sync::Arc, time::Duration};
use watch_core::{
    CachedDetail, ListKey, RATINGS_TTL, StoredList, StrengthCache,
    dashen::Mode,
    ir::{MatchDetail, MatchSummary, RoleRating},
};

/// How long a stored match detail is kept.
const DETAIL_KEEP_MS: i64 = 180 * 24 * 3600 * 1000;

/// The source of the current time, so that nothing in the store reads the system clock
/// and a test can move time itself.
pub trait Clock: Send + Sync + std::fmt::Debug {
    fn now_ms(&self) -> i64;
}

#[derive(Debug)]
pub struct SystemClock;

impl Clock for SystemClock {
    fn now_ms(&self) -> i64 {
        watch_core::now_ms() as i64
    }
}

#[derive(Debug, Clone, Serialize)]
pub struct CacheStats {
    /// Stored match details.
    pub matches: usize,
    /// Matches in the stored match lists.
    pub listed: usize,
    /// Distinct players seen in stored matches.
    pub participants: usize,
    /// Players with at least one stored season of ranks.
    pub players: usize,
    pub bytes: u64,
}

#[derive(Debug)]
pub struct LocalStore {
    matches: Db,
    ratings: Db,
    layout: Layout,
    clock: Arc<dyn Clock>,
    ratings_ttl_ms: i64,
}

/// The season column: 0 stands for the current season.
fn season_key(season: Option<u32>) -> i64 {
    season.map_or(0, i64::from)
}

fn list_id<'a>(key: &ListKey<'a>) -> ListId<'a> {
    ListId {
        subject: key.subject,
        mode: key.mode.provider_value(),
        season: season_key(key.season),
    }
}

impl LocalStore {
    /// Opens the store in `dir` with the system clock and the standard rank lifetime.
    pub fn open(dir: &Path) -> rusqlite::Result<Self> {
        Self::open_with(dir, Arc::new(SystemClock), RATINGS_TTL)
    }

    /// Opens (creating if needed) the two databases in `dir`. What an older version kept in
    /// `strength.db` is moved over once.
    pub fn open_with(
        dir: &Path,
        clock: Arc<dyn Clock>,
        ratings_ttl: Duration,
    ) -> rusqlite::Result<Self> {
        let layout = Layout::new(dir);
        layout.ensure();
        let matches = Db::open("matches", &layout.matches_db(), &SQL.matches_schema)?;
        let ratings = Db::open("ratings", &layout.ratings_db(), &SQL.ratings_schema)?;
        let now = clock.now_ms();
        let ratings_ttl_ms = ratings_ttl.as_millis() as i64;
        files::migrate_legacy(&layout, &matches, &ratings, now - ratings_ttl_ms);
        matches.write("drop old details", |tx| {
            matches::prune_details(tx, now - DETAIL_KEEP_MS)
        });
        matches.write("index participants", matches::backfill_participants);
        // Expired ranks would only ever be overwritten: do not keep them.
        ratings.write("drop expired ranks", |tx| {
            ratings::prune(tx, now - ratings_ttl_ms)
        });
        Ok(Self {
            matches,
            ratings,
            layout,
            clock,
            ratings_ttl_ms,
        })
    }

    pub fn stats(&self) -> CacheStats {
        let counts = self
            .matches
            .read("count matches", matches::counts)
            .unwrap_or_default();
        CacheStats {
            matches: counts.details,
            listed: counts.listed,
            participants: counts.players,
            players: self
                .ratings
                .read("count players", ratings::players)
                .unwrap_or(0),
            bytes: self.layout.bytes(),
        }
    }

    /// Forgets everything, in both databases.
    pub fn clear(&self) {
        self.matches.write("clear matches", matches::delete_all);
        self.ratings.write("clear ratings", ratings::delete_all);
        for db in [&self.matches, &self.ratings] {
            let _ = db.with(|c| c.execute_batch(VACUUM));
        }
    }
}

impl StrengthCache for LocalStore {
    fn match_list(&self, key: ListKey<'_>) -> StoredList {
        let id = list_id(&key);
        self.matches
            .read("read the match list", |c| {
                Ok(StoredList {
                    rows: matches::list_rows(c, id)?,
                    exhausted: matches::list_exhausted(c, id)?,
                })
            })
            .unwrap_or_default()
    }

    fn put_match_rows(&self, key: ListKey<'_>, rows: &[MatchSummary]) {
        let id = list_id(&key);
        self.matches
            .write("store match rows", |tx| matches::upsert_rows(tx, id, rows));
    }

    fn set_list_exhausted(&self, key: ListKey<'_>, exhausted: bool) {
        let id = list_id(&key);
        self.matches.write("store the list state", |tx| {
            matches::set_list_exhausted(tx, id, exhausted)
        });
    }

    fn clear_match_list(&self, key: ListKey<'_>) {
        let id = list_id(&key);
        self.matches
            .write("clear a match list", |tx| matches::delete_list(tx, id));
    }

    fn detail(&self, mode: Mode, match_id: &str, subject: &str) -> Option<CachedDetail> {
        self.matches
            .read("read a match detail", |c| {
                matches::detail(c, mode.provider_value(), match_id, subject)
            })
            .flatten()
    }

    fn put_detail(&self, subject: &str, detail: &MatchDetail, unreachable: &[String]) {
        let now = self.clock.now_ms();
        self.matches.write("store a match detail", |tx| {
            matches::put_detail(tx, subject, detail, unreachable, now)
        });
    }

    fn season_ratings(&self, bnet_id: &str, season: u32) -> Option<Vec<RoleRating>> {
        let (fetched, ratings) = self
            .ratings
            .read("read ranks", |c| ratings::get(c, bnet_id, season))
            .flatten()?;
        // Past its lifetime counts as missing: the caller fetches and overwrites it.
        (self.clock.now_ms().saturating_sub(fetched) <= self.ratings_ttl_ms).then_some(ratings)
    }

    fn put_season_ratings(&self, bnet_id: &str, season: u32, ratings: &[RoleRating]) {
        let now = self.clock.now_ms();
        self.ratings.write("store ranks", |tx| {
            ratings::put(tx, bnet_id, season, ratings, now)
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use rusqlite::Connection;
    use std::sync::atomic::{AtomicI64, Ordering};
    use watch_core::{
        Catalog,
        dashen::normalize,
        ir::{Rank, Role},
    };

    /// A clock the test moves by hand.
    #[derive(Debug)]
    struct ManualClock(AtomicI64);

    impl ManualClock {
        fn new() -> Arc<Self> {
            Arc::new(Self(AtomicI64::new(1_700_000_000_000)))
        }
        fn advance(&self, by: Duration) {
            self.0.fetch_add(by.as_millis() as i64, Ordering::SeqCst);
        }
    }

    impl Clock for ManualClock {
        fn now_ms(&self) -> i64 {
            self.0.load(Ordering::SeqCst)
        }
    }

    const DAY: Duration = Duration::from_secs(24 * 3600);

    fn temp_dir(tag: &str) -> std::path::PathBuf {
        let dir = std::env::temp_dir().join(format!("wo-store-{tag}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        dir
    }

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

    fn summary(id: &str, at: i64) -> MatchSummary {
        let row = serde_json::json!({"matchId": id, "beginTs": at, "roleType": "tank"});
        normalize::match_list(&serde_json::json!([row]), Mode::Quick, &Catalog::default()).remove(0)
    }

    fn key(subject: &str) -> ListKey<'_> {
        ListKey {
            subject,
            mode: Mode::Quick,
            season: None,
        }
    }

    #[test]
    fn every_statement_is_valid_against_the_schema() {
        for (statements, schema) in [
            (SQL.for_matches(), &SQL.matches_schema),
            (SQL.for_ratings(), &SQL.ratings_schema),
        ] {
            let conn = Connection::open_in_memory().unwrap();
            for ddl in schema {
                conn.execute(ddl, []).unwrap();
            }
            for sql in statements {
                conn.prepare(sql)
                    .unwrap_or_else(|e| panic!("does not prepare: {sql}\n{e}"));
            }
        }
    }

    #[test]
    fn ranks_expire_after_their_lifetime_and_the_next_lookup_overwrites_them() {
        let dir = temp_dir("ratings");
        let clock = ManualClock::new();
        let store = LocalStore::open_with(&dir, clock.clone(), RATINGS_TTL).unwrap();
        assert!(store.season_ratings("1", 25).is_none());
        store.put_season_ratings("1", 25, &[rating(Role::Tank, 2300)]);
        store.put_season_ratings("1", 24, &[rating(Role::Tank, 2000)]);

        clock.advance(2 * DAY);
        let kept = store.season_ratings("1", 25).unwrap();
        assert_eq!(kept[0].rank.skill_rating, Some(2300));

        // Past three days every season is a miss, past seasons included.
        clock.advance(2 * DAY);
        assert!(store.season_ratings("1", 25).is_none());
        assert!(store.season_ratings("1", 24).is_none());

        // The lookup that follows overwrites the row and stamps it again.
        store.put_season_ratings("1", 25, &[rating(Role::Tank, 2400)]);
        assert_eq!(
            store.season_ratings("1", 25).unwrap()[0].rank.skill_rating,
            Some(2400)
        );
        assert_eq!(
            store.stats().players,
            1,
            "one player, however often it is replaced"
        );
        // Other players and seasons are separate.
        assert!(store.season_ratings("2", 25).is_none());
        store.clear();
        assert_eq!(store.stats().players, 0);
        drop(store);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn expired_ranks_are_dropped_when_the_store_opens() {
        let dir = temp_dir("prune");
        let clock = ManualClock::new();
        {
            let store = LocalStore::open_with(&dir, clock.clone(), RATINGS_TTL).unwrap();
            store.put_season_ratings("1", 25, &[rating(Role::Tank, 2300)]);
        }
        clock.advance(4 * DAY);
        let store = LocalStore::open_with(&dir, clock, RATINGS_TTL).unwrap();
        assert_eq!(store.stats().players, 0);
        drop(store);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn match_lists_persist_per_player_mode_and_season_and_can_be_reset() {
        let dir = temp_dir("lists");
        let k = key("1001");
        {
            let store = LocalStore::open(&dir).unwrap();
            assert!(store.match_list(k).rows.is_empty());
            store.put_match_rows(k, &[summary("a", 10), summary("b", 30), summary("c", 20)]);
            store.set_list_exhausted(k, true);
        }
        // Reopened: still there, newest first, and the flag survived.
        let store = LocalStore::open(&dir).unwrap();
        let stored = store.match_list(k);
        let ids: Vec<_> = stored.rows.iter().map(|m| m.id.as_str()).collect();
        assert_eq!(ids, ["b", "c", "a"]);
        assert!(stored.exhausted);
        // Another player, mode or season has its own list.
        assert!(store.match_list(key("2")).rows.is_empty());
        assert!(
            store
                .match_list(ListKey {
                    mode: Mode::Competitive,
                    ..k
                })
                .rows
                .is_empty()
        );
        assert!(
            store
                .match_list(ListKey {
                    season: Some(24),
                    ..k
                })
                .rows
                .is_empty()
        );
        // Rows are replaced, not doubled.
        store.put_match_rows(k, &[summary("a", 10)]);
        assert_eq!(store.match_list(k).rows.len(), 3);
        assert_eq!(store.stats().listed, 3);
        store.clear_match_list(k);
        let cleared = store.match_list(k);
        assert!(cleared.rows.is_empty() && !cleared.exhausted);
        drop(store);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_detail_is_stored_with_its_participants_and_unreachable_players() {
        let path = format!(
            "{}/../watch-core/tests/fixtures/fightQueryMatchInfo.json",
            env!("CARGO_MANIFEST_DIR")
        );
        let Ok(bytes) = std::fs::read(&path) else {
            return; // the fixture is part of the core crate's tests
        };
        let payload: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
        let detail = normalize::match_detail(
            "m1",
            normalize::payload(&payload),
            Mode::Quick,
            None,
            &Catalog::default(),
        );
        let dir = temp_dir("detail");
        let store = LocalStore::open(&dir).unwrap();
        assert!(store.detail(Mode::Quick, &detail.id, "1001").is_none());
        store.put_detail("1001", &detail, &["999".to_owned()]);
        let kept = store.detail(Mode::Quick, &detail.id, "1001").unwrap();
        assert_eq!(kept.detail.id, detail.id);
        assert_eq!(kept.unreachable, ["999"]);
        // Stored again, still one detail; another subject's copy is separate.
        store.put_detail("1001", &detail, &[]);
        assert_eq!(store.stats().matches, 1);
        assert!(store.detail(Mode::Quick, &detail.id, "2002").is_none());
        let people = detail
            .allies
            .iter()
            .chain(&detail.enemies)
            .filter(|p| p.bnet_id.is_some())
            .count();
        assert_eq!(store.stats().participants > 0, people > 0);
        drop(store);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn an_older_single_file_store_is_carried_over_once() {
        let dir = temp_dir("legacy");
        std::fs::create_dir_all(&dir).unwrap();
        let clock = ManualClock::new();
        let now = clock.now_ms();
        {
            // What the single-file version had: all tables in strength.db.
            let old = Connection::open(dir.join("strength.db")).unwrap();
            for ddl in SQL.matches_schema.iter().chain(&SQL.ratings_schema) {
                old.execute(ddl, []).unwrap();
            }
            let upsert = &SQL.rating.upsert;
            old.execute(upsert, rusqlite::params!["1", 25, now, "[]"])
                .unwrap();
            // One already past its lifetime: not carried over.
            let stale = now - (RATINGS_TTL.as_millis() as i64) - 1;
            old.execute(upsert, rusqlite::params!["2", 25, stale, "[]"])
                .unwrap();
            old.execute(
                &SQL.list.upsert,
                rusqlite::params!["1001", "sport", 0, "m1", 5, "{}"],
            )
            .unwrap();
        }
        let store = LocalStore::open_with(&dir, clock, RATINGS_TTL).unwrap();
        assert_eq!(store.stats().players, 1);
        assert_eq!(store.stats().listed, 1);
        assert!(!dir.join("strength.db").exists(), "the old file is removed");
        drop(store);
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// SQL lives in `store/sql.rs` and nowhere else: no other source file of the program
    /// may contain a statement or use the database library.
    #[test]
    fn sql_is_confined_to_the_sql_module() {
        // Built from pieces so that this test does not contain what it looks for.
        let words: Vec<String> = [
            ["SEL", "ECT "],
            ["INS", "ERT "],
            ["DEL", "ETE FROM"],
            ["UPD", "ATE "],
            ["CREATE ", "TABLE"],
            ["ATT", "ACH DATABASE"],
            ["PRA", "GMA"],
            ["rus", "qlite"],
        ]
        .iter()
        .map(|p| p.concat())
        .collect();
        let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("..");
        let mut files = Vec::new();
        for crate_src in ["watchd/src", "watch-core/src"] {
            collect(&root.join(crate_src), &mut files);
        }
        let allowed = [
            Path::new("store").join("sql.rs"),
            Path::new("store").join("db.rs"),
            Path::new("store").join("matches.rs"),
            Path::new("store").join("ratings.rs"),
            Path::new("store").join("files.rs"),
            Path::new("store").join("mod.rs"),
        ];
        let mut offenders = Vec::new();
        for file in files {
            if allowed.iter().any(|a| file.ends_with(a)) {
                continue;
            }
            let text = std::fs::read_to_string(&file).unwrap();
            for w in &words {
                if text.contains(w.as_str()) {
                    offenders.push(format!("{} contains {w:?}", file.display()));
                }
            }
        }
        assert!(
            offenders.is_empty(),
            "SQL outside the store: {offenders:#?}"
        );
    }

    fn collect(dir: &Path, out: &mut Vec<std::path::PathBuf>) {
        for entry in std::fs::read_dir(dir).unwrap().flatten() {
            let path = entry.path();
            if path.is_dir() {
                collect(&path, out);
            } else if path.extension().is_some_and(|e| e == "rs") {
                out.push(path);
            }
        }
    }

    /// Statements are text the generator wrote, never built from values at the call site:
    /// only `sql.rs` may format SQL, and the other store files hold no statement text.
    #[test]
    fn the_store_files_other_than_sql_hold_no_statement_text() {
        let words: Vec<String> = [
            ["SEL", "ECT "],
            ["INS", "ERT "],
            ["DEL", "ETE FROM"],
            ["CREATE ", "TABLE"],
        ]
        .iter()
        .map(|p| p.concat())
        .collect();
        for name in ["db.rs", "matches.rs", "ratings.rs", "files.rs", "mod.rs"] {
            let path = Path::new(env!("CARGO_MANIFEST_DIR"))
                .join("src/store")
                .join(name);
            let text = std::fs::read_to_string(&path).unwrap();
            // mod.rs holds this test, which names them in pieces only.
            for w in &words {
                assert!(!text.contains(w.as_str()), "{name} contains {w:?}");
            }
        }
    }
}
