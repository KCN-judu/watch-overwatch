import 'models.dart';

int? _i(Object? v) => v is num ? v.toInt() : null;
double? _d(Object? v) => v is num ? v.toDouble() : null;
String? _s(Object? v) => v is String && v.isNotEmpty ? v : null;

/// A measure a benchmark compares (`watch_core::benchmark::BenchMetric`).
enum BenchMetric {
  damage,
  healing,
  mitigation,
  eliminations,
  finalBlows,
  deaths,
  unknown;

  static BenchMetric parse(String? v) => switch (v) {
    'damage' => damage,
    'healing' => healing,
    'mitigation' => mitigation,
    'eliminations' => eliminations,
    'final_blows' => finalBlows,
    'deaths' => deaths,
    _ => unknown,
  };
}

/// Five bands of the peers' spread: bottom 10 %, 10–30, 30–70, 70–90, top 10.
enum Band {
  poor,
  subpar,
  average,
  good,
  great;

  static Band parse(String? v) =>
      Band.values.firstWhere((b) => b.name == v, orElse: () => average);
}

class MetricBench {
  MetricBench(Map<String, dynamic> j)
    : metric = BenchMetric.parse(_s(j['metric'])),
      value = _d(j['value']) ?? 0,
      peerMedian = _d(j['peer_median']) ?? 0,
      percentile = _d(j['percentile']) ?? 0,
      band = Band.parse(_s(j['band'])),
      peerTiers = [
        for (final t in (j['peers'] as Map?)?['tiers'] as List? ?? const [])
          '$t',
      ],
      peerMatches = _i((j['peers'] as Map?)?['matches']) ?? 0;
  final BenchMetric metric;

  /// The subject's median match and the peers', per 10 minutes.
  final double value, peerMedian;

  /// 0–100, better up (turned around for deaths).
  final double percentile;
  final Band band;

  /// Tier keys the peers were drawn from, lowest first; empty is any rank.
  final List<String> peerTiers;
  final int peerMatches;
}

class HeroBench {
  HeroBench(Map<String, dynamic> j)
    : hero = EntityRef.opt(j['hero']),
      role = Role.parse(_s(j['role'])),
      matches = _i(j['matches']) ?? 0,
      tier = _s(j['tier']),
      metrics = [
        for (final m in (j['metrics'] as List?) ?? const [])
          if (m is Map<String, dynamic>) MetricBench(m),
      ];
  final EntityRef? hero;
  final Role role;
  final int matches;
  final String? tier;
  final List<MetricBench> metrics;
}

class BenchmarkResult {
  BenchmarkResult(Map<String, dynamic> j)
    : enabled = j['enabled'] == true,
      matches = _i(j['matches']) ?? 0,
      heroes = [
        for (final h in (j['heroes'] as List?) ?? const [])
          if (h is Map<String, dynamic>) HeroBench(h),
      ];
  final bool enabled;

  /// Stored matches of the mode the sample is drawn from.
  final int matches;
  final List<HeroBench> heroes;

  /// The benchmark for [hero], by its game id; null when there is none.
  HeroBench? of(EntityRef hero) => heroes
      .where(
        (h) =>
            h.hero != null &&
            (h.hero!.officialId ?? h.hero!.guid) ==
                (hero.officialId ?? hero.guid),
      )
      .firstOrNull;
}
