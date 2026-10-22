//! A day's summary: how the player's matches on one calendar day went, what stood out
//! (best single matches, top-of-the-lobby figures, personal records, streaks), and how
//! the day compares with the month before it. Days are calendar days in the report zone
//! ([`crate::analysis::REPORT_UTC_OFFSET_MINUTES`]); only stored data is used.
use crate::analysis::{Aggregate, Dimension, Group, Record, aggregate, breakdown};
use crate::ir::*;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

const DAY_MS: i64 = 86_400_000;
/// The "usual" figures are the days before, this far back.
pub const USUAL_DAYS: i64 = 30;
/// The usual figures need this many earlier matches on the role.
pub const MIN_USUAL: usize = 5;
/// A single match is a personal record when it beats this many earlier stored matches.
pub const MIN_RECORD_HISTORY: usize = 20;
/// Heroes and maps listed.
pub const LISTED: usize = 6;

/// `YYYY-MM-DD` of the calendar day `days` after 1970-01-01 (Howard Hinnant's algorithm).
pub fn date_of(days: i64) -> String {
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = yoe + era * 400 + i64::from(m <= 2);
    format!("{y:04}-{m:02}-{d:02}")
}

/// The calendar day (days since 1970-01-01, local) of an instant.
pub fn day_of(at_ms: i64, utc_offset_minutes: i32) -> i64 {
    (at_ms + i64::from(utc_offset_minutes) * 60_000).div_euclid(DAY_MS)
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DayEntry {
    pub day: String,
    pub record: Record,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum HighlightKind {
    /// `value` matches where the player topped the whole lobby in `stat`.
    LobbyTop,
    /// The day's best single match in `stat`.
    DayBest,
    /// A single match beating every earlier stored match in `stat`.
    PersonalRecord,
    /// `value` wins in a row.
    Streak,
    /// `value` matches without dying.
    Deathless,
    /// The day's best match by KDA among wins.
    BestMatch,
    /// The day's best Fleta index (needs stored details).
    BestFleta,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Highlight {
    pub kind: HighlightKind,
    /// `kills`, `damage`, `healing`, `mitigation`, `kda`, or empty.
    pub stat: String,
    pub value: f64,
    /// The match it is about, when one.
    pub match_id: Option<String>,
    pub hero: Option<EntityRef>,
    pub map: Option<EntityRef>,
    /// For a record: the previous best.
    pub previous: Option<f64>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Versus {
    pub stat: String,
    pub today: f64,
    pub usual: f64,
    /// Matches on each side.
    pub today_n: usize,
    pub usual_n: usize,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RankChange {
    pub role: Role,
    pub from: i64,
    pub to: i64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DailySummary {
    pub day: String,
    pub aggregate: Aggregate,
    /// Sittings (matches less than `session_gap_ms` apart) that day.
    pub sittings: usize,
    pub first_ms: Option<i64>,
    pub last_ms: Option<i64>,
    /// Total length of the day's matches with a stored detail, and how many those were.
    pub play_s: Option<f64>,
    pub play_samples: usize,
    pub heroes: Vec<Group>,
    pub maps: Vec<Group>,
    pub roles: Vec<Group>,
    pub rank_changes: Vec<RankChange>,
    pub highlights: Vec<Highlight>,
    /// The day's main role against its usual figures (the month before).
    pub versus_role: Option<Role>,
    pub versus: Vec<Versus>,
    /// The day's matches, newest first.
    pub match_ids: Vec<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct Daily {
    /// Days with matches, newest first.
    pub days: Vec<DayEntry>,
    pub summary: Option<DailySummary>,
}

const STATS: [&str; 4] = ["kills", "damage", "healing", "mitigation"];

/// One match's figure for a "versus" row.
fn per_match(m: &MatchSummary, stat: &str) -> Option<f64> {
    if stat == "kda" {
        kda(&m.stats)
    } else {
        m.stats.get(stat)
    }
}

fn kda(s: &StatLine) -> Option<f64> {
    let (k, a, d) = (s.kills?, s.assists?, s.deaths?);
    Some((k + a) / d.max(1.0))
}

/// Days with matches, and the summary of `day` (`YYYY-MM-DD`; the newest day when
/// absent or unknown).
pub fn daily(
    rows: &[MatchSummary],
    details: &BTreeMap<String, MatchDetail>,
    day: Option<&str>,
    utc_offset_minutes: i32,
    session_gap_ms: i64,
) -> Daily {
    let mut timed: Vec<&MatchSummary> = rows.iter().filter(|m| m.started_at_ms.is_some()).collect();
    timed.sort_by_key(|m| m.started_at_ms);
    let day_n = |m: &MatchSummary| day_of(m.started_at_ms.unwrap_or_default(), utc_offset_minutes);

    let mut by_day: BTreeMap<i64, Vec<&MatchSummary>> = BTreeMap::new();
    for m in &timed {
        by_day.entry(day_n(m)).or_default().push(m);
    }
    let days: Vec<DayEntry> = by_day
        .iter()
        .rev()
        .map(|(d, ms)| {
            let mut record = Record::default();
            for m in ms {
                record.add(m.outcome);
            }
            DayEntry {
                day: date_of(*d),
                record,
            }
        })
        .collect();
    let chosen = day
        .and_then(|d| by_day.keys().copied().find(|k| date_of(*k) == d))
        .or_else(|| by_day.keys().next_back().copied());
    let Some(chosen) = chosen else {
        return Daily {
            days,
            summary: None,
        };
    };
    let today: Vec<&MatchSummary> = by_day[&chosen].clone();
    let earlier: Vec<&MatchSummary> = timed
        .iter()
        .copied()
        .filter(|m| day_n(m) < chosen)
        .collect();

    let owned: Vec<MatchSummary> = today.iter().map(|m| (*m).clone()).collect();
    let agg = aggregate(today.iter().copied());

    // Sittings.
    let mut sittings = 0;
    let mut last: Option<i64> = None;
    for m in &today {
        let at = m.started_at_ms.unwrap_or_default();
        if last.is_none_or(|l| at - l > session_gap_ms) {
            sittings += 1;
        }
        last = Some(at);
    }

    // Play time from stored details.
    let lengths: Vec<f64> = today
        .iter()
        .filter_map(|m| details.get(&m.id)?.duration_s)
        .filter(|s| *s > 0.0)
        .collect();

    let mut heroes = breakdown(&owned, Dimension::Hero);
    heroes.retain(|g| g.key != "unknown");
    heroes.truncate(LISTED);
    let mut maps = breakdown(&owned, Dimension::Map);
    maps.retain(|g| g.key != "unknown");
    maps.truncate(LISTED);
    let mut roles = breakdown(&owned, Dimension::Role);
    roles.retain(|g| g.key != "unknown");

    // Rank changes: the role's rating before its first match of the day (its last match
    // before, else the first of the day) to its last of the day.
    let mut rank_changes = Vec::new();
    for role in [Role::Tank, Role::Damage, Role::Support] {
        let sr = |m: &&MatchSummary| m.rank.as_ref().and_then(|r| r.skill_rating);
        let day_srs: Vec<i64> = today
            .iter()
            .filter(|m| m.role == role)
            .filter_map(sr)
            .collect();
        let Some(&to) = day_srs.last() else { continue };
        let from = earlier
            .iter()
            .rev()
            .filter(|m| m.role == role)
            .find_map(sr)
            .unwrap_or(day_srs[0]);
        rank_changes.push(RankChange { role, from, to });
    }

    let mut highlights = Vec::new();
    let about = |kind, stat: &str, value: f64, m: &MatchSummary, previous| Highlight {
        kind,
        stat: stat.into(),
        value,
        match_id: Some(m.id.clone()),
        hero: m.hero.clone(),
        map: m.map.clone(),
        previous,
    };
    // Top of the lobby.
    for stat in STATS {
        let n = today
            .iter()
            .filter(|m| {
                m.highlights.as_ref().is_some_and(|h| match stat {
                    "kills" => h.kills,
                    "damage" => h.damage,
                    "healing" => h.healing,
                    _ => h.mitigation,
                })
            })
            .count();
        if n > 0 {
            highlights.push(Highlight {
                kind: HighlightKind::LobbyTop,
                stat: stat.into(),
                value: n as f64,
                match_id: None,
                hero: None,
                map: None,
                previous: None,
            });
        }
    }
    // Best single matches, and records.
    for stat in STATS {
        let best = today
            .iter()
            .filter_map(|m| Some((m, m.stats.get(stat)?)))
            .filter(|(_, v)| *v > 0.0)
            .max_by(|a, b| a.1.total_cmp(&b.1));
        let Some((m, v)) = best else { continue };
        let before: Vec<f64> = earlier.iter().filter_map(|e| e.stats.get(stat)).collect();
        let prev = before.iter().copied().fold(f64::NEG_INFINITY, f64::max);
        if before.len() >= MIN_RECORD_HISTORY && v > prev {
            highlights.push(about(HighlightKind::PersonalRecord, stat, v, m, Some(prev)));
        } else {
            highlights.push(about(HighlightKind::DayBest, stat, v, m, None));
        }
    }
    if let Some((m, v)) = today
        .iter()
        .filter(|m| m.outcome == Outcome::Win)
        .filter_map(|m| Some((m, kda(&m.stats)?)))
        .max_by(|a, b| a.1.total_cmp(&b.1))
    {
        highlights.push(about(HighlightKind::BestMatch, "kda", v, m, None));
    }
    let mut streak = 0;
    let mut best_streak = 0;
    for m in &today {
        if m.outcome == Outcome::Win {
            streak += 1;
            best_streak = best_streak.max(streak);
        } else if m.outcome == Outcome::Loss {
            streak = 0;
        }
    }
    if best_streak >= 3 {
        highlights.push(Highlight {
            kind: HighlightKind::Streak,
            stat: String::new(),
            value: best_streak as f64,
            match_id: None,
            hero: None,
            map: None,
            previous: None,
        });
    }
    let deathless = today.iter().filter(|m| m.stats.deaths == Some(0.0)).count();
    if deathless > 0 {
        highlights.push(Highlight {
            kind: HighlightKind::Deathless,
            stat: String::new(),
            value: deathless as f64,
            match_id: None,
            hero: None,
            map: None,
            previous: None,
        });
    }
    let fleta = today
        .iter()
        .filter_map(|m| {
            let d = details.get(&m.id)?;
            let me = d.subject()?;
            let f = crate::analysis::fleta(
                me.stats.final_blows,
                crate::analysis::team_final_blows(&d.allies),
            )?;
            Some((m, f))
        })
        .max_by(|a, b| a.1.total_cmp(&b.1));
    if let Some((m, f)) = fleta {
        highlights.push(about(HighlightKind::BestFleta, "fleta", f, m, None));
    }

    // Against the usual: the day's main role, per match, over the month before.
    let main_role = roles.first().and_then(|g| {
        [Role::Tank, Role::Damage, Role::Support]
            .into_iter()
            .find(|r| {
                serde_json::to_value(r)
                    .ok()
                    .and_then(|v| v.as_str().map(String::from))
                    == Some(g.key.clone())
            })
    });
    let mut versus = Vec::new();
    if let Some(role) = main_role {
        let start = chosen * DAY_MS - i64::from(utc_offset_minutes) * 60_000;
        let usual: Vec<&MatchSummary> = earlier
            .iter()
            .copied()
            .filter(|m| {
                m.role == role && m.started_at_ms.unwrap_or_default() >= start - USUAL_DAYS * DAY_MS
            })
            .collect();
        let mine: Vec<&MatchSummary> = today.iter().copied().filter(|m| m.role == role).collect();
        if usual.len() >= MIN_USUAL {
            let mean = |ms: &[&MatchSummary], stat: &str| {
                let v: Vec<f64> = ms.iter().filter_map(|m| per_match(m, stat)).collect();
                (!v.is_empty()).then(|| (v.iter().sum::<f64>() / v.len() as f64, v.len()))
            };
            for stat in ["kills", "deaths", "damage", "healing", "mitigation", "kda"] {
                if let (Some((t, tn)), Some((u, un))) = (mean(&mine, stat), mean(&usual, stat))
                    && (t > 0.0 || u > 0.0)
                {
                    versus.push(Versus {
                        stat: stat.into(),
                        today: t,
                        usual: u,
                        today_n: tn,
                        usual_n: un,
                    });
                }
            }
        }
    }

    let mut match_ids: Vec<String> = today.iter().map(|m| m.id.clone()).collect();
    match_ids.reverse();
    Daily {
        days,
        summary: Some(DailySummary {
            day: date_of(chosen),
            aggregate: agg,
            sittings,
            first_ms: today.first().and_then(|m| m.started_at_ms),
            last_ms: today.last().and_then(|m| m.started_at_ms),
            play_s: (!lengths.is_empty()).then(|| lengths.iter().sum()),
            play_samples: lengths.len(),
            heroes,
            maps,
            roles,
            rank_changes,
            highlights,
            versus_role: main_role.filter(|_| !versus.is_empty()),
            versus,
            match_ids,
        }),
    }
}

/// Stored details keyed by match id, for [`daily`].
pub fn by_id(details: Vec<MatchDetail>) -> BTreeMap<String, MatchDetail> {
    details.into_iter().map(|d| (d.id.clone(), d)).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    const HOUR: i64 = 3_600_000;
    // 2026-10-22 00:00 in UTC+8.
    const DAY: i64 = 1_792_627_200_000 - 8 * HOUR;

    fn row(id: &str, at: i64, o: Outcome, kills: f64, deaths: f64, top: bool) -> MatchSummary {
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
            outcome: o,
            map: Some(EntityRef::new(EntityKind::Map, "1", Some("努巴尼".into()))),
            hero: Some(EntityRef::new(EntityKind::Hero, "h", Some("安娜".into()))),
            role: Role::Support,
            score: Score::default(),
            stats: StatLine {
                kills: Some(kills),
                assists: Some(10.0),
                deaths: Some(deaths),
                damage: Some(3000.0),
                healing: Some(9000.0),
                ..StatLine::default()
            },
            highlights: Some(Highlights {
                kills: false,
                damage: false,
                healing: top,
                mitigation: false,
            }),
            rank: Some(Rank {
                tier: None,
                division: None,
                score: None,
                skill_rating: Some(2400 + (at / HOUR) % 7 * 25),
                at_ms: None,
            }),
            hero_icon_url: None,
        }
    }

    #[test]
    fn dates_are_calendar_days_in_the_report_zone() {
        assert_eq!(date_of(0), "1970-01-01");
        assert_eq!(date_of(day_of(DAY, 480)), "2026-10-22");
        // 23:30 local is still the same day; 00:30 is the next.
        assert_eq!(
            date_of(day_of(DAY + 23 * HOUR + HOUR / 2, 480)),
            "2026-10-22"
        );
        assert_eq!(
            date_of(day_of(DAY + 24 * HOUR + HOUR / 2, 480)),
            "2026-10-23"
        );
    }

    #[test]
    fn a_day_says_how_it_went_and_what_stood_out() {
        let mut rows = Vec::new();
        // 25 earlier matches over the month before, never more than 20 kills.
        for k in 0..25 {
            rows.push(row(
                &format!("e{k}"),
                DAY - (k + 1) * 24 * HOUR,
                Outcome::Win,
                12.0 + (k % 8) as f64,
                6.0,
                false,
            ));
        }
        // The day: four wins in a row, a 0-death match, a 31-kill record, two lobby tops.
        rows.push(row("a", DAY + 19 * HOUR, Outcome::Win, 15.0, 4.0, true));
        rows.push(row(
            "b",
            DAY + 19 * HOUR + HOUR / 3,
            Outcome::Win,
            31.0,
            0.0,
            true,
        ));
        rows.push(row("c", DAY + 20 * HOUR, Outcome::Win, 18.0, 5.0, false));
        rows.push(row(
            "d",
            DAY + 20 * HOUR + HOUR / 3,
            Outcome::Win,
            9.0,
            7.0,
            false,
        ));
        rows.push(row("e", DAY + 23 * HOUR, Outcome::Loss, 8.0, 9.0, false));
        let v = daily(&rows, &BTreeMap::new(), None, 480, 2 * HOUR);
        assert_eq!(v.days[0].day, "2026-10-22");
        assert_eq!(v.days.len(), 26);
        let s = v.summary.unwrap();
        assert_eq!((s.aggregate.record.wins, s.aggregate.record.losses), (4, 1));
        assert_eq!(s.sittings, 2);
        assert_eq!(s.match_ids[0], "e");
        let find = |k: HighlightKind, stat: &str| {
            s.highlights
                .iter()
                .find(|h| h.kind == k && h.stat == stat)
                .cloned()
        };
        let rec = find(HighlightKind::PersonalRecord, "kills").unwrap();
        assert_eq!(
            (rec.value, rec.previous, rec.match_id.as_deref()),
            (31.0, Some(19.0), Some("b"))
        );
        assert_eq!(find(HighlightKind::LobbyTop, "healing").unwrap().value, 2.0);
        assert_eq!(find(HighlightKind::Streak, "").unwrap().value, 4.0);
        assert_eq!(find(HighlightKind::Deathless, "").unwrap().value, 1.0);
        assert_eq!(
            find(HighlightKind::BestMatch, "kda")
                .unwrap()
                .match_id
                .as_deref(),
            Some("b")
        );
        assert_eq!(s.versus_role, Some(Role::Support));
        assert!(
            s.versus
                .iter()
                .any(|x| x.stat == "kills" && x.usual_n == 25)
        );
        assert_eq!(s.rank_changes.len(), 1);
        // An earlier day by date.
        let past = daily(&rows, &BTreeMap::new(), Some("2026-10-21"), 480, 2 * HOUR)
            .summary
            .unwrap();
        assert_eq!(past.aggregate.record.matches, 1);
    }
}
