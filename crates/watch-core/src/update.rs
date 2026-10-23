//! Updating the app from its GitHub releases: which release is newer, which file of it
//! is the Windows package, checking that file against its published sha256, unpacking it
//! and copying it over the program folder. The network and the processes are the
//! service's (`watchd`); everything here works on values and paths so it can be tested.
use anyhow::{Context, bail};
use serde::Serialize;
use serde_json::Value;
use sha2::{Digest, Sha256};
use std::fs;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

/// Where the releases are published.
pub const REPO: &str = "KCN-judu/watch-overwatch";

/// The latest release, as the GitHub API gives it (no credentials, public repository).
pub fn latest_release_url() -> String {
    format!("https://api.github.com/repos/{REPO}/releases/latest")
}

/// This build's version; `WATCHD_VERSION_OVERRIDE` stands in for it when testing an
/// update against an already published release.
pub fn current_version() -> String {
    std::env::var("WATCHD_VERSION_OVERRIDE")
        .ok()
        .filter(|v| parse_version(v).is_some())
        .unwrap_or_else(|| env!("CARGO_PKG_VERSION").to_owned())
}

/// `1.2.0` or `v1.2.0` → (1, 2, 0); a pre-release suffix (`-rc1`) is ignored.
pub fn parse_version(v: &str) -> Option<(u64, u64, u64)> {
    let v = v.trim().trim_start_matches('v');
    let core = v.split(['-', '+']).next()?;
    let mut parts = core.split('.').map(|p| p.parse::<u64>().ok());
    let out = (
        parts.next()??,
        parts.next()??,
        parts.next().unwrap_or(Some(0))?,
    );
    parts.next().is_none().then_some(out)
}

/// Whether `latest` is a later version than `current`; false when either does not parse.
pub fn is_newer(latest: &str, current: &str) -> bool {
    matches!((parse_version(latest), parse_version(current)), (Some(l), Some(c)) if l > c)
}

/// A published release with a Windows package.
#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct Release {
    pub version: String,
    pub tag: String,
    pub name: String,
    /// The release text (Markdown), what changed.
    pub notes: String,
    pub published_at: Option<String>,
    pub page_url: Option<String>,
    pub zip_name: String,
    pub zip_url: String,
    pub zip_size: u64,
    /// The `.sha256` published beside the zip; a release without one is not installed.
    pub sha256_url: Option<String>,
}

/// The release in a GitHub `releases/latest` answer; none for a draft, a pre-release or
/// one without a `…-windows-x64.zip`.
pub fn release_from_github(j: &Value) -> Option<Release> {
    if j["draft"].as_bool() == Some(true) || j["prerelease"].as_bool() == Some(true) {
        return None;
    }
    let tag = j["tag_name"].as_str()?.to_owned();
    parse_version(&tag)?;
    let assets = j["assets"].as_array()?;
    let name_of = |a: &Value| a["name"].as_str().unwrap_or("").to_owned();
    let zip = assets
        .iter()
        .find(|a| name_of(a).ends_with("-windows-x64.zip"))?;
    let zip_name = name_of(zip);
    let sha = assets
        .iter()
        .find(|a| name_of(a) == format!("{zip_name}.sha256"));
    Some(Release {
        version: tag.trim_start_matches('v').to_owned(),
        name: j["name"].as_str().unwrap_or(&tag).to_owned(),
        tag,
        notes: j["body"].as_str().unwrap_or("").to_owned(),
        published_at: j["published_at"].as_str().map(str::to_owned),
        page_url: j["html_url"].as_str().map(str::to_owned),
        zip_url: zip["browser_download_url"].as_str()?.to_owned(),
        zip_size: zip["size"].as_u64().unwrap_or(0),
        sha256_url: sha.and_then(|a| a["browser_download_url"].as_str().map(str::to_owned)),
        zip_name,
    })
}

