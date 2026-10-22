use crate::data_dir;
use crate::ir::{EntityKind, EntityRef, Role, official_id};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::{
    collections::HashMap,
    path::Path,
    sync::{
        OnceLock,
        atomic::{AtomicU32, Ordering},
    },
};

/// The season the provider is in now. It starts as the newest season the catalog knows,
/// and moves forward while running when the provider is seen to have started a new one
/// before the catalog was updated (see [`crate::collect::same_season_data`]); it never
/// moves back. Serialised as the plain number.
#[derive(Default)]
pub struct CurrentSeason(AtomicU32);

impl CurrentSeason {
    pub fn new(season: u32) -> Self {
        Self(AtomicU32::new(season))
    }
    pub fn get(&self) -> u32 {
        self.0.load(Ordering::Relaxed)
    }
    /// Moves to `season` if that is later; returns whether it moved.
    pub fn advance_to(&self, season: u32) -> bool {
        self.0.fetch_max(season, Ordering::Relaxed) < season
    }
}

impl Clone for CurrentSeason {
    fn clone(&self) -> Self {
        Self::new(self.get())
    }
}

impl Serialize for CurrentSeason {
    fn serialize<S: serde::Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_u32(self.get())
    }
}

impl<'de> Deserialize<'de> for CurrentSeason {
    fn deserialize<D: serde::Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        u32::deserialize(d).map(Self::new)
    }
}

/// When the catalog names no season at all.
const FALLBACK_SEASON: u32 = 25;

