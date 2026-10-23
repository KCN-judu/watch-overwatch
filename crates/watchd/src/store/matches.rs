//! Match lists, finished-match details and who took part in them (`matches.db`).
//! Plain functions over a connection or transaction: no locking, no clock, no files, no
//! logging; the caller ([`super::LocalStore`]) supplies those.
use rusqlite::{Connection, OptionalExtension, Transaction, params};
use watch_core::{
    CachedDetail,
    ir::{MatchDetail, MatchSummary},
};

use super::sql::SQL;

/// Which stored list: whose, which mode, which season (0 is the current one).
#[derive(Clone, Copy)]
pub struct ListId<'a> {
    pub subject: &'a str,
    pub mode: &'a str,
    pub season: i64,
}

#[derive(Debug, Default, PartialEq, Eq)]
pub struct Counts {
    pub details: usize,
    pub listed: usize,
    pub players: usize,
}

fn count(conn: &Connection, sql: &str) -> rusqlite::Result<usize> {
    let n: i64 = conn.prepare_cached(sql)?.query_row([], |r| r.get(0))?;
    Ok(n.max(0) as usize)
}

// ---- match lists ---------------------------------------------------------------------------------

/// The stored rows of a list, newest first. A row that no longer parses (the format moved
/// on) is left out; the next read of the list fetches it again.
pub fn list_rows(conn: &Connection, id: ListId<'_>) -> rusqlite::Result<Vec<MatchSummary>> {
    let mut statement = conn.prepare_cached(&SQL.list.rows)?;
    let rows = statement.query_map(params![id.subject, id.mode, id.season], |r| {
        r.get::<_, String>(0)
    })?;
    Ok(rows
        .filter_map(Result::ok)
        .filter_map(|data| serde_json::from_str(&data).ok())
        .collect())
}

pub fn list_exhausted(conn: &Connection, id: ListId<'_>) -> rusqlite::Result<bool> {
    let flag: Option<i64> = conn
        .prepare_cached(&SQL.state.select)?
        .query_row(params![id.subject, id.mode, id.season], |r| r.get(0))
        .optional()?;
    Ok(flag.is_some_and(|f| f != 0))
}

/// Adds rows to a list; a row already there is replaced.
pub fn upsert_rows(
    tx: &Transaction<'_>,
    id: ListId<'_>,
    rows: &[MatchSummary],
) -> rusqlite::Result<()> {
    let mut statement = tx.prepare_cached(&SQL.list.upsert)?;
    for m in rows {
        let Ok(data) = serde_json::to_string(m) else {
            continue;
        };
        statement.execute(params![
            id.subject,
            id.mode,
            id.season,
            m.id,
            m.started_at_ms,
            data
        ])?;
    }
    Ok(())
}

pub fn set_list_exhausted(
    tx: &Transaction<'_>,
    id: ListId<'_>,
    exhausted: bool,
) -> rusqlite::Result<()> {
    tx.prepare_cached(&SQL.state.upsert)?.execute(params![
        id.subject,
        id.mode,
        id.season,
        exhausted as i64
    ])?;
    Ok(())
}

/// Removes a list and its completeness flag.
pub fn delete_list(tx: &Transaction<'_>, id: ListId<'_>) -> rusqlite::Result<()> {
    let args = params![id.subject, id.mode, id.season];
    tx.prepare_cached(&SQL.list.delete)?.execute(args)?;
    tx.prepare_cached(&SQL.state.delete)?.execute(args)?;
    Ok(())
}

// ---- details and participants --------------------------------------------------------------------

/// The detail of a match as `subject` saw it, and when it was fetched. One that no longer
/// parses is a miss.
pub fn detail(
    conn: &Connection,
    mode: &str,
    match_id: &str,
    subject: &str,
) -> rusqlite::Result<Option<(CachedDetail, i64)>> {
    let row: Option<(String, String, i64)> = conn
        .prepare_cached(&SQL.detail.select)?
        .query_row(params![mode, match_id, subject], |r| {
            Ok((r.get(0)?, r.get(1)?, r.get(2)?))
        })
        .optional()?;
    Ok(row.and_then(|(data, unreachable, fetched_ms)| {
        Some((
            CachedDetail {
                detail: serde_json::from_str(&data).ok()?,
                unreachable: serde_json::from_str(&unreachable).unwrap_or_default(),
            },
            fetched_ms,
        ))
    }))
}

