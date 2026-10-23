import 'package:flutter/material.dart';

import '../../core/hero_stats.dart';
import '../../core/models.dart';
import '../../core/stats.dart';
import '../../core/support.dart';
import '../../design/cards.dart';
import '../../design/headline.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';
import '../../l10n/strings.dart';
import '../../state/app_state.dart';
import '../../state/match_view.dart';

/// Two heroes side by side: matches, win rate (with its range), KDA and play time, then
/// every stat both can produce, per 10 minutes, with the difference left minus right.
/// Says so when the two are of different roles or one has few matches. With no second
/// hero yet, a picker (same role first).
class HeroComparePage extends StatelessWidget {
  const HeroComparePage({
    super.key,
    required this.workspace,
    required this.a,
    required this.b,
    required this.all,
  });
  final PlayerWorkspace workspace;
  final HeroUsage a;
  final HeroUsage? b;

  /// Every hero of the season, for the picker.
  final List<HeroUsage> all;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = context.c;
    final other = b;
    final bar = Row(
      children: [
        AppButton(
          a.hero.label,
          icon: Icons.arrow_back,
          quiet: true,
          onPressed: workspace.closeHeroCompare,
        ),
        Text('›', style: Ty.body.copyWith(color: c.textSecondary)),
        const SizedBox(width: Sp.withinGroup),
        Expanded(
          child: Text(
            other == null
                ? tr.compare.pickHero
                : tr.compare.heroesTitle(a.hero.label, other.hero.label),
            style: Ty.bodyStrong,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (other != null)
          AppButton(
            tr.compare.change,
            quiet: true,
            onPressed: () => workspace.compareHero(null),
          ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        bar,
        const SizedBox(height: Sp.withinGroup),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(right: Sp.betweenGroups, bottom: 28),
            children: [
              if (other == null)
                _Picker(workspace: workspace, a: a, all: all)
              else
                _Comparison(
                  a: a,
                  b: other,
                  catalog: app.catalog,
                  recent:
                      workspace.matchesFor(app.mode).value?.matches ?? const [],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Picker extends StatelessWidget {
  const _Picker({required this.workspace, required this.a, required this.all});
  final PlayerWorkspace workspace;
  final HeroUsage a;
  final List<HeroUsage> all;

  @override
  Widget build(BuildContext context) {
    final cat = AppScope.of(context).catalog;
    final role = cat.heroRole(a.hero);
    final others =
        [
          for (final h in all)
            if (PlayerWorkspace.heroKey(h) != PlayerWorkspace.heroKey(a)) h,
        ]..sort((x, y) {
          final rx = cat.heroRole(x.hero) == role ? 0 : 1;
          final ry = cat.heroRole(y.hero) == role ? 0 : 1;
          return rx != ry ? rx - ry : (y.matches ?? 0) - (x.matches ?? 0);
        });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(tr.compare.pickHero, info: tr.compare.pickHeroTip),
        const SizedBox(height: SectionHeader.below),
        Wrap(
          spacing: Sp.withinGroup,
          runSpacing: Sp.withinGroup,
          children: [
            for (final h in others)
              Pressable(
                onTap: () => workspace.compareHero(PlayerWorkspace.heroKey(h)),
                semanticLabel:
                    '${h.hero.label} ${tr.common.matchCount(h.matches ?? 0)}',
                outlineAtRest: true,
                padding: const EdgeInsets.fromLTRB(
                  Sp.iconGap,
                  Sp.iconGap,
                  Sp.betweenItems,
                  Sp.iconGap,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    NetImage(
                      cat.heroIcon(h.hero),
                      size: 28,
                      fallback: h.hero.label,
                    ),
                    const SizedBox(width: Sp.withinGroup),
                    Text(h.hero.label, style: Ty.bodyStrong),
                    const SizedBox(width: Sp.iconGap),
                    Text(
                      tr.common.matchCount(h.matches ?? 0),
                      style: Ty.meta.copyWith(color: context.c.textSecondary),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _Comparison extends StatelessWidget {
  const _Comparison({
    required this.a,
    required this.b,
    required this.catalog,
    required this.recent,
  });
  final HeroUsage a, b;
  final Catalog catalog;
  final List<MatchSummary> recent;

  List<MatchSummary> _of(HeroUsage h) => [
    for (final m in recent)
      if (m.hero?.guid == h.hero.guid) m,
  ];

  /// The season KDA, or the recent matches' when the provider gives none (as the hero
  /// page does).
  double? _kda(HeroUsage h) => h.kda ?? Agg(_of(h)).kda;

  static String _rateNote(HeroUsage h) {
    final n = h.matches ?? 0, w = h.wins ?? 0;
    final r = wilsonPct(w, n);
    return r == null
        ? tr.common.matchCount(n)
        : tr.compare.rateNote(
            n,
            fmtPct(r.$1, digits: 0),
            fmtPct(r.$2, digits: 0),
          );
  }

  /// `+12.3（+8%）`: left minus right, and that against right.
  static String _diff(double? x, double? y, String Function(double) f) {
    if (x == null || y == null) return tr.compare.onlyOne;
    final d = x - y;
    final sign = d > 0 ? '+' : (d < 0 ? '−' : '±');
    final pct = y == 0
        ? ''
        : '（$sign${fmtPct((d / y).abs() * 100, digits: 0)}）';
    return '$sign${f(d.abs())}$pct';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final ra = catalog.heroRole(a.hero), rb = catalog.heroRole(b.hero);
    final warnings = [
      if (ra != rb) tr.compare.differentRoles,
      for (final h in [a, b])
        if ((h.matches ?? 0) < fallbackMinGroupMatches)
          tr.compare.tooFew(h.hero.label, h.matches ?? 0),
    ];
    final rowsA = {
      for (final r in HeroStats.rows(a, catalog, _of(a))) r.name: r,
    };
    final rowsB = {
      for (final r in HeroStats.rows(b, catalog, _of(b))) r.name: r,
    };
    final shared = [
      for (final name in rowsA.keys)
        if (rowsB.containsKey(name)) name,
    ];
    final head = Ty.meta.copyWith(color: c.textSecondary);
    TableRow row(
      String label,
      String x,
      String y,
      String d, {
      bool top = false,
    }) => TableRow(
      decoration: top
          ? null
          : BoxDecoration(
              border: Border(top: BorderSide(color: c.grid)),
            ),
      children: [
        for (final (i, t) in [label, x, y, d].indexed)
          Padding(
            padding: const EdgeInsets.symmetric(
              vertical: Sp.iconGap,
              horizontal: Sp.withinGroup,
            ),
            child: Text(
              t,
              textAlign: i == 0 ? TextAlign.left : TextAlign.right,
              style: top ? head : (i == 0 ? Ty.body : Ty.num(Ty.body)),
            ),
          ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final w in warnings)
          Padding(
            padding: const EdgeInsets.only(bottom: Sp.withinGroup),
            child: StatusBanner(severity: Severity.warning, title: w),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (i, h) in [a, b].indexed) ...[
              if (i > 0) const SizedBox(width: Sp.betweenSections),
              Expanded(
                child: HeadlineBand(
                  art: catalog.heroBanner(h.hero),
                  tint: heroTint(context, h.hero),
                  title: h.hero.label,
                  figures: [
                    HeadlineFigure(
                      label: tr.compare.winRate,
                      value: fmtPct(h.winRatePct, digits: 0),
                      note: _rateNote(h),
                    ),
                    HeadlineFigure(
                      label: tr.compare.kda,
                      value: fmtTwo(_kda(h)),
                    ),
                    HeadlineFigure(
                      label: tr.compare.playTime,
                      value: fmtPlayTime(h.playTimeS),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: Sp.betweenSections),
        Panel(
          child: Table(
            columnWidths: const {0: FlexColumnWidth(2)},
            children: [
              row(
                tr.compare.statColumn,
                a.hero.label,
                b.hero.label,
                tr.compare.diffColumn,
                top: true,
              ),
              row(
                tr.compare.winRate,
                fmtPct(a.winRatePct),
                fmtPct(b.winRatePct),
                _diff(a.winRatePct, b.winRatePct, (v) => fmtOne(v)),
              ),
              row(
                tr.compare.kda,
                fmtTwo(_kda(a)),
                fmtTwo(_kda(b)),
                _diff(_kda(a), _kda(b), fmtTwo),
              ),
              for (final name in shared)
                () {
                  final x = rowsA[name]!, y = rowsB[name]!;
                  final per10 = x.per10 != null && y.per10 != null;
                  final vx = per10 ? x.per10 : x.perMatch;
                  final vy = per10 ? y.per10 : y.perMatch;
                  String f(double v) => fmtHeroStat(name, v);
                  return row(
                    name,
                    vx == null ? tr.compare.onlyOne : f(vx),
                    vy == null ? tr.compare.onlyOne : f(vy),
                    _diff(vx, vy, f),
                  );
                }(),
            ],
          ),
        ),
        const SizedBox(height: Sp.withinGroup),
        Text(tr.compare.per10Note, style: head),
      ],
    );
  }
}
