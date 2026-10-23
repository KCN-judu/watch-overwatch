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
fn a_new_season_shows_as_the_current_answer_equalling_the_next_numbered_one() {
    let cat = catalog();
    let raw = fixture("queryCountInfo");
    let current = normalize::career(normalize::payload(&raw), Mode::Competitive, None, &cat);
    let numbered = normalize::career(normalize::payload(&raw), Mode::Competitive, Some(26), &cat);
    // Same play, only the requested season differs: the provider is in season 26.
    assert!(collect::same_season_data(&current, &numbered));
    // A season that has not started comes back empty.
    let empty = normalize::career(&json!({}), Mode::Competitive, Some(26), &cat);
    assert!(!collect::same_season_data(&current, &empty));
    // Two empty answers say nothing (a player with no matches this season).
    assert!(!collect::same_season_data(&empty, &empty));
    // Different records are different seasons.
    let mut other = numbered.clone();
    other.roles[0].matches = other.roles[0].matches.map(|m| m + 1);
    assert!(!collect::same_season_data(&current, &other));
}

#[test]
fn the_current_season_only_moves_forward() {
    let cat = catalog();
    let start = cat.current_season.get();
    assert!(cat.current_season.advance_to(start + 1));
    assert!(!cat.current_season.advance_to(start));
    assert_eq!(cat.current_season.get(), start + 1);
    // A copy of the catalog carries the season it had.
    assert_eq!(cat.clone().current_season.get(), start + 1);
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
    let ratings = [
        rating("1001", Role::Support, 2000, None),
        rating("1002", Role::Damage, 3200, None),
        rating("1003", Role::Tank, 2500, Some(24)),
        rating("2001", Role::Damage, 2600, None),
        // A rating for a role they did not play this match is ignored.
        rating("9999", Role::Tank, 4800, None),
    ];
    // The analysis reads the snapshots taken from these ranks, nothing else.
    let by_id = ratings.iter().map(|r| (r.bnet_id.as_str(), r)).collect();
    watch_core::snapshot::take(&mut d, &by_id, 0);
    let mut details = std::collections::BTreeMap::new();
    details.insert(d.id.clone(), d);
    let lobby = strength::lobby_strength(&details);
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
                        // Ranked on another role only: used, and counted as such.
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
        (m.enemy.rated.overall, m.enemy.other_role),
        (1, 1),
        "the enemy is ranked only on tank but played damage: rated by that rank, and counted as such"
    );
    assert_eq!(m.ally.other_role, 0);
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
    let m = strength::match_strength(&d);
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

// ---- strength cache and single-role selection -------------------------------------------

