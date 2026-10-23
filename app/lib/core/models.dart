// Dart mirror of `watch-core::ir`. Field names follow the Rust serde output
// (snake_case). Missing or malformed values become null, never zero.
import '../l10n/strings.dart';
import 'stadium.dart';

typedef Json = Map<String, dynamic>;

double? _d(Object? v) => v is num
    ? v.toDouble()
    : v is String
    ? double.tryParse(v)
    : null;
int? _i(Object? v) => _d(v)?.round();
String? _s(Object? v) => v is String && v.isNotEmpty ? v : null;
bool _b(Object? v) => v == true;
Json? _o(Object? v) => v is Map<String, dynamic> ? v : null;
List<T> _list<T>(Object? v, T Function(Json) f) => v is List
    ? [
        for (final e in v)
          if (e is Map<String, dynamic>) f(e),
      ]
    : <T>[];

enum Mode {
  competitive('competitive', 'sport'),
  quick('quick', 'leisure'),
  stadium('stadium', 'SportFight');

  const Mode(this.id, this.provider);
  final String id;
  final String provider;
  String get label => switch (this) {
    Mode.competitive => tr.core.modeCompetitive,
    Mode.quick => tr.core.modeQuick,
    Mode.stadium => tr.core.modeStadium,
  };

  /// Two-character name for dense controls; [label] stays the full name.
  String get shortLabel => switch (this) {
    Mode.competitive => tr.core.modeCompetitiveShort,
    Mode.quick => tr.core.modeQuickShort,
    Mode.stadium => tr.core.modeStadiumShort,
  };
  static Mode parse(String? v) =>
      Mode.values.firstWhere((m) => m.id == v, orElse: () => Mode.competitive);
}

enum Role {
  tank('tank'),
  damage('damage'),
  support('support'),
  open('open'),
  unknown('unknown');

  const Role(this.id);
  final String id;
  String get label => switch (this) {
    Role.tank => tr.core.roleTank,
    Role.damage => tr.core.roleDamage,
    Role.support => tr.core.roleSupport,
    Role.open => tr.core.roleOpen,
    Role.unknown => '',
  };
  static Role parse(String? v) =>
      Role.values.firstWhere((r) => r.id == v, orElse: () => Role.unknown);
  static const playable = [Role.tank, Role.damage, Role.support];

  /// This role if it is one a player queues as, otherwise [fallback].
  Role playableOr(Role fallback) => playable.contains(this) ? this : fallback;
}

enum Outcome {
  win('win'),
  loss('loss'),
  draw('draw'),
  unknown('unknown');

  const Outcome(this.id);
  final String id;
  String get label => switch (this) {
    Outcome.win => tr.core.outcomeWin,
    Outcome.loss => tr.core.outcomeLoss,
    Outcome.draw => tr.core.outcomeDraw,
    Outcome.unknown => tr.common.missing,
  };
  static Outcome parse(String? v) => Outcome.values.firstWhere(
    (o) => o.id == v,
    orElse: () => Outcome.unknown,
  );
}

enum Queue {
  roleQueue('role_queue'),
  openQueue('open_queue'),
  sixVsSix('six_vs_six'),
  unknown('unknown');

  const Queue(this.id);
  final String id;
  String get label => switch (this) {
    Queue.roleQueue => tr.core.queueRole,
    Queue.openQueue => tr.core.queueOpen,
    Queue.sixVsSix => '6v6',
    Queue.unknown => '',
  };
  static Queue parse(String? v) =>
      Queue.values.firstWhere((q) => q.id == v, orElse: () => Queue.unknown);
}

class EntityRef {
  const EntityRef(this.kind, this.guid, this.name, this.officialId);
  final String kind;
  final String guid;
  final String? name;
  final String? officialId;
  factory EntityRef.fromJson(Json j) => EntityRef(
    _s(j['kind']) ?? '',
    _s(j['guid']) ?? '',
    _s(j['name']),
    _s(j['official_id']),
  );
  static EntityRef? opt(Object? v) =>
      _o(v) == null ? null : EntityRef.fromJson(_o(v)!);
  String get label =>
      name ??
      tr.core.unknownEntity(
        guid.length > 6 ? '…${guid.substring(guid.length - 6)}' : guid,
      );
}

/// The catalog's tier names (`Catalog.rankName`), installed when the catalog loads; a
/// rank names itself without a catalog at hand.
String? Function(String tier, {bool stadium})? rankNames;

/// Display name of a tier: the catalog's (the provider's own), else the string table's
/// copy of the same names. Stadium has its own ladder with its own names.
String? tierName(String tier, {bool stadium = false}) =>
    rankNames?.call(tier, stadium: stadium) ??
    (stadium ? tr.core.tiersStadium : tr.core.tiers)[tier];

