import 'models.dart';

/// One rated match on a role's track (`watch_core::ranks::TrackPoint`).
class TrackPoint {
  TrackPoint(Json j)
    : matchId = (j['match_id'] as String?) ?? '',
      atMs = (j['at_ms'] as num?)?.toInt() ?? 0,
      outcome = Outcome.parse(j['outcome'] as String?),
      skillRating = (j['skill_rating'] as num?)?.toInt() ?? 0,
      tier = j['tier'] as String?,
      division = (j['division'] as num?)?.toInt(),
      season = (j['season'] as num?)?.toInt(),
      enemyEdge = (j['enemy_edge'] as num?)?.toDouble();
  final String matchId;
  final int atMs;
  final Outcome outcome;
  final int skillRating;
  final String? tier;
  final int? division;

  /// The season it is placed in (by career match counts); null past the known ones.
  final int? season;

  /// Enemy team's mean rating minus the player's team's, where known.
  final double? enemyEdge;
}

class RoleTrack {
  RoleTrack(Json j)
    : role = Role.parse(j['role'] as String?),
      points = [
        for (final p in (j['points'] as List?) ?? const [])
          if (p is Map<String, dynamic>) TrackPoint(p),
      ];
  final Role role;

  /// Oldest first.
  final List<TrackPoint> points;
}

/// A stretch of one role losing rating, peak to trough (`watch_core::ranks::Drop`).
class RankDrop {
  RankDrop(Json j)
    : role = Role.parse(j['role'] as String?),
      fromMatchId = (j['from_match_id'] as String?) ?? '',
      toMatchId = (j['to_match_id'] as String?) ?? '',
      fromMs = (j['from_ms'] as num?)?.toInt() ?? 0,
      toMs = (j['to_ms'] as num?)?.toInt() ?? 0,
      fromRating = (j['from_rating'] as num?)?.toInt() ?? 0,
      toRating = (j['to_rating'] as num?)?.toInt() ?? 0,
      matches = (j['matches'] as num?)?.toInt() ?? 0,
      wins = (j['wins'] as num?)?.toInt() ?? 0,
      losses = (j['losses'] as num?)?.toInt() ?? 0,
      rated = (j['rated'] as num?)?.toInt() ?? 0,
      meanEnemyEdge = (j['mean_enemy_edge'] as num?)?.toDouble();
  final Role role;
  final String fromMatchId, toMatchId;
  final int fromMs, toMs, fromRating, toRating, matches, wins, losses, rated;
  final double? meanEnemyEdge;
}

class RanksResult {
  RanksResult(Json j)
    : enabled = j['enabled'] == true,
      roles = [
        for (final r in ((j['ranks'] as Json?)?['roles'] as List?) ?? const [])
          if (r is Map<String, dynamic>) RoleTrack(r),
      ],
      seasons = [
        for (final s
            in ((j['ranks'] as Json?)?['seasons'] as List?) ?? const [])
          if (s is Map<String, dynamic>)
            (
              season: (s['season'] as num?)?.toInt() ?? 0,
              startMs: (s['start_ms'] as num?)?.toInt() ?? 0,
              matches: (s['matches'] as num?)?.toInt() ?? 0,
            ),
      ],
      drops = [
        for (final d in ((j['ranks'] as Json?)?['drops'] as List?) ?? const [])
          if (d is Map<String, dynamic>) RankDrop(d),
      ];
  final bool enabled;
  final List<RoleTrack> roles;

  /// Newest first.
  final List<({int season, int startMs, int matches})> seasons;

  /// Newest first.
  final List<RankDrop> drops;
}
