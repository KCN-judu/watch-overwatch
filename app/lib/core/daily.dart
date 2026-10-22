import 'models.dart';
import 'overview.dart';

List<T> _list<T>(Object? v, T Function(Json) f) => [
  for (final e in (v as List?) ?? const [])
    if (e is Map<String, dynamic>) f(e),
];

/// One day with matches (`watch_core::daily::DayEntry`).
class DayEntry {
  DayEntry(Json j)
    : day = (j['day'] as String?) ?? '',
      record = OverviewRecord(j['record'] as Json?);

  /// `YYYY-MM-DD`.
  final String day;
  final OverviewRecord record;
}

enum HighlightKind {
  lobbyTop('lobby_top'),
  dayBest('day_best'),
  personalRecord('personal_record'),
  streak('streak'),
  deathless('deathless'),
  bestMatch('best_match'),
  bestFleta('best_fleta'),
  unknown('');

  const HighlightKind(this.id);
  final String id;
  static HighlightKind parse(String? v) => values.firstWhere(
    (k) => k.id == v && k != unknown,
    orElse: () => unknown,
  );
}

class DayHighlight {
  DayHighlight(Json j)
    : kind = HighlightKind.parse(j['kind'] as String?),
      stat = (j['stat'] as String?) ?? '',
      value = (j['value'] as num?)?.toDouble() ?? 0,
      matchId = j['match_id'] as String?,
      hero = EntityRef.opt(j['hero']),
      map = EntityRef.opt(j['map']),
      previous = (j['previous'] as num?)?.toDouble();
  final HighlightKind kind;

  /// `kills`, `damage`, `healing`, `mitigation`, `kda`, `fleta`, or empty.
  final String stat;
  final double value;
  final String? matchId;
  final EntityRef? hero, map;

  /// For a record: the previous best.
  final double? previous;
}

class Versus {
  Versus(Json j)
    : stat = (j['stat'] as String?) ?? '',
      today = (j['today'] as num?)?.toDouble() ?? 0,
      usual = (j['usual'] as num?)?.toDouble() ?? 0,
      todayN = (j['today_n'] as num?)?.toInt() ?? 0,
      usualN = (j['usual_n'] as num?)?.toInt() ?? 0;
  final String stat;
  final double today, usual;
  final int todayN, usualN;
}

class RankChange {
  RankChange(Json j)
    : role = Role.parse(j['role'] as String?),
      from = (j['from'] as num?)?.toInt() ?? 0,
      to = (j['to'] as num?)?.toInt() ?? 0;
  final Role role;
  final int from, to;
}

class DailySummary {
  DailySummary(Json j)
    : day = (j['day'] as String?) ?? '',
      aggregate = OverviewAggregate(j['aggregate'] as Json?),
      sittings = (j['sittings'] as num?)?.toInt() ?? 0,
      firstMs = (j['first_ms'] as num?)?.toInt(),
      lastMs = (j['last_ms'] as num?)?.toInt(),
      playS = (j['play_s'] as num?)?.toDouble(),
      playSamples = (j['play_samples'] as num?)?.toInt() ?? 0,
      heroes = _list(j['heroes'], OverviewGroup.new),
      maps = _list(j['maps'], OverviewGroup.new),
      rankChanges = _list(j['rank_changes'], RankChange.new),
      highlights = _list(j['highlights'], DayHighlight.new),
      versusRole = j['versus_role'] == null
          ? null
          : Role.parse(j['versus_role'] as String?),
      versus = _list(j['versus'], Versus.new),
      matchIds = [
        for (final id in (j['match_ids'] as List?) ?? const []) '$id',
      ];
  final String day;
  final OverviewAggregate aggregate;
  final int sittings;
  final int? firstMs, lastMs;

  /// Total length of the matches with a stored detail, over [playSamples] of them.
  final double? playS;
  final int playSamples;
  final List<OverviewGroup> heroes, maps;
  final List<RankChange> rankChanges;
  final List<DayHighlight> highlights;

  /// The day's main role, which [versus] is about.
  final Role? versusRole;
  final List<Versus> versus;

  /// Newest first.
  final List<String> matchIds;
}

class DailyResult {
  DailyResult(Json j)
    : enabled = j['enabled'] == true,
      days = _list((j['daily'] as Json?)?['days'], DayEntry.new),
      summary = (j['daily'] as Json?)?['summary'] is Map<String, dynamic>
          ? DailySummary((j['daily'] as Json)['summary'] as Json)
          : null;
  final bool enabled;

  /// Newest first.
  final List<DayEntry> days;
  final DailySummary? summary;
}
