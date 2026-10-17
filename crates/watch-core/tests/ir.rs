//! Normalization, collection and analysis over fixtures derived from masked
//! upstream captures (Overstats `src/client/api_structure`).
use serde_json::{Value, json};
use std::collections::HashMap;
use std::sync::Mutex;
use watch_core::{
    Catalog, Failure,
    analysis::{self, AnalysisOptions, Clock, Dimension, Window},
    collect::{self, CollectPlan, Fetched, Fetcher},
    dashen::{Endpoint, Mode, normalize},
    ir::*,
    strength::{self, RatingSource},
};

fn fixture(name: &str) -> Value {
    let path = format!("{}/tests/fixtures/{name}.json", env!("CARGO_MANIFEST_DIR"));
    serde_json::from_slice(&std::fs::read(path).unwrap()).unwrap()
}

fn catalog() -> Catalog {
    Catalog::from_legacy(&json!({
        "heroList":[
            {"heroGuid":"207165582859043685","id":"0x02E0000000000365","name":"安娜","roleType":"healer"},
            {"heroGuid":"207165582859042818","id":"0x02E0000000000002","name":"死神","roleType":"dps"},
            {"heroGuid":"207165582859042819","name":"莱因哈特","roleType":"tank"},
            {"heroGuid":"207165582859042820","name":"源氏","roleType":"dps"}
        ],
        "mapList":[{"guid":"576460752303424195","id":"0x08000000000002C3","name":"努巴尼","mode":"运载目标"}],
        "heroAttrList":[{"heroGuid":"207165582859043685","valueGuid":"603482350067646495","valueText":"消灭","valueType":"通用数据"}],
        "perkList":[{"guid":"920986123797276132","id":"0x0CC80000000025E4","name":"纳米强化"}]
    }))
}

#[test]
fn career_snapshot_types_every_documented_block() {
    let cat = catalog();
    let c = normalize::career(
        normalize::payload(&fixture("queryCountInfo")),
        Mode::Competitive,
        None,
        &cat,
    );
    let role = &c.roles[0];
    assert_eq!(role.role, Role::Support);
    assert_eq!(role.win_rate_pct, Some(64.18));
    assert_eq!(role.kda, Some(5.8));
    let current = role.current_rank.as_ref().unwrap();
    assert_eq!(
        (
            current.tier.as_deref(),
            current.division,
            current.skill_rating
        ),
        (Some("Platinum"), Some(5), Some(2000))
    );
    assert_eq!(role.peak_rank.as_ref().unwrap().skill_rating, Some(3200));
    let queue = &c.queues[0];
    assert_eq!(
        (queue.queue, queue.wins, queue.losses),
        (Queue::RoleQueue, Some(62), Some(40))
    );
    assert_eq!(queue.per_match.damage, Some(7023.0));
    assert_eq!(queue.server_max.as_ref().unwrap().kills, Some(20.0));
    assert_eq!(
        c.recent_form.as_ref().unwrap().per_match.damage,
        Some(3634.0)
    );
    let hero = &c.heroes[0];
    assert_eq!(hero.hero.name.as_deref(), Some("安娜"));
    assert_eq!(hero.per_match[0].stat.name.as_deref(), Some("消灭"));
    assert_eq!(hero.per_10min[0].value, 7.1);
    assert_eq!(
        c.frequent_heroes[0].official_id.as_deref(),
        Some("0x02E0000000000365")
    );
    assert_eq!(c.province_ranks[0].rank, Some(321));
    assert_eq!(c.behavior.as_ref().unwrap().honors_received, Some(30));
    assert_eq!(c.recent_matches[0].kind.ranked, Some(true));
}