/// The normal ladder's tier floors. Stadium ratings are on a scale of their own that
/// has not been checked against real data, so no tier is worked out from them.
const _tierBases = [
  ('Bronze', 500),
  ('Silver', 1000),
  ('Gold', 1500),
  ('Platinum', 2000),
  ('Emerald', 2500),
  ('Diamond', 3000),
  ('Master', 3500),
  ('Grandmaster', 4000),
  ('Champion', 4500),
];

/// `2350` → `('Platinum', 2)`. Null when the rating is outside the ladder.
(String, int)? ratingTier(num? skillRating) {
  if (skillRating == null || skillRating < 500) return null;
  var tier = _tierBases.first;
  for (final t in _tierBases) {
    if (skillRating >= t.$2) tier = t;
  }
  final step = ((skillRating - tier.$2) / 100).floor().clamp(0, 4);
  return (tier.$1, 5 - step);
}

/// `2350` → `白金 2`. Null when the rating is outside the ladder, and for Stadium
/// ratings (see [_tierBases]).
String? ratingLabel(num? skillRating, {bool stadium = false}) {
  final t = stadium ? null : ratingTier(skillRating);
  final name = t == null ? null : tierName(t.$1);
  return name == null ? null : tr.core.rank(name, t!.$2);
}

class Rank {
  const Rank(this.tier, this.division, this.score, this.skillRating);
  final String? tier;
  final int? division;
  final int? score;
  final int? skillRating;
  factory Rank.fromJson(Json j) => Rank(
    _s(j['tier']),
    _i(j['division']),
    _i(j['score']),
    _i(j['skill_rating']),
  );
  static Rank? opt(Object? v) => _o(v) == null ? null : Rank.fromJson(_o(v)!);

  /// The provider's tier key, or the one the rating falls in when only a rating is
  /// known (a rank borrowed from another role), so the emblem can still be shown.
  /// Stadium ranks only use the provider's key.
  String? tierKey({bool stadium = false}) =>
      tier ?? (stadium ? null : ratingTier(skillRating)?.$1);

  /// The division, worked out from the rating the same way when the provider gave none.
  int? divisionOrRating({bool stadium = false}) =>
      division ??
      (tier == null && !stadium ? ratingTier(skillRating)?.$2 : null);

  /// On the normal ladder: 白金 2, 英杰 1. On the Stadium ladder: 精英 3, 传奇 1.
  String get label => labelOn();

  /// [label] on the given ladder. Tier and division from the provider; else the
  /// rating's place on the normal ladder; a Stadium rank with only a rating shows it.
  String labelOn({bool stadium = false}) {
    final name = tier == null ? null : tierName(tier!, stadium: stadium);
    if (name != null) return tr.core.rank(name, division);
    if (stadium && skillRating != null) {
      return tr.core.ratingOnly(skillRating.toString());
    }
    return ratingLabel(skillRating, stadium: stadium) ?? tr.common.unranked;
  }
}

class StatLine {
  const StatLine({
    this.kills,
    this.assists,
    this.deaths,
    this.damage,
    this.healing,
    this.mitigation,
    this.finalBlows,
    this.soloKills,
    this.damageTaken,
    this.healingTaken,
    this.objectiveTimeS,
  });
  final double? kills,
      assists,
      deaths,
      damage,
      healing,
      mitigation,
      finalBlows,
      soloKills,
      damageTaken,
      healingTaken,
      objectiveTimeS;
  factory StatLine.fromJson(Json? j) => j == null
      ? const StatLine()
      : StatLine(
          kills: _d(j['kills']),
          assists: _d(j['assists']),
          deaths: _d(j['deaths']),
          damage: _d(j['damage']),
          healing: _d(j['healing']),
          mitigation: _d(j['mitigation']),
          finalBlows: _d(j['final_blows']),
          soloKills: _d(j['solo_kills']),
          damageTaken: _d(j['damage_taken']),
          healingTaken: _d(j['healing_taken']),
          objectiveTimeS: _d(j['objective_time_s']),
        );
  double? field(String name) => switch (name) {
    'kills' => kills,
    'assists' => assists,
    'deaths' => deaths,
    'damage' => damage,
    'healing' => healing,
    'mitigation' => mitigation,
    _ => null,
  };
}

class Highlights {
  const Highlights(this.kills, this.damage, this.healing, this.mitigation);
  final bool kills, damage, healing, mitigation;
  static Highlights? opt(Object? v) {
    final j = _o(v);
    return j == null
        ? null
        : Highlights(
            _b(j['kills']),
            _b(j['damage']),
            _b(j['healing']),
            _b(j['mitigation']),
          );
  }
}