#[derive(Clone, Default, Serialize, Deserialize)]
pub struct Catalog {
    pub heroes: HashMap<String, Value>,
    pub maps: HashMap<String, Value>,
    pub current_season: CurrentSeason,
    #[serde(default)]
    pub statistics: Vec<Value>,
    #[serde(default)]
    pub perks: Value,
    #[serde(default)]
    pub hero_config: Value,
    /// `perkList`: perks keyed by decimal GUID.
    #[serde(default)]
    pub perk_list: Vec<Value>,
    /// `modTrait`: stadium powers and items keyed by hero hex id.
    #[serde(default)]
    pub mod_traits: Value,
    /// Official interface icons the provider ships: rank tiers (normal and
    /// stadium) and endorsement levels. Image addresses only.
    #[serde(default)]
    pub icons: Value,
    #[serde(skip)]
    index: OnceLock<Index>,
}
/// Name lookups by `0x…` official id, built once from the raw catalog lists.
#[derive(Clone, Default)]
struct Index {
    stats: HashMap<String, (String, bool)>,
    perks: HashMap<String, String>,
    upgrades: HashMap<String, String>,
}
impl Catalog {
    fn portrait_for_name(name: &str) -> Option<String> {
        let known = match name {
            "莱因哈特" => {
                "https://d15f34w2p8l1cc.cloudfront.net/overwatch/551fbe070c16fdfcc17f7f1de63af22c53e7d2f1340fc2f3172441504527bc4e.png"
            }
            "卡西迪" => {
                "https://d15f34w2p8l1cc.cloudfront.net/overwatch/9240cd64cc8ef58df9acbf55204ab1b5d8578f743fda5931f0dbccbd75ab841b.png"
            }
            "安娜" => {
                "https://d15f34w2p8l1cc.cloudfront.net/overwatch/985b06beae46b7ba3ca87d1512d0fc62ca7f206ceca58ef16fc44d43a1cc84ed.png"
            }
            "源氏" => {
                "https://d15f34w2p8l1cc.cloudfront.net/overwatch/156b12c20b1aea872c1eeb5bb37a7de1047b2ab30ecefd0663a8925badde1ea8.png"
            }
            "半藏" => {
                "https://d15f34w2p8l1cc.cloudfront.net/overwatch/78b61c3e806fb26b02b8980fba62189155074fc15bd865b0883268e546030be5.png"
            }
            "末日铁拳" => {
                "https://d15f34w2p8l1cc.cloudfront.net/overwatch/ff5c54f43ad253c7faeda9c4ed31d42582ea6b19205d197866f3dd0c0aa14c16.png"
            }
            "天使" => {
                "https://d15f34w2p8l1cc.cloudfront.net/overwatch/3bfb8bd8ec827e53d870f1238ab73d8aa1f5dbfbcfaaf7f96ffcd35b5c6102ab.png"
            }
            "路西奥" => {
                "https://d15f34w2p8l1cc.cloudfront.net/overwatch/040bb13f5123ab93faad2f95627ba184608aef4b2469a4d3003859c7087df044.png"
            }
            "小美" => {
                "https://d15f34w2p8l1cc.cloudfront.net/overwatch/4a55ced3bd597fb08e0fde9dc007f8543ac616ba98ca3db9b0e4d871a8ae17f8.png"
            }
            "莫伊拉" => {
                "https://d15f34w2p8l1cc.cloudfront.net/overwatch/f48f8485056d5d00dad195859188d23e50f7126b8b08b5646f46ef1b42f5e1de.png"
            }
            "奥丽莎" => {
                "https://d15f34w2p8l1cc.cloudfront.net/overwatch/a73958a28551f5254f3ab3f97c5f5f8d698a95c0b6a515d1a2b1caac169205a6.png"
            }
            "路霸" => {
                "https://d15f34w2p8l1cc.cloudfront.net/overwatch/89ddf07e4b619ed96169042e296a1b8856d102746f35add88284b44a9a5a6a03.png"
            }
            "死神" => {
                "https://d15f34w2p8l1cc.cloudfront.net/overwatch/dc6ff07ac790c00dc95a40882449617bb6e0e38906b353a630cffe0c815270a9.png"
            }
            "西格玛" => {
                "https://d15f34w2p8l1cc.cloudfront.net/overwatch/a4c032fa466c9a6d9c6974747635d7ef910027f91cd58892af0c899db565f92d.png"
            }
            "索洁恩" => {
                "https://d15f34w2p8l1cc.cloudfront.net/overwatch/82b8c1b8765dcb9a0ba16e343c3516bf324c771ac81e9878473280216e70a889.png"
            }
            "黑影" => {
                "https://d15f34w2p8l1cc.cloudfront.net/overwatch/47727b02a16e3bd7b2447d86ae1edf11587bc320b2aecb4f2f16a7ca4ad4e8a0.png"
            }
            "秩序之光" => {
                "https://d15f34w2p8l1cc.cloudfront.net/overwatch/ebec57e8bd68b3d4383edfeb34f8f52dd0b94a6467d594c2fee722e8a97c32aa.png"
            }
            "闪光" => {
                "https://d15f34w2p8l1cc.cloudfront.net/overwatch/4504f6f15cb3feaa92ecd38e01dcf751cb5abdac2e0bb52d0555727e53277502.png"
            }
            "温斯顿" => {
                "https://d15f34w2p8l1cc.cloudfront.net/overwatch/46a10db3aa908c590ddc4e7606376a88143d1f1306ecfbea043263040f9529a5.png"
            }
            "破坏球" => {
                "https://d15f34w2p8l1cc.cloudfront.net/overwatch/9ef1d58867136e0b26f928d896000b9dab216118f6e2f59e53f2e975e1e27afa.png"
            }
            _ => {
                return serde_json::from_str::<Value>(include_str!(
                    "../../../ui/hero-portraits.json"
                ))
                .ok()
                .and_then(|value| value["portraits"][name].as_str().map(str::to_owned));
            }
        };
        Some(known.to_owned())
    }
    fn icons_from(raw: &Value) -> Value {
        let tiers = |key: &str, field: &str| -> serde_json::Map<String, Value> {
            raw[key]
                .as_array()
                .into_iter()
                .flatten()
                .filter_map(|r| {
                    let value = match field {
                        "name" => json!(clean_name(r[field].as_str()?)?),
                        _ => r[field].clone(),
                    };
                    Some((r["key"].as_str()?.to_owned(), value))
                })
                .collect()
        };
        // Perk icons by `0x…` id, from the shared list and the per-hero list.
        let mut perks = serde_json::Map::new();
        let perk_lists = raw["perkList"].as_array().into_iter().flatten().chain(
            raw["heroPerkList"]
                .as_object()
                .into_iter()
                .flat_map(|o| o.values())
                .filter_map(Value::as_array)
                .flatten(),
        );
        for perk in perk_lists {
            let id = perk["guid"]
                .as_str()
                .and_then(official_id)
                .or_else(|| perk["id"].as_str().map(str::to_owned));
            if let (Some(id), Some(icon)) = (id, perk["icon"].as_str()) {
                perks.entry(id).or_insert_with(|| json!(icon));
            }
        }
        json!({
            "perks": perks,
            "ranks": tiers("rankList", "icon"),
            "ranks_stadium": tiers("rankListFight", "icon"),
            // The provider's own tier names: 英杰 for the top normal tier, and the Stadium
            // ladder's own names (菜鸟 … 传奇), which differ from the normal ones.
            "rank_names": tiers("rankList", "name"),
            "rank_names_stadium": tiers("rankListFight", "name"),
            "endorsement": raw["appreciationLevelIcon"],
        })
    }
    pub fn from_legacy(raw: &Value) -> Self {
        let mut result = Self {
            current_season: CurrentSeason::new(FALLBACK_SEASON),
            ..Self::default()
        };
        if let Some(heroes) = raw.get("heroList").and_then(Value::as_array) {
            for h in heroes {
                if let Some(id) = h.get("heroGuid").and_then(Value::as_str) {
                    result.heroes.insert(
                        id.into(),
                        json!({"name":h["name"],"official_id":h["id"],"icon":h["icon"],"small_icon":h["smallIconUrl"],"cover":h["cover"],"art":h["ddHeroIcon"],"banner":h["destinyHeroBanner"],"role":h["roleType"],"portrait":Self::portrait_for_name(h["name"].as_str().unwrap_or(""))}),
                    );
                }
            }
        }
        if let Some(maps) = raw.get("mapList").and_then(Value::as_array) {
            for m in maps {
                if let Some(id) = m.get("guid").and_then(Value::as_str) {
                    result
                        .maps
                        .insert(id.into(), json!({"name":m["name"],"official_id":m["id"],"mode":m["mode"],"icon":m["icon"]}));
                }
            }
        }
        if let Some(evaluations) = raw.get("AIEvaluateConfig").and_then(Value::as_array) {
            for e in evaluations {
                if let Some(seasons) = e.get("seasonIdList").and_then(Value::as_array) {
                    for s in seasons {
                        if let Some(n) = s
                            .as_u64()
                            .or_else(|| s.as_str().and_then(|s| s.parse().ok()))
                            && n <= 100
                        {
                            result.current_season.advance_to(n as u32);
                        }
                    }
                }
            }
        }
        result.statistics = raw["heroAttrList"].as_array().cloned().unwrap_or_default();
        result.perks = raw["heroPerkList"].clone();
        result.hero_config = raw["heroConfig"].clone();
        result.perk_list = raw["perkList"].as_array().cloned().unwrap_or_default();
        result.mod_traits = raw["modTrait"].clone();
        result.icons = Self::icons_from(raw);
        if let Some(seasons) = raw["seasonList"].as_object() {
            for key in seasons.keys() {
                if let Ok(n) = key.parse::<u32>() {
                    result.current_season.advance_to(n);
                }
            }
        }
        result
    }
    /// The imported catalog if present, otherwise the bundled snapshot
    /// (`data/query_tool.min.json`, regenerated with `cargo xtask slim-catalog`).
    pub fn load() -> Self {
        std::fs::read(data_dir().join("catalog.json"))
            .ok()
            .and_then(|bytes| serde_json::from_slice(&bytes).ok())
            .unwrap_or_else(Self::bundled)
    }
    pub fn bundled() -> Self {
        serde_json::from_str::<Value>(include_str!("../data/query_tool.min.json"))
            .map(|raw| Self::from_legacy(&raw))
            .unwrap_or(Self {
                current_season: CurrentSeason::new(FALLBACK_SEASON),
                ..Self::default()
            })
    }
    pub fn import(path: &Path) -> anyhow::Result<()> {
        let raw: Value = serde_json::from_slice(&std::fs::read(path)?)?;
        let catalog = Self::from_legacy(&raw);
        std::fs::create_dir_all(data_dir())?;
        std::fs::write(
            data_dir().join("catalog.json"),
            serde_json::to_vec_pretty(&catalog)?,
        )?;
        Ok(())
    }
    pub fn enrich(&self, value: &mut Value) {
        match value {
            Value::Object(object) => {
                let hero = object
                    .get("heroGuid")
                    .or_else(|| object.get("heroId"))
                    .and_then(Value::as_str)
                    .and_then(|id| self.heroes.get(id));
                if let Some(hero) = hero {
                    object.insert("heroName".into(), hero["name"].clone());
                    if !object.contains_key("heroIcon") {
                        object.insert("heroIcon".into(), hero["icon"].clone());
                    }
                    if hero["portrait"].is_string() && !object.contains_key("heroPortrait") {
                        object.insert("heroPortrait".into(), hero["portrait"].clone());
                    }
                    if !object.contains_key("heroPortrait")
                        && let Some(name) = hero["name"].as_str().and_then(Self::portrait_for_name)
                    {
                        object.insert("heroPortrait".into(), Value::String(name));
                    }
                }
                if let Some(id) = object
                    .get("heroGuid")
                    .and_then(Value::as_str)
                    .map(String::from)
                {
                    object.insert("hero_ref".into(), self.entity("hero", &id));
                }
                if let Some(map) = object
                    .get("mapGuid")
                    .and_then(Value::as_str)
                    .and_then(|id| self.maps.get(id))
                {
                    object.insert("mapName".into(), map["name"].clone());
                }
                if let Some(id) = object
                    .get("mapGuid")
                    .and_then(Value::as_str)
                    .map(String::from)
                {
                    object.insert("map_ref".into(), self.entity("map", &id));
                }
                for v in object.values_mut() {
                    self.enrich(v);
                }
            }
            Value::Array(array) => {
                for v in array {
                    self.enrich(v);
                }
            }
            _ => {}
        }
    }
    /// Legacy JSON reference kept for UI enrichment; built from the typed reference.
    pub fn entity(&self, kind: &str, guid: &str) -> Value {
        let kind = if kind == "hero" {
            EntityKind::Hero
        } else {
            EntityKind::Map
        };
        let r = self.entity_ref(kind, guid);
        json!({"id":r.stable_id(),"kind":kind.as_str(),"dashen_guid":r.guid,"official_id":r.official_id,"name_zh":r.name,"mapping_status":if r.name.is_some(){"resolved"}else{"unresolved"}})
    }
    pub fn entity_ref(&self, kind: EntityKind, guid: &str) -> EntityRef {
        EntityRef::new(kind, guid, self.name(kind, guid))
    }
    pub fn name(&self, kind: EntityKind, guid: &str) -> Option<String> {
        let named = |v: Option<&Value>| {
            v.and_then(|v| v["name"].as_str())
                .filter(|s| !s.is_empty())
                .map(String::from)
        };
        match kind {
            EntityKind::Hero => named(self.heroes.get(guid)),
            EntityKind::Map => named(self.maps.get(guid)),
            EntityKind::Stat => self
                .index()
                .stats
                .get(&official_id(guid)?)
                .map(|s| s.0.clone()),
            EntityKind::Perk => self.index().perks.get(&official_id(guid)?).cloned(),
            EntityKind::StadiumUpgrade => self.index().upgrades.get(&official_id(guid)?).cloned(),
        }
    }
    /// Stadium powers and items by `0x…` id: name, picture, description (with the game's
    /// `[ability]` and `{value}` markup), category (异能 / 武器 / 技能 / 生存) and rarity.
    pub fn stadium_upgrades(&self) -> Value {
        let mut out = serde_json::Map::new();
        for upgrade in self
            .mod_traits
            .as_object()
            .into_iter()
            .flat_map(|o| o.values())
            .filter_map(Value::as_array)
            .flatten()
        {
            let Some(id) = upgrade["id"]
                .as_str()
                .map(|s| s.to_ascii_uppercase().replacen("0X", "0x", 1))
            else {
                continue;
            };
            out.entry(id).or_insert_with(|| {
                json!({
                    "name": upgrade["name"].as_str().and_then(clean_name),
                    "icon": upgrade["icon"].as_str().filter(|u| u.starts_with("https://")),
                    "desc": upgrade["desc"].as_str().and_then(clean_name),
                    "category": upgrade["category"],
                    "level": upgrade["level"].as_str().filter(|s| !s.is_empty()),
                })
            });
        }
        Value::Object(out)
    }
    /// True for `特色数据` (hero-specific) stats, false for `通用数据`.
    pub fn stat_is_hero_specific(&self, guid: &str) -> Option<bool> {
        self.index().stats.get(&official_id(guid)?).map(|s| s.1)
    }
    pub fn hero_role(&self, guid: &str) -> Role {
        self.heroes
            .get(guid)
            .and_then(|h| h["role"].as_str())
            .map_or(Role::Unknown, Role::parse)
    }
    fn index(&self) -> &Index {
        self.index.get_or_init(|| {
            let hex = |v: &Value| {
                v.as_str()
                    .map(|s| s.to_ascii_uppercase().replacen("0X", "0x", 1))
                    .or_else(|| v.as_str().and_then(official_id))
            };
            let text = |v: &Value| {
                v.as_str()
                    .map(|s| s.split("<br").next().unwrap_or(s).trim().to_owned())
                    .filter(|s| !s.is_empty())
            };
            let mut index = Index::default();
            for stat in &self.statistics {
                if let (Some(id), Some(name)) = (
                    stat["valueGuid"].as_str().and_then(official_id),
                    text(&stat["valueText"]),
                ) {
                    let specific = stat["valueType"].as_str() == Some("特色数据");
                    index.stats.entry(id).or_insert((name, specific));
                }
            }
            for perk in self.perk_list.iter().chain(
                self.perks
                    .as_object()
                    .into_iter()
                    .flat_map(|o| o.values())
                    .filter_map(Value::as_array)
                    .flatten(),
            ) {
                let id = perk["guid"]
                    .as_str()
                    .and_then(official_id)
                    .or_else(|| hex(&perk["id"]).filter(|s| s.starts_with("0x")));
                if let (Some(id), Some(name)) = (id, text(&perk["name"])) {
                    index.perks.entry(id).or_insert(name);
                }
            }
            for upgrade in self
                .mod_traits
                .as_object()
                .into_iter()
                .flat_map(|o| o.values())
                .filter_map(Value::as_array)
                .flatten()
            {
                if let (Some(id), Some(name)) = (hex(&upgrade["id"]), text(&upgrade["name"])) {
                    index.upgrades.entry(id).or_insert(name);
                }
            }
            index
        })
    }
}

