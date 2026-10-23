//! `/api/update/*`: checking GitHub for a newer release, downloading and checking its
//! package in the background, and handing over to a copy of this program that installs
//! it once the app and the service have exited (`watch_core::update` does the work on
//! files). Nothing but the public release is fetched; no credentials are sent.
use crate::AppState;
use axum::{
    Json,
    extract::State,
    http::StatusCode,
    response::{IntoResponse, Response},
};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use watch_core::update::{self, Release};

/// A check is reused this long unless the user asks again.
const CHECK_TTL: Duration = Duration::from_secs(6 * 3600);

#[derive(Default)]
pub(crate) struct Updates {
    checked: Option<(Instant, Option<Release>)>,
    download: Download,
}

#[derive(Clone, Serialize)]
struct Download {
    /// `idle`, `downloading`, `verifying`, `ready`, `failed`.
    state: &'static str,
    version: Option<String>,
    received: u64,
    total: u64,
    error: Option<String>,
}

impl Default for Download {
    fn default() -> Self {
        Self {
            state: "idle",
            version: None,
            received: 0,
            total: 0,
            error: None,
        }
    }
}

pub(crate) type UpdateBook = Arc<Mutex<Updates>>;

/// An error answer in the service's shape: `{error: {kind, message}}` with a status.
fn fail(status: StatusCode, kind: &str, message: impl Into<String>) -> Response {
    (
        status,
        Json(json!({"error": {"kind": kind, "message": message.into()}})),
    )
        .into_response()
}

fn updates_dir() -> PathBuf {
    watch_core::data_dir().join("updates")
}

/// Where this program runs from, if it is a program folder an update may replace.
fn install_dir() -> Option<PathBuf> {
    let dir = std::env::current_exe().ok()?.parent()?.to_path_buf();
    update::is_install_dir(&dir).then_some(dir)
}

fn http() -> reqwest::Result<reqwest::Client> {
    reqwest::Client::builder()
        .user_agent(format!("watch-overwatch/{}", update::current_version()))
        .connect_timeout(Duration::from_secs(10))
        .build()
}

async fn fetch_latest() -> Result<Option<Release>, String> {
    let response = http()
        .map_err(|e| e.to_string())?
        .get(update::latest_release_url())
        .header("accept", "application/vnd.github+json")
        .timeout(Duration::from_secs(20))
        .send()
        .await
        .map_err(|e| e.to_string())?;
    if response.status() == reqwest::StatusCode::NOT_FOUND {
        return Ok(None);
    }
    if !response.status().is_success() {
        return Err(format!("GitHub {}", response.status()));
    }
    let body: Value = response.json().await.map_err(|e| e.to_string())?;
    Ok(update::release_from_github(&body))
}

#[derive(Deserialize, Default)]
pub(crate) struct CheckRequest {
    #[serde(default)]
    force: bool,
}

fn answer(latest: Option<&Release>, download: &Download) -> Value {
    let current = update::current_version();
    let newer = latest.is_some_and(|r| update::is_newer(&r.version, &current));
    json!({
        "current": current,
        "latest": latest,
        "newer": newer,
        "installable": install_dir().is_some(),
        "download": download,
    })
}

/// `POST /api/update/check` `{force?}`: this version, the latest release and whether it is
/// newer; whether this copy can install it (not a development build).
pub(crate) async fn check(
    State(app): State<AppState>,
    body: Option<Json<CheckRequest>>,
) -> Response {
    let force = body.map(|b| b.force).unwrap_or(false);
    {
        let book = app.updates.lock().unwrap();
        if let Some((at, latest)) = &book.checked
            && !force
            && at.elapsed() < CHECK_TTL
        {
            return Json(answer(latest.as_ref(), &book.download)).into_response();
        }
    }
    clean_leftovers();
    match fetch_latest().await {
        Ok(latest) => {
            let mut book = app.updates.lock().unwrap();
            book.checked = Some((Instant::now(), latest.clone()));
            Json(answer(latest.as_ref(), &book.download)).into_response()
        }
        Err(e) => {
            tracing::warn!("update check failed: {e}");
            fail(StatusCode::BAD_GATEWAY, "network", e)
        }
    }
}

/// `POST /api/update/status`: how the download is going.
pub(crate) async fn status(State(app): State<AppState>) -> Json<Value> {
    let book = app.updates.lock().unwrap();
    Json(json!({"download": book.download}))
}

/// `POST /api/update/download`: fetches, checks and unpacks the latest release in the
/// background; `/api/update/status` follows it.
pub(crate) async fn download(State(app): State<AppState>) -> Response {
    let release = {
        let mut book = app.updates.lock().unwrap();
        let Some((_, Some(release))) = book.checked.clone() else {
            return fail(StatusCode::CONFLICT, "invalid", "check first");
        };
        if !update::is_newer(&release.version, &update::current_version()) {
            return fail(StatusCode::CONFLICT, "invalid", "already up to date");
        }
        if matches!(book.download.state, "downloading" | "verifying")
            || (book.download.state == "ready"
                && book.download.version.as_deref() == Some(&release.version))
        {
            return Json(json!({"download": book.download})).into_response();
        }
        book.download = Download {
            state: "downloading",
            version: Some(release.version.clone()),
            total: release.zip_size,
            ..Download::default()
        };
        release
    };
    let book = app.updates.clone();
    tokio::spawn(async move {
        let result = fetch_package(&release, &book).await;
        let mut b = book.lock().unwrap();
        match result {
            Ok(()) => b.download.state = "ready",
            Err(e) => {
                tracing::warn!("update download failed: {e:#}");
                b.download.state = "failed";
                b.download.error = Some(format!("{e:#}"));
            }
        }
    });
    let b = app.updates.lock().unwrap();
    Json(json!({"download": b.download})).into_response()
}

