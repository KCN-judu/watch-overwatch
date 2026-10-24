import 'package:flutter/material.dart';

import '../../core/benchmark.dart';
import '../../core/metric_doc.dart';
import '../../core/models.dart';
import '../../core/overview.dart';
import '../../core/support.dart';
import '../../design/cards.dart';
import '../../design/chart_kit.dart';
import '../../design/faces.dart';
import '../../design/headline.dart';
import '../../design/icons.dart';
import '../../design/share.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';
import '../../l10n/strings.dart';
import '../../state/app_state.dart';
import 'player_compare.dart';
import 'recap.dart';

/// One screen about one player, answer first (docs/ui-design.md §11, the skill's
/// visual-direction.md): a headline band over their most-played hero's banner with the
/// few figures that say how they are doing now and against before, then their last 20
/// matches as faces, what is worth noticing, where and with whom they win, and when.
/// Every block leads somewhere: a match opens, a hero or map filters the match list.
/// Worked out from the stored match list only, so it is there at once.
class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key, required this.workspace});
  final PlayerWorkspace workspace;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final ws = workspace;
    final mode = app.mode;
    final load = ws.overviewFor(mode);
    final result = load.value;
    final o = result?.overview;
    if (load.failedWithoutData) {
      return ErrorPanel(
        what: tr.overview.emptyTitle,
        error: load.error!,
        onRetry: () => ws.loadOverview(mode),
      );
    }
    if (o == null) {
      return load.loading || !load.has
          ? const AfterDelay(child: Center(child: Spinner()))
          : const SizedBox.shrink();
    }
    if (result!.listed == 0) {
      return EmptyState(
        icon: Icons.dashboard_sharp,
        title: tr.overview.emptyTitle,
        body: tr.overview.emptyBody(mode.label),
        actions: [
          AppButton(
            tr.overview.openMatches,
            primary: true,
            onPressed: () => app.setTab('matches'),
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.only(right: scrollGutter, bottom: Sp.page),
      children: [
        _Headline(workspace: ws, mode: mode, o: o, listed: result.listed),
        const SizedBox(height: Sp.betweenSections),
        _Form(workspace: ws, mode: mode, o: o),
        const SizedBox(height: Sp.betweenSections),
        _Insights(workspace: ws, mode: mode, o: o),
        const SizedBox(height: Sp.betweenSections),
        LayoutBuilder(
          builder: (context, box) {
            final heroes = _Groups(
              workspace: ws,
              mode: mode,
              o: o,
              heroes: true,
            );
            final maps = _Groups(
              workspace: ws,
              mode: mode,
              o: o,
              heroes: false,
            );
            if (box.maxWidth < 900) {
              return Column(
                children: [
                  heroes,
                  const SizedBox(height: Sp.betweenSections),
                  maps,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: heroes),
                const SizedBox(width: Sp.betweenSections),
                Expanded(child: maps),
              ],
            );
          },
        ),
        const SizedBox(height: Sp.betweenSections),
        Shareable(
          title: tr.overview.heatTitle,
          caption: tr.recap.caption(
            app.maskName(ws.name),
            mode.label,
            result.listed,
          ),
          fileName: tr.overview.heatTitle,
          child: Panel(
            child: HourHeatmap(
              metric: tr.overview.heatMetric,
              format: (v) => fmtPct(v, digits: 0),
              cells: [
                for (final day in o.heat)
                  [for (final r in day) HeatCell(r.winRatePct, r.decided)],
              ],
            ),
          ),
        ),
        const SizedBox(height: Sp.betweenSections),
        PlayerCompareSection(workspace: ws, mode: mode, mine: result),
      ],
    );
  }
}

// ---- Headline ------------------------------------------------------------------------

class _Headline extends StatelessWidget {
  const _Headline({
    required this.workspace,
    required this.mode,
    required this.o,
    required this.listed,
  });
  final PlayerWorkspace workspace;
  final Mode mode;
  final Overview o;
  final int listed;

  /// The hero played most in the recent matches: the band's picture.
  EntityRef? get _topHero {
    final counts = <String, (EntityRef, int)>{};
    for (final f in o.form) {
      final h = f.hero;
      if (h == null) continue;
      final seen = counts[h.guid];
      counts[h.guid] = (h, (seen?.$2 ?? 0) + 1);
    }
    if (counts.isEmpty) return null;
    return (counts.values.toList()..sort((a, b) => b.$2.compareTo(a.$2)))
        .first
        .$1;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final app = AppScope.of(context);
    final banner = app.catalog.heroBanner(_topHero);
    final recent = o.recent.record, before = o.before.record;
    final today = o.windows['today']?.record;
    String? delta(double? now, double? then, String Function(double) fmt) =>
        now == null || then == null || before.decided < 10
        ? null
        : '${now >= then ? '+' : '−'}${fmt((now - then).abs())}';
    final rateDelta = delta(
      recent.winRatePct,
      before.winRatePct,
      (v) => fmtPct(v, digits: 0),
    );
    final kdaDelta = delta(o.recent.kda, o.before.kda, fmtTwo);
    final rateUp = (recent.winRatePct ?? 0) >= (before.winRatePct ?? 0);
    final kdaUp = (o.recent.kda ?? 0) >= (o.before.kda ?? 0);

    return HeadlineBand(
      art: banner,
      tint: heroTint(context, _topHero),
      eyebrow: Row(
        children: [
          Text(
            tr.overview.coverage(listed, mode.label),
            style: Ty.meta.copyWith(color: c.textSecondary),
          ),
          InfoTip(tr.overview.coverageTip),
        ],
      ),
      actions: [
        AppButton(
          tr.recap.open,
          icon: Icons.auto_stories_sharp,
          tooltip: tr.recap.openTip,
          onPressed: () => showRecap(
            context,
            workspace: workspace,
            mode: mode,
            overview: o,
            listed: listed,
          ),
        ),
      ],
      figures: [
        HeadlineFigure(
          label: tr.overview.winRateRecent,
          value: fmtPct(recent.winRatePct, digits: 0),
          note: rateDelta == null
              ? tr.overview.notEnoughBefore
              : tr.overview.versusBefore(rateDelta),
          noteColor: rateDelta == null
              ? c.textSecondary
              : rateUp
              ? c.positive
              : c.negative,
          // One point is not a line: the sparkline waits for a second.
          trailing: o.rollingWinPct.whereType<double>().length < 2
              ? null
              : Sparkline(
                  values: o.rollingWinPct,
                  label: tr.overview.rollingLabel,
                  format: (v) => fmtPct(v, digits: 0),
                  width: 96,
                  height: 32,
                ),
        ),
        HeadlineFigure(
          label: tr.overview.recordRecent,
          child: RecordText(recent.wins, recent.losses, draws: recent.draws),
        ),
        HeadlineFigure(
          label: tr.overview.kdaRecent,
          value: fmtTwo(o.recent.kda),
          note: kdaDelta == null ? null : tr.overview.versusBefore(kdaDelta),
          noteColor: kdaUp ? c.positive : c.negative,
        ),
        if (today == null || today.matches == 0)
          HeadlineFigure(
            label: tr.overview.today,
            value: tr.overview.noMatchesToday,
            small: true,
          )
        else
          HeadlineFigure(
            label: tr.overview.today,
            child: RecordText(
              today.wins,
              today.losses,
              draws: today.draws,
              style: Ty.figure,
            ),
          ),
      ],
    );
  }
}

// ---- Form strip ----------------------------------------------------------------------

class _Form extends StatelessWidget {
  const _Form({required this.workspace, required this.mode, required this.o});
  final PlayerWorkspace workspace;
  final Mode mode;
  final Overview o;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final app = AppScope.of(context);
    final ids = [for (final f in o.form.reversed) f.matchId];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          tr.overview.formTitle,
          trailing: Text(
            tr.overview.formHint,
            style: Ty.meta.copyWith(color: c.textSecondary),
          ),
        ),
        const SizedBox(height: SectionHeader.below),
        FaceStrip(
          faces: [
            for (final f in o.form)
              (
                portrait: app.catalog.heroPortrait(f.hero),
                outcome: f.outcome,
                tip: tr.overview.formTip(
                  f.outcome.label,
                  f.map?.label ?? tr.common.unknownMap,
                  f.hero?.label ?? tr.common.unknownHero,
                  fmtDateTime(f.startedAtMs),
                ),
                onTap: () {
                  workspace.openMatch(mode, f.matchId, ids);
                  app.setTab('matches');
                },
              ),
          ],
        ),
      ],
    );
  }
}

