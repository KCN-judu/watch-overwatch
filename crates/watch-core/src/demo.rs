//! A made-up player to look around with before any account is set up: searching for
//! [`DEMO_NAME`] answers with [`DEMO_TOKEN`], and every request carrying that token is
//! answered here, in the provider's own format, instead of going upstream. So the whole
//! app (lists, details, careers, trends, every analysis) works on it unchanged.
//!
//! Everything is generated from a fixed seed and the bundled catalog: the same matches
//! every time (moved along with the clock so "today" has some), with no real player in
//! them. Names are invented; ids start with `demo-`.
use crate::Catalog;
use crate::dashen::Endpoint;
use serde_json::{Value, json};
use std::sync::OnceLock;

/// What to search for. Shown in the app's first-run page.
pub use crate::DEMO_NAME;
/// Stands in for a `customerToken`; never sent anywhere.
pub const DEMO_TOKEN: &str = "demo-sample-token";
/// The sample player's id. Its number is the generator's version: matches made by an
/// earlier version, already stored on a machine, then stay under the old id and never
/// mix with these.
const SUBJECT: &str = "demo-3";
/// Competitive and quick play matches in the list.
const MATCHES: usize = 160;
const PAGE: usize = 20;
const DAY_MS: i64 = 86_400_000;

/// The provider's answer to a request, when it is for the sample player.
pub fn respond(endpoint: Endpoint, payload: &Value) -> Option<Value> {
    // The other players in the sample matches are looked up too (lobby strength): their
    // names carry `#示例`, their tokens are the sample token with their id after it.
    let other = match endpoint {
        Endpoint::SearchAccount => {
            let name = payload["name"].as_str()?.trim();
            if name.eq_ignore_ascii_case(DEMO_NAME) {
                None
            } else {
                Some(name.split_once(TAG)?.1.to_string())
            }
        }
        _ => {
            let token = payload["token"].as_str()?;
            if token == DEMO_TOKEN {
                None
            } else {
                Some(
                    token
                        .strip_prefix(DEMO_TOKEN)?
                        .strip_prefix(':')?
                        .to_string(),
                )
            }
        }
    };
    let w = world();
    let mode = payload["gameMode"].as_str().unwrap_or("sport");
    if let Some(tag) = other {
        return Some(
            json!({"code": 0, "success": true, "data": other_player(endpoint, &tag, mode)}),
        );
    }
    let data = match endpoint {
        Endpoint::SearchAccount => json!({
            "customerToken": DEMO_TOKEN, "bnetId": SUBJECT, "name": DEMO_NAME, "level": 7,
        }),
        Endpoint::Card => json!({
            "bnetId": SUBJECT, "name": DEMO_NAME, "level": 7, "gameTime": "812.4",
            "title": "示例数据",
        }),
        Endpoint::MatchList => {
            let page = payload["page"].as_u64().unwrap_or(1).max(1) as usize;
            // Past seasons' lists are not asked for by the app; answer empty.
            if payload.get("season").is_some_and(|s| !s.is_null()) {
                json!([])
            } else {
                let rows: Vec<Value> = w
                    .matches(mode)
                    .iter()
                    .skip((page - 1) * PAGE)
                    .take(PAGE)
                    .map(|m| m.row(w))
                    .collect();
                json!(rows)
            }
        }
        Endpoint::MatchInfo => {
            let id = payload["matchId"].as_str().unwrap_or_default();
            let m = w.all().into_iter().find(|m| m.id == id)?;
            m.info(w)
        }
        Endpoint::CareerCount => w.career(mode, payload["season"].as_u64()),
        Endpoint::PlayerHeroBoard => json!({
            "bnetId": SUBJECT, "sportPresetHeroBillboardList": [], "sportOpenHeroBillboardList": [],
        }),
        // Stadium and the boards: nothing for the sample player.
        Endpoint::FightMatchList | Endpoint::HeroBoard | Endpoint::ProvinceRank => json!([]),
        Endpoint::FightCount | Endpoint::FightRoleCard | Endpoint::FightMatchInfo => json!({}),
    };
    Some(json!({"code": 0, "success": true, "data": data}))
}

/// Marks the invented players' names: `晨星#示例1101`.
const TAG: &str = "#示例";

