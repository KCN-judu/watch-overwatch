use crate::ir::{EntityRef, MatchDetail, MatchSummary, Outcome, Participant, StatLine};
use serde::Serialize;
use serde_json::{Value, json};
use std::collections::BTreeMap;

/// Versioned, credential-free interchange envelope. Provider fields are isolated.
#[derive(Serialize)]
pub struct ExportDocument {
    pub schema_version: &'static str,
    pub generated_at_unix_ms: u128,
    pub source: Value,
    pub query: Value,
    pub completeness: Value,
    pub units: Value,
    pub entities: Vec<Value>,
    pub records: Value,
    pub provider_data: Value,
}
pub fn sanitize(mut value: Value) -> Value {
    match &mut value {
        Value::Object(o) => {
            o.retain(|k, _| {
                let k = k.to_ascii_lowercase().replace(['_', '-'], "");
                ![
                    "token",
                    "apikey",
                    "cookie",
                    "authorization",
                    "password",
                    "traceid",
                ]
                .iter()
                .any(|secret| k.contains(secret))
                    && k != "session"
            });
            for v in o.values_mut() {
                *v = sanitize(v.take());
            }
        }
        Value::Array(a) => {
            for v in a {
                *v = sanitize(v.take());
            }
        }
        _ => {}
    }
    value
}
#[derive(Debug, Clone, Serialize)]
pub struct Completeness {
    /// `complete`, `partial` (page limit reached), `page` (one page) or `provider_snapshot`.
    pub status: &'static str,
    pub page_limit: Option<u32>,
    pub cached: Option<bool>,
    pub season_errors: usize,
}

/// Typed input for an export. Records are projected from the IR; provider JSON
/// appears only in `provider_data`, and only for technical exports.
pub struct ExportSource<'a> {
    pub view: &'a str,
    pub query: Value,
    pub player_name: Option<&'a str>,
    pub matches: &'a [MatchSummary],
    pub details: &'a BTreeMap<String, MatchDetail>,
    pub summary: Value,
    pub completeness: Completeness,
    pub provider_data: Value,
    pub technical: bool,
}

fn name_or(e: Option<&EntityRef>, fallback: &str) -> String {
    e.and_then(|e| e.name.clone())
        .unwrap_or_else(|| fallback.to_owned())
}

fn export_stats(s: &StatLine) -> Value {
    json!({"kills":s.kills,"assists":s.assists,"deaths":s.deaths,"damage":s.damage,"healing":s.healing,"blocked_damage":s.mitigation,"mitigation":s.mitigation})
}

fn export_people(players: &[Participant]) -> Vec<Value> {
    players
        .iter()
        .map(|p| {
            json!({
                "player_name": p.name.as_deref().unwrap_or("未知玩家"),
                "hero_name": name_or(p.hero.as_ref(), "未知英雄"),
                "hero_role": p.role.name_zh(),
                "stats": export_stats(&p.stats),
            })
        })
        .collect()
}

