import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/support.dart';
import '../../design/cards.dart';
import '../../design/charts.dart';
import '../../design/data_table.dart';
import '../../design/icons.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';
import '../../l10n/strings.dart';
import '../../state/app_state.dart';
import 'rank_track.dart';
import '../player_view.dart';

class TrendPage extends StatefulWidget {
  const TrendPage({super.key, required this.workspace});
  final PlayerWorkspace workspace;
  @override
  State<TrendPage> createState() => _TrendPageState();
}

class _TrendPageState extends State<TrendPage> {
  /// 'rank' or 'win'. Defaults to rank when the data has any rank at all.
  String? _metric;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final ws = widget.workspace;
    final mode = app.mode;
    final load = ws.trendFor(mode);

    if (load.failedWithoutData) {
      return ErrorPanel(
        what: tr.analysis.trendFailed,
        error: load.error!,
        onRetry: () => ws.loadTrend(mode, fresh: true),
      );
    }
    final points = load.value ?? const <SeasonPoint>[];
    if (load.firstLoad || (!load.has && !load.loading)) {
      return AfterDelay(
        child: Center(child: RefreshingChip(label: tr.analysis.trendLoading)),
      );
    }
    if (points.isEmpty) {
      return EmptyState(
        icon: Icons.timeline,
        title: tr.analysis.noPastSeasons(mode.label),
        body: tr.analysis.noPastSeasonsBody(mode.label),
        actions: [
          AppButton(
            tr.common.refresh,
            onPressed: () => ws.loadTrend(mode, fresh: true),
          ),
        ],
      );
    }

    final seasons = points.map((p) => p.season).whereType<int>().toList()
      ..sort();
    final first = seasons.first, last = seasons.last;
    final range = [for (var s = first; s <= last; s++) s];
    final hasRank = points.any((p) => p.current?.skillRating != null);
    final metric = _metric ?? (hasRank ? 'rank' : 'win');
    final roles = Role.playable
        .where((r) => points.any((p) => p.role == r))
        .toList();