#[test]
fn match_rows_parse_strings_modes_ranks_and_highlights() {
    let cat = catalog();
    let rows = normalize::match_list(
        normalize::payload(&fixture("queryMatchList")),
        Mode::Competitive,
        &cat,
    );
    assert_eq!(rows.len(), 3);
    assert!(rows[0].highlights.unwrap().healing);
    assert_eq!(
        rows[0].map.as_ref().unwrap().name.as_deref(),
        Some("努巴尼")
    );
    // String-encoded numbers and an empty rank object.
    assert_eq!(
        (
            rows[1].outcome,
            rows[1].stats.damage,
            rows[1].rank.is_none()
        ),
        (Outcome::Loss, Some(1000.0), true)
    );
    assert_eq!(
        (rows[2].outcome, rows[2].kind.queue, rows[2].kind.ranked),
        (Outcome::Draw, Queue::OpenQueue, Some(false))
    );
    assert_eq!(rows[2].stats.healing, None);
    // Compact rank decoding when only the score is present.
    let r = normalize::rank(Some(&json!({"rankScore":497})), Mode::Competitive).unwrap();
    assert_eq!(
        (r.tier.as_deref(), r.division, r.skill_rating),
        (Some("Diamond"), Some(3), Some(3200))
    );
    let emerald = normalize::rank(Some(&json!({"rankScore":896})), Mode::Competitive).unwrap();
    assert_eq!(emerald.tier.as_deref(), Some("Emerald"));
}

#[test]
fn match_detail_marks_subject_and_drops_credentials() {
    let cat = catalog();
    let d = normalize::match_detail(
        "m3",
        normalize::payload(&fixture("queryMatchInfo")),
        Mode::Competitive,
        Some("1001"),
        &cat,
    );
    assert_eq!(
        (d.outcome, d.outcome_source),
        (Outcome::Win, OutcomeSource::Provider)
    );
    assert_eq!(d.started_at_ms, Some(1_777_212_060_000));
    assert_eq!(d.duration_s, Some(955.0));
    let me = d.subject().unwrap();
    assert_eq!(me.name.as_deref(), Some("Me#1001"));
    assert_eq!(me.stats.final_blows, Some(3.0));
    assert_eq!(me.perks[0].perk.name.as_deref(), Some("纳米强化"));
    assert_eq!(me.party_bnet_ids, vec!["1002"]);
    // Perks encoded as a JSON string; role inferred from the catalog when absent.
    assert_eq!(d.allies[2].perks[0].level, Some(2));
    assert_eq!(d.allies[1].role, Role::Damage);
    assert!(d.enemies[0].suspended);
    assert_eq!(d.bans.ally.len(), 1, "\"0\" is an empty ban slot");
    assert_eq!(d.subject_heroes[0].share, Some(1.0));
    assert_eq!(d.subject_heroes[0].stats.len(), 2);
    assert!(!serde_json::to_string(&d).unwrap().contains("SECRET"));
}

#[test]
fn stadium_detail_uses_totals_name_map_and_score_outcome() {
    let cat = catalog();
    let d = normalize::match_detail(
        "s1",
        normalize::payload(&fixture("fightQueryMatchInfo")),
        Mode::Stadium,
        Some("1001"),
        &cat,
    );
    assert_eq!(
        (d.outcome, d.outcome_source),
        (Outcome::Loss, OutcomeSource::Score)
    );
    assert_eq!(d.duration_s, Some(1200.0));
    let me = d.subject().unwrap();
    assert_eq!(me.name.as_deref(), Some("Me#1001"));
    let build = me.stadium.as_ref().unwrap();
    assert_eq!(
        (build.worth, build.powers.len(), build.items.len()),
        (Some(45000.0), 1, 1)
    );
    assert_eq!(
        me.rank.as_ref().unwrap().skill_rating,
        Some(2650),
        "stadium scores are continuous"
    );
    assert_eq!(d.enemies[0].name.as_deref(), Some("Foe#2001"));
    assert_eq!(d.rounds.len(), 1);
}

#[test]
fn profile_merges_search_and_card() {
    let mut p = normalize::profile(
        &json!({"name":"Me#1001","bnetId":1001,"totalMatchNum":123,"customerToken":"SECRET"}),
    );
    normalize::merge_profile(
        &mut p,
        normalize::profile(normalize::payload(&fixture("queryCard"))),
    );
    assert_eq!(p.total_matches, Some(123));
    assert_eq!(p.play_time_hours, Some(1063.29));
    assert_eq!(p.bnet_id.as_deref(), Some("1001"));
    assert_eq!(p.suspension.unwrap().expires_at_ms, Some(1_787_127_797_000));
    let board = normalize::player_hero_board(
        normalize::payload(&fixture("customGetUserHeroBillboard")),
        &catalog(),
    );
    assert_eq!(
        (board[0].queue, board[0].rank, board[0].win_rate_pct),
        (Queue::RoleQueue, Some(1860), Some(72.73))
    );
}

