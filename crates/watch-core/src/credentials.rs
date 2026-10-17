use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};

#[cfg(target_os = "windows")]
fn local_app_data_dir() -> Option<PathBuf> {
    use std::{ffi::OsString, os::windows::ffi::OsStringExt, ptr};
    use windows_sys::Win32::{
        System::Com::CoTaskMemFree,
        UI::Shell::{FOLDERID_LocalAppData, SHGetKnownFolderPath},
    };

    let mut raw = ptr::null_mut();
    // The shell API resolves the current user's redirected Local AppData folder
    // without depending on the environment inherited by a background process.
    let result =
        unsafe { SHGetKnownFolderPath(&FOLDERID_LocalAppData, 0, ptr::null_mut(), &mut raw) };
    if result < 0 || raw.is_null() {
        return None;
    }
    let mut len = 0;
    unsafe {
        while *raw.add(len) != 0 {
            len += 1;
        }
    }
    let path = PathBuf::from(OsString::from_wide(unsafe {
        std::slice::from_raw_parts(raw, len)
    }));
    unsafe { CoTaskMemFree(raw.cast()) };
    Some(path)
}

#[cfg(not(target_os = "windows"))]
fn local_app_data_dir() -> Option<PathBuf> {
    std::env::var_os("LOCALAPPDATA").map(PathBuf::from)
}

// No Debug implementation: token values must never enter diagnostic logs.
#[derive(Clone, Serialize, Deserialize)]
pub struct AccountSecret {
    pub name: String,
    pub role_id: u64,
    pub token: String,
    #[serde(default = "default_dts")]
    pub dts: u32,
    #[serde(default = "default_server")]
    pub server: u32,
}
fn default_dts() -> u32 {
    2026
}
fn default_server() -> u32 {
    1
}
#[derive(Clone, Serialize, Deserialize, Default)]
pub struct SecretsFile {
    pub accounts: Vec<AccountSecret>,
}
impl SecretsFile {
    pub fn validate(&self) -> anyhow::Result<()> {
        let mut names = std::collections::HashSet::new();
        for a in &self.accounts {
            anyhow::ensure!(
                !a.name.trim().is_empty() && names.insert(&a.name),
                "Account names must be unique and nonempty"
            );
            anyhow::ensure!(
                a.role_id > 0 && !a.token.trim().is_empty() && !a.token.starts_with("replace-"),
                "Account credentials are incomplete"
            );
            anyhow::ensure!(
                a.token.bytes().all(|c| c.is_ascii_graphic()),
                "Token contains invalid characters"
            );
        }
        Ok(())
    }
}
pub fn data_dir() -> PathBuf {
    local_app_data_dir()
        .or_else(|| std::env::var_os("LOCALAPPDATA").map(PathBuf::from))
        .or_else(|| {
            std::env::var_os("USERPROFILE")
                .map(PathBuf::from)
                .map(|path| path.join("AppData").join("Local"))
        })
        .unwrap_or_else(|| PathBuf::from("."))
        .join("Watch Overwatch")
}
pub fn secrets_path() -> PathBuf {
    data_dir().join("secrets.json")
}
pub fn load_secrets() -> anyhow::Result<SecretsFile> {
    if !secrets_path().exists() {
        return Ok(SecretsFile::default());
    }
    let secrets: SecretsFile =
        serde_json::from_slice(&std::fs::read(secrets_path())?).map_err(|_| {
            anyhow::anyhow!("secrets.json is invalid; check the documented JSON structure")
        })?;
    secrets.validate()?;
    Ok(secrets)
}
pub fn save_secrets(secrets: &SecretsFile) -> anyhow::Result<()> {
    secrets.validate()?;
    std::fs::create_dir_all(data_dir())?;
    let temporary = data_dir().join(format!("secrets-{}.tmp", uuid::Uuid::new_v4()));
    std::fs::write(&temporary, serde_json::to_vec_pretty(secrets)?)?;
    std::fs::rename(temporary, secrets_path())?;
    Ok(())
}
/// Read only literal credentials. Never executes the Python configuration.
pub fn import_legacy(path: &Path) -> anyhow::Result<usize> {
    anyhow::ensure!(
        !secrets_path().exists(),
        "A secrets file already exists; import will not overwrite it"
    );
    let text = std::fs::read_to_string(path)?;
    let uncommented = text
        .lines()
        .filter(|line| !line.trim_start().starts_with('#'))
        .collect::<Vec<_>>()
        .join("\n");
    let block = regex::Regex::new(r"(?s)DASHEN_ACCOUNTS\s*=\s*\[(.*?)\]")?
        .captures(&uncommented)
        .ok_or_else(|| anyhow::anyhow!("No literal DASHEN_ACCOUNTS list found"))?[1]
        .to_string();
    let objects = regex::Regex::new(r"(?s)\{([^{}]*)\}")?;
    let name_re = regex::Regex::new(r#"["']name["']\s*:\s*["']([^"']+)["']"#)?;
    let role_re = regex::Regex::new(r#"["']role_id["']\s*:\s*(\d+)"#)?;
    let token_re = regex::Regex::new(r#"["']token["']\s*:\s*["']([^"']+)["']"#)?;
    let mut accounts = Vec::new();
    for object in objects.captures_iter(&block) {
        let value = &object[1];
        let name = name_re
            .captures(value)
            .ok_or_else(|| anyhow::anyhow!("Missing account name"))?[1]
            .to_string();
        let role_id = role_re
            .captures(value)
            .ok_or_else(|| anyhow::anyhow!("Missing role id"))?[1]
            .parse()?;
        let token = token_re
            .captures(value)
            .ok_or_else(|| anyhow::anyhow!("Missing token"))?[1]
            .to_string();
        accounts.push(AccountSecret {
            name,
            role_id,
            token,
            dts: default_dts(),
            server: default_server(),
        });
    }
    anyhow::ensure!(!accounts.is_empty(), "No accounts found");
    let count = accounts.len();
    save_secrets(&SecretsFile { accounts })?;
    Ok(count)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn data_dir_is_the_user_local_app_data_folder() {
        let path = data_dir();
        assert_eq!(
            path.file_name().and_then(|name| name.to_str()),
            Some("Watch Overwatch")
        );
        #[cfg(target_os = "windows")]
        assert!(
            path.parent()
                .is_some_and(|parent| parent.ends_with("AppData\\Local"))
        );
    }
}