class MatchSummary {
  MatchSummary(Json j)
    : raw = j,
      id = _s(j['id']) ?? '',
      startedAtMs = _i(j['started_at_ms']),
      mode = Mode.parse(_s(_o(j['kind'])?['mode'])),
      queue = Queue.parse(_s(_o(j['kind'])?['queue'])),
      ranked = _o(j['kind'])?['ranked'] as bool?,
      outcome = Outcome.parse(_s(j['outcome'])),
      map = EntityRef.opt(j['map']),
      hero = EntityRef.opt(j['hero']),
      role = Role.parse(_s(j['role'])),
      scoreTeam = _i(_o(j['score'])?['team']),
      scoreOpponent = _i(_o(j['score'])?['opponent']),
      stats = StatLine.fromJson(_o(j['stats'])),
      highlights = Highlights.opt(j['highlights']),
      rank = Rank.opt(j['rank']),
      heroIconUrl = _s(j['hero_icon_url']);

  /// The row as the service sent it; sent back unchanged when this match is analysed.
  final Json raw;
  final String id;
  final int? startedAtMs;
  final Mode mode;
  final Queue queue;
  final bool? ranked;
  final Outcome outcome;
  final EntityRef? map;
  final EntityRef? hero;
  final Role role;
  final int? scoreTeam, scoreOpponent;
  final StatLine stats;
  final Highlights? highlights;
  final Rank? rank;
  final String? heroIconUrl;

  DateTime? get startedAt => startedAtMs == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(startedAtMs!);
}

class StatValue {
  StatValue(Json j)
    : stat = EntityRef.fromJson(_o(j['stat']) ?? const {}),
      value = _d(j['value']);
  final EntityRef stat;

  /// Null when the provider sent something that is not a number: missing, never 0.
  final double? value;
}

class PerkPick {
  PerkPick(Json j)
    : perk = EntityRef.fromJson(_o(j['perk']) ?? const {}),
      level = _i(j['level']);
  final EntityRef perk;
  final int? level;
}

class StadiumBuild {
  StadiumBuild(Json j)
    : worth = _d(j['worth']),
      powers = _list(j['powers'], EntityRef.fromJson),
      items = _list(j['items'], EntityRef.fromJson);
  final double? worth;
  final List<EntityRef> powers, items;
}

class Participant {
  Participant(Json j)
    : name = _s(j['name']),
      bnetId = _s(j['bnet_id']),
      isSubject = _b(j['is_subject']),
      hero = EntityRef.opt(j['hero']),
      role = Role.parse(_s(j['role'])),
      stats = StatLine.fromJson(_o(j['stats'])),
      rank = Rank.opt(j['rank']),
      careerRank = Rank.opt(j['career_rank']),
      careerOtherRoles = _b(j['career_other_roles']),
      careerRankAtMs = (j['career_rank_at_ms'] as num?)?.toInt(),
      fleta = _d(j['fleta']),
      endorsedBy = [
        for (final e in (j['endorsed_by_bnet_ids'] as List? ?? const [])) '$e',
      ],
      perks = _list(j['perks'], PerkPick.new),
      partyBnetIds = [
        for (final e in (j['party_bnet_ids'] as List? ?? const [])) '$e',
      ],
      suspended = _b(j['suspended']),
      stadium = _o(j['stadium']) == null
          ? null
          : StadiumBuild(_o(j['stadium'])!);
  final String? name, bnetId;
  final bool isSubject;
  final EntityRef? hero;
  final Role role;
  final StatLine stats;

  /// The rank the match itself reported (competitive and Stadium).
  final Rank? rank;

  /// The player's own competitive rank now for this role, from what was looked up for the
  /// strength analysis; not the rank at the time of the match.
  final Rank? careerRank;

  /// [careerRank] is the highest of the player's ranks in other roles.
  final bool careerOtherRoles;

  /// When [careerRank] was looked up for this match (a snapshot kept with it); null while
  /// it has not been.
  final int? careerRankAtMs;

  /// Final blows as a percentage of half the player's team's final blows; null when
  /// either is unknown.
  final double? fleta;

  /// Who endorsed this player after the match (bnet ids).
  final List<String> endorsedBy;
  final List<PerkPick> perks;
  final List<String> partyBnetIds;
  final bool suspended;
  final StadiumBuild? stadium;
}

class HeroSegment {
  HeroSegment(Json j)
    : hero = EntityRef.fromJson(_o(j['hero']) ?? const {}),
      playTimeS = _d(j['play_time_s']),
      share = _d(j['share']),
      stats = _list(j['stats'], StatValue.new);
  final EntityRef hero;
  final double? playTimeS, share;
  final List<StatValue> stats;
}

