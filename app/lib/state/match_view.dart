import '../core/models.dart';
import '../core/support.dart';

/// Filters on the match list. All filters AND together; one selection per facet.
class MatchFilters {
  Set<Outcome> outcomes = {};
  Role? role;
  String? heroGuid;
  String? mapGuid;
  String query = '';

  bool get active =>
      outcomes.isNotEmpty ||
      role != null ||
      heroGuid != null ||
      mapGuid != null ||
      query.trim().isNotEmpty;

  void clear() {
    outcomes = {};
    role = null;
    heroGuid = null;
    mapGuid = null;
    query = '';
  }

  bool accepts(MatchSummary m) {
    if (outcomes.isNotEmpty && !outcomes.contains(m.outcome)) return false;
    if (role != null && m.role != role) return false;
    if (heroGuid != null && m.hero?.guid != heroGuid) return false;
    if (mapGuid != null && m.map?.guid != mapGuid) return false;
    if (query.trim().isNotEmpty) {
      final hay =
          '${m.hero?.name ?? ''} ${m.map?.name ?? ''} ${m.role.label} ${m.outcome.label}';
      if (!matchesQuery(hay, query)) return false;
    }
    return true;
  }
}

/// Counts for a facet value given every *other* filter, so options can show how many rows remain.
Map<String, int> facetCounts(
  List<MatchSummary> all,
  MatchFilters f,
  String facet,
) {
  final probe = MatchFilters()
    ..outcomes = f.outcomes
    ..role = facet == 'role' ? null : f.role
    ..heroGuid = facet == 'hero' ? null : f.heroGuid
    ..mapGuid = facet == 'map' ? null : f.mapGuid
    ..query = f.query;
  final out = <String, int>{};
  for (final m in all.where(probe.accepts)) {
    final key = switch (facet) {
      'role' => m.role.id,
      'hero' => m.hero?.guid,
      'map' => m.map?.guid,
      _ => null,
    };
    if (key != null) out[key] = (out[key] ?? 0) + 1;
  }
  return out;
}

Comparable<Object>? sortKey(MatchSummary m, String column) => switch (column) {
  'time' => m.startedAtMs,
  'outcome' => m.outcome.index,
  'map' => m.map?.name,
  'hero' => m.hero?.name,
  'role' => m.role.index,
  'score' =>
    m.scoreTeam == null || m.scoreOpponent == null
        ? null
        : m.scoreTeam! - m.scoreOpponent!,
  'kda' =>
    m.stats.deaths == null || m.stats.kills == null || m.stats.assists == null
        ? null
        : (m.stats.kills! + m.stats.assists!) /
              (m.stats.deaths! == 0 ? 1 : m.stats.deaths!),
  'damage' => m.stats.damage,
  'healing' => m.stats.healing,
  'mitigation' => m.stats.mitigation,
  'rank' => m.rank?.skillRating,
  _ => null,
};

/// Sorts a copy. Missing values always sort last; ties keep newest-first so rows never jump.
List<MatchSummary> sorted(
  List<MatchSummary> rows,
  String column,
  bool ascending,
) {
  final out = [...rows];
  int cmp(Comparable<Object>? a, Comparable<Object>? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return ascending ? a.compareTo(b) : b.compareTo(a);
  }

  out.sort((a, b) {
    final c = cmp(sortKey(a, column), sortKey(b, column));
    if (c != 0) return c;
    return (b.startedAtMs ?? 0).compareTo(a.startedAtMs ?? 0);
  });
  return out;
}

/// Aggregate over the rows shown. Mirrors `watch-core::analysis::aggregate`:
/// win rate = wins / (wins + losses); means skip missing values and report their sample size.
class Agg {
  Agg(Iterable<MatchSummary> rows) {
    var k = 0.0, a = 0.0, d = 0.0;
    final sums = <String, double>{};
    final counts = <String, int>{};
    for (final m in rows) {
      matches++;
      switch (m.outcome) {
        case Outcome.win:
          wins++;
        case Outcome.loss:
          losses++;
        case Outcome.draw:
          draws++;
        case Outcome.unknown:
          unknown++;
      }
      final s = m.stats;
      if (s.kills != null && s.assists != null && s.deaths != null) {
        k += s.kills!;
        a += s.assists!;
        d += s.deaths!;
      }
      for (final f in [
        'damage',
        'healing',
        'mitigation',
        'kills',
        'assists',
        'deaths',
      ]) {
        final v = s.field(f);
        if (v != null) {
          sums[f] = (sums[f] ?? 0) + v;
          counts[f] = (counts[f] ?? 0) + 1;
        }
      }
    }
    final decided = wins + losses;
    winRatePct = decided > 0 ? 100.0 * wins / decided : null;
    kda = d > 0 ? (k + a) / d : null;
    for (final f in sums.keys) {
      mean[f] = sums[f]! / counts[f]!;
      samples[f] = counts[f]!;
    }
  }
  int matches = 0, wins = 0, losses = 0, draws = 0, unknown = 0;
  double? winRatePct, kda;
  final Map<String, double> mean = {};
  final Map<String, int> samples = {};
}
