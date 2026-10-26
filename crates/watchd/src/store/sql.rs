//! Every SQL statement the local store runs, and nothing else in the program contains SQL.
//!
//! Tables are declared once as data ([`Table`]); the statements for them are generated
//! from that declaration when the program first needs them ([`SQL`]), so no query is ever
//! put together at the place that runs it, a column cannot be misspelled in one statement
//! and not another, and each statement is a fixed text with numbered parameters that
//! SQLite can cache a plan for. The tests prepare every statement against the real schema.
use std::sync::LazyLock;

/// One column: its name and everything that follows the name in its declaration.
pub struct Column {
    pub name: &'static str,
    pub decl: &'static str,
}

const fn col(name: &'static str, decl: &'static str) -> Column {
    Column { name, decl }
}

/// A table: its columns in storage order and its primary key.
pub struct Table {
    pub name: &'static str,
    pub columns: &'static [Column],
    pub key: &'static [&'static str],
}

impl Table {
    fn check(&self, columns: &[&str]) {
        for c in columns {
            assert!(
                self.columns.iter().any(|x| x.name == *c),
                "table {} has no column {c}",
                self.name
            );
        }
    }

    /// `a = ?1 AND b = ?2` over `by`, in that order.
    fn predicate(&self, by: &[&str]) -> String {
        self.check(by);
        by.iter()
            .enumerate()
            .map(|(i, c)| format!("{c} = ?{}", i + 1))
            .collect::<Vec<_>>()
            .join(" AND ")
    }

    fn filter(&self, by: &[&str]) -> String {
        if by.is_empty() {
            String::new()
        } else {
            format!(" WHERE {}", self.predicate(by))
        }
    }

    /// Create.
    pub fn create(&self) -> String {
        self.check(self.key);
        let columns: Vec<String> = self
            .columns
            .iter()
            .map(|c| format!("{} {}", c.name, c.decl))
            .collect();
        format!(
            "CREATE TABLE IF NOT EXISTS {}({}, PRIMARY KEY({}))",
            self.name,
            columns.join(", "),
            self.key.join(", ")
        )
    }

    /// Create or update: all columns in storage order as `?1..?n`; a row with the same
    /// key has its other columns replaced.
    pub fn upsert(&self) -> String {
        let names: Vec<&str> = self.columns.iter().map(|c| c.name).collect();
        let marks: Vec<String> = (1..=names.len()).map(|i| format!("?{i}")).collect();
        let updates: Vec<String> = names
            .iter()
            .filter(|n| !self.key.contains(n))
            .map(|n| format!("{n} = excluded.{n}"))
            .collect();
        let on_conflict = if updates.is_empty() {
            "DO NOTHING".to_owned()
        } else {
            format!("DO UPDATE SET {}", updates.join(", "))
        };
        format!(
            "INSERT INTO {} ({}) VALUES ({}) ON CONFLICT({}) {on_conflict}",
            self.name,
            names.join(", "),
            marks.join(", "),
            self.key.join(", ")
        )
    }

    /// Read: `columns` of the rows whose `by` columns equal `?1..`, optionally ordered.
    pub fn select(&self, columns: &[&str], by: &[&str], order: Option<&str>) -> String {
        self.check(columns);
        let order = order.map_or_else(String::new, |o| format!(" ORDER BY {o}"));
        format!(
            "SELECT {} FROM {}{}{order}",
            columns.join(", "),
            self.name,
            self.filter(by)
        )
    }

    /// Delete the rows whose `by` columns equal `?1..`.
    pub fn delete_where(&self, by: &[&str]) -> String {
        format!("DELETE FROM {}{}", self.name, self.filter(by))
    }

    /// Delete the rows whose `column` is below `?1`.
    pub fn delete_older(&self, column: &str) -> String {
        self.check(&[column]);
        format!("DELETE FROM {} WHERE {column} < ?1", self.name)
    }

    pub fn delete_all(&self) -> String {
        self.delete_where(&[])
    }

    pub fn count(&self) -> String {
        format!("SELECT COUNT(*) FROM {}", self.name)
    }

    pub fn count_distinct(&self, column: &str) -> String {
        self.check(&[column]);
        format!("SELECT COUNT(DISTINCT {column}) FROM {}", self.name)
    }

    /// Copy the rows of the same table in the attached database `schema`; with
    /// `at_least`, only those whose column is `>= ?1`. Rows already here win.
    pub fn copy_from(&self, schema: &str, at_least: Option<&str>) -> String {
        self.copy_columns_from(
            schema,
            &self.columns.iter().map(|c| c.name).collect::<Vec<_>>(),
            at_least,
        )
    }

