//! Lobby strength (对局强度), overall and per role.
//!
//! Each participant is rated on the 500-5000 skill-rating scale: the rank they
//! carried in the match when the provider supplies one (competitive, stadium),
//! otherwise their competitive career rank for the role they played in that
//! match (quick play; see `CollectPlan::lobby_ratings`). `overall` averages every
//! rated player; `tank` / `damage` / `support` average only players on that role.
use crate::analysis::Record;
use crate::ir::*;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

const ROLES: [Role; 3] = [Role::Tank, Role::Damage, Role::Support];

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct RoleMeans {
    pub overall: Option<f64>,
    pub tank: Option<f64>,
    pub damage: Option<f64>,
    pub support: Option<f64>,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct RoleCounts {
    pub overall: usize,
    pub tank: usize,
    pub damage: usize,
    pub support: usize,
}

/// `None` is the overall slot.
type Slot = Option<Role>;
const SLOTS: [Slot; 4] = [
    None,
    Some(Role::Tank),
    Some(Role::Damage),
    Some(Role::Support),
];

fn mean(values: &[f64]) -> Option<f64> {
    (!values.is_empty()).then(|| values.iter().sum::<f64>() / values.len() as f64)
}

impl RoleMeans {
    pub fn get(&self, slot: Slot) -> Option<f64> {
        match slot {
            None => self.overall,
            Some(Role::Tank) => self.tank,
            Some(Role::Damage) => self.damage,
            Some(Role::Support) => self.support,
            Some(_) => None,
        }
    }
    fn set(&mut self, slot: Slot, value: Option<f64>) {
        match slot {
            None => self.overall = value,
            Some(Role::Tank) => self.tank = value,
            Some(Role::Damage) => self.damage = value,
            Some(Role::Support) => self.support = value,
            Some(_) => {}
        }
    }
    fn from_rated(rated: &[(Role, f64)]) -> (Self, RoleCounts) {
        let mut means = Self::default();
        let mut counts = RoleCounts::default();
        for slot in SLOTS {
            let values: Vec<f64> = rated
                .iter()
                .filter(|(role, _)| slot.is_none_or(|s| s == *role))
                .map(|r| r.1)
                .collect();
            means.set(slot, mean(&values));
            let n = values.len();
            match slot {
                None => counts.overall = n,
                Some(Role::Tank) => counts.tank = n,
                Some(Role::Damage) => counts.damage = n,
                _ => counts.support = n,
            }
        }
        (means, counts)
    }
    /// Lowest and highest rating per slot.
    fn extremes(rated: &[(Role, f64)]) -> (Self, Self) {
        let mut lo = Self::default();
        let mut hi = Self::default();
        for slot in SLOTS {
            let values = rated
                .iter()
                .filter(|(role, _)| slot.is_none_or(|s| s == *role))
                .map(|r| r.1);
            lo.set(slot, values.clone().reduce(f64::min));
            hi.set(slot, values.reduce(f64::max));
        }
        (lo, hi)
    }
    /// `a - b` per slot where both sides are known.
    fn diff(a: &Self, b: &Self) -> Self {
        let mut out = Self::default();
        for slot in SLOTS {
            out.set(slot, a.get(slot).zip(b.get(slot)).map(|(x, y)| x - y));
        }
        out
    }
    /// Match-weighted mean of per-match means, per slot.
    fn average<'a>(items: impl Iterator<Item = &'a Self> + Clone) -> Self {
        let mut out = Self::default();
        for slot in SLOTS {
            let values: Vec<f64> = items.clone().filter_map(|m| m.get(slot)).collect();
            out.set(slot, mean(&values));
        }
        out
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RatingSource {
    InMatch,
    Career,
    Mixed,
    None,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SideStrength {
    pub mean: RoleMeans,
    /// Lowest and highest rating among the rated players, per slot: the spread
    /// behind the mean (a mean of 3000 can be five 3000s or 2000 and 4000s).
    #[serde(default)]
    pub min: RoleMeans,
    #[serde(default)]
    pub max: RoleMeans,
    pub rated: RoleCounts,
    /// Of the rated players, how many have no rank for the role they played and are
    /// rated by their ranks in other roles.
    #[serde(default)]
    pub other_role: usize,
    pub players: usize,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct MatchStrength {
    pub match_id: String,
    pub started_at_ms: Option<i64>,
    pub mode: Mode,
    pub outcome: Outcome,
    pub subject_role: Role,
    pub source: RatingSource,
    pub ally: SideStrength,
    pub enemy: SideStrength,
    /// Both teams together.
    pub lobby: RoleMeans,
    /// Ally minus enemy; positive means the subject's side was rated higher.
    pub diff: RoleMeans,
}

/// A participant's rating for the lobby: the rank the match reported, else the snapshot
/// taken for this match (`crate::snapshot`). Never a rank looked up later.
fn participant_rating(p: &Participant) -> Option<(f64, RatingSource, RatingFit)> {
    if let Some(sr) = p.rank.as_ref().and_then(|r| r.skill_rating) {
        return Some((sr as f64, RatingSource::InMatch, RatingFit::SameRole));
    }
    let sr = p.career_rank.as_ref()?.skill_rating?;
    let fit = if p.career_other_roles {
        RatingFit::OtherRoles
    } else {
        RatingFit::SameRole
    };
    Some((sr as f64, RatingSource::Career, fit))
}

pub fn match_strength(detail: &MatchDetail) -> MatchStrength {
    let mut sources = Vec::new();
    let mut side = |players: &[Participant]| {
        let mut other_role = 0;
        let rated: Vec<(Role, f64)> = players
            .iter()
            .filter_map(|p| {
                let (sr, source, fit) = participant_rating(p)?;
                sources.push(source);
                other_role += usize::from(fit == RatingFit::OtherRoles);
                Some((p.role, sr))
            })
            .collect();
        let (mean, rated_counts) = RoleMeans::from_rated(&rated);
        let (min, max) = RoleMeans::extremes(&rated);
        let strength = SideStrength {
            mean,
            min,
            max,
            rated: rated_counts,
            other_role,
            players: players.len(),
        };
        (strength, rated)
    };
    let (ally, mut both) = side(&detail.allies);
    let (enemy, enemy_rated) = side(&detail.enemies);
    both.extend(enemy_rated);
    let source = match (
        sources.contains(&RatingSource::InMatch),
        sources.contains(&RatingSource::Career),
    ) {
        (true, true) => RatingSource::Mixed,
        (true, false) => RatingSource::InMatch,
        (false, true) => RatingSource::Career,
        (false, false) => RatingSource::None,
    };
    MatchStrength {
        match_id: detail.id.clone(),
        started_at_ms: detail.started_at_ms,
        mode: detail.mode,
        outcome: detail.outcome,
        subject_role: detail.subject().map_or(Role::Unknown, |p| p.role),
        source,
        diff: RoleMeans::diff(&ally.mean, &enemy.mean),
        lobby: RoleMeans::from_rated(&both).0,
        ally,
        enemy,
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct StrengthGroup {
    pub mode: Mode,
    /// Role the subject played; `None` groups all of them.
    pub subject_role: Option<Role>,
    pub record: Record,
    pub lobby: RoleMeans,
    pub ally: RoleMeans,
    pub enemy: RoleMeans,
    pub diff: RoleMeans,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct LobbyStrength {
    /// Newest first. A match in which nobody could be rated is kept (source `none`, no
    /// means), so it shows as a gap; the groups below only count matches with a rating.
    pub matches: Vec<MatchStrength>,
    /// Stadium ranks are a separate ladder, so summaries never mix modes.
    pub by_mode: Vec<StrengthGroup>,
    pub by_subject_role: Vec<StrengthGroup>,
}

fn group(mode: Mode, subject_role: Option<Role>, items: &[&MatchStrength]) -> StrengthGroup {
    let mut record = Record::default();
    for m in items {
        record.add(m.outcome);
    }
    let it = items.iter().copied();
    StrengthGroup {
        mode,
        subject_role,
        record,
        lobby: RoleMeans::average(it.clone().map(|m| &m.lobby)),
        ally: RoleMeans::average(it.clone().map(|m| &m.ally.mean)),
        enemy: RoleMeans::average(it.clone().map(|m| &m.enemy.mean)),
        diff: RoleMeans::average(it.map(|m| &m.diff)),
    }
}

pub fn lobby_strength(details: &BTreeMap<String, MatchDetail>) -> LobbyStrength {
    let mut matches: Vec<MatchStrength> = details.values().map(match_strength).collect();
    matches.sort_by_key(|m| std::cmp::Reverse(m.started_at_ms));
    let mut out = LobbyStrength::default();
    for mode in Mode::ALL {
        let in_mode: Vec<&MatchStrength> = matches
            .iter()
            .filter(|m| m.mode == mode && m.source != RatingSource::None)
            .collect();
        if in_mode.is_empty() {
            continue;
        }
        out.by_mode.push(group(mode, None, &in_mode));
        for role in ROLES {
            let played: Vec<&MatchStrength> = in_mode
                .iter()
                .copied()
                .filter(|m| m.subject_role == role)
                .collect();
            if !played.is_empty() {
                out.by_subject_role.push(group(mode, Some(role), &played));
            }
        }
    }
    out.matches = matches;
    out
}

/// `2350.0` → `("Platinum", 2)`.
pub fn rating_tier(skill_rating: f64) -> Option<(&'static str, u8)> {
    let (tier, base) = crate::dashen::normalize::TIER_BASES
        .iter()
        .rev()
        .find(|(_, base)| skill_rating >= *base as f64)?;
    let steps = ((skill_rating - *base as f64) / 100.0)
        .floor()
        .clamp(0.0, 4.0) as u8;
    Some((tier, 5 - steps))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;

    fn rank(sr: i64) -> Rank {
        Rank {
            tier: None,
            division: None,
            score: None,
            skill_rating: Some(sr),
            at_ms: None,
        }
    }

    fn player(id: &str, role: Role, in_match: Option<i64>) -> Participant {
        Participant {
            name: None,
            bnet_id: Some(id.into()),
            is_subject: false,
            hero: None,
            hero_icon_url: None,
            role,
            stats: StatLine::default(),
            rank: in_match.map(rank),
            career_rank: None,
            career_other_roles: false,
            career_rank_at_ms: None,
            fleta: None,
            perks: Vec::new(),
            party_bnet_ids: Vec::new(),
            endorsed_by_bnet_ids: Vec::new(),
            suspended: false,
            stadium: None,
        }
    }

    fn subject(role: Role) -> Participant {
        Participant {
            is_subject: true,
            ..player("me", role, None)
        }
    }

    fn detail(
        id: &str,
        at: i64,
        mode: Mode,
        outcome: Outcome,
        allies: Vec<Participant>,
        enemies: Vec<Participant>,
    ) -> MatchDetail {
        MatchDetail {
            id: id.into(),
            mode,
            map: None,
            outcome,
            outcome_source: OutcomeSource::Provider,
            started_at_ms: Some(at),
            duration_s: None,
            score: Score::default(),
            bans: Bans::default(),
            subject_heroes: Vec::new(),
            allies,
            enemies,
            rounds: Vec::new(),
        }
    }

    fn rating(id: &str, roles: &[(Role, Option<u32>, i64)]) -> PlayerRating {
        PlayerRating {
            bnet_id: id.into(),
            name: None,
            roles: roles
                .iter()
                .map(|&(role, season, sr)| RoleRating {
                    role,
                    season,
                    rank: rank(sr),
                })
                .collect(),
        }
    }

    /// Snapshots taken from `ratings`, then the strength: the analysis sees only those.
    fn strength(d: &MatchDetail, ratings: &[PlayerRating]) -> MatchStrength {
        let by_id: HashMap<&str, &PlayerRating> =
            ratings.iter().map(|r| (r.bnet_id.as_str(), r)).collect();
        let mut d = d.clone();
        crate::snapshot::take(&mut d, &by_id, 0);
        match_strength(&d)
    }

    #[test]
    fn the_rank_in_the_match_wins_over_the_career_rank() {
        let d = detail(
            "m",
            1,
            Mode::Competitive,
            Outcome::Win,
            vec![subject(Role::Support), player("a", Role::Tank, Some(2400))],
            Vec::new(),
        );
        let s = strength(&d, &[rating("a", &[(Role::Tank, None, 4000)])]);
        assert_eq!(s.source, RatingSource::InMatch);
        assert_eq!(s.ally.mean.tank, Some(2400.0));
        assert_eq!(s.ally.rated.overall, 1);
        assert_eq!(s.ally.players, 2);
        assert_eq!(s.subject_role, Role::Support);
    }

    #[test]
    fn career_ranks_fill_in_and_other_roles_are_counted() {
        let d = detail(
            "m",
            1,
            Mode::Quick,
            Outcome::Win,
            vec![
                player("a", Role::Damage, None),
                player("b", Role::Damage, None),
            ],
            vec![player("c", Role::Support, None)],
        );
        let ratings = [
            rating("a", &[(Role::Damage, None, 3000)]),
            // No damage rank: the higher of this season's other ranks.
            rating(
                "b",
                &[(Role::Tank, None, 2000), (Role::Support, None, 2600)],
            ),
        ];
        let s = strength(&d, &ratings);
        assert_eq!(s.source, RatingSource::Career);
        assert_eq!(s.ally.mean.damage, Some(2800.0));
        assert_eq!(s.ally.min.damage, Some(2600.0));
        assert_eq!(s.ally.max.damage, Some(3000.0));
        assert_eq!(s.ally.other_role, 1);
        assert_eq!(s.enemy.rated.overall, 0);
        assert_eq!(s.enemy.mean.overall, None);
        assert_eq!(s.diff.overall, None);
    }

    #[test]
    fn mixed_sources_and_the_ally_minus_enemy_difference() {
        let d = detail(
            "m",
            1,
            Mode::Quick,
            Outcome::Loss,
            vec![player("a", Role::Tank, Some(2000))],
            vec![player("b", Role::Tank, None)],
        );
        let s = strength(&d, &[rating("b", &[(Role::Tank, None, 2500)])]);
        assert_eq!(s.source, RatingSource::Mixed);
        assert_eq!(s.diff.tank, Some(-500.0));
        assert_eq!(s.lobby.overall, Some(2250.0));
        assert_eq!(s.lobby.support, None);
    }

    #[test]
    fn current_season_rank_is_preferred_over_an_older_one() {
        let r = rating(
            "a",
            &[(Role::Tank, Some(20), 4000), (Role::Tank, None, 2100)],
        );
        assert_eq!(
            r.rating_for(Role::Tank),
            Some((2100.0, RatingFit::SameRole))
        );
        let old_only = rating("a", &[(Role::Support, Some(20), 1800)]);
        assert_eq!(
            old_only.rating_for(Role::Damage),
            Some((1800.0, RatingFit::OtherRoles))
        );
        assert_eq!(r.rating_for(Role::Unknown), None);
    }

    #[test]
    fn unrated_matches_stay_as_gaps_but_do_not_count_in_groups() {
        let mut details = BTreeMap::new();
        details.insert(
            "rated".into(),
            detail(
                "rated",
                2,
                Mode::Quick,
                Outcome::Win,
                vec![subject(Role::Tank), player("a", Role::Tank, Some(3000))],
                vec![player("b", Role::Tank, Some(2000))],
            ),
        );
        details.insert(
            "blank".into(),
            detail(
                "blank",
                3,
                Mode::Quick,
                Outcome::Loss,
                vec![subject(Role::Tank)],
                vec![player("c", Role::Tank, None)],
            ),
        );
        let out = lobby_strength(&details);
        let ids: Vec<&str> = out.matches.iter().map(|m| m.match_id.as_str()).collect();
        assert_eq!(ids, ["blank", "rated"]);
        assert_eq!(out.matches[0].source, RatingSource::None);
        assert_eq!(out.by_mode.len(), 1);
        assert_eq!(out.by_mode[0].record.matches, 1);
        assert_eq!(out.by_mode[0].diff.overall, Some(1000.0));
        assert_eq!(out.by_subject_role.len(), 1);
        assert_eq!(out.by_subject_role[0].subject_role, Some(Role::Tank));
    }

    #[test]
    fn modes_are_never_mixed() {
        let mut details = BTreeMap::new();
        for (id, mode) in [("q", Mode::Quick), ("s", Mode::Stadium)] {
            details.insert(
                id.into(),
                detail(
                    id,
                    1,
                    mode,
                    Outcome::Win,
                    vec![subject(Role::Damage), player("a", Role::Damage, Some(2000))],
                    Vec::new(),
                ),
            );
        }
        let out = lobby_strength(&details);
        let modes: Vec<Mode> = out.by_mode.iter().map(|g| g.mode).collect();
        assert_eq!(modes, [Mode::Quick, Mode::Stadium]);
        assert!(out.by_mode.iter().all(|g| g.record.matches == 1));
    }

    #[test]
    fn ratings_map_to_tiers_and_divisions() {
        assert_eq!(rating_tier(2350.0), Some(("Platinum", 2)));
        assert_eq!(rating_tier(2000.0), Some(("Platinum", 5)));
        assert_eq!(rating_tier(2499.0), Some(("Platinum", 1)));
        assert_eq!(rating_tier(5000.0), Some(("Champion", 1)));
        assert_eq!(rating_tier(499.0), None);
    }
}