fn staged_dir(version: &str) -> PathBuf {
    updates_dir().join(format!("v{version}"))
}

async fn fetch_package(release: &Release, book: &UpdateBook) -> anyhow::Result<()> {
    let Some(sha_url) = &release.sha256_url else {
        anyhow::bail!("the release has no checksum");
    };
    let client = http()?;
    let expected = update::parse_sha256(
        &client
            .get(sha_url)
            .timeout(Duration::from_secs(30))
            .send()
            .await?
            .error_for_status()?
            .text()
            .await?,
    )
    .ok_or_else(|| anyhow::anyhow!("the checksum file cannot be read"))?;
    let mut response = client
        .get(&release.zip_url)
        .send()
        .await?
        .error_for_status()?;
    if let Some(len) = response.content_length() {
        book.lock().unwrap().download.total = len;
    }
    let mut bytes = Vec::with_capacity(release.zip_size as usize);
    while let Some(chunk) =
        tokio::time::timeout(Duration::from_secs(60), response.chunk()).await??
    {
        bytes.extend_from_slice(&chunk);
        book.lock().unwrap().download.received = bytes.len() as u64;
    }
    book.lock().unwrap().download.state = "verifying";
    let actual = update::sha256_hex(&bytes);
    if actual != expected {
        anyhow::bail!("checksum mismatch: the download is damaged");
    }
    let dest = staged_dir(&release.version);
    tokio::task::spawn_blocking(move || update::extract(&bytes, &dest)).await??;
    Ok(())
}

/// `POST /api/update/apply`: starts the installer (a copy of this program, so the real one
/// can be replaced) and exits; the app quits right after the answer.
pub(crate) async fn apply(State(app): State<AppState>) -> Response {
    let version = {
        let b = app.updates.lock().unwrap();
        if b.download.state != "ready" {
            return fail(StatusCode::CONFLICT, "invalid", "nothing downloaded");
        }
        b.download.version.clone().unwrap_or_default()
    };
    let Some(target) = install_dir() else {
        return fail(
            StatusCode::CONFLICT,
            "invalid",
            "not a release folder; install by hand",
        );
    };
    match start_installer(&staged_dir(&version), &target) {
        Ok(()) => {
            tokio::spawn(async {
                tokio::time::sleep(Duration::from_millis(500)).await;
                std::process::exit(0);
            });
            Json(json!({"ok": true})).into_response()
        }
        Err(e) => fail(
            StatusCode::INTERNAL_SERVER_ERROR,
            "internal",
            format!("{e:#}"),
        ),
    }
}

fn start_installer(staged: &Path, target: &Path) -> anyhow::Result<()> {
    let dir = updates_dir();
    std::fs::create_dir_all(&dir)?;
    let installer = dir.join(format!("installer-{}.exe", std::process::id()));
    std::fs::copy(std::env::current_exe()?, &installer)?;
    let mut command = std::process::Command::new(&installer);
    command
        .arg("apply-update")
        .arg(staged)
        .arg(target)
        .current_dir(&dir);
    #[cfg(target_os = "windows")]
    {
        use std::os::windows::process::CommandExt;
        // DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP | CREATE_NO_WINDOW
        command.creation_flags(0x0000_0008 | 0x0000_0200 | 0x0800_0000);
    }
    command.spawn()?;
    Ok(())
}

/// Installers and unpacked packages left by an earlier update.
fn clean_leftovers() {
    let Ok(entries) = std::fs::read_dir(updates_dir()) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        let name = entry.file_name().to_string_lossy().into_owned();
        if name.starts_with("installer-") && name.ends_with(".exe") {
            let _ = std::fs::remove_file(&path);
        }
    }
}

/// `watchd apply-update <staged> <program folder>`, run by [apply] from its copy: waits for
/// the app and the service to let go of their files, copies the new ones over, removes
/// the staged copy and starts the app again. On failure the old app starts, and the reason
/// is in `updates/update.log`.
pub(crate) fn run_installer(staged: &Path, target: &Path) -> anyhow::Result<()> {
    let log = updates_dir().join("update.log");
    let result = update::install(staged, target, Duration::from_secs(60));
    let line = match &result {
        Ok(n) => format!("installed {n} files into {}\n", target.display()),
        Err(e) => format!("install failed: {e:#}\n"),
    };
    let _ = std::fs::write(&log, line);
    if result.is_ok() {
        let _ = std::fs::remove_dir_all(staged);
    }
    std::process::Command::new(target.join("watch-overwatch.exe"))
        .current_dir(target)
        .spawn()?;
    result.map(|_| ())
}
