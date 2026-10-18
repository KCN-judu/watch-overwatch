//! Copies the game data in `resources/game` into the app and registers it.
//!
//! `resources/game/heroes.json` and `resources/game/icons/` come from unpacking the
//! installed game (see docs/game-data.md). The app bundles a copy under
//! `app/assets/game/`. Flutter does not look inside asset folders, so every folder that
//! holds files has to be listed in `app/pubspec.yaml`; this task rewrites that list.
use anyhow::{Context, bail};
use std::path::{Path, PathBuf};

/// The line the game's asset entries are attached after.
const ANCHOR: &str = "    - assets/levels/";
const ENTRY_PREFIX: &str = "- assets/game/";

pub fn sync(root: &Path) -> anyhow::Result<()> {
    let source = root.join("resources").join("game");
    let app = root.join("app");
    let target = app.join("assets").join("game");
    if !source.join("heroes.json").is_file() {
        bail!("resources/game/heroes.json not found");
    }
    if target.exists() {
        std::fs::remove_dir_all(&target)?;
    }
    std::fs::create_dir_all(&target)?;
    std::fs::copy(source.join("heroes.json"), target.join("heroes.json"))?;
    let icons = Path::new("icons").join("heroes");
    copy_tree(&source.join(&icons), &target.join(&icons))?;

    let mut folders = Vec::new();
    folders_with_files(&target.join(&icons), &app, &mut folders)?;
    folders.sort();
    let pubspec = app.join("pubspec.yaml");
    let text = std::fs::read_to_string(&pubspec)
        .with_context(|| format!("cannot read {}", pubspec.display()))?;
    std::fs::write(&pubspec, rewrite_pubspec(&text, &folders)?)?;
    println!("copied; {} asset folders registered", folders.len());
    Ok(())
}

fn copy_tree(from: &Path, to: &Path) -> anyhow::Result<()> {
    std::fs::create_dir_all(to)?;
    for entry in std::fs::read_dir(from)? {
        let entry = entry?;
        let destination = to.join(entry.file_name());
        if entry.file_type()?.is_dir() {
            copy_tree(&entry.path(), &destination)?;
        } else {
            std::fs::copy(entry.path(), destination)?;
        }
    }
    Ok(())
}

/// Every folder under `dir` that directly holds a file, as `a/b/c/` relative to `base`.
fn folders_with_files(dir: &Path, base: &Path, out: &mut Vec<String>) -> anyhow::Result<()> {
    let mut has_file = false;
    let mut children: Vec<PathBuf> = Vec::new();
    for entry in std::fs::read_dir(dir)? {
        let entry = entry?;
        if entry.file_type()?.is_dir() {
            children.push(entry.path());
        } else {
            has_file = true;
        }
    }
    if has_file {
        let relative = dir.strip_prefix(base)?;
        let parts: Vec<String> = relative
            .components()
            .map(|c| c.as_os_str().to_string_lossy().into_owned())
            .collect();
        out.push(format!("{}/", parts.join("/")));
    }
    for child in children {
        folders_with_files(&child, base, out)?;
    }
    Ok(())
}

/// `pubspec` with its `assets/game/` entries replaced by `heroes.json` and `folders`,
/// at the place the old ones were (after the levels entry when there were none). The
/// file's own line endings are kept.
pub fn rewrite_pubspec(pubspec: &str, folders: &[String]) -> anyhow::Result<String> {
    let newline = if pubspec.contains("\r\n") {
        "\r\n"
    } else {
        "\n"
    };
    let had_final_newline = pubspec.ends_with('\n');
    let is_game = |l: &str| l.trim_start().starts_with(ENTRY_PREFIX);
    let all: Vec<&str> = pubspec.lines().collect();
    let first_game = all.iter().position(|l| is_game(l));
    let mut lines: Vec<String> = all
        .iter()
        .filter(|l| !is_game(l))
        .map(|l| (*l).to_owned())
        .collect();
    let at = match first_game {
        Some(i) => i,
        None => {
            lines
                .iter()
                .position(|l| l.trim_end() == ANCHOR)
                .context("pubspec.yaml has no assets/levels/ entry to attach to")?
                + 1
        }
    };
    let entries = std::iter::once("    - assets/game/heroes.json".to_owned())
        .chain(folders.iter().map(|f| format!("    - {f}")));
    lines.splice(at..at, entries);
    let mut out = lines.join(newline);
    if had_final_newline {
        out.push_str(newline);
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    const BASE: &str = "flutter:\n  assets:\n    - assets/roles/\n    - assets/levels/\n    - assets/game/heroes.json\n    - assets/game/old/\n    - assets/tools/\n";

    fn folders() -> Vec<String> {
        vec![
            "assets/game/icons/heroes/A/abilities/".to_owned(),
            "assets/game/icons/heroes/A/perks/".to_owned(),
        ]
    }

    #[test]
    fn old_game_entries_are_replaced_and_the_rest_is_untouched() {
        let out = rewrite_pubspec(BASE, &folders()).unwrap();
        assert_eq!(
            out,
            "flutter:\n  assets:\n    - assets/roles/\n    - assets/levels/\n    - assets/game/heroes.json\n    - assets/game/icons/heroes/A/abilities/\n    - assets/game/icons/heroes/A/perks/\n    - assets/tools/\n"
        );
    }

    #[test]
    fn entries_stay_where_they_were_even_when_something_sits_before_them() {
        let base = "a:\n    - assets/levels/\n    - assets/tools/\n    - assets/game/heroes.json\n    - assets/game/old/\n";
        let out = rewrite_pubspec(base, &folders()).unwrap();
        assert!(out.starts_with(
            "a:\n    - assets/levels/\n    - assets/tools/\n    - assets/game/heroes.json\n    - assets/game/icons/heroes/A/abilities/\n"
        ));
        assert!(!out.contains("old/"));
    }

    #[test]
    fn running_it_twice_gives_the_same_file() {
        let once = rewrite_pubspec(BASE, &folders()).unwrap();
        assert_eq!(rewrite_pubspec(&once, &folders()).unwrap(), once);
    }

    #[test]
    fn windows_line_endings_are_kept() {
        let crlf = BASE.replace('\n', "\r\n");
        let out = rewrite_pubspec(&crlf, &folders()).unwrap();
        assert!(out.ends_with("\r\n"));
        assert!(!out.replace("\r\n", "").contains('\n'));
    }

    #[test]
    fn a_pubspec_without_the_anchor_is_an_error() {
        assert!(rewrite_pubspec("flutter:\n  assets:\n    - assets/roles/\n", &folders()).is_err());
    }
}