/// Stores a detail and the index of its participants together, stamped `now_ms`.
pub fn put_detail(
    tx: &Transaction<'_>,
    subject: &str,
    detail: &MatchDetail,
    unreachable: &[String],
    now_ms: i64,
) -> rusqlite::Result<()> {
    // A match read again keeps the rank snapshots taken for it before.
    let mut detail = detail.clone();
    if let Some((old, _)) = self::detail(tx, detail.mode.provider_value(), &detail.id, subject)? {
        watch_core::snapshot::carry(&mut detail, &old.detail);
    }
    let detail = &detail;
    let (Ok(data), Ok(unreachable)) = (
        serde_json::to_string(detail),
        serde_json::to_string(unreachable),
    ) else {
        return Ok(());
    };
    tx.prepare_cached(&SQL.detail.upsert)?.execute(params![
        detail.mode.provider_value(),
        detail.id,
        subject,
        now_ms,
        unreachable,
        data
    ])?;
    index_participants(tx, subject, detail)
}

/// Who took part in a match and on which side, findable without opening the detail.
fn index_participants(
    tx: &Transaction<'_>,
    subject: &str,
    detail: &MatchDetail,
) -> rusqlite::Result<()> {
    let mut statement = tx.prepare_cached(&SQL.participant.upsert)?;
    for (side, people) in [("ally", &detail.allies), ("enemy", &detail.enemies)] {
        for p in people {
            let Some(id) = p.bnet_id.as_deref() else {
                continue;
            };
            statement.execute(params![
                subject,
                detail.mode.provider_value(),
                detail.id,
                id,
                side,
                p.name,
                p.role.id()
            ])?;
        }
    }
    Ok(())
}

/// Every stored detail (any subject), for figures drawn from all of them (peer benchmarks).
pub fn all_details(conn: &Connection) -> rusqlite::Result<Vec<MatchDetail>> {
    Ok(conn
        .prepare_cached(&SQL.detail.select_all)?
        .query_map([], |r| r.get::<_, String>(1))?
        .filter_map(Result::ok)
        .filter_map(|data| serde_json::from_str(&data).ok())
        .collect())
}
/// Details stored before the participant index existed are added to it, once: only when
/// the index is empty and there are details.
pub fn backfill_participants(tx: &Transaction<'_>) -> rusqlite::Result<()> {
    if count(tx, &SQL.participant.count)? > 0 || count(tx, &SQL.detail.count)? == 0 {
        return Ok(());
    }
    let stored: Vec<(String, String)> = tx
        .prepare_cached(&SQL.detail.select_all)?
        .query_map([], |r| Ok((r.get(0)?, r.get(1)?)))?
        .filter_map(Result::ok)
        .collect();
    for (subject, data) in stored {
        if let Ok(detail) = serde_json::from_str::<MatchDetail>(&data) {
            index_participants(tx, &subject, &detail)?;
        }
    }
    Ok(())
}

// ---- who a name is ----------------------------------------------------------------------------

/// Remembers that these (lower-cased) names are this player.
pub fn remember_names(
    tx: &Transaction<'_>,
    names: &[String],
    bnet_id: &str,
) -> rusqlite::Result<()> {
    let mut statement = tx.prepare_cached(&SQL.player.name_upsert)?;
    for name in names {
        statement.execute(params![name, bnet_id])?;
    }
    Ok(())
}

pub fn remember_profile(tx: &Transaction<'_>, bnet_id: &str, data: &str) -> rusqlite::Result<()> {
    tx.prepare_cached(&SQL.player.profile_upsert)?
        .execute(params![bnet_id, data])?;
    Ok(())
}

