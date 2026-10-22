//! The statistics every page shares, so a number means the same thing everywhere
//! (docs/algorithms.md §7.1): how many matches a figure needs before it is compared, the
//! plausible range of a win rate, and how firmly a trend is worded.
//!
//! Game records are small and noisy. 87.5 % over 8 matches and 67 % over 64 are not the
//! same kind of number: the first could easily be a 55 % player on a good week. So a rate
//! always comes with its count and its range, and anything ranked is ranked by what the
//! range says it is at least, not by the bare rate.
use serde::{Deserialize, Serialize};

/// Fewest matches before a hero, map or other group is compared or ranked; below it the
/// group is listed with its count but greyed out.
pub const MIN_GROUP_MATCHES: usize = 5;

/// Fewest matches a trend is read from (see [`crate::growth`]).
pub const MIN_TREND_MATCHES: usize = crate::growth::MIN_FOR_GROWTH;

/// z for a 95 % range.
const Z95: f64 = 1.959_964;

/// The Wilson score interval of `wins` out of `n`, in percent: the range the true rate
/// plausibly lies in. Unlike ± around the bare rate, it stays inside 0–100 and does not
/// collapse to a point at 0 or n wins. `None` when there is nothing to judge.
pub fn wilson_pct(wins: usize, n: usize) -> Option<(f64, f64)> {
    if n == 0 {
        return None;
    }
    let (n, p) = (n as f64, wins as f64 / n as f64);
    let z2 = Z95 * Z95;
    let centre = (p + z2 / (2.0 * n)) / (1.0 + z2 / n);
    let half = Z95 * (p * (1.0 - p) / n + z2 / (4.0 * n * n)).sqrt() / (1.0 + z2 / n);
    Some((
        100.0 * (centre - half).max(0.0),
        100.0 * (centre + half).min(1.0),
    ))
}

/// How firmly a finding is worded, from its p value and sample.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Confidence {
    /// p < 0.05: “较可信”.
    Firm,
    /// p < 0.10: “有迹象”.
    Hint,
    /// Not distinguishable from chance: “看不出变化”.
    None,
    /// Fewer matches than the test needs: “样本不足”.
    TooFew,
}

impl Confidence {
    pub fn of(p: Option<f64>, n: usize, min: usize) -> Self {
        match p {
            _ if n < min => Self::TooFew,
            Some(p) if p < 0.05 => Self::Firm,
            Some(p) if p < 0.10 => Self::Hint,
            _ => Self::None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn wilson_matches_the_textbook_values() {
        // 8 of 10: 49.0 %–94.3 % (Wilson, 95 %).
        let (lo, hi) = wilson_pct(8, 10).unwrap();
        assert!((lo - 49.0).abs() < 0.1, "{lo}");
        assert!((hi - 94.3).abs() < 0.1, "{hi}");
        // The range never leaves 0–100, even at the ends.
        let (lo, hi) = wilson_pct(0, 5).unwrap();
        assert_eq!(lo, 0.0);
        assert!(hi > 40.0 && hi < 50.0);
        let (lo, hi) = wilson_pct(5, 5).unwrap();
        assert!(lo > 50.0 && hi == 100.0);
        assert_eq!(wilson_pct(0, 0), None);
    }

    #[test]
    fn a_small_perfect_record_ranks_below_a_large_good_one() {
        // 7 of 8 (87.5 %) against 43 of 64 (67 %): at least ~53 % against ~55 %.
        let small = wilson_pct(7, 8).unwrap().0;
        let large = wilson_pct(43, 64).unwrap().0;
        assert!(small < large, "{small} vs {large}");
    }

    #[test]
    fn confidence_wording_follows_p_and_sample() {
        assert_eq!(Confidence::of(Some(0.01), 20, 8), Confidence::Firm);
        assert_eq!(Confidence::of(Some(0.07), 20, 8), Confidence::Hint);
        assert_eq!(Confidence::of(Some(0.4), 20, 8), Confidence::None);
        assert_eq!(Confidence::of(Some(0.01), 5, 8), Confidence::TooFew);
        assert_eq!(Confidence::of(None, 20, 8), Confidence::None);
    }
}