/// Serves fixtures by endpoint; page 2+ repeats page 1, as the provider does.
struct FakeDashen {
    calls: Mutex<Vec<(Endpoint, Value)>>,
    fail: Option<Endpoint>,
}

impl Fetcher for FakeDashen {
    async fn fetch(&self, endpoint: Endpoint, payload: Value) -> Result<Fetched, Failure> {
        self.calls.lock().unwrap().push((endpoint, payload.clone()));
        if Some(endpoint) == self.fail {
            return Err(Failure {
                kind: "upstream",
                message: "down".into(),
                retry_after_ms: None,
            });
        }
        let value = match endpoint {
            Endpoint::Card => fixture("queryCard"),
            Endpoint::CareerCount => fixture("queryCountInfo"),
            Endpoint::MatchList if payload["gameMode"] == "sport" => fixture("queryMatchList"),
            Endpoint::MatchList => json!({"code":0,"data":[]}),
            Endpoint::MatchInfo => fixture("queryMatchInfo"),
            Endpoint::PlayerHeroBoard => fixture("customGetUserHeroBillboard"),
            _ => json!({"code":0,"data":{}}),
        };
        Ok(Fetched {
            value,
            cached: false,
        })
    }
}

#[tokio::test]
async fn collector_builds_a_complete_dataset_with_coverage() {
    let fake = FakeDashen {
        calls: Mutex::new(Vec::new()),
        fail: None,
    };
    let plan = CollectPlan {
        max_details: 2,
        career_seasons: vec![20],
        ..CollectPlan::default()
    };
    let identity = json!({"name":"Me#1001","bnetId":"1001"});
    let ds = collect::collect_player(&fake, &catalog(), "TOKEN", &identity, &plan).await;
    assert_eq!(ds.matches.len(), 3);
    assert!(
        ds.matches
            .windows(2)
            .all(|w| w[0].started_at_ms >= w[1].started_at_ms)
    );
    assert_eq!(ds.careers.len(), 4, "2 modes × (current + season 20)");
    assert_eq!(
        (ds.coverage.details_requested, ds.coverage.details_ok),
        (2, 2)
    );
    assert!(ds.coverage.match_lists.iter().all(|l| l.exhausted));
    assert_eq!(
        ds.coverage.match_lists[0].pages_fetched, 2,
        "page 2 repeated page 1"
    );
    assert!(ds.details["m3"].subject().is_some());
    assert!(ds.profile.suspension.is_some());
    assert_eq!(ds.hero_boards.len(), 1);
    let calls = fake.calls.lock().unwrap();
    assert!(
        calls
            .iter()
            .any(|(e, p)| *e == Endpoint::CareerCount && p["season"] == 20)
    );
    // Round-trips, so saved datasets can be analysed offline.
    let text = serde_json::to_string(&ds).unwrap();
    assert!(!text.contains("SECRET"));
    let back: PlayerDataset = serde_json::from_str(&text).unwrap();
    assert_eq!(back, ds);
}

#[tokio::test]
async fn collector_records_failures_instead_of_aborting() {
    let fake = FakeDashen {
        calls: Mutex::new(Vec::new()),
        fail: Some(Endpoint::MatchInfo),
    };
    let ds = collect::collect_player(
        &fake,
        &catalog(),
        "TOKEN",
        &json!({}),
        &CollectPlan::default(),
    )
    .await;
    assert_eq!(ds.matches.len(), 3);
    assert_eq!(ds.coverage.details_ok, 0);
    assert_eq!(ds.coverage.failures(), 3);
    assert!(
        ds.coverage
            .fetches
            .iter()
            .filter(|f| !f.ok)
            .all(|f| f.error_kind.as_deref() == Some("upstream"))
    );
}