/// Another player of the sample matches, answered from their tag alone: a rank per role
/// near the sample player's, the same every time.
fn other_player(endpoint: Endpoint, tag: &str, mode: &str) -> Value {
    let id = format!("demo-p{tag}");
    match endpoint {
        Endpoint::SearchAccount => json!({
            "customerToken": format!("{DEMO_TOKEN}:{tag}"), "bnetId": id,
            "name": format!("示例{TAG}{tag}"),
        }),
        Endpoint::CareerCount if mode != "leisure" => {
            let mut r = Rng(tag
                .bytes()
                .fold(7u64, |h, b| h.wrapping_mul(31).wrapping_add(b as u64)));
            let roles: Vec<Value> = ROLES
                .iter()
                .map(|role| {
                    let sr = 2100 + (r.next() % 700) as i64;
                    json!({"roleType": role, "matchSum": 20 + r.next() % 80, "winRate": "50.00",
                           "lastRankInfo": rank_info(sr, 0), "maxRankInfo": rank_info(sr + 100, 0)})
                })
                .collect();
            json!({"bnetId": id, "guideCountData": roles})
        }
        Endpoint::MatchList | Endpoint::FightMatchList => json!([]),
        _ => json!({"bnetId": id}),
    }
}

/// A small deterministic generator (SplitMix64).
struct Rng(u64);
impl Rng {
    fn next(&mut self) -> u64 {
        self.0 = self.0.wrapping_add(0x9E37_79B9_7F4A_7C15);
        let mut z = self.0;
        z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
        z ^ (z >> 31)
    }
    fn f(&mut self) -> f64 {
        (self.next() >> 11) as f64 / (1u64 << 53) as f64
    }
    fn pick<'a, T>(&mut self, v: &'a [T]) -> &'a T {
        &v[(self.next() % v.len() as u64) as usize]
    }
    /// Around `mean`, spread `sd` (roughly normal).
    fn around(&mut self, mean: f64, sd: f64) -> f64 {
        let u = (0..4).map(|_| self.f()).sum::<f64>() - 2.0;
        (mean + u * sd * 1.7).max(0.0)
    }
}

const ROLES: [&str; 3] = ["tank", "dps", "healer"];
const NAMES: [&str; 24] = [
    "晨星", "青柠", "北辰", "远山", "白桦", "流萤", "石榴", "海盐", "松风", "落雪", "长夜", "鲸歌",
    "竹影", "橘子", "云杉", "雾灯", "灰隼", "夏至", "星野", "砂糖", "南风", "铁壁", "银杏", "寒露",
];

struct Match {
    id: String,
    competitive: bool,
    at_ms: i64,
    role: usize,
    hero: String,
    map: String,
    win: bool,
    sr: i64,
    /// Teammates queued with the subject (indexes into the friend list).
    party: Vec<usize>,
    /// Enemy team's rating edge over the subject's team.
    edge: i64,
    seed: u64,
    kills: f64,
    deaths: f64,
    assists: f64,
    damage: f64,
    healing: f64,
    mitigation: f64,
}

struct World {
    /// Hero guids per role, the subject's own first.
    heroes: [Vec<String>; 3],
    maps: Vec<String>,
    /// Hero → (stat guid, name) the game defines.
    stats: std::collections::HashMap<String, Vec<(String, String)>>,
    sport: Vec<Match>,
    leisure: Vec<Match>,
    season: u32,
}

fn world() -> &'static World {
    static W: OnceLock<(i64, World)> = OnceLock::new();
    &W.get_or_init(|| {
        let today = crate::now_ms() as i64 / DAY_MS;
        (today, build(today))
    })
    .1
}

fn tier_of(sr: i64) -> (&'static str, i64) {
    const T: [(&str, i64); 9] = [
        ("Bronze", 500),
        ("Silver", 1000),
        ("Gold", 1500),
        ("Platinum", 2000),
        ("Emerald", 2500),
        ("Diamond", 3000),
        ("Master", 3500),
        ("Grandmaster", 4000),
        ("Champion", 4500),
    ];
    let t = T.iter().rev().find(|t| sr >= t.1).unwrap_or(&T[0]);
    (t.0, (5 - (sr - t.1) / 100).clamp(1, 5))
}

