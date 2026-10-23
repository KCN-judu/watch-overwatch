//! Rank snapshots: each participant's competitive rank as it was looked up for a match,
//! kept with the match itself (`Participant::career_rank` and `career_rank_at_ms`).
//!
//! The provider only tells a player's rank *now*, so the snapshot is the rank when the
//! match was read in (usually soon after it was played; for older matches, when they were
//! first looked up). Once taken it never changes: the same match shows the same lobby
//! however much later it is opened, and lobby strength is worked out from it alone.
use std::collections::HashMap;

use crate::ir::{CareerRank, MatchDetail, Participant, PlayerRating, Rank, RatingFit, Role};

/// Whether this participant still needs a snapshot: a known player in a known role,
/// with no rank reported by the match itself and none looked up yet.
pub fn wants(p: &Participant) -> bool {
    let in_match = p.rank.as_ref().is_some_and(|r| r.skill_rating.is_some());
    p.bnet_id.is_some() && p.role != Role::Unknown && !in_match && p.career == CareerRank::Querying
}

/// Whether any participant of the match still needs a snapshot, leaving out those who
/// cannot be looked up (`unreachable`: the match gave no token for them).
pub fn missing(detail: &MatchDetail, unreachable: &[String]) -> bool {
    detail.allies.iter().chain(&detail.enemies).any(|p| {
        wants(p)
            && !p
                .bnet_id
                .as_ref()
                .is_some_and(|id| unreachable.contains(id))
    })
}

/// How many participants of the match still need one (same rule as [`missing`]).
pub fn missing_count(detail: &MatchDetail, unreachable: &[String]) -> usize {
    detail
        .allies
        .iter()
        .chain(&detail.enemies)
        .filter(|p| {
            wants(p)
                && !p
                    .bnet_id
                    .as_ref()
                    .is_some_and(|id| unreachable.contains(id))
        })
        .count()
}

/// Takes the snapshot of every participant that wants one and whose ranks were looked up
/// (`ratings`), at `now_ms`: the rank in the role played, or the best of the others
/// ([`PlayerRating::rating_for`]); none at all is a snapshot too (looked up, unranked).
/// Answers whether anything was taken.
pub fn take(detail: &mut MatchDetail, ratings: &HashMap<&str, &PlayerRating>, now_ms: i64) -> bool {
    let mut taken = false;
    for p in detail.allies.iter_mut().chain(detail.enemies.iter_mut()) {
        if !wants(p) {
            continue;
        }
        let Some(player) = p.bnet_id.as_deref().and_then(|id| ratings.get(id)) else {
            continue;
        };
        let at_ms = Some(now_ms);
        p.career = match player.rating_for(p.role) {
            Some((_, RatingFit::SameRole)) => match player.for_role(p.role) {
                Some(r) => CareerRank::Ranked {
                    rank: r.rank.clone(),
                    other_roles: false,
                    at_ms,
                },
                None => CareerRank::Unranked { at_ms },
            },
            Some((best, RatingFit::OtherRoles)) => {
                // Tier and division from the rating, so the rank shows its emblem like
                // any other rank instead of only a label.
                let tier = crate::strength::rating_tier(best);
                CareerRank::Ranked {
                    rank: Rank {
                        tier: tier.map(|(t, _)| t.to_owned()),
                        division: tier.map(|(_, d)| d),
                        score: None,
                        skill_rating: Some(best.round() as i64),
                        at_ms: None,
                    },
                    other_roles: true,
                    at_ms,
                }
            }
            None => CareerRank::Unranked { at_ms },
        };
        taken = true;
    }
    taken
}

/// Keeps the snapshots of a match stored before when it is stored again (a detail read
/// anew never has them): by player, only where the new one has none.
pub fn carry(new: &mut MatchDetail, old: &MatchDetail) {
    let kept: HashMap<&str, &Participant> = old
        .allies
        .iter()
        .chain(&old.enemies)
        .filter(|p| p.career != CareerRank::Querying)
        .filter_map(|p| Some((p.bnet_id.as_deref()?, p)))
        .collect();
    for p in new.allies.iter_mut().chain(new.enemies.iter_mut()) {
        if p.career != CareerRank::Querying {
            continue;
        }
        if let Some(o) = p.bnet_id.as_deref().and_then(|id| kept.get(id)) {
            p.career = o.career.clone();
        }
    }
}

/// Those the match gave no token for cannot be looked up: unranked, so they are not
/// waited for.
pub fn unreachable(detail: &mut MatchDetail, ids: &[String], now_ms: i64) {
    for p in detail.allies.iter_mut().chain(detail.enemies.iter_mut()) {
        if wants(p) && p.bnet_id.as_ref().is_some_and(|id| ids.contains(id)) {
            p.career = CareerRank::Unranked {
                at_ms: Some(now_ms),
            };
        }
    }
}
