use axum::{
    Json,
    extract::State,
    http::StatusCode,
    response::{IntoResponse, Response},
};
use serde::Deserialize;
use std::path::Path;
fn read(path: &Path) -> anyhow::Result<Vec<String>> {
    if !path.exists() {
        return Ok(Vec::new());
    }
    Ok(serde_json::from_slice(&std::fs::read(path)?)?)
}
fn update(path: &Path, name: &str, remove: bool) -> anyhow::Result<Vec<String>> {
    let name = name.trim();
    anyhow::ensure!(
        !name.is_empty() && name.len() <= 128 && !name.chars().any(char::is_control),
        "Invalid BattleTag"
    );
    let mut players = read(path)?;
    players.retain(|v| !v.eq_ignore_ascii_case(name));
    if !remove {
        players.insert(0, name.to_owned());
    }
    std::fs::create_dir_all(path.parent().unwrap())?;
    let temporary = path.with_extension(format!("{}.tmp", uuid::Uuid::new_v4()));
    std::fs::write(&temporary, serde_json::to_vec_pretty(&players)?)?;
    std::fs::rename(temporary, path)?;
    Ok(players)
}
pub async fn list(State(s): State<crate::AppState>) -> Response {
    let _guard = s.settings_lock.lock().await;
    respond(read(&watch_core::data_dir().join("players.json")))
}
#[derive(Deserialize)]
pub struct Input {
    name: String,
    #[serde(default)]
    remove: bool,
}
pub async fn save(State(s): State<crate::AppState>, Json(input): Json<Input>) -> Response {
    let _guard = s.settings_lock.lock().await;
    respond(update(
        &watch_core::data_dir().join("players.json"),
        &input.name,
        input.remove,
    ))
}
fn respond(result: anyhow::Result<Vec<String>>) -> Response {
    match result {
        Ok(players) => Json(players).into_response(),
        Err(_) => (StatusCode::INTERNAL_SERVER_ERROR, Json(serde_json::json!({"error":{"message":"无法读取或保存本机玩家列表，请检查文件权限。"}}))).into_response(),
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn persists_deduplicates_and_removes() {
        let dir = std::env::temp_dir().join(format!("watch-players-{}", uuid::Uuid::new_v4()));
        let path = dir.join("players.json");
        assert!(read(&path).unwrap().is_empty());
        update(&path, "Player#12345", false).unwrap();
        update(&path, "player#12345", false).unwrap();
        assert_eq!(read(&path).unwrap(), vec!["player#12345"]);
        assert!(update(&path, " Player#12345 ", true).unwrap().is_empty());
        assert!(update(&path, "", false).is_err());
        std::fs::remove_dir_all(dir).unwrap();
    }
}
