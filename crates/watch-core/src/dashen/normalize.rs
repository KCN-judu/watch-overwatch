//! Raw Dashen JSON → IR. This is the only module that knows upstream key names,
//! their aliases (`heroId`/`heroGuid`, `rank_name`/`rankName`, …), string-encoded
//! numbers and per-mode shape differences. Unknown or malformed values become
//! `None` rather than failing the whole response.
use super::Mode;
use crate::Catalog;
use crate::ir::*;
use serde_json::Value;

/// Tolerant read-only view over a JSON value.
#[derive(Clone, Copy)]
struct V<'a>(&'a Value);

impl<'a> V<'a> {
    fn get(self, keys: &[&str]) -> Option<&'a Value> {
        keys.iter()
            .filter_map(|k| self.0.get(k))
            .find(|v| !v.is_null())
    }
    fn f64(self, keys: &[&str]) -> Option<f64> {
        self.get(keys).and_then(number)
    }
    fn i64(self, keys: &[&str]) -> Option<i64> {
        self.f64(keys)
            .filter(|n| n.fract() == 0.0 && n.abs() < 9.0e15)
            .map(|n| n as i64)
    }
    fn str(self, keys: &[&str]) -> Option<String> {
        self.get(keys).and_then(|v| match v {
            Value::String(s) if !s.trim().is_empty() => Some(s.trim().to_owned()),
            Value::Number(n) => Some(n.to_string()),
            _ => None,
        })
    }
    fn bool(self, key: &str) -> Option<bool> {
        self.0.get(key).and_then(|v| match v {
            Value::Bool(b) => Some(*b),
            Value::Number(n) => n.as_i64().map(|n| n != 0),
            _ => None,
        })
    }
    /// Arrays, also accepting a JSON-encoded array string (seen for perk lists).
    fn list(self, keys: &[&str]) -> Vec<Value> {
        match self.get(keys) {
            Some(Value::Array(a)) => a.clone(),
            Some(Value::String(s)) => serde_json::from_str::<Vec<Value>>(s).unwrap_or_default(),
            _ => Vec::new(),
        }
    }
    fn obj(self, keys: &[&str]) -> Option<V<'a>> {
        self.get(keys)
            .filter(|v| v.as_object().is_some_and(|o| !o.is_empty()))
            .map(V)
    }
}

fn number(v: &Value) -> Option<f64> {
    match v {
        Value::Number(n) => n.as_f64(),
        Value::String(s) => s.trim().parse::<f64>().ok(),
        _ => None,
    }
    .filter(|n| n.is_finite())
}

fn strings(values: &[Value]) -> Vec<String> {
    values
        .iter()
        .filter_map(|v| match v {
            Value::String(s) if !s.is_empty() && s != "0" => Some(s.clone()),
            Value::Number(n) if n.as_u64() != Some(0) => Some(n.to_string()),
            _ => None,
        })
        .collect()
}

fn entity(cat: &Catalog, kind: EntityKind, guid: Option<String>) -> Option<EntityRef> {
    guid.filter(|g| g != "0").map(|g| cat.entity_ref(kind, &g))
}

/// The response body's `data` field, or the value itself if it is not an envelope.
pub fn payload(response: &Value) -> &Value {
    match response.get("data") {
        Some(data) if response.get("code").is_some() || response.get("success").is_some() => data,
        _ => response,
    }
}

