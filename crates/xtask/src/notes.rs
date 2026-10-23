//! `cargo xtask release-notes <version>`: the CHANGELOG section of one version, printed as
//! the GitHub release text. The app's update dialog shows that text as "更新内容".
use anyhow::bail;
use std::path::Path;

/// The body under `## <version>` (a heading such as `## 1.3.0（2026-10-24）`), up to the
/// next version, with the version as the title.
pub fn section(changelog: &str, version: &str) -> Option<String> {
    let version = version.trim_start_matches('v');
    let mut lines = changelog.lines();
    lines.find(|l| {
        l.strip_prefix("## ").is_some_and(|rest| {
            rest.strip_prefix(version)
                .is_some_and(|after| !after.starts_with(|c: char| c.is_ascii_digit() || c == '.'))
        })
    })?;
    let body: Vec<&str> = lines.take_while(|l| !l.starts_with("## ")).collect();
    let body = body.join("\n").trim().to_owned();
    (!body.is_empty()).then(|| format!("# Watch Overwatch {version}\n\n{body}\n"))
}

pub fn run(root: &Path, version: &str) -> anyhow::Result<()> {
    let changelog = std::fs::read_to_string(root.join("CHANGELOG.md"))?;
    let Some(text) = section(&changelog, version) else {
        bail!("CHANGELOG.md has no section for {version}");
    };
    print!("{text}");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    const LOG: &str = "# 变更记录\n\n## 未发布\n\n- 还没发\n\n## 1.10.0（2026-11-01）\n\n### 新增\n\n- 十\n\n## 1.1.0\n\n- 一\n";

    #[test]
    fn one_version_is_cut_out_up_to_the_next() {
        assert_eq!(
            section(LOG, "v1.10.0").unwrap(),
            "# Watch Overwatch 1.10.0\n\n### 新增\n\n- 十\n"
        );
        assert_eq!(
            section(LOG, "1.1.0").unwrap(),
            "# Watch Overwatch 1.1.0\n\n- 一\n"
        );
        assert!(section(LOG, "1.1").is_none());
        assert!(section(LOG, "2.0.0").is_none());
    }
}