class Round {
  Round(Json j)
    : index = _i(j['index']) ?? 0,
      scoreTeam = _i(_o(j['score'])?['team']),
      scoreOpponent = _i(_o(j['score'])?['opponent']),
      durationS = _d(j['duration_s']);
  final int index;
  final int? scoreTeam, scoreOpponent;
  final double? durationS;
}

class MatchDetail {
  MatchDetail(Json j, {this.ratingsPending = false})
    : id = _s(j['id']) ?? '',
      mode = Mode.parse(_s(j['mode'])),
      map = EntityRef.opt(j['map']),
      outcome = Outcome.parse(_s(j['outcome'])),
      outcomeFromScore = _s(j['outcome_source']) == 'score',
      startedAtMs = _i(j['started_at_ms']),
      durationS = _d(j['duration_s']),
      scoreTeam = _i(_o(j['score'])?['team']),
      scoreOpponent = _i(_o(j['score'])?['opponent']),
      bansAlly = _list(_o(j['bans'])?['ally'], EntityRef.fromJson),
      bansEnemy = _list(_o(j['bans'])?['enemy'], EntityRef.fromJson),
      subjectHeroes = _list(j['subject_heroes'], HeroSegment.new),
      allies = _list(j['allies'], Participant.new),
      enemies = _list(j['enemies'], Participant.new),
      rounds = _list(j['rounds'], Round.new),
      stadiumTimeline = _list(j['stadium_timeline'], RoundStep.new);
  final String id;

  /// The players' ranks are not all looked up yet; the table is shown first and filled
  /// in when they are.
  final bool ratingsPending;
  final Mode mode;
  final EntityRef? map;
  final Outcome outcome;
  final bool outcomeFromScore;
  final int? startedAtMs;
  final double? durationS;
  final int? scoreTeam, scoreOpponent;
  final List<EntityRef> bansAlly, bansEnemy;
  final List<HeroSegment> subjectHeroes;
  final List<Participant> allies, enemies;
  final List<Round> rounds;

  /// Stadium: what the player took round by round, and how each round went.
  final List<RoundStep> stadiumTimeline;
}

class PlayerProfile {
  PlayerProfile(Json j)
    : name = _s(j['name']),
      bnetId = _s(j['bnet_id']),
      avatarUrl = _s(j['avatar_url']),
      title = _s(j['title']),
      titleIconUrl = _s(j['title_icon_url']),
      endorsementLevel = _i(j['endorsement_level']),
      playTimeHours = _d(j['play_time_hours']),
      totalMatches = _i(j['total_matches']),
      suspensionStatus = _s(_o(j['suspension'])?['status']),
      suspensionExpiresMs = _i(_o(j['suspension'])?['expires_at_ms']),
      suspended = _o(j['suspension']) != null;
  final String? name, bnetId, avatarUrl, title;

  /// The title's own picture, when the provider has one.
  final String? titleIconUrl;
  final int? endorsementLevel, totalMatches;
  final double? playTimeHours;
  final bool suspended;
  final String? suspensionStatus;
  final int? suspensionExpiresMs;
}

class RoleCareer {
  RoleCareer(Json j)
    : role = Role.parse(_s(j['role'])),
      current = Rank.opt(j['current_rank']),
      peak = Rank.opt(j['peak_rank']),
      matches = _i(j['matches']),
      winRatePct = _d(j['win_rate_pct']),
      kda = _d(j['kda']),
      maxWinStreak = _i(j['max_win_streak']);
  final Role role;
  final Rank? current, peak;
  final int? matches, maxWinStreak;
  final double? winRatePct, kda;
}

class HeroUsage {
  HeroUsage(Json j)
    : queue = Queue.parse(_s(j['queue'])),
      hero = EntityRef.fromJson(_o(j['hero']) ?? const {}),
      heroLevel = _i(j['hero_level']),
      matches = _i(j['matches']),
      wins = _i(j['wins']),
      winRatePct = _d(j['win_rate_pct']),
      kda = _d(j['kda']),
      playTimeS = _d(j['play_time_s']),
      perMatch = _list(j['per_match'], StatValue.new),
      per10min = _list(j['per_10min'], StatValue.new);
  final Queue queue;
  final EntityRef hero;
  final int? heroLevel, matches, wins;
  final double? winRatePct, kda, playTimeS;
  final List<StatValue> perMatch, per10min;

  /// Average length of one match on this hero, in seconds.
  double? get avgMatchSeconds {
    for (final v in perMatch) {
      final value = v.value;
      if (v.stat.name == '累计游戏时间' && value != null && value > 0) return value;
    }
    final t = playTimeS, n = matches;
    return t != null && n != null && n > 0 ? t / n : null;
  }

