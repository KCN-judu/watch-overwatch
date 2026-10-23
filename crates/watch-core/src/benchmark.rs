//! Peer benchmarks (同侪基准): how a player's typical match on a hero compares with other
//! players on that hero, at about their rank, in the matches stored on this machine.
//!
//! Every stored match carries nine other players with their stats, and most of them have
//! a rank (in the match, or looked up for lobby strength). That is a sample of the CN
//! servers no outside site has. It is a biased sample (only lobbies of players someone
//! looked up here), and that is said wherever a benchmark is shown.
//!
//! **What is compared.** Per-10-minute figures of one match each (damage, healing,
//! mitigation, eliminations, final blows, deaths): the subject's *median* match against
//! the peers' match-by-match spread, as a percentile, so one great or awful game does not
//! decide it. Deaths are better when lower, so their percentile is turned around.
//!
//! **Who counts as a peer.** Same hero, same mode, at the subject's tier; if that has fewer
//! than [`MIN_PEERS`] matches, the tiers either side are added; then any rank. The answer
//! says which band was used and how many peer matches it rests on.
use crate::growth::MIN_DURATION_S;
use crate::ir::*;
use crate::strength::rating_tier;
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, HashMap};

/// Fewest peer matches a percentile is given from.
pub const MIN_PEERS: usize = 30;
/// Fewest matches of the subject's own on the hero.
pub const MIN_OWN: usize = 3;

/// The normal ladder, lowest first (Stadium ranks are a ladder of their own: not used).
const TIERS: [&str; 9] = [
    "Bronze",
    "Silver",
    "Gold",
    "Platinum",
    "Emerald",
    "Diamond",
    "Master",
    "Grandmaster",
    "Champion",
];

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum BenchMetric {
    Damage,
    Healing,
    Mitigation,
    Eliminations,
    FinalBlows,
    Deaths,
}

impl BenchMetric {
    pub const ALL: [BenchMetric; 6] = [
        BenchMetric::Damage,
        BenchMetric::Healing,
        BenchMetric::Mitigation,
        BenchMetric::Eliminations,
        BenchMetric::FinalBlows,
        BenchMetric::Deaths,
    ];
    fn raw(self, s: &StatLine) -> Option<f64> {
        match self {
            Self::Damage => s.damage,
            Self::Healing => s.healing,
            Self::Mitigation => s.mitigation,
            Self::Eliminations => s.kills,
            Self::FinalBlows => s.final_blows,
            Self::Deaths => s.deaths,
        }
    }
    /// Fewer is better.
    fn lower_is_better(self) -> bool {
        self == Self::Deaths
    }
}

/// Five bands of the peers' spread (Leetify-style): bottom 10 %, 10–30, 30–70, 70–90, top 10.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Band {
    Poor,
    Subpar,
    Average,
    Good,
    Great,
}

impl Band {
    pub fn of(percentile: f64) -> Self {
        match percentile {
            p if p < 10.0 => Self::Poor,
            p if p < 30.0 => Self::Subpar,
            p if p < 70.0 => Self::Average,
            p if p < 90.0 => Self::Good,
            _ => Self::Great,
        }
    }
}