    /// Like [`Table::copy_from`], for an attached table that has only these `columns`.
    pub fn copy_columns_from(
        &self,
        schema: &str,
        columns: &[&str],
        at_least: Option<&str>,
    ) -> String {
        self.check(columns);
        let list = columns.join(", ");
        let filter = at_least.map_or_else(String::new, |c| {
            self.check(&[c]);
            format!(" WHERE {c} >= ?1")
        });
        format!(
            "INSERT OR IGNORE INTO {name} ({list}) SELECT {list} FROM {schema}.{name}{filter}",
            name = self.name
        )
    }
}

// ---- Tables ---------------------------------------------------------------------------------

/// A finished match as one player saw it (its two teams are relative to them).
pub const MATCH_DETAIL: Table = Table {
    name: "match_detail",
    columns: &[
        col("mode", "TEXT NOT NULL"),
        col("match_id", "TEXT NOT NULL"),
        col("subject", "TEXT NOT NULL"),
        col("fetched_ms", "INTEGER NOT NULL"),
        col("unreachable", "TEXT NOT NULL"),
        col("data", "TEXT NOT NULL"),
    ],
    key: &["mode", "match_id", "subject"],
};

/// One row of a player's match list. `season` 0 is the current season.
pub const MATCH_LIST: Table = Table {
    name: "match_list",
    columns: &[
        col("subject", "TEXT NOT NULL"),
        col("mode", "TEXT NOT NULL"),
        col("season", "INTEGER NOT NULL"),
        col("match_id", "TEXT NOT NULL"),
        col("started_ms", "INTEGER"),
        col("data", "TEXT NOT NULL"),
    ],
    key: &["subject", "mode", "season", "match_id"],
};

/// Whether a stored match list reaches the player's oldest match.
pub const LIST_STATE: Table = Table {
    name: "list_state",
    columns: &[
        col("subject", "TEXT NOT NULL"),
        col("mode", "TEXT NOT NULL"),
        col("season", "INTEGER NOT NULL"),
        col("exhausted", "INTEGER NOT NULL"),
    ],
    key: &["subject", "mode", "season"],
};

/// Who took part in a stored match, on which side and in which role.
pub const PARTICIPANT: Table = Table {
    name: "match_participant",
    columns: &[
        col("subject", "TEXT NOT NULL"),
        col("mode", "TEXT NOT NULL"),
        col("match_id", "TEXT NOT NULL"),
        col("bnet_id", "TEXT NOT NULL"),
        col("side", "TEXT NOT NULL"),
        col("name", "TEXT"),
        col("role", "TEXT NOT NULL"),
    ],
    key: &["subject", "mode", "match_id", "bnet_id"],
};

/// Which player a name (lower-cased) belongs to, so a stored list can be shown before the
/// upstream has said who the name is.
pub const PLAYER_NAME: Table = Table {
    name: "player_name",
    columns: &[
        col("name_lower", "TEXT NOT NULL"),
        col("bnet_id", "TEXT NOT NULL"),
    ],
    key: &["name_lower"],
};

/// The last profile read for a player (as the JSON the app shows).
pub const PLAYER_PROFILE: Table = Table {
    name: "player_profile",
    columns: &[
        col("bnet_id", "TEXT NOT NULL"),
        col("data", "TEXT NOT NULL"),
    ],
    key: &["bnet_id"],
};

/// A player's career in a finished season (the provider's answer, as JSON). A finished
/// season never changes, so it is read once; the current season is not stored here.
pub const PAST_CAREER: Table = Table {
    name: "past_career",
    columns: &[
        col("subject", "TEXT NOT NULL"),
        col("mode", "TEXT NOT NULL"),
        col("season", "INTEGER NOT NULL"),
        col("data", "TEXT NOT NULL"),
    ],
    key: &["subject", "mode", "season"],
};

// ---- Fixed statements --------------------------------------------------------------------------

pub const PRAGMAS: &str = "PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;";
pub const VACUUM: &str = "VACUUM";
/// Details holding rank snapshots in a 1.4.0 development format: `career_rank*` fields, or
/// `career` as a single `{at_ms?, state, …}` instead of the three roles. Stored JSON has
/// its keys sorted, so the three roles always begin `"career":{"damage"`.
pub const OLD_RANK_SNAPSHOTS: &str = "SELECT mode, match_id, subject, data FROM match_detail \
     WHERE data LIKE '%\"career_rank%' \
     OR (data LIKE '%\"career\":{%' AND data NOT LIKE '%\"career\":{\"damage\"%')";
