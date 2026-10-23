//! Rank snapshots read in the background (`/api/ranks/*`): after a player's match list is
//! updated the app starts a job for that player and mode, and the matches still missing
//! snapshots are read a few at a time, newest first (`watch_core::snapshot`).
//!
//! The job gives way to everything else. Before each upstream request it waits until no
//! other query has been running for [`QUIET`]: a page the user opens is answered first,
//! and the job carries on by itself afterwards. A job for another player started later
//! goes first too. What is done is in the stored matches, so a job stopped for any reason
//! (the service restarted, the session expired) picks up where it was when started again.
use crate::AppState;
use crate::service::{Session, SessionFetcher, prepare_with, subject_id};
use axum::{
    Json,
    extract::State,
    response::{IntoResponse, Response},
};
use serde::Serialize;
use serde_json::Value;
use serde_json::json;
use std::collections::{HashMap, HashSet};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use tokio::sync::Notify;
use watch_core::collect::{self, Fetched, Fetcher};
use watch_core::dashen::{Endpoint, Mode};
use watch_core::ir::MatchSummary;
use watch_core::snapshot::Lookups;
use watch_core::{Failure, ListKey, StrengthCache as _};

/// How long the other queries must have been quiet before the job asks the upstream again.
pub(crate) const QUIET: Duration = Duration::from_millis(1500);
/// Matches read per step; the job looks again for a newer job between steps.
const BATCH: usize = 3;
/// How many of the newest matches are kept with snapshots.
pub(crate) const WINDOW: usize = 300;
/// The pauses before the matches whose lookups failed are tried again; after the last,
/// they wait for the next start.
const RETRIES: [Duration; 3] = [
    Duration::from_secs(30),
    Duration::from_secs(60),
    Duration::from_secs(120),
];

/// The queries running now that are not the background job's, and when the last ended.
#[derive(Default)]
pub(crate) struct Foreground {
    busy: AtomicUsize,
    last: Mutex<Option<Instant>>,
    changed: Notify,
}

/// Held while a query runs: the background job waits for every one to be dropped.
pub(crate) struct Busy(Arc<Foreground>);

impl Drop for Busy {
    fn drop(&mut self) {
        self.0.busy.fetch_sub(1, Ordering::SeqCst);
        *self.0.last.lock().unwrap() = Some(Instant::now());
        self.0.changed.notify_waiters();
    }
}

impl Foreground {
    pub(crate) fn enter(self: &Arc<Self>) -> Busy {
        self.busy.fetch_add(1, Ordering::SeqCst);
        self.changed.notify_waiters();
        Busy(self.clone())
    }

    /// How long nothing has run; `None` while something does.
    fn idle_for(&self) -> Option<Duration> {
        if self.busy.load(Ordering::SeqCst) > 0 {
            return None;
        }
        Some(
            self.last
                .lock()
                .unwrap()
                .map_or(Duration::MAX, |t| t.elapsed()),
        )
    }

    pub(crate) fn quiet(&self, quiet: Duration) -> bool {
        self.idle_for().is_some_and(|d| d >= quiet)
    }

    /// Returns once nothing has run for `quiet`.
    pub(crate) async fn wait_quiet(&self, quiet: Duration) {
        loop {
            let changed = self.changed.notified();
            match self.idle_for() {
                Some(d) if d >= quiet => return,
                Some(d) => {
                    tokio::select! {
                        _ = tokio::time::sleep(quiet - d) => {}
                        _ = changed => {}
                    }
                }
                None => changed.await,
            }
        }
    }
}

/// Where a job stands, as `/api/ranks/status` gives it.
#[derive(Clone, Serialize)]
pub(crate) struct JobStatus {
    /// `waiting` (queued behind another), `running`, `paused` (giving way to a query),
    /// `retrying` (only matches whose lookups failed are left; tried again after
    /// `retry_in_s`), `done` (nothing left, or the retries are used up).
    pub state: &'static str,
    /// Matches finished in this job, and still to do.
    pub done: usize,
    pub remaining: usize,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub retry_in_s: Option<u64>,
}

