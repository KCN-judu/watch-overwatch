import 'models.dart';
import 'overview.dart';

/// A player met in the stored matches (`watch_core::party::Mate`).
class Mate {
  Mate(Json j)
    : key = (j['key'] as String?) ?? '',
      name = j['name'] as String?,
      asAlly = OverviewRecord(j['as_ally'] as Json?),
      asEnemy = OverviewRecord(j['as_enemy'] as Json?),
      inParty = (j['in_party'] as num?)?.toInt() ?? 0,
      lastMs = (j['last_ms'] as num?)?.toInt(),
      matchIds = [
        for (final id in (j['match_ids'] as List?) ?? const []) '$id',
      ];
  final String key;
  final String? name;

  /// The player's results with them on their side, and against them.
  final OverviewRecord asAlly, asEnemy;
  final int inParty;
  final int? lastMs;

  /// Shared matches, newest first.
  final List<String> matchIds;
  int get shared => matchIds.length;
}

class PeopleResult {
  PeopleResult(Json j)
    : enabled = j['enabled'] == true,
      details = ((j['people'] as Json?)?['details'] as num?)?.toInt() ?? 0,
      mates = [
        for (final m in ((j['people'] as Json?)?['mates'] as List?) ?? const [])
          if (m is Map<String, dynamic>) Mate(m),
      ],
      party = OverviewRecord((j['people'] as Json?)?['party'] as Json?),
      solo = OverviewRecord((j['people'] as Json?)?['solo'] as Json?),
      partySize = {
        for (final e
            in (((j['people'] as Json?)?['party_size'] as Map?) ?? const {})
                .entries)
          '${e.key}': (e.value as num).toInt(),
      };
  final bool enabled;

  /// Stored details the lists come from.
  final int details;
  final List<Mate> mates;
  final OverviewRecord party, solo;

  /// Group size per stored match (1 = alone).
  final Map<String, int> partySize;
}

/// One match both players were in (`watch_core::party::SharedMatch`).
class SharedMatch {
  SharedMatch(Json j)
    : matchId = (j['match_id'] as String?) ?? '',
      startedAtMs = (j['started_at_ms'] as num?)?.toInt(),
      map = EntityRef.opt(j['map']),
      outcome = Outcome.parse(j['outcome'] as String?),
      sameSide = j['same_side'] == true,
      grouped = j['grouped'] == true,
      meHero = EntityRef.opt(j['me_hero']),
      me = StatLine.fromJson(j['me'] as Json?),
      themHero = EntityRef.opt(j['them_hero']),
      them = StatLine.fromJson(j['them'] as Json?);
  final String matchId;
  final int? startedAtMs;
  final EntityRef? map;
  final Outcome outcome;
  final bool sameSide, grouped;
  final EntityRef? meHero, themHero;
  final StatLine me, them;
}

class DuoResult {
  DuoResult(Json j)
    : name = (j['duo'] as Json?)?['name'] as String?,
      matches = [
        for (final m in ((j['duo'] as Json?)?['matches'] as List?) ?? const [])
          if (m is Map<String, dynamic>) SharedMatch(m),
      ],
      withThem = OverviewRecord((j['duo'] as Json?)?['with'] as Json?),
      without = OverviewRecord((j['duo'] as Json?)?['without'] as Json?),
      against = OverviewRecord((j['duo'] as Json?)?['against'] as Json?);
  final String? name;
  final List<SharedMatch> matches;
  final OverviewRecord withThem, without, against;
}