fn rank_info(sr: i64, at_ms: i64) -> Value {
    let (tier, div) = tier_of(sr);
    json!({"rankName": tier, "rankSubTier": div, "ts": at_ms})
}

fn build(today: i64) -> World {
    let cat = Catalog::bundled();
    let mut by_role: [Vec<String>; 3] = Default::default();
    let mut guids: Vec<&String> = cat.heroes.keys().collect();
    guids.sort();
    for g in guids {
        let role = cat.heroes[g]["role"].as_str().unwrap_or_default();
        if let Some(i) = ROLES.iter().position(|r| *r == role) {
            by_role[i].push(g.clone());
        }
    }
    let wanted = ["攻击/护送", "运载目标", "占领要点", "机动推进", "闪点作战"];
    // A pool of ten real maps (with a picture, one per name), so that a few dozen matches
    // per map make the map findings visible, as a regular player's would.
    let mut pool: Vec<(&String, &str)> = cat
        .maps
        .iter()
        .filter(|(_, m)| m["mode"].as_str().is_some_and(|t| wanted.contains(&t)))
        .filter(|(_, m)| {
            m["icon"]
                .as_str()
                .is_some_and(|i| i.starts_with("https://"))
        })
        .filter_map(|(g, m)| Some((g, m["name"].as_str()?)))
        .collect();
    pool.sort();
    let mut names = std::collections::HashSet::new();
    let maps: Vec<String> = pool
        .into_iter()
        .filter(|(_, n)| !n.contains(" - ") && names.insert(*n))
        .map(|(g, _)| g.clone())
        .take(10)
        .collect();
    let mut stats: std::collections::HashMap<String, Vec<(String, String)>> = Default::default();
    for s in &cat.statistics {
        if let (Some(h), Some(g), Some(n)) = (
            s["heroGuid"].as_str(),
            s["valueGuid"].as_str(),
            s["valueText"].as_str(),
        ) {
            stats
                .entry(h.into())
                .or_default()
                .push((g.into(), n.into()));
        }
    }
    let mut w = World {
        heroes: by_role,
        maps,
        stats,
        sport: Vec::new(),
        leisure: Vec::new(),
        season: cat.current_season.get(),
    };
    w.sport = w.generate(true, today, 0x5EED_0001);
    w.leisure = w.generate(false, today, 0x5EED_0002);
    w
}

impl World {
    fn matches(&self, mode: &str) -> &[Match] {
        if mode == "leisure" {
            &self.leisure
        } else {
            &self.sport
        }
    }
    fn all(&self) -> Vec<&Match> {
        self.sport.iter().chain(&self.leisure).collect()
    }

