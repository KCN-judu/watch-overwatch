//! The local store: one SQLite file under the user's data folder, `matches.db`: each
//! player's match list, finished-match details (with everyone who took part, and the rank
//! snapshot taken for each) and an index of who took part in which match.
//!
//! It holds other players' names and bnet ids (they are in the match details) but never
//! any token. Match details stored more than 180 days ago are dropped when the file opens;
//! match lists are kept, as they are only ever extended. Players' ranks are not kept
//! apart from the matches: the `ratings.db` of earlier versions is deleted.
//!
//! How the code is divided, so each kind of side effect has one home:
//!  - [`sql`]: every statement, generated from table declarations; no SQL anywhere else;
//!  - [`db`]: owns the connection, the lock, transactions and failure logging;
//!  - [`matches`]: typed reads and writes over a connection, nothing else
//!    (no clock, no files);
//!  - [`files`]: paths, sizes and carrying an older store over;
//!  - this module: the [`Clock`] (the only source of time), and the adapter that gives the
//!    collector the [`StrengthCache`] it asks for.
mod db;
mod files;
mod matches;
mod sql;

use db::Db;
use files::Layout;
use matches::ListId;
use serde::Serialize;
use sql::{SQL, VACUUM};
use std::{path::Path, sync::Arc};
use watch_core::{
    CachedDetail, ListKey, StoredList, StrengthCache,
    dashen::Mode,
    ir::{MatchDetail, MatchSummary},
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
    pub bytes: u64,
}

#[derive(Debug)]
pub struct LocalStore {
    matches: Db,
    layout: Layout,
    clock: Arc<dyn Clock>,
}

/// A detail fetched less than this long after its match ended may not be complete yet:
/// the provider could still be filling it in.
const SETTLING_MS: i64 = 60 * 60 * 1000;
/// Such a detail is fetched again once it is this old, until one fetched after the match
/// has settled replaces it.
const RECHECK_MS: i64 = 10 * 60 * 1000;

