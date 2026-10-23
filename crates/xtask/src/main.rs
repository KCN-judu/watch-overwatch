//! Development tasks for the repository, run as `cargo xtask <task>` from anywhere in it.
//!
//! They replace what used to be loose scripts, so the repository needs nothing but the
//! Rust toolchain: no second language to install, and the tasks are tested like the rest.
mod catalog;
mod game_assets;
mod notes;
mod package;

use anyhow::{Context, bail};
use std::path::{Path, PathBuf};

const USAGE: &str = "usage:
  cargo xtask sync-assets                      copy resources/game into the app and register it in pubspec.yaml
  cargo xtask slim-catalog <source> <target>   cut a full query_tool.json down to what the program reads
  cargo xtask update-catalog <dir>             rebuild the bundled catalog from the live files downloaded into <dir>
  cargo xtask package                          zip the release builds into dist/ with its sha256
  cargo xtask release-notes <version>          print the CHANGELOG section of <version> as release text";

fn main() -> anyhow::Result<()> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let root = repository_root()?;
    match args
        .iter()
        .map(String::as_str)
        .collect::<Vec<_>>()
        .as_slice()
    {
        ["sync-assets"] => game_assets::sync(&root),
        ["slim-catalog", source, target] => {
            catalog::slim_file(Path::new(source), Path::new(target))
        }
        ["update-catalog", dir] => catalog::update_file(
            Path::new(dir),
            &root.join("crates/watch-core/data/query_tool.min.json"),
        ),
        ["package"] => package::run(&root),
        ["release-notes", version] => notes::run(&root, version),
        _ => bail!("{USAGE}"),
    }
}

/// The repository root: two levels above this crate.
fn repository_root() -> anyhow::Result<PathBuf> {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .ancestors()
        .nth(2)
        .map(Path::to_path_buf)
        .context("cannot find the repository root")
}
