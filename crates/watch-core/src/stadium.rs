//! Stadium builds: which powers and items players take on a hero, when, and how those
//! matches went; the commonest power sets; and one match round by round.
//!
//! The sample is the stored Stadium details: the player's own matches, or with
//! [`Scope::Everyone`] every player in them (each player-match counts once, on the side
//! they played). Stadium is never mixed with the other modes.
use crate::analysis::Record;
use crate::ir::*;
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, HashMap};

/// Power sets listed per hero.
pub const BUILDS_PER_HERO: usize = 6;
/// Matches listed under an entry for drilling down (the player's own, newest first).
pub const MATCHES_PER_ENTRY: usize = 20;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Scope {
    /// The player's own matches.
    Own,
    /// Everyone in the stored matches.
    Everyone,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct UpgradeStat {
    pub upgrade: EntityRef,
    /// The round it is usually taken in (1-based), where rounds are stored.
    pub round: Option<usize>,
    pub picks: usize,
    /// Share of the hero's player-matches that took it.
    pub pick_rate_pct: f64,
    pub record: Record,
    /// The player's own matches with it, newest first, for drilling down.
    pub match_ids: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct BuildStat {
    /// The set of powers, in pick order where known.
    pub powers: Vec<EntityRef>,
    pub record: Record,
    pub pick_rate_pct: f64,
    pub match_ids: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct HeroBuilds {
    pub hero: EntityRef,
    /// Player-matches in the sample, and how many of them are the player's own.
    pub matches: usize,
    pub own_matches: usize,
    pub record: Record,
    /// Entries with enough matches first, by the low end of their plausible win rate; the
    /// rest after, most picked first.
    pub powers: Vec<UpgradeStat>,
    pub items: Vec<UpgradeStat>,
    pub builds: Vec<BuildStat>,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct StadiumView {
    pub scope: Option<Scope>,
    /// Stored Stadium details the sample came from.
    pub details: usize,
    /// Most played (in the sample) first.
    pub heroes: Vec<HeroBuilds>,
}

/// One round of a match for the player: what they took that round and how it went.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RoundStep {
    /// 1-based.
    pub round: usize,
    pub won: Option<bool>,
    pub powers: Vec<EntityRef>,
    pub items: Vec<EntityRef>,
    /// Cash at the end of the round, where given.
    pub worth: Option<f64>,
}

/// Whether the team won round `i`. Round scores are either the round's own result or
/// the running total; the running total is recognised by adding up to the rounds played.
pub fn round_won(rounds: &[Round], i: usize) -> Option<bool> {
    let s = rounds.get(i)?.score;
    let (t, o) = (s.team?, s.opponent?);
    if t + o == i as i64 + 1 {
        let before = if i == 0 { 0 } else { rounds[i - 1].score.team? };
        return Some(t > before);
    }
    (t != o).then_some(t > o)
}

fn find<'a>(team: &'a [Participant], who: &Participant) -> Option<&'a Participant> {
    team.iter().find(|p| match (&p.bnet_id, &who.bnet_id) {
        (Some(a), Some(b)) => a == b,
        _ => p.is_subject && who.is_subject,
    })
}

fn known(e: &EntityRef) -> bool {
    !e.guid.is_empty() && e.guid != "0"
}

/// The round (0-based) each of a player's upgrades first shows up in, from the rounds'
/// rosters; empty when rounds are not stored.
fn first_rounds(detail: &MatchDetail, who: &Participant, ally: bool) -> HashMap<String, usize> {
    let mut out = HashMap::new();
    for (i, r) in detail.rounds.iter().enumerate() {
        let team = if ally { &r.allies } else { &r.enemies };
        let Some(build) = find(team, who).and_then(|p| p.stadium.as_ref()) else {
            continue;
        };
        for e in build.powers.iter().chain(&build.items) {
            out.entry(e.guid.clone()).or_insert(i);
        }
    }
    out
}

/// The player's match round by round.
pub fn timeline(detail: &MatchDetail) -> Vec<RoundStep> {
    if detail.mode != Mode::Stadium {
        return Vec::new();
    }
    let Some(me) = detail.subject() else {
        return Vec::new();
    };
    let mut seen = std::collections::HashSet::new();
    let mut out = Vec::new();
    for (i, r) in detail.rounds.iter().enumerate() {
        let build = find(&r.allies, me).and_then(|p| p.stadium.as_ref());
        let fresh = |list: &[EntityRef], seen: &mut std::collections::HashSet<String>| {
            list.iter()
                .filter(|e| known(e) && seen.insert(e.guid.clone()))
                .cloned()
                .collect::<Vec<_>>()
        };
        let (powers, items) = match build {
            Some(b) => (fresh(&b.powers, &mut seen), fresh(&b.items, &mut seen)),
            None => (Vec::new(), Vec::new()),
        };
        out.push(RoundStep {
            round: i + 1,
            won: round_won(&detail.rounds, i),
            powers,
            items,
            worth: build.and_then(|b| b.worth),
        });
    }
    out
}

fn flip(o: Outcome) -> Outcome {
    match o {
        Outcome::Win => Outcome::Loss,
        Outcome::Loss => Outcome::Win,
        other => other,
    }
}

struct Pick {
    upgrade: EntityRef,
    round: Option<usize>,
}

struct Entry {
    match_id: String,
    started_at_ms: Option<i64>,
    outcome: Outcome,
    own: bool,
    powers: Vec<Pick>,
    items: Vec<Pick>,
}

#[derive(Default)]
struct Tally {
    upgrade: Option<EntityRef>,
    record: Record,
    rounds: BTreeMap<usize, usize>,
    own: Vec<(Option<i64>, String)>,
    powers: Vec<EntityRef>,
}

impl Tally {
    fn add(&mut self, e: &Entry, round: Option<usize>) {
        self.record.add(e.outcome);
        if let Some(r) = round {
            *self.rounds.entry(r).or_default() += 1;
        }
        if e.own {
            self.own.push((e.started_at_ms, e.match_id.clone()));
        }
    }
    fn match_ids(&mut self) -> Vec<String> {
        self.own.sort_by_key(|o| std::cmp::Reverse(o.0));
        self.own
            .iter()
            .take(MATCHES_PER_ENTRY)
            .map(|(_, id)| id.clone())
            .collect()
    }
}

fn order(a: &Record, b: &Record) -> std::cmp::Ordering {
    let low = |r: &Record| r.win_rate_low_pct.unwrap_or(0.0);
    b.enough
        .cmp(&a.enough)
        .then_with(|| {
            if a.enough {
                low(b).total_cmp(&low(a))
            } else {
                std::cmp::Ordering::Equal
            }
        })
        .then_with(|| b.matches.cmp(&a.matches))
}

fn upgrades(entries: &[&Entry], items: bool) -> Vec<UpgradeStat> {
    let mut tallies: BTreeMap<String, Tally> = BTreeMap::new();
    for e in entries {
        for p in if items { &e.items } else { &e.powers } {
            let t = tallies.entry(p.upgrade.guid.clone()).or_default();
            t.upgrade.get_or_insert_with(|| p.upgrade.clone());
            t.add(e, p.round);
        }
    }
    let total = entries.len().max(1) as f64;
    let mut out: Vec<UpgradeStat> = tallies
        .into_values()
        .filter_map(|mut t| {
            let round = t
                .rounds
                .iter()
                .max_by_key(|(r, n)| (**n, std::cmp::Reverse(**r)))
                .map(|(r, _)| r + 1);
            Some(UpgradeStat {
                match_ids: t.match_ids(),
                upgrade: t.upgrade?,
                round,
                picks: t.record.matches,
                pick_rate_pct: 100.0 * t.record.matches as f64 / total,
                record: t.record,
            })
        })
        .collect();
    out.sort_by(|a, b| order(&a.record, &b.record));
    out
}

fn builds(entries: &[&Entry]) -> Vec<BuildStat> {
    let mut tallies: BTreeMap<Vec<String>, Tally> = BTreeMap::new();
    for e in entries.iter().filter(|e| !e.powers.is_empty()) {
        let mut key: Vec<String> = e.powers.iter().map(|p| p.upgrade.guid.clone()).collect();
        key.sort();
        let t = tallies.entry(key).or_default();
        if t.powers.is_empty() {
            let mut ordered: Vec<&Pick> = e.powers.iter().collect();
            ordered.sort_by_key(|p| p.round.unwrap_or(usize::MAX));
            t.powers = ordered.iter().map(|p| p.upgrade.clone()).collect();
        }
        t.add(e, None);
    }
    let total = entries.len().max(1) as f64;
    let mut out: Vec<BuildStat> = tallies
        .into_values()
        .map(|mut t| BuildStat {
            match_ids: t.match_ids(),
            pick_rate_pct: 100.0 * t.record.matches as f64 / total,
            powers: std::mem::take(&mut t.powers),
            record: t.record,
        })
        .collect();
    // Commonest sets first: a set is only worth comparing once it recurs.
    out.sort_by(|a, b| {
        b.record
            .matches
            .cmp(&a.record.matches)
            .then_with(|| order(&a.record, &b.record))
    });
    out.truncate(BUILDS_PER_HERO);
    out
}

/// Builds per hero over the stored Stadium `details`, for `subject` alone or everyone.
pub fn stadium(details: &[MatchDetail], subject: &str, scope: Scope) -> StadiumView {
    let mut by_hero: BTreeMap<String, (EntityRef, Vec<Entry>)> = BTreeMap::new();
    let mut used = 0;
    for d in details.iter().filter(|d| d.mode == Mode::Stadium) {
        let mine = d.subject().and_then(|p| p.bnet_id.as_deref()) == Some(subject)
            || d.allies
                .iter()
                .any(|p| p.bnet_id.as_deref() == Some(subject));
        if scope == Scope::Own && !mine {
            continue;
        }
        used += 1;
        let sides = [
            (true, &d.allies, d.outcome),
            (false, &d.enemies, flip(d.outcome)),
        ];
        for (ally, team, outcome) in sides {
            for p in team.iter() {
                let own = p.bnet_id.as_deref() == Some(subject);
                if scope == Scope::Own && !own {
                    continue;
                }
                let (Some(hero), Some(build)) = (&p.hero, &p.stadium) else {
                    continue;
                };
                let firsts = first_rounds(d, p, ally);
                let picks = |list: &[EntityRef]| {
                    list.iter()
                        .filter(|e| known(e))
                        .map(|e| Pick {
                            round: firsts.get(&e.guid).copied(),
                            upgrade: e.clone(),
                        })
                        .collect::<Vec<_>>()
                };
                by_hero
                    .entry(hero.guid.clone())
                    .or_insert_with(|| (hero.clone(), Vec::new()))
                    .1
                    .push(Entry {
                        match_id: d.id.clone(),
                        started_at_ms: d.started_at_ms,
                        outcome,
                        own,
                        powers: picks(&build.powers),
                        items: picks(&build.items),
                    });
            }
        }
    }
    let mut heroes: Vec<HeroBuilds> = by_hero
        .into_values()
        .map(|(hero, entries)| {
            let refs: Vec<&Entry> = entries.iter().collect();
            let mut record = Record::default();
            for e in &entries {
                record.add(e.outcome);
            }
            HeroBuilds {
                hero,
                matches: entries.len(),
                own_matches: entries.iter().filter(|e| e.own).count(),
                record,
                powers: upgrades(&refs, false),
                items: upgrades(&refs, true),
                builds: builds(&refs),
            }
        })
        .collect();
    heroes.sort_by(|a, b| {
        b.own_matches
            .cmp(&a.own_matches)
            .then_with(|| b.matches.cmp(&a.matches))
    });
    StadiumView {
        scope: Some(scope),
        details: used,
        heroes,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn up(guid: &str) -> EntityRef {
        EntityRef::new(
            EntityKind::StadiumUpgrade,
            guid,
            Some(format!("强化{guid}")),
        )
    }

    fn player(id: &str, subject: bool, powers: &[&str], items: &[&str]) -> Participant {
        Participant {
            name: None,
            bnet_id: Some(id.into()),
            is_subject: subject,
            hero: Some(EntityRef::new(EntityKind::Hero, "h", Some("安娜".into()))),
            hero_icon_url: None,
            role: Role::Support,
            stats: StatLine::default(),
            rank: None,
            career_rank: None,
            career_other_roles: false,
            fleta: None,
            perks: Vec::new(),
            party_bnet_ids: Vec::new(),
            endorsed_by_bnet_ids: Vec::new(),
            suspended: false,
            stadium: Some(StadiumBuild {
                worth: Some(1000.0),
                powers: powers.iter().map(|g| up(g)).collect(),
                items: items.iter().map(|g| up(g)).collect(),
            }),
        }
    }

    fn round(i: usize, team: i64, opponent: i64, me: Participant) -> Round {
        Round {
            index: i,
            map: None,
            score: Score {
                team: Some(team),
                opponent: Some(opponent),
            },
            duration_s: None,
            allies: vec![me],
            enemies: Vec::new(),
        }
    }

    fn detail(id: &str, outcome: Outcome, me: Participant, foe: Participant) -> MatchDetail {
        MatchDetail {
            id: id.into(),
            mode: Mode::Stadium,
            map: None,
            outcome,
            outcome_source: OutcomeSource::Provider,
            started_at_ms: Some(0),
            duration_s: None,
            score: Score::default(),
            bans: Bans::default(),
            subject_heroes: Vec::new(),
            allies: vec![me],
            enemies: vec![foe],
            rounds: Vec::new(),
        }
    }

    #[test]
    fn a_round_by_round_build_shows_what_came_when() {
        let mut d = detail(
            "m",
            Outcome::Win,
            player("me", true, &["p1", "p2"], &["i1", "0"]),
            player("x", false, &[], &[]),
        );
        d.rounds = vec![
            round(0, 1, 0, player("me", true, &["p1"], &["i1"])),
            round(1, 1, 1, player("me", true, &["p1"], &["i1"])),
            round(2, 2, 1, player("me", true, &["p1", "p2"], &["i1"])),
        ];
        let t = timeline(&d);
        assert_eq!(t.len(), 3);
        assert_eq!(t[0].won, Some(true));
        assert_eq!(t[1].won, Some(false));
        assert_eq!(t[2].won, Some(true));
        assert_eq!(t[0].powers[0].guid, "p1");
        assert!(t[1].powers.is_empty());
        assert_eq!(t[2].powers[0].guid, "p2");
        // And the pick round of p2 is the third.
        let v = stadium(&[d], "me", Scope::Own);
        let p2 = v.heroes[0]
            .powers
            .iter()
            .find(|u| u.upgrade.guid == "p2")
            .unwrap();
        assert_eq!(p2.round, Some(3));
    }

    #[test]
    fn everyone_counts_each_side_with_its_own_result() {
        let mut details = Vec::new();
        for k in 0..6 {
            details.push(detail(
                &format!("m{k}"),
                Outcome::Win,
                player("me", true, &["p1"], &[]),
                player(&format!("x{k}"), false, &["p9"], &[]),
            ));
        }
        let own = stadium(&details, "me", Scope::Own);
        assert_eq!(own.heroes[0].matches, 6);
        assert_eq!(own.heroes[0].powers.len(), 1);
        let all = stadium(&details, "me", Scope::Everyone);
        let h = &all.heroes[0];
        assert_eq!((h.matches, h.own_matches), (12, 6));
        let p1 = &h.powers.iter().find(|u| u.upgrade.guid == "p1").unwrap();
        let p9 = &h.powers.iter().find(|u| u.upgrade.guid == "p9").unwrap();
        assert_eq!((p1.record.wins, p9.record.losses), (6, 6));
        assert_eq!(p1.pick_rate_pct, 50.0);
        // Ranked by evidence: p1 (all won) before p9 (all lost); only own matches drill.
        assert_eq!(h.powers[0].upgrade.guid, "p1");
        assert_eq!(p1.match_ids.len(), 6);
        assert!(p9.match_ids.is_empty());
        assert_eq!(h.builds.len(), 2);
    }

    #[test]
    fn small_samples_follow_the_ranked_ones() {
        let mut details = Vec::new();
        for k in 0..6 {
            details.push(detail(
                &format!("a{k}"),
                if k < 3 { Outcome::Win } else { Outcome::Loss },
                player("me", true, &["common"], &[]),
                player("x", false, &[], &[]),
            ));
        }
        details.push(detail(
            "b",
            Outcome::Win,
            player("me", true, &["rare"], &[]),
            player("x", false, &[], &[]),
        ));
        let v = stadium(&details, "me", Scope::Own);
        let order: Vec<&str> = v.heroes[0]
            .powers
            .iter()
            .map(|u| u.upgrade.guid.as_str())
            .collect();
        assert_eq!(order, ["common", "rare"]);
        assert!(!v.heroes[0].powers[1].record.enough);
    }
}
