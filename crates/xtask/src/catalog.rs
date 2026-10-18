//! Cuts the game's full `query_tool.json` down to the fields the program reads, which is
//! what `crates/watch-core/data/query_tool.min.json` holds.
use anyhow::{Context, anyhow};
use serde_json::{Map, Value, json};
use std::path::Path;

/// The object `o` reduced to the keys in `keep` (those it has).
fn pick(o: &Value, keep: &[&str]) -> Value {
    let mut out = Map::new();
    for key in keep {
        if let Some(v) = o.get(*key) {
            out.insert((*key).to_owned(), v.clone());
        }
    }
    Value::Object(out)
}

fn pick_each(list: &Value, keep: &[&str]) -> Value {
    Value::Array(
        list.as_array()
            .map(|a| a.iter().map(|o| pick(o, keep)).collect())
            .unwrap_or_default(),
    )
}

/// A map of lists, each list reduced like [`pick_each`].
fn pick_each_in_map(map: &Value, keep: &[&str]) -> Value {
    Value::Object(
        map.as_object()
            .map(|m| {
                m.iter()
                    .map(|(k, v)| (k.clone(), pick_each(v, keep)))
                    .collect()
            })
            .unwrap_or_default(),
    )
}

fn required<'a>(full: &'a Value, key: &str) -> anyhow::Result<&'a Value> {
    full.get(key)
        .ok_or_else(|| anyhow!("the source has no `{key}`"))
}

fn or(full: &Value, key: &str, default: Value) -> Value {
    full.get(key).cloned().unwrap_or(default)
}

/// The slimmed catalog. Slimming a slimmed catalog changes nothing.
pub fn slim(full: &Value) -> anyhow::Result<Value> {
    Ok(json!({
        "heroList": pick_each(required(full, "heroList")?, &[
            "id", "heroGuid", "roleGuid", "roleType", "name", "icon", "smallIconUrl",
            "cover", "ddHeroIcon", "destinyHeroBanner", "isStadium",
        ]),
        "mapList": pick_each(required(full, "mapList")?, &["guid", "id", "icon", "name", "mode"]),
        "heroAttrList": pick_each(
            required(full, "heroAttrList")?,
            &["heroGuid", "valueGuid", "valueText", "valueType"],
        ),
        "perkList": pick_each(required(full, "perkList")?, &["id", "guid", "name", "icon"]),
        "heroPerkList": pick_each_in_map(
            required(full, "heroPerkList")?,
            &["heroId", "id", "name", "icon"],
        ),
        "modTrait": pick_each_in_map(
            required(full, "modTrait")?,
            &["heroId", "id", "name", "category", "level"],
        ),
        "seasonList": or(full, "seasonList", json!({})),
        "rankList": pick_each(&or(full, "rankList", json!([])), &["key", "icon", "level"]),
        "rankListFight": pick_each(&or(full, "rankListFight", json!([])), &["key", "icon"]),
        "appreciationLevelIcon": or(full, "appreciationLevelIcon", json!({})),
        "AIEvaluateConfig": or(full, "AIEvaluateConfig", json!([])),
    }))
}

fn size(v: &Value) -> usize {
    match v {
        Value::Array(a) => a.len(),
        Value::Object(o) => o.len(),
        _ => 0,
    }
}

/// Reads `source`, slims it and writes the compact result to `target`.
pub fn slim_file(source: &Path, target: &Path) -> anyhow::Result<()> {
    let full: Value = serde_json::from_slice(
        &std::fs::read(source).with_context(|| format!("cannot read {}", source.display()))?,
    )
    .with_context(|| format!("{} is not JSON", source.display()))?;
    let slimmed = slim(&full)?;
    std::fs::write(target, serde_json::to_vec(&slimmed)?)
        .with_context(|| format!("cannot write {}", target.display()))?;
    let counts: Vec<String> = slimmed
        .as_object()
        .into_iter()
        .flatten()
        .map(|(k, v)| format!("{k}: {}", size(v)))
        .collect();
    println!("{}", counts.join(", "));
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn bundled() -> Value {
        let path =
            Path::new(env!("CARGO_MANIFEST_DIR")).join("../watch-core/data/query_tool.min.json");
        serde_json::from_slice(&std::fs::read(path).unwrap()).unwrap()
    }

    #[test]
    fn slimming_the_bundled_snapshot_changes_nothing() {
        let snapshot = bundled();
        assert_eq!(slim(&snapshot).unwrap(), snapshot);
    }

    #[test]
    fn fields_the_program_does_not_read_are_dropped() {
        let mut full = bundled();
        full["heroList"][0]["lore"] = json!("a very long story");
        full["mapList"][0]["internalFlag"] = json!(true);
        full["somethingElse"] = json!([1, 2, 3]);
        let out = slim(&full).unwrap();
        assert!(out["heroList"][0].get("lore").is_none());
        assert!(out["mapList"][0].get("internalFlag").is_none());
        assert!(out.get("somethingElse").is_none());
        assert_eq!(out, slim(&bundled()).unwrap());
    }

    #[test]
    fn a_source_without_the_main_lists_is_an_error_not_an_empty_catalog() {
        assert!(slim(&json!({"mapList": []})).is_err());
    }
}