// ---- Insights ------------------------------------------------------------------------

class _Insights extends StatelessWidget {
  const _Insights({
    required this.workspace,
    required this.mode,
    required this.o,
  });
  final PlayerWorkspace workspace;
  final Mode mode;
  final Overview o;

  static String _metric(BenchMetric m) => switch (m) {
    BenchMetric.damage => tr.heroes.metricDamage,
    BenchMetric.healing => tr.heroes.metricHealing,
    BenchMetric.mitigation => tr.heroes.metricMitigation,
    BenchMetric.eliminations => tr.heroes.metricEliminations,
    BenchMetric.finalBlows => tr.heroes.metricFinalBlows,
    BenchMetric.deaths => tr.heroes.metricDeaths,
    BenchMetric.unknown => '',
  };

  String _text(Insight i) {
    final overall = fmtPct(i.other, digits: 0);
    final rate = fmtPct(i.value, digits: 0);
    final s = i.subject ?? '';
    String signed(int d) =>
        '${d > 0
            ? '+'
            : d < 0
            ? '−'
            : ''}${d.abs()}';
    final items = tr.common.list([
      for (final it in i.items)
        tr.overview.driverItem(it.label, signed(it.delta)),
    ]);
    return switch (i.kind) {
      InsightKind.streak =>
        i.positive ? tr.overview.streakWin(i.n) : tr.overview.streakLoss(i.n),
      InsightKind.streakStrength => tr.overview.streakStrength(
        i.value.round(),
        i.n,
      ),
      InsightKind.recentForm =>
        i.positive
            ? tr.overview.recentUp(rate, overall)
            : tr.overview.recentDown(rate, overall),
      InsightKind.drivers =>
        i.positive
            ? tr.overview.driversUp(items)
            : tr.overview.driversDown(items),
      InsightKind.map =>
        i.positive
            ? tr.overview.mapUp(s, rate, i.n, overall)
            : tr.overview.mapDown(s, rate, i.n, overall),
      InsightKind.hero =>
        i.positive
            ? tr.overview.heroUp(s, rate, i.n, overall)
            : tr.overview.heroDown(s, rate, i.n, overall),
      InsightKind.fatigue => tr.overview.fatigue(rate, overall),
      InsightKind.heroMetric =>
        i.positive
            ? tr.overview.heroMetricUp(s, _metric(i.metric), i.value.round())
            : tr.overview.heroMetricDown(s, _metric(i.metric), i.value.round()),
      InsightKind.unknown => '',
    };
  }

  static IconData _icon(Insight i) => switch (i.kind) {
    InsightKind.streak =>
      i.positive
          ? Icons.local_fire_department_sharp
          : Icons.self_improvement_sharp,
    InsightKind.streakStrength => Icons.balance_sharp,
    InsightKind.map => Icons.map_sharp,
    InsightKind.hero || InsightKind.heroMetric => Icons.person_outline_sharp,
    InsightKind.fatigue => Icons.bedtime_sharp,
    _ => i.positive ? Icons.trending_up_sharp : Icons.trending_down_sharp,
  };

  /// Opens the match list filtered to a finding's map or hero.
  void _drill(AppState app, String kind, String key) {
    for (final m in workspace.matchesFor(mode).value?.matches ?? const []) {
      final e = kind == 'map' ? m.map : m.hero;
      if (e == null || groupKey(e) != key) continue;
      final f = workspace.filtersFor(mode)..clear();
      if (kind == 'map') {
        f.mapGuid = e.guid;
      } else {
        f.heroGuid = e.guid;
      }
      workspace.touch();
      app.setTab('matches');
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final app = AppScope.of(context);
    final muted = app.mutedInsights;
    final shown = o.insights
        .where(
          (i) => i.kind != InsightKind.unknown && !muted.contains(i.kind.id),
        )
        .toList();
    final hidden = o.insights.length - shown.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          tr.overview.insightsTitle,
          info: tr.overview.insightsTip,
          infoDoc: MetricDoc.threshold,
          trailing: muted.isEmpty
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      tr.overview.muted(muted.length),
                      style: Ty.meta.copyWith(color: c.textSecondary),
                    ),
                    const SizedBox(width: Sp.withinGroup),
                    AppButton(
                      tr.overview.unmute,
                      quiet: true,
                      onPressed: app.unmuteInsights,
                    ),
                  ],
                ),
        ),
        const SizedBox(height: SectionHeader.below),
        if (shown.isEmpty)
          Text(
            hidden > 0
                ? tr.overview.muted(muted.length)
                : tr.overview.insightsNone,
            style: Ty.body.copyWith(color: c.textSecondary),
          )
        else
          Column(
            children: [
              for (final i in shown) ...[
                _card(context, app, i),
                const SizedBox(height: Sp.withinGroup),
              ],
            ],
          ),
      ],
    );
  }

  Widget _card(BuildContext context, AppState app, Insight i) {
    final c = context.c;
    final accent = i.positive ? c.positive : c.negative;
    final drill = switch (i.kind) {
      InsightKind.map => i.key == null ? null : ('map', i.key!),
      InsightKind.hero ||
      InsightKind.heroMetric => i.key == null ? null : ('hero', i.key!),
      _ => null,
    };
    return IntrinsicHeight(
      child: CardSurface(
        accent: accent,
        child: Row(
          children: [
            Icon(_icon(i), size: 28, color: accent),
            const SizedBox(width: Sp.betweenGroups),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_text(i), style: Ty.bodyStrong),
                  if (i.items.isNotEmpty) ...[
                    const SizedBox(height: Sp.withinControl),
                    Wrap(
                      spacing: Sp.withinGroup,
                      children: [
                        for (final it in i.items)
                          AppButton(
                            it.label,
                            quiet: true,
                            icon: it.kind == 'map'
                                ? Icons.map_sharp
                                : Icons.person_outline_sharp,
                            onPressed: () => _drill(app, it.kind, it.key),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (drill != null)
              IconAction(
                icon: Icons.filter_alt_sharp,
                label: tr.overview.openMatches,
                onPressed: () => _drill(app, drill.$1, drill.$2),
              ),
            IconAction(
              icon: Icons.notifications_off_sharp,
              label: tr.overview.mute,
              onPressed: () => app.muteInsight(i.kind.id),
            ),
          ],
        ),
      ),
    );
  }
}

// ---- Heroes and maps -----------------------------------------------------------------

class _Groups extends StatelessWidget {
  const _Groups({
    required this.workspace,
    required this.mode,
    required this.o,
    required this.heroes,
  });
  final PlayerWorkspace workspace;
  final Mode mode;
  final Overview o;
  final bool heroes;

  /// The entity behind a group key, from the stored matches (for the icon and the filter).
  EntityRef? _entity(String key) {
    for (final m in workspace.matchesFor(mode).value?.matches ?? const []) {
      final e = heroes ? m.hero : m.map;
      if (e != null && groupKey(e) == key) return e;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final groups = (heroes ? o.byHero : o.byMap)
        .where((g) => g.key != 'unknown')
        .take(heroes ? 6 : 8)
        .toList();
    final overall = o.overall.record.winRatePct;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Shareable(
          title: heroes ? tr.overview.heroesTitle : tr.overview.mapsTitle,
          info: tr.overview.groupTip,
          infoDoc: MetricDoc.winRateRange,
          caption: tr.recap.caption(
            app.maskName(workspace.name),
            mode.label,
            o.overall.record.matches,
          ),
          fileName: heroes ? tr.overview.heroesTitle : tr.overview.mapsTitle,
          child: Panel(
            child: IntervalBars(
              format: (v) => fmtPct(v, digits: 0),
              reference: overall,
              referenceMeaning: overall == null
                  ? null
                  : tr.overview.overallRate(fmtPct(overall, digits: 0)),
              labelWidth: heroes ? 150 : 170,
              rows: [
                for (final g in groups)
                  () {
                    final r = g.aggregate.record;
                    final e = _entity(g.key);
                    return IntervalRow(
                      label: g.label ?? e?.label ?? g.key,
                      value: r.winRatePct ?? 0,
                      low: r.lowPct,
                      high: r.highPct,
                      n: r.decided,
                      enough: r.enough,
                      leading: heroes
                          ? NetImage(
                              app.catalog.heroIcon(e),
                              size: 24,
                              fallback: g.label ?? '',
                            )
                          : null,
                      onTap: e == null
                          ? null
                          : () {
                              final f = workspace.filtersFor(mode)..clear();
                              if (heroes) {
                                f.heroGuid = e.guid;
                              } else {
                                f.mapGuid = e.guid;
                              }
                              workspace.touch();
                              app.setTab('matches');
                            },
                    );
                  }(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