/// Counts the requests a run makes, so cache hits show up as requests that did not happen.
struct Counting {
    info: Mutex<usize>,
    careers: Mutex<usize>,
}
impl Counting {
    fn new() -> Self {
        Self {
            info: Mutex::new(0),
            careers: Mutex::new(0),
        }
    }
    fn counts(&self) -> (usize, usize) {
        (*self.info.lock().unwrap(), *self.careers.lock().unwrap())
    }
}
impl Fetcher for Counting {
    async fn fetch(&self, endpoint: Endpoint, payload: Value) -> Result<Fetched, Failure> {
        let value = match endpoint {
            Endpoint::MatchList if payload["gameMode"] == "leisure" => {
                json!({"code":0,"data":[{"matchId":"q1","matchRet":1,"beginTs":5,"gameMode":"LeisurePreset"}]})
            }
            Endpoint::MatchInfo => {
                *self.info.lock().unwrap() += 1;
                fixture("queryMatchInfo")
            }
            Endpoint::CareerCount if payload["token"] != "TOKEN" => {
                *self.careers.lock().unwrap() += 1;
                let token = payload["token"].as_str().unwrap().to_string();
                let season = payload["season"].as_u64();
                let row = |role: &str, score: u64| json!({"roleType":role,"lastRankInfo":{"rankScore":score}});
                let rows = match (token.as_str(), season) {
                    ("SECRET-1", None) => vec![row("healer", 395)],
                    ("SECRET-2", Some(24)) => vec![row("dps", 497)],
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

fn cached_plan(cache: &std::sync::Arc<dyn watch_core::StrengthCache>) -> CollectPlan {
    CollectPlan {
        modes: vec![Mode::Quick],
        lobby_ratings: true,
        hero_board: false,
        cache: Some(cache.clone()),
        ..CollectPlan::default()
    }
}

fn lobby_means(ds: &PlayerDataset) -> (Option<f64>, Option<f64>) {
    let a = analysis::analyze(ds, &AnalysisOptions::default());
    let m = &a.lobby_strength.matches[0];
    (m.ally.mean.support, m.ally.mean.damage)
}

#[tokio::test]
async fn a_repeat_run_is_served_from_the_cache_with_the_same_result() {
    let mem = std::sync::Arc::new(watch_core::MemoryCache::new());
    let cache: std::sync::Arc<dyn watch_core::StrengthCache> = mem;
    let fake = Counting::new();
    let plan = cached_plan(&cache);
    let id = json!({"bnetId":"1001"});

    let first = collect::collect_player(&fake, &catalog(), "TOKEN", &id, &plan).await;
    let (info1, careers1) = fake.counts();
    assert_eq!(info1, 1);
    assert!(careers1 > 0, "the first run looks the players up");
    assert_eq!(first.coverage.cache_hits, 0);

    let second = collect::collect_player(&fake, &catalog(), "TOKEN", &id, &plan).await;
    assert_eq!(
        fake.counts(),
        (info1, careers1),
        "the second run needs no detail or career request"
    );
    assert!(second.coverage.cache_hits > 0);
    assert_eq!(lobby_means(&first), lobby_means(&second));
    // The second run reads the snapshots kept with the match: nobody is looked up.
    assert_eq!(
        (first.player_ratings.len(), second.player_ratings.len()),
        (3, 0)
    );
    assert!(
        !serde_json::to_string(&second).unwrap().contains("SECRET"),
        "tokens are never cached or returned"
    );
}

#[tokio::test]
async fn a_match_with_its_snapshots_is_not_read_again_when_the_stored_ranks_are_gone() {
    let mem = std::sync::Arc::new(watch_core::MemoryCache::new());
    let cache: std::sync::Arc<dyn watch_core::StrengthCache> = mem.clone();
    let fake = Counting::new();
    let plan = cached_plan(&cache);
    let id = json!({"bnetId":"1001"});
    let first = collect::collect_player(&fake, &catalog(), "TOKEN", &id, &plan).await;
    let (_, careers1) = fake.counts();

    // The stored ranks are gone but the match keeps its snapshots: nothing is asked.
    mem.clear_ratings();
    let second = collect::collect_player(&fake, &catalog(), "TOKEN", &id, &plan).await;
    let (info2, careers2) = fake.counts();
    assert_eq!(info2, 1);
    assert_eq!(careers2, careers1);
    assert_eq!(lobby_means(&first), lobby_means(&second));
}

#[tokio::test]
async fn refreshing_ratings_leaves_a_snapshotted_match_as_it_was() {
    let mem = std::sync::Arc::new(watch_core::MemoryCache::new());
    let cache: std::sync::Arc<dyn watch_core::StrengthCache> = mem;
    let fake = Counting::new();
    let id = json!({"bnetId":"1001"});
    let plan = cached_plan(&cache);
    collect::collect_player(&fake, &catalog(), "TOKEN", &id, &plan).await;
    let (_, before) = fake.counts();
    let refresh = CollectPlan {
        refresh_ratings: true,
        ..cached_plan(&cache)
    };
    let ds = collect::collect_player(&fake, &catalog(), "TOKEN", &id, &refresh).await;
    let (_, after) = fake.counts();
    assert_eq!(after, before, "the match's lobby is its snapshot");
    assert_eq!(lobby_means(&ds), (Some(2000.0), Some(3200.0)));
}

#[tokio::test]
async fn the_cache_is_kept_per_queried_player() {
    let mem = std::sync::Arc::new(watch_core::MemoryCache::new());
    let cache: std::sync::Arc<dyn watch_core::StrengthCache> = mem;
    let fake = Counting::new();
    let plan = cached_plan(&cache);
    collect::collect_player(&fake, &catalog(), "TOKEN", &json!({"bnetId":"1001"}), &plan).await;
    let (info1, _) = fake.counts();
    // The same match as seen by another player has its sides the other way round.
    collect::collect_player(&fake, &catalog(), "TOKEN", &json!({"bnetId":"2001"}), &plan).await;
    let (info2, _) = fake.counts();
    assert_eq!(info2, info1 + 1);
}

#[tokio::test]
async fn a_single_role_pages_and_fetches_only_that_role() {
    struct RolePager {
        pages: Mutex<Vec<u64>>,
        infos: Mutex<usize>,
    }
    impl Fetcher for RolePager {
        async fn fetch(&self, endpoint: Endpoint, payload: Value) -> Result<Fetched, Failure> {
            let value = match endpoint {
                Endpoint::MatchList => {
                    let page = payload["page"].as_u64().unwrap();
                    self.pages.lock().unwrap().push(page);
                    let at = 1000 - page as i64 * 10;
                    json!({"code":0,"data":[
                        role_row(&format!("t{page}"), at, "tank"),
                        role_row(&format!("d{page}"), at - 1, "dps"),
                        role_row(&format!("s{page}"), at - 2, "healer"),
                    ]})
                }
                Endpoint::MatchInfo => {
                    *self.infos.lock().unwrap() += 1;
                    fixture("queryMatchInfo")
                }
                _ => json!({"code":0,"data":{}}),
            };
            Ok(Fetched {
                value,
                cached: false,
            })
        }
    }
    let fake = RolePager {
        pages: Mutex::new(Vec::new()),
        infos: Mutex::new(0),
    };
    let plan = CollectPlan {
        modes: vec![Mode::Quick],
        max_pages: 20,
        details_per_role: Some(3),
        roles: vec![Role::Tank],
        hero_board: false,
        ..CollectPlan::default()
    };
    assert!(plan.validate().is_ok());
    let ds =
        collect::collect_player(&fake, &catalog(), "TOKEN", &json!({"bnetId":"1001"}), &plan).await;
    assert_eq!(
        *fake.pages.lock().unwrap(),
        vec![1, 2, 3],
        "three tank matches are on three pages; the other roles do not extend the search"
    );
    assert_eq!(
        *fake.infos.lock().unwrap(),
        3,
        "only tank matches get a detail"
    );
    assert_eq!(ds.coverage.details_requested, 3);

    let bad = CollectPlan {
        roles: vec![Role::Open],
        ..plan
    };
    assert!(
        bad.validate().is_err(),
        "only the three playable roles can be chosen"
    );
}

#[test]
fn selection_can_be_limited_to_some_roles() {
    let cat = catalog();
    let rows = json!([
        role_row("s1", 20, "healer"),
        role_row("t1", 19, "tank"),
        role_row("d1", 18, "dps"),
        role_row("t2", 17, "tank"),
        role_row("s2", 16, "healer"),
    ]);
    let list = normalize::match_list(&rows, Mode::Quick, &cat);
    let ids = |picked: Vec<usize>| {
        picked
            .into_iter()
            .map(|i| list[i].id.clone())
            .collect::<Vec<_>>()
    };
    assert_eq!(
        ids(collect::select_per_role_for(&list, 5, &[Role::Tank])),
        ["t1", "t2"]
    );
    assert_eq!(
        ids(collect::select_per_role_for(
            &list,
            1,
            &[Role::Tank, Role::Support]
        )),
        ["s1", "t1"]
    );
    assert!(collect::role_quota_met_for(&list, 2, &[Role::Tank]));
    assert!(!collect::role_quota_met_for(
        &list,
        2,
        &[Role::Tank, Role::Damage]
    ));
}

#[tokio::test]
async fn known_matches_are_used_without_reading_the_list_again() {
    struct NoList {
        lists: Mutex<usize>,
        infos: Mutex<Vec<String>>,
    }
    impl Fetcher for NoList {
        async fn fetch(&self, endpoint: Endpoint, payload: Value) -> Result<Fetched, Failure> {
            let value = match endpoint {
                Endpoint::MatchList => {
                    *self.lists.lock().unwrap() += 1;
                    json!({"code":0,"data":[]})
                }
                Endpoint::MatchInfo => {
                    self.infos
                        .lock()
                        .unwrap()
                        .push(payload["matchId"].as_str().unwrap_or("").to_string());
                    fixture("queryMatchInfo")
                }
                _ => json!({"code":0,"data":{}}),
            };
            Ok(Fetched {
                value,
                cached: false,
            })
        }
    }
    let cat = catalog();
    let rows = json!([
        role_row("s1", 20, "healer"),
        role_row("t1", 19, "tank"),
        role_row("t2", 18, "tank"),
    ]);
    let known = normalize::match_list(&rows, Mode::Quick, &cat);
    let fake = NoList {
        lists: Mutex::new(0),
        infos: Mutex::new(Vec::new()),
    };
    let plan = CollectPlan {
        modes: vec![Mode::Quick],
        details_per_role: Some(5),
        roles: vec![Role::Tank],
        known_matches: known,
        hero_board: false,
        ..CollectPlan::default()
    };
    assert!(plan.validate().is_ok());
    let ds = collect::collect_player(&fake, &cat, "TOKEN", &json!({"bnetId":"1001"}), &plan).await;
    assert_eq!(*fake.lists.lock().unwrap(), 0, "the list is not read again");
    assert_eq!(
        *fake.infos.lock().unwrap(),
        ["s1", "t1", "t2"],
        "every row handed in gets its detail: the caller already chose them"
    );
    assert_eq!(ds.matches.len(), 3, "the rows handed in are the history");
}

// ---- the stored match list: only what is new is fetched -------------------------------------

/// An upstream history, newest first, ten matches a page; records every page asked for.
struct History {
    ids: Mutex<Vec<(String, &'static str)>>,
    pages: Mutex<Vec<u64>>,
    /// A list page that fails when asked for.
    fail_page: Mutex<Option<u64>>,
}

impl History {
    fn new(n: usize) -> Self {
        let h = History {
            ids: Mutex::new(Vec::new()),
            pages: Mutex::new(Vec::new()),
            fail_page: Mutex::new(None),
        };
        h.add_newer(n, "tank");
        h.pages.lock().unwrap().clear();
        h
    }
    /// `n` matches newer than everything so far.
    fn add_newer(&self, n: usize, role: &'static str) {
        let mut ids = self.ids.lock().unwrap();
        let next = ids.len();
        let mut fresh: Vec<_> = (next..next + n)
            .rev()
            .map(|i| (format!("m{i}"), role))
            .collect();
        fresh.append(&mut ids);
        *ids = fresh;
    }
    fn take_pages(&self) -> Vec<u64> {
        std::mem::take(&mut *self.pages.lock().unwrap())
    }
}

impl Fetcher for History {
    async fn fetch(&self, endpoint: Endpoint, payload: Value) -> Result<Fetched, Failure> {
        let value = match endpoint {
            Endpoint::MatchList => {
                let page = payload["page"].as_u64().unwrap();
                self.pages.lock().unwrap().push(page);
                if *self.fail_page.lock().unwrap() == Some(page) {
                    return Err(Failure {
                        kind: "upstream",
                        message: "down".into(),
                        retry_after_ms: None,
                    });
                }
                let ids = self.ids.lock().unwrap();
                let rows: Vec<Value> = ids
                    .iter()
                    .skip((page as usize - 1) * 10)
                    .take(10)
                    .map(|(id, role)| {
                        let n: i64 = id[1..].parse().unwrap();
                        role_row(id, 1000 + n, role)
                    })
                    .collect();
                json!({"code":0,"data":rows})
            }
            _ => json!({"code":0,"data":{}}),
        };
        Ok(Fetched {
            value,
            cached: false,
        })
    }
}

async fn sync(
    h: &History,
    cache: &watch_core::MemoryCache,
    max_pages: u32,
    quota: Option<(usize, &[Role])>,
) -> collect::MatchPages {
    let scope = collect::SyncScope {
        page: collect::PageScope {
            token: "T",
            mode: Mode::Quick,
            season: None,
            max_pages,
        },
        subject: "1001",
        quota,
    };
    collect::sync_match_list(h, &catalog(), cache, &scope, None).await
}

#[tokio::test]
async fn the_first_read_takes_everything_and_later_reads_only_what_is_new() {
    let h = History::new(25);
    let cache = watch_core::MemoryCache::new();

    let first = sync(&h, &cache, 20, None).await;
    assert_eq!(first.matches.len(), 25);
    assert!(first.coverage.exhausted);
    assert_eq!(
        h.take_pages(),
        vec![1, 2, 3, 4],
        "the empty page 4 proves the end"
    );

    let again = sync(&h, &cache, 20, None).await;
    assert_eq!(
        h.take_pages(),
        vec![1],
        "nothing new: one request to find out"
    );
    assert_eq!((again.matches.len(), again.coverage.new_matches), (25, 0));
    assert!(again.coverage.exhausted);

    h.add_newer(3, "damage");
    let three = sync(&h, &cache, 20, None).await;
    assert_eq!(
        h.take_pages(),
        vec![1],
        "three new matches fit on the first page"
    );
    assert_eq!((three.matches.len(), three.coverage.new_matches), (28, 3));
    assert_eq!(three.matches[0].id, "m27", "newest first");

    h.add_newer(12, "support");
    let twelve = sync(&h, &cache, 20, None).await;
    assert_eq!(h.take_pages(), vec![1, 2], "page 2 reaches the stored run");
    assert_eq!(
        (twelve.matches.len(), twelve.coverage.new_matches),
        (40, 12)
    );
    let ids: std::collections::HashSet<_> = twelve.matches.iter().map(|m| &m.id).collect();
    assert_eq!(ids.len(), 40, "no match twice");
}

#[tokio::test]
async fn a_page_budget_splits_a_long_read_and_the_next_call_resumes() {
    let h = History::new(45);
    let cache = watch_core::MemoryCache::new();
    let a = sync(&h, &cache, 2, None).await;
    assert_eq!(a.matches.len(), 20);
    assert!(!a.coverage.exhausted);
    assert_eq!(h.take_pages(), vec![1, 2]);

    // The next call checks page 1 for news, then carries on where the store ends.
    let b = sync(&h, &cache, 2, None).await;
    assert_eq!(h.take_pages(), vec![1, 3]);
    assert_eq!(b.matches.len(), 30);

    let mut last = b;
    let mut calls = 0;
    while !last.coverage.exhausted && calls < 10 {
        last = sync(&h, &cache, 2, None).await;
        calls += 1;
    }
    assert_eq!(last.matches.len(), 45);
    assert!(last.coverage.exhausted);
}

#[tokio::test]
async fn older_matches_are_read_only_until_the_quota_is_met() {
    let h = History::new(0);
    // Oldest to newest: 30 tank, then 6 support, then 4 damage.
    h.add_newer(30, "tank");
    h.add_newer(6, "healer");
    h.add_newer(4, "dps");
    let cache = watch_core::MemoryCache::new();
    let got = sync(&h, &cache, 20, Some((3, &[Role::Support]))).await;
    assert_eq!(
        h.take_pages(),
        vec![1],
        "the first page already holds 3 supports"
    );
    assert!(!got.coverage.exhausted);
    assert_eq!(got.matches.len(), 10);

    // A larger quota resumes from the store instead of starting over.
    let more = sync(&h, &cache, 20, Some((6, &[Role::Support]))).await;
    assert_eq!(
        h.take_pages(),
        vec![1],
        "6 supports are within the first 10 too"
    );
    assert_eq!(more.matches.len(), 10);
    let tanks = sync(&h, &cache, 20, Some((12, &[Role::Tank]))).await;
    assert_eq!(
        h.take_pages(),
        vec![1, 2, 3],
        "page 1 is the news check, then older pages"
    );
    assert!(
        tanks
            .matches
            .iter()
            .filter(|m| m.role == Role::Tank)
            .count()
            >= 12
    );
}

#[tokio::test]
async fn news_that_does_not_reach_the_stored_run_replaces_it() {
    let h = History::new(10);
    let cache = watch_core::MemoryCache::new();
    sync(&h, &cache, 20, None).await;
    h.take_pages();
    // 35 matches since: two pages cannot reach the stored ten.
    h.add_newer(35, "tank");
    let got = sync(&h, &cache, 2, None).await;
    assert_eq!(h.take_pages(), vec![1, 2]);
    assert_eq!(
        got.matches.len(),
        20,
        "only the new run; a gap is never stored"
    );
    assert!(!got.coverage.exhausted);
    let mut last = got;
    for _ in 0..6 {
        if last.coverage.exhausted {
            break;
        }
        last = sync(&h, &cache, 20, None).await;
    }
    assert_eq!(last.matches.len(), 45);
    let ids: std::collections::HashSet<_> = last.matches.iter().map(|m| &m.id).collect();
    assert_eq!(ids.len(), 45);
}

#[tokio::test]
async fn a_failed_page_never_costs_the_stored_list() {
    let h = History::new(25);
    let cache = watch_core::MemoryCache::new();
    sync(&h, &cache, 20, None).await;
    h.take_pages();
    // 15 matches since: they only join the stored run on page 2, which fails.
    h.add_newer(15, "tank");
    *h.fail_page.lock().unwrap() = Some(2);
    let broken = sync(&h, &cache, 20, None).await;
    assert!(broken.error.is_some());
    assert_eq!(broken.matches.len(), 25, "what was stored is still there");
    assert!(broken.coverage.exhausted, "and still known to be complete");
    // The next try, with the upstream back, picks the news up.
    *h.fail_page.lock().unwrap() = None;
    let fixed = sync(&h, &cache, 20, None).await;
    assert!(fixed.error.is_none());
    assert_eq!((fixed.matches.len(), fixed.coverage.new_matches), (40, 15));
}

#[tokio::test]
async fn rows_already_stored_are_refreshed_from_the_pages_read() {
    let h = History::new(25);
    let cache = watch_core::MemoryCache::new();
    sync(&h, &cache, 20, None).await;
    // The upstream later corrects the newest match (here its role).
    h.ids.lock().unwrap()[0].1 = "healer";
    let again = sync(&h, &cache, 20, None).await;
    assert_eq!(again.coverage.new_matches, 0);
    assert_eq!(again.matches[0].id, "m24");
    assert_eq!(again.matches[0].role, Role::Support);
    let key = watch_core::ListKey {
        subject: "1001",
        mode: Mode::Quick,
        season: None,
    };
    use watch_core::StrengthCache as _;
    assert_eq!(
        cache.match_list(key).rows[0].role,
        Role::Support,
        "and stored that way"
    );
}

// ---- a match is ready for analysis when everything it needs is stored ----------------------

fn fixture_detail(mode: Mode) -> MatchDetail {
    normalize::match_detail(
        "m3",
        normalize::payload(&fixture("queryMatchInfo")),
        mode,
        Some("1001"),
        &catalog(),
    )
}

#[test]
fn a_match_is_prepared_once_its_detail_and_every_lookup_are_stored() {
    use watch_core::StrengthCache as _;
    // Quick play: the detail carries no ranks, so every participant needs a lookup.
    let mut detail = fixture_detail(Mode::Quick);
    for p in detail.allies.iter_mut().chain(detail.enemies.iter_mut()) {
        p.rank = None;
    }
    let cache = watch_core::MemoryCache::new();
    assert!(!collect::match_prepared(
        &cache,
        Mode::Quick,
        "m3",
        "1001",
        25
    ));
    cache.put_detail("1001", &detail, &[]);
    assert!(
        !collect::match_prepared(&cache, Mode::Quick, "m3", "1001", 25),
        "the detail alone is not enough: nobody has been rated"
    );
    // Looked up and snapshotted, everyone: ready.
    let mut rated = 0;
    let mut looked_up = Vec::new();
    for p in detail.allies.iter().chain(&detail.enemies) {
        let (Some(id), true) = (p.bnet_id.as_deref(), p.role != Role::Unknown) else {
            continue;
        };
        looked_up.push(rating(id, p.role, 2000 + rated, None));
        rated += 100;
    }
    let by_id = looked_up.iter().map(|r| (r.bnet_id.as_str(), r)).collect();
    let mut snapped = detail.clone();
    watch_core::snapshot::take(&mut snapped, &by_id, 1);
    cache.put_detail("1001", &snapped, &[]);
    assert!(collect::match_prepared(
        &cache,
        Mode::Quick,
        "m3",
        "1001",
        25
    ));
    // A player the upstream gave no token for is not waited for.
    let cache2 = watch_core::MemoryCache::new();
    let everyone: Vec<String> = detail
        .allies
        .iter()
        .chain(&detail.enemies)
        .filter_map(|p| p.bnet_id.clone())
        .collect();
    cache2.put_detail("1001", &detail, &everyone);
    assert!(collect::match_prepared(
        &cache2,
        Mode::Quick,
        "m3",
        "1001",
        25
    ));
}

#[test]
fn a_rank_snapshot_is_taken_once_kept_when_the_match_is_stored_again_and_never_replaces_the_match_rank()
 {
    use watch_core::StrengthCache as _;
    let mut detail = fixture_detail(Mode::Quick);
    for p in detail.allies.iter_mut().chain(detail.enemies.iter_mut()) {
        p.rank = None;
    }
    let target = detail
        .allies
        .iter()
        .find(|p| p.bnet_id.is_some() && p.role != Role::Unknown)
        .unwrap()
        .clone();
    let id = target.bnet_id.clone().unwrap();
    let got = |d: &MatchDetail| {
        d.allies
            .iter()
            .find(|p| p.bnet_id.as_deref() == Some(&id))
            .unwrap()
            .clone()
    };
    assert!(watch_core::snapshot::missing(&detail, &[]));
    // Looked up at 2100: the snapshot says 2100 and when it was taken.
    let first = rating(&id, target.role, 2100, None);
    let by_id = std::iter::once((id.as_str(), &first)).collect();
    let mut snapped = detail.clone();
    assert!(watch_core::snapshot::take(&mut snapped, &by_id, 1_000));
    let p = got(&snapped);
    assert_eq!(p.career_rank.and_then(|r| r.skill_rating), Some(2100));
    assert_eq!(p.career_rank_at_ms, Some(1_000));
    // A later lookup at 2600 does not move it: it is this match's lobby.
    let later = rating(&id, target.role, 2600, None);
    let by_id = std::iter::once((id.as_str(), &later)).collect();
    watch_core::snapshot::take(&mut snapped, &by_id, 2_000);
    assert_eq!(
        got(&snapped).career_rank.and_then(|r| r.skill_rating),
        Some(2100)
    );
    // The match read in again (no snapshots in it) keeps the stored one.
    let cache = watch_core::MemoryCache::new();
    cache.put_detail("1001", &snapped, &[]);
    cache.put_detail("1001", &detail, &[]);
    let kept = cache
        .detail(Mode::Quick, &detail.id, "1001")
        .unwrap()
        .detail;
    assert_eq!(
        got(&kept).career_rank.and_then(|r| r.skill_rating),
        Some(2100)
    );
    assert_eq!(got(&kept).career_rank_at_ms, Some(1_000));
    // Looked up and unranked is a snapshot too.
    let none = PlayerRating {
        bnet_id: id.clone(),
        name: None,
        roles: Vec::new(),
    };
    let by_id = std::iter::once((id.as_str(), &none)).collect();
    let mut unranked = detail.clone();
    watch_core::snapshot::take(&mut unranked, &by_id, 3_000);
    assert!(got(&unranked).career_rank.is_none());
    assert_eq!(got(&unranked).career_rank_at_ms, Some(3_000));
    // A rank the match itself reported needs no snapshot and gets none.
    let mut with_rank = detail.clone();
    for p in with_rank.allies.iter_mut() {
        if p.bnet_id.as_deref() == Some(&id) {
            p.rank = Some(Rank {
                tier: None,
                division: None,
                score: None,
                skill_rating: Some(3000),
                at_ms: None,
            });
        }
    }
    let by_id = std::iter::once((id.as_str(), &first)).collect();
    watch_core::snapshot::take(&mut with_rank, &by_id, 4_000);
    assert!(got(&with_rank).career_rank_at_ms.is_none());
}

#[test]
fn a_rating_prefers_the_role_played_then_the_best_other_role_this_season_then_earlier() {
    let mk = |roles: Vec<(Role, i64, Option<u32>)>| PlayerRating {
        bnet_id: "1".into(),
        name: None,
        roles: roles
            .into_iter()
            .map(|(role, sr, season)| rating("1", role, sr, season).roles[0].clone())
            .collect(),
    };
    // The role played wins over everything else.
    let p = mk(vec![(Role::Damage, 2000, None), (Role::Tank, 3000, None)]);
    assert_eq!(
        p.rating_for(Role::Damage),
        Some((2000.0, RatingFit::SameRole))
    );
    // No rank for it: the highest of the others this season, earlier seasons ignored.
    let p = mk(vec![
        (Role::Tank, 1500, None),
        (Role::Support, 2500, None),
        (Role::Tank, 900, Some(24)),
    ]);
    assert_eq!(
        p.rating_for(Role::Damage),
        Some((2500.0, RatingFit::OtherRoles))
    );
    // Only earlier seasons have anything: those.
    let p = mk(vec![(Role::Tank, 1800, Some(24))]);
    assert_eq!(
        p.rating_for(Role::Support),
        Some((1800.0, RatingFit::OtherRoles))
    );
    // Ranked in nothing, or a role that is not known: no rating.
    assert_eq!(mk(vec![]).rating_for(Role::Tank), None);
    assert_eq!(p.rating_for(Role::Unknown), None);
}

#[tokio::test]
async fn a_match_limit_keeps_the_newest_matches_of_each_mode() {
    let h = History::new(25);
    let cache: std::sync::Arc<dyn watch_core::StrengthCache> =
        std::sync::Arc::new(watch_core::MemoryCache::new());
    let plan = CollectPlan {
        modes: vec![Mode::Quick],
        max_pages: 10,
        max_details: 0,
        hero_board: false,
        match_limit: Some(7),
        cache: Some(cache.clone()),
        ..CollectPlan::default()
    };
    let ds = collect::collect_player(&h, &catalog(), "T", &json!({"bnetId":"1001"}), &plan).await;
    let ids: Vec<&str> = ds.matches.iter().map(|m| m.id.as_str()).collect();
    assert_eq!(ids, ["m24", "m23", "m22", "m21", "m20", "m19", "m18"]);
    // Everything is still kept locally; the limit only shapes the dataset.
    let all = collect::collect_player(
        &h,
        &catalog(),
        "T",
        &json!({"bnetId":"1001"}),
        &CollectPlan {
            match_limit: None,
            ..plan.clone()
        },
    )
    .await;
    assert_eq!(all.matches.len(), 25);
    assert!(
        CollectPlan {
            match_limit: Some(0),
            ..CollectPlan::default()
        }
        .validate()
        .is_err()
    );
}

#[test]
fn fleta_is_a_players_share_of_half_their_teams_final_blows() {
    let mut d = fixture_detail(Mode::Competitive);
    // The fixture's teams are short: make them five.
    d.allies = vec![d.allies[0].clone(); 5];
    d.enemies = vec![d.enemies[0].clone(); 5];
    let finals = [6.0, 2.0, 2.0, 0.0, 0.0];
    for (p, f) in d.allies.iter_mut().zip(finals) {
        p.stats.final_blows = Some(f);
    }
    d.allies[3].stats.final_blows = None; // unknown stays unknown
    for p in d.enemies.iter_mut() {
        p.stats.final_blows = Some(0.0);
    }
    analysis::attach_fleta(&mut d);
    // The team made 10 final blows: half is 5, so 6 is 120% and 2 is 40%.
    assert_eq!(d.allies[0].fleta, Some(120.0));
    assert_eq!(d.allies[1].fleta, Some(40.0));
    assert_eq!(d.allies[3].fleta, None);
    assert_eq!(d.allies[4].fleta, Some(0.0));
    // A team with no final blows has no index to give.
    assert!(d.enemies.iter().all(|p| p.fleta.is_none()));
}

#[tokio::test]
async fn once_ranks_expire_a_snapshotted_match_still_asks_nothing() {
    struct Counter(Mutex<Vec<Option<u64>>>);
    impl Fetcher for Counter {
        async fn fetch(&self, endpoint: Endpoint, payload: Value) -> Result<Fetched, Failure> {
            let value = match endpoint {
                Endpoint::MatchList if payload["gameMode"] == "leisure" => {
                    json!({"code":0,"data":[{"matchId":"q1","matchRet":1,"beginTs":5,"gameMode":"LeisurePreset"}]})
                }
                Endpoint::MatchInfo => fixture("queryMatchInfo"),
                Endpoint::CareerCount if payload["token"] != "TOKEN" => {
                    self.0.lock().unwrap().push(payload["season"].as_u64());
                    // Nobody has a rank: every player needs the previous season too.
                    json!({"code":0,"data":{"guideCountData":[]}})
                }
                _ => json!({"code":0,"data":[]}),
            };
            Ok(Fetched {
                value,
                cached: false,
            })
        }
    }
    let fake = Counter(Mutex::new(Vec::new()));
    let cache: std::sync::Arc<dyn watch_core::StrengthCache> = std::sync::Arc::new(
        watch_core::MemoryCache::new().with_ratings_ttl(std::time::Duration::from_millis(1)),
    );
    let plan = CollectPlan {
        modes: vec![Mode::Quick],
        lobby_ratings: true,
        hero_board: false,
        cache: Some(cache),
        ..CollectPlan::default()
    };
    let cat = catalog();
    let identity = json!({"bnetId":"1001"});
    let run = || collect::collect_player(&fake, &cat, "TOKEN", &identity, &plan);
    run().await;
    let first = std::mem::take(&mut *fake.0.lock().unwrap());
    assert!(
        first.contains(&None) && first.contains(&Some(24)),
        "the first run needs both"
    );
    // Past the lifetime of the current season's ranks.
    std::thread::sleep(std::time::Duration::from_millis(20));
    run().await;
    let second = fake.0.lock().unwrap().clone();
    assert!(second.is_empty(), "the snapshots answer: {second:?}");
}

#[tokio::test]
async fn without_the_profile_no_card_or_career_is_requested() {
    let fake = FakeDashen {
        calls: Mutex::new(Vec::new()),
        fail: None,
    };
    let plan = CollectPlan {
        modes: vec![Mode::Quick],
        profile: false,
        max_details: 0,
        hero_board: false,
        ..CollectPlan::default()
    };
    let ds =
        collect::collect_player(&fake, &catalog(), "TOKEN", &json!({"bnetId":"1001"}), &plan).await;
    let calls: Vec<Endpoint> = fake.calls.lock().unwrap().iter().map(|c| c.0).collect();
    assert!(!calls.contains(&Endpoint::Card) && !calls.contains(&Endpoint::CareerCount));
    assert!(
        calls.contains(&Endpoint::MatchList),
        "the list is still read"
    );
    assert!(ds.careers.is_empty());
    assert_eq!(
        ds.profile.bnet_id.as_deref(),
        Some("1001"),
        "the identity is enough for who it is"
    );
}