pub fn build_export(src: ExportSource) -> ExportDocument {
    let mut entities = BTreeMap::new();
    let mut note = |e: Option<&EntityRef>| {
        if let Some(e) = e {
            let name = e.name.clone().unwrap_or_else(|| "未知".into());
            entities.insert(
                format!("{}:{name}", e.kind.as_str()),
                json!({"kind":e.kind.as_str(),"name":name}),
            );
        }
    };
    for m in src.matches {
        note(m.hero.as_ref());
        note(m.map.as_ref());
        if let Some(d) = src.details.get(&m.id) {
            for p in d.allies.iter().chain(&d.enemies) {
                note(p.hero.as_ref());
            }
        }
    }
    let matches: Vec<Value> = src
        .matches
        .iter()
        .enumerate()
        .map(|(index, m)| {
            let detail = src.details.get(&m.id);
            json!({
                "match_index": index,
                "player_name": src.player_name,
                "outcome": match m.outcome { Outcome::Win => "win", Outcome::Loss => "loss", Outcome::Draw => "draw", Outcome::Unknown => "unknown" },
                "started_at_unix_ms": m.started_at_ms,
                "hero_name": name_or(m.hero.as_ref(), "未知英雄"),
                "hero_role": m.role.name_zh(),
                "map_name": name_or(m.map.as_ref(), "未知地图"),
                "score": [m.score.team, m.score.opponent],
                "stats": export_stats(&m.stats),
                "teammates": detail.map(|d| export_people(&d.allies)).unwrap_or_default(),
                "enemies": detail.map(|d| export_people(&d.enemies)).unwrap_or_default(),
            })
        })
        .collect();
    let technical = src.technical;
    ExportDocument {
        schema_version: "1.1.0",
        generated_at_unix_ms: crate::now_ms(),
        source: json!({"provider":"netease_dashen","client":"Watch Overwatch","client_version":env!("CARGO_PKG_VERSION")}),
        query: sanitize(src.query),
        completeness: serde_json::to_value(&src.completeness).unwrap_or(Value::Null),
        units: json!({"timestamps":"unix_milliseconds","durations":"seconds","win_rate":"percent_0_100","missing_values":"null","summary_win_rate_denominator":"wins_plus_losses","identifier_policy":if technical{"provider_identifiers_in_provider_data"}else{"friendly_names_only"},"provider_fields":if technical{"sanitized_provider_snapshot"}else{"excluded_by_default"}}),
        entities: entities.into_values().collect(),
        records: json!({"player_name":src.player_name,"matches":matches,"summary":src.summary}),
        provider_data: if technical {
            sanitize(src.provider_data)
        } else {
            Value::Null
        },
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        Catalog,
        dashen::{Mode, normalize},
    };
    #[test]
    fn exports_preserve_missing_stats_without_ids_or_secrets() {
        let cat = Catalog::default();
        let matches = normalize::match_list(
            &json!([{"matchId":"m","matchRet":1,"heroGuid":"42","customerToken":"secret"}]),
            Mode::Competitive,
            &cat,
        );
        let mut details = BTreeMap::new();
        details.insert(
            "m".to_string(),
            normalize::match_detail(
                "m",
                &json!({"teammateList":[{"name":"A#1","customerToken":"secret","kill":3}]}),
                Mode::Competitive,
                None,
                &cat,
            ),
        );
        let e = build_export(ExportSource {
            view: "matches",
            query: json!({"session":"secret"}),
            player_name: Some("P#1"),
            matches: &matches,
            details: &details,
            summary: Value::Null,
            completeness: Completeness {
                status: "page",
                page_limit: None,
                cached: Some(false),
                season_errors: 0,
            },
            provider_data: json!({"customerToken":"secret","x_api_key":"secret"}),
            technical: true,
        });
        let v = serde_json::to_value(e).unwrap();
        let m = &v["records"]["matches"][0];
        assert_eq!(m["outcome"], "win");
        assert_eq!(m["stats"]["damage"], Value::Null);
        assert_eq!(m["teammates"][0]["stats"]["kills"], 3.0);
        assert_eq!(v["entities"][0]["name"], "未知");
        assert!(m.get("match_id").is_none());
        assert_eq!(m["hero_name"], "未知英雄");
        assert!(!v.to_string().contains("secret"));

        // The published schema describes this document: every required field is there,
        // and a technical export's provider data is a type the schema allows.
        let schema: Value =
            serde_json::from_str(include_str!("../../../docs/watch-overwatch.schema.json"))
                .unwrap();
        for key in schema["required"].as_array().unwrap() {
            assert!(v.get(key.as_str().unwrap()).is_some(), "missing {key}");
        }
        let allowed = &schema["properties"]["provider_data"]["type"];
        assert!(allowed.as_array().unwrap().contains(&json!("object")));
        assert!(v["provider_data"].is_object());
    }
}
