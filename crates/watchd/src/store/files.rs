//! The store's dealings with the file system, kept out of the database code: where the
//! file is, how big it is, carrying an older single-file store over and deleting the rank
//! cache earlier versions kept.
use std::path::{Path, PathBuf};

use super::{
    db::Db,
    sql::{ATTACH_LEGACY, DETACH_LEGACY, SQL},
};

const MATCHES_FILE: &str = "matches.db";
/// The rank cache of versions before 1.4.0; ranks now live in the match snapshots.
const RANK_CACHE_FILE: &str = "ratings.db";
/// The single file older versions kept everything in.
const LEGACY_FILE: &str = "strength.db";

#[derive(Debug, Clone)]
pub struct Layout {
    dir: PathBuf,
}

impl Layout {
    pub fn new(dir: &Path) -> Self {
        Self {
            dir: dir.to_owned(),
        }
    }

    /// Creates the folder when it is missing.
    pub fn ensure(&self) {
        let _ = std::fs::create_dir_all(&self.dir);
    }

    pub fn matches_db(&self) -> PathBuf {
        self.dir.join(MATCHES_FILE)
    }

    /// Deletes the rank cache of earlier versions, if it is still there.
    pub fn remove_rank_cache(&self) {
        for suffix in ["", "-wal", "-shm"] {
            let _ = std::fs::remove_file(self.dir.join(format!("{RANK_CACHE_FILE}{suffix}")));
        }
    }

    /// Bytes the database takes, with its write-ahead log.
    pub fn bytes(&self) -> u64 {
        [MATCHES_FILE.to_string(), format!("{MATCHES_FILE}-wal")]
            .iter()
            .map(|name| std::fs::metadata(self.dir.join(name)).map_or(0, |m| m.len()))
            .sum()
    }

    fn legacy(&self) -> Option<PathBuf> {
        let path = self.dir.join(LEGACY_FILE);
        path.exists().then_some(path)
    }

    fn remove_legacy(&self) {
        for name in [LEGACY_FILE, "strength.db-wal", "strength.db-shm"] {
            let _ = std::fs::remove_file(self.dir.join(name));
        }
    }
}

/// Moves the matches an older version kept in the single `strength.db` into the current
/// database, then deletes it (its ranks are not carried over: ranks live in the match
/// snapshots now). Nothing happens when there is no old file; the old file stays if
/// copying failed.
pub fn migrate_legacy(layout: &Layout, matches: &Db) {
    let Some(legacy) = layout.legacy() else {
        return;
    };
    let path = legacy.to_string_lossy().into_owned();
    let copied = matches.with(|c| {
        c.execute(ATTACH_LEGACY, [&path])?;
        // A table the old file never had is nothing to carry over.
        for sql in [
            &SQL.legacy.detail,
            &SQL.legacy.list,
            &SQL.legacy.state,
            &SQL.legacy.participant,
        ] {
            let _ = c.execute(sql, []);
        }
        c.execute(DETACH_LEGACY, []).map(|_| ())
    });
    match copied {
        Ok(()) => layout.remove_legacy(),
        Err(e) => tracing::warn!("local store: could not move the old cache over: {e}"),
    }
}