#[tokio::test]
async fn search_requires_a_customer_token() {
    struct Search(Value);
    impl Fetcher for Search {
        async fn fetch(&self, _: Endpoint, _: Value) -> Result<Fetched, Failure> {
            Ok(Fetched {
                value: self.0.clone(),
                cached: false,
            })
        }
    }
    let ok = Search(json!({"code":0,"data":{"name":"A#1","customerToken":"T"}}));
    assert_eq!(collect::search_player(&ok, " A＃1 ").await.unwrap().0, "T");
    let missing = Search(json!({"code":0,"data":{"name":"A#1"}}));
    assert_eq!(
        collect::search_player(&missing, "A#1")
            .await
            .unwrap_err()
            .kind,
        "business"
    );
    assert_eq!(
        collect::search_player(&ok, "  ").await.unwrap_err().kind,
        "validation"
    );
}

fn row(id: &str, at: i64, outcome: Outcome, hero: &str, damage: Option<f64>) -> MatchSummary {
    let cat = catalog();
    let mut m = normalize::match_summary(
        &json!({"matchId":id,"beginTs":at,"heroGuid":hero,"kill":1,"assist":1,"death":1}),
        Mode::Competitive,
        &cat,
    );
    m.outcome = outcome;
    m.stats.damage = damage;
    m
}

#[test]
fn aggregate_skips_missing_values_and_tracks_streaks() {
    let hour = 3_600_000;
    let rows = vec![
        row(
            "a",
            4 * hour,
            Outcome::Win,
            "207165582859043685",
            Some(100.0),
        ),
        row("b", 3 * hour, Outcome::Win, "207165582859043685", None),
        row(
            "c",
            2 * hour,
            Outcome::Loss,
            "207165582859042818",
            Some(300.0),
        ),
        row("d", hour, Outcome::Draw, "207165582859042818", Some(200.0)),
    ];
    let a = analysis::aggregate(&rows);
    assert_eq!(a.record.win_rate_pct.map(|r| r.round()), Some(67.0));
    assert_eq!(
        a.per_match.damage,
        Some(200.0),
        "mean over the 3 rows that supplied damage"
    );
    assert_eq!(a.samples["damage"], 3);
    assert_eq!((a.streaks.best_win, a.streaks.current), (2, 2));
    assert_eq!(a.kda, Some(2.0));
    let heroes = analysis::breakdown(&rows, Dimension::Hero);
    assert_eq!(heroes.len(), 2);
    assert_eq!(
        heroes
            .iter()
            .find(|g| g.label.as_deref() == Some("安娜"))
            .unwrap()
            .aggregate
            .record
            .wins,
        2
    );
    let sessions = analysis::sessions(&rows, hour);
    assert_eq!(sessions.len(), 1);
    assert_eq!(analysis::sessions(&rows, hour - 1).len(), 4);
    let common = analysis::common_matches(&rows, &rows[1..3]);
    assert_eq!(
        common.iter().map(|m| m.id.as_str()).collect::<Vec<_>>(),
        vec!["b", "c"]
    );
}

#[test]
fn windows_use_the_configured_calendar_zone() {
    let day = 86_400_000;
    // 2026-10-17 01:00 UTC is 10:00 in UTC+09.
    let now = 20_378 * day + 3_600_000;
    let clock = Clock {
        now_ms: now,
        utc_offset_minutes: 9 * 60,
    };
    let local_midnight = 20_378 * day - 9 * 3_600_000;
    assert!(Window::Today.contains(clock, Some(local_midnight)));
    assert!(!Window::Today.contains(clock, Some(local_midnight - 1)));
    assert!(Window::Yesterday.contains(clock, Some(local_midnight - 1)));
    assert!(!Window::Week.contains(clock, None));
    assert!(Window::All.contains(clock, None));
    assert_eq!(clock.local_hour(now), 10);
}

