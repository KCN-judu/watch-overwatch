//! Survival time (存活时长): how long the subject lasts, on average, in each match, and
//! whether that is getting longer.
//!
//! The provider does not report how long a player was alive, so it is worked out from what
//! it does report: a match of `duration_s` seconds in which the player died `d` times was
//! lived in `d + 1` stretches (the last one ends with the match, not a death), so
//! `duration_s / (d + 1)` is the average length of one of them. The time spent waiting to
//! respawn is inside that figure, so it is a little longer than the time actually spent
//! alive; it is the same bias in every match, which is what a comparison between matches
//! needs.
//!
//! Growth is read two ways: the average of the older half of the matches against the
//! newer half, and a Mann-Kendall trend test over the whole series (no assumption about
//! how the values are distributed; the p value says how likely a series with no trend is
//! to drift this much). It is worked out for all matches together and for each role
//! alone, because roles live for different lengths of time and a player who changes role
//! changes the overall figure without changing at all.
use crate::ir::*;
use serde::{Deserialize, Serialize};

/// Matches shorter than this say nothing about how long a player lives (remakes, leavers).
pub const MIN_DURATION_S: f64 = 120.0;
/// Fewest matches a trend is read from.
pub const MIN_FOR_GROWTH: usize = 8;
/// The trend is called one when a series with none would drift this much less often than
/// this.
pub const TREND_P: f64 = 0.10;

