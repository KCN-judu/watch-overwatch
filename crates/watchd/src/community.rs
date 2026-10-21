use super::{AppState, fail};
use axum::{
    Json,
    extract::State,
    response::{IntoResponse, Response},
};
use serde::Deserialize;
use serde_json::{Value, json};
use std::{
    collections::HashMap,
    sync::OnceLock,
    time::{Duration, Instant},
};
use tokio::sync::{Mutex, Semaphore};
use watch_core::{Failure, RequestSpec};

type Cache = Mutex<HashMap<String, (Instant, Value)>>;
static CACHE: OnceLock<Cache> = OnceLock::new();
static GATE: Semaphore = Semaphore::const_new(2);
fn err(kind: &'static str, message: &str) -> Failure {
    Failure {
        kind,
        message: message.into(),
        retry_after_ms: None,
    }
}
async fn fetch(url: &str, html: bool) -> Result<Value, Failure> {
    let key = format!("{html}:{url}");
    let cache = CACHE.get_or_init(|| Mutex::new(HashMap::new()));
    if let Some((_, v)) = cache
        .lock()
        .await
        .get(&key)
        .filter(|(at, _)| at.elapsed() < Duration::from_secs(300))
    {
        return Ok(v.clone());
    }
    let permit = GATE
        .try_acquire()
        .map_err(|_| err("busy", "公共数据正在读取，请稍后重试。"))?;
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(20))
        .redirect(reqwest::redirect::Policy::limited(3))
        .user_agent("Mozilla/5.0 WatchOverwatch/0.1")
        .build()
        .map_err(|_| err("network", "无法创建连接。"))?;
    let mut response = client
        .get(url)
        .header("Referer", "https://ow.blizzard.cn/")
        .send()
        .await
        .map_err(|_| err("network", "公共数据源连接失败。请稍后重试。"))?;
    if !response.status().is_success() {
        return Err(err("upstream", "公共数据源拒绝请求或暂不可用。"));
    }
    let mut bytes = Vec::new();
    while let Some(chunk) = response
        .chunk()
        .await
        .map_err(|_| err("network", "读取响应失败。"))?
    {
        if bytes.len() + chunk.len() > 8 * 1024 * 1024 {
            return Err(err("response", "公共响应过大。"));
        }
        bytes.extend_from_slice(&chunk);
    }
    let value = if html {
        let doc = scraper::Html::parse_document(&String::from_utf8_lossy(&bytes));
        let selector = scraper::Selector::parse("h1,h2,h3,h4,p,li").unwrap();
        json!({"sections":doc.select(&selector).map(|e|e.text().collect::<Vec<_>>().join(" ")).filter(|s|!s.trim().is_empty()).take(600).collect::<Vec<_>>()})
    } else {
        serde_json::from_slice(&bytes).map_err(|_| err("response", "公共数据源未返回 JSON。"))?
    };
    drop(permit);
    let mut cache = cache.lock().await;
    if cache.len() >= 50 {
        cache.clear();
    }
    cache.insert(key, (Instant::now(), value.clone()));
    Ok(value)
}
pub(crate) async fn catalog(State(s): State<AppState>) -> Json<Value> {
    Json(
        json!({"heroes":s.catalog.heroes,"maps":s.catalog.maps,"statistics":s.catalog.statistics,"perks":s.catalog.perks,"hero_config":s.catalog.hero_config,"current_season":s.catalog.current_season,"icons":s.catalog.icons,"stadium_upgrades":s.catalog.stadium_upgrades()}),
    )
}
#[derive(Deserialize)]
pub(crate) struct Query {
    kind: String,
    #[serde(default)]
    province: String,
    #[serde(default)]
    hero: String,
    #[serde(default)]
    role: String,
    #[serde(default)]
    mode: String,
    season: Option<u32>,
    #[serde(default)]
    mmr: String,
    #[serde(default)]
    name: String,
    year: Option<u32>,
    month: Option<u32>,
}
pub(crate) async fn query(State(s): State<AppState>, Json(q): Json<Query>) -> Response {
    match tokio::time::timeout(Duration::from_secs(45), run(s, q)).await {
        Ok(Ok(v)) => Json(watch_core::sanitize(v)).into_response(),
        Ok(Err(e)) => fail(e).into_response(),
        Err(_) => fail(err("timeout", "公共查询超时。请缩小范围重试。 ")).into_response(),
    }
}
async fn run(s: AppState, q: Query) -> Result<Value, Failure> {
    match q.kind.as_str() {
        "province" | "hero_board" => {
            if q.province.len() > 64
                || (!q.role.is_empty()
                    && !["tank", "dps", "support", "healer", "all"].contains(&q.role.as_str()))
            {
                return Err(err("validation", "省份或职责无效。"));
            }
            let hero_guid = s
                .catalog
                .heroes
                .iter()
                .find(|(_, h)| {
                    h["official_id"]
                        .as_str()
                        .is_some_and(|id| id.eq_ignore_ascii_case(&q.hero))
                })
                .map(|(guid, _)| guid.clone())
                .unwrap_or_else(|| q.hero.clone());
            if q.kind == "hero_board"
                && !s.catalog.heroes.contains_key(&q.hero)
                && hero_guid == q.hero
            {
                return Err(err("validation", "请从目录选择英雄。"));
            }
            let endpoint = if q.kind == "province" {
                "queryProvinceRank"
            } else {
                "billboard/getHeroBillboard"
            };
            let (_,mut v)=s.client.request(RequestSpec{endpoint:endpoint.into(),payload:json!({"province":q.province,"roleType":q.role,"heroGuid":hero_guid,"gameMode":if q.mode=="leisure"{"leisure"}else{"sport"}})}).await?;
            s.catalog.enrich(&mut v);
            Ok(json!({"source":"netease_dashen","data":v["data"]}))
        }
        "pick_rate" => {
            let season = q.season.unwrap_or(2);
            if season == 0 || season > 100 {
                return Err(err("validation", "无效赛季。"));
            }
            let mode = if q.mode == "leisure" {
                "kuaisu"
            } else {
                "jingji"
            };
            let mmr = if q.mmr.is_empty() { "-127" } else { &q.mmr };
            if ![
                "-127",
                "Bronze",
                "Silver",
                "Gold",
                "Platinum",
                "Emerald",
                "Diamond",
                "Master",
                "Grandmaster",
                "Champion",
            ]
            .contains(&mmr)
            {
                return Err(err("validation", "无效段位。"));
            }
            let url = format!(
                "https://webapi.blizzard.cn/ow-armory-server/hero_leaderboard?game_mode={mode}&season={season}&mmr={mmr}"
            );
            let mut v = fetch(&url, false).await?;
            if v["code"] != 0 {
                return Err(err("business", "官方英雄统计返回业务错误。"));
            }
            if let Some(rows) = v["data"].as_array_mut() {
                for row in rows {
                    if let Some(id) = row["hero_id"].as_str() {
                        let matched = s.catalog.heroes.iter().find(|(_, h)| {
                            h["official_id"]
                                .as_str()
                                .is_some_and(|official| official.eq_ignore_ascii_case(id))
                        });
                        if let Some((guid, _)) = matched {
                            row["hero_ref"] = s.catalog.entity("hero", guid);
                        }
                    }
                }
            }
            Ok(json!({"source":url,"season":season,"mode":mode,"mmr":mmr,"data":v["data"]}))
        }
        "shop" => {
            let sources = [
                (
                    "精选商品",
                    "https://shop.battlenet.com.cn/api/itemshop/pages/blt01ee8af4f4da5e5f?userId=0&locale=zh-CN&mobileFlow=false",
                ),
                (
                    "电竞商品",
                    "https://shop.battlenet.com.cn/api/itemshop/pages/blt2065e08d915d3ff8?userId=0&locale=zh-CN&mobileFlow=false",
                ),
                (
                    "赛季物品",
                    "https://shop.battlenet.com.cn/api/card-collection?id=blt9f0779a1ce3674d7&id=bltf6f3754ef9ac5efe&id=bltff44f3db7e349cb3&id=blt11708b9adcddb5e2&id=blt9463b6e951095627&locale=zh-cn&mobileFlow=false",
                ),
                (
                    "光子水晶",
                    "https://shop.battlenet.com.cn/api/card-collection?id=blt96bb02f90b1c493c&id=blt41c246cabce228fe&locale=zh-cn&mobileFlow=false",
                ),
                (
                    "货币",
                    "https://shop.battlenet.com.cn/api/card-collection?id=blt33b65689468107fd&id=blte794697a49f1ac23&id=blt965ebe71fa46b9fb&locale=zh-cn&mobileFlow=false",
                ),
                (
                    "PVE",
                    "https://shop.battlenet.com.cn/api/card-collection?id=blt6ba8925b6fb5d816&locale=zh-cn&mobileFlow=false",
                ),
            ];
            let index = q.season.unwrap_or(0) as usize;
            let (title, url) = sources
                .get(index)
                .ok_or_else(|| err("validation", "未知商店分类。"))?;
            let v = fetch(url, false).await?;
            let items = v
                .as_array()
                .cloned()
                .or_else(|| v["mtxCollections"][0]["items"].as_array().cloned())
                .ok_or_else(|| err("response", "商店数据结构已变化。"))?;
            Ok(
                json!({"source":url,"title":title,"expires_at_unix_ms":v["expiresAtMs"],"items":items}),
            )
        }
        "patch" => {
            let year = q.year.unwrap_or(2026);
            let month = q.month.unwrap_or(10);
            if !(2016..=2100).contains(&year) || !(1..=12).contains(&month) {
                return Err(err("validation", "无效年月。"));
            }
            let url = if q.mode == "global" {
                format!("https://overwatch.blizzard.com/en-us/news/patch-notes/live/{year}/{month}")
            } else {
                format!("https://ow.blizzard.cn/news/patch-notes/live/{year}/{month}/")
            };
            Ok(json!({"source":url,"data":fetch(&url,true).await?}))
        }
        "blizzard_search" => {
            let name = q.name.trim().split('#').next().unwrap_or("");
            if name.is_empty() || name.len() > 100 {
                return Err(err("validation", "请输入战网名称。"));
            }
            let mut url =
                reqwest::Url::parse("https://overwatch.blizzard.com/en-us/search/account-by-name/")
                    .unwrap();
            url.path_segments_mut().unwrap().push(name).push("");
            Ok(json!({"source":url.as_str(),"data":fetch(url.as_str(),false).await?}))
        }
        "blizzard_profile" => {
            let name = q.name.trim().replace('#', "-");
            if name.is_empty() || name.len() > 150 {
                return Err(err("validation", "请输入玩家 ID。"));
            }
            let mut url =
                reqwest::Url::parse("https://overwatch.blizzard.com/en-us/career/").unwrap();
            url.path_segments_mut().unwrap().push(&name).push("");
            Ok(json!({"source":url.as_str(),"data":fetch(url.as_str(),true).await?}))
        }
        "esports" => {
            let path = watch_core::data_dir().join("integrations.json");
            let config: Value = std::fs::read(path)
                .ok()
                .and_then(|b| serde_json::from_slice(&b).ok())
                .unwrap_or(Value::Null);
            let token=config["pandascore_token"].as_str().filter(|s|!s.is_empty()).ok_or_else(||err("validation","赛事需要 PandaScore token。请在本机 integrations.json 中填写 pandascore_token。"))?;
            // Provider credentials never enter a URL or a user-facing error.
            let client = reqwest::Client::new();
            let _gate = GATE
                .try_acquire()
                .map_err(|_| err("busy", "公共请求繁忙。"))?;
            let v: Value = client
                .get("https://api.pandascore.co/ow/matches")
                .bearer_auth(token)
                .timeout(Duration::from_secs(20))
                .send()
                .await
                .map_err(|_| err("network", "赛事连接失败。"))?
                .error_for_status()
                .map_err(|_| err("upstream", "赛事认证或服务失败。"))?
                .json()
                .await
                .map_err(|_| err("response", "赛事数据无效。"))?;
            Ok(json!({"source":"https://api.pandascore.co/ow/matches","data":v}))
        }
        _ => Err(err("validation", "未知公共功能。")),
    }
}