#[test]
fn team_share_and_companions_come_from_details() {
    let cat = catalog();
    let d = normalize::match_detail(
        "m3",
        normalize::payload(&fixture("queryMatchInfo")),
        Mode::Competitive,
        Some("1001"),
        &cat,
    );
    let share = analysis::team_share(&d).unwrap();
    assert!((share.share.damage.unwrap() - 4631.0 / 20631.0).abs() < 1e-9);
    assert!(share.team_best.healing && !share.team_best.damage);
    let mut details = std::collections::BTreeMap::new();
    details.insert(d.id.clone(), d);
    let people = analysis::companions(&details, 1);
    let pal = people
        .iter()
        .find(|c| c.bnet_id.as_deref() == Some("1002"))
        .unwrap();
    assert_eq!((pal.as_ally.wins, pal.in_party), (1, 1));
    let tank = people
        .iter()
        .find(|c| c.bnet_id.as_deref() == Some("1003"))
        .unwrap();
    assert_eq!(tank.in_party, 0);
}

#[tokio::test]
async fn full_analysis_runs_on_a_collected_dataset() {
    let fake = FakeDashen {
        calls: Mutex::new(Vec::new()),
        fail: None,
    };
    let ds = collect::collect_player(
        &fake,
        &catalog(),
        "TOKEN",
        &json!({"bnetId":"1001"}),
        &CollectPlan::default(),
    )
    .await;
    let a = analysis::analyze(
        &ds,
        &AnalysisOptions {
            now_ms: Some(1_777_212_060_658),
            ..AnalysisOptions::default()
        },
    );
    assert_eq!(a.overall.record.matches, 3);
    assert_eq!(a.by_queue.len(), 2);
    assert_eq!(a.by_hour.len(), 24);
    assert_eq!(a.rank_timeline.len(), 1);
    assert_eq!(a.team_share.matches, 3);
    assert!(!a.season_trend.is_empty());
    let mut seen = HashMap::new();
    for w in &a.windows {
        seen.insert(format!("{:?}", w.window), w.aggregate.record.matches);
    }
    assert_eq!(seen["Week"], 3);
}

fn rating(id: &str, role: Role, sr: i64, season: Option<u32>) -> PlayerRating {
    PlayerRating {
        bnet_id: id.into(),
        name: None,
        roles: vec![RoleRating {
            role,
            season,
            rank: Rank {
                tier: None,
                division: None,
                score: None,
                skill_rating: Some(sr),
                at_ms: None,
            },
        }],
    }
}

#[test]
fn lobby_strength_is_split_by_role_and_side() {
    let cat = catalog();
    let mut d = normalize::match_detail(
        "m3",
        normalize::payload(&fixture("queryMatchInfo")),
        Mode::Quick,
        Some("1001"),
        &cat,
    );
    d.started_at_ms = Some(1);
    let ratings = vec![
        rating("1001", Role::Support, 2000, None),
        rating("1002", Role::Damage, 3200, None),
        rating("1003", Role::Tank, 2500, Some(24)),
        rating("2001", Role::Damage, 2600, None),
        // A rating for a role they did not play this match is ignored.
        rating("9999", Role::Tank, 4800, None),
    ];
    let mut details = std::collections::BTreeMap::new();
    details.insert(d.id.clone(), d);
    let lobby = strength::lobby_strength(&details, &ratings);
    let m = &lobby.matches[0];
    assert_eq!(
        (m.source, m.subject_role),
        (RatingSource::Career, Role::Support)
    );
    assert_eq!(
        (m.ally.mean.tank, m.ally.mean.damage, m.ally.mean.support),
        (Some(2500.0), Some(3200.0), Some(2000.0))
    );
    assert!((m.ally.mean.overall.unwrap() - 7700.0 / 3.0).abs() < 1e-9);
    assert_eq!((m.ally.rated.overall, m.ally.players), (3, 3));
    assert_eq!(
        (m.enemy.mean.damage, m.enemy.mean.tank),
        (Some(2600.0), None)
    );
    assert_eq!(m.diff.damage, Some(600.0));
    assert_eq!(m.diff.tank, None, "no enemy tank was rated");
    assert!((m.lobby.overall.unwrap() - 10300.0 / 4.0).abs() < 1e-9);
    assert_eq!(lobby.by_mode.len(), 1);
    let supp = &lobby.by_subject_role[0];
    assert_eq!(
        (supp.subject_role, supp.record.wins),
        (Some(Role::Support), 1)
    );
    assert_eq!(supp.ally.damage, Some(3200.0));
    assert_eq!(strength::rating_tier(2350.0), Some(("Platinum", 2)));
    assert_eq!(strength::rating_tier(4999.0), Some(("Champion", 1)));
}

