//! Rank tracks: the rating each role's matches reported, match by match; which season
//! each match belongs to; and the stretches where a role lost rating, with how strong
//! the opposing teams were in them.
//!
//! The match list carries no season. A season's matches are its career match count
//! (`season_matches`), taken from the newest end of the list: the newest `n` matches are
//! the current season's, the `m` before them the season before, and so on. Matches past
//! the oldest known count have no season.
use crate::ir::*;
use crate::strength::LobbyStrength;
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, HashMap};

/// A stretch counts as a drop from this many points lost (one division).
pub const DROP_POINTS: i64 = 100;
/// Drops listed, newest first.
pub const MAX_DROPS: usize = 3;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TrackPoint {
    pub match_id: String,
    pub at_ms: i64,
    pub outcome: Outcome,
    pub skill_rating: i64,
    pub tier: Option<String>,
    pub division: Option<u8>,
    pub season: Option<u32>,
    /// Enemy team's mean rating minus the player's team's, where the match's lobby
    /// strength is known.
    pub enemy_edge: Option<f64>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RoleTrack {
    pub role: Role,
    /// Oldest first.
    pub points: Vec<TrackPoint>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SeasonSpan {
    pub season: u32,
    /// First and last match of the season in the list.
    pub start_ms: i64,
    pub end_ms: i64,
    pub matches: usize,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Drop {
    pub role: Role,
    pub from_match_id: String,
    pub to_match_id: String,
    pub from_ms: i64,
    pub to_ms: i64,
    pub from_rating: i64,
    pub to_rating: i64,
    /// Matches after the peak, down to the trough.
    pub matches: usize,
    pub wins: usize,
    pub losses: usize,
    /// Of those, the ones with a known lobby strength, and their mean enemy edge.
    pub rated: usize,
    pub mean_enemy_edge: Option<f64>,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct RankTrack {
    pub roles: Vec<RoleTrack>,
    /// Newest first.
    pub seasons: Vec<SeasonSpan>,
    /// Newest first.
    pub drops: Vec<Drop>,
}

/// `rows` in any order; `season_matches` is each season's career match count.
pub fn rank_track(
    rows: &[MatchSummary],
    season_matches: &BTreeMap<u32, usize>,
    current: u32,
    strength: Option<&LobbyStrength>,
) -> RankTrack {
    let mut newest: Vec<&MatchSummary> =
        rows.iter().filter(|m| m.started_at_ms.is_some()).collect();
    newest.sort_by_key(|m| std::cmp::Reverse(m.started_at_ms));

    // Seasons from the newest end, while counts are known and consecutive.
    let mut season_of: HashMap<&str, u32> = HashMap::new();
    let mut seasons = Vec::new();
    let mut at = 0;
    let mut s = current;
    while let Some(&n) = season_matches.get(&s) {
        let part = &newest[at.min(newest.len())..(at + n).min(newest.len())];
        if let (Some(last), Some(first)) = (part.first(), part.last()) {
            seasons.push(SeasonSpan {
                season: s,
                start_ms: first.started_at_ms.unwrap_or_default(),
                end_ms: last.started_at_ms.unwrap_or_default(),
                matches: part.len(),
            });
        }
        for m in part {
            season_of.insert(m.id.as_str(), s);
        }
        at += n;
        if at >= newest.len() || s == 0 {
            break;
        }
        s -= 1;
    }

    let edge: HashMap<&str, f64> = strength
        .map(|st| {
            st.matches
                .iter()
                .filter_map(|m| Some((m.match_id.as_str(), -m.diff.overall?)))
                .collect()
        })
        .unwrap_or_default();

    let mut by_role: BTreeMap<Role, Vec<TrackPoint>> = BTreeMap::new();
    for m in newest.iter().rev() {
        let Some(sr) = m.rank.as_ref().and_then(|r| r.skill_rating) else {
            continue;
        };
        let rank = m.rank.as_ref().unwrap();
        by_role.entry(m.role).or_default().push(TrackPoint {
            match_id: m.id.clone(),
            at_ms: m.started_at_ms.unwrap_or_default(),
            outcome: m.outcome,
            skill_rating: sr,
            tier: rank.tier.clone(),
            division: rank.division,
            season: season_of.get(m.id.as_str()).copied(),
            enemy_edge: edge.get(m.id.as_str()).copied(),
        });
    }
    let roles: Vec<RoleTrack> = by_role
        .into_iter()
        .map(|(role, points)| RoleTrack { role, points })
        .collect();
    let mut drops: Vec<Drop> = roles.iter().flat_map(drops_of).collect();
    drops.sort_by_key(|d| std::cmp::Reverse(d.to_ms));
    drops.truncate(MAX_DROPS);
    RankTrack {
        roles,
        seasons,
        drops,
    }
}

/// Peak-to-trough stretches of one role losing at least [`DROP_POINTS`], within a season.
fn drops_of(track: &RoleTrack) -> Vec<Drop> {
    let p = &track.points;
    let mut out = Vec::new();
    let mut i = 0;
    while i + 1 < p.len() {
        // Walk to the next local peak, then down to the trough after it.
        while i + 1 < p.len()
            && p[i + 1].skill_rating >= p[i].skill_rating
            && p[i + 1].season == p[i].season
        {
            i += 1;
        }
        let peak = i;
        while i + 1 < p.len()
            && p[i + 1].skill_rating <= p[i].skill_rating
            && p[i + 1].season == p[i].season
        {
            i += 1;
        }
        let trough = i;
        if trough == peak {
            i += 1;
            continue;
        }
        let lost = p[peak].skill_rating - p[trough].skill_rating;
        if lost >= DROP_POINTS {
            let stretch = &p[peak + 1..=trough];
            let edges: Vec<f64> = stretch.iter().filter_map(|t| t.enemy_edge).collect();
            out.push(Drop {
                role: track.role,
                from_match_id: p[peak].match_id.clone(),
                to_match_id: p[trough].match_id.clone(),
                from_ms: p[peak].at_ms,
                to_ms: p[trough].at_ms,
                from_rating: p[peak].skill_rating,
                to_rating: p[trough].skill_rating,
                matches: stretch.len(),
                wins: stretch.iter().filter(|t| t.outcome == Outcome::Win).count(),
                losses: stretch
                    .iter()
                    .filter(|t| t.outcome == Outcome::Loss)
                    .count(),
                rated: edges.len(),
                mean_enemy_edge: (!edges.is_empty())
                    .then(|| edges.iter().sum::<f64>() / edges.len() as f64),
            });
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn row(id: &str, at: i64, role: Role, sr: Option<i64>, outcome: Outcome) -> MatchSummary {
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
            map: None,
            hero: None,
            role,
            score: Score::default(),
            stats: StatLine::default(),
            highlights: None,
            rank: sr.map(|sr| Rank {
                tier: Some("Gold".into()),
                division: Some(3),
                score: None,
                skill_rating: Some(sr),
                at_ms: None,
            }),
            hero_icon_url: None,
        }
    }

    #[test]
    fn seasons_are_counted_back_from_the_newest_match() {
        let rows: Vec<MatchSummary> = (0..10)
            .map(|k| row(&format!("m{k}"), k, Role::Support, Some(2000), Outcome::Win))
            .collect();
        let counts = BTreeMap::from([(25, 4), (24, 3)]);
        let t = rank_track(&rows, &counts, 25, None);
        let s: Vec<(u32, usize, i64, i64)> = t
            .seasons
            .iter()
            .map(|s| (s.season, s.matches, s.start_ms, s.end_ms))
            .collect();
        assert_eq!(s, [(25, 4, 6, 9), (24, 3, 3, 5)]);
        let p = &t.roles[0].points;
        assert_eq!(p[9].season, Some(25));
        assert_eq!(p[3].season, Some(24));
        assert_eq!(p[2].season, None);
    }

    #[test]
    fn a_drop_says_how_strong_the_other_side_was() {
        let srs = [2000, 2050, 2100, 2060, 2010, 1980, 1990];
        let rows: Vec<MatchSummary> = srs
            .iter()
            .enumerate()
            .map(|(k, sr)| {
                let o = if (3..=5).contains(&k) {
                    Outcome::Loss
                } else {
                    Outcome::Win
                };
                row(&format!("m{k}"), k as i64, Role::Damage, Some(*sr), o)
            })
            .collect();
        let t = rank_track(&rows, &BTreeMap::new(), 25, None);
        assert_eq!(t.drops.len(), 1);
        let d = &t.drops[0];
        assert_eq!((d.from_rating, d.to_rating, d.matches), (2100, 1980, 3));
        assert_eq!((d.wins, d.losses), (0, 3));
        assert_eq!(d.from_match_id, "m2");
        assert_eq!(d.mean_enemy_edge, None);
    }

    #[test]
    fn roles_have_their_own_tracks_and_unrated_matches_are_left_out() {
        let rows = [
            row("a", 1, Role::Tank, Some(2500), Outcome::Win),
            row("b", 2, Role::Support, Some(1800), Outcome::Win),
            row("c", 3, Role::Tank, None, Outcome::Loss),
        ];
        let t = rank_track(&rows, &BTreeMap::new(), 25, None);
        assert_eq!(t.roles.len(), 2);
        assert_eq!(t.roles.iter().map(|r| r.points.len()).sum::<usize>(), 2);
    }
}
