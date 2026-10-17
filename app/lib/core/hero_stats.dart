import '../state/match_view.dart';
import 'models.dart';
import 'support.dart';

/// Where a hero-stat figure came from.
enum StatSource {
  /// The provider's own number.
  provider,

  /// Worked out from the provider's per-match average (average × 600 ÷ match length).
  derived,

  /// Averaged from the recent matches the app has read, because the provider left it out.
  recent,

  /// The hero can produce this stat, nobody reported one, so it is zero.
  zero,
}

class HeroStatRow {
  HeroStatRow(this.guid, this.name);
  final String guid, name;

  /// Null where the stat has no per-10-minute meaning (rates, times).
  double? per10;
  double? perMatch;
  StatSource per10Source = StatSource.provider;
  StatSource perMatchSource = StatSource.provider;
}

/// Fills the gaps in a hero's provider stats by one rule:
///  - the hero cannot produce the stat (it is not in the game's list for that hero,
///    and the provider did not report it): no figure, shown as a dash;
///  - the hero can produce it but the provider left it out: worked out from what we
///    have (per-10 from the per-match average, per-match from recent matches),
///    otherwise zero.
class HeroStats {
  /// Provider stat name → the field on a match summary that measures the same thing.
  static const _matchField = {
    '消灭': 'kills',
    '阵亡': 'deaths',
    '助攻': 'assists',
    '对英雄伤害量': 'damage',
    '治疗量': 'healing',
  };

  /// Every stat of [h] that exists for this hero, with per-match and per-10 figures.
  static List<HeroStatRow> rows(
    HeroUsage h,
    Catalog cat,
    List<MatchSummary> recent,
  ) {
    final agg = recent.isEmpty ? null : Agg(recent);
    final byGuid = <String, HeroStatRow>{};
    final secs = h.avgMatchSeconds;

    // The game's list for this hero, then anything the provider reported beyond it.
    for (final s in cat.expectedStats(h.hero)) {
      byGuid[s.guid] = HeroStatRow(s.guid, s.name);
    }
    for (final v in [...h.perMatch, ...h.per10min]) {
      final n = v.stat.name;
      if (n != null)
        byGuid.putIfAbsent(v.stat.guid, () => HeroStatRow(v.stat.guid, n));
    }

    final pm = {for (final v in h.perMatch) v.stat.guid: v.value};
    final p10 = {for (final v in h.per10min) v.stat.guid: v.value};

    for (final r in byGuid.values) {
      // Per match.
      if (pm.containsKey(r.guid)) {
        r.perMatch = pm[r.guid];
      } else {
        final field = _matchField[r.name];
        final fromMatches = field == null ? null : agg?.mean[field];
        if (fromMatches != null) {
          r.perMatch = fromMatches;
          r.perMatchSource = StatSource.recent;
        } else {
          r.perMatch = 0;
          r.perMatchSource = StatSource.zero;
        }
      }
      // Per 10 minutes.
      if (p10.containsKey(r.guid)) {
        r.per10 = p10[r.guid];
      } else if (!HeroUsage.scalesPer10(r.name)) {
        r.per10 = null;
      } else if (r.perMatch == 0) {
        r.per10 = 0;
        r.per10Source = r.perMatchSource == StatSource.provider
            ? StatSource.derived
            : StatSource.zero;
      } else if (secs != null && secs > 0 && r.perMatch != null) {
        r.per10 = r.perMatch! * 600 / secs;
        r.per10Source = StatSource.derived;
      } else {
        r.per10 = null;
      }
    }
    final out = _mergeSelfHealing(byGuid.values.toList());
    // Stats the game's list does not carry for this hero but matches show it doing
    // (a hero whose list has no healing at all): add them from matches.
    if (agg != null) {
      for (final e in _matchField.entries) {
        if (out.any((r) => r.name == e.key)) continue;
        final mean = agg.mean[e.value];
        if (mean == null || mean <= 0) continue;
        out.add(
          HeroStatRow('match:${e.value}', e.key)
            ..perMatch = mean
            ..perMatchSource = StatSource.recent
            ..per10 = secs != null && secs > 0 ? mean * 600 / secs : null
            ..per10Source = StatSource.recent,
        );
      }
    }
    // Some stats every hero can produce, and supports always heal: a missing record
    // for these is zero, never "cannot produce".
    final always = [
      '消灭',
      '阵亡',
      '助攻',
      '对英雄伤害量',
      if (cat.heroRole(h.hero) == Role.support &&
          !out.any((r) => r.name.contains('治疗量') && !r.name.contains('承受')))
        '治疗量',
    ];
    for (final name in always) {
      if (out.any((r) => r.name == name)) continue;
      out.add(
        HeroStatRow('always:$name', name)
          ..perMatch = 0
          ..per10 = 0
          ..perMatchSource = StatSource.zero
          ..per10Source = StatSource.zero,
      );
    }
    return out;
  }

  /// Self-healing is healing: one row 治疗量, the two figures added together. A hero
  /// with only self-healing in its list gets that row renamed.
  static List<HeroStatRow> _mergeSelfHealing(List<HeroStatRow> rows) {
    final self = rows.where((r) => r.name == '自我治疗量').firstOrNull;
    if (self == null) return rows;
    final total = rows.where((r) => r.name == '治疗量').firstOrNull;
    if (total == null) {
      return [
        for (final r in rows)
          if (identical(r, self))
            HeroStatRow(self.guid, '治疗量')
              ..per10 = self.per10
              ..perMatch = self.perMatch
              ..per10Source = self.per10Source
              ..perMatchSource = self.perMatchSource
          else
            r,
      ];
    }
    double? add(double? a, double? b) =>
        a == null && b == null ? null : (a ?? 0) + (b ?? 0);
    // The merged figure is provider data when either part is, otherwise the weaker source.
    StatSource join(StatSource a, StatSource b) =>
        a == StatSource.provider || b == StatSource.provider
        ? StatSource.provider
        : (a == StatSource.zero ? b : a);
    total
      ..per10 = add(total.per10, self.per10)
      ..perMatch = add(total.perMatch, self.perMatch)
      ..per10Source = join(total.per10Source, self.per10Source)
      ..perMatchSource = join(total.perMatchSource, self.perMatchSource);
    return [
      for (final r in rows)
        if (!identical(r, self)) r,
    ];
  }

  /// Per-10-minute figure for one named stat in a table cell: null when the hero
  /// cannot produce it, a number (possibly 0) when it can.
  static double? cell10(
    HeroUsage h,
    Catalog cat,
    List<MatchSummary> recent,
    bool Function(String) match,
  ) {
    for (final r in rows(h, cat, recent)) {
      if (match(r.name)) return r.per10;
    }
    return null;
  }

  /// Damage mitigated per 10 minutes. The game's stat list has no such stat, so it
  /// comes from matches: tanks always can produce it, others only if a match shows some.
  static double? mitigation10(
    HeroUsage h,
    Catalog cat,
    List<MatchSummary> recent,
  ) {
    final agg = recent.isEmpty ? null : Agg(recent);
    final mean = agg?.mean['mitigation'];
    final tank = cat.heroRole(h.hero) == Role.tank;
    final secs = h.avgMatchSeconds;
    if (mean == null || mean == 0) {
      return tank ? 0 : null;
    }
    if (secs == null || secs <= 0) return null;
    return mean * 600 / secs;
  }
}