#[tokio::test]
async fn collector_rates_unranked_participants_with_previous_season_fallback() {
    struct Careers(Mutex<Vec<(String, Option<u64>)>>);
    impl Fetcher for Careers {
        async fn fetch(&self, endpoint: Endpoint, payload: Value) -> Result<Fetched, Failure> {
            let value = match endpoint {
                Endpoint::MatchList if payload["gameMode"] == "leisure" => {
                    json!({"code":0,"data":[{"matchId":"q1","matchRet":1,"beginTs":5,"gameMode":"LeisurePreset"}]})
                }
                Endpoint::MatchInfo => fixture("queryMatchInfo"),
                Endpoint::CareerCount if payload["token"] != "TOKEN" => {
                    let token = payload["token"].as_str().unwrap().to_string();
                    let season = payload["season"].as_u64();
                    self.0.lock().unwrap().push((token.clone(), season));
                    let row = |role: &str, score: u64| json!({"roleType":role,"lastRankInfo":{"rankScore":score}});
                    let rows = match (token.as_str(), season) {
                        ("SECRET-1", None) => vec![row("healer", 395)],
                        ("SECRET-2", Some(24)) => vec![row("dps", 497)],
                        // Ranked on another role only: not used for the role played.
                        ("SECRET-3", _) => vec![row("tank", 795)],
                        _ => vec![],
                    };
                    json!({"code":0,"data":{"guideCountData":rows}})
                }
                _ => json!({"code":0,"data":[]}),
            };
            Ok(Fetched {
                value,
                cached: false,
            })
        }
    }
    let fake = Careers(Mutex::new(Vec::new()));
    let plan = CollectPlan {
        modes: vec![Mode::Quick],
        lobby_ratings: true,
        hero_board: false,
        ..CollectPlan::default()
    };
    let ds =
        collect::collect_player(&fake, &catalog(), "TOKEN", &json!({"bnetId":"1001"}), &plan).await;
    let calls = fake.0.lock().unwrap().clone();
    assert!(calls.contains(&("SECRET-1".into(), None)));
    assert!(
        !calls.contains(&("SECRET-1".into(), Some(24))),
        "current season already covered the role"
    );
    assert!(calls.contains(&("SECRET-2".into(), Some(24))));
    assert_eq!(ds.player_ratings.len(), 3, "Tank#1003 has no token");
    let a = analysis::analyze(&ds, &AnalysisOptions::default());
    let m = &a.lobby_strength.matches[0];
    assert_eq!(
        (m.ally.mean.support, m.ally.mean.damage),
        (Some(2000.0), Some(3200.0))
    );
    assert_eq!(
        m.enemy.rated.overall, 0,
        "the enemy is only ranked on tank but played damage"
    );
    assert!(!serde_json::to_string(&ds).unwrap().contains("SECRET"));
}

#[tokio::test]
async fn competitive_lobbies_use_in_match_ranks_without_extra_requests() {
    let fake = FakeDashen {
        calls: Mutex::new(Vec::new()),
        fail: None,
    };
    let mut detail = fixture("queryMatchInfo");
    for p in detail["data"]["teammateList"].as_array_mut().unwrap() {
        p["rankInfo"] = json!({"rankName":"Gold","rankSubTier":1,"rankScore":291});
    }
    let cat = catalog();
    let d = normalize::match_detail(
        "m",
        normalize::payload(&detail),
        Mode::Competitive,
        Some("1001"),
        &cat,
    );
    let m = strength::match_strength(&d, &HashMap::new());
    assert_eq!(
        (m.source, m.ally.mean.overall, m.ally.mean.tank),
        (RatingSource::InMatch, Some(1900.0), Some(1900.0))
    );
    let plan = CollectPlan {
        lobby_ratings: true,
        max_details: 1,
        ..CollectPlan::default()
    };
    let ds = collect::collect_player(&fake, &cat, "TOKEN", &json!({"bnetId":"1001"}), &plan).await;
    // The fixture has no in-match ranks, so its tokened, role-known players get looked up.
    assert_eq!(ds.player_ratings.len(), 3);
    drop(fake);
}

