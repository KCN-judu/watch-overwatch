//! Who the player meets: the players seen most often in their stored matches, on their
//! side and against them; how the player does in a group against alone; and two
//! players' shared matches side by side.
//!
//! Only stored details count (the match list has no rosters). Groups come from
//! `friendBnetIds`: a teammate is in the player's group when either lists the other.
use crate::analysis::Record;
use crate::ir::*;
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, HashMap};

/// A player is listed from this many shared matches.
pub const MIN_SHARED: usize = 2;
/// Players listed.
pub const MAX_LISTED: usize = 50;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Mate {
    pub key: String,
    pub name: Option<String>,
    pub bnet_id: Option<String>,
    /// The player's results with them on their side, and against them.
    pub as_ally: Record,
    pub as_enemy: Record,
    /// Shared matches where they were in the player's group.
    pub in_party: usize,
    pub last_ms: Option<i64>,
    /// Shared matches, newest first.
    pub match_ids: Vec<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct People {
    /// Stored details of the player in the mode.
    pub details: usize,
    /// Most shared matches first.
    pub mates: Vec<Mate>,
    /// The player's results in a group (anyone on their side grouped with them) and alone.
    pub party: Record,
    pub solo: Record,
    /// Group size per stored match (1 = alone), for marking the match list.
    pub party_size: BTreeMap<String, usize>,
}

fn grouped(me: &Participant, p: &Participant) -> bool {
    p.bnet_id
        .as_ref()
        .is_some_and(|id| me.party_bnet_ids.contains(id))
        || me
            .bnet_id
            .as_ref()
            .is_some_and(|id| p.party_bnet_ids.contains(id))
}

fn key(p: &Participant) -> Option<String> {
    p.bnet_id.clone().or_else(|| p.name.clone())
}

/// The player's details of one mode, any order.
pub fn people(details: &[MatchDetail]) -> People {
    let mut sorted: Vec<&MatchDetail> = details.iter().collect();
    sorted.sort_by_key(|d| std::cmp::Reverse(d.started_at_ms));
    let mut out = People {
        details: sorted.len(),
        ..People::default()
    };
    let mut found: HashMap<String, Mate> = HashMap::new();
    for d in sorted {
        let Some(me) = d.subject() else { continue };
        let group = d
            .allies
            .iter()
            .filter(|p| !p.is_subject && grouped(me, p))
            .count();
        out.party_size.insert(d.id.clone(), group + 1);
        if group > 0 {
            out.party.add(d.outcome);
        } else {
            out.solo.add(d.outcome);
        }
        for (ally, team) in [(true, &d.allies), (false, &d.enemies)] {
            for p in team.iter().filter(|p| !p.is_subject) {
                let Some(k) = key(p) else { continue };
                let m = found.entry(k.clone()).or_insert_with(|| Mate {
                    key: k,
                    name: None,
                    bnet_id: p.bnet_id.clone(),
                    as_ally: Record::default(),
                    as_enemy: Record::default(),
                    in_party: 0,
                    last_ms: d.started_at_ms,
                    match_ids: Vec::new(),
                });
                if m.name.is_none() {
                    m.name = p.name.clone();
                }
                m.match_ids.push(d.id.clone());
                if ally {
                    m.as_ally.add(d.outcome);
                    m.in_party += usize::from(grouped(me, p));
                } else {
                    m.as_enemy.add(d.outcome);
                }
            }
        }
    }
    let mut mates: Vec<Mate> = found
        .into_values()
        .filter(|m| m.match_ids.len() >= MIN_SHARED)
        .collect();
    mates.sort_by(|a, b| {
        b.match_ids
            .len()
            .cmp(&a.match_ids.len())
            .then_with(|| b.in_party.cmp(&a.in_party))
            .then_with(|| b.last_ms.cmp(&a.last_ms))
    });
    mates.truncate(MAX_LISTED);
    out.mates = mates;
    out
}

/// One shared match, both players' lines.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SharedMatch {
    pub match_id: String,
    pub started_at_ms: Option<i64>,
    pub map: Option<EntityRef>,
    /// The player's result.
    pub outcome: Outcome,
    pub same_side: bool,
    pub grouped: bool,
    pub me_hero: Option<EntityRef>,
    pub me_role: Role,
    pub me: StatLine,
    pub them_hero: Option<EntityRef>,
    pub them_role: Role,
    pub them: StatLine,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct Duo {
    pub name: Option<String>,
    /// Newest first.
    pub matches: Vec<SharedMatch>,
    /// The player's results with them on their side, and in their other matches.
    pub with: Record,
    pub without: Record,
    pub against: Record,
}

/// The player's details of one mode against the player `other` (a `Mate::key`).
pub fn duo(details: &[MatchDetail], other: &str) -> Duo {
    let mut sorted: Vec<&MatchDetail> = details.iter().collect();
    sorted.sort_by_key(|d| std::cmp::Reverse(d.started_at_ms));
    let mut out = Duo::default();
    for d in sorted {
        let Some(me) = d.subject() else { continue };
        let find = |team: &[Participant]| {
            team.iter()
                .find(|p| !p.is_subject && key(p).as_deref() == Some(other))
                .cloned()
        };
        let (them, same_side) = match (find(&d.allies), find(&d.enemies)) {
            (Some(p), _) => (p, true),
            (None, Some(p)) => (p, false),
            (None, None) => {
                out.without.add(d.outcome);
                continue;
            }
        };
        if out.name.is_none() {
            out.name = them.name.clone();
        }
        if same_side {
            out.with.add(d.outcome);
        } else {
            out.without.add(d.outcome);
            out.against.add(d.outcome);
        }
        out.matches.push(SharedMatch {
            match_id: d.id.clone(),
            started_at_ms: d.started_at_ms,
            map: d.map.clone(),
            outcome: d.outcome,
            same_side,
            grouped: same_side && grouped(me, &them),
            me_hero: me.hero.clone(),
            me_role: me.role,
            me: me.stats.clone(),
            them_hero: them.hero.clone(),
            them_role: them.role,
            them: them.stats,
        });
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn p(id: &str, subject: bool, party: &[&str]) -> Participant {
        Participant {
            name: Some(format!("玩家{id}")),
            bnet_id: Some(id.into()),
            is_subject: subject,
            hero: None,
            hero_icon_url: None,
            role: Role::Support,
            stats: StatLine::default(),
            rank: None,
            career_rank: None,
            career_other_roles: false,
            fleta: None,
            perks: Vec::new(),
            party_bnet_ids: party.iter().map(|s| s.to_string()).collect(),
            endorsed_by_bnet_ids: Vec::new(),
            suspended: false,
            stadium: None,
        }
    }

    fn d(
        id: &str,
        at: i64,
        o: Outcome,
        allies: Vec<Participant>,
        enemies: Vec<Participant>,
    ) -> MatchDetail {
        MatchDetail {
            id: id.into(),
            mode: Mode::Competitive,
            map: None,
            outcome: o,
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

    fn sample() -> Vec<MatchDetail> {
        vec![
            // With friend "f" in a group, twice: a win and a loss.
            d(
                "1",
                1,
                Outcome::Win,
                vec![p("me", true, &["f"]), p("f", false, &[])],
                vec![p("x", false, &[])],
            ),
            d(
                "2",
                2,
                Outcome::Loss,
                vec![p("me", true, &[]), p("f", false, &["me"])],
                vec![p("x", false, &[])],
            ),
            // Alone, "f" on the other side.
            d(
                "3",
                3,
                Outcome::Win,
                vec![p("me", true, &[]), p("y", false, &[])],
                vec![p("f", false, &[])],
            ),
        ]
    }

    #[test]
    fn mates_count_sides_and_groups() {
        let v = people(&sample());
        assert_eq!(v.details, 3);
        let f = v.mates.iter().find(|m| m.key == "f").unwrap();
        assert_eq!(
            (f.as_ally.matches, f.as_enemy.matches, f.in_party),
            (2, 1, 2)
        );
        assert_eq!(f.match_ids, ["3", "2", "1"]);
        assert_eq!(f.name.as_deref(), Some("玩家f"));
        // "y" met once: not listed.
        assert!(v.mates.iter().all(|m| m.key != "y"));
        assert_eq!((v.party.matches, v.solo.matches), (2, 1));
        assert_eq!(v.party_size["1"], 2);
        assert_eq!(v.party_size["3"], 1);
    }

    #[test]
    fn a_duo_lists_shared_matches_and_compares_with_the_rest() {
        let v = duo(&sample(), "f");
        assert_eq!(v.matches.len(), 3);
        assert_eq!(v.matches[0].match_id, "3");
        assert!(!v.matches[0].same_side);
        assert!(v.matches[1].grouped);
        assert_eq!((v.with.wins, v.with.losses), (1, 1));
        assert_eq!((v.against.wins, v.without.matches), (1, 1));
    }
}