/// Which peers a benchmark is drawn from.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PeerGroup {
    /// Tier keys included, lowest first; empty means any rank.
    pub tiers: Vec<String>,
    pub matches: usize,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct MetricBench {
    pub metric: BenchMetric,
    /// The subject's median match, per 10 minutes.
    pub value: f64,
    /// The peers' median match, per 10 minutes.
    pub peer_median: f64,
    /// Where the subject's median sits among the peers' matches, 0–100, with "better" up
    /// (turned around for deaths).
    pub percentile: f64,
    pub band: Band,
    pub peers: PeerGroup,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct HeroBench {
    pub hero: EntityRef,
    pub role: Role,
    /// The subject's matches on the hero that counted.
    pub matches: usize,
    /// The subject's tier on this role, if known (the band the peers are picked around).
    pub tier: Option<String>,
    pub metrics: Vec<MetricBench>,
}

/// Per-10-minute figures of one player in one match, or `None` when the match is too
/// short or the player's hero is unknown.
fn per10(detail: &MatchDetail, p: &Participant) -> Option<(String, BTreeMap<BenchMetric, f64>)> {
    let duration = detail.duration_s.filter(|d| *d >= MIN_DURATION_S)?;
    let hero = p.hero.as_ref()?.stable_id();
    let figures = BenchMetric::ALL
        .into_iter()
        .filter_map(|m| m.raw(&p.stats).map(|v| (m, v / duration * 600.0)))
        .collect();
    Some((hero, figures))
}

/// A participant's tier: the rank in the match, else their career rank for the role.
fn tier_of(p: &Participant, ratings: &HashMap<&str, &PlayerRating>) -> Option<&'static str> {
    let sr = p
        .rank
        .as_ref()
        .and_then(|r| r.skill_rating)
        .map(|v| v as f64)
        .or_else(|| {
            ratings
                .get(p.bnet_id.as_deref()?)
                .and_then(|r| r.rating_for(p.role))
                .map(|(sr, _)| sr)
        })?;
    rating_tier(sr).map(|(t, _)| t)
}

fn median(v: &mut [f64]) -> Option<f64> {
    if v.is_empty() {
        return None;
    }
    v.sort_by(f64::total_cmp);
    let n = v.len();
    Some(if n % 2 == 1 {
        v[n / 2]
    } else {
        (v[n / 2 - 1] + v[n / 2]) / 2.0
    })
}

/// Share of `peers` below `x`, counting ties as half (0–100).
fn percentile(peers: &[f64], x: f64) -> f64 {
    let below = peers.iter().filter(|v| **v < x).count() as f64;
    let equal = peers.iter().filter(|v| **v == x).count() as f64;
    100.0 * (below + equal / 2.0) / peers.len() as f64
}

/// The subject's matches on one hero: the hero, the role, each match's figures.
type OwnMatches = (EntityRef, Role, Vec<Figures>);
type Figures = BTreeMap<BenchMetric, f64>;

/// One peer match: hero, tier, figures.
struct PeerMatch {
    hero: String,
    tier: Option<usize>,
    figures: BTreeMap<BenchMetric, f64>,
}