/// A provider string with stray invisible characters removed (`全明星` arrives as
/// `全明星\u{200C}`), trimmed; `None` when nothing is left.
fn clean_name(s: &str) -> Option<String> {
    let cleaned: String = s
        .chars()
        .filter(|c| !matches!(c, '\u{200B}'..='\u{200F}' | '\u{2060}' | '\u{FEFF}'))
        .collect();
    let cleaned = cleaned.trim();
    (!cleaned.is_empty()).then(|| cleaned.to_owned())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn invisible_characters_are_dropped_from_names() {
        assert_eq!(clean_name("全明星\u{200C}").as_deref(), Some("全明星"));
        assert_eq!(clean_name(" 英杰 ").as_deref(), Some("英杰"));
        assert_eq!(clean_name("\u{200B}"), None);
    }

    #[test]
    fn the_bundled_catalog_names_both_ladders() {
        let c = Catalog::bundled();
        let names = &c.icons["rank_names"];
        assert_eq!(names["Champion"], "英杰");
        assert_eq!(names["Emerald"], "翡翠");
        let stadium = &c.icons["rank_names_stadium"];
        assert_eq!(stadium["Bronze"], "菜鸟");
        assert_eq!(stadium["Master"], "全明星");
        assert_eq!(stadium["Grandmaster"], "传奇");
        assert!(stadium.get("Emerald").is_none());
    }

    #[test]
    fn stadium_upgrades_carry_picture_and_description() {
        let all = Catalog::bundled().stadium_upgrades();
        let all = all.as_object().unwrap();
        assert!(all.len() > 900);
        let with_icon = all.values().filter(|u| u["icon"].is_string()).count();
        assert_eq!(with_icon, all.len());
        let one = &all["0x0CC800000000099B"];
        assert_eq!(one["name"], "邪恶飞翼");
        assert_eq!(one["category"], "生存");
        assert!(one["desc"].as_str().unwrap().contains("幽灵形态"));
    }
}
