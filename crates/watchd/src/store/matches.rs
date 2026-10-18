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

/// The detail of a match as `subject` saw it. One that no longer parses is a miss.
pub fn detail(
    conn: &Connection,
    mode: &str,
    match_id: &str,
    subject: &str,
) -> rusqlite::Result<Option<CachedDetail>> {
    let row: Option<(String, String)> = conn
        .prepare_cached(&SQL.detail.select)?
        .query_row(params![mode, match_id, subject], |r| {
            Ok((r.get(0)?, r.get(1)?))
        })
        .optional()?;
    Ok(row.and_then(|(data, unreachable)| {
        Some(CachedDetail {
            detail: serde_json::from_str(&data).ok()?,
            unreachable: serde_json::from_str(&unreachable).unwrap_or_default(),
        })
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
    ] {
        tx.execute(sql, [])?;
    }
    Ok(())
}
