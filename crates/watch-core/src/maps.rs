//! Maps grouped by mode type (escort, control, push …), each with its record, how long
//! its matches ran and the heroes played on it.
//!
//! The mode type is the catalog's (`mapList[].mode`); the caller passes it in, so this
//! module stays free of catalog knowledge. The match list says nothing about attack or
//! defence, so maps are not split by side.
use crate::analysis::{Aggregate, Dimension, Group, Record, aggregate, breakdown};
use crate::ir::*;
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, HashMap};

/// Heroes listed per map.
pub const HEROES_PER_MAP: usize = 5;

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct MapsView {
    /// Most played first.
    pub modes: Vec<ModeGroup>,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct ModeGroup {
    /// The catalog's mode type, `None` for maps it does not know.
    pub mode: Option<String>,
    pub record: Record,
    /// Maps with enough matches first, by the low end of their plausible win rate; then
    /// the rest, most played first, with `ranked` false.
    pub maps: Vec<MapRow>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct MapRow {
    pub map: EntityRef,
    /// Its stable id (what the overview's groups and findings use).
    pub key: String,
    pub aggregate: Aggregate,
    /// Mean length of its matches with a stored detail, and how many those were.
    pub duration_s: Option<f64>,
    pub duration_samples: usize,
    /// Most played heroes on it, at most [`HEROES_PER_MAP`].
    pub heroes: Vec<Group>,
    /// Has enough matches to take part in the order.
    pub ranked: bool,
}

/// `durations` maps a match id to its length in seconds, where a detail is stored.
pub fn maps(
    rows: &[MatchSummary],
    durations: &HashMap<String, f64>,
    mode_of: impl Fn(&EntityRef) -> Option<String>,
) -> MapsView {
    let mut by_map: BTreeMap<String, (EntityRef, Vec<MatchSummary>)> = BTreeMap::new();
    for m in rows {
        let Some(map) = &m.map else { continue };
        by_map
            .entry(map.stable_id())
            .or_insert_with(|| (map.clone(), Vec::new()))
            .1
            .push(m.clone());
    }
    let mut by_mode: BTreeMap<Option<String>, Vec<MapRow>> = BTreeMap::new();
    for (key, (map, rows)) in by_map {
        let lengths: Vec<f64> = rows
            .iter()
            .filter_map(|m| durations.get(&m.id).copied())
            .filter(|s| *s > 0.0)
            .collect();
        let mut heroes = breakdown(&rows, Dimension::Hero);
        heroes.retain(|g| g.key != "unknown");
        heroes.truncate(HEROES_PER_MAP);
        let aggregate = aggregate(&rows);
        let row = MapRow {
            ranked: aggregate.record.enough,
            key,
            aggregate,
            duration_s: (!lengths.is_empty())
                .then(|| lengths.iter().sum::<f64>() / lengths.len() as f64),
            duration_samples: lengths.len(),
            heroes,
            map: map.clone(),
        };
        by_mode.entry(mode_of(&map)).or_default().push(row);
    }
    let mut modes: Vec<ModeGroup> = by_mode
        .into_iter()
        .map(|(mode, mut maps)| {
            maps.sort_by(|a, b| {
                let low = |r: &MapRow| r.aggregate.record.win_rate_low_pct.unwrap_or(0.0);
                b.ranked
                    .cmp(&a.ranked)
                    .then_with(|| {
                        if a.ranked {
                            low(b).total_cmp(&low(a))
                        } else {
                            std::cmp::Ordering::Equal
                        }
                    })
                    .then_with(|| b.aggregate.record.matches.cmp(&a.aggregate.record.matches))
            });
            let mut record = Record::default();
            for m in rows.iter().filter(|m| {
                m.map
                    .as_ref()
                    .is_some_and(|e| maps.iter().any(|r| r.key == e.stable_id()))
            }) {
                record.add(m.outcome);
            }
            ModeGroup { mode, record, maps }
        })
        .collect();
    // Unknown mode type last, whatever its size.
    modes.sort_by_key(|g| (g.mode.is_none(), std::cmp::Reverse(g.record.matches)));
    MapsView { modes }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn row(id: &str, map: &str, hero: &str, outcome: Outcome) -> MatchSummary {
        MatchSummary {
            id: id.into(),
            started_at_ms: Some(0),
            kind: MatchKind {
                mode: Mode::Competitive,
                queue: Queue::RoleQueue,
                ranked: None,
                provider_mode: None,
                instance_type: None,
            },
            outcome,
            map: Some(EntityRef::new(
                EntityKind::Map,
                map,
                Some(format!("地图{map}")),
            )),
            hero: Some(EntityRef::new(
                EntityKind::Hero,
                hero,
                Some(format!("英雄{hero}")),
            )),
            role: Role::Support,
            score: Score::default(),
            stats: StatLine::default(),
            highlights: None,
            rank: None,
            hero_icon_url: None,
        }
    }

    fn mode_of(e: &EntityRef) -> Option<String> {
        match e.guid.as_str() {
            "1" | "2" | "3" => Some("运载目标".into()),
            "4" => Some("占领要点".into()),
            _ => None,
        }
    }

    #[test]
    fn maps_sit_under_their_mode_and_short_samples_are_not_ranked() {
        let mut rows = Vec::new();
        // Map 1: 6 of 8; map 2: 2 of 8; map 3: 2 wins only; map 4: 1 win; map 9: unknown type.
        for k in 0..8 {
            let o = if k < 6 { Outcome::Win } else { Outcome::Loss };
            rows.push(row(&format!("a{k}"), "1", "1", o));
            let o = if k < 2 { Outcome::Win } else { Outcome::Loss };
            rows.push(row(&format!("b{k}"), "2", "2", o));
        }
        rows.push(row("c0", "3", "1", Outcome::Win));
        rows.push(row("c1", "3", "1", Outcome::Win));
        rows.push(row("d0", "4", "1", Outcome::Win));
        rows.push(row("e0", "9", "1", Outcome::Win));
        let durations = HashMap::from([("a0".to_string(), 600.0), ("a1".to_string(), 900.0)]);
        let v = maps(&rows, &durations, mode_of);
        let modes: Vec<Option<&str>> = v.modes.iter().map(|g| g.mode.as_deref()).collect();
        assert_eq!(modes, [Some("运载目标"), Some("占领要点"), None]);
        let escort = &v.modes[0];
        assert_eq!(escort.record.matches, 18);
        let order: Vec<&str> = escort.maps.iter().map(|m| m.map.guid.as_str()).collect();
        assert_eq!(order, ["1", "2", "3"]);
        assert!(escort.maps[0].ranked && escort.maps[1].ranked && !escort.maps[2].ranked);
        assert_eq!(escort.maps[0].duration_s, Some(750.0));
        assert_eq!(escort.maps[0].duration_samples, 2);
        assert_eq!(escort.maps[0].heroes[0].label.as_deref(), Some("英雄1"));
    }
}