fn role_row(id: &str, at: i64, role: &str) -> Value {
    json!({"matchId":id,"beginTs":at,"roleType":role,"matchRet":1,"gameMode":"LeisurePreset"})
}

#[test]
fn per_role_selection_takes_the_newest_n_of_each_role_and_what_exists() {
    let cat = catalog();
    // Newest first: 5 support, 2 tank, 4 damage, 1 unknown role.
    let rows = json!([
        role_row("s1", 20, "healer"),
        role_row("s2", 19, "healer"),
        role_row("t1", 18, "tank"),
        role_row("d1", 17, "dps"),
        role_row("s3", 16, "healer"),
        role_row("u1", 15, ""),
        role_row("d2", 14, "dps"),
        role_row("s4", 13, "healer"),
        role_row("t2", 12, "tank"),
        role_row("d3", 11, "dps"),
        role_row("s5", 10, "healer"),
        role_row("d4", 9, "dps"),
    ]);
    let list = normalize::match_list(&rows, Mode::Quick, &cat);
    let ids = |picked: Vec<usize>| {
        picked
            .into_iter()
            .map(|i| list[i].id.clone())
            .collect::<Vec<_>>()
    };
    assert_eq!(
        ids(collect::select_per_role(&list, 2)),
        ["s1", "s2", "t1", "d1", "d2", "t2"]
    );
    // Asking for more than exists returns everything the player has, never padding.
    let all = ids(collect::select_per_role(&list, 10));
    assert_eq!(all.len(), 11, "the match with no role is never chosen");
    assert!(!all.contains(&"u1".to_string()));
    assert!(collect::role_quota_met(&list, 2));
    assert!(
        !collect::role_quota_met(&list, 3),
        "only two tank matches exist"
    );
}

#[tokio::test]
async fn paging_stops_once_every_role_has_enough_and_the_dataset_uses_only_those_matches() {
    struct Pager(Mutex<Vec<u64>>);
    impl Fetcher for Pager {
        async fn fetch(&self, endpoint: Endpoint, payload: Value) -> Result<Fetched, Failure> {
            let value = match endpoint {
                Endpoint::MatchList => {
                    let page = payload["page"].as_u64().unwrap();
                    self.0.lock().unwrap().push(page);
                    // Each page holds one match per role, with page-unique ids.
                    let at = 1000 - page as i64 * 10;
                    json!({"code":0,"data":[
                        role_row(&format!("t{page}"), at, "tank"),
                        role_row(&format!("d{page}"), at - 1, "dps"),
                        role_row(&format!("s{page}"), at - 2, "healer"),
                    ]})
                }
                Endpoint::MatchInfo => fixture("queryMatchInfo"),
                _ => json!({"code":0,"data":{}}),
            };
            Ok(Fetched {
                value,
                cached: false,
            })
        }
    }
    let fake = Pager(Mutex::new(Vec::new()));
    let plan = CollectPlan {
        modes: vec![Mode::Quick],
        max_pages: 20,
        details_per_role: Some(3),
        hero_board: false,
        ..CollectPlan::default()
    };
    let ds = collect::collect_player(&fake, &catalog(), "T", &json!({}), &plan).await;
    assert_eq!(
        *fake.0.lock().unwrap(),
        vec![1, 2, 3],
        "three pages give three matches per role; no further paging"
    );
    assert_eq!(ds.coverage.details_requested, 9);
    assert_eq!(ds.coverage.details_ok, 9);
    assert!(plan.validate().is_ok());
    assert!(
        CollectPlan {
            details_per_role: Some(0),
            ..CollectPlan::default()
        }
        .validate()
        .is_err()
    );
}