    return ListView(
      padding: const EdgeInsets.only(right: 16),
      children: [
        Wrap(
          spacing: Sp.betweenGroups,
          runSpacing: Sp.withinGroup,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Semantics(
              header: true,
              child: Text(
                tr.analysis.trendTitle(mode.label, first, last),
                style: Ty.section,
              ),
            ),
            if (range.length > 1)
              SegmentedBar<String>(
                semanticLabel: tr.analysis.metricSemantic,
                value: metric,
                onChanged: (v) => setState(() => _metric = v),
                segments: [
                  Segment(
                    'rank',
                    tr.analysis.ratingSegment,
                    hint: hasRank
                        ? tr.analysis.ratingSegmentHint
                        : tr.analysis.noRanksIn(mode.label),
                  ),
                  Segment('win', tr.analysis.winRate),
                ],
              ),
            LoadStatusBar(
              compact: true,
              at: load.at,
              loading: load.loading,
              error: load.error?.message,
              onRetry: () => ws.loadTrend(mode, fresh: true),
            ),
            InfoTip(
              metric == 'rank'
                  ? (hasRank
                        ? tr.analysis.rankInfo
                        : tr.analysis.noRankInfo(mode.label))
                  : tr.analysis.winRateInfo,
            ),
          ],
        ),
        const SizedBox(height: Sp.betweenGroups),
        RankTrackSection(
          workspace: ws,
          mode: mode,
          seasonMatches: {
            for (final p in points)
              if (p.season != null)
                p.season!: points
                    .where((q) => q.season == p.season)
                    .fold(0, (n, q) => n + (q.matches ?? 0)),
          },
        ),
        const SizedBox(height: Sp.betweenSections),
        if (range.length == 1) ...[
          Wrap(
            spacing: Sp.betweenGroups,
            runSpacing: Sp.betweenGroups,
            children: [
              for (final r in roles)
                for (final p in points.where((p) => p.role == r))
                  _SeasonCard(point: p, catalog: app.catalog),
            ],
          ),
          const SizedBox(height: Sp.withinGroup),
          Text(
            tr.analysis.onlyOneSeason(first),
            style: Ty.meta.copyWith(color: context.c.textSecondary),
          ),
        ] else ...[
          if (metric == 'rank' && !hasRank)
            const SizedBox.shrink()
          else
            Wrap(
              spacing: Sp.betweenGroups,
              runSpacing: Sp.betweenGroups,
              children: [
                for (final r in roles)
                  _RoleChart(
                    role: r,
                    points: points,
                    range: range,
                    metric: metric,
                    allPoints: points,
                  ),
              ],
            ),
          const SizedBox(height: Sp.betweenSections),
          SectionHeader(tr.analysis.seasonsTitle),
          const SizedBox(height: Sp.withinGroup),
          SizedBox(
            height: _h(context, math.min(points.length, 14)),
            child: _table(context, points),
          ),
          const SizedBox(height: Sp.betweenSections),
        ],
      ],
    );
  }

  double _h(BuildContext context, int rows) {
    final scale = math.max(
      1.0,
      MediaQuery.textScalerOf(context).scale(13) / 13,
    );
    return context.density.rowHeight * scale * (rows + 1) + 4;
  }

  Widget _table(BuildContext context, List<SeasonPoint> points) {
    final rows = [...points]
      ..sort((a, b) {
        final s = (b.season ?? 0).compareTo(a.season ?? 0);
        return s != 0 ? s : a.role.index.compareTo(b.role.index);
      });
    return AppTable<SeasonPoint>(
      tableLabel: tr.analysis.seasonsTable,
      columns: [
        Col(
          id: 'season',
          label: tr.analysis.seasonColumn,
          width: 84,
          cell: (_, p) => Text(tr.analysis.seasonShort(p.season)),
        ),
        Col(
          id: 'role',
          label: tr.analysis.roleColumn,
          width: 72,
          flex: true,
          tooltip: roleLegend,
          cell: (_, p) => RoleIcon(p.role, size: 18, showLabel: true),
        ),
        Col(
          id: 'matches',
          label: tr.analysis.matchesColumn,
          width: 64,
          numeric: true,
          cell: (_, p) => Text(fmtInt(p.matches)),
        ),
        Col(
          id: 'win',
          label: tr.analysis.winRate,
          width: 76,
          numeric: true,
          cell: (_, p) => Text(fmtPct(p.winRatePct)),
        ),
        Col(
          id: 'kda',
          label: 'KDA',
          width: 64,
          numeric: true,
          cell: (_, p) => Text(fmtTwo(p.kda)),
        ),
        Col(
          id: 'cur',
          label: tr.analysis.seasonEndRank,
          width: 120,
          cell: (_, p) => RankBadge(
            p.current,
            catalog: AppScope.read(context).catalog,
            showText: true,
          ),
        ),
        Col(
          id: 'peak',
          label: tr.analysis.peakRank,
          width: 120,
          cell: (_, p) => RankBadge(
            p.peak,
            catalog: AppScope.read(context).catalog,
            showText: true,
          ),
        ),
      ],
      rows: rows,
      rowLabel: (p) => tr.analysis.seasonRow(
        season: p.season == null
            ? tr.common.missing
            : tr.common.season(p.season!),
        role: p.role.label,
        matches: fmtInt(p.matches),
        winRate: fmtPct(p.winRatePct),
        current:
            p.current?.labelOn(stadium: p.mode == Mode.stadium) ??
            tr.common.unranked,
        peak:
            p.peak?.labelOn(stadium: p.mode == Mode.stadium) ??
            tr.common.unranked,
      ),
    );
  }
}

class _RoleChart extends StatelessWidget {
  const _RoleChart({
    required this.role,
    required this.points,
    required this.range,
    required this.metric,
    required this.allPoints,
  });
  final Role role;
  final List<SeasonPoint> points;
  final List<int> range;
  final String metric;
  final List<SeasonPoint> allPoints;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final mine = {
      for (final p in points.where((p) => p.role == role)) p.season: p,
    };
    double? v(SeasonPoint? p, bool peak) => p == null
        ? null
        : metric == 'rank'
        ? (peak ? p.peak?.skillRating : p.current?.skillRating)?.toDouble()
        : p.winRatePct;
    final current = [for (final s in range) v(mine[s], false)];
    final peak = [for (final s in range) v(mine[s], true)];

