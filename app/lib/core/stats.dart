import 'dart:math' as math;

/// The Wilson score interval of [wins] out of [n], in percent (95 %): the range the true
/// rate plausibly lies in. The same formula as `watch_core::stats::wilson_pct`, for rates
/// the app gets from the provider directly (a hero's season record); both are tested on
/// the same values. Null when there is nothing to judge.
(double, double)? wilsonPct(int wins, int n) {
  if (n <= 0) return null;
  const z = 1.959964;
  final p = wins / n, z2 = z * z;
  final centre = (p + z2 / (2 * n)) / (1 + z2 / n);
  final half = z * math.sqrt(p * (1 - p) / n + z2 / (4 * n * n)) / (1 + z2 / n);
  return (100 * math.max(0, centre - half), 100 * math.min(1, centre + half));
}

/// Fewest matches before a group is compared, when the service has not said
/// (`/api/state` `thresholds.group`, from `watch_core::stats::MIN_GROUP_MATCHES`).
const fallbackMinGroupMatches = 5;

/// The player's own usual range before each match: the middle half (first to third
/// quartile) of the [window] known values before it, once there are [minPrior] of them;
/// null before that. A match outside it is unusual for them, whichever way.
({List<double?> lows, List<double?> highs}) baselineBand(
  List<double?> values, {
  int window = 20,
  int minPrior = 8,
}) {
  final lows = <double?>[], highs = <double?>[];
  final prior = <double>[];
  for (final v in values) {
    if (prior.length >= minPrior) {
      final sorted = [...prior]..sort();
      lows.add(_quantile(sorted, 0.25));
      highs.add(_quantile(sorted, 0.75));
    } else {
      lows.add(null);
      highs.add(null);
    }
    if (v != null) {
      prior.add(v);
      if (prior.length > window) prior.removeAt(0);
    }
  }
  return (lows: lows, highs: highs);
}

/// Linear interpolation between order statistics (the usual “type 7” quantile).
double _quantile(List<double> sorted, double q) {
  final pos = (sorted.length - 1) * q;
  final lo = pos.floor(), hi = pos.ceil();
  return sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - lo);
}
