//! The one place that decides the rank a participant is shown with: the app draws it and
//! the analyses (lobby strength, peer benchmarks) count it, so a player is never drawn as
//! one rank and counted as another.
//!
//! From the rank the match reported, the three-role snapshot (`Participant::career`),
//! the role played and the mode:
//! 1. the match reported a rank: that one;
//! 2. the role played is ranked: that rank;
//! 3. the role played is still being looked up: querying;
//! 4. the role played has none (or is not known): the highest of the other roles, once
//!    every one of them is known; querying while any still is; unranked when none has one.
//!
//! Stadium has no competitive rank to look up, and a player without an id cannot be
//! looked up: both are unranked unless the match reported a rank.
use serde::Serialize;

use crate::ir::{Mode, Participant, Rank, RankState};

/// How a shown rank was reached.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Basis {
    /// Reported by the match itself.
    Match,
    /// The snapshot's rank in the role played.
    Role,
    /// None in the role played: the highest of the snapshot's other roles.
    OtherRoles,
}

/// What a participant is shown with: one of three states.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(tag = "state", rename_all = "snake_case")]
pub enum ShownRank<'a> {
    Ranked { rank: &'a Rank, basis: Basis },
    Unranked,
    Querying,
}

impl ShownRank<'_> {
    /// The rating the lobby counts, and whether it is borrowed from other roles.
    pub fn rating(&self) -> Option<(f64, bool)> {
        match self {
            ShownRank::Ranked { rank, basis } => {
                Some((rank.skill_rating? as f64, *basis == Basis::OtherRoles))
            }
            _ => None,
        }
    }
}

fn sr(state: &RankState) -> Option<(&Rank, i64)> {
    match state {
        RankState::Ranked(rank) => Some((rank, rank.skill_rating?)),
        _ => None,
    }
}

pub fn shown(p: &Participant, mode: Mode) -> ShownRank<'_> {
    if let Some(rank) = p.rank.as_ref() {
        return ShownRank::Ranked {
            rank,
            basis: Basis::Match,
        };
    }
    if mode == Mode::Stadium || p.bnet_id.is_none() {
        return ShownRank::Unranked;
    }
    match p.career.get(p.role) {
        Some(RankState::Ranked(rank)) => ShownRank::Ranked {
            rank,
            basis: Basis::Role,
        },
        Some(RankState::Querying) => ShownRank::Querying,
        Some(RankState::Unranked) | None => {
            let others: Vec<&RankState> = p
                .career
                .iter()
                .filter(|(role, _)| *role != p.role)
                .map(|(_, s)| s)
                .collect();
            if others.iter().any(|s| **s == RankState::Querying) {
                return ShownRank::Querying;
            }
            match others.into_iter().filter_map(sr).max_by_key(|(_, v)| *v) {
                Some((rank, _)) => ShownRank::Ranked {
                    rank,
                    basis: Basis::OtherRoles,
                },
                None => ShownRank::Unranked,
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ir::{Role, RoleRanks};

    fn rank(sr: i64) -> Rank {
        Rank {
            tier: None,
            division: None,
            score: None,
            skill_rating: Some(sr),
            at_ms: None,
        }
    }

    fn player(role: Role, career: RoleRanks) -> Participant {
        let mut p: Participant = serde_json::from_value(serde_json::json!({
            "name": "a", "bnet_id": "1", "is_subject": false, "hero": null,
            "hero_icon_url": null, "role": "tank", "stats": {}, "rank": null,
            "perks": [], "party_bnet_ids": [], "endorsed_by_bnet_ids": [],
            "suspended": false, "stadium": null,
        }))
        .unwrap();
        p.role = role;
        p.career = career;
        p
    }

    fn label(s: ShownRank<'_>) -> String {
        match s {
            ShownRank::Ranked { rank, basis } => format!("{basis:?} {:?}", rank.skill_rating),
            ShownRank::Unranked => "unranked".into(),
            ShownRank::Querying => "querying".into(),
        }
    }

    #[test]
    fn the_role_played_first_then_the_best_other_once_all_are_known() {
        let r = |s| RankState::Ranked(rank(s));
        let career = |tank, damage, support| RoleRanks {
            tank,
            damage,
            support,
        };
        let q = || RankState::Querying;
        let u = || RankState::Unranked;
        let show = |role, c| label(shown(&player(role, c), Mode::Quick));
        assert_eq!(
            show(Role::Tank, career(r(2400), q(), q())),
            "Role Some(2400)"
        );
        assert_eq!(show(Role::Tank, career(q(), r(3000), r(2000))), "querying");
        // No tank rank: the highest of the others, but only once both are known.
        assert_eq!(show(Role::Tank, career(u(), r(3000), q())), "querying");
        assert_eq!(
            show(Role::Tank, career(u(), r(2600), r(3100))),
            "OtherRoles Some(3100)"
        );
        assert_eq!(show(Role::Tank, career(u(), u(), u())), "unranked");
        // Role not known: the best of the three.
        assert_eq!(
            show(Role::Unknown, career(r(1800), u(), r(2200))),
            "OtherRoles Some(2200)"
        );
        // What it counts: the rating, and whether it is borrowed.
        let p = player(Role::Tank, career(u(), r(2600), u()));
        assert_eq!(shown(&p, Mode::Quick).rating(), Some((2600.0, true)));
    }

    #[test]
    fn the_match_rank_wins_and_stadium_or_an_unknown_player_is_unranked() {
        let mut p = player(Role::Tank, RoleRanks::default());
        assert_eq!(label(shown(&p, Mode::Stadium)), "unranked");
        p.bnet_id = None;
        assert_eq!(label(shown(&p, Mode::Quick)), "unranked");
        p.rank = Some(rank(3300));
        assert_eq!(label(shown(&p, Mode::Quick)), "Match Some(3300)");
        assert_eq!(shown(&p, Mode::Quick).rating(), Some((3300.0, false)));
    }
}