    // One scale for all roles so the charts can be compared.
    double lo = 0, hi = 100;
    if (metric == 'rank') {
      final all = allPoints
          .expand((p) => [p.current?.skillRating, p.peak?.skillRating])
          .whereType<int>();
      lo = (all.reduce(math.min) / 500).floor() * 500.0;
      hi = (all.reduce(math.max) / 500).ceil() * 500.0;
      if (hi - lo < 500) hi = lo + 500;
    }
    final known = current.whereType<double>();
    final summary = known.isEmpty
        ? tr.analysis.roleNoData(role.label)
        : tr.analysis.roleSummary(
            role.label,
            range.first,
            range.last,
            metric == 'rank'
                ? tr.analysis.points(fmtInt(known.last))
                : tr.analysis.percent(fmtInt(known.last)),
          );
    return SizedBox(
      width: 420,
      child: Panel(
        padding: PanelPadding.chart,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: Sp.withinGroup),
              child: Semantics(
                header: true,
                child: RoleIcon(role, size: 18, showLabel: true),
              ),
            ),
            const SizedBox(height: 4),
            LineChart(
              height: 200,
              yMin: lo,
              yMax: hi,
              series: [
                ChartSeries(
                  label: metric == 'rank'
                      ? tr.analysis.seasonEnd
                      : tr.analysis.winRate,
                  color: c.accent,
                  values: current,
                ),
                if (metric == 'rank')
                  ChartSeries(
                    label: tr.analysis.peak,
                    color: c.textSecondary,
                    values: peak,
                    dashed: true,
                  ),
              ],
              xLabels: [for (final s in range) tr.analysis.seasonShort(s)],
              pointNotes: [
                for (final s in range)
                  mine[s] == null
                      ? tr.analysis.noData
                      : tr.analysis.seasonPointNote(
                          fmtInt(mine[s]!.matches),
                          mine[s]!.current?.labelOn(
                                stadium:
                                    AppScope.of(context).mode == Mode.stadium,
                              ) ??
                              tr.common.unranked,
                        ),
              ],
              valueFormat: (x) =>
                  metric == 'rank' ? fmtInt(x) : tr.analysis.percent(fmtInt(x)),
              summary: summary,
            ),
          ],
        ),
      ),
    );
  }
}

/// One role in one season, as numbers: used when there is only a single season to show.
class _SeasonCard extends StatelessWidget {
  const _SeasonCard({required this.point, required this.catalog});
  final SeasonPoint point;
  final Catalog catalog;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final p = point;
    Widget stat(String label, String value) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Ty.meta.copyWith(color: c.textSecondary)),
        Text(value, style: Ty.num(Ty.figure)),
      ],
    );
    return Panel(
      width: 360,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              RoleIcon(p.role, size: 22, showLabel: true),
              const Spacer(),
              Text(
                tr.analysis.seasonShort(p.season),
                style: Ty.num(Ty.body).copyWith(color: c.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: Sp.betweenGroups),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              stat(tr.analysis.matchesColumn, fmtInt(p.matches)),
              stat(tr.analysis.winRate, fmtPct(p.winRatePct)),
              stat('KDA', fmtTwo(p.kda)),
            ],
          ),
          if (p.current != null || p.peak != null) ...[
            const SizedBox(height: Sp.betweenGroups),
            Row(
              children: [
                Text(
                  tr.analysis.seasonEnd,
                  style: Ty.meta.copyWith(color: c.textSecondary),
                ),
                const SizedBox(width: 6),
                RankBadge(p.current, catalog: catalog, showText: true),
                const Spacer(),
                Text(
                  tr.analysis.peak,
                  style: Ty.meta.copyWith(color: c.textSecondary),
                ),
                const SizedBox(width: 6),
                RankBadge(p.peak, catalog: catalog, showText: true),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
