//! Development tasks for the repository, run as `cargo xtask <task>` from anywhere in it.
//!
//! They replace what used to be loose scripts, so the repository needs nothing but the
//! Rust toolchain: no second language to install, and the tasks are tested like the rest.
mod catalog;
mod game_assets;

use anyhow::{Context, bail};
use std::path::{Path, PathBuf};

const USAGE: &str = "usage:
  cargo xtask sync-assets                      copy resources/game into the app and register it in pubspec.yaml
  cargo xtask slim-catalog <source> <target>   cut a full query_tool.json down to what the program reads";

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