/// One job: whom it is for, and its own state: who has been asked (so a player is asked
/// once per job), the matches that failed this round and how many rounds were retried.
struct Job {
    subject: String,
    mode: Mode,
    session: Session,
    lookups: Arc<Mutex<Lookups>>,
    deferred: HashSet<String>,
    retries: usize,
}

type JobKey = (String, Mode);

#[derive(Default)]
pub(crate) struct RankJobs {
    inner: Mutex<Jobs>,
    wake: Notify,
}

#[derive(Default)]
struct Jobs {
    /// Next first.
    queue: Vec<Job>,
    status: HashMap<JobKey, JobStatus>,
}

impl RankJobs {
    fn set(&self, key: &JobKey, f: impl FnOnce(&mut JobStatus)) {
        let mut jobs = self.inner.lock().unwrap();
        let status = jobs.status.entry(key.clone()).or_insert(JobStatus {
            state: "waiting",
            done: 0,
            remaining: 0,
            retry_in_s: None,
        });
        f(status);
    }

    pub(crate) fn status(&self, subject: &str, mode: Mode) -> Option<JobStatus> {
        let jobs = self.inner.lock().unwrap();
        jobs.status.get(&(subject.to_owned(), mode)).cloned()
    }

    /// Queues a job ahead of the others (a job already queued for it moves up).
    fn start(&self, job: Job) {
        let key = (job.subject.clone(), job.mode);
        {
            let mut jobs = self.inner.lock().unwrap();
            jobs.queue
                .retain(|j| (j.subject.as_str(), j.mode) != (key.0.as_str(), key.1));
            jobs.queue.insert(0, job);
            let status = jobs.status.entry(key).or_insert(JobStatus {
                state: "waiting",
                done: 0,
                remaining: 0,
                retry_in_s: None,
            });
            if matches!(status.state, "done") {
                status.state = "waiting";
                status.done = 0;
            }
        }
        self.wake.notify_one();
    }

    fn next(&self) -> Option<Job> {
        let mut jobs = self.inner.lock().unwrap();
        (!jobs.queue.is_empty()).then(|| jobs.queue.remove(0))
    }

    fn others_waiting(&self) -> bool {
        !self.inner.lock().unwrap().queue.is_empty()
    }

    fn put_back(&self, job: Job) {
        self.inner.lock().unwrap().queue.push(job);
    }
}

/// The matches of the stored list (newest [`WINDOW`]) still missing their snapshots.
pub(crate) fn pending(
    store: &crate::store::LocalStore,
    subject: &str,
    mode: Mode,
) -> Vec<MatchSummary> {
    let key = ListKey {
        subject,
        mode,
        season: None,
    };
    store
        .match_list(key)
        .rows
        .into_iter()
        .take(WINDOW)
        .filter(|m| !collect::match_prepared(store, mode, &m.id, subject, 0))
        .collect()
}

/// Asks the upstream only once the other queries are quiet, and says so in the status.
struct Yielding<'a> {
    inner: SessionFetcher<'a>,
    foreground: &'a Foreground,
    jobs: &'a RankJobs,
    key: &'a JobKey,
}

impl Fetcher for Yielding<'_> {
    async fn fetch(&self, endpoint: Endpoint, payload: Value) -> Result<Fetched, Failure> {
        if !self.foreground.quiet(QUIET) {
            self.jobs.set(self.key, |s| s.state = "paused");
            self.foreground.wait_quiet(QUIET).await;
            self.jobs.set(self.key, |s| s.state = "running");
        }
        self.inner.fetch(endpoint, payload).await
    }
}

/// Starts (or moves up) the job for this player and mode.
pub(crate) fn start(s: &AppState, session: Session, mode: Mode) -> Option<String> {
    let subject = subject_id(&session.identity)?;
    s.rank_jobs.start(Job {
        subject: subject.clone(),
        mode,
        session,
        lookups: Arc::default(),
        deferred: HashSet::new(),
        retries: 0,
    });
    Some(subject)
}

/// The one loop that runs the jobs, for the life of the service.
pub(crate) async fn run(s: AppState) {
    loop {
        let Some(job) = s.rank_jobs.next() else {
            s.rank_jobs.wake.notified().await;
            continue;
        };
        run_job(&s, job).await;
    }
}