    /// Newest first, in sittings of a few matches on most evenings.
    fn generate(&self, competitive: bool, today: i64, seed: u64) -> Vec<Match> {
        let mut r = Rng(seed);
        let total = if competitive { MATCHES } else { MATCHES / 2 };
        let mut out = Vec::new();
        let mut sr = [2450i64, 2280, 2610];
        let now = crate::now_ms() as i64;
        let strong_map = self.maps.get(3).cloned().unwrap_or_default();
        let weak_map = self.maps.get(7).cloned().unwrap_or_default();
        // Oldest first while generating, then reversed.
        let mut day = today - 34;
        while out.len() < total && day <= today {
            if r.f() < 0.25 {
                day += 1;
                continue;
            }
            let sitting = 2 + (r.next() % 5) as usize;
            // Evening, UTC+8: 19:00 to 22:00 local.
            let mut at = day * DAY_MS + (11 + (r.next() % 3) as i64) * 3_600_000;
            for k in 0..sitting {
                // Nothing later than now: today's evening may not have come yet.
                if out.len() >= total || at > now {
                    break;
                }
                let role = match r.next() % 10 {
                    0..=4 => 2,
                    5..=7 => 1,
                    _ => 0,
                };
                let pool = &self.heroes[role];
                let hero = if r.f() < 0.7 {
                    pool[(r.next() % pool.len().min(2) as u64) as usize].clone()
                } else {
                    r.pick(pool).clone()
                };
                let map = r.pick(&self.maps).clone();
                let party: Vec<usize> = match r.next() % 10 {
                    0..=3 => vec![0],
                    4 => vec![0, 1],
                    _ => Vec::new(),
                };
                // A rough patch two to three weeks ago, against stronger teams.
                let rough = (today - day) > 14 && (today - day) < 19;
                let edge = if rough {
                    150 + (r.next() % 150) as i64
                } else {
                    (r.next() % 160) as i64 - 80
                };
                let mut p = 0.52 + if map == strong_map { 0.3 } else { 0.0 }
                    - if map == weak_map { 0.28 } else { 0.0 }
                    + if party.is_empty() { 0.0 } else { 0.06 }
                    - if k >= 3 { 0.25 } else { 0.0 }
                    - edge as f64 / 1000.0;
                p = p.clamp(0.1, 0.9);
                let win = r.f() < p;
                if competitive {
                    sr[role] += if win { 24 } else { -24 } + (r.next() % 7) as i64 - 3;
                    sr[role] = sr[role].clamp(1600, 3400);
                }
                let (dmg, heal, mit) = match role {
                    0 => (7500.0, 0.0, 9000.0),
                    1 => (9800.0, 0.0, 0.0),
                    _ => (3800.0, 9200.0, 0.0),
                };
                let lift = if win { 1.12 } else { 0.9 };
                out.push(Match {
                    id: format!(
                        "demo-3-{}-{:04}",
                        if competitive { "sport" } else { "leisure" },
                        out.len()
                    ),
                    competitive,
                    at_ms: at,
                    role,
                    hero,
                    map,
                    win,
                    sr: sr[role],
                    party,
                    edge,
                    seed: r.next(),
                    kills: r
                        .around(if role == 2 { 9.0 } else { 17.0 } * lift, 3.0)
                        .round(),
                    deaths: r.around(if win { 5.0 } else { 7.5 }, 2.0).round(),
                    assists: r
                        .around(if role == 2 { 13.0 } else { 6.0 } * lift, 2.5)
                        .round(),
                    damage: r.around(dmg * lift, 1500.0).round(),
                    healing: r
                        .around(heal * lift, if heal > 0.0 { 1500.0 } else { 0.0 })
                        .round(),
                    mitigation: r
                        .around(mit * lift, if mit > 0.0 { 2000.0 } else { 0.0 })
                        .round(),
                });
                at += (14 + (r.next() % 9) as i64) * 60_000;
            }
            day += 1;
        }
        out.reverse();
        // Ids newest first, so the list's order and the ids agree.
        let n = out.len();
        for (i, m) in out.iter_mut().enumerate() {
            m.id = format!(
                "demo-3-{}-{:04}",
                if competitive { "sport" } else { "leisure" },
                n - 1 - i
            );
        }
        out
    }

