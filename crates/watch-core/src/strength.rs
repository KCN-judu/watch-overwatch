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
use std::collections::{BTreeMap, HashMap};

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

fn participant_rating(
    p: &Participant,
    ratings: &HashMap<&str, &PlayerRating>,
) -> Option<(f64, RatingSource, RatingFit)> {
    if let Some(sr) = p.rank.as_ref().and_then(|r| r.skill_rating) {
        return Some((sr as f64, RatingSource::InMatch, RatingFit::SameRole));
    }
    let (sr, fit) = ratings.get(p.bnet_id.as_deref()?)?.rating_for(p.role)?;
    Some((sr, RatingSource::Career, fit))
}

pub fn match_strength(
    detail: &MatchDetail,
    ratings: &HashMap<&str, &PlayerRating>,
) -> MatchStrength {
    let mut sources = Vec::new();
    let mut side = |players: &[Participant]| {
        let mut other_role = 0;
        let rated: Vec<(Role, f64)> = players
            .iter()
            .filter_map(|p| {
                let (sr, source, fit) = participant_rating(p, ratings)?;
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

pub fn lobby_strength(
    details: &BTreeMap<String, MatchDetail>,
    ratings: &[PlayerRating],
) -> LobbyStrength {
    let by_id: HashMap<&str, &PlayerRating> =
        ratings.iter().map(|r| (r.bnet_id.as_str(), r)).collect();
    let mut matches: Vec<MatchStrength> = details
        .values()
        .map(|d| match_strength(d, &by_id))
        .collect();
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
