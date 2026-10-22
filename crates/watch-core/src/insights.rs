//! Findings (洞察): what changed and why, said only when the evidence is firm.
//!
//! Each rule looks at one kind of thing and either finds something clear or says nothing;
//! a finding states its numbers and sample, so the app can word it and show what it rests
//! on, and carries what to open to see it (a map, a hero). Nothing here is a model or a
//! guess: every rule is a plain comparison with a fixed bar (docs/algorithms.md §7.4).
//!
//! The rules, in the order they are shown:
//!  - a streak of three or more, and for a losing one, how many of those matches had a
//!    clearly stronger enemy team (lobby strength);
//!  - the recent rate against the one before, and which maps and heroes moved it;
//!  - a map, a hero whose whole plausible rate is above or below the player's;
//!  - later matches of a sitting going worse than its first three;
//!  - on the most-played hero, a measure clearly below or above peers (benchmarks).
use crate::analysis::{Aggregate, Group, Session};
use crate::benchmark::{BenchMetric, HeroBench};
use crate::ir::*;
use crate::stats::two_proportion_p;
use crate::strength::LobbyStrength;
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, HashMap};

/// Most findings shown at once.
pub const MAX_FINDINGS: usize = 5;
/// A streak is said from this length.
pub const MIN_STREAK: usize = 3;
/// The recent rate is said to have moved when it differs by this many points (with at
/// least [`MIN_DECIDED`] decided matches on each side).
pub const MIN_SWING_POINTS: f64 = 15.0;
pub const MIN_DECIDED: usize = 10;
/// An enemy team is "clearly stronger" when its mean rating is this much higher (two
/// divisions).
pub const STRONGER_BY: f64 = 200.0;
/// A sitting's matches from this one on count as "later".
pub const LATE_FROM: usize = 3;
/// p below which a difference between two rates is said.
pub const FINDING_P: f64 = 0.10;
/// A peer percentile below this (or above 100 minus it) is said.
pub const PEER_EDGE: f64 = 25.0;

/// What a finding is about; the app words it (each kind is one sentence in its table).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum InsightKind {
    /// `n` matches won (positive) or lost (negative) in a row, up to now.
    Streak,
    /// Of the `n` matches of a losing streak, `value` had an enemy team rated at least
    /// [`STRONGER_BY`] higher.
    StreakStrength,
    /// The recent win rate (`value`) against the one before (`other`), over `n` matches.
    RecentForm,
    /// What moved the recent rate: `items` are maps and heroes with the change in their
    /// wins minus losses between the two stretches.
    Drivers,
    /// A map (`subject`) clearly better or worse than the player's rate (`other`): its
    /// whole plausible range is on one side. `value` is its rate over `n` matches.
    Map,
    /// The same for a hero.
    Hero,
    /// In sittings of four or more, the matches from the fourth on (`value`, over `n`)
    /// against the first three (`other`); `p` is the test of the difference.
    Fatigue,
    /// On the most-played hero (`subject`), a measure (`metric`) at percentile `value`
    /// among peers.
    HeroMetric,
}

/// One thing a finding lists (a map or hero that moved the rate).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct InsightItem {
    pub label: String,
    /// Stable id of the hero or map, for drilling down.
    pub key: String,
    /// `entity` kind: `hero` or `map`.
    pub kind: String,
    /// Change in wins minus losses, newer stretch against older.
    pub delta: i64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Insight {
    pub kind: InsightKind,
    /// Good news (true), bad news (false).
    pub positive: bool,
    pub subject: Option<String>,
    pub value: f64,
    pub other: Option<f64>,
    pub n: usize,
    /// For drill-down: the group's key (a hero or map stable id).
    pub key: Option<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub items: Vec<InsightItem>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub p: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub metric: Option<BenchMetric>,
}

impl Insight {
    fn new(kind: InsightKind, positive: bool, value: f64, n: usize) -> Self {
        Self {
            kind,
            positive,
            subject: None,
            value,
            other: None,
            n,
            key: None,
            items: Vec::new(),
            p: None,
            metric: None,
        }
    }
}

/// What the findings may draw on beyond the match list: the lobby strength of stored
/// details and the peer benchmarks, when the caller has them.
#[derive(Default)]
pub struct Context<'a> {
    pub strength: Option<&'a LobbyStrength>,
    pub benchmarks: &'a [HeroBench],
}