/// Whether a stored detail should be fetched again rather than used: it was read soon after
/// its match ended (see [`SETTLING_MS`]) and that was a while ago. A detail without a start
/// time cannot be judged and is used as it is.
fn provisional(detail: &MatchDetail, fetched_ms: i64, now_ms: i64) -> bool {
    let Some(start) = detail.started_at_ms else {
        return false;
    };
    let end = start + detail.duration_s.map_or(0, |s| (s * 1000.0) as i64);
    fetched_ms - end < SETTLING_MS && now_ms - fetched_ms > RECHECK_MS
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
    /// Opens the store in `dir` with the system clock.
    pub fn open(dir: &Path) -> rusqlite::Result<Self> {
        Self::open_with(dir, Arc::new(SystemClock))
    }

    /// Opens (creating if needed) the database in `dir`. What an older version kept in
    /// `strength.db` is moved over once; the rank cache of earlier versions is deleted.
    pub fn open_with(dir: &Path, clock: Arc<dyn Clock>) -> rusqlite::Result<Self> {
        let layout = Layout::new(dir);
        layout.ensure();
        let matches = Db::open("matches", &layout.matches_db(), &SQL.matches_schema, &[])?;
        let now = clock.now_ms();
        files::migrate_legacy(&layout, &matches);
        layout.remove_rank_cache();
        matches.write("drop old details", |tx| {
            matches::prune_details(tx, now - DETAIL_KEEP_MS)
        });
        matches.write("index participants", matches::backfill_participants);
        matches.write("upgrade rank snapshots", matches::upgrade_rank_snapshots);
        Ok(Self {
            matches,
            layout,
            clock,
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
            bytes: self.layout.bytes(),
        }
    }

    /// Remembers that `names` (any case) are the player `bnet_id`.
    pub fn remember_player(&self, names: &[&str], bnet_id: &str) {
        let lower: Vec<String> = names.iter().map(|n| n.to_lowercase()).collect();
        self.matches.write("remember a player", |tx| {
            matches::remember_names(tx, &lower, bnet_id)
        });
    }

    /// Keeps the profile (as JSON) last read for a player.
    pub fn remember_profile(&self, bnet_id: &str, json: &str) {
        self.matches.write("remember a profile", |tx| {
            matches::remember_profile(tx, bnet_id, json)
        });
    }

    /// Who `name` is, if it has been looked up before: the bnet id and the last profile.
    pub fn known_player(&self, name: &str) -> Option<(String, Option<String>)> {
        let lower = name.trim().to_lowercase();
        self.matches
            .read("recall a player", |c| {
                let Some(id) = matches::known_id(c, &lower)? else {
                    return Ok(None);
                };
                let profile = matches::known_profile(c, &id)?;
                Ok(Some((id, profile)))
            })
            .flatten()
    }

    /// `subject`'s stored matches with the player `name` (newest first, at most 3), as
    /// `(mode, match_id, bnet_id)`: a way to that player's token without a search.
    pub fn shared_matches(&self, subject: &str, name: &str) -> Vec<(Mode, String, String)> {
        let lower = name.trim().to_lowercase();
        self.matches
            .read("find shared matches", |c| {
                let id = matches::known_id(c, &lower)?;
                matches::shared_matches(c, subject, id.as_deref(), &lower)
            })
            .unwrap_or_default()
            .into_iter()
            .filter_map(|(mode, id, player)| Some((Mode::parse(&mode)?, id, player)))
            .collect()
    }

    /// Every stored match detail, whoever it was stored for.
    pub fn all_details(&self) -> Vec<MatchDetail> {
        self.matches
            .read("read all details", matches::all_details)
            .unwrap_or_default()
    }

    /// The provider's answer for a player's career in a finished season, if read before.
    pub fn past_career(&self, subject: &str, mode: Mode, season: u32) -> Option<String> {
        self.matches
            .read("read a past season", |c| {
                matches::past_career(c, subject, mode.provider_value(), i64::from(season))
            })
            .flatten()
    }

    /// Keeps a finished season's career; it is never read from the provider again.
    pub fn put_past_career(&self, subject: &str, mode: Mode, season: u32, data: &str) {
        self.matches.write("store a past season", |tx| {
            matches::put_past_career(tx, subject, mode.provider_value(), i64::from(season), data)
        });
    }

    /// Forgets everything.
    pub fn clear(&self) {
        self.matches.write("clear matches", matches::delete_all);
        let _ = self.matches.with(|c| c.execute_batch(VACUUM));
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
        let (kept, fetched_ms) = self
            .matches
            .read("read a match detail", |c| {
                matches::detail(c, mode.provider_value(), match_id, subject)
            })
            .flatten()?;
        // Not yet final: read it again (and store the new one) instead.
        (!provisional(&kept.detail, fetched_ms, self.clock.now_ms())).then_some(kept)
    }

    fn put_detail(&self, subject: &str, detail: &MatchDetail, unreachable: &[String]) {
        let now = self.clock.now_ms();
        self.matches.write("store a match detail", |tx| {
            matches::put_detail(tx, subject, detail, unreachable, now)
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use rusqlite::Connection;
    use std::sync::atomic::{AtomicI64, Ordering};
    use std::time::Duration;
    use watch_core::{
        Catalog,
        dashen::normalize,
        ir::{Bans, Outcome, OutcomeSource, Score},
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
        for (statements, schema) in [(SQL.for_matches(), &SQL.matches_schema)] {
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
    fn a_finished_season_is_kept_per_player_and_mode_and_forgotten_on_clear() {
        let dir = temp_dir("past-career");
        let store = LocalStore::open(&dir).unwrap();
        assert_eq!(store.past_career("1", Mode::Competitive, 24), None);
        store.put_past_career("1", Mode::Competitive, 24, r#"{"a":1}"#);
        assert_eq!(
            store.past_career("1", Mode::Competitive, 24).as_deref(),
            Some(r#"{"a":1}"#)
        );
        // Another mode, season or player is another row.
        assert_eq!(store.past_career("1", Mode::Quick, 24), None);
        assert_eq!(store.past_career("1", Mode::Competitive, 23), None);
        assert_eq!(store.past_career("2", Mode::Competitive, 24), None);
        // Kept across a restart.
        drop(store);
        let store = LocalStore::open(&dir).unwrap();
        assert!(store.past_career("1", Mode::Competitive, 24).is_some());
        store.clear();
        assert_eq!(store.past_career("1", Mode::Competitive, 24), None);
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
    fn a_name_is_remembered_with_its_last_profile_and_forgotten_on_clear() {
        let dir = temp_dir("names");
        {
            let store = LocalStore::open(&dir).unwrap();
            assert!(store.known_player("Scott#52183").is_none());
            store.remember_player(&["Scott#52183", "scott#52183"], "519735692");
            store.remember_profile("519735692", r#"{"name":"Scott#52183"}"#);
        }
        // Still there after a restart, found whatever the case and spaces.
        let store = LocalStore::open(&dir).unwrap();
        let (id, profile) = store.known_player("  sCOTT#52183 ").unwrap();
        assert_eq!(id, "519735692");
        assert_eq!(profile.as_deref(), Some(r#"{"name":"Scott#52183"}"#));
        assert!(store.known_player("someone#1").is_none());
        store.clear();
        assert!(store.known_player("Scott#52183").is_none());
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
    fn snapshots_in_an_old_format_are_dropped_on_opening_to_be_looked_up_again() {
        use watch_core::ir::RoleRanks;
        let path = format!(
            "{}/../watch-core/tests/fixtures/fightQueryMatchInfo.json",
            env!("CARGO_MANIFEST_DIR")
        );
        let Ok(bytes) = std::fs::read(&path) else {
            return;
        };
        let payload: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
        let detail = normalize::match_detail(
            "m1",
            normalize::payload(&payload),
            Mode::Quick,
            None,
            &Catalog::default(),
        );
        let dir = temp_dir("old-snapshots");
        let store = LocalStore::open(&dir).unwrap();
        store.put_detail("1001", &detail, &[]);
        drop(store);
        // As development builds of 1.4.0 left them: one rank and a time, or one state.
        let conn = Connection::open(dir.join("matches.db")).unwrap();
        let keys = rusqlite::params![Mode::Quick.provider_value(), detail.id, "1001"];
        let data: String = conn
            .query_row(&sql::SQL.detail.select, keys, |r| r.get(0))
            .unwrap();
        let mut v: serde_json::Value = serde_json::from_str(&data).unwrap();
        v["allies"][0]["career_rank"] = serde_json::json!({"skill_rating": 1850});
        v["allies"][0]["career_rank_at_ms"] = serde_json::json!(1000);
        // Stored JSON has sorted keys: `at_ms` comes before `state`.
        v["enemies"][0]["career"] = serde_json::json!({"at_ms": 2000, "state": "unranked"});
        conn.execute(
            sql::SET_DETAIL_DATA,
            rusqlite::params![
                v.to_string(),
                Mode::Quick.provider_value(),
                detail.id,
                "1001"
            ],
        )
        .unwrap();
        drop(conn);

        let store = LocalStore::open(&dir).unwrap();
        let kept = store
            .detail(Mode::Quick, &detail.id, "1001")
            .unwrap()
            .detail;
        assert_eq!(kept.allies[0].career, RoleRanks::default());
        assert_eq!(kept.enemies[0].career, RoleRanks::default());
        // The old fields are gone from what is stored, not only ignored when read.
        let conn = Connection::open(dir.join("matches.db")).unwrap();
        let keys = rusqlite::params![Mode::Quick.provider_value(), detail.id, "1001"];
        let data: String = conn
            .query_row(&sql::SQL.detail.select, keys, |r| r.get(0))
            .unwrap();
        assert!(!data.contains("career_rank") && !data.contains("\"at_ms\":2000"));
        drop(conn);
        drop(store);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_detail_read_just_after_its_match_is_read_again_until_it_has_settled() {
        let clock = ManualClock::new();
        let dir = temp_dir("settling");
        let store = LocalStore::open_with(&dir, clock.clone()).unwrap();
        let now = clock.now_ms();
        let detail = |at: i64| MatchDetail {
            id: "m".into(),
            mode: Mode::Quick,
            map: None,
            outcome: Outcome::Win,
            outcome_source: OutcomeSource::Provider,
            started_at_ms: Some(at),
            duration_s: Some(600.0),
            score: Score::default(),
            bans: Bans::default(),
            subject_heroes: Vec::new(),
            allies: Vec::new(),
            enemies: Vec::new(),
            rounds: Vec::new(),
        };
        // Started 20 minutes ago, ended 10 minutes ago: fetched before it settled.
        store.put_detail("1", &detail(now - 20 * 60_000), &[]);
        assert!(
            store.detail(Mode::Quick, "m", "1").is_some(),
            "fresh, use it"
        );
        clock.advance(Duration::from_secs(11 * 60));
        assert!(
            store.detail(Mode::Quick, "m", "1").is_none(),
            "read it again"
        );
        // Read again an hour and a half after the match ended: final from now on.
        clock.advance(Duration::from_secs(80 * 60));
        store.put_detail("1", &detail(now - 20 * 60_000), &[]);
        clock.advance(10 * DAY);
        assert!(store.detail(Mode::Quick, "m", "1").is_some());
        // A detail without a start time cannot be judged and is used as it is.
        let mut untimed = detail(0);
        untimed.id = "u".into();
        untimed.started_at_ms = None;
        store.put_detail("1", &untimed, &[]);
        clock.advance(DAY);
        assert!(store.detail(Mode::Quick, "u", "1").is_some());
        drop(store);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn the_rank_cache_of_earlier_versions_is_deleted_on_opening() {
        let dir = temp_dir("rank-cache");
        std::fs::create_dir_all(&dir).unwrap();
        for name in ["ratings.db", "ratings.db-wal"] {
            std::fs::write(dir.join(name), b"old").unwrap();
        }
        let store = LocalStore::open(&dir).unwrap();
        assert!(!dir.join("ratings.db").exists());
        assert!(!dir.join("ratings.db-wal").exists());
        drop(store);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn an_older_single_file_store_is_carried_over_once() {
        let dir = temp_dir("legacy");
        std::fs::create_dir_all(&dir).unwrap();
        let clock = ManualClock::new();
        {
            // What the single-file version had: all tables in strength.db.
            let old = Connection::open(dir.join("strength.db")).unwrap();
            for ddl in &SQL.matches_schema {
                old.execute(ddl, []).unwrap();
            }
            old.execute(
                &SQL.list.upsert,
                rusqlite::params!["1001", "sport", 0, "m1", 5, "{}"],
            )
            .unwrap();
        }
        let store = LocalStore::open_with(&dir, clock).unwrap();
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
        for name in ["db.rs", "matches.rs", "files.rs", "mod.rs"] {
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
