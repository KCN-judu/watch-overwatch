use axum::{
    Json,
    http::StatusCode,
    response::{IntoResponse, Response},
};
use serde::Deserialize;
use serde_json::{Value, json};
use std::{io::Write, path::Path};

#[derive(Deserialize)]
pub struct Input {
    file_name: String,
    content: Value,
}

fn write_export(dir: &Path, input: Input) -> anyhow::Result<Value> {
    let stem: String = input
        .file_name
        .trim_end_matches(".json")
        .chars()
        .take(100)
        .map(|c| {
            if c.is_alphanumeric() || matches!(c, '-' | '_' | '#') {
                c
            } else {
                '_'
            }
        })
        .collect();
    let stem = if stem.is_empty() {
        "watch-overwatch"
    } else {
        &stem
    };
    std::fs::create_dir_all(dir)?;
    let file_name = format!("{stem}-{}.json", uuid::Uuid::new_v4());
    let path = dir.join(&file_name);
    let mut bytes = serde_json::to_vec_pretty(&input.content)?;
    bytes.push(b'\n');
    let mut file = std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&path)?;
    if let Err(error) = file.write_all(&bytes).and_then(|()| file.sync_all()) {
        drop(file);
        let _ = std::fs::remove_file(&path);
        return Err(error.into());
    }
    Ok(
        json!({"ok":true,"path":path.display().to_string(),"file_name":file_name,"bytes":bytes.len()}),
    )
}

pub async fn save(Json(input): Json<Input>) -> Response {
    match tokio::task::spawn_blocking(move || {
        write_export(&watch_core::data_dir().join("exports"), input)
    })
    .await
    {
        Ok(Ok(result)) => Json(result).into_response(),
        _ => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(
                json!({"error":{"message":"JSON 保存失败，请检查本机导出目录的权限与剩余空间。"}}),
            ),
        )
            .into_response(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn contains_paths_and_preserves_existing_exports() {
        let dir = std::env::temp_dir().join(format!("watch-export-{}", uuid::Uuid::new_v4()));
        let save = || {
            write_export(
                &dir,
                Input {
                    file_name: "../../CON/玩家.json".into(),
                    content: json!({"hero":"安娜","damage_blocked":123}),
                },
            )
            .unwrap()
        };
        let first = save();
        let second = save();
        let path = std::path::PathBuf::from(first["path"].as_str().unwrap());
        assert_eq!(path.parent(), Some(dir.as_path()));
        assert_ne!(first["path"], second["path"]);
        let data: Value = serde_json::from_slice(&std::fs::read(path).unwrap()).unwrap();
        assert_eq!(data["hero"], "安娜");
        assert_eq!(std::fs::read_dir(&dir).unwrap().count(), 2);
        std::fs::remove_dir_all(dir).unwrap();
    }
}
