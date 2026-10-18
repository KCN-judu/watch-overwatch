//! Players' competitive ranks, one row per player and season (`ratings.db`). Every row is
//! stamped with when it was fetched; whether a row is still good is decided by the caller
//! comparing that stamp with its clock, so these functions never read the time.
use rusqlite::{Connection, OptionalExtension, Transaction, params};
use watch_core::ir::RoleRating;

use super::sql::SQL;

/// What is stored about a player's ranks in a season.
pub struct Stored {
    /// When they were fetched (ms since the epoch).
    pub fetched_ms: i64,
    /// A finished season: never goes stale.
    pub settled: bool,
    pub ratings: Vec<RoleRating>,
}

/// The stored ranks of a player in a season. Rows that no longer parse are a miss.
pub fn get(conn: &Connection, bnet_id: &str, season: u32) -> rusqlite::Result<Option<Stored>> {
    let row: Option<(i64, i64, String)> = conn
        .prepare_cached(&SQL.rating.select)?
        .query_row(params![bnet_id, season], |r| {
            Ok((r.get(0)?, r.get(1)?, r.get(2)?))
        })
        .optional()?;
    Ok(row.and_then(|(fetched_ms, settled, data)| {
        Some(Stored {
            fetched_ms,
            settled: settled != 0,
            ratings: serde_json::from_str(&data).ok()?,
        })
    }))
}

/// Stores ranks stamped `now_ms`, replacing any earlier ones.
pub fn put(
    tx: &Transaction<'_>,
    bnet_id: &str,
    season: u32,
    ratings: &[RoleRating],
    settled: bool,
    now_ms: i64,
) -> rusqlite::Result<()> {
    let Ok(data) = serde_json::to_string(ratings) else {
        return Ok(());
    };
    tx.prepare_cached(&SQL.rating.upsert)?.execute(params![
        bnet_id,
        season,
        now_ms,
        data,
        settled as i64
    ])?;
    Ok(())
}

/// Drops ranks fetched before `cutoff_ms`, except settled ones.
pub fn prune(tx: &Transaction<'_>, cutoff_ms: i64) -> rusqlite::Result<()> {
    tx.prepare_cached(&SQL.rating.delete_older)?
        .execute([cutoff_ms])?;
    Ok(())
}

/// How many players have stored ranks.
pub fn players(conn: &Connection) -> rusqlite::Result<usize> {
    let n: i64 = conn
        .prepare_cached(&SQL.rating.count_players)?
        .query_row([], |r| r.get(0))?;
    Ok(n.max(0) as usize)
}

pub fn delete_all(tx: &Transaction<'_>) -> rusqlite::Result<()> {
    tx.execute(&SQL.rating.delete_all, [])?;
    Ok(())
}