pub const TIER_BASES: [(&str, i64); 9] = [
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
/// Compact normal-mode `rankScore` is `raw_id*100 + (100-division)`; raw ids are
/// not in tier order (Emerald was added later as 8).
const COMPACT_TIERS: [&str; 9] = [
    "Bronze",
    "Silver",
    "Gold",
    "Platinum",
    "Diamond",
    "Master",
    "Grandmaster",
    "Champion",
    "Emerald",
];

pub fn rank(raw: Option<&Value>, mode: Mode) -> Option<Rank> {
    let r = V(raw.filter(|v| v.as_object().is_some_and(|o| !o.is_empty()))?);
    let score = r.i64(&["rankScore", "rank_score", "score"]);
    // Unranked players carry a placeholder `{rankName:"None", rankScore:0}`.
    let mut tier = r
        .str(&["rankName", "rank_name"])
        .filter(|t| !t.eq_ignore_ascii_case("none") && !t.eq_ignore_ascii_case("null"));
    let mut division = r
        .i64(&["rankSubTier", "rank_sub_tier"])
        .filter(|d| (1..=5).contains(d))
        .map(|d| d as u8);
    if !mode.continuous_rank_score()
        && let Some(s) = score.filter(|s| *s > 0)
        && (tier.is_none() || division.is_none())
        && (95..=99).contains(&(s % 100))
    {
        tier = tier.or_else(|| COMPACT_TIERS.get((s / 100) as usize).map(|t| t.to_string()));
        division = division.or(Some((100 - s % 100) as u8));
    }
    let skill_rating = if mode.continuous_rank_score() {
        score.filter(|s| *s > 0)
    } else {
        tier.as_deref()
            .and_then(|t| {
                TIER_BASES
                    .iter()
                    .find(|(name, _)| name.eq_ignore_ascii_case(t))
            })
            .map(|(_, base)| base + (5 - i64::from(division.unwrap_or(5))) * 100)
    };
    if tier.is_none() && score.is_none_or(|s| s <= 0) {
        return None;
    }
    Some(Rank {
        tier,
        division,
        score,
        skill_rating,
        at_ms: r.i64(&["ts"]),
    })
}

/// Provider row `gameMode` (`SportPreset`, `QuickOpen`, `LeisureV6`, `SportFight`…).
fn kind(row: V, requested: Mode) -> MatchKind {
    let provider_mode = row.str(&["gameMode"]);
    let raw = provider_mode.as_deref().unwrap_or("");
    let mode = if raw.ends_with("Fight") {
        Mode::Stadium
    } else if raw.starts_with("Sport") {
        Mode::Competitive
    } else if raw.starts_with("Quick") || raw.starts_with("Leisure") {
        Mode::Quick
    } else {
        requested
    };
    let queue = if raw.ends_with("Preset") {
        Queue::RoleQueue
    } else if raw.ends_with("Open") || raw == "QuickPlay" {
        Queue::OpenQueue
    } else if raw.ends_with("V6") {
        Queue::SixVsSix
    } else {
        Queue::Unknown
    };
    let instance_type = row.str(&["instanceType"]);
    MatchKind {
        mode,
        queue,
        ranked: instance_type.as_deref().and_then(|t| match t {
            "IT_RANKED" => Some(true),
            "IT_UNRANKED" | "IT_RULESET" => Some(false),
            _ => None,
        }),
        provider_mode,
        instance_type,
    }
}

fn score(v: V) -> Score {
    Score {
        team: v.i64(&["teamScore"]),
        opponent: v.i64(&["opponentScore"]),
    }
}

/// `matchRet`: 1 win, 0 draw, -1 loss; 2 has historically been treated as a loss.
/// Stadium details omit it, so the final score decides.
fn outcome(v: V, score: Score) -> (Outcome, OutcomeSource) {
    match v.i64(&["matchRet"]) {
        Some(1) => (Outcome::Win, OutcomeSource::Provider),
        Some(0) => (Outcome::Draw, OutcomeSource::Provider),
        Some(-1) | Some(2) => (Outcome::Loss, OutcomeSource::Provider),
        Some(_) => (Outcome::Unknown, OutcomeSource::Unknown),
        None => match (score.team, score.opponent) {
            (Some(a), Some(b)) => (
                match a.cmp(&b) {
                    std::cmp::Ordering::Greater => Outcome::Win,
                    std::cmp::Ordering::Less => Outcome::Loss,
                    std::cmp::Ordering::Equal => Outcome::Draw,
                },
                OutcomeSource::Score,
            ),
            _ => (Outcome::Unknown, OutcomeSource::Unknown),
        },
    }
}

fn stat_line(v: V) -> StatLine {
    StatLine {
        kills: v.f64(&["kill"]),
        assists: v.f64(&["assist"]),
        deaths: v.f64(&["death"]),
        damage: v.f64(&["heroDamage"]),
        healing: v.f64(&["cure"]),
        mitigation: v.f64(&["resistDamage"]),
        final_blows: v.f64(&["finalHit", "finalBlows"]),
        solo_kills: v.f64(&["soloKills", "individualKill"]),
        damage_taken: v.f64(&["damageTaken"]),
        healing_taken: v.f64(&["healingTaken"]),
        objective_time_s: v.f64(&["targetCompetingTime"]),
    }
}

/// Career averages use `ave*` keys; `recentMatchCount` says `aveDamage`.
fn average_line(v: V) -> StatLine {
    StatLine {
        kills: v.f64(&["aveKill"]),
        assists: v.f64(&["aveAssist"]),
        deaths: v.f64(&["aveDeath"]),
        damage: v.f64(&["aveHeroDamage", "aveDamage"]),
        healing: v.f64(&["aveCure"]),
        mitigation: v.f64(&["aveResistDamage"]),
        final_blows: v.f64(&["aveFinalHit"]),
        solo_kills: v.f64(&["aveIndividualKill"]),
        ..StatLine::default()
    }
}

/// Match rows arrive as a bare array or under `matchList` / `recentMatchList` / `list`.
pub fn match_rows(data: &Value) -> Vec<Value> {
    let v = V(data);
    match data {
        Value::Array(a) => a.clone(),
        _ => v.list(&["matchList", "recentMatchList", "list"]),
    }
}

pub fn match_list(data: &Value, requested: Mode, cat: &Catalog) -> Vec<MatchSummary> {
    match_rows(data)
        .iter()
        .filter(|row| row.is_object())
        .map(|row| match_summary(row, requested, cat))
        .collect()
}

pub fn match_summary(row: &Value, requested: Mode, cat: &Catalog) -> MatchSummary {
    let v = V(row);
    let kind = kind(v, requested);
    let score = score(v);
    let hero = entity(cat, EntityKind::Hero, v.str(&["heroGuid", "heroId"]));
    // The hero's catalogued role wins over the list row's `roleType`: for the same
    // match the list can say damage while the detail (and the game) say support
    // (Sombra), which put a support game into the damage quota and filters.
    let role = hero
        .as_ref()
        .map(|h| cat.hero_role(&h.guid))
        .filter(|r| *r != Role::Unknown)
        .or_else(|| {
            v.str(&["roleType"])
                .map(|r| Role::parse(&r))
                .filter(|r| *r != Role::Unknown)
        })
        .unwrap_or(Role::Unknown);
    let highlights = ["killMax", "heroDamageMax", "cureMax", "resistDamageMax"]
        .iter()
        .any(|k| v.bool(k).is_some())
        .then(|| Highlights {
            kills: v.bool("killMax").unwrap_or(false),
            damage: v.bool("heroDamageMax").unwrap_or(false),
            healing: v.bool("cureMax").unwrap_or(false),
            mitigation: v.bool("resistDamageMax").unwrap_or(false),
        });
    MatchSummary {
        id: v.str(&["matchId"]).unwrap_or_default(),
        started_at_ms: v.i64(&["beginTs"]),
        rank: rank(v.get(&["rankInfo"]), kind.mode),
        kind,
        outcome: outcome(v, score).0,
        map: entity(cat, EntityKind::Map, v.str(&["mapGuid"])),
        hero,
        role,
        score,
        stats: stat_line(v),
        highlights,
        hero_icon_url: v.str(&["heroIcon"]),
    }
}

fn participant(
    raw: &Value,
    mode: Mode,
    subject: Option<&str>,
    names: Option<V>,
    cat: &Catalog,
) -> Participant {
    let v = V(raw);
    let bnet_id = v.str(&["bnetId"]);
    let name = v.str(&["name", "userName"]).or_else(|| {
        let id = bnet_id.as_deref()?;
        names?.str(&[id])
    });
    let hero = entity(cat, EntityKind::Hero, v.str(&["heroGuid", "heroId"]));
    let role = v
        .str(&["roleType"])
        .map(|r| Role::parse(&r))
        .filter(|r| *r != Role::Unknown)
        .or_else(|| hero.as_ref().map(|h| cat.hero_role(&h.guid)))
        .unwrap_or(Role::Unknown);
    let perks = v
        .list(&[
            "perks",
            "perkList",
            "heroPerks",
            "perkGuids",
            "perkGuidList",
        ])
        .iter()
        .filter_map(|p| match p {
            Value::Object(_) => Some((
                V(p).str(&["guid", "perkGuid", "id"])?,
                V(p).i64(&["perkLevel", "level"]),
            )),
            other => strings(std::slice::from_ref(other))
                .pop()
                .map(|g| (g, None)),
        })
        .map(|(guid, level)| PerkPick {
            perk: cat.entity_ref(EntityKind::Perk, &guid),
            level: level.and_then(|l| u8::try_from(l).ok()),
        })
        .collect();
    let upgrades = |keys: &[&str]| -> Vec<EntityRef> {
        strings(&v.list(keys))
            .iter()
            .map(|g| cat.entity_ref(EntityKind::StadiumUpgrade, g))
            .collect()
    };
    let stadium = (mode == Mode::Stadium).then(|| StadiumBuild {
        worth: v.f64(&["endWorth", "worth"]),
        powers: upgrades(&["traitGuids"]),
        items: upgrades(&["modGuids"]),
    });
    Participant {
        is_subject: subject.is_some() && bnet_id.as_deref() == subject,
        name,
        bnet_id,
        hero,
        hero_icon_url: v.str(&["heroIcon"]),
        role,
        stats: stat_line(v),
        rank: rank(v.get(&["rankInfo"]), mode),
        perks,
        party_bnet_ids: strings(&v.list(&["friendBnetIds"])),
        endorsed_by_bnet_ids: strings(&v.list(&["endorserBnetIds"])),
        suspended: v.obj(&["riskStatus"]).is_some(),
        stadium,
    }
}

fn team(
    list: &[Value],
    mode: Mode,
    subject: Option<&str>,
    names: Option<V>,
    cat: &Catalog,
) -> Vec<Participant> {
    list.iter()
        .filter(|p| p.is_object())
        .map(|p| participant(p, mode, subject, names, cat))
        .collect()
}

fn stat_values(raw: Option<&Value>, cat: &Catalog) -> Vec<StatValue> {
    let mut out: Vec<StatValue> = match raw {
        Some(Value::Object(o)) => {
            if let Some(inner) = o.get("statMap").filter(|v| v.is_object()) {
                return stat_values(Some(inner), cat);
            }
            o.iter()
                .filter_map(|(k, v)| Some((k.clone(), number(v)?)))
                .collect::<Vec<_>>()
        }
        Some(Value::Array(a)) => a
            .iter()
            .filter_map(|e| {
                let e = V(e);
                Some((
                    e.str(&["valueGuid", "statGuid", "guid"])?,
                    e.f64(&["value"])?,
                ))
            })
            .collect(),
        _ => Vec::new(),
    }
    .into_iter()
    .map(|(guid, value)| StatValue {
        stat: cat.entity_ref(EntityKind::Stat, &guid),
        value,
    })
    .collect();
    out.sort_by(|a, b| a.stat.guid.cmp(&b.stat.guid));
    out
}

/// `queryMatchInfo` / `fight/queryMatchInfo`. `subject_bnet_id` marks the token owner.
pub fn match_detail(
    match_id: &str,
    data: &Value,
    mode: Mode,
    subject_bnet_id: Option<&str>,
    cat: &Catalog,
) -> MatchDetail {
    let root = V(data);
    // Stadium nests the totals under `totalCount`; rosters may sit beside it.
    let total = root.obj(&["totalCount"]).unwrap_or(root);
    let names = root.obj(&["nameMap"]);
    let roster = |key: &str| {
        let list = total.list(&[key]);
        if list.is_empty() {
            root.list(&[key])
        } else {
            list
        }
    };
    let score = Score {
        team: total.i64(&["teamScore"]).or(root.i64(&["teamScore"])),
        opponent: total
            .i64(&["opponentScore"])
            .or(root.i64(&["opponentScore"])),
    };
    let (outcome, outcome_source) = outcome(root, score);
    let subject = subject_bnet_id;
    let allies = team(&roster("teammateList"), mode, subject, names, cat);
    let bans = |key: &str| {
        strings(&root.list(&[key]))
            .iter()
            .map(|g| cat.entity_ref(EntityKind::Hero, g))
            .collect()
    };
    let started_at_ms = root
        .i64(&["startTime"])
        .map(|s| if s < 100_000_000_000 { s * 1000 } else { s })
        .or_else(|| {
            roster("teammateList")
                .iter()
                .find_map(|p| V(p).i64(&["beginTs"]))
        });
    let subject_heroes = root
        .list(&["heroList"])
        .iter()
        .filter_map(|h| {
            let h = V(h);
            Some(HeroSegment {
                hero: cat.entity_ref(EntityKind::Hero, &h.str(&["heroId", "heroGuid"])?),
                play_time_s: h.f64(&["userTimeSec", "useTimeSec"]),
                share: h.f64(&["useTimeRate"]).map(|r| (r / 100.0).clamp(0.0, 1.0)),
                stats: stat_values(h.get(&["statMap"]), cat),
            })
        })
        .collect();
    let rounds = root
        .list(&["roundCountList"])
        .iter()
        .enumerate()
        .map(|(index, r)| {
            let r = V(r);
            Round {
                index,
                map: entity(cat, EntityKind::Map, r.str(&["mapGuid"])),
                score: self::score(r),
                duration_s: r.f64(&["gameTimeSec"]),
                allies: team(&r.list(&["teammateList"]), mode, subject, names, cat),
                enemies: team(&r.list(&["enemyList"]), mode, subject, names, cat),
            }
        })
        .collect();
    MatchDetail {
        id: match_id.to_owned(),
        mode,
        map: entity(
            cat,
            EntityKind::Map,
            total.str(&["mapGuid"]).or(root.str(&["mapGuid"])),
        ),
        outcome,
        outcome_source,
        started_at_ms,
        duration_s: total.f64(&["gameTimeSec"]).or(root.f64(&["gameTimeSec"])),
        score,
        bans: Bans {
            ally: bans("teamBanHeroGuids"),
            enemy: bans("enemyBanHeroGuids"),
        },
        subject_heroes,
        enemies: team(&roster("enemyList"), mode, subject, names, cat),
        allies,
        rounds,
    }
}

/// `searchBnetAccount` or `queryCard` data.
pub fn profile(data: &Value) -> PlayerProfile {
    let v = V(data);
    PlayerProfile {
        name: v.str(&["name"]),
        bnet_id: v.str(&["bnetId"]),
        avatar_url: v.str(&["icon"]),
        title: v.str(&["title"]),
        title_icon_url: v.str(&["titleIcon"]),
        endorsement_level: v.i64(&["level"]),
        play_time_hours: v.f64(&["gameTime"]),
        total_matches: v.i64(&["totalMatchNum"]),
        suspension: v.obj(&["riskStatus"]).map(|r| Suspension {
            status: r.str(&["status"]),
            expires_at_ms: r.i64(&["expireTime"]),
        }),
    }
}

/// Fills fields one profile source lacks from another (search has match totals,
/// the card has suspension state).
pub fn merge_profile(base: &mut PlayerProfile, other: PlayerProfile) {
    macro_rules! fill {
        ($($f:ident),*) => { $( if base.$f.is_none() { base.$f = other.$f; } )* };
    }
    fill!(
        name,
        bnet_id,
        avatar_url,
        title,
        title_icon_url,
        endorsement_level,
        play_time_hours,
        total_matches
    );
    if other.suspension.is_some() {
        base.suspension = other.suspension;
    }
}

fn role_career(v: V, mode: Mode) -> RoleCareer {
    RoleCareer {
        role: v
            .str(&["roleType"])
            .map_or(Role::Unknown, |r| Role::parse(&r)),
        current_rank: rank(v.get(&["lastRankInfo"]), mode),
        peak_rank: rank(v.get(&["maxRankInfo"]), mode),
        matches: v.i64(&["matchSum"]),
        win_rate_pct: v.f64(&["winRate"]),
        kda: v.f64(&["kda"]),
        core_score: v.f64(&["coreCount"]),
        max_win_streak: v.i64(&["maxWinStreak"]),
        queue_guid: v.str(&["rulesetQueueGuid"]),
    }
}

fn queue_summary(v: V, queue: Queue) -> QueueSummary {
    let server = v.obj(&["serverMapCountData"]);
    QueueSummary {
        queue,
        matches: v.i64(&["matchSum"]),
        wins: v.i64(&["matchWinSum"]),
        losses: v.i64(&["matchLossSum"]),
        win_rate_pct: v.f64(&["winRate"]),
        per_match: average_line(v),
        server_average: server.map(|s| StatLine {
            kills: s.f64(&["kill"]),
            deaths: s.f64(&["death"]),
            damage: s.f64(&["damage"]),
            healing: s.f64(&["cure"]),
            mitigation: s.f64(&["resistDamage"]),
            ..StatLine::default()
        }),
        server_max: server.map(|s| StatLine {
            kills: s.f64(&["maxKill"]),
            deaths: s.f64(&["maxDeath"]),
            damage: s.f64(&["maxDamage"]),
            healing: s.f64(&["maxCure"]),
            mitigation: s.f64(&["maxResistDamage"]),
            ..StatLine::default()
        }),
    }
}

fn hero_usage(v: V, queue: Queue, cat: &Catalog) -> Option<HeroUsage> {
    let rank_info = v.obj(&["heroRankInfo"]);
    Some(HeroUsage {
        queue,
        hero: cat.entity_ref(EntityKind::Hero, &v.str(&["heroGuid", "heroId"])?),
        hero_level: v.i64(&["heroLevel"]),
        matches: v.i64(&["matchSum"]),
        wins: v.i64(&["winSum"]),
        win_rate_pct: v.f64(&["winRate"]),
        kda: v.f64(&["kda"]),
        play_time_s: v.f64(&["gameTime"]),
        per_match: stat_values(v.get(&["statAveCount"]), cat),
        per_10min: stat_values(v.get(&["statPerTenMinCount"]), cat),
        rank_tier_index: rank_info.and_then(|r| r.i64(&["rank"])),
        ranked_level: rank_info.and_then(|r| r.i64(&["rankedLevel"])),
    })
}

/// `queryCountInfo` (competitive/quick) or `fight/queryCount` (stadium) data.
pub fn career(data: &Value, mode: Mode, season: Option<u32>, cat: &Catalog) -> CareerSnapshot {
    let v = V(data);
    let mut roles: Vec<RoleCareer> = v
        .list(&["guideCountData"])
        .into_iter()
        .chain(v.list(&["roleTypeCountData"]))
        .filter(|r| r.is_object())
        .map(|r| role_career(V(&r), mode))
        .collect();
    roles.sort_by_key(|r| r.role);
    let queues = [
        ("presetsSummaryData", Queue::RoleQueue),
        ("openSummaryData", Queue::OpenQueue),
    ]
    .iter()
    .filter_map(|(key, queue)| v.obj(&[key]).map(|s| queue_summary(s, *queue)))
    .collect();
    // Hero usage key names differ by queue and mode, including the upstream
    // misspelling `presetsyList` for quick play.
    let hero_lists = [
        ("presetsHeroUseSummaryList", Queue::RoleQueue),
        ("presetsHeroList", Queue::RoleQueue),
        ("presetsyList", Queue::RoleQueue),
        ("openHeroUseSummaryList", Queue::OpenQueue),
        ("openHeroList", Queue::OpenQueue),
        ("v6HeroUseSummaryList", Queue::SixVsSix),
        ("heroUseSummaryList", Queue::Unknown),
    ];
    let mut seen = std::collections::HashSet::new();
    let heroes = hero_lists
        .iter()
        .flat_map(|(key, queue)| {
            v.list(&[key])
                .into_iter()
                .filter_map(move |h| hero_usage(V(&h), *queue, cat))
        })
        .filter(|h| seen.insert((h.queue, h.hero.guid.clone())))
        .collect();
    let recent_matches = v
        .list(&["matchList"])
        .iter()
        .filter(|r| r.is_object())
        .map(|r| match_summary(r, mode, cat))
        .collect();
    CareerSnapshot {
        mode,
        season,
        roles,
        queues,
        recent_form: v.obj(&["recentMatchCount"]).map(|r| RecentForm {
            role: r
                .str(&["roleType"])
                .map_or(Role::Unknown, |x| Role::parse(&x)),
            win_rate_pct: r.f64(&["winRate"]),
            per_match: average_line(r),
        }),
        frequent_heroes: strings(&v.list(&["frequentHeroIds"]))
            .iter()
            .map(|g| cat.entity_ref(EntityKind::Hero, g))
            .collect(),
        heroes,
        province_ranks: v
            .list(&["userProvinceRankList"])
            .iter()
            .map(|p| {
                let p = V(p);
                ProvinceRank {
                    role: p
                        .str(&["roleType"])
                        .map_or(Role::Unknown, |r| Role::parse(&r)),
                    province: p.str(&["province"]),
                    rank: p.i64(&["rankNum"]),
                }
            })
            .collect(),
        behavior: v.obj(&["gameAction"]).map(|g| Behavior {
            comment: g.str(&["comment"]),
            honors_received: g.i64(&["getHonorsCnt"]),
            honors_sent: g.i64(&["sendHonorsCnt"]),
            reports: g.i64(&["reportedCnt"]),
        }),
        recent_matches,
    }
}

/// `billboard/customGetUserHeroBillboard` data.
pub fn player_hero_board(data: &Value, cat: &Catalog) -> Vec<HeroBoardEntry> {
    let v = V(data);
    [
        ("sportPresetHeroBillboardList", Queue::RoleQueue),
        ("sportOpenHeroBillboardList", Queue::OpenQueue),
    ]
    .iter()
    .flat_map(|(key, queue)| {
        v.list(&[key]).into_iter().map(move |e| {
            let e = V(&e);
            HeroBoardEntry {
                queue: *queue,
                hero: entity(cat, EntityKind::Hero, e.str(&["heroGuid"])),
                province: e.str(&["province"]),
                rank: e.i64(&["rankNum"]),
                ranked_level: e.i64(&["rankedLevel"]),
                matches: e.i64(&["matchSum"]),
                win_rate_pct: e.f64(&["winRate"]),
            }
        })
    })
    .collect()
}

/// `(bnet_id, customerToken, name)` for every rostered player in a match detail.
/// Tokens never enter the IR; this exists only so a collector can look up other
/// players' careers in memory.
pub fn participant_tokens(data: &Value) -> Vec<(String, String, Option<String>)> {
    let root = V(data);
    let total = root.obj(&["totalCount"]).unwrap_or(root);
    let names = root.obj(&["nameMap"]);
    ["teammateList", "enemyList"]
        .iter()
        .flat_map(|key| {
            let list = total.list(&[key]);
            if list.is_empty() {
                root.list(&[key])
            } else {
                list
            }
        })
        .filter_map(|p| {
            let p = V(&p);
            let id = p.str(&["bnetId"])?;
            let token = p.str(&["customerToken"])?;
            let name = p.str(&["name", "userName"]).or_else(|| names?.str(&[&id]));
            Some((id, token, name))
        })
        .collect()
}

/// Ranked roles from one competitive career payload.
pub fn role_ratings(data: &Value, season: Option<u32>) -> Vec<RoleRating> {
    V(data)
        .list(&["guideCountData"])
        .iter()
        .filter_map(|r| {
            let r = V(r);
            let role = Role::parse(&r.str(&["roleType"])?);
            let rank = rank(r.get(&["lastRankInfo"]), Mode::Competitive)?;
            (role != Role::Unknown && rank.skill_rating.is_some()).then_some(RoleRating {
                role,
                season,
                rank,
            })
        })
        .collect()
}