/// Benchmarks for `subject`'s heroes in `mode`, from every stored detail of that mode
/// (whoever it was stored for; each match counted once). `subject_tiers` is the subject's
/// own tier per role, when known.
pub fn benchmarks(
    details: &[MatchDetail],
    ratings: &[PlayerRating],
    subject: &str,
    mode: Mode,
    subject_tiers: &HashMap<Role, String>,
) -> Vec<HeroBench> {
    if mode == Mode::Stadium {
        return Vec::new();
    }
    let by_id: HashMap<&str, &PlayerRating> =
        ratings.iter().map(|r| (r.bnet_id.as_str(), r)).collect();
    let mut seen = std::collections::HashSet::new();
    let mut peers: Vec<PeerMatch> = Vec::new();
    // The subject's own matches on each hero: role, figures.
    let mut own: BTreeMap<String, OwnMatches> = BTreeMap::new();
    for d in details.iter().filter(|d| d.mode == mode) {
        for p in d.allies.iter().chain(&d.enemies) {
            let Some(id) = p.bnet_id.as_deref() else {
                continue;
            };
            // A match stored for two subjects holds the same players twice.
            if !seen.insert((d.id.clone(), id.to_owned())) {
                continue;
            }
            let Some((hero, figures)) = per10(d, p) else {
                continue;
            };
            if id == subject {
                let entry = own
                    .entry(hero)
                    .or_insert_with(|| (p.hero.clone().unwrap(), p.role, Vec::new()));
                entry.2.push(figures);
            } else {
                let tier = tier_of(p, &by_id).and_then(|t| TIERS.iter().position(|x| *x == t));
                peers.push(PeerMatch {
                    hero,
                    tier,
                    figures,
                });
            }
        }
    }

    let mut out: Vec<HeroBench> = own
        .into_iter()
        .filter(|(_, (_, _, m))| m.len() >= MIN_OWN)
        .map(|(hero_id, (hero, role, mine))| {
            let tier = subject_tiers.get(&role).cloned();
            let at = tier
                .as_deref()
                .and_then(|t| TIERS.iter().position(|x| *x == t));
            let on_hero: Vec<&PeerMatch> = peers.iter().filter(|p| p.hero == hero_id).collect();
            // Narrowest band with enough peer matches: the tier, the tiers either side, any.
            let bands: Vec<Option<(usize, usize)>> = match at {
                Some(t) => vec![
                    Some((t, t)),
                    Some((t.saturating_sub(1), (t + 1).min(TIERS.len() - 1))),
                    None,
                ],
                None => vec![None],
            };
            let metrics = BenchMetric::ALL
                .into_iter()
                .filter_map(|metric| {
                    let mut values: Vec<f64> = mine
                        .iter()
                        .filter_map(|f| f.get(&metric).copied())
                        .collect();
                    let value = median(&mut values)?;
                    let (group, mut peer_values) = bands.iter().find_map(|band| {
                        let values: Vec<f64> = on_hero
                            .iter()
                            .filter(|p| match band {
                                Some((lo, hi)) => p.tier.is_some_and(|t| t >= *lo && t <= *hi),
                                None => true,
                            })
                            .filter_map(|p| p.figures.get(&metric).copied())
                            .collect();
                        (values.len() >= MIN_PEERS).then(|| {
                            let tiers = match band {
                                Some((lo, hi)) => {
                                    TIERS[*lo..=*hi].iter().map(|t| t.to_string()).collect()
                                }
                                None => Vec::new(),
                            };
                            (
                                PeerGroup {
                                    tiers,
                                    matches: values.len(),
                                },
                                values,
                            )
                        })
                    })?;
                    // Something the hero hardly does (a support's mitigation): when the typical
                    // peer match and the subject's both have none, there is nothing to compare.
                    if value == 0.0 && median(&mut peer_values.clone()).unwrap_or_default() == 0.0 {
                        return None;
                    }
                    let mut pct = percentile(&peer_values, value);
                    if metric.lower_is_better() {
                        pct = 100.0 - pct;
                    }
                    Some(MetricBench {
                        metric,
                        value,
                        peer_median: median(&mut peer_values).unwrap_or_default(),
                        percentile: pct,
                        band: Band::of(pct),
                        peers: group,
                    })
                })
                .collect::<Vec<_>>();
            HeroBench {
                hero,
                role,
                matches: mine.len(),
                tier,
                metrics,
            }
        })
        .filter(|h| !h.metrics.is_empty())
        .collect();
    out.sort_by_key(|h| std::cmp::Reverse(h.matches));
    out
}