  /// Rates, times and flags do not scale to "per 10 minutes".
  static bool scalesPer10(String name) =>
      !name.endsWith('率') &&
      !name.contains('游戏时间') &&
      !name.contains('英雄获胜') &&
      !name.contains('平均');

  /// Per-10-minute value of the stat the provider reports per match as [perMatchValue]:
  /// the provider's own figure when it gave one (they supply only a handful),
  /// otherwise average × 600 ÷ average match length. `derived` marks the second case.
  ({double value, bool derived})? per10For(StatValue perMatchValue) {
    for (final v in per10min) {
      if (v.stat.guid == perMatchValue.stat.guid) {
        final value = v.value;
        return value == null ? null : (value: value, derived: false);
      }
    }
    final name = perMatchValue.stat.name, secs = avgMatchSeconds;
    final value = perMatchValue.value;
    if (name == null ||
        value == null ||
        secs == null ||
        secs <= 0 ||
        !scalesPer10(name)) {
      return null;
    }
    return (value: value * 600 / secs, derived: true);
  }

  /// Per-10-minute value by stat name (provider's, else derived), for table columns.
  double? per10ByName(bool Function(String) match) {
    for (final v in per10min) {
      final n = v.stat.name;
      if (n != null && match(n)) return v.value;
    }
    for (final v in perMatch) {
      final n = v.stat.name;
      if (n != null && match(n)) return per10For(v)?.value;
    }
    return null;
  }
}

class Behavior {
  Behavior(Json j)
    : comment = _s(j['comment']),
      honorsReceived = _i(j['honors_received']),
      honorsSent = _i(j['honors_sent']),
      reports = _i(j['reports']);
  final String? comment;
  final int? honorsReceived, honorsSent, reports;
}

class ProvinceRank {
  ProvinceRank(Json j)
    : role = Role.parse(_s(j['role'])),
      province = _s(j['province']),
      rank = _i(j['rank']);
  final Role role;
  final String? province;
  final int? rank;
}

class CareerSnapshot {
  CareerSnapshot(Json j)
    : mode = Mode.parse(_s(j['mode'])),
      season = _i(j['season']),
      roles = _list(j['roles'], RoleCareer.new),
      heroes = _list(j['heroes'], HeroUsage.new),
      provinceRanks = _list(j['province_ranks'], ProvinceRank.new),
      serverAverage = _serverAverage(j['queues']),
      behavior = _o(j['behavior']) == null
          ? null
          : Behavior(_o(j['behavior'])!);
  final Mode mode;
  final int? season;
  final List<RoleCareer> roles;
  final List<HeroUsage> heroes;
  final List<ProvinceRank> provinceRanks;

  /// The provider's server-wide average per match (`serverMapCountData`), from the
  /// role queue when it has one: a reference line, not a peer group.
  final StatLine? serverAverage;

  static StatLine? _serverAverage(Object? queues) {
    StatLine? any;
    for (final q in (queues as List?) ?? const []) {
      if (q is! Map || q['server_average'] is! Map) continue;
      final s = StatLine.fromJson(
        (q['server_average'] as Map).cast<String, dynamic>(),
      );
      if (q['queue'] == 'role_queue') return s;
      any ??= s;
    }
    return any;
  }

  final Behavior? behavior;
  RoleCareer? role(Role r) {
    for (final c in roles) {
      if (c.role == r) return c;
    }
    return null;
  }
}

class SeasonPoint {
  SeasonPoint(Json j)
    : mode = Mode.parse(_s(j['mode'])),
      season = _i(j['season']),
      role = Role.parse(_s(j['role'])),
      matches = _i(j['matches']),
      winRatePct = _d(j['win_rate_pct']),
      kda = _d(j['kda']),
      current = Rank.opt(j['current_rank']),
      peak = Rank.opt(j['peak_rank']);
  final Mode mode;
  final int? season, matches;
  final Role role;
  final double? winRatePct, kda;
  final Rank? current, peak;
}

class HeroBoardEntry {
  HeroBoardEntry(Json j)
    : queue = Queue.parse(_s(j['queue'])),
      hero = EntityRef.opt(j['hero']),
      province = _s(j['province']),
      rank = _i(j['rank']),
      rankedLevel = _i(j['ranked_level']),
      matches = _i(j['matches']),
      winRatePct = _d(j['win_rate_pct']);
  final Queue queue;
  final EntityRef? hero;
  final String? province;
  final int? rank, rankedLevel, matches;
  final double? winRatePct;
}

class ListCoverage {
  ListCoverage(Json j)
    : mode = Mode.parse(_s(j['mode'])),
      pagesFetched = _i(j['pages_fetched']) ?? 0,
      exhausted = _b(j['exhausted']),
      newMatches = _i(j['new_matches']) ?? 0,
      totalMatches = _i(j['total_matches']) ?? 0;
  final Mode mode;
  final int pagesFetched;