/// The overview's figures the rules read.
pub struct Facts<'a> {
    pub overall: &'a Aggregate,
    /// Newest first.
    pub recent: &'a [&'a MatchSummary],
    pub before: &'a [&'a MatchSummary],
    pub recent_agg: &'a Aggregate,
    pub before_agg: &'a Aggregate,
    pub by_map: &'a [Group],
    pub by_hero: &'a [Group],
    pub sessions: &'a [Session],
    pub rows: &'a [MatchSummary],
    pub context: &'a Context<'a>,
}

pub fn find(f: &Facts<'_>) -> Vec<Insight> {
    let mut out = Vec::new();
    out.extend(streak(f));
    out.extend(streak_strength(f));
    let form = recent_form(f);
    if let Some(form) = &form {
        out.push(form.clone());
        out.extend(drivers(f, form.positive));
    }
    if let Some(rate) = f.overall.record.win_rate_pct {
        for (kind, groups) in [(InsightKind::Map, f.by_map), (InsightKind::Hero, f.by_hero)] {
            if let Some((g, up)) = clear_outliers(groups, rate).first() {
                let mut i = Insight::new(
                    kind,
                    *up,
                    g.aggregate.record.win_rate_pct.unwrap_or_default(),
                    g.aggregate.record.matches,
                );
                i.subject = g.label.clone();
                i.other = Some(rate);
                i.key = Some(g.key.clone());
                out.push(i);
            }
        }
    }
    out.extend(fatigue(f));
    out.extend(hero_metric(f));
    out.truncate(MAX_FINDINGS);
    out
}

fn streak(f: &Facts<'_>) -> Option<Insight> {
    let s = f.overall.streaks.current;
    let n = s.unsigned_abs() as usize;
    (n >= MIN_STREAK).then(|| Insight::new(InsightKind::Streak, s > 0, n as f64, n))
}

/// For a losing streak: how many of its matches (with a stored detail rated for strength)
/// had a clearly stronger enemy.
fn streak_strength(f: &Facts<'_>) -> Option<Insight> {
    let s = f.overall.streaks.current;
    if s > -(MIN_STREAK as i64) {
        return None;
    }
    let strength = f.context.strength?;
    let by_id: HashMap<&str, _> = strength
        .matches
        .iter()
        .map(|m| (m.match_id.as_str(), m))
        .collect();
    let streak_ids: Vec<&str> = f
        .recent
        .iter()
        .take(s.unsigned_abs() as usize)
        .map(|m| m.id.as_str())
        .collect();
    let rated: Vec<f64> = streak_ids
        .iter()
        .filter_map(|id| by_id.get(id)?.diff.overall)
        .collect();
    let stronger = rated.iter().filter(|d| -**d >= STRONGER_BY).count();
    // Said only when it explains most of the streak.
    (rated.len() >= MIN_STREAK && stronger * 2 > rated.len()).then(|| {
        let mut i = Insight::new(
            InsightKind::StreakStrength,
            false,
            stronger as f64,
            rated.len(),
        );
        i.other = Some(STRONGER_BY);
        i
    })
}

fn recent_form(f: &Facts<'_>) -> Option<Insight> {
    let (now, then) = (
        f.recent_agg.record.win_rate_pct?,
        f.before_agg.record.win_rate_pct?,
    );
    let n = f.recent_agg.record.wins + f.recent_agg.record.losses;
    let m = f.before_agg.record.wins + f.before_agg.record.losses;
    (n >= MIN_DECIDED && m >= MIN_DECIDED && (now - then).abs() >= MIN_SWING_POINTS).then(|| {
        let mut i = Insight::new(InsightKind::RecentForm, now > then, now, n);
        i.other = Some(then);
        i
    })
}

fn net(
    rows: &[&MatchSummary],
    pick: impl Fn(&MatchSummary) -> Option<&EntityRef>,
) -> BTreeMap<String, (String, i64)> {
    let mut out: BTreeMap<String, (String, i64)> = BTreeMap::new();
    for m in rows {
        let Some(e) = pick(m) else { continue };
        let d = match m.outcome {
            Outcome::Win => 1,
            Outcome::Loss => -1,
            _ => continue,
        };
        let entry = out
            .entry(e.stable_id())
            .or_insert_with(|| (e.name.clone().unwrap_or_default(), 0));
        entry.1 += d;
    }
    out
}