    fn career(&self, mode: &str, season: Option<u64>) -> Value {
        let current = self.season as u64;
        // Seasons after the current one have not started; the three before it have.
        let past = match season {
            None => 0,
            Some(s) if s > current => return json!({"bnetId": SUBJECT}),
            Some(s) => current - s,
        };
        if past > 3 {
            return json!({"bnetId": SUBJECT});
        }
        let competitive = mode != "leisure";
        let ms = self.matches(mode);
        let mut roles = Vec::new();
        let mut heroes: std::collections::BTreeMap<&str, (usize, usize, f64)> = Default::default();
        let mut total = (0usize, 0usize);
        for (ri, role) in ROLES.iter().enumerate() {
            let of: Vec<&Match> = ms.iter().filter(|m| m.role == ri).collect();
            // Past seasons: as many matches again, a little lower.
            let scale = if past == 0 {
                1.0
            } else {
                0.8 + 0.1 * past as f64
            };
            let n = (of.len() as f64 * scale) as usize;
            let wins = (of.iter().filter(|m| m.win).count() as f64
                * scale
                * if past == 0 { 1.0 } else { 0.95 }) as usize;
            total.0 += n;
            total.1 += wins;
            let sr = of.first().map_or(2300, |m| m.sr) - past as i64 * 120;
            let peak = of.iter().map(|m| m.sr).max().unwrap_or(sr) - past as i64 * 100;
            let mut role_json = json!({
                "roleType": role, "matchSum": n,
                "winRate": format!("{:.2}", if n == 0 { 0.0 } else { 100.0 * wins as f64 / n as f64 }),
                "kda": "3.40",
            });
            if competitive && n > 0 {
                role_json["lastRankInfo"] = rank_info(sr, 0);
                role_json["maxRankInfo"] = rank_info(peak, 0);
            }
            roles.push(role_json);
            if past == 0 {
                for m in &of {
                    let e = heroes.entry(m.hero.as_str()).or_default();
                    e.0 += 1;
                    e.1 += usize::from(m.win);
                    e.2 += 600.0 + (m.seed % 500) as f64;
                }
            }
        }
        let hero_list: Vec<Value> = heroes
            .iter()
            .map(|(h, (n, w, secs))| {
                let names = self.stats.get(*h).cloned().unwrap_or_default();
                let per10: Vec<Value> = names
                    .iter()
                    .take(8)
                    .enumerate()
                    .map(|(i, (g, _))| json!({"valueGuid": g, "value": 2.0 + i as f64 * 1.7}))
                    .collect();
                json!({
                    "heroGuid": h, "matchSum": n, "winSum": w,
                    "winRate": 100.0 * *w as f64 / *n as f64, "kda": "3.2",
                    "gameTime": secs, "heroLevel": 10 + n % 40,
                    "statPerTenMinCount": per10,
                })
            })
            .collect();
        let summary = json!({
            "matchSum": total.0, "matchWinSum": total.1, "matchLossSum": total.0 - total.1,
            "winRate": format!("{:.2}", if total.0 == 0 { 0.0 } else { 100.0 * total.1 as f64 / total.0 as f64 }),
            "aveHeroDamage": 6800, "aveCure": 5200, "aveResistDamage": 3100,
            "aveKill": 14, "aveAssist": 10, "aveDeath": 6, "aveFinalHit": 5,
        });
        let mut out = json!({
            "bnetId": SUBJECT,
            "guideCountData": roles,
            "presetsSummaryData": summary,
            "frequentHeroIds": self.heroes.iter().filter_map(|r| r.first()).collect::<Vec<_>>(),
            "gameAction": {"comment": "这是示例数据", "getHonorsCnt": 21, "sendHonorsCnt": 17, "reportedCnt": 0},
        });
        if past == 0 {
            out["presetsHeroUseSummaryList"] = json!(hero_list);
            out["matchList"] = json!(ms.iter().take(10).map(|m| m.row(self)).collect::<Vec<_>>());
        }
        out
    }
}

