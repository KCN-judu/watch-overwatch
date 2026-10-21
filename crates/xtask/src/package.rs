//! `cargo xtask package`: the Windows release zip and its checksum, from what the release
//! builds (`cargo build --release` and `flutter build windows --release`) left behind.
use anyhow::{Context, bail};
use sha2::{Digest, Sha256};
use std::fs::{self, File};
use std::io::Write;
use std::path::{Path, PathBuf};
use zip::{CompressionMethod, ZipWriter, write::SimpleFileOptions};

const VERSION: &str = env!("CARGO_PKG_VERSION");

/// The text placed next to the program in the zip.
fn readme() -> String {
    format!(
        "Watch Overwatch {VERSION}
国服守望先锋对局与数据分析桌面应用（Windows 10/11，64 位）

运行
  双击 watch-overwatch.exe。它会自动启动同目录的 watchd.exe，关闭窗口时一起退出。
  两个文件和 data 文件夹必须放在同一个目录里。

第一次使用
  1. 打开“设置”，添加一个大神账号（名称、role_id、token）。
     怎么拿 role_id 和 token：见“获取账号凭据.md”（设置页也有“复制获取脚本”按钮）。
  2. 在左上角输入完整的战网昵称（如 Player#12345），按 Enter。
  详细说明见“使用指引.md”。

数据存放
  账号凭据、界面状态、图片缓存、本地对局库（matches.db）和段位库（ratings.db）
  都在 %LOCALAPPDATA%\\Watch Overwatch\\ 下，不在本目录里。
  删除本目录不会删除它们；要彻底清理，一并删除那个文件夹。

说明
  程序里的职责、子职责、技能、威能等图标和资料来自游戏本体和暴雪、大神的公开资源，仅供个人使用。
  需要 Microsoft Visual C++ 运行库（大多数电脑已安装）。
"
    )
    .replace('\n', "\r\n")
}

pub fn run(root: &Path) -> anyhow::Result<()> {
    let name = format!("watch-overwatch-v{VERSION}-windows-x64");
    let app = root.join("app/build/windows/x64/runner/Release");
    let service = root.join("target/release/watchd.exe");
    for need in [&app, &service] {
        if !need.exists() {
            bail!(
                "{} is missing: run `cargo build --release` and `flutter build windows --release` first",
                need.display()
            );
        }
    }
    let dist = root.join("dist");
    fs::create_dir_all(&dist)?;
    let zip_path = dist.join(format!("{name}.zip"));

    let mut found: Vec<(PathBuf, String)> = Vec::new();
    collect(&app, &name, &mut found)?;
    let files = with_extras(
        found,
        [
            (service, format!("{name}/watchd.exe")),
            (
                root.join("docs/user-guide.md"),
                format!("{name}/使用指引.md"),
            ),
            (
                root.join("docs/credentials.md"),
                format!("{name}/获取账号凭据.md"),
            ),
        ],
    );

    let mut zip = ZipWriter::new(File::create(&zip_path)?);
    let options = SimpleFileOptions::default().compression_method(CompressionMethod::Deflated);
    for (path, entry) in &files {
        zip.start_file(entry, options)?;
        zip.write_all(&fs::read(path).with_context(|| path.display().to_string())?)?;
    }
    zip.start_file(format!("{name}/README.txt"), options)?;
    zip.write_all(b"\xEF\xBB\xBF")?;
    zip.write_all(readme().as_bytes())?;
    zip.finish()?;

    let digest = Sha256::digest(fs::read(&zip_path)?);
    let hex: String = digest.iter().map(|b| format!("{b:02x}")).collect();
    fs::write(
        dist.join(format!("{name}.zip.sha256")),
        format!("{hex}  {name}.zip\n"),
    )?;
    let size = fs::metadata(&zip_path)?.len() as f64 / 1_048_576.0;
    println!("{} ({size:.1} MB)\nsha256 {hex}", zip_path.display());
    Ok(())
}

/// The files of the app build plus the extras, one entry per name: an extra replaces a file
/// of the same name (a copy of `watchd.exe` left in the build folder, say) instead of making
/// the zip hold two.
fn with_extras(
    found: Vec<(PathBuf, String)>,
    extras: impl IntoIterator<Item = (PathBuf, String)>,
) -> Vec<(PathBuf, String)> {
    let mut files: Vec<(PathBuf, String)> = found;
    for (path, entry) in extras {
        files.retain(|(_, name)| *name != entry);
        files.push((path, entry));
    }
    files
}

/// Every file under `dir`, with the entry name it gets under `prefix`.
fn collect(dir: &Path, prefix: &str, out: &mut Vec<(PathBuf, String)>) -> anyhow::Result<()> {
    let mut entries: Vec<_> = fs::read_dir(dir)?.collect::<Result<_, _>>()?;
    entries.sort_by_key(|e| e.file_name());
    for entry in entries {
        let path = entry.path();
        let entry_name = format!("{prefix}/{}", entry.file_name().to_string_lossy());
        if path.is_dir() {
            collect(&path, &entry_name, out)?;
        } else {
            out.push((path, entry_name));
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_extra_replaces_a_file_of_the_same_name() {
        let found = vec![
            (
                PathBuf::from("build/watch-overwatch.exe"),
                "p/watch-overwatch.exe".to_owned(),
            ),
            (PathBuf::from("build/watchd.exe"), "p/watchd.exe".to_owned()),
        ];
        let files = with_extras(
            found,
            [
                (
                    PathBuf::from("target/watchd.exe"),
                    "p/watchd.exe".to_owned(),
                ),
                (PathBuf::from("docs/a.md"), "p/a.md".to_owned()),
            ],
        );
        let names: Vec<&str> = files.iter().map(|(_, n)| n.as_str()).collect();
        assert_eq!(names, ["p/watch-overwatch.exe", "p/watchd.exe", "p/a.md"]);
        let service = files.iter().find(|(_, n)| n == "p/watchd.exe").unwrap();
        assert_eq!(service.0, PathBuf::from("target/watchd.exe"));
    }
}