/// The two maps or heroes whose wins minus losses moved most the way the rate moved.
fn drivers(f: &Facts<'_>, up: bool) -> Option<Insight> {
    let mut items: Vec<InsightItem> = Vec::new();
    for (kind, pick) in [
        (
            "map",
            (|m: &MatchSummary| m.map.as_ref()) as fn(&MatchSummary) -> Option<&EntityRef>,
        ),
        ("hero", |m: &MatchSummary| m.hero.as_ref()),
    ] {
        let now = net(f.recent, pick);
        let then = net(f.before, pick);
        let keys: std::collections::BTreeSet<&String> = now.keys().chain(then.keys()).collect();
        for k in keys {
            let a = now.get(k).map_or(0, |v| v.1);
            let b = then.get(k).map_or(0, |v| v.1);
            let label = now
                .get(k)
                .or(then.get(k))
                .map(|v| v.0.clone())
                .unwrap_or_default();
            if label.is_empty() {
                continue;
            }
            items.push(InsightItem {
                label,
                key: k.clone(),
                kind: kind.into(),
                delta: a - b,
            });
        }
    }
    items.retain(|i| if up { i.delta >= 2 } else { i.delta <= -2 });
    items.sort_by_key(|i| if up { -i.delta } else { i.delta });
    items.truncate(2);
    (!items.is_empty()).then(|| {
        let mut i = Insight::new(InsightKind::Drivers, up, 0.0, f.recent.len());
        i.items = items;
        i
    })
}

/// Groups whose whole plausible range lies above or below `rate` (both with enough
/// matches), best evidence first.
fn clear_outliers(groups: &[Group], rate: f64) -> Vec<(&Group, bool)> {
    let mut found: Vec<(&Group, bool, f64)> = groups
        .iter()
        .filter(|g| g.aggregate.record.enough && g.key != "unknown")
        .filter_map(|g| {
            let r = &g.aggregate.record;
            let (lo, hi) = (r.win_rate_low_pct?, r.win_rate_high_pct?);
            if lo > rate {
                Some((g, true, lo - rate))
            } else if hi < rate {
                Some((g, false, rate - hi))
            } else {
                None
            }
        })
        .collect();
    found.sort_by(|a, b| b.2.total_cmp(&a.2));
    found.into_iter().map(|(g, up, _)| (g, up)).collect()
}

/// Later matches of a sitting against its first [`LATE_FROM`], over every sitting long
/// enough to have later ones.
fn fatigue(f: &Facts<'_>) -> Option<Insight> {
    let outcome: HashMap<&str, Outcome> =
        f.rows.iter().map(|m| (m.id.as_str(), m.outcome)).collect();
    let (mut early, mut late) = ((0, 0), (0, 0)); // (wins, decided)
    for s in f.sessions.iter().filter(|s| s.match_ids.len() > LATE_FROM) {
        for (i, id) in s.match_ids.iter().enumerate() {
            let side = if i < LATE_FROM { &mut early } else { &mut late };
            match outcome.get(id.as_str()) {
                Some(Outcome::Win) => {
                    side.0 += 1;
                    side.1 += 1;
                }
                Some(Outcome::Loss) => side.1 += 1,
                _ => {}
            }
        }
    }
    if early.1 < MIN_DECIDED || late.1 < MIN_DECIDED {
        return None;
    }
    let p = two_proportion_p(late.0, late.1, early.0, early.1)?;
    let (late_rate, early_rate) = (
        100.0 * late.0 as f64 / late.1 as f64,
        100.0 * early.0 as f64 / early.1 as f64,
    );
    // Only the useful direction is said: tiring later on.
    (p < FINDING_P && late_rate < early_rate).then(|| {
        let mut i = Insight::new(InsightKind::Fatigue, false, late_rate, late.1);
        i.other = Some(early_rate);
        i.p = Some(p);
        i
    })
}

