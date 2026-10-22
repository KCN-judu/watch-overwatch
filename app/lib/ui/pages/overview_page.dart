import 'package:flutter/material.dart';

import '../../core/metric_doc.dart';
import '../../core/benchmark.dart';
import '../../core/models.dart';
import '../../core/overview.dart';
import '../../core/support.dart';
import '../../design/cards.dart';
import '../../design/chart_kit.dart';
import '../../design/icons.dart';
import '../../design/net_pic.dart';
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
        icon: Icons.dashboard_outlined,
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
      padding: const EdgeInsets.only(right: Sp.betweenGroups, bottom: Sp.page),
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

    final figures = Wrap(
      spacing: Sp.page,
      runSpacing: Sp.betweenGroups,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        _Figure(
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
          trailing: Sparkline(
            values: o.rollingWinPct,
            label: tr.overview.rollingLabel,
            format: (v) => fmtPct(v, digits: 0),
            width: 96,
            height: 32,
          ),
        ),
        _Figure(
          label: tr.overview.recordRecent,
          value: tr.overview.record(recent.wins, recent.losses, recent.draws),
          small: true,
        ),
        _Figure(
          label: tr.overview.kdaRecent,
          value: fmtTwo(o.recent.kda),
          note: kdaDelta == null ? null : tr.overview.versusBefore(kdaDelta),
          noteColor: kdaUp ? c.positive : c.negative,
        ),
        _Figure(
          label: tr.overview.today,
          value: today == null || today.matches == 0
              ? tr.overview.noMatchesToday
              : tr.overview.record(today.wins, today.losses, today.draws),
          small: true,
        ),
      ],
    );

    return ClipRect(
      child: Stack(
        children: [
          // The player's most-played hero, faded in from the right behind the figures.
          if (banner != null)
            Positioned.fill(
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (rect) => const LinearGradient(
                  begin: Alignment.centerRight,
                  end: Alignment.centerLeft,
                  colors: AppColors.artFade,
                  stops: [0, 0.6, 1],
                ).createShader(rect),
                child: Opacity(
                  opacity: 0.55,
                  child: NetPic(
                    banner,
                    fit: BoxFit.cover,
                    alignment: const Alignment(0.6, -0.2),
                  ),
                ),
              ),
            ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(Sp.betweenSections),
            decoration: BoxDecoration(
              border: Border.all(color: c.border),
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  c.raised.withValues(alpha: 0.96),
                  c.raised.withValues(alpha: 0.80),
                  c.raised.withValues(alpha: 0.30),
                ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      tr.overview.coverage(listed, mode.label),
                      style: Ty.meta.copyWith(color: c.textSecondary),
                    ),
                    InfoTip(tr.overview.coverageTip),
                    const Spacer(),
                    AppButton(
                      tr.recap.open,
                      icon: Icons.auto_stories_outlined,
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
                ),
                const SizedBox(height: Sp.betweenGroups),
                figures,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One headline figure: small label, the figure in the display size, and a coloured
/// comparison under it.
class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.value,
    this.note,
    this.noteColor,
    this.trailing,
    this.small = false,
  });
  final String label, value;
  final String? note;
  final Color? noteColor;
  final Widget? trailing;

  /// A phrase rather than a number: one step smaller.
  final bool small;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      container: true,
      label: [label, value, ?note].join('，'),
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Ty.meta.copyWith(color: c.textSecondary)),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              AnimatedValueText(
                value,
                style: Ty.num(small ? Ty.figure : Ty.display),
              ),
              if (trailing != null) ...[
                const SizedBox(width: Sp.betweenGroups),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: trailing!,
                ),
              ],
            ],
          ),
          if (note != null)
            Text(note!, style: Ty.meta.copyWith(color: noteColor)),
        ],
      ),
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
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final f in o.form)
              Pressable(
                onTap: () {
                  workspace.openMatch(mode, f.matchId, ids);
                  app.setTab('matches');
                },
                semanticLabel: tr.overview.formTip(
                  f.outcome.label,
                  f.map?.label ?? tr.common.unknownMap,
                  f.hero?.label ?? tr.common.unknownHero,
                  fmtDateTime(f.startedAtMs),
                ),
                tooltip: tr.overview.formTip(
                  f.outcome.label,
                  f.map?.label ?? tr.common.unknownMap,
                  f.hero?.label ?? tr.common.unknownHero,
                  fmtDateTime(f.startedAtMs),
                ),
                radius: 0,
                child: SizedBox(
                  width: 52,
                  height: 64,
                  child: Column(
                    children: [
                      SizedBox(
                        width: 52,
                        height: 52,
                        child: PortraitCell(app.catalog.heroPortrait(f.hero)),
                      ),
                      // The result: a coloured bar with the word, not colour alone.
                      Container(
                        height: 12,
                        alignment: Alignment.center,
                        color: c.outcome(f.outcome.id),
                        child: Text(
                          f.outcome.label,
                          style: Ty.meta.copyWith(
                            fontSize: 10,
                            height: 1.1,
                            color: c.onAccent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
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
          ? Icons.local_fire_department_outlined
          : Icons.self_improvement,
    InsightKind.streakStrength => Icons.balance,
    InsightKind.map => Icons.map_outlined,
    InsightKind.hero || InsightKind.heroMetric => Icons.person_outline,
    InsightKind.fatigue => Icons.bedtime_outlined,
    _ => i.positive ? Icons.trending_up : Icons.trending_down,
  };

  /// Opens the match list filtered to a finding's map or hero.
  void _drill(AppState app, String kind, String key) {
    for (final m in workspace.matchesFor(mode).value?.matches ?? const []) {
      final e = kind == 'map' ? m.map : m.hero;
      if (e == null || _Groups._stable(e) != key) continue;
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
                                ? Icons.map_outlined
                                : Icons.person_outline,
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
                icon: Icons.filter_alt_outlined,
                label: tr.overview.openMatches,
                onPressed: () => _drill(app, drill.$1, drill.$2),
              ),
            IconAction(
              icon: Icons.notifications_off_outlined,
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
      if (e != null && _stable(e) == key) return e;
    }
    return null;
  }

  static String _stable(EntityRef e) => e.officialId != null
      ? 'overwatch:${e.kind}:${e.officialId!.toLowerCase()}'
      : 'dashen:${e.kind}:${e.guid}';

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