pub const SET_DETAIL_DATA: &str =
    "UPDATE match_detail SET data = ?1 WHERE mode = ?2 AND match_id = ?3 AND subject = ?4";
pub const ATTACH_LEGACY: &str = "ATTACH DATABASE ?1 AS legacy";
pub const DETACH_LEGACY: &str = "DETACH DATABASE legacy";
const PARTICIPANT_INDEX: &str =
    "CREATE INDEX IF NOT EXISTS participant_by_player ON match_participant(bnet_id)";
/// Participants whose match is no longer stored.
const PARTICIPANT_ORPHANS: &str = "DELETE FROM match_participant WHERE NOT EXISTS (
    SELECT 1 FROM match_detail d WHERE d.subject = match_participant.subject
    AND d.mode = match_participant.mode AND d.match_id = match_participant.match_id)";
/// `mode`, `match_id`, `bnet_id` of `?1`'s stored matches with the player `?2` (a bnet id)
/// or named `?3` (lower-cased), newest fetched first.
const PARTICIPANT_SHARED: &str = "SELECT p.mode, p.match_id, p.bnet_id FROM match_participant p
    JOIN match_detail d ON d.subject = p.subject AND d.mode = p.mode AND d.match_id = p.match_id
    WHERE p.subject = ?1 AND p.bnet_id <> ?1 AND (p.bnet_id = ?2 OR lower(p.name) = ?3)
    ORDER BY d.fetched_ms DESC LIMIT 3";

// ---- Generated statements ----------------------------------------------------------------------

pub struct ListSql {
    pub upsert: String,
    /// `data` of a list's rows (`?1` subject, `?2` mode, `?3` season), newest first.
    pub rows: String,
    pub delete: String,
    pub delete_all: String,
    pub count: String,
}

pub struct StateSql {
    pub upsert: String,
    pub select: String,
    pub delete: String,
    pub delete_all: String,
}

pub struct DetailSql {
    pub upsert: String,
    /// `data`, `unreachable`, `fetched_ms` of one detail (`?1` mode, `?2` match id,
    /// `?3` subject).
    pub select: String,
    /// `subject`, `data` of every detail.
    pub select_all: String,
    pub delete_older: String,
    pub count: String,
    pub delete_all: String,
}

pub struct PlayerSql {
    pub name_upsert: String,
    /// `bnet_id` for a lower-cased name (`?1`).
    pub name_select: String,
    pub profile_upsert: String,
    /// `data` for a bnet id (`?1`).
    pub profile_select: String,
    pub name_delete_all: String,
    pub profile_delete_all: String,
}

pub struct CareerSql {
    pub upsert: String,
    /// `data` of one finished season (`?1` subject, `?2` mode, `?3` season).
    pub select: String,
    pub delete_all: String,
}

pub struct ParticipantSql {
    pub upsert: String,
    pub delete_orphans: &'static str,
    pub shared: &'static str,
    pub count: String,
    pub count_players: String,
    pub delete_all: String,
}

/// Copying an older single-file store into the current one.
pub struct LegacySql {
    pub detail: String,
    pub list: String,
    pub state: String,
    pub participant: String,
}

pub struct Sql {
    pub matches_schema: Vec<String>,
    pub list: ListSql,
    pub state: StateSql,
    pub detail: DetailSql,
    pub participant: ParticipantSql,
    pub player: PlayerSql,
    pub career: CareerSql,
    pub legacy: LegacySql,
}