async fn run_job(s: &AppState, mut job: Job) {
    let Some(store) = s.store.clone() else {
        return;
    };
    let key: JobKey = (job.subject.clone(), job.mode);
    let mut last: Option<usize> = None;
    loop {
        let waiting = pending(&store, &job.subject, job.mode);
        let remaining = waiting.len();
        if let Some(before) = last {
            let step = before.saturating_sub(remaining);
            s.rank_jobs.set(&key, |st| st.done += step);
        }
        last = Some(remaining);
        if remaining == 0 {
            s.rank_jobs.set(&key, |st| {
                st.state = "done";
                st.remaining = 0;
                st.retry_in_s = None;
            });
            return;
        }
        // Matches that failed this round wait at the back: the ones behind them go first.
        let ready: Vec<MatchSummary> = waiting
            .into_iter()
            .filter(|m| !job.deferred.contains(&m.id))
            .collect();
        if ready.is_empty() {
            // Only failed ones are left: they go back into the queue after a pause, a few
            // times; after that they wait for the next start (the next refresh).
            if job.retries >= RETRIES.len() {
                s.rank_jobs.set(&key, |st| {
                    st.state = "done";
                    st.remaining = remaining;
                    st.retry_in_s = None;
                });
                return;
            }
            let pause = RETRIES[job.retries];
            job.retries += 1;
            job.deferred.clear();
            s.rank_jobs.set(&key, |st| {
                st.state = "retrying";
                st.remaining = remaining;
                st.retry_in_s = Some(pause.as_secs());
            });
            // Waits out the pause; a job started meanwhile goes first, and this one keeps
            // its place in the retries and carries on after it. A wake-up with no job
            // waiting (left over from an earlier start) does not cut the pause short.
            let until = tokio::time::Instant::now() + pause;
            loop {
                tokio::select! {
                    _ = tokio::time::sleep_until(until) => break,
                    _ = s.rank_jobs.wake.notified() => {}
                }
                if s.rank_jobs.others_waiting() {
                    s.rank_jobs.set(&key, |st| st.state = "waiting");
                    s.rank_jobs.put_back(job);
                    return;
                }
            }
            continue;
        }
        // A job started since goes first; this one carries on after it.
        if s.rank_jobs.others_waiting() {
            s.rank_jobs.set(&key, |st| {
                st.state = "waiting";
                st.remaining = remaining;
            });
            s.rank_jobs.put_back(job);
            return;
        }
        s.rank_jobs.set(&key, |st| {
            st.state = "running";
            st.remaining = remaining;
            st.retry_in_s = None;
        });
        let fetcher = Yielding {
            inner: SessionFetcher {
                client: &s.client,
                cache: &job.session.cache,
                fresh: false,
            },
            foreground: &s.foreground,
            jobs: &s.rank_jobs,
            key: &key,
        };
        let batch: Vec<MatchSummary> = ready.into_iter().take(BATCH).collect();
        let ids: Vec<String> = batch.iter().map(|m| m.id.clone()).collect();
        prepare_with(
            &fetcher,
            s,
            &job.session,
            job.mode,
            batch,
            true,
            Some(job.lookups.clone()),
        )
        .await;
        // What is still missing after its step failed somewhere: to the back.
        for id in ids {
            if !collect::match_prepared(store.as_ref(), job.mode, &id, &job.subject, 0) {
                job.deferred.insert(id);
            }
        }
    }
}

#[derive(serde::Deserialize)]
pub(crate) struct JobInput {
    session: String,
    #[serde(default = "competitive")]
    mode: String,
}

fn competitive() -> String {
    "competitive".into()
}

fn answer(status: Option<JobStatus>) -> Response {
    Json(json!({ "job": status })).into_response()
}

async fn job_of(s: &AppState, input: &JobInput) -> Result<(Session, Mode), Failure> {
    let mode = Mode::parse(&input.mode)
        .filter(|m| *m != Mode::Stadium)
        .ok_or_else(|| Failure {
            kind: "validation",
            message: "角斗领域没有段位。".into(),
            retry_after_ms: None,
        })?;
    let session =
        crate::service::session(s, &input.session, "玩家会话已过期，请重新查找玩家。").await?;
    Ok((session, mode))
}

