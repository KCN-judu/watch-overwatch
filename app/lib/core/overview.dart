import 'models.dart';

int? _i(Object? v) => v is num ? v.toInt() : null;
double? _d(Object? v) => v is num ? v.toDouble() : null;
String? _s(Object? v) => v is String && v.isNotEmpty ? v : null;
List<T> _list<T>(Object? v, T Function(Json) f) => [
  for (final e in (v as List?) ?? const [])
    if (e is Map<String, dynamic>) f(e),
];

/// A win–loss record as the service counts it (`watch_core::analysis::Record`).
class OverviewRecord {
  OverviewRecord(Json? j)
    : matches = _i(j?['matches']) ?? 0,
      wins = _i(j?['wins']) ?? 0,
      losses = _i(j?['losses']) ?? 0,
      draws = _i(j?['draws']) ?? 0,
      winRatePct = _d(j?['win_rate_pct']),
      lowPct = _d(j?['win_rate_low_pct']),
      highPct = _d(j?['win_rate_high_pct']),
      enough = j?['enough'] == true;
  final int matches, wins, losses, draws;

  /// Wins over decided matches (draws and unknown results left out).
  final double? winRatePct;

  /// Its plausible range (Wilson, 95 %).
  final double? lowPct, highPct;

  /// Enough decided matches to be compared.
  final bool enough;
  int get decided => wins + losses;
}

class OverviewAggregate {
  OverviewAggregate(Json? j)
    : record = OverviewRecord(j?['record'] as Json?),
      perMatch = StatLine.fromJson(j?['per_match'] as Json?),
      kda = _d(j?['kda']),
      streak = _i((j?['streaks'] as Json?)?['current']) ?? 0;
  final OverviewRecord record;
  final StatLine perMatch;
  final double? kda;

  /// Positive: current win streak; negative: loss streak.
  final int streak;
}

class OverviewGroup {
  OverviewGroup(Json j)
    : key = _s(j['key']) ?? '',
      label = _s(j['label']),
      aggregate = OverviewAggregate(j['aggregate'] as Json?);
  final String key;
  final String? label;
  final OverviewAggregate aggregate;
}

class FormPoint {
  FormPoint(Json j)
    : matchId = _s(j['match_id']) ?? '',
      startedAtMs = _i(j['started_at_ms']),
      outcome = Outcome.parse(_s(j['outcome'])),
      hero = EntityRef.opt(j['hero']),
      role = Role.parse(_s(j['role'])),
      map = EntityRef.opt(j['map']);
  final String matchId;
  final int? startedAtMs;
  final Outcome outcome;
  final EntityRef? hero;
  final Role role;
  final EntityRef? map;
}

enum InsightKind {
  streak,
  recentForm,
  map,
  hero,
  unknown;

  static InsightKind parse(String? v) => switch (v) {
    'streak' => streak,
    'recent_form' => recentForm,
    'map' => map,
    'hero' => hero,
    _ => unknown,
  };
}

/// A finding the service considers firm enough to say (the app words it).
class Insight {
  Insight(Json j)
    : kind = InsightKind.parse(_s(j['kind'])),
      positive = j['positive'] == true,
      subject = _s(j['subject']),
      value = _d(j['value']) ?? 0,
      other = _d(j['other']),
      n = _i(j['n']) ?? 0,
      key = _s(j['key']);
  final InsightKind kind;
  final bool positive;
  final String? subject;
  final double value;
  final double? other;
  final int n;

  /// The hero or map it is about, for drilling down.
  final String? key;
}

class Overview {
  Overview(Json j)
    : overall = OverviewAggregate(j['overall'] as Json?),
      recent = OverviewAggregate(j['recent'] as Json?),
      before = OverviewAggregate(j['before'] as Json?),
      windows = {
        for (final w in (j['windows'] as List?) ?? const [])
          if (w is Map<String, dynamic> && _s(w['window']) != null)
            _s(w['window'])!: OverviewAggregate(w['aggregate'] as Json?),
      },
      byRole = _list(j['by_role'], OverviewGroup.new),
      byHero = _list(j['by_hero'], OverviewGroup.new),
      byMap = _list(j['by_map'], OverviewGroup.new),
      heat = [
        for (final day in (j['heat'] as List?) ?? const [])
          [
            for (final r in (day as List?) ?? const [])
              OverviewRecord(r as Json?),
          ],
      ],
      sessions = [
        for (final s in (j['sessions'] as List?) ?? const [])
          if (s is Map<String, dynamic>)
            (
              startMs: _i(s['start_ms']),
              lastStartMs: _i(s['last_start_ms']),
              aggregate: OverviewAggregate(s['aggregate'] as Json?),
            ),
      ],
      form = _list(j['form'], FormPoint.new),
      rollingWinPct = [
        for (final v in (j['rolling_win_pct'] as List?) ?? const []) _d(v),
      ],
      insights = _list(j['insights'], Insight.new);
  final OverviewAggregate overall, recent, before;

  /// By window name: `today`, `yesterday`, `week`.
  final Map<String, OverviewAggregate> windows;
  final List<OverviewGroup> byRole, byHero, byMap;

  /// `heat[weekday][hour]`, Monday first.
  final List<List<OverviewRecord>> heat;
  final List<({int? startMs, int? lastStartMs, OverviewAggregate aggregate})>
  sessions;

  /// The newest matches, oldest first.
  final List<FormPoint> form;
  final List<double?> rollingWinPct;
  final List<Insight> insights;
}

class OverviewResult {
  OverviewResult(Json j)
    : enabled = j['enabled'] == true,
      listed = _i(j['listed']) ?? 0,
      overview = j['overview'] is Map<String, dynamic>
          ? Overview(j['overview'] as Json)
          : null;
  final bool enabled;

  /// Matches in the stored list it is worked out from.
  final int listed;
  final Overview? overview;
}
