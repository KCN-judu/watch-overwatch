import 'models.dart';
import 'overview.dart';

/// Whose matches a build statistic is over (`watch_core::stadium::Scope`).
enum BuildSample {
  own('own'),
  everyone('everyone');

  const BuildSample(this.id);
  final String id;
}

/// A power or item on one hero (`watch_core::stadium::UpgradeStat`).
class UpgradeStat {
  UpgradeStat(Json j)
    : upgrade = EntityRef.fromJson((j['upgrade'] as Json?) ?? const {}),
      round = (j['round'] as num?)?.toInt(),
      picks = (j['picks'] as num?)?.toInt() ?? 0,
      pickRatePct = (j['pick_rate_pct'] as num?)?.toDouble() ?? 0,
      record = OverviewRecord(j['record'] as Json?),
      matchIds = [
        for (final id in (j['match_ids'] as List?) ?? const []) '$id',
      ];
  final EntityRef upgrade;

  /// The round it is usually taken in (1-based).
  final int? round;
  final int picks;
  final double pickRatePct;
  final OverviewRecord record;

  /// The player's own matches with it, newest first.
  final List<String> matchIds;
}

/// A set of powers taken together.
class BuildStat {
  BuildStat(Json j)
    : powers = [
        for (final p in (j['powers'] as List?) ?? const [])
          if (p is Map<String, dynamic>) EntityRef.fromJson(p),
      ],
      record = OverviewRecord(j['record'] as Json?),
      pickRatePct = (j['pick_rate_pct'] as num?)?.toDouble() ?? 0,
      matchIds = [
        for (final id in (j['match_ids'] as List?) ?? const []) '$id',
      ];
  final List<EntityRef> powers;
  final OverviewRecord record;
  final double pickRatePct;
  final List<String> matchIds;
}

class HeroBuilds {
  HeroBuilds(Json j)
    : hero = EntityRef.fromJson((j['hero'] as Json?) ?? const {}),
      matches = (j['matches'] as num?)?.toInt() ?? 0,
      ownMatches = (j['own_matches'] as num?)?.toInt() ?? 0,
      record = OverviewRecord(j['record'] as Json?),
      powers = _list(j['powers'], UpgradeStat.new),
      items = _list(j['items'], UpgradeStat.new),
      builds = _list(j['builds'], BuildStat.new);
  final EntityRef hero;
  final int matches, ownMatches;
  final OverviewRecord record;
  final List<UpgradeStat> powers, items;
  final List<BuildStat> builds;
}

class StadiumResult {
  StadiumResult(Json j)
    : enabled = j['enabled'] == true,
      details = ((j['stadium'] as Json?)?['details'] as num?)?.toInt() ?? 0,
      heroes = _list((j['stadium'] as Json?)?['heroes'], HeroBuilds.new);
  final bool enabled;

  /// Stored Stadium matches the sample came from.
  final int details;
  final List<HeroBuilds> heroes;

  HeroBuilds? of(EntityRef hero) =>
      heroes.where((h) => h.hero.guid == hero.guid).firstOrNull;
}

/// One round of a Stadium match for the player (`watch_core::stadium::RoundStep`).
class RoundStep {
  RoundStep(Json j)
    : round = (j['round'] as num?)?.toInt() ?? 0,
      won = j['won'] is bool ? j['won'] as bool : null,
      powers = _list(j['powers'], EntityRef.fromJson),
      items = _list(j['items'], EntityRef.fromJson),
      worth = (j['worth'] as num?)?.toDouble();
  final int round;
  final bool? won;
  final List<EntityRef> powers, items;
  final double? worth;
}

List<T> _list<T>(Object? v, T Function(Json) f) => [
  for (final e in (v as List?) ?? const [])
    if (e is Map<String, dynamic>) f(e),
];