  /// True when the stored list reaches the player's oldest match.
  final bool exhausted;

  /// Matches this read added to the local store, and how many it holds in all.
  final int newMatches, totalMatches;
}

class FetchRecord {
  FetchRecord(Json j)
    : endpoint = _s(j['endpoint']) ?? '',
      ok = _b(j['ok']),
      errorKind = _s(j['error_kind']);
  final String endpoint;
  final bool ok;
  final String? errorKind;
}

class Coverage {
  Coverage(Json? j)
    : matchLists = _list(j?['match_lists'], ListCoverage.new),
      detailsRequested = _i(j?['details_requested']) ?? 0,
      detailsOk = _i(j?['details_ok']) ?? 0,
      cacheHits = _i(j?['cache_hits']) ?? 0,
      fetches = _list(j?['fetches'], FetchRecord.new);
  final List<ListCoverage> matchLists;
  final int detailsRequested, detailsOk;

  /// Details and ratings taken from the local cache instead of the network.
  final int cacheHits;
  final List<FetchRecord> fetches;
  int get failures => fetches.where((f) => !f.ok).length;
}

class PlayerRating {
  PlayerRating(Json j)
    : bnetId = _s(j['bnet_id']) ?? '',
      hasRoles = (j['roles'] as List? ?? const []).isNotEmpty;
  final String bnetId;
  final bool hasRoles;
}

class PlayerDataset {
  PlayerDataset(Json j)
    : generatedAtMs = _i(j['generated_at_ms']) ?? 0,
      profile = PlayerProfile(_o(j['profile']) ?? const {}),
      careers = _list(j['careers'], CareerSnapshot.new),
      matches = _list(j['matches'], MatchSummary.new),
      heroBoards = _list(j['hero_boards'], HeroBoardEntry.new),
      ratings = _list(j['player_ratings'], PlayerRating.new),
      coverage = Coverage(_o(j['coverage']));
  final int generatedAtMs;
  final PlayerProfile profile;
  final List<CareerSnapshot> careers;
  final List<MatchSummary> matches;
  final List<HeroBoardEntry> heroBoards;
  final List<PlayerRating> ratings;
  final Coverage coverage;
  DateTime get generatedAt =>
      DateTime.fromMillisecondsSinceEpoch(generatedAtMs);
  CareerSnapshot? career(Mode m) {
    for (final c in careers) {
      if (c.mode == m && c.season == null) return c;
    }
    return null;
  }
}

// ---- Lobby strength -------------------------------------------------------

class RoleMeans {
  RoleMeans(Json? j)
    : overall = _d(j?['overall']),
      tank = _d(j?['tank']),
      damage = _d(j?['damage']),
      support = _d(j?['support']);
  final double? overall, tank, damage, support;

  /// `null` selects the overall slot.
  double? slot(Role? r) => switch (r) {
    null => overall,
    Role.tank => tank,
    Role.damage => damage,
    Role.support => support,
    _ => null,
  };
}

class RoleCounts {
  RoleCounts(Json? j)
    : overall = _i(j?['overall']) ?? 0,
      tank = _i(j?['tank']) ?? 0,
      damage = _i(j?['damage']) ?? 0,
      support = _i(j?['support']) ?? 0;
  final int overall, tank, damage, support;
}

class SideStrength {
  SideStrength(Json? j)
    : mean = RoleMeans(_o(j?['mean'])),
      min = RoleMeans(_o(j?['min'])),
      max = RoleMeans(_o(j?['max'])),
      rated = RoleCounts(_o(j?['rated'])),
      otherRole = _i(j?['other_role']) ?? 0,
      players = _i(j?['players']) ?? 0;

  /// Lowest and highest rated player per slot: the spread behind [mean].
  final RoleMeans mean, min, max;
  final RoleCounts rated;

  /// Of the rated players, how many have no rank for the role they played and are rated
  /// by the highest of their ranks in other roles.
  final int otherRole;
  final int players;
}

class MatchStrength {
  MatchStrength(Json j)
    : matchId = _s(j['match_id']) ?? '',
      startedAtMs = _i(j['started_at_ms']),
      mode = Mode.parse(_s(j['mode'])),
      outcome = Outcome.parse(_s(j['outcome'])),
      subjectRole = Role.parse(_s(j['subject_role'])),
      source = _s(j['source']) ?? 'none',
      ally = SideStrength(_o(j['ally'])),
      enemy = SideStrength(_o(j['enemy'])),
      lobby = RoleMeans(_o(j['lobby'])),
      diff = RoleMeans(_o(j['diff']));
  final String matchId;
  final int? startedAtMs;
  final Mode mode;
  final Outcome outcome;
  final Role subjectRole;
  final String source;
  final SideStrength ally, enemy;
  final RoleMeans lobby, diff;

