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
//! [`Lookups`], threaded through it; across runs it is the background job's own state.
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
    /// A request for the player failed in the current attempt.
    failed: bool,
    /// The current attempt ended with every request answered.
    answered: bool,
}

impl Lookups {
    /// A finished run from ranks already looked up.
    pub fn from_ratings(ratings: &HashMap<&str, &PlayerRating>) -> Self {
        let mut l = Self::default();
        for (id, r) in ratings {
            l.begin(id);
            l.answer(id, &r.roles);
            l.finish(id);
        }
        l
    }

    /// A player's ranks as the dataset lists them (`PlayerRating`): the ranked roles.
    pub fn rating(&self, id: &str, name: Option<String>) -> PlayerRating {
        PlayerRating {
            bnet_id: id.to_owned(),
            name,
            roles: self
                .ranks(id)
                .map(|r| {
                    r.iter()
                        .filter_map(|(role, s)| match s {
                            RankState::Ranked(rank) => Some(RoleRating {
                                role,
                                season: None,
                                rank: rank.clone(),
                            }),
                            _ => None,
                        })
                        .collect()
                })
                .unwrap_or_default(),
        }
    }

    /// This season's answer for a player: each role with a rank becomes ranked.
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

    /// Whether the player was asked and every request answered: nothing to ask again.
    /// A player whose request failed is not, so a later attempt asks again.
    pub fn known(&self, id: &str) -> bool {
        self.players.get(id).is_some_and(|l| l.answered)
    }

    /// An attempt for the player begins: a failure of an earlier one is forgotten.
    pub fn begin(&mut self, id: &str) {
        self.players.entry(id.to_owned()).or_default().failed = false;
    }

    /// A request for the player failed: the roles it would have answered stay unknown,
    /// and the player is asked again by a later attempt.
    pub fn failed(&mut self, id: &str) {
        self.players.entry(id.to_owned()).or_default().failed = true;
    }

    /// Players whose last attempt failed.
    pub fn failures(&self) -> usize {
        self.players.values().filter(|l| l.failed).count()
    }

    /// The player's attempt is over: with no failure, a role still without a rank this
    /// season has none (unranked); after a failure it stays querying, to be asked again.
    pub fn finish(&mut self, id: &str) {
        let l = self.players.entry(id.to_owned()).or_default();
        l.answered = !l.failed;
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
            let l = self.players.entry(id.clone()).or_default();
            l.ranks = RoleRanks::unranked();
            l.answered = true;
        }
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
    fn this_season_decides_and_a_failure_is_asked_again() {
        let mut l = Lookups::default();
        // This season ranks damage only: the other two are unranked, whatever earlier
        // seasons said.
        l.begin("a");
        l.answer("a", &[row(Role::Damage, 3000)]);
        l.finish("a");
        let a = l.ranks("a").unwrap();
        assert!(matches!(&a.damage, RankState::Ranked(r) if r.skill_rating == Some(3000)));
        assert_eq!(
            (&a.tank, &a.support),
            (&RankState::Unranked, &RankState::Unranked)
        );
        assert!(l.known("a"));
        // A request failed: nothing is concluded, and the player is asked again.
        l.begin("b");
        l.failed("b");
        l.finish("b");
        assert_eq!(l.ranks("b").unwrap(), &RoleRanks::default());
        assert!(!l.known("b"));
        assert_eq!(l.failures(), 1);
        // The next attempt answers: settled.
        l.begin("b");
        l.answer("b", &[row(Role::Tank, 2000)]);
        l.finish("b");
        assert!(l.known("b"));
        assert!(l.ranks("b").unwrap().settled());
        assert_eq!(l.failures(), 0);
        // No token: unranked everywhere, settled.
        l.unreachable(&["c".into()]);
        assert_eq!(l.ranks("c"), Some(&RoleRanks::unranked()));
    }
}
