//! Growth (成长): match by match, how the subject is doing on a few measures, and whether
//! each is trending up or down. The measures are how long they last per death, their
//! Fleta index, their KDA, and what a support heals and a tank mitigates.
//!
//! **Survival time.** The provider does not say when anyone died, only how many times, so
//! the time between deaths is worked out as the match's length over its deaths: time at
//! risk per death, the usual way to estimate how long something lasts when each match is
//! only seen as a total. A match with no deaths has no finished life at all; it is given
//! the whole match as its figure and flagged `deathless`, because the real figure is at
//! least that long. Time spent waiting to respawn is inside every figure, the same way in
//! every match, which is what a comparison needs. It cannot know *when* the last death
//! was, so a match that ends a minute after the final death still counts that minute.
//!
//! **Trend.** Each measure is read two ways: the average of the older half of the matches
//! against the newer half, and a Mann-Kendall trend test over the whole series (no
//! assumption about how the values are distributed; the p value says how likely a series
//! with no trend is to drift this much). It is worked out for all matches together and for
//! each role alone, because roles differ (a support lives longer than a tank, a damage
//! hero finishes more kills) and a player who changes role changes the overall figure
//! without changing at all.
use crate::analysis;
use crate::ir::*;
use serde::{Deserialize, Serialize};

/// Matches shorter than this say nothing about how a player did (remakes, leavers).
pub const MIN_DURATION_S: f64 = 120.0;
/// Fewest matches a trend is read from.
pub const MIN_FOR_GROWTH: usize = 8;
/// The trend is called one when a series with none would drift this much less often than
/// this.
pub const TREND_P: f64 = 0.10;

/// One match as the growth measures see it.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct MatchPoint {
    pub match_id: String,
    pub started_at_ms: i64,
    pub mode: Mode,
    pub role: Role,
    pub hero: Option<EntityRef>,
    pub outcome: Outcome,
    pub duration_s: f64,
    pub deaths: f64,
    /// Seconds per death: `duration_s / deaths`; the whole match when there was none.
    pub life_s: f64,
    /// No death in the match: `life_s` is the match length, and the real figure is at
    /// least that.
    pub deathless: bool,
    /// Final blows as a percentage of half the team's (see [`analysis::attach_fleta`]).
    pub fleta: Option<f64>,
    /// `(kills + assists) / deaths`, with no deaths counted as one.
    pub kda: Option<f64>,
    /// Healing per 10 minutes; only for a match played as support (other roles heal as a
    /// side effect, and a figure that is zero for most of them would only drag a trend).
    pub healing10: Option<f64>,
    /// Damage mitigated per 10 minutes; only for a match played as tank.
    pub mitigation10: Option<f64>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Metric {
    Life,
    Fleta,
    Kda,
    Healing,
    Mitigation,
}

impl Metric {
    pub const ALL: [Metric; 5] = [
        Metric::Life,
        Metric::Fleta,
        Metric::Kda,
        Metric::Healing,
        Metric::Mitigation,
    ];