  /// False when nobody in the match could be rated: kept in the list as a gap.
  bool get hasData => source != 'none';
}

class StrengthGroup {
  StrengthGroup(Json j)
    : mode = Mode.parse(_s(j['mode'])),
      subjectRole = _s(j['subject_role']) == null
          ? null
          : Role.parse(_s(j['subject_role'])),
      matches = _i(_o(j['record'])?['matches']) ?? 0,
      wins = _i(_o(j['record'])?['wins']) ?? 0,
      losses = _i(_o(j['record'])?['losses']) ?? 0,
      winRatePct = _d(_o(j['record'])?['win_rate_pct']),
      lobby = RoleMeans(_o(j['lobby'])),
      ally = RoleMeans(_o(j['ally'])),
      enemy = RoleMeans(_o(j['enemy'])),
      diff = RoleMeans(_o(j['diff']));
  final Mode mode;
  final Role? subjectRole;
  final int matches, wins, losses;
  final double? winRatePct;
  final RoleMeans lobby, ally, enemy, diff;
}

class LobbyStrength {
  LobbyStrength(Json? j)
    : matches = _list(j?['matches'], MatchStrength.new),
      byMode = _list(j?['by_mode'], StrengthGroup.new),
      bySubjectRole = _list(j?['by_subject_role'], StrengthGroup.new);
  final List<MatchStrength> matches;
  final List<StrengthGroup> byMode, bySubjectRole;
}

/// Where a running analysis is, as reported by the local service.
/// `phase` is list, details, ratings, finish or done.
class AnalysisProgress {
  AnalysisProgress(Json j, {this.phaseSince})
    : phase = _s(_o(j['progress'])?['phase']) ?? 'list',
      done = _i(_o(j['progress'])?['done']) ?? 0,
      total = _i(_o(j['progress'])?['total']) ?? 0,
      note = _s(_o(j['progress'])?['note']) ?? '',
      matchesFound = _i(_o(j['progress'])?['matches_found']) ?? 0,
      cached = _i(_o(j['progress'])?['cached']) ?? 0,
      requests = _i(_o(j['progress'])?['requests']) ?? 0,
      failures = _i(_o(j['progress'])?['failures']) ?? 0,
      elapsedMs = _i(j['elapsed_ms']) ?? 0;
  final String phase, note;
  final int done, total, matchesFound, requests, failures, cached, elapsedMs;

  /// When this phase was first seen by the client, for the remaining-time estimate.
  final DateTime? phaseSince;

  static const phases = ['list', 'details', 'ratings', 'finish'];
  int get phaseIndex => phase == 'done'
      ? phases.length
      : phases.indexOf(phase).clamp(0, phases.length - 1);

  /// Seconds left in the current phase, once a few items are done.
  int? get remainingSeconds {
    if (total <= 0 || done < 2 || done >= total || phaseSince == null) {
      return null;
    }
    final spent = DateTime.now().difference(phaseSince!).inMilliseconds;
    return (spent / done * (total - done) / 1000).round();
  }
}

/// Result of `/api/player/dataset` with lobby ratings enabled.
class StrengthResult {
  StrengthResult(Json j)
    : dataset = PlayerDataset(_o(j['dataset']) ?? const {}),
      lobby = LobbyStrength(_o(_o(j['analysis'])?['lobby_strength']));
  final PlayerDataset dataset;
  final LobbyStrength lobby;
}

/// One match as the growth panel sees it (see `growth.rs`): how long the subject lasted
/// per death, their Fleta index and their KDA.
class GrowthPoint {
  GrowthPoint(Json j)
    : matchId = _s(j['match_id']) ?? '',
      startedAtMs = _i(j['started_at_ms']),
      role = Role.parse(_s(j['role'])),
      hero = EntityRef.opt(j['hero']),
      outcome = Outcome.parse(_s(j['outcome'])),
      durationS = _d(j['duration_s']) ?? 0,
      deaths = _d(j['deaths']) ?? 0,
      lifeS = _d(j['life_s']) ?? 0,
      deathless = j['deathless'] == true,
      fleta = _d(j['fleta']),
      kda = _d(j['kda']),
      healing10 = _d(j['healing10']),
      mitigation10 = _d(j['mitigation10']);
  final String matchId;
  final int? startedAtMs;
  final Role role;
  final EntityRef? hero;
  final Outcome outcome;
  final double durationS, deaths;

  /// Seconds per death; the whole match when [deathless] (then it is a lower bound).
  final double lifeS;
  final bool deathless;
  final double? fleta, kda;

  /// Per 10 minutes; only for a support match (healing) or a tank match (mitigation).
  final double? healing10, mitigation10;
}