impl Sql {
    fn build() -> Self {
        let list_key = ["subject", "mode", "season"];
        Self {
            matches_schema: vec![
                MATCH_DETAIL.create(),
                MATCH_LIST.create(),
                LIST_STATE.create(),
                PARTICIPANT.create(),
                PARTICIPANT_INDEX.to_owned(),
                PLAYER_NAME.create(),
                PLAYER_PROFILE.create(),
                PAST_CAREER.create(),
            ],
            list: ListSql {
                upsert: MATCH_LIST.upsert(),
                rows: MATCH_LIST.select(
                    &["data"],
                    &list_key,
                    Some("started_ms IS NULL, started_ms DESC"),
                ),
                delete: MATCH_LIST.delete_where(&list_key),
                delete_all: MATCH_LIST.delete_all(),
                count: MATCH_LIST.count(),
            },
            state: StateSql {
                upsert: LIST_STATE.upsert(),
                select: LIST_STATE.select(&["exhausted"], &list_key, None),
                delete: LIST_STATE.delete_where(&list_key),
                delete_all: LIST_STATE.delete_all(),
            },
            detail: DetailSql {
                upsert: MATCH_DETAIL.upsert(),
                select: MATCH_DETAIL.select(
                    &["data", "unreachable", "fetched_ms"],
                    &["mode", "match_id", "subject"],
                    None,
                ),
                select_all: MATCH_DETAIL.select(&["subject", "data"], &[], None),
                delete_older: MATCH_DETAIL.delete_older("fetched_ms"),
                count: MATCH_DETAIL.count(),
                delete_all: MATCH_DETAIL.delete_all(),
            },
            participant: ParticipantSql {
                upsert: PARTICIPANT.upsert(),
                delete_orphans: PARTICIPANT_ORPHANS,
                shared: PARTICIPANT_SHARED,
                count: PARTICIPANT.count(),
                count_players: PARTICIPANT.count_distinct("bnet_id"),
                delete_all: PARTICIPANT.delete_all(),
            },
            player: PlayerSql {
                name_upsert: PLAYER_NAME.upsert(),
                name_select: PLAYER_NAME.select(&["bnet_id"], &["name_lower"], None),
                profile_upsert: PLAYER_PROFILE.upsert(),
                profile_select: PLAYER_PROFILE.select(&["data"], &["bnet_id"], None),
                name_delete_all: PLAYER_NAME.delete_all(),
                profile_delete_all: PLAYER_PROFILE.delete_all(),
            },
            career: CareerSql {
                upsert: PAST_CAREER.upsert(),
                select: PAST_CAREER.select(&["data"], &["subject", "mode", "season"], None),
                delete_all: PAST_CAREER.delete_all(),
            },
            legacy: LegacySql {
                detail: MATCH_DETAIL.copy_from("legacy", None),
                list: MATCH_LIST.copy_from("legacy", None),
                state: LIST_STATE.copy_from("legacy", None),
                participant: PARTICIPANT.copy_from("legacy", None),
            },
        }
    }

    /// Statements that run against `matches.db`, for validation.
    #[cfg(test)]
    pub fn for_matches(&self) -> Vec<&str> {
        let mut all: Vec<&str> = self.matches_schema.iter().map(String::as_str).collect();
        all.extend(
            [
                &self.list.upsert,
                &self.list.rows,
                &self.list.delete,
                &self.list.delete_all,
                &self.list.count,
                &self.state.upsert,
                &self.state.select,
                &self.state.delete,
                &self.state.delete_all,
                &self.detail.upsert,
                &self.detail.select,
                &self.detail.select_all,
                &self.detail.delete_older,
                &self.detail.count,
                &self.detail.delete_all,
                &self.participant.upsert,
                &self.participant.count,
                &self.participant.count_players,
                &self.participant.delete_all,
                &self.player.name_upsert,
                &self.player.name_select,
                &self.player.profile_upsert,
                &self.player.profile_select,
                &self.player.name_delete_all,
                &self.player.profile_delete_all,
                &self.career.upsert,
                &self.career.select,
                &self.career.delete_all,
            ]
            .map(String::as_str),
        );
        all.push(self.participant.delete_orphans);
        all.push(self.participant.shared);
        all
    }
}

/// All statements, generated once on first use.
pub static SQL: LazyLock<Sql> = LazyLock::new(Sql::build);

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn generated_statements_have_the_expected_shape() {
        assert_eq!(
            PAST_CAREER.upsert(),
            "INSERT INTO past_career (subject, mode, season, data) \
             VALUES (?1, ?2, ?3, ?4) ON CONFLICT(subject, mode, season) \
             DO UPDATE SET data = excluded.data"
        );
        assert_eq!(
            SQL.career.select,
            "SELECT data FROM past_career WHERE subject = ?1 AND mode = ?2 AND season = ?3"
        );
        assert_eq!(
            SQL.list.delete,
            "DELETE FROM match_list WHERE subject = ?1 AND mode = ?2 AND season = ?3"
        );
        assert_eq!(
            SQL.detail.delete_older,
            "DELETE FROM match_detail WHERE fetched_ms < ?1"
        );
        // A table that is all key has nothing to update.
        assert!(
            Table {
                name: "t",
                columns: &[Column {
                    name: "a",
                    decl: "TEXT"
                }],
                key: &["a"],
            }
            .upsert()
            .ends_with("DO NOTHING")
        );
    }

    #[test]
    #[should_panic(expected = "has no column")]
    fn a_statement_naming_a_missing_column_cannot_be_generated() {
        let _ = PAST_CAREER.select(&["data"], &["nobody"], None);
    }
}