/// The subject's tier per role, from the ranks of the matches stored for them (the newest
/// rank seen in each role), else their career rank.
pub fn subject_tiers(
    details: &[MatchDetail],
    rating: Option<&PlayerRating>,
) -> HashMap<Role, String> {
    let mut out = HashMap::new();
    let mut newest: Vec<&MatchDetail> = details.iter().collect();
    newest.sort_by_key(|d| std::cmp::Reverse(d.started_at_ms));
    for d in newest {
        if let Some(me) = d.subject()
            && let Some(sr) = me.rank.as_ref().and_then(|r| r.skill_rating)
            && let Some((t, _)) = rating_tier(sr as f64)
        {
            out.entry(me.role).or_insert_with(|| t.to_owned());
        }
    }
    if let Some(r) = rating {
        for role in Role::PLAYABLE {
            if out.contains_key(&role) {
                continue;
            }
            if let Some((sr, analysis_fit)) = r.rating_for(role)
                && analysis_fit == RatingFit::SameRole
                && let Some((t, _)) = rating_tier(sr)
            {
                out.insert(role, t.to_owned());
            }
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn player(
        id: &str,
        hero: &str,
        role: Role,
        damage: f64,
        deaths: f64,
        sr: Option<i64>,
    ) -> Participant {
        Participant {
            name: None,
            bnet_id: Some(id.into()),
            is_subject: false,
            hero: Some(EntityRef::new(EntityKind::Hero, hero, Some(hero.into()))),
            hero_icon_url: None,
            role,
            stats: StatLine {
                damage: Some(damage),
                deaths: Some(deaths),
                ..StatLine::default()
            },
            rank: sr.map(|sr| Rank {
                tier: None,
                division: None,
                score: None,
                skill_rating: Some(sr),
                at_ms: None,
            }),
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

    fn detail(id: &str, players: Vec<Participant>) -> MatchDetail {
        MatchDetail {
            id: id.into(),
            mode: Mode::Competitive,
            map: None,
            outcome: Outcome::Win,
            outcome_source: OutcomeSource::Provider,
            started_at_ms: Some(0),
            duration_s: Some(600.0),
            score: Score::default(),
            bans: Bans::default(),
            subject_heroes: Vec::new(),
            allies: players,
            enemies: Vec::new(),
            rounds: Vec::new(),
        }
    }

    /// The subject plays hero "1" in three matches doing 6000 damage; 40 gold peers on
    /// hero "1" do 1000..=40 × 100 damage (per 10 minutes, as matches are 10 minutes).
    fn fixture() -> Vec<MatchDetail> {
        let mut out = Vec::new();
        for m in 0..3 {
            out.push(detail(
                &format!("own{m}"),
                vec![player("me", "1", Role::Damage, 6000.0, 4.0, Some(1700))],
            ));
        }
        for k in 0..40 {
            out.push(detail(
                &format!("p{k}"),
                vec![player(
                    &format!("peer{k}"),
                    "1",
                    Role::Damage,
                    1000.0 + 100.0 * k as f64,
                    k as f64 / 5.0,
                    Some(1600),
                )],
            ));
        }
        out
    }

    #[test]
    fn the_typical_match_is_placed_among_peers_at_the_same_tier() {
        let tiers = HashMap::from([(Role::Damage, "Gold".to_owned())]);
        let b = benchmarks(&fixture(), &[], "me", Mode::Competitive, &tiers);
        assert_eq!(b.len(), 1);
        let h = &b[0];
        assert_eq!(h.matches, 3);
        let dmg = h
            .metrics
            .iter()
            .find(|m| m.metric == BenchMetric::Damage)
            .unwrap();
        assert_eq!(dmg.value, 6000.0);
        assert_eq!(dmg.peers.tiers, ["Gold"]);
        assert_eq!(dmg.peers.matches, 40);
        // The peers run 1000 to 4900, all below 6000.
        assert_eq!(dmg.percentile, 100.0);
        assert_eq!(dmg.band, Band::Great);
        // Deaths: 4 per 10 minutes; peers 0..7.8. Fewer is better, so turned around.
        let deaths = h
            .metrics
            .iter()
            .find(|m| m.metric == BenchMetric::Deaths)
            .unwrap();
        assert!(deaths.percentile < 50.0, "{}", deaths.percentile);
    }

    #[test]
    fn too_few_peers_at_the_tier_widens_to_any_rank() {
        let tiers = HashMap::from([(Role::Damage, "Diamond".to_owned())]);
        let b = benchmarks(&fixture(), &[], "me", Mode::Competitive, &tiers);
        let dmg = b[0]
            .metrics
            .iter()
            .find(|m| m.metric == BenchMetric::Damage)
            .unwrap();
        assert!(dmg.peers.tiers.is_empty(), "any rank");
        assert_eq!(dmg.peers.matches, 40);
    }

    #[test]
    fn nothing_from_too_few_own_matches_or_in_stadium() {
        let mut few = fixture();
        few.remove(0);
        few.remove(0);
        assert!(benchmarks(&few, &[], "me", Mode::Competitive, &HashMap::new()).is_empty());
        assert!(benchmarks(&fixture(), &[], "me", Mode::Stadium, &HashMap::new()).is_empty());
    }

    #[test]
    fn bands_follow_the_percentile() {
        assert_eq!(Band::of(5.0), Band::Poor);
        assert_eq!(Band::of(20.0), Band::Subpar);
        assert_eq!(Band::of(50.0), Band::Average);
        assert_eq!(Band::of(80.0), Band::Good);
        assert_eq!(Band::of(95.0), Band::Great);
    }
}