/// `POST /api/ranks/start` `{session, mode}`: starts (or moves up) the background job for
/// the player and mode, and answers where it stands.
pub(crate) async fn start_handler(
    State(s): State<AppState>,
    Json(input): Json<JobInput>,
) -> Response {
    let (session, mode) = match job_of(&s, &input).await {
        Ok(v) => v,
        Err(e) => return crate::fail(e).into_response(),
    };
    if s.store.is_none() {
        return answer(None);
    }
    match start(&s, session, mode) {
        Some(subject) => answer(s.rank_jobs.status(&subject, mode)),
        None => answer(None),
    }
}

/// `POST /api/ranks/status` `{session, mode}`: where the job stands; `null` when none was
/// started for the player and mode in this run of the service.
pub(crate) async fn status_handler(
    State(s): State<AppState>,
    Json(input): Json<JobInput>,
) -> Response {
    let (session, mode) = match job_of(&s, &input).await {
        Ok(v) => v,
        Err(e) => return crate::fail(e).into_response(),
    };
    let status = subject_id(&session.identity).and_then(|id| s.rank_jobs.status(&id, mode));
    answer(status)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn the_quiet_wait_lasts_while_a_query_runs_and_a_moment_after() {
        let fg = Arc::new(Foreground::default());
        let quiet = Duration::from_millis(80);
        assert!(fg.quiet(quiet), "nothing has run yet");
        let busy = fg.enter();
        assert!(!fg.quiet(quiet));
        let waiter = {
            let fg = fg.clone();
            tokio::spawn(async move {
                let t = Instant::now();
                fg.wait_quiet(quiet).await;
                t.elapsed()
            })
        };
        tokio::time::sleep(Duration::from_millis(100)).await;
        assert!(!waiter.is_finished(), "still waiting while the query runs");
        drop(busy);
        let waited = waiter.await.unwrap();
        // The query ran 100 ms, then the quiet spell: the wait covers both.
        assert!(waited >= Duration::from_millis(170), "{waited:?}");
    }

    #[cfg(any(debug_assertions, feature = "demo"))]
    #[tokio::test]
    async fn the_job_gives_way_to_a_query_then_takes_every_snapshot() {
        use crate::service::{SearchInput, search_player};
        use watch_core::{Policy, SecretsFile, WatchClient};
        let dir = std::env::temp_dir().join(format!("watchd-ranks-{}", uuid::Uuid::new_v4()));
        let store = crate::store::LocalStore::open(&dir).ok().map(Arc::new);
        // Nothing listens on port 9: only the sample player can answer.
        let client = WatchClient::with_base(
            SecretsFile { accounts: vec![] },
            "http://127.0.0.1:9",
            Policy::default(),
        )
        .unwrap();
        let s = AppState {
            client: Arc::new(client),
            sessions: Arc::new(tokio::sync::Mutex::new(HashMap::new())),
            settings_lock: Arc::new(tokio::sync::Mutex::new(())),
            catalog: Arc::new(watch_core::Catalog::bundled()),
            progress: Arc::new(Mutex::new(HashMap::new())),
            store: store.clone(),
            season_checked: Arc::default(),
            updates: Arc::default(),
            foreground: Arc::default(),
            rank_jobs: Arc::default(),
        };
        let store = store.unwrap();
        let found = search_player(
            State(s.clone()),
            Json(
                serde_json::from_value::<SearchInput>(json!({"name": watch_core::DEMO_NAME}))
                    .unwrap(),
            ),
        )
        .await;
        let found: Value = serde_json::from_slice(
            &axum::body::to_bytes(found.into_body(), usize::MAX)
                .await
                .unwrap(),
        )
        .unwrap();
        let id = found["session"].as_str().unwrap().to_string();
        let session = crate::service::session(&s, &id, "").await.unwrap();
        let subject = subject_id(&session.identity).unwrap();
        // The list as a refresh leaves it: rows only, no details or snapshots yet. Quick
        // play: its matches report no ranks, so every player needs a snapshot.
        let mode = Mode::Quick;
        let rows: Vec<MatchSummary> = {
            let fetcher = SessionFetcher {
                client: &s.client,
                cache: &session.cache,
                fresh: false,
            };
            collect::match_pages(&fetcher, &s.catalog, &session.token, mode, None, 1)
                .await
                .matches
        };
        assert!(!rows.is_empty());
        store.put_match_rows(
            ListKey {
                subject: &subject,
                mode,
                season: None,
            },
            &rows,
        );
        let before = pending(&store, &subject, mode).len();
        assert_eq!(before, rows.len().min(WINDOW));

        // A query is running: the job starts but asks nothing.
        let busy = s.foreground.enter();
        tokio::spawn(run(s.clone()));
        start(&s, session, mode).unwrap();
        tokio::time::sleep(Duration::from_millis(400)).await;
        let st = s.rank_jobs.status(&subject, mode).unwrap();
        assert_eq!(st.state, "paused");
        assert_eq!(pending(&store, &subject, mode).len(), before);

        // The query ends: the job carries on by itself and finishes.
        drop(busy);
        let deadline = Instant::now() + Duration::from_secs(60);
        while s.rank_jobs.status(&subject, mode).unwrap().state != "done" {
            assert!(Instant::now() < deadline, "the job did not finish");
            tokio::time::sleep(Duration::from_millis(50)).await;
        }
        assert!(pending(&store, &subject, mode).is_empty());
        let st = s.rank_jobs.status(&subject, mode).unwrap();
        assert_eq!(st.done, before);
        // Every match now carries its lobby's snapshots.
        let kept = store.detail(mode, &rows[0].id, &subject).unwrap();
        let snapped = kept
            .detail
            .allies
            .iter()
            .chain(&kept.detail.enemies)
            .filter(|p| p.career.settled())
            .count();
        assert!(snapped > 0);
        assert!(!watch_core::snapshot::missing(&kept.detail));
        let _ = std::fs::remove_dir_all(dir);
    }

    #[tokio::test]
    async fn matches_whose_lookups_fail_go_back_into_the_queue_after_a_pause() {
        use watch_core::{Policy, SecretsFile, WatchClient};
        let dir = std::env::temp_dir().join(format!("watchd-retry-{}", uuid::Uuid::new_v4()));
        let store = crate::store::LocalStore::open(&dir).ok().map(Arc::new);
        // Nothing listens on port 9 and this is not the sample player: every request fails.
        let client = WatchClient::with_base(
            SecretsFile { accounts: vec![] },
            "http://127.0.0.1:9",
            Policy::default(),
        )
        .unwrap();
        let s = AppState {
            client: Arc::new(client),
            sessions: Arc::new(tokio::sync::Mutex::new(HashMap::new())),
            settings_lock: Arc::new(tokio::sync::Mutex::new(())),
            catalog: Arc::new(watch_core::Catalog::bundled()),
            progress: Arc::new(Mutex::new(HashMap::new())),
            store: store.clone(),
            season_checked: Arc::default(),
            updates: Arc::default(),
            foreground: Arc::default(),
            rank_jobs: Arc::default(),
        };
        let store = store.unwrap();
        let session = Session {
            token: "nobody".into(),
            identity: json!({"bnetId": "9"}),
            cache: Arc::default(),
        };
        let row: MatchSummary = watch_core::dashen::normalize::match_list(
            &json!([{"matchId": "m1", "beginTs": 5, "roleType": "tank"}]),
            Mode::Quick,
            &watch_core::Catalog::default(),
        )
        .remove(0);
        store.put_match_rows(
            ListKey {
                subject: "9",
                mode: Mode::Quick,
                season: None,
            },
            &[row],
        );
        tokio::spawn(run(s.clone()));
        start(&s, session, Mode::Quick).unwrap();
        let deadline = Instant::now() + Duration::from_secs(20);
        loop {
            let st = s.rank_jobs.status("9", Mode::Quick).unwrap();
            if st.state == "retrying" {
                // Not given up: the match waits for its retry, with the pause stated.
                assert_eq!(st.remaining, 1);
                assert_eq!(st.retry_in_s, Some(30));
                break;
            }
            assert_ne!(st.state, "done", "gave up without retrying");
            assert!(Instant::now() < deadline, "never retried: {}", st.state);
            tokio::time::sleep(Duration::from_millis(50)).await;
        }
        let _ = std::fs::remove_dir_all(dir);
    }
}