/// One match: how long the subject lasted per life in it.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct LifeSample {
    pub match_id: String,
    pub started_at_ms: i64,
    pub mode: Mode,
    pub role: Role,
    pub hero: Option<EntityRef>,
    pub outcome: Outcome,
    pub duration_s: f64,
    pub deaths: f64,
    /// `duration_s / (deaths + 1)`.
    pub life_s: f64,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct LifeStat {
    pub matches: usize,
    pub mean_s: Option<f64>,
    pub median_s: Option<f64>,
    pub shortest_s: Option<f64>,
    pub longest_s: Option<f64>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Trend {
    /// Lives are getting longer.
    Longer,
    /// Lives are getting shorter.
    Shorter,
    /// No trend either way (not enough change to tell from chance).
    Flat,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Growth {
    pub matches: usize,
    /// Mean of the older half and of the newer half (the middle match of an odd number
    /// belongs to neither).
    pub older_mean_s: f64,
    pub newer_mean_s: f64,
    pub change_s: f64,
    /// `change_s` as a share of `older_mean_s`.
    pub change_pct: f64,
    /// Least-squares slope, in seconds per match.
    pub slope_s_per_match: f64,
    /// Two-sided p value of the Mann-Kendall test.
    pub p: f64,
    pub trend: Trend,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RoleLife {
    pub role: Role,
    pub stat: LifeStat,
    /// Absent below [`MIN_FOR_GROWTH`] matches.
    pub growth: Option<Growth>,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct SurvivalReport {
    /// Oldest first.
    pub samples: Vec<LifeSample>,
    /// Matches handed in that could not be used (no detail, no deaths figure, too short).
    pub skipped: usize,
    pub overall: LifeStat,
    pub growth: Option<Growth>,
    pub by_role: Vec<RoleLife>,
    pub won: LifeStat,
    pub lost: LifeStat,
}

pub fn survival<'a>(details: impl IntoIterator<Item = &'a MatchDetail>) -> SurvivalReport {
    let mut samples = Vec::new();
    let mut skipped = 0;
    for d in details {
        match sample(d) {
            Some(s) => samples.push(s),
            None => skipped += 1,
        }
    }
    samples.sort_by(|a, b| (a.started_at_ms, &a.match_id).cmp(&(b.started_at_ms, &b.match_id)));

    let lives = |keep: &dyn Fn(&LifeSample) -> bool| -> Vec<f64> {
        samples
            .iter()
            .filter(|s| keep(s))
            .map(|s| s.life_s)
            .collect()
    };
    let by_role = Role::PLAYABLE
        .into_iter()
        .filter_map(|role| {
            let v = lives(&|s| s.role == role);
            (!v.is_empty()).then(|| RoleLife {
                role,
                stat: stat(&v),
                growth: growth(&v),
            })
        })
        .collect();
    let all = lives(&|_| true);
    SurvivalReport {
        overall: stat(&all),
        growth: growth(&all),
        by_role,
        won: stat(&lives(&|s| s.outcome == Outcome::Win)),
        lost: stat(&lives(&|s| s.outcome == Outcome::Loss)),
        samples,
        skipped,
    }
}

fn sample(d: &MatchDetail) -> Option<LifeSample> {
    let me = d.subject()?;
    let duration_s = d.duration_s.filter(|s| *s >= MIN_DURATION_S)?;
    let deaths = me.stats.deaths.filter(|x| *x >= 0.0)?;
    Some(LifeSample {
        match_id: d.id.clone(),
        started_at_ms: d.started_at_ms?,
        mode: d.mode,
        role: me.role,
        hero: me.hero.clone(),
        outcome: d.outcome,
        duration_s,
        deaths,
        life_s: duration_s / (deaths + 1.0),
    })
}

fn mean(v: &[f64]) -> f64 {
    v.iter().sum::<f64>() / v.len() as f64
}

fn stat(v: &[f64]) -> LifeStat {
    if v.is_empty() {
        return LifeStat::default();
    }
    let mut s = v.to_vec();
    s.sort_by(f64::total_cmp);
    let mid = s.len() / 2;
    LifeStat {
        matches: s.len(),
        mean_s: Some(mean(&s)),
        median_s: Some(if s.len() % 2 == 1 {
            s[mid]
        } else {
            (s[mid - 1] + s[mid]) / 2.0
        }),
        shortest_s: s.first().copied(),
        longest_s: s.last().copied(),
    }
}

/// The trend of a series given oldest first.
fn growth(v: &[f64]) -> Option<Growth> {
    let n = v.len();
    if n < MIN_FOR_GROWTH {
        return None;
    }
    let half = n / 2;
    let older_mean_s = mean(&v[..half]);
    let newer_mean_s = mean(&v[n - half..]);
    let change_s = newer_mean_s - older_mean_s;

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
    let trend = if p >= TREND_P || change_s == 0.0 {
        Trend::Flat
    } else if change_s > 0.0 {
        Trend::Longer
    } else {
        Trend::Shorter
    };
    Some(Growth {
        matches: n,
        older_mean_s,
        newer_mean_s,
        change_s,
        change_pct: if older_mean_s > 0.0 {
            change_s / older_mean_s * 100.0
        } else {
            0.0
        },
        slope_s_per_match: sxy / sxx,
        p,
        trend,
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
fn erfc(x: f64) -> f64 {
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

    fn detail(
        id: &str,
        at: i64,
        role: Role,
        deaths: f64,
        duration: f64,
        outcome: Outcome,
    ) -> MatchDetail {
        let me = Participant {
            name: None,
            bnet_id: None,
            is_subject: true,
            hero: None,
            hero_icon_url: None,
            role,
            stats: StatLine {
                deaths: Some(deaths),
                ..StatLine::default()
            },
            rank: None,
            career_rank: None,
            career_other_roles: false,
            fleta: None,
            perks: Vec::new(),
            party_bnet_ids: Vec::new(),
            endorsed_by_bnet_ids: Vec::new(),
            suspended: false,
            stadium: None,
        };
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
            allies: vec![me],
            enemies: Vec::new(),
            rounds: Vec::new(),
        }
    }

    #[test]
    fn a_life_is_the_match_over_deaths_plus_one() {
        let d = detail("a", 1, Role::Support, 3.0, 600.0, Outcome::Win);
        assert_eq!(sample(&d).unwrap().life_s, 150.0);
        // Never dying is one life as long as the match.
        let d = detail("b", 2, Role::Support, 0.0, 600.0, Outcome::Win);
        assert_eq!(sample(&d).unwrap().life_s, 600.0);
    }

    #[test]
    fn unusable_matches_are_counted_not_averaged() {
        let short = detail("s", 1, Role::Tank, 1.0, 60.0, Outcome::Loss);
        let mut no_deaths = detail("n", 2, Role::Tank, 1.0, 600.0, Outcome::Loss);
        no_deaths.allies[0].stats.deaths = None;
        let ok = detail("o", 3, Role::Tank, 1.0, 600.0, Outcome::Win);
        let r = survival([&short, &no_deaths, &ok]);
        assert_eq!(r.skipped, 2);
        assert_eq!(r.overall.matches, 1);
        assert_eq!(r.overall.mean_s, Some(300.0));
        assert_eq!(r.won.matches, 1);
        assert_eq!(r.lost.matches, 0);
    }

    #[test]
    fn samples_come_out_oldest_first() {
        let a = detail("late", 20, Role::Tank, 1.0, 600.0, Outcome::Win);
        let b = detail("early", 10, Role::Tank, 1.0, 600.0, Outcome::Win);
        let r = survival([&a, &b]);
        assert_eq!(r.samples[0].match_id, "early");
    }

    #[test]
    fn a_rising_series_is_called_longer_and_a_noisy_flat_one_is_not() {
        let rising: Vec<f64> = (0..20).map(|i| 100.0 + 5.0 * i as f64).collect();
        let g = growth(&rising).unwrap();
        assert_eq!(g.trend, Trend::Longer);
        assert!(g.p < 0.001, "p = {}", g.p);
        assert!((g.slope_s_per_match - 5.0).abs() < 1e-9);
        assert!(g.change_s > 0.0 && g.change_pct > 0.0);

        let falling: Vec<f64> = rising.iter().rev().copied().collect();
        assert_eq!(growth(&falling).unwrap().trend, Trend::Shorter);

        let flat = [
            100.0, 140.0, 90.0, 130.0, 95.0, 135.0, 92.0, 138.0, 96.0, 128.0,
        ];
        let g = growth(&flat).unwrap();
        assert_eq!(g.trend, Trend::Flat);
        assert!(g.p > 0.5, "p = {}", g.p);
    }

    #[test]
    fn too_few_matches_give_no_trend() {
        assert!(growth(&[1.0, 2.0, 3.0]).is_none());
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
        let r = survival(details.iter());
        assert_eq!(r.growth.as_ref().unwrap().trend, Trend::Longer);
        for role in &r.by_role {
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