impl Match {
    fn game_mode(&self) -> &'static str {
        if self.competitive {
            "SportPreset"
        } else {
            "LeisurePreset"
        }
    }

    fn row(&self, _w: &World) -> Value {
        let mut row = json!({
            "matchId": self.id, "mapGuid": self.map, "heroGuid": self.hero,
            "roleType": ROLES[self.role], "matchRet": if self.win { 1 } else { -1 },
            "instanceType": if self.competitive { "IT_RANKED" } else { "IT_UNRANKED" },
            "teamScore": if self.win { 3 } else { 1 }, "opponentScore": if self.win { 1 } else { 3 },
            "kill": self.kills, "death": self.deaths, "assist": self.assists,
            "heroDamage": self.damage, "cure": self.healing, "resistDamage": self.mitigation,
            "beginTs": self.at_ms, "gameMode": self.game_mode(),
            // Top of the lobby on a strong night.
            "killMax": self.kills >= 22.0, "heroDamageMax": self.damage >= 11_500.0,
            "cureMax": self.healing >= 10_500.0, "resistDamageMax": self.mitigation >= 10_500.0,
        });
        if self.competitive {
            row["rankInfo"] = rank_info(self.sr, self.at_ms);
        }
        row
    }

    /// The match as `queryMatchInfo` gives it: both teams of five, the subject first.
    fn info(&self, w: &World) -> Value {
        let mut r = Rng(self.seed);
        let duration = 600 + (r.next() % 540) as i64;
        let slots = [0usize, 1, 1, 2, 2];
        let friends = [
            ("demo-p1101", "晨星#示例1101"),
            ("demo-p2202", "青柠#示例2202"),
        ];
        let my_slot = slots.iter().position(|s| *s == self.role).unwrap_or(0);
        // A hero plays once per team: `taken` holds the team's heroes so far.
        let player = |id: String,
                      name: String,
                      role: usize,
                      sr: i64,
                      me: bool,
                      r: &mut Rng,
                      taken: &mut Vec<String>| {
            let hero = if me {
                self.hero.clone()
            } else {
                let mut h = r.pick(&w.heroes[role]).clone();
                for _ in 0..32 {
                    if !taken.contains(&h) {
                        break;
                    }
                    h = r.pick(&w.heroes[role]).clone();
                }
                h
            };
            taken.push(hero.clone());
            let (k, d, a, dmg, heal, mit) = if me {
                (
                    self.kills,
                    self.deaths,
                    self.assists,
                    self.damage,
                    self.healing,
                    self.mitigation,
                )
            } else {
                let base = match role {
                    0 => (16.0, 6.0, 7.0, 7200.0, 0.0, 8800.0),
                    1 => (18.0, 6.5, 5.0, 9500.0, 0.0, 0.0),
                    _ => (8.0, 5.5, 13.0, 3500.0, 8800.0, 0.0),
                };
                (
                    r.around(base.0, 3.0).round(),
                    r.around(base.1, 2.0).round(),
                    r.around(base.2, 2.5).round(),
                    r.around(base.3, 1500.0).round(),
                    r.around(base.4, if base.4 > 0.0 { 1500.0 } else { 0.0 })
                        .round(),
                    r.around(base.5, if base.5 > 0.0 { 2000.0 } else { 0.0 })
                        .round(),
                )
            };
            let mut p = json!({
                "name": name, "bnetId": id, "heroGuid": hero, "roleType": ROLES[role],
                "kill": k, "death": d, "assist": a, "heroDamage": dmg, "cure": heal,
                "resistDamage": mit, "finalHit": (k * 0.4).round(),
            });
            if self.competitive {
                p["rankInfo"] = rank_info(sr, self.at_ms);
            }
            p
        };
        let mut allies = Vec::new();
        let mut ally_heroes = vec![self.hero.clone()];
        let mut used = 0;
        for (i, role) in slots.iter().enumerate() {
            let (id, name, me) = if i == my_slot {
                (SUBJECT.to_string(), DEMO_NAME.to_string(), true)
            } else if used < self.party.len() {
                let f = friends[self.party[used]];
                used += 1;
                (f.0.to_string(), f.1.to_string(), false)
            } else {
                let n = r.pick(&NAMES);
                let tag = 3000 + r.next() % 6000;
                (format!("demo-p{tag}"), format!("{n}{TAG}{tag}"), false)
            };
            let sr = self.sr + (r.next() % 200) as i64 - 100;
            allies.push(player(id, name, *role, sr, me, &mut r, &mut ally_heroes));
        }
        // Who queued with whom.
        let group: Vec<String> = allies
            .iter()
            .filter_map(|p| p["bnetId"].as_str())
            .filter(|id| *id == SUBJECT || friends.iter().any(|f| f.0 == *id))
            .map(String::from)
            .collect();
        if group.len() > 1 {
            for p in allies.iter_mut() {
                let id = p["bnetId"].as_str().unwrap_or_default().to_string();
                if group.contains(&id) {
                    p["friendBnetIds"] =
                        json!(group.iter().filter(|g| **g != id).collect::<Vec<_>>());
                }
            }
        }
        let mut enemy_heroes = Vec::new();
        let enemies: Vec<Value> = slots
            .iter()
            .map(|role| {
                let n = r.pick(&NAMES);
                let tag = 3000 + r.next() % 6000;
                let sr = self.sr + self.edge + (r.next() % 200) as i64 - 100;
                player(
                    format!("demo-p{tag}"),
                    format!("{n}{TAG}{tag}"),
                    *role,
                    sr,
                    false,
                    &mut r,
                    &mut enemy_heroes,
                )
            })
            .collect();
        json!({
            "matchRet": if self.win { 1 } else { -1 },
            "mapGuid": self.map, "gameTimeSec": duration, "startTime": self.at_ms / 1000,
            "teamScore": if self.win { 3 } else { 1 }, "opponentScore": if self.win { 1 } else { 3 },
            "heroList": [{"heroId": self.hero, "userTimeSec": duration, "useTimeRate": "100.00", "statMap": {}}],
            "teammateList": allies, "enemyList": enemies,
            "teamBanHeroGuids": [], "enemyBanHeroGuids": [],
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::dashen::normalize;

    #[test]
    fn the_sample_player_is_found_and_answered_without_the_network() {
        let found = respond(Endpoint::SearchAccount, &json!({"name": DEMO_NAME})).unwrap();
        assert_eq!(found["data"]["customerToken"], DEMO_TOKEN);
        assert!(respond(Endpoint::SearchAccount, &json!({"name": "Someone#1"})).is_none());
        assert!(respond(Endpoint::MatchList, &json!({"token": "real"})).is_none());
        // A teammate of the sample matches is found too, and never goes upstream.
        let mate = respond(Endpoint::SearchAccount, &json!({"name": "晨星#示例1101"})).unwrap();
        let token = mate["data"]["customerToken"].as_str().unwrap().to_string();
        let career = respond(
            Endpoint::CareerCount,
            &json!({"token": token, "gameMode": "sport"}),
        );
        assert_eq!(
            career.unwrap()["data"]["guideCountData"]
                .as_array()
                .unwrap()
                .len(),
            3
        );

        let cat = Catalog::bundled();
        let page = respond(
            Endpoint::MatchList,
            &json!({"token": DEMO_TOKEN, "gameMode": "sport", "page": 1}),
        )
        .unwrap();
        let rows = normalize::match_list(
            normalize::payload(&page),
            crate::ir::Mode::Competitive,
            &cat,
        );
        assert_eq!(rows.len(), PAGE);
        assert!(
            rows.windows(2)
                .all(|w| w[0].started_at_ms >= w[1].started_at_ms)
        );
        assert!(rows[0].rank.as_ref().and_then(|r| r.skill_rating).is_some());

        let info = respond(
            Endpoint::MatchInfo,
            &json!({"token": DEMO_TOKEN, "matchId": rows[0].id}),
        )
        .unwrap();
        let d = normalize::match_detail(
            &rows[0].id,
            normalize::payload(&info),
            crate::ir::Mode::Competitive,
            Some(SUBJECT),
            &cat,
        );
        assert_eq!((d.allies.len(), d.enemies.len()), (5, 5));
        for team in [&d.allies, &d.enemies] {
            let heroes: std::collections::HashSet<_> = team
                .iter()
                .filter_map(|p| p.hero.as_ref())
                .map(|h| &h.guid)
                .collect();
            assert_eq!(heroes.len(), 5, "a hero twice in one team");
        }
        assert!(d.subject().is_some());
        assert_eq!(d.outcome, rows[0].outcome);

        let career = respond(
            Endpoint::CareerCount,
            &json!({"token": DEMO_TOKEN, "gameMode": "sport"}),
        )
        .unwrap();
        let c = normalize::career(
            normalize::payload(&career),
            crate::ir::Mode::Competitive,
            None,
            &cat,
        );
        assert_eq!(c.roles.len(), 3);
        assert!(!c.heroes.is_empty());
    }

    #[test]
    fn the_sample_player_has_something_worth_noticing() {
        let cat = Catalog::bundled();
        let mut rows = Vec::new();
        for page in 1.. {
            let v = respond(
                Endpoint::MatchList,
                &json!({"token": DEMO_TOKEN, "gameMode": "sport", "page": page}),
            )
            .unwrap();
            let got =
                normalize::match_list(normalize::payload(&v), crate::ir::Mode::Competitive, &cat);
            if got.is_empty() {
                break;
            }
            rows.extend(got);
        }
        let clock = crate::analysis::Clock::now(crate::analysis::REPORT_UTC_OFFSET_MINUTES);
        let o = crate::analysis::overview(
            &rows,
            clock,
            crate::analysis::AnalysisOptions::default().session_gap_ms,
            &crate::insights::Context::default(),
        );
        assert!(
            !o.insights.is_empty(),
            "no findings over {} matches",
            rows.len()
        );
        let maps: std::collections::HashSet<&str> = rows
            .iter()
            .filter_map(|m| m.map.as_ref()?.name.as_deref())
            .collect();
        assert!(maps.len() <= 10);
        assert!(
            rows.iter()
                .all(|m| m.started_at_ms <= Some(crate::now_ms() as i64))
        );
    }
}
