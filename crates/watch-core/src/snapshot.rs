//! Rank snapshots: each participant's competitive ranks in the three roles as they were
//! looked up for a match, kept with the match itself (`Participant::career`).
//!
//! The provider only tells a player's ranks *now*, so the snapshot is the ranks when the
//! match was read in (usually soon after it was played; for older matches, when they were
//! first looked up). A role once known (ranked or unranked) never changes: the same match
//! shows the same lobby however much later it is opened. What a participant is shown with
//! is worked out from it by `crate::rank_view`.
//!
//! The values carry only states. Everything about the lookup itself (which answers came,
//! which requests failed, who cannot be looked up) is the state of one lookup run,
//! [`Lookups`], threaded through it; across runs it is the rank cache and its times.
use std::collections::HashMap;

use crate::ir::{MatchDetail, Participant, PlayerRating, RankState, Role, RoleRanks, RoleRating};

/// Whether this participant's snapshot still has a role to look up: a known player whose
/// rank the match did not report.
pub fn wants(p: &Participant) -> bool {
    p.bnet_id.is_some() && p.rank.is_none() && !p.career.settled()
}

/// Whether any participant of the match still has a role to look up.
pub fn missing(detail: &MatchDetail) -> bool {
    detail.allies.iter().chain(&detail.enemies).any(wants)
}

/// Fills the roles still being looked up with what is known now; known roles stay.
fn merge(into: &mut RoleRanks, from: &RoleRanks) {
    for role in Role::PLAYABLE {
        if let (Some(slot), Some(known)) = (into.get_mut(role), from.get(role))
            && *slot == RankState::Querying
        {
            *slot = known.clone();
        }
    }
}

/// Keeps the snapshots of a match stored before when it is stored again (a detail read
/// anew has none): by player, role by role.
pub fn carry(new: &mut MatchDetail, old: &MatchDetail) {
    let kept: HashMap<&str, &RoleRanks> = old
        .allies
        .iter()
        .chain(&old.enemies)
        .filter_map(|p| Some((p.bnet_id.as_deref()?, &p.career)))
        .collect();
    for p in new.allies.iter_mut().chain(new.enemies.iter_mut()) {
        if let Some(old) = p.bnet_id.as_deref().and_then(|id| kept.get(id)) {
            merge(&mut p.career, old);
        }
    }
}

/// The state of one lookup run: for each player, the roles known so far and whether a
/// request for them failed. Answers are folded in as they come ([`Lookups::answer`]);
/// [`Lookups::finish`] then settles a player whose every request got an answer.
#[derive(Debug, Default)]
pub struct Lookups {
    players: HashMap<String, Lookup>,
}

#[derive(Debug, Default)]
struct Lookup {
    ranks: RoleRanks,
    failed: bool,
}

impl Lookups {
    /// A finished run from ranks already looked up (each player's newest season first).
    pub fn known(ratings: &HashMap<&str, &PlayerRating>) -> Self {
        let mut l = Self::default();
        for (id, r) in ratings {
            l.answer(id, &r.roles);
            l.finish(id);
        }
        l
    }

    /// A season's answer for a player: each role with a rank becomes ranked, unless a
    /// newer season (folded in earlier) already gave it one.
    pub fn answer(&mut self, id: &str, rows: &[RoleRating]) {
        let l = self.players.entry(id.to_owned()).or_default();
        for r in rows {
            if let Some(slot) = l.ranks.get_mut(r.role)
                && *slot == RankState::Querying
                && r.rank.skill_rating.is_some()
            {
                *slot = RankState::Ranked(r.rank.clone());
            }
        }
    }

    /// A request for the player failed: the roles it would have answered stay unknown.
    pub fn failed(&mut self, id: &str) {
        self.players.entry(id.to_owned()).or_default().failed = true;
    }

    /// Every season that could answer for the player has been asked: with no failure, a
    /// role still without a rank has none (unranked); after a failure it stays querying,
    /// to be asked again another time.
    pub fn finish(&mut self, id: &str) {
        let l = self.players.entry(id.to_owned()).or_default();
        if !l.failed {
            for role in Role::PLAYABLE {
                if let Some(slot) = l.ranks.get_mut(role)
                    && *slot == RankState::Querying
                {
                    *slot = RankState::Unranked;
                }
            }
        }
    }

    /// The match gave no token for these players: they cannot be looked up, and count as
    /// unranked in every role.
    pub fn unreachable(&mut self, ids: &[String]) {
        for id in ids {
            self.players.entry(id.clone()).or_default().ranks = RoleRanks::unranked();
        }
    }

    /// Whether every role of this player is ranked already, so an older season is not
    /// needed.
    pub fn complete(&self, id: &str) -> bool {
        self.players.get(id).is_some_and(|l| {
            l.ranks
                .iter()
                .all(|(_, s)| matches!(s, RankState::Ranked(_)))
        })
    }

    /// What is known of a player so far (after [`Lookups::finish`], their snapshot).
    pub fn ranks(&self, id: &str) -> Option<&RoleRanks> {
        self.players.get(id).map(|l| &l.ranks)
    }

    /// Writes into every participant still looking for a role what this run found out.
    /// Answers whether anything changed.
    pub fn take(&self, detail: &mut MatchDetail) -> bool {
        let mut changed = false;
        for p in detail.allies.iter_mut().chain(detail.enemies.iter_mut()) {
            if !wants(p) {
                continue;
            }
            let Some(l) = p.bnet_id.as_deref().and_then(|id| self.players.get(id)) else {
                continue;
            };
            let before = p.career.clone();
            merge(&mut p.career, &l.ranks);
            changed |= p.career != before;
        }
        changed
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ir::Rank;

    fn row(role: Role, sr: i64) -> RoleRating {
        RoleRating {
            role,
            season: None,
            rank: Rank {
                tier: None,
                division: None,
                score: None,
                skill_rating: Some(sr),
                at_ms: None,
            },
        }
    }

    #[test]
    fn a_newer_season_wins_and_a_failure_leaves_the_rest_unknown() {
        let mut l = Lookups::default();
        // This season: damage only; last season: damage and support.
        l.answer("a", &[row(Role::Damage, 3000)]);
        l.answer("a", &[row(Role::Damage, 2500), row(Role::Support, 2200)]);
        l.finish("a");
        let a = l.ranks("a").unwrap();
        assert!(matches!(&a.damage, RankState::Ranked(r) if r.skill_rating == Some(3000)));
        assert!(matches!(&a.support, RankState::Ranked(r) if r.skill_rating == Some(2200)));
        assert_eq!(a.tank, RankState::Unranked);
        // A request failed: what did not answer stays to be asked again.
        l.answer("b", &[row(Role::Tank, 2000)]);
        l.failed("b");
        l.finish("b");
        let b = l.ranks("b").unwrap();
        assert!(matches!(b.tank, RankState::Ranked(_)));
        assert_eq!(b.damage, RankState::Querying);
        assert!(!b.settled());
        // No token: unranked everywhere, settled.
        l.unreachable(&["c".into()]);
        assert_eq!(l.ranks("c"), Some(&RoleRanks::unranked()));
    }
}