enum GrowthMetric {
  life,
  fleta,
  kda,
  healing,
  mitigation;

  static GrowthMetric? parse(String? v) =>
      GrowthMetric.values.where((m) => m.name == v).firstOrNull;
}

enum Trend {
  up,
  down,
  flat;

  static Trend parse(String? v) =>
      Trend.values.firstWhere((t) => t.name == v, orElse: () => flat);
}

/// How firmly a finding may be worded (`watch_core::stats::Confidence`).
enum Confidence {
  firm,
  hint,
  none,
  tooFew;

  static Confidence parse(String? v) => switch (v) {
    'firm' => firm,
    'hint' => hint,
    'too_few' => tooFew,
    _ => none,
  };

  /// 较可信 / 有迹象 / 看不出变化 / 样本不足.
  String get label => switch (this) {
    firm => tr.analysis.confidenceFirm,
    hint => tr.analysis.confidenceHint,
    none => tr.analysis.confidenceNone,
    tooFew => tr.analysis.confidenceTooFew,
  };
}

/// Whether a measure is going up: older half against newer half, and the trend test.
class Growth {
  Growth(Json j)
    : matches = _i(j['matches']) ?? 0,
      olderMean = _d(j['older_mean']) ?? 0,
      newerMean = _d(j['newer_mean']) ?? 0,
      change = _d(j['change']) ?? 0,
      changePct = _d(j['change_pct']) ?? 0,
      slopePerMatch = _d(j['slope_per_match']) ?? 0,
      p = _d(j['p']) ?? 1,
      trend = Trend.parse(_s(j['trend'])),
      confidence = Confidence.parse(_s(j['confidence']));
  final int matches;
  final double olderMean, newerMean, change, changePct, slopePerMatch, p;
  final Trend trend;

  /// How firmly the change may be worded; decided by the service from the p value.
  final Confidence confidence;
  static Growth? opt(Object? v) => v is Map<String, dynamic> ? Growth(v) : null;
}

class RoleGrowth {
  RoleGrowth(Json j)
    : role = Role.parse(_s(j['role'])),
      matches = _i(j['matches']) ?? 0,
      mean = _d(j['mean']),
      growth = Growth.opt(j['growth']);
  final Role role;
  final int matches;
  final double? mean;
  final Growth? growth;
}

class MetricGrowth {
  MetricGrowth(Json j)
    : metric = GrowthMetric.parse(_s(j['metric'])),
      matches = _i(j['matches']) ?? 0,
      mean = _d(j['mean']),
      growth = Growth.opt(j['growth']),
      byRole = _list(j['by_role'], RoleGrowth.new);
  final GrowthMetric? metric;
  final int matches;
  final double? mean;
  final Growth? growth;
  final List<RoleGrowth> byRole;

  /// The trend for one role, or for all matches together when [role] is null.
  Growth? growthFor(Role? role) => role == null
      ? growth
      : byRole.where((r) => r.role == role).firstOrNull?.growth;
}

/// The service's answer for the growth panel: the matches it could use (oldest first)
/// and each measure's trend.
class GrowthResult {
  GrowthResult(Json j)
    : enabled = j['enabled'] == true,
      listed = _i(j['listed']) ?? 0,
      stored = _i(j['stored']) ?? 0,
      points = _list((j['report'] as Map?)?['points'], GrowthPoint.new),
      skipped = _i((j['report'] as Map?)?['skipped']) ?? 0,
      metrics = _list((j['report'] as Map?)?['metrics'], MetricGrowth.new);
  final bool enabled;

  /// Matches in the stored list, and how many of them have a detail stored.
  final int listed, stored;
  final List<GrowthPoint> points;

  /// Stored matches that could not be used (too short, no deaths figure).
  final int skipped;
  final List<MetricGrowth> metrics;

  MetricGrowth? metric(GrowthMetric m) =>
      metrics.where((x) => x.metric == m).firstOrNull;

  /// Roles that appear in the matches, in display order.
  List<Role> get roles => [
    for (final r in Role.playable)
      if (points.any((p) => p.role == r)) r,
  ];
}

/// The background rank-snapshot job of one player and mode (`/api/ranks/status`).
class RankJob {
  RankJob(Json j)
    : state = '${j['state'] ?? 'done'}',
      done = (j['done'] as num?)?.toInt() ?? 0,
      remaining = (j['remaining'] as num?)?.toInt() ?? 0;
  static RankJob? opt(Object? j) =>
      j is Map ? RankJob(j.cast<String, dynamic>()) : null;

  /// `waiting`, `running`, `paused` (giving way to another query), `done`.
  final String state;
  final int done, remaining;
  bool get finished => state == 'done';
  bool get paused => state == 'paused';
}
