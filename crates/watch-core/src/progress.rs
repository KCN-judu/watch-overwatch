//! Live progress of a long collection, readable from another request while it runs.
use serde::Serialize;
use std::sync::Mutex;

/// What the collection is doing right now. `phase` is one of `list` (reading match
/// pages), `details` (one request per match), `ratings` (one or two requests per
/// participant), `finish`, `done`.
#[derive(Debug, Clone, Default, Serialize)]
pub struct ProgressSnapshot {
    pub phase: String,
    pub done: usize,
    /// Zero while unknown.
    pub total: usize,
    /// Short human note for the current step (a map name, a page number).
    pub note: String,
    pub matches_found: usize,
    pub requests: usize,
    pub failures: usize,
}

#[derive(Debug, Default)]
pub struct Progress {
    inner: Mutex<ProgressSnapshot>,
}

impl Progress {
    pub fn update(&self, f: impl FnOnce(&mut ProgressSnapshot)) {
        if let Ok(mut s) = self.inner.lock() {
            f(&mut s);
        }
    }
    pub fn snapshot(&self) -> ProgressSnapshot {
        self.inner.lock().map(|s| s.clone()).unwrap_or_default()
    }
}

/// Convenience for call sites that may not track progress.
pub fn report(p: Option<&Progress>, f: impl FnOnce(&mut ProgressSnapshot)) {
    if let Some(p) = p {
        p.update(f);
    }
}
