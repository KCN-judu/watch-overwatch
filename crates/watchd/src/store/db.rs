//! The one place that owns a SQLite connection. Everything that reads or writes goes
//! through [`Db::read`] or [`Db::write`], so locking, transactions and failure handling
//! are decided here and nowhere else.
use rusqlite::{Connection, Transaction};
use std::{path::Path, sync::Mutex};

use super::sql::PRAGMAS;

#[derive(Debug)]
pub struct Db {
    name: &'static str,
    conn: Mutex<Connection>,
}

impl Db {
    /// Opens `path` and runs `schema` (each statement is idempotent), then `upgrades`:
    /// statements, in order, that bring a database made by an older version up to date.
    /// The first one fails with "duplicate column" on one that already is, which ends the
    /// upgrade.
    pub fn open(
        name: &'static str,
        path: &Path,
        schema: &[String],
        upgrades: &[String],
    ) -> rusqlite::Result<Self> {
        let conn = Connection::open(path)?;
        conn.execute_batch(PRAGMAS)?;
        for statement in schema {
            conn.execute(statement, [])?;
        }
        for statement in upgrades {
            match conn.execute(statement, []) {
                Ok(_) => {}
                // Already up to date: the rest of the upgrade has been done too.
                Err(e) if e.to_string().contains("duplicate column") => break,
                Err(e) => return Err(e),
            }
        }
        Ok(Self {
            name,
            conn: Mutex::new(conn),
        })
    }

    /// Runs `f` with the connection and hands its error back: for the steps of opening the
    /// store, where a failure has to be seen.
    pub fn with<T>(
        &self,
        f: impl FnOnce(&Connection) -> rusqlite::Result<T>,
    ) -> rusqlite::Result<T> {
        let conn = self.conn.lock().map_err(|_| poisoned())?;
        f(&conn)
    }

    /// A read. A failure is logged and answered as "nothing there": the store is only ever
    /// a shortcut, never the source of truth.
    pub fn read<T>(
        &self,
        what: &str,
        f: impl FnOnce(&Connection) -> rusqlite::Result<T>,
    ) -> Option<T> {
        self.with(f).map_err(|e| self.log(what, &e)).ok()
    }

    /// A write, in one transaction: all of it or none of it. A failure is logged.
    pub fn write<T>(
        &self,
        what: &str,
        f: impl FnOnce(&Transaction<'_>) -> rusqlite::Result<T>,
    ) -> Option<T> {
        let run = || -> rusqlite::Result<T> {
            let mut conn = self.conn.lock().map_err(|_| poisoned())?;
            let tx = conn.transaction()?;
            let out = f(&tx)?;
            tx.commit()?;
            Ok(out)
        };
        run().map_err(|e| self.log(what, &e)).ok()
    }

    fn log(&self, what: &str, e: &rusqlite::Error) {
        tracing::warn!("local store ({}): {what}: {e}", self.name);
    }
}

fn poisoned() -> rusqlite::Error {
    rusqlite::Error::ToSqlConversionFailure("the database lock is poisoned".into())
}