/// On the most-played benchmarked hero: its weakest measure if clearly low, else its
/// strongest if clearly high.
fn hero_metric(f: &Facts<'_>) -> Option<Insight> {
    let hero = f.context.benchmarks.first()?;
    let weakest = hero
        .metrics
        .iter()
        .min_by(|a, b| a.percentile.total_cmp(&b.percentile))?;
    let strongest = hero
        .metrics
        .iter()
        .max_by(|a, b| a.percentile.total_cmp(&b.percentile))?;
    let (m, positive) = if weakest.percentile < PEER_EDGE {
        (weakest, false)
    } else if strongest.percentile > 100.0 - PEER_EDGE {
        (strongest, true)
    } else {
        return None;
    };
    let mut i = Insight::new(
        InsightKind::HeroMetric,
        positive,
        m.percentile,
        hero.matches,
    );
    i.subject = hero.hero.name.clone();
    i.key = Some(hero.hero.stable_id());
    i.metric = Some(m.metric);
    i.other = Some(m.peer_median);
    Some(i)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::analysis::{Clock, overview};
    use crate::benchmark::{Band, MetricBench, PeerGroup};

    const HOUR: i64 = 3_600_000;

    fn row(id: &str, at: i64, outcome: Outcome, map: &str, hero: &str) -> MatchSummary {
        MatchSummary {
            id: id.into(),
            started_at_ms: Some(at),
            kind: MatchKind {
                mode: Mode::Competitive,
                queue: Queue::RoleQueue,
                ranked: None,
                provider_mode: None,
                instance_type: None,
            },
            outcome,
            map: Some(EntityRef::new(
                EntityKind::Map,
                map,
                Some(format!("地图{map}")),
            )),
            hero: Some(EntityRef::new(
                EntityKind::Hero,
                hero,
                Some(format!("英雄{hero}")),
            )),
            role: Role::Support,
            score: Score::default(),
            stats: StatLine::default(),
            highlights: None,
            rank: None,
            hero_icon_url: None,
        }
    }

    fn clock() -> Clock {
        Clock {
            now_ms: 0,
            utc_offset_minutes: 8 * 60,
        }
    }

    fn kinds(rows: &[MatchSummary], ctx: &Context<'_>) -> Vec<Insight> {
        overview(rows, clock(), 2 * HOUR, ctx).insights
    }

    #[test]
    fn later_matches_of_a_sitting_going_worse_is_said() {
        // Five sittings a day apart: three wins, then three losses each time.
        let mut rows = Vec::new();
        for s in 0..5 {
            for k in 0..6 {
                let o = if k < 3 { Outcome::Win } else { Outcome::Loss };
                rows.push(row(
                    &format!("{s}-{k}"),
                    s * 24 * HOUR + k * HOUR / 2,
                    o,
                    "1",
                    "1",
                ));
            }
        }
        let found = kinds(&rows, &Context::default());
        let f = found
            .iter()
            .find(|i| i.kind == InsightKind::Fatigue)
            .unwrap();
        assert_eq!(f.value, 0.0);
        assert_eq!(f.other, Some(100.0));
        assert!(f.p.unwrap() < 0.001);
        assert_eq!(f.n, 15);
    }

    #[test]
    fn the_same_rate_early_and_late_says_nothing_about_fatigue() {
        let mut rows = Vec::new();
        for s in 0..10 {
            for k in 0..6 {
                // Two wins of three in the first three and in the last three.
                let o = if [0, 1, 3, 4].contains(&k) {
                    Outcome::Win
                } else {
                    Outcome::Loss
                };
                rows.push(row(
                    &format!("{s}-{k}"),
                    s * 24 * HOUR + k * HOUR / 2,
                    o,
                    "1",
                    "1",
                ));
            }
        }
        assert!(
            !kinds(&rows, &Context::default())
                .iter()
                .any(|i| i.kind == InsightKind::Fatigue)
        );
    }

    #[test]
    fn a_falling_rate_names_what_moved_it() {
        let mut rows = Vec::new();
        // Before: 20 matches, map 1 always won, map 2 split.
        for k in 0..20 {
            let (map, o) = if k < 10 {
                ("1", Outcome::Win)
            } else {
                (
                    "2",
                    if k % 2 == 0 {
                        Outcome::Win
                    } else {
                        Outcome::Loss
                    },
                )
            };
            rows.push(row(&format!("b{k}"), k * 24 * HOUR, o, map, "1"));
        }
        // Recent: map 1 always lost now, map 2 the same as before.
        for k in 0..20 {
            let (map, o) = if k < 10 {
                ("1", Outcome::Loss)
            } else {
                (
                    "2",
                    if k % 2 == 0 {
                        Outcome::Win
                    } else {
                        Outcome::Loss
                    },
                )
            };
            rows.push(row(&format!("r{k}"), (100 + k) * 24 * HOUR, o, map, "1"));
        }
        let found = kinds(&rows, &Context::default());
        let form = found
            .iter()
            .find(|i| i.kind == InsightKind::RecentForm)
            .unwrap();
        assert!(!form.positive);
        let d = found
            .iter()
            .find(|i| i.kind == InsightKind::Drivers)
            .unwrap();
        assert_eq!(d.items[0].label, "地图1");
        assert_eq!(d.items[0].delta, -20);
        assert_eq!(d.items[0].kind, "map");
        assert!(d.items.len() <= 2);
    }

    fn rated(id: &str, sr: i64) -> Participant {
        Participant {
            name: None,
            bnet_id: Some(id.into()),
            is_subject: false,
            hero: None,
            hero_icon_url: None,
            role: Role::Support,
            stats: StatLine::default(),
            rank: Some(Rank {
                tier: None,
                division: None,
                score: None,
                skill_rating: Some(sr),
                at_ms: None,
            }),
            career_rank: None,
            career_other_roles: false,
            fleta: None,
            perks: Vec::new(),
            party_bnet_ids: Vec::new(),
            endorsed_by_bnet_ids: Vec::new(),
            suspended: false,
            stadium: None,
        }
    }

    #[test]
    fn a_losing_streak_against_stronger_teams_is_explained() {
        let rows: Vec<MatchSummary> = (0..3)
            .map(|k| row(&format!("m{k}"), k * HOUR, Outcome::Loss, "1", "1"))
            .collect();
        let details: BTreeMap<String, MatchDetail> = rows
            .iter()
            .map(|m| {
                (
                    m.id.clone(),
                    MatchDetail {
                        id: m.id.clone(),
                        mode: Mode::Competitive,
                        map: None,
                        outcome: Outcome::Loss,
                        outcome_source: OutcomeSource::Provider,
                        started_at_ms: m.started_at_ms,
                        duration_s: Some(600.0),
                        score: Score::default(),
                        bans: Bans::default(),
                        subject_heroes: Vec::new(),
                        allies: vec![rated("a", 2000)],
                        enemies: vec![rated("e", 2300)],
                        rounds: Vec::new(),
                    },
                )
            })
            .collect();
        let strength = crate::strength::lobby_strength(&details, &[]);
        let ctx = Context {
            strength: Some(&strength),
            benchmarks: &[],
        };
        let found = kinds(&rows, &ctx);
        let s = found
            .iter()
            .find(|i| i.kind == InsightKind::StreakStrength)
            .unwrap();
        assert_eq!((s.value, s.n), (3.0, 3));
        // Without strength data, only the streak itself.
        assert!(
            !kinds(&rows, &Context::default())
                .iter()
                .any(|i| i.kind == InsightKind::StreakStrength)
        );
    }

    #[test]
    fn the_main_hero_clear_weakness_among_peers_is_said() {
        let metric = |m, p| MetricBench {
            metric: m,
            value: 1.0,
            peer_median: 1.0,
            percentile: p,
            band: Band::of(p),
            peers: PeerGroup {
                tiers: Vec::new(),
                matches: 90,
            },
        };
        let benches = [HeroBench {
            hero: EntityRef::new(EntityKind::Hero, "1", Some("雾子".into())),
            role: Role::Support,
            matches: 40,
            tier: None,
            metrics: vec![
                metric(BenchMetric::Healing, 10.0),
                metric(BenchMetric::Damage, 55.0),
            ],
        }];
        let ctx = Context {
            strength: None,
            benchmarks: &benches,
        };
        let rows = [row("m", 0, Outcome::Win, "1", "1")];
        let found = kinds(&rows, &ctx);
        let h = found
            .iter()
            .find(|i| i.kind == InsightKind::HeroMetric)
            .unwrap();
        assert!(!h.positive);
        assert_eq!(h.metric, Some(BenchMetric::Healing));
        assert_eq!(h.subject.as_deref(), Some("雾子"));
    }
}