    fn of(self, p: &MatchPoint) -> Option<f64> {
        match self {
            Metric::Life => Some(p.life_s),
            Metric::Fleta => p.fleta,
            Metric::Kda => p.kda,
            Metric::Healing => p.healing10,
            Metric::Mitigation => p.mitigation10,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Trend {
    Up,
    Down,
    /// No trend either way (not enough change to tell from chance).
    Flat,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Growth {
    pub matches: usize,
    /// Mean of the older half and of the newer half (the middle match of an odd number
    /// belongs to neither).
    pub older_mean: f64,
    pub newer_mean: f64,
    pub change: f64,
    /// `change` as a share of `older_mean`.
    pub change_pct: f64,
    /// Least-squares slope, per match.
    pub slope_per_match: f64,
    /// Two-sided p value of the Mann-Kendall test.
    pub p: f64,
    pub trend: Trend,
    /// How firmly the change may be worded (from `p`); see [`crate::stats::Confidence`].
    pub confidence: crate::stats::Confidence,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RoleGrowth {
    pub role: Role,
    pub matches: usize,
    pub mean: f64,
    /// Absent below [`MIN_FOR_GROWTH`] matches.
    pub growth: Option<Growth>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct MetricGrowth {
    pub metric: Metric,
    pub matches: usize,
    pub mean: Option<f64>,
    pub growth: Option<Growth>,
    pub by_role: Vec<RoleGrowth>,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct GrowthReport {
    /// Oldest first.
    pub points: Vec<MatchPoint>,
    /// Matches handed in that could not be used (no deaths figure, too short).
    pub skipped: usize,
    pub metrics: Vec<MetricGrowth>,
}

pub fn growth<'a>(details: impl IntoIterator<Item = &'a MatchDetail>) -> GrowthReport {
    let mut points = Vec::new();
    let mut skipped = 0;
    for d in details {
        match point(d) {
            Some(p) => points.push(p),
            None => skipped += 1,
        }
    }
    points.sort_by(|a, b| (a.started_at_ms, &a.match_id).cmp(&(b.started_at_ms, &b.match_id)));

    let metrics = Metric::ALL
        .into_iter()
        .map(|metric| {
            let series = |keep: &dyn Fn(&MatchPoint) -> bool| -> Vec<f64> {
                points
                    .iter()
                    .filter(|p| keep(p))
                    .filter_map(|p| metric.of(p))
                    .collect()
            };
            let all = series(&|_| true);
            let by_role = Role::PLAYABLE
                .into_iter()
                .filter_map(|role| {
                    let v = series(&|p| p.role == role);
                    (!v.is_empty()).then(|| RoleGrowth {
                        role,
                        matches: v.len(),
                        mean: mean(&v),
                        growth: trend(&v),
                    })
                })
                .collect();
            MetricGrowth {
                metric,
                matches: all.len(),
                mean: (!all.is_empty()).then(|| mean(&all)),
                growth: trend(&all),
                by_role,
            }
        })
        .collect();
    GrowthReport {
        points,
        skipped,
        metrics,
    }
}

fn point(d: &MatchDetail) -> Option<MatchPoint> {
    let me = d.subject()?;
    let duration_s = d.duration_s.filter(|s| *s >= MIN_DURATION_S)?;
    let deaths = me.stats.deaths.filter(|x| *x >= 0.0)?;
    let s = &me.stats;
    Some(MatchPoint {
        match_id: d.id.clone(),
        started_at_ms: d.started_at_ms?,
        mode: d.mode,
        role: me.role,
        hero: me.hero.clone(),
        outcome: d.outcome,
        duration_s,
        deaths,
        life_s: if deaths > 0.0 {
            duration_s / deaths
        } else {
            duration_s
        },
        deathless: deaths == 0.0,
        fleta: analysis::fleta(s.final_blows, analysis::team_final_blows(&d.allies)),
        kda: s
            .kills
            .zip(s.assists)
            .map(|(k, a)| (k + a) / deaths.max(1.0)),
        healing10: s
            .healing
            .filter(|_| me.role == Role::Support)
            .map(|h| h / duration_s * 600.0),
        mitigation10: s
            .mitigation
            .filter(|_| me.role == Role::Tank)
            .map(|m| m / duration_s * 600.0),
    })
}

fn mean(v: &[f64]) -> f64 {
    v.iter().sum::<f64>() / v.len() as f64
}

/// The trend of a series given oldest first.
fn trend(v: &[f64]) -> Option<Growth> {
    let n = v.len();
    if n < MIN_FOR_GROWTH {
        return None;
    }
    let half = n / 2;
    let older_mean = mean(&v[..half]);
    let newer_mean = mean(&v[n - half..]);
    let change = newer_mean - older_mean;

    // Least squares against the match number.
    let xs = (n as f64 - 1.0) / 2.0;
    let ys = mean(v);
    let (mut sxy, mut sxx) = (0.0, 0.0);
    for (i, y) in v.iter().enumerate() {
        let dx = i as f64 - xs;
        sxy += dx * (y - ys);
        sxx += dx * dx;
    }

    let p = mann_kendall_p(v);
    let direction = if p >= TREND_P || change == 0.0 {
        Trend::Flat
    } else if change > 0.0 {
        Trend::Up
    } else {
        Trend::Down
    };
    Some(Growth {
        matches: n,
        older_mean,
        newer_mean,
        change,
        change_pct: if older_mean != 0.0 {
            change / older_mean.abs() * 100.0
        } else {
            0.0
        },
        slope_per_match: sxy / sxx,
        p,
        trend: direction,
        confidence: crate::stats::Confidence::of(Some(p), n, MIN_FOR_GROWTH),
    })
}

/// Two-sided p value of the Mann-Kendall test, by the normal approximation (with the
/// correction for ties).
fn mann_kendall_p(v: &[f64]) -> f64 {
    let n = v.len();
    let mut s = 0.0_f64;
    for i in 0..n {
        for j in i + 1..n {
            s += match v[j].total_cmp(&v[i]) {
                std::cmp::Ordering::Greater => 1.0,
                std::cmp::Ordering::Less => -1.0,
                std::cmp::Ordering::Equal => 0.0,
            };
        }
    }
    let nf = n as f64;
    let mut var = nf * (nf - 1.0) * (2.0 * nf + 5.0);
    let mut sorted = v.to_vec();
    sorted.sort_by(f64::total_cmp);
    for tie in sorted.chunk_by(|a, b| a == b).filter(|g| g.len() > 1) {
        let t = tie.len() as f64;
        var -= t * (t - 1.0) * (2.0 * t + 5.0);
    }
    var /= 18.0;
    if var <= 0.0 || s == 0.0 {
        return 1.0;
    }
    let z = (s - s.signum()) / var.sqrt();
    erfc(z.abs() / std::f64::consts::SQRT_2)
}

/// Complementary error function (Abramowitz and Stegun 7.1.26, error under 1.5e-7).
pub(crate) fn erfc(x: f64) -> f64 {
    let t = 1.0 / (1.0 + 0.327_591_1 * x);
    let poly = t
        * (0.254_829_592
            + t * (-0.284_496_736
                + t * (1.421_413_741 + t * (-1.453_152_027 + t * 1.061_405_429))));
    poly * (-x * x).exp()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn participant(role: Role, subject: bool, stats: StatLine) -> Participant {
        Participant {
            name: None,
            bnet_id: None,
            is_subject: subject,
            hero: None,
            hero_icon_url: None,
            role,
            stats,
            rank: None,
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

    fn detail(
        id: &str,
        at: i64,
        role: Role,
        deaths: f64,
        duration: f64,
        outcome: Outcome,
    ) -> MatchDetail {
        let me = participant(
            role,
            true,
            StatLine {
                deaths: Some(deaths),
                kills: Some(6.0),
                assists: Some(4.0),
                final_blows: Some(2.0),
                ..StatLine::default()
            },
        );
        let mate = participant(
            role,
            false,
            StatLine {
                final_blows: Some(8.0),
                ..StatLine::default()
            },
        );
        MatchDetail {
            id: id.into(),
            mode: Mode::Quick,
            map: None,
            outcome,
            outcome_source: OutcomeSource::Provider,
            started_at_ms: Some(at),
            duration_s: Some(duration),
            score: Score::default(),
            bans: Bans::default(),
            subject_heroes: Vec::new(),
            allies: vec![me, mate],
            enemies: Vec::new(),
            rounds: Vec::new(),
        }
    }

    fn metric(r: &GrowthReport, m: Metric) -> &MetricGrowth {
        r.metrics.iter().find(|x| x.metric == m).unwrap()
    }

    #[test]
    fn a_life_is_the_match_over_its_deaths() {
        // Five minutes with one death is five minutes per death, not half of it.
        let d = detail("a", 1, Role::Support, 1.0, 300.0, Outcome::Win);
        let p = point(&d).unwrap();
        assert_eq!(p.life_s, 300.0);
        assert!(!p.deathless);
        let d = detail("b", 2, Role::Support, 3.0, 600.0, Outcome::Win);
        assert_eq!(point(&d).unwrap().life_s, 200.0);
    }

    #[test]
    fn a_match_without_deaths_is_flagged_and_given_the_whole_match() {
        let d = detail("a", 1, Role::Support, 0.0, 600.0, Outcome::Win);
        let p = point(&d).unwrap();
        assert_eq!(p.life_s, 600.0);
        assert!(p.deathless);
        // KDA counts no deaths as one.
        assert_eq!(p.kda, Some(10.0));
    }

    #[test]
    fn kda_and_fleta_come_from_the_match() {
        let d = detail("a", 1, Role::Damage, 5.0, 600.0, Outcome::Loss);
        let p = point(&d).unwrap();
        assert_eq!(p.kda, Some(2.0)); // (6 + 4) / 5
        // 2 of the team's 10 final blows: 2 / (10 * 0.5) = 40%.
        assert_eq!(p.fleta, Some(40.0));
    }

    #[test]
    fn healing_is_a_support_figure_and_mitigation_a_tank_one_per_ten_minutes() {
        let mut d = detail("a", 1, Role::Support, 2.0, 300.0, Outcome::Win);
        d.allies[0].stats.healing = Some(3000.0);
        d.allies[0].stats.mitigation = Some(900.0);
        let p = point(&d).unwrap();
        assert_eq!(p.healing10, Some(6000.0)); // 3000 in 5 minutes
        assert_eq!(p.mitigation10, None);
        let mut d = detail("b", 2, Role::Tank, 2.0, 600.0, Outcome::Win);
        d.allies[0].stats.healing = Some(500.0);
        d.allies[0].stats.mitigation = Some(9000.0);
        let p = point(&d).unwrap();
        assert_eq!(p.healing10, None);
        assert_eq!(p.mitigation10, Some(9000.0));
    }

    #[test]
    fn unknown_figures_stay_missing_not_zero() {
        let mut d = detail("a", 1, Role::Damage, 2.0, 600.0, Outcome::Win);
        d.allies[0].stats.final_blows = None;
        d.allies[0].stats.kills = None;
        let p = point(&d).unwrap();
        assert_eq!(p.fleta, None);
        assert_eq!(p.kda, None);
    }

    #[test]
    fn unusable_matches_are_counted_not_averaged() {
        let short = detail("s", 1, Role::Tank, 1.0, 60.0, Outcome::Loss);
        let mut no_deaths = detail("n", 2, Role::Tank, 1.0, 600.0, Outcome::Loss);
        no_deaths.allies[0].stats.deaths = None;
        let ok = detail("o", 3, Role::Tank, 2.0, 600.0, Outcome::Win);
        let r = growth([&short, &no_deaths, &ok]);
        assert_eq!(r.skipped, 2);
        assert_eq!(r.points.len(), 1);
        assert_eq!(metric(&r, Metric::Life).mean, Some(300.0));
    }

    #[test]
    fn points_come_out_oldest_first() {
        let a = detail("late", 20, Role::Tank, 1.0, 600.0, Outcome::Win);
        let b = detail("early", 10, Role::Tank, 1.0, 600.0, Outcome::Win);
        let r = growth([&a, &b]);
        assert_eq!(r.points[0].match_id, "early");
    }

    #[test]
    fn a_metric_is_read_only_over_the_matches_that_have_it() {
        let mut details = Vec::new();
        for i in 0..10 {
            let mut d = detail(&format!("m{i}"), i, Role::Damage, 2.0, 600.0, Outcome::Win);
            if i % 2 == 0 {
                d.allies[0].stats.final_blows = None;
            }
            details.push(d);
        }
        let r = growth(details.iter());
        assert_eq!(metric(&r, Metric::Life).matches, 10);
        assert_eq!(metric(&r, Metric::Fleta).matches, 5);
        // Five matches are too few for a trend.
        assert!(metric(&r, Metric::Fleta).growth.is_none());
    }

    #[test]
    fn a_rising_series_is_called_up_and_a_noisy_flat_one_is_not() {
        let rising: Vec<f64> = (0..20).map(|i| 100.0 + 5.0 * i as f64).collect();
        let g = trend(&rising).unwrap();
        assert_eq!(g.trend, Trend::Up);
        assert!(g.p < 0.001, "p = {}", g.p);
        assert!((g.slope_per_match - 5.0).abs() < 1e-9);
        assert!(g.change > 0.0 && g.change_pct > 0.0);

        let falling: Vec<f64> = rising.iter().rev().copied().collect();
        assert_eq!(trend(&falling).unwrap().trend, Trend::Down);

        let flat = [
            100.0, 140.0, 90.0, 130.0, 95.0, 135.0, 92.0, 138.0, 96.0, 128.0,
        ];
        let g = trend(&flat).unwrap();
        assert_eq!(g.trend, Trend::Flat);
        assert!(g.p > 0.5, "p = {}", g.p);
    }

    #[test]
    fn too_few_matches_give_no_trend() {
        assert!(trend(&[1.0, 2.0, 3.0]).is_none());
    }

    #[test]
    fn roles_are_read_apart_so_a_role_change_is_not_growth() {
        // Tank lives are short, support lives are long; switching from one to the other
        // moves the overall series a lot but neither role's own series at all.
        let mut details = Vec::new();
        for i in 0..10 {
            details.push(detail(
                &format!("t{i}"),
                i,
                Role::Tank,
                9.0,
                600.0,
                Outcome::Win,
            ));
        }
        for i in 0..10 {
            details.push(detail(
                &format!("s{i}"),
                100 + i,
                Role::Support,
                2.0,
                600.0,
                Outcome::Win,
            ));
        }
        let r = growth(details.iter());
        let life = metric(&r, Metric::Life);
        assert_eq!(life.growth.as_ref().unwrap().trend, Trend::Up);
        for role in &life.by_role {
            assert_eq!(
                role.growth.as_ref().unwrap().trend,
                Trend::Flat,
                "{:?}",
                role.role
            );
        }
    }

    #[test]
    fn mann_kendall_matches_a_known_value() {
        // Fifteen pairs, one of them (4 before 3) out of order: S = 14 - 1 = 13. The
        // continuity-corrected z is (13 - 1) / sqrt(6 * 5 * 17 / 18) = 2.2545, so p = 0.0242.
        let p = mann_kendall_p(&[1.0, 2.0, 4.0, 3.0, 5.0, 6.0]);
        assert!((p - 0.0242).abs() < 0.001, "p = {p}");
    }
}
