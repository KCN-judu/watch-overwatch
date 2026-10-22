//! Pure analysis over the IR: no I/O and no provider knowledge, so it runs the
//! same on a live collection or a dataset loaded from disk.
//!
//! Missing values are skipped, never counted as zero: every mean divides by the
//! number of matches that actually supplied that stat. Win rate excludes draws
//! and unknown results (`wins / (wins + losses)`).
use crate::ir::*;
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, HashMap};

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct Record {
    pub matches: usize,
    pub wins: usize,
    pub losses: usize,
    pub draws: usize,
    pub unknown: usize,
    pub win_rate_pct: Option<f64>,
    /// The plausible range of the win rate (Wilson, 95 %; see [`crate::stats`]). Rank by
    /// `win_rate_low_pct`, not by the bare rate.
    #[serde(default)]
    pub win_rate_low_pct: Option<f64>,
    #[serde(default)]
    pub win_rate_high_pct: Option<f64>,
    /// Enough decided matches to compare ([`crate::stats::MIN_GROUP_MATCHES`]).
    #[serde(default)]
    pub enough: bool,
}

impl Record {
    pub fn add(&mut self, outcome: Outcome) {
        self.matches += 1;
        match outcome {
            Outcome::Win => self.wins += 1,
            Outcome::Loss => self.losses += 1,
            Outcome::Draw => self.draws += 1,
            Outcome::Unknown => self.unknown += 1,
        }
        let decided = self.wins + self.losses;
        self.win_rate_pct = (decided > 0).then(|| 100.0 * self.wins as f64 / decided as f64);
        let range = crate::stats::wilson_pct(self.wins, decided);
        self.win_rate_low_pct = range.map(|r| r.0);
        self.win_rate_high_pct = range.map(|r| r.1);
        self.enough = decided >= crate::stats::MIN_GROUP_MATCHES;
    }
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct Streaks {
    pub best_win: usize,
    pub best_loss: usize,
    /// Positive: current win streak; negative: current loss streak.
    pub current: i64,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct Aggregate {
    pub record: Record,
    /// Sums over matches that supplied each stat.
    pub totals: StatLine,
    /// Means over matches that supplied each stat.
    pub per_match: StatLine,
    /// Matches that supplied each stat, so means can be judged.
    pub samples: BTreeMap<String, usize>,
    /// `(kills + assists) / deaths`, over matches supplying all three; `None` at zero deaths.
    pub kda: Option<f64>,
    pub streaks: Streaks,
    pub first_ms: Option<i64>,
    pub last_ms: Option<i64>,
}

/// Sum, mean and sample count per stat field.
fn stat_means<'a>(
    lines: impl Iterator<Item = &'a StatLine>,
) -> (StatLine, StatLine, BTreeMap<String, usize>) {
    let mut sums = [0.0f64; StatLine::FIELDS.len()];
    let mut counts = [0usize; StatLine::FIELDS.len()];
    for line in lines {
        for (i, field) in StatLine::FIELDS.iter().enumerate() {
            if let Some(v) = line.get(field) {
                sums[i] += v;
                counts[i] += 1;
            }
        }
    }
    let (mut totals, mut means, mut samples) =
        (StatLine::default(), StatLine::default(), BTreeMap::new());
    for (i, field) in StatLine::FIELDS.iter().enumerate() {
        if counts[i] > 0 {
            totals.set(field, Some(sums[i]));
            means.set(field, Some(sums[i] / counts[i] as f64));
            samples.insert(field.to_string(), counts[i]);
        }
    }
    (totals, means, samples)
}

pub fn aggregate<'a>(rows: impl IntoIterator<Item = &'a MatchSummary>) -> Aggregate {
    let mut rows: Vec<&MatchSummary> = rows.into_iter().collect();
    // Chronological order for streaks; untimed rows keep their relative order.
    rows.sort_by_key(|m| m.started_at_ms.unwrap_or(i64::MIN));
    let mut record = Record::default();
    let mut streaks = Streaks::default();
    let (mut win_run, mut loss_run) = (0usize, 0usize);
    let (mut k, mut a, mut d) = (0.0, 0.0, 0.0);
    for m in &rows {
        record.add(m.outcome);
        win_run = if m.outcome == Outcome::Win {
            win_run + 1
        } else {
            0
        };
        loss_run = if m.outcome == Outcome::Loss {
            loss_run + 1
        } else {
            0
        };
        streaks.best_win = streaks.best_win.max(win_run);
        streaks.best_loss = streaks.best_loss.max(loss_run);
        if let (Some(mk), Some(ma), Some(md)) = (m.stats.kills, m.stats.assists, m.stats.deaths) {
            k += mk;
            a += ma;
            d += md;
        }
    }
    streaks.current = win_run as i64 - loss_run as i64;
    let (totals, per_match, samples) = stat_means(rows.iter().map(|m| &m.stats));
    Aggregate {
        record,
        totals,
        per_match,
        samples,
        kda: (d > 0.0).then(|| (k + a) / d),
        streaks,
        first_ms: rows.iter().filter_map(|m| m.started_at_ms).min(),
        last_ms: rows.iter().filter_map(|m| m.started_at_ms).max(),
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Dimension {
    Hero,
    Map,
    Role,
    Mode,
    Queue,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Group {
    pub key: String,
    pub label: Option<String>,
    pub aggregate: Aggregate,
}

fn enum_key<T: Serialize>(value: &T) -> String {
    serde_json::to_value(value)
        .ok()
        .and_then(|v| v.as_str().map(String::from))
        .unwrap_or_default()
}

fn entity_key(e: Option<&EntityRef>) -> (String, Option<String>) {
    e.map_or(("unknown".into(), None), |e| {
        (e.stable_id(), e.name.clone())
    })
}

/// Groups by one dimension, largest group first.
pub fn breakdown(rows: &[MatchSummary], dimension: Dimension) -> Vec<Group> {
    let mut groups: BTreeMap<String, (Option<String>, Vec<&MatchSummary>)> = BTreeMap::new();
    for m in rows {
        let (key, label) = match dimension {
            Dimension::Hero => entity_key(m.hero.as_ref()),
            Dimension::Map => entity_key(m.map.as_ref()),
            Dimension::Role => (
                enum_key(&m.role),
                Some(m.role.name_zh().into()).filter(|s: &String| !s.is_empty()),
            ),
            Dimension::Mode => (enum_key(&m.kind.mode), None),
            Dimension::Queue => (enum_key(&m.kind.queue), None),
        };
        let entry = groups.entry(key).or_insert((label, Vec::new()));
        entry.1.push(m);
    }
    let mut out: Vec<Group> = groups
        .into_iter()
        .map(|(key, (label, rows))| Group {
            key,
            label,
            aggregate: aggregate(rows),
        })
        .collect();
    out.sort_by_key(|g| std::cmp::Reverse(g.aggregate.record.matches));
    out
}

/// Reference time and the zone used for calendar days and hours.
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct Clock {
    pub now_ms: i64,
    pub utc_offset_minutes: i32,
}

impl Clock {
    pub fn now(utc_offset_minutes: i32) -> Self {
        Self {
            now_ms: crate::now_ms() as i64,
            utc_offset_minutes,
        }
    }
    fn offset_ms(self) -> i64 {
        i64::from(self.utc_offset_minutes) * 60_000
    }
    fn day_start(self) -> i64 {
        (self.now_ms + self.offset_ms()).div_euclid(DAY_MS) * DAY_MS - self.offset_ms()
    }
    pub fn local_hour(self, at_ms: i64) -> u32 {
        ((at_ms + self.offset_ms()).rem_euclid(DAY_MS) / 3_600_000) as u32
    }
}

const DAY_MS: i64 = 86_400_000;

/// Calendar zone for day/hour bucketing: China Standard Time (UTC+08), where the CN
/// servers, Dashen and the players this app is for all are. (Up to 1.2.0 it was
/// Asia/Tokyo, UTC+09, which put every match an hour late and midnight in the wrong place.)
pub const REPORT_TIMEZONE: &str = "Asia/Shanghai";
pub const REPORT_UTC_OFFSET_MINUTES: i32 = 8 * 60;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Window {
    All,
    Today,
    Yesterday,
    Week,
}

impl Window {
    pub fn parse(value: &str) -> Option<Self> {
        match value {
            "recent" | "all" => Some(Self::All),
            "today" => Some(Self::Today),
            "yesterday" => Some(Self::Yesterday),
            "week" => Some(Self::Week),
            _ => None,
        }
    }
    /// Half-open `[start, end)`; `today` is the local calendar day, `week` rolling 7×24h.
    pub fn bounds(self, clock: Clock) -> (i64, i64) {
        let day = clock.day_start();
        match self {
            Self::All => (i64::MIN, i64::MAX),
            Self::Today => (day, clock.now_ms + 1),
            Self::Yesterday => (day - DAY_MS, day),
            Self::Week => (clock.now_ms - 7 * DAY_MS, clock.now_ms + 1),
        }
    }
    pub fn contains(self, clock: Clock, at_ms: Option<i64>) -> bool {
        if self == Self::All {
            return true;
        }
        let (start, end) = self.bounds(clock);
        at_ms.is_some_and(|t| t >= start && t < end)
    }
}

pub fn in_window(rows: &[MatchSummary], window: Window, clock: Clock) -> Vec<MatchSummary> {
    rows.iter()
        .filter(|m| window.contains(clock, m.started_at_ms))
        .cloned()
        .collect()
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Session {
    pub start_ms: i64,
    /// Start of the last match in the session (list rows carry no duration).
    pub last_start_ms: i64,
    pub match_ids: Vec<String>,
    pub aggregate: Aggregate,
}

/// Chains matches whose start times are at most `max_gap_ms` apart. Newest first.
pub fn sessions(rows: &[MatchSummary], max_gap_ms: i64) -> Vec<Session> {
    let mut timed: Vec<&MatchSummary> = rows.iter().filter(|m| m.started_at_ms.is_some()).collect();
    timed.sort_by_key(|m| m.started_at_ms);
    let mut chains: Vec<Vec<&MatchSummary>> = Vec::new();
    for m in timed {
        match chains.last_mut() {
            Some(chain)
                if m.started_at_ms.unwrap() - chain.last().unwrap().started_at_ms.unwrap()
                    <= max_gap_ms =>
            {
                chain.push(m)
            }
            _ => chains.push(vec![m]),
        }
    }
    chains
        .into_iter()
        .rev()
        .map(|chain| Session {
            start_ms: chain[0].started_at_ms.unwrap(),
            last_start_ms: chain.last().unwrap().started_at_ms.unwrap(),
            match_ids: chain.iter().map(|m| m.id.clone()).collect(),
            aggregate: aggregate(chain),
        })
        .collect()
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct HourBucket {
    pub hour: u32,
    pub record: Record,
}

/// Results by local start hour, all 24 hours present.
pub fn by_hour(rows: &[MatchSummary], clock: Clock) -> Vec<HourBucket> {
    let mut buckets: Vec<HourBucket> = (0..24)
        .map(|hour| HourBucket {
            hour,
            record: Record::default(),
        })
        .collect();
    for m in rows {
        if let Some(t) = m.started_at_ms {
            buckets[clock.local_hour(t) as usize].record.add(m.outcome);
        }
    }
    buckets
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RankPoint {
    pub at_ms: i64,
    pub match_id: String,
    pub mode: Mode,
    pub role: Role,
    pub tier: Option<String>,
    pub division: Option<u8>,
    pub skill_rating: Option<i64>,
}

/// Per-match rank snapshots in chronological order.
pub fn rank_timeline(rows: &[MatchSummary]) -> Vec<RankPoint> {
    let mut points: Vec<RankPoint> = rows
        .iter()
        .filter_map(|m| {
            let rank = m.rank.as_ref()?;
            Some(RankPoint {
                at_ms: m.started_at_ms?,
                match_id: m.id.clone(),
                mode: m.kind.mode,
                role: m.role,
                tier: rank.tier.clone(),
                division: rank.division,
                skill_rating: rank.skill_rating,
            })
        })
        .collect();
    points.sort_by_key(|p| p.at_ms);
    points
}

/// Matches of `a` whose id also appears in `b` (both players were in the lobby).
pub fn common_matches(a: &[MatchSummary], b: &[MatchSummary]) -> Vec<MatchSummary> {
    let ids: std::collections::HashSet<&str> = b
        .iter()
        .map(|m| m.id.as_str())
        .filter(|id| !id.is_empty())
        .collect();
    let mut seen = std::collections::HashSet::new();
    a.iter()
        .filter(|m| ids.contains(m.id.as_str()) && seen.insert(m.id.as_str()))
        .cloned()
        .collect()
}

/// The subject's fraction of their own team's totals in one match (0-1).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TeamShare {
    pub match_id: String,
    pub share: StatLine,
    /// Subject holds the team's highest positive value (ties all count).
    pub team_best: Highlights,
}

pub fn team_share(detail: &MatchDetail) -> Option<TeamShare> {
    let me = detail.subject()?;
    let mut share = StatLine::default();
    let mut best = [false; 4];
    for field in StatLine::FIELDS {
        let values: Vec<f64> = detail
            .allies
            .iter()
            .filter_map(|p| p.stats.get(field))
            .collect();
        let total: f64 = values.iter().sum();
        if let Some(mine) = me.stats.get(field)
            && total > 0.0
        {
            share.set(field, Some(mine / total));
        }
    }
    for (i, field) in ["kills", "damage", "healing", "mitigation"]
        .iter()
        .enumerate()
    {
        let max = detail
            .allies
            .iter()
            .filter_map(|p| p.stats.get(field))
            .fold(f64::NEG_INFINITY, f64::max);
        best[i] = max > 0.0 && me.stats.get(field) == Some(max);
    }
    Some(TeamShare {
        match_id: detail.id.clone(),
        share,
        team_best: Highlights {
            kills: best[0],
            damage: best[1],
            healing: best[2],
            mitigation: best[3],
        },
    })
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct TeamShareSummary {
    pub matches: usize,
    pub mean_share: StatLine,
    pub team_best_counts: BTreeMap<String, usize>,
}

pub fn team_share_summary<'a>(
    details: impl IntoIterator<Item = &'a MatchDetail>,
) -> TeamShareSummary {
    let shares: Vec<TeamShare> = details.into_iter().filter_map(team_share).collect();
    let (_, mean_share, _) = stat_means(shares.iter().map(|s| &s.share));
    let mut counts = BTreeMap::new();
    for s in &shares {
        for (name, hit) in [
            ("kills", s.team_best.kills),
            ("damage", s.team_best.damage),
            ("healing", s.team_best.healing),
            ("mitigation", s.team_best.mitigation),
        ] {
            *counts.entry(name.to_string()).or_insert(0) += usize::from(hit);
        }
    }
    TeamShareSummary {
        matches: shares.len(),
        mean_share,
        team_best_counts: counts,
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Companion {
    pub name: Option<String>,
    pub bnet_id: Option<String>,
    pub as_ally: Record,
    pub as_enemy: Record,
    /// Matches where they queued in the subject's group.
    pub in_party: usize,
}

/// Other players met across fetched details, results from the subject's side.
pub fn companions(details: &BTreeMap<String, MatchDetail>, min_matches: usize) -> Vec<Companion> {
    let mut found: HashMap<String, Companion> = HashMap::new();
    for d in details.values() {
        let me = d.subject();
        let my_id = me.and_then(|p| p.bnet_id.as_deref());
        for (ally, players) in [(true, &d.allies), (false, &d.enemies)] {
            for p in players.iter().filter(|p| !p.is_subject) {
                let Some(key) = p.bnet_id.clone().or_else(|| p.name.clone()) else {
                    continue;
                };
                let c = found.entry(key).or_insert_with(|| Companion {
                    name: p.name.clone(),
                    bnet_id: p.bnet_id.clone(),
                    as_ally: Record::default(),
                    as_enemy: Record::default(),
                    in_party: 0,
                });
                if c.name.is_none() {
                    c.name = p.name.clone();
                }
                if ally {
                    c.as_ally.add(d.outcome);
                    let grouped = me.is_some_and(|me| {
                        p.bnet_id
                            .as_ref()
                            .is_some_and(|id| me.party_bnet_ids.contains(id))
                            || my_id.is_some_and(|id| p.party_bnet_ids.iter().any(|x| x == id))
                    });
                    c.in_party += usize::from(grouped);
                } else {
                    c.as_enemy.add(d.outcome);
                }
            }
        }
    }
    let mut out: Vec<Companion> = found
        .into_values()
        .filter(|c| c.as_ally.matches + c.as_enemy.matches >= min_matches)
        .collect();
    out.sort_by(|a, b| {
        (b.as_ally.matches + b.as_enemy.matches)
            .cmp(&(a.as_ally.matches + a.as_enemy.matches))
            .then_with(|| a.name.cmp(&b.name))
    });
    out
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SeasonPoint {
    pub mode: Mode,
    pub season: Option<u32>,
    pub role: Role,
    pub matches: Option<i64>,
    pub win_rate_pct: Option<f64>,
    pub kda: Option<f64>,
    pub current_rank: Option<Rank>,
    pub peak_rank: Option<Rank>,
}

/// Per-role career rows across season snapshots, ordered by mode, role, season
/// (current season, `None`, last).
pub fn season_trend(careers: &[CareerSnapshot]) -> Vec<SeasonPoint> {
    let mut points: Vec<SeasonPoint> = careers
        .iter()
        .flat_map(|c| {
            c.roles.iter().map(move |r| SeasonPoint {
                mode: c.mode,
                season: c.season,
                role: r.role,
                matches: r.matches,
                win_rate_pct: r.win_rate_pct,
                kda: r.kda,
                current_rank: r.current_rank.clone(),
                peak_rank: r.peak_rank.clone(),
            })
        })
        .collect();
    points.sort_by_key(|p| (p.mode, p.role, p.season.unwrap_or(u32::MAX)));
    points
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct AnalysisOptions {
    pub utc_offset_minutes: i32,
    /// Reference time; `None` uses the current time.
    pub now_ms: Option<i64>,
    pub session_gap_ms: i64,
    pub min_companion_matches: usize,
}

impl Default for AnalysisOptions {
    fn default() -> Self {
        Self {
            utc_offset_minutes: REPORT_UTC_OFFSET_MINUTES,
            now_ms: None,
            session_gap_ms: 5 * 3_600_000,
            min_companion_matches: 2,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WindowAggregate {
    pub window: Window,
    pub aggregate: Aggregate,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PlayerAnalysis {
    pub clock: ClockInfo,
    pub overall: Aggregate,
    pub windows: Vec<WindowAggregate>,
    pub by_mode: Vec<Group>,
    pub by_queue: Vec<Group>,
    pub by_role: Vec<Group>,
    pub by_hero: Vec<Group>,
    pub by_map: Vec<Group>,
    pub sessions: Vec<Session>,
    pub by_hour: Vec<HourBucket>,
    pub rank_timeline: Vec<RankPoint>,
    pub team_share: TeamShareSummary,
    pub companions: Vec<Companion>,
    pub season_trend: Vec<SeasonPoint>,
    pub lobby_strength: crate::strength::LobbyStrength,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ClockInfo {
    pub now_ms: i64,
    pub utc_offset_minutes: i32,
}

pub fn analyze(ds: &PlayerDataset, options: &AnalysisOptions) -> PlayerAnalysis {
    let clock = Clock {
        now_ms: options.now_ms.unwrap_or(crate::now_ms() as i64),
        utc_offset_minutes: options.utc_offset_minutes,
    };
    let rows = &ds.matches;
    PlayerAnalysis {
        clock: ClockInfo {
            now_ms: clock.now_ms,
            utc_offset_minutes: clock.utc_offset_minutes,
        },
        overall: aggregate(rows),
        windows: [Window::Today, Window::Yesterday, Window::Week]
            .into_iter()
            .map(|window| WindowAggregate {
                window,
                aggregate: aggregate(
                    rows.iter()
                        .filter(|m| window.contains(clock, m.started_at_ms)),
                ),
            })
            .collect(),
        by_mode: breakdown(rows, Dimension::Mode),
        by_queue: breakdown(rows, Dimension::Queue),
        by_role: breakdown(rows, Dimension::Role),
        by_hero: breakdown(rows, Dimension::Hero),
        by_map: breakdown(rows, Dimension::Map),
        sessions: sessions(rows, options.session_gap_ms),
        by_hour: by_hour(rows, clock),
        rank_timeline: rank_timeline(rows),
        team_share: team_share_summary(ds.details.values()),
        companions: companions(&ds.details, options.min_companion_matches),
        season_trend: season_trend(&ds.careers),
        lobby_strength: crate::strength::lobby_strength(&ds.details, &ds.player_ratings),
    }
}

// ---- Overview ------------------------------------------------------------------------------

/// How many of the newest matches count as "recent" on the overview.
pub const RECENT_MATCHES: usize = 20;

/// One match in the overview's form strip.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct FormPoint {
    pub match_id: String,
    pub started_at_ms: Option<i64>,
    pub outcome: Outcome,
    pub hero: Option<EntityRef>,
    pub role: Role,
    pub map: Option<EntityRef>,
}

pub use crate::insights::{Insight, InsightItem, InsightKind};
/// Everything the overview page shows, from a player's stored match list alone.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Overview {
    pub overall: Aggregate,
    /// The newest [`RECENT_MATCHES`] matches, and the same number before them.
    pub recent: Aggregate,
    pub before: Aggregate,
    pub windows: Vec<WindowAggregate>,
    pub by_role: Vec<Group>,
    pub by_hero: Vec<Group>,
    pub by_map: Vec<Group>,
    /// `heat[weekday][hour]`, Monday first, in the report time zone.
    pub heat: Vec<Vec<Record>>,
    /// The newest session first, at most three.
    pub sessions: Vec<Session>,
    /// The newest [`RECENT_MATCHES`] matches, oldest first.
    pub form: Vec<FormPoint>,
    /// Win rate over the last 10 decided matches at each of the newest 30, oldest first.
    pub rolling_win_pct: Vec<Option<f64>>,
    /// Findings firm enough to say; never more than four.
    pub insights: Vec<Insight>,
}

fn weekday(clock: Clock, at_ms: i64) -> usize {
    // 1970-01-01 was a Thursday: Monday is 0.
    (((at_ms + clock.offset_ms()).div_euclid(DAY_MS) + 3).rem_euclid(7)) as usize
}

/// `context` adds what the stored list alone cannot say (lobby strength, peer benchmarks)
/// to the findings; [`crate::insights::Context::default`] leaves it out.
pub fn overview(
    rows: &[MatchSummary],
    clock: Clock,
    session_gap_ms: i64,
    context: &crate::insights::Context<'_>,
) -> Overview {
    let mut newest: Vec<&MatchSummary> = rows.iter().collect();
    newest.sort_by_key(|m| std::cmp::Reverse(m.started_at_ms.unwrap_or(i64::MIN)));
    let recent: Vec<&MatchSummary> = newest.iter().take(RECENT_MATCHES).copied().collect();
    let before: Vec<&MatchSummary> = newest
        .iter()
        .skip(RECENT_MATCHES)
        .take(RECENT_MATCHES)
        .copied()
        .collect();
    let mut heat = vec![vec![Record::default(); 24]; 7];
    for m in rows {
        if let Some(t) = m.started_at_ms {
            heat[weekday(clock, t)][clock.local_hour(t) as usize].add(m.outcome);
        }
    }
    let decided: Vec<&MatchSummary> = newest
        .iter()
        .filter(|m| matches!(m.outcome, Outcome::Win | Outcome::Loss))
        .copied()
        .collect();
    let rolling_win_pct = (0..decided.len().min(30))
        .rev()
        .map(|i| {
            let window: Vec<_> = decided.iter().skip(i).take(10).collect();
            (window.len() == 10).then(|| {
                100.0 * window.iter().filter(|m| m.outcome == Outcome::Win).count() as f64 / 10.0
            })
        })
        .collect();
    let overall = aggregate(rows.iter());
    let recent_agg = aggregate(recent.iter().copied());
    let before_agg = aggregate(before.iter().copied());
    let by_hero = breakdown(rows, Dimension::Hero);
    let by_map = breakdown(rows, Dimension::Map);

    let all_sessions = sessions(rows, session_gap_ms);
    let insights = crate::insights::find(&crate::insights::Facts {
        overall: &overall,
        recent: &recent,
        before: &before,
        recent_agg: &recent_agg,
        before_agg: &before_agg,
        by_map: &by_map,
        by_hero: &by_hero,
        sessions: &all_sessions,
        rows,
        context,
    });

    Overview {
        windows: [Window::Today, Window::Yesterday, Window::Week]
            .into_iter()
            .map(|window| WindowAggregate {
                window,
                aggregate: aggregate(
                    rows.iter()
                        .filter(|m| window.contains(clock, m.started_at_ms)),
                ),
            })
            .collect(),
        by_role: breakdown(rows, Dimension::Role),
        by_hero,
        by_map,
        heat,
        sessions: all_sessions.into_iter().take(3).collect(),
        form: recent
            .iter()
            .rev()
            .map(|m| FormPoint {
                match_id: m.id.clone(),
                started_at_ms: m.started_at_ms,
                outcome: m.outcome,
                hero: m.hero.clone(),
                role: m.role,
                map: m.map.clone(),
            })
            .collect(),
        rolling_win_pct,
        overall,
        recent: recent_agg,
        before: before_agg,
        insights,
    }
}

/// Fills each participant's Fleta index: their final blows as a percentage of half of
/// their own team's final blows, so 100 means they took half of the team's final blows
/// (the share a player in a team of five would not be expected to exceed by much), and
/// higher means they finished off more of the kills than that. Worked out per team, from
/// the match only. `None` when the player's final blows are unknown or the team has none.
pub fn attach_fleta(detail: &mut MatchDetail) {
    for team in [&mut detail.allies, &mut detail.enemies] {
        let total = team_final_blows(team);
        for p in team.iter_mut() {
            p.fleta = fleta(p.stats.final_blows, total);
        }
    }
}

/// All the final blows a team is known to have made.
pub fn team_final_blows(team: &[Participant]) -> f64 {
    team.iter().filter_map(|p| p.stats.final_blows).sum()
}

/// Fleta index of a player with `final_blows` in a team that made `team_total`.
pub fn fleta(final_blows: Option<f64>, team_total: f64) -> Option<f64> {
    final_blows
        .filter(|_| team_total > 0.0)
        .map(|f| f / (team_total * 0.5) * 100.0)
}

#[cfg(test)]
mod tests {
    use super::*;

    const HOUR: i64 = 3_600_000;

    fn row(id: &str, at: Option<i64>, outcome: Outcome, stats: StatLine) -> MatchSummary {
        MatchSummary {
            id: id.into(),
            started_at_ms: at,
            kind: MatchKind {
                mode: Mode::Quick,
                queue: Queue::RoleQueue,
                ranked: None,
                provider_mode: None,
                instance_type: None,
            },
            outcome,
            map: None,
            hero: None,
            role: Role::Support,
            score: Score::default(),
            stats,
            highlights: None,
            rank: None,
            hero_icon_url: None,
        }
    }

    fn timed(id: &str, at: i64, outcome: Outcome) -> MatchSummary {
        row(id, Some(at), outcome, StatLine::default())
    }

    fn kda(k: f64, a: f64, d: f64) -> StatLine {
        StatLine {
            kills: Some(k),
            assists: Some(a),
            deaths: Some(d),
            ..StatLine::default()
        }
    }

    fn player(name: &str, subject: bool, stats: StatLine) -> Participant {
        Participant {
            name: Some(name.into()),
            bnet_id: Some(format!("{name}#1")),
            is_subject: subject,
            hero: None,
            hero_icon_url: None,
            role: Role::Damage,
            stats,
            rank: None,
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

    fn detail(
        id: &str,
        outcome: Outcome,
        allies: Vec<Participant>,
        enemies: Vec<Participant>,
    ) -> MatchDetail {
        MatchDetail {
            id: id.into(),
            mode: Mode::Quick,
            map: None,
            outcome,
            outcome_source: OutcomeSource::Provider,
            started_at_ms: Some(0),
            duration_s: None,
            score: Score::default(),
            bans: Bans::default(),
            subject_heroes: Vec::new(),
            allies,
            enemies,
            rounds: Vec::new(),
        }
    }

    fn damage(v: f64) -> StatLine {
        StatLine {
            damage: Some(v),
            ..StatLine::default()
        }
    }

    #[test]
    fn win_rate_leaves_out_draws_and_unknown_results() {
        let mut r = Record::default();
        for o in [
            Outcome::Win,
            Outcome::Loss,
            Outcome::Draw,
            Outcome::Unknown,
            Outcome::Win,
        ] {
            r.add(o);
        }
        assert_eq!(
            (r.matches, r.wins, r.losses, r.draws, r.unknown),
            (5, 2, 1, 1, 1)
        );
        assert!((r.win_rate_pct.unwrap() - 200.0 / 3.0).abs() < 1e-9);
    }

    #[test]
    fn no_decided_match_means_no_win_rate() {
        let mut r = Record::default();
        r.add(Outcome::Draw);
        assert_eq!(r.win_rate_pct, None);
    }

    #[test]
    fn means_divide_by_the_matches_that_supplied_the_stat() {
        // A missing damage value is not a zero: the mean is over the two that have one.
        let rows = [
            row("a", Some(1), Outcome::Win, damage(1000.0)),
            row("b", Some(2), Outcome::Win, StatLine::default()),
            row("c", Some(3), Outcome::Loss, damage(3000.0)),
        ];
        let agg = aggregate(&rows);
        assert_eq!(agg.totals.damage, Some(4000.0));
        assert_eq!(agg.per_match.damage, Some(2000.0));
        assert_eq!(agg.samples.get("damage"), Some(&2));
        assert_eq!(agg.per_match.healing, None);
        assert!(!agg.samples.contains_key("healing"));
    }

    #[test]
    fn kda_uses_only_matches_with_all_three_counts() {
        let partial = StatLine {
            kills: Some(50.0),
            ..StatLine::default()
        };
        let rows = [
            row("a", Some(1), Outcome::Win, kda(6.0, 4.0, 2.0)),
            row("b", Some(2), Outcome::Win, partial),
            row("c", Some(3), Outcome::Win, kda(2.0, 0.0, 2.0)),
        ];
        assert_eq!(aggregate(&rows).kda, Some(3.0));
    }

    #[test]
    fn kda_is_unknown_without_any_death() {
        let rows = [row("a", Some(1), Outcome::Win, kda(6.0, 4.0, 0.0))];
        assert_eq!(aggregate(&rows).kda, None);
    }

    #[test]
    fn streaks_follow_start_time_not_input_order() {
        // Chronologically W W W L L: best win 3, best loss 2, ending on a two-loss streak.
        let rows = [
            timed("l2", 5, Outcome::Loss),
            timed("w1", 1, Outcome::Win),
            timed("l1", 4, Outcome::Loss),
            timed("w3", 3, Outcome::Win),
            timed("w2", 2, Outcome::Win),
        ];
        let agg = aggregate(&rows);
        assert_eq!(agg.streaks.best_win, 3);
        assert_eq!(agg.streaks.best_loss, 2);
        assert_eq!(agg.streaks.current, -2);
        assert_eq!((agg.first_ms, agg.last_ms), (Some(1), Some(5)));
    }

    #[test]
    fn a_draw_breaks_both_streaks() {
        let rows = [
            timed("a", 1, Outcome::Win),
            timed("b", 2, Outcome::Draw),
            timed("c", 3, Outcome::Win),
        ];
        let agg = aggregate(&rows);
        assert_eq!(agg.streaks.best_win, 1);
        assert_eq!(agg.streaks.current, 1);
    }

    #[test]
    fn breakdown_puts_the_largest_group_first_and_keeps_unknown_heroes_apart() {
        let hero = |guid: &str| Some(EntityRef::new(EntityKind::Hero, guid, Some(guid.into())));
        let mut rows = vec![
            timed("a", 1, Outcome::Win),
            timed("b", 2, Outcome::Win),
            timed("c", 3, Outcome::Loss),
            timed("d", 4, Outcome::Loss),
        ];
        rows[0].hero = hero("1");
        rows[1].hero = hero("2");
        rows[2].hero = hero("2");
        let groups = breakdown(&rows, Dimension::Hero);
        assert_eq!(groups.len(), 3);
        assert_eq!(groups[0].label.as_deref(), Some("2"));
        assert_eq!(groups[0].aggregate.record.matches, 2);
        let unknown = groups.iter().find(|g| g.key == "unknown").unwrap();
        assert_eq!(unknown.label, None);
        assert_eq!(unknown.aggregate.record.matches, 1);
    }

    #[test]
    fn breakdown_by_role_carries_the_chinese_label() {
        let groups = breakdown(&[timed("a", 1, Outcome::Win)], Dimension::Role);
        assert_eq!(groups[0].key, "support");
        assert_eq!(groups[0].label.as_deref(), Some("支援"));
    }

    #[test]
    fn calendar_days_follow_the_clock_offset() {
        // 2026-01-02 00:00 at UTC+08 is 2026-01-01 16:00 UTC.
        let midnight_local = 1_767_283_200_000;
        let clock = Clock {
            now_ms: midnight_local + HOUR / 2,
            utc_offset_minutes: 8 * 60,
        };
        let just_after = Some(midnight_local + 60_000);
        let just_before = Some(midnight_local - 60_000);
        assert!(Window::Today.contains(clock, just_after));
        assert!(!Window::Today.contains(clock, just_before));
        assert!(Window::Yesterday.contains(clock, just_before));
        assert!(!Window::Yesterday.contains(clock, Some(midnight_local - 24 * HOUR - 1)));
        assert!(Window::Week.contains(clock, just_before));
        assert!(!Window::Week.contains(clock, None));
        assert!(Window::All.contains(clock, None));
    }

    #[test]
    fn window_names_parse() {
        assert_eq!(Window::parse("recent"), Some(Window::All));
        assert_eq!(Window::parse("week"), Some(Window::Week));
        assert_eq!(Window::parse("month"), None);
    }

    #[test]
    fn sessions_split_on_long_gaps_newest_first() {
        let rows = [
            timed("a", 0, Outcome::Win),
            timed("b", HOUR, Outcome::Loss),
            timed("c", 10 * HOUR, Outcome::Win),
            row("untimed", None, Outcome::Win, StatLine::default()),
        ];
        let s = sessions(&rows, 5 * HOUR);
        assert_eq!(s.len(), 2);
        assert_eq!(s[0].match_ids, ["c"]);
        assert_eq!(s[1].match_ids, ["a", "b"]);
        assert_eq!(s[1].start_ms, 0);
        assert_eq!(s[1].last_start_ms, HOUR);
        assert_eq!(s[1].aggregate.record.losses, 1);
    }

    #[test]
    fn hours_are_local_and_all_present() {
        let clock = Clock {
            now_ms: 0,
            utc_offset_minutes: 8 * 60,
        };
        // 16:00 UTC is midnight at UTC+08.
        let buckets = by_hour(&[timed("a", 16 * HOUR, Outcome::Win)], clock);
        assert_eq!(buckets.len(), 24);
        assert_eq!(buckets[0].record.wins, 1);
        assert_eq!(buckets.iter().map(|b| b.record.matches).sum::<usize>(), 1);
    }

    #[test]
    fn rank_timeline_is_chronological_and_skips_untimed_or_unranked_rows() {
        let rank = |sr| Rank {
            tier: Some("Gold".into()),
            division: Some(3),
            score: None,
            skill_rating: Some(sr),
            at_ms: None,
        };
        let mut late = timed("late", 2, Outcome::Win);
        late.rank = Some(rank(1800));
        let mut early = timed("early", 1, Outcome::Win);
        early.rank = Some(rank(1700));
        let mut untimed = row("x", None, Outcome::Win, StatLine::default());
        untimed.rank = Some(rank(1));
        let unranked = timed("y", 3, Outcome::Win);
        let points = rank_timeline(&[late, untimed, early, unranked]);
        let ids: Vec<&str> = points.iter().map(|p| p.match_id.as_str()).collect();
        assert_eq!(ids, ["early", "late"]);
        assert_eq!(points[1].skill_rating, Some(1800));
    }

    #[test]
    fn common_matches_are_shared_ids_once_each() {
        let a = [
            timed("1", 1, Outcome::Win),
            timed("2", 2, Outcome::Win),
            timed("2", 2, Outcome::Win),
            timed("", 3, Outcome::Win),
        ];
        let b = [timed("2", 2, Outcome::Loss), timed("", 3, Outcome::Loss)];
        let common = common_matches(&a, &b);
        assert_eq!(common.len(), 1);
        assert_eq!(common[0].id, "2");
        // The subject's side of the shared match is kept.
        assert_eq!(common[0].outcome, Outcome::Win);
    }

    #[test]
    fn team_share_is_the_subjects_part_of_their_own_team() {
        let d = detail(
            "m",
            Outcome::Win,
            vec![
                player("me", true, damage(6000.0)),
                player("mate", false, damage(4000.0)),
            ],
            vec![player("foe", false, damage(99_999.0))],
        );
        let s = team_share(&d).unwrap();
        assert_eq!(s.share.damage, Some(0.6));
        assert!(s.team_best.damage);
        assert!(!s.team_best.healing);
    }

    #[test]
    fn ties_and_zeros_for_team_best() {
        let tied = detail(
            "m",
            Outcome::Win,
            vec![
                player("me", true, damage(5000.0)),
                player("mate", false, damage(5000.0)),
            ],
            Vec::new(),
        );
        assert!(team_share(&tied).unwrap().team_best.damage);
        let zeros = detail(
            "m",
            Outcome::Win,
            vec![
                player("me", true, damage(0.0)),
                player("mate", false, damage(0.0)),
            ],
            Vec::new(),
        );
        let s = team_share(&zeros).unwrap();
        assert!(!s.team_best.damage);
        assert_eq!(s.share.damage, None);
    }

    #[test]
    fn team_share_needs_the_subject() {
        let d = detail(
            "m",
            Outcome::Win,
            vec![player("mate", false, damage(1.0))],
            Vec::new(),
        );
        assert_eq!(team_share(&d), None);
        assert_eq!(team_share_summary([&d]).matches, 0);
    }

    #[test]
    fn team_share_summary_counts_team_best_matches() {
        let won = detail(
            "a",
            Outcome::Win,
            vec![
                player("me", true, damage(6000.0)),
                player("mate", false, damage(4000.0)),
            ],
            Vec::new(),
        );
        let lost = detail(
            "b",
            Outcome::Loss,
            vec![
                player("me", true, damage(2000.0)),
                player("mate", false, damage(8000.0)),
            ],
            Vec::new(),
        );
        let s = team_share_summary([&won, &lost]);
        assert_eq!(s.matches, 2);
        assert!((s.mean_share.damage.unwrap() - 0.4).abs() < 1e-9);
        assert_eq!(s.team_best_counts.get("damage"), Some(&1));
        assert_eq!(s.team_best_counts.get("kills"), Some(&0));
    }

    #[test]
    fn companions_count_sides_and_parties() {
        let mut me = player("me", true, StatLine::default());
        me.party_bnet_ids = vec!["duo#1".into()];
        let mut details = BTreeMap::new();
        details.insert(
            "a".into(),
            detail(
                "a",
                Outcome::Win,
                vec![me.clone(), player("duo", false, StatLine::default())],
                vec![player("rival", false, StatLine::default())],
            ),
        );
        details.insert(
            "b".into(),
            detail(
                "b",
                Outcome::Loss,
                vec![me, player("duo", false, StatLine::default())],
                vec![player("once", false, StatLine::default())],
            ),
        );
        let found = companions(&details, 2);
        assert_eq!(found.len(), 1);
        let duo = &found[0];
        assert_eq!(duo.name.as_deref(), Some("duo"));
        assert_eq!((duo.as_ally.wins, duo.as_ally.losses), (1, 1));
        assert_eq!(duo.as_enemy.matches, 0);
        assert_eq!(duo.in_party, 2);
        assert_eq!(companions(&details, 1).len(), 3);
    }

    #[test]
    fn fleta_is_final_blows_over_half_the_team() {
        assert_eq!(fleta(Some(5.0), 10.0), Some(100.0));
        assert_eq!(fleta(Some(2.0), 10.0), Some(40.0));
        assert_eq!(fleta(None, 10.0), None);
        assert_eq!(fleta(Some(0.0), 0.0), None);
    }

    #[test]
    fn attach_fleta_works_per_team() {
        let fb = |v| StatLine {
            final_blows: Some(v),
            ..StatLine::default()
        };
        let mut d = detail(
            "m",
            Outcome::Win,
            vec![player("me", true, fb(3.0)), player("mate", false, fb(3.0))],
            vec![player("foe", false, fb(10.0))],
        );
        attach_fleta(&mut d);
        assert_eq!(d.allies[0].fleta, Some(100.0));
        assert_eq!(d.enemies[0].fleta, Some(200.0));
    }

    fn on_map(id: &str, at: i64, outcome: Outcome, map: &str) -> MatchSummary {
        let mut m = timed(id, at, outcome);
        m.map = Some(EntityRef::new(EntityKind::Map, map, Some(map.into())));
        m
    }

    #[test]
    fn weekdays_start_on_monday_in_the_report_zone() {
        let clock = Clock {
            now_ms: 0,
            utc_offset_minutes: 8 * 60,
        };
        // 2026-10-19 00:30 +08 was a Monday; 2026-10-18 23:30 +08 a Sunday.
        let monday = 1_792_368_000_000 - 8 * HOUR + 30 * 60_000;
        assert_eq!(weekday(clock, monday), 0);
        assert_eq!(weekday(clock, monday - HOUR), 6);
    }

    #[test]
    fn the_overview_splits_recent_from_before_and_lists_form_oldest_first() {
        let clock = Clock {
            now_ms: 100 * HOUR,
            utc_offset_minutes: 8 * 60,
        };
        let rows: Vec<MatchSummary> = (0..45)
            .map(|i| {
                timed(
                    &format!("m{i}"),
                    i * HOUR,
                    if i % 2 == 0 {
                        Outcome::Win
                    } else {
                        Outcome::Loss
                    },
                )
            })
            .collect();
        let o = overview(&rows, clock, 5 * HOUR, &crate::insights::Context::default());
        assert_eq!(o.overall.record.matches, 45);
        assert_eq!(o.recent.record.matches, RECENT_MATCHES);
        assert_eq!(o.before.record.matches, RECENT_MATCHES);
        assert_eq!(o.form.len(), RECENT_MATCHES);
        assert_eq!(o.form.first().unwrap().match_id, "m25");
        assert_eq!(o.form.last().unwrap().match_id, "m44");
        assert_eq!(o.rolling_win_pct.len(), 30);
        assert_eq!(o.rolling_win_pct.last().unwrap(), &Some(50.0));
        assert_eq!(o.heat.len(), 7);
        assert!(o.heat.iter().all(|d| d.len() == 24));
        let heat_total: usize = o.heat.iter().flatten().map(|r| r.matches).sum();
        assert_eq!(heat_total, 45);
        assert!(o.sessions.len() <= 3);
    }

    #[test]
    fn only_a_map_whose_whole_range_is_off_the_rate_is_a_finding() {
        let clock = Clock {
            now_ms: 0,
            utc_offset_minutes: 8 * 60,
        };
        let mut rows = Vec::new();
        let mut t = 0;
        let mut add = |rows: &mut Vec<MatchSummary>, map: &str, wins: usize, losses: usize| {
            for k in 0..wins + losses {
                t += HOUR;
                let o = if k < wins {
                    Outcome::Win
                } else {
                    Outcome::Loss
                };
                rows.push(on_map(&format!("{map}{k}"), t, o, map));
            }
        };
        // 18 of 20 on one map is clearly above a ~50 % player; 3 of 5 elsewhere is not.
        add(&mut rows, "1", 18, 2);
        add(&mut rows, "2", 3, 2);
        add(&mut rows, "3", 10, 25);
        let o = overview(&rows, clock, HOUR / 2, &crate::insights::Context::default());
        let maps: Vec<_> = o
            .insights
            .iter()
            .filter(|i| i.kind == InsightKind::Map)
            .collect();
        assert_eq!(maps.len(), 1);
        assert_eq!(maps[0].subject.as_deref(), Some("1"));
        assert!(maps[0].positive);
        assert!(o.insights.len() <= 4);
    }

    #[test]
    fn a_long_streak_is_said() {
        let clock = Clock {
            now_ms: 0,
            utc_offset_minutes: 8 * 60,
        };
        let rows: Vec<MatchSummary> = (0..4)
            .map(|i| timed(&format!("m{i}"), i * HOUR, Outcome::Loss))
            .collect();
        let o = overview(&rows, clock, HOUR, &crate::insights::Context::default());
        let s = o
            .insights
            .iter()
            .find(|i| i.kind == InsightKind::Streak)
            .unwrap();
        assert!(!s.positive);
        assert_eq!(s.n, 4);
    }
}