/// The hash in a `sha256sum`-style line (`<hex>  <file>`).
pub fn parse_sha256(text: &str) -> Option<String> {
    let hex = text.split_whitespace().next()?.to_ascii_lowercase();
    (hex.len() == 64 && hex.bytes().all(|b| b.is_ascii_hexdigit())).then_some(hex)
}

pub fn sha256_hex(bytes: &[u8]) -> String {
    Sha256::digest(bytes)
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
}

/// Unpacks a release zip into `dest`, dropping the zip's top folder
/// (`watch-overwatch-v1.3.0-windows-x64/`). Entries that would land outside `dest` are
/// refused. Returns how many files were written.
pub fn extract(zip_bytes: &[u8], dest: &Path) -> anyhow::Result<usize> {
    let mut archive = zip::ZipArchive::new(std::io::Cursor::new(zip_bytes))?;
    if dest.exists() {
        fs::remove_dir_all(dest)?;
    }
    fs::create_dir_all(dest)?;
    let mut written = 0;
    for i in 0..archive.len() {
        let mut entry = archive.by_index(i)?;
        let Some(path) = entry.enclosed_name() else {
            bail!("unsafe path in the package: entry {i}");
        };
        let inner: PathBuf = path.components().skip(1).collect();
        if inner.as_os_str().is_empty() {
            continue;
        }
        let out = dest.join(&inner);
        if entry.is_dir() {
            fs::create_dir_all(&out)?;
            continue;
        }
        if let Some(parent) = out.parent() {
            fs::create_dir_all(parent)?;
        }
        let mut data = Vec::with_capacity(entry.size() as usize);
        entry.read_to_end(&mut data)?;
        fs::write(&out, data).with_context(|| out.display().to_string())?;
        written += 1;
    }
    if !is_install_dir(dest) {
        bail!("the package does not hold the program");
    }
    Ok(written)
}

/// Whether `dir` is a program folder as the release zip lays it out: the app, the service
/// and the app's `data` folder side by side. A development build is not, and is never
/// overwritten.
pub fn is_install_dir(dir: &Path) -> bool {
    dir.join("watch-overwatch.exe").is_file()
        && dir.join("watchd.exe").is_file()
        && dir.join("data").is_dir()
}

/// Copies every file under `from` over `to`, retrying a file that is still in use (the app
/// and the service take a moment to exit) until `patience` runs out.
pub fn install(from: &Path, to: &Path, patience: Duration) -> anyhow::Result<usize> {
    let deadline = Instant::now() + patience;
    let mut files = Vec::new();
    walk(from, &mut files)?;
    for file in &files {
        let target = to.join(file.strip_prefix(from)?);
        if let Some(parent) = target.parent() {
            fs::create_dir_all(parent)?;
        }
        loop {
            match fs::copy(file, &target) {
                Ok(_) => break,
                Err(e) if Instant::now() < deadline => {
                    tracing::debug!("{} busy ({e}), retrying", target.display());
                    std::thread::sleep(Duration::from_millis(300));
                }
                Err(e) => return Err(e).with_context(|| target.display().to_string()),
            }
        }
    }
    Ok(files.len())
}