/// The bnet id a (lower-cased) name was last seen to be, if any.
pub fn known_id(conn: &Connection, name_lower: &str) -> rusqlite::Result<Option<String>> {
    conn.prepare_cached(&SQL.player.name_select)?
        .query_row([name_lower], |r| r.get(0))
        .optional()
}

pub fn known_profile(conn: &Connection, bnet_id: &str) -> rusqlite::Result<Option<String>> {
    conn.prepare_cached(&SQL.player.profile_select)?
        .query_row([bnet_id], |r| r.get(0))
        .optional()
}

/// A stored career of a finished season (the provider's answer as JSON), if any.
pub fn past_career(
    conn: &Connection,
    subject: &str,
    mode: &str,
    season: i64,
) -> rusqlite::Result<Option<String>> {
    conn.prepare_cached(&SQL.career.select)?
        .query_row(params![subject, mode, season], |r| r.get(0))
        .optional()
}

pub fn put_past_career(
    tx: &Transaction<'_>,
    subject: &str,
    mode: &str,
    season: i64,
    data: &str,
) -> rusqlite::Result<()> {
    tx.prepare_cached(&SQL.career.upsert)?
        .execute(params![subject, mode, season, data])?;
    Ok(())
}

// ---- upkeep ----------------------------------------------------------------------------------------

/// Drops details fetched before `cutoff_ms` and the participants left without a match.
pub fn prune_details(tx: &Transaction<'_>, cutoff_ms: i64) -> rusqlite::Result<()> {
    tx.prepare_cached(&SQL.detail.delete_older)?
        .execute([cutoff_ms])?;
    tx.execute(SQL.participant.delete_orphans, [])?;
    Ok(())
}

pub fn counts(conn: &Connection) -> rusqlite::Result<Counts> {
    Ok(Counts {
        details: count(conn, &SQL.detail.count)?,
        listed: count(conn, &SQL.list.count)?,
        players: count(conn, &SQL.participant.count_players)?,
    })
}

/// Forgets every list, detail and participant.
pub fn delete_all(tx: &Transaction<'_>) -> rusqlite::Result<()> {
    for sql in [
        &SQL.detail.delete_all,
        &SQL.participant.delete_all,
        &SQL.list.delete_all,
        &SQL.state.delete_all,
        &SQL.player.name_delete_all,
        &SQL.player.profile_delete_all,
        &SQL.career.delete_all,
    ] {
        tx.execute(sql, [])?;
    }
    Ok(())
}

/// Rank snapshots stored by a development build of 1.4.0 (`career_rank`,
/// `career_other_roles`, `career_rank_at_ms` on each participant) rewritten once into the
/// three states (`career`): ranked with the rank, or unranked, both with when.
pub fn upgrade_rank_snapshots(tx: &Transaction<'_>) -> rusqlite::Result<()> {
    let old: Vec<(String, String, String, String)> = tx
        .prepare(super::sql::OLD_RANK_SNAPSHOTS)?
        .query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?)))?
        .filter_map(Result::ok)
        .collect();
    let mut update = tx.prepare(super::sql::SET_DETAIL_DATA)?;
    for (mode, match_id, subject, data) in old {
        let Ok(mut v) = serde_json::from_str::<serde_json::Value>(&data) else {
            continue;
        };
        for side in ["allies", "enemies"] {
            let Some(people) = v[side].as_array_mut() else {
                continue;
            };
            for p in people {
                let Some(p) = p.as_object_mut() else { continue };
                let at = p.remove("career_rank_at_ms").filter(|a| !a.is_null());
                let rank = p.remove("career_rank").filter(|r| !r.is_null());
                let other = p.remove("career_other_roles").and_then(|o| o.as_bool());
                let Some(at) = at else { continue };
                p.insert(
                    "career".into(),
                    match rank {
                        Some(rank) => serde_json::json!({
                            "state": "ranked", "rank": rank,
                            "other_roles": other.unwrap_or(false), "at_ms": at,
                        }),
                        None => serde_json::json!({"state": "unranked", "at_ms": at}),
                    },
                );
            }
        }
        update.execute(params![v.to_string(), mode, match_id, subject])?;
    }
    Ok(())
}
