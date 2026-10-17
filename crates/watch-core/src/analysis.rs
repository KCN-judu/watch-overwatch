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
    out.sort_by(|a, b| b.aggregate.record.matches.cmp(&a.aggregate.record.matches));
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

/// Calendar zone for day/hour bucketing. The app has always reported in
/// Asia/Tokyo (UTC+09); note Dashen's own servers run on UTC+08.
pub const REPORT_TIMEZONE: &str = "Asia/Tokyo";
pub const REPORT_UTC_OFFSET_MINUTES: i32 = 9 * 60;

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