fn walk(dir: &Path, out: &mut Vec<PathBuf>) -> anyhow::Result<()> {
    for entry in fs::read_dir(dir)? {
        let path = entry?.path();
        if path.is_dir() {
            walk(&path, out)?;
        } else {
            out.push(path);
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use std::io::Write;

    #[test]
    fn versions_compare_by_number_not_text() {
        assert!(is_newer("v1.10.0", "1.9.3"));
        assert!(is_newer("1.3.0", "1.2.0"));
        assert!(!is_newer("v1.2.0", "1.2.0"));
        assert!(!is_newer("1.1.9", "1.2.0"));
        assert!(!is_newer("nightly", "1.2.0"));
        assert_eq!(parse_version("v1.3"), Some((1, 3, 0)));
        assert_eq!(parse_version("1.3.0-rc1"), Some((1, 3, 0)));
        assert_eq!(parse_version("1.2.3.4"), None);
    }

    fn github(prerelease: bool) -> Value {
        json!({
            "tag_name": "v1.3.0",
            "name": "Watch Overwatch 1.3.0",
            "body": "## 新增\n- 每日总结",
            "draft": false,
            "prerelease": prerelease,
            "published_at": "2026-10-24T08:00:00Z",
            "html_url": "https://github.com/KCN-judu/watch-overwatch/releases/tag/v1.3.0",
            "assets": [
                {"name": "watch-overwatch-v1.3.0-windows-x64.zip.sha256", "size": 105,
                 "browser_download_url": "https://example.test/z.sha256"},
                {"name": "watch-overwatch-v1.3.0-windows-x64.zip", "size": 24000000,
                 "browser_download_url": "https://example.test/z.zip"}
            ]
        })
    }

    #[test]
    fn the_windows_zip_and_its_checksum_are_picked_from_the_assets() {
        let r = release_from_github(&github(false)).unwrap();
        assert_eq!(r.version, "1.3.0");
        assert_eq!(r.zip_url, "https://example.test/z.zip");
        assert_eq!(r.zip_size, 24_000_000);
        assert_eq!(
            r.sha256_url.as_deref(),
            Some("https://example.test/z.sha256")
        );
        assert!(release_from_github(&github(true)).is_none());
        assert!(release_from_github(&json!({"tag_name": "v1.3.0", "assets": []})).is_none());
    }

    #[test]
    fn a_checksum_line_gives_its_hash() {
        let hex = sha256_hex(b"abc");
        assert_eq!(
            hex,
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
        assert_eq!(
            parse_sha256(&format!("{}  pkg.zip\n", hex.to_uppercase())),
            Some(hex)
        );
        assert_eq!(parse_sha256("not a hash"), None);
    }

    fn package(entries: &[(&str, &[u8])]) -> Vec<u8> {
        let mut zip = zip::ZipWriter::new(std::io::Cursor::new(Vec::new()));
        for (name, data) in entries {
            zip.start_file(*name, zip::write::SimpleFileOptions::default())
                .unwrap();
            zip.write_all(data).unwrap();
        }
        zip.finish().unwrap().into_inner()
    }

    fn temp(name: &str) -> PathBuf {
        let dir =
            std::env::temp_dir().join(format!("watch-update-{name}-{}", uuid::Uuid::new_v4()));
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn a_package_unpacks_without_its_top_folder_and_installs_over_the_old_one() {
        let zip = package(&[
            ("p/watch-overwatch.exe", b"app 2"),
            ("p/watchd.exe", b"service 2"),
            ("p/data/flutter_assets/a.txt", b"asset 2"),
        ]);
        let root = temp("install");
        let staged = root.join("staged");
        assert_eq!(extract(&zip, &staged).unwrap(), 3);
        let installed = root.join("program");
        fs::create_dir_all(installed.join("data")).unwrap();
        fs::write(installed.join("watch-overwatch.exe"), b"app 1").unwrap();
        fs::write(installed.join("watchd.exe"), b"service 1").unwrap();
        fs::write(installed.join("data/old.txt"), b"kept").unwrap();
        assert!(is_install_dir(&installed));
        assert_eq!(install(&staged, &installed, Duration::ZERO).unwrap(), 3);
        assert_eq!(
            fs::read(installed.join("watchd.exe")).unwrap(),
            b"service 2"
        );
        assert_eq!(
            fs::read(installed.join("data/flutter_assets/a.txt")).unwrap(),
            b"asset 2"
        );
        assert!(installed.join("data/old.txt").exists());
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn a_package_without_the_program_or_with_escaping_paths_is_refused() {
        let root = temp("refuse");
        let only_docs = package(&[("p/README.txt", b"hi")]);
        assert!(extract(&only_docs, &root.join("a")).is_err());
        let escaping = package(&[("p/../../evil.exe", b"x")]);
        assert!(extract(&escaping, &root.join("b")).is_err());
        fs::remove_dir_all(root).unwrap();
    }
}
