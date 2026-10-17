import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/support.dart';
import '../../design/charts.dart';
import '../../design/data_table.dart';
import '../../design/icons.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';
import '../../state/app_state.dart';
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
        what: '无法读取往期赛季',
        error: load.error!,
        onRetry: () => ws.loadTrend(mode, fresh: true),
      );
    }
    final points = load.value ?? const <SeasonPoint>[];
    if (load.firstLoad || (!load.has && !load.loading)) {
      return const AfterDelay(
        child: Center(child: RefreshingChip(label: '正在读取往期赛季…')),
      );
    }
    if (points.isEmpty) {
      return EmptyState(
        icon: Icons.timeline,
        title: '没有往期${mode.label}记录',
        body: '最近 6 个赛季没有${mode.label}的职责数据，可能没打过或资料为私密。',
        actions: [
          AppButton('重试', onPressed: () => ws.loadTrend(mode, fresh: true)),
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
              child: Text('${mode.label} · S$first–S$last', style: Ty.section),
            ),
            if (range.length > 1)
              SegmentedBar<String>(
                semanticLabel: '指标',
                value: metric,
                onChanged: (v) => setState(() => _metric = v),
                segments: [
                  Segment(
                    'rank',
                    '段位分',
                    hint: hasRank ? '500–5000' : '${mode.label}没有段位',
                  ),
                  const Segment('win', '胜率'),
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
                        ? '三张图纵轴相同，可直接比较。实线是赛季末段位，虚线是该赛季最高段位。'
                        : '${mode.label}不提供段位，请切换到胜率。')
                  : '胜率 = 胜 ÷ （胜 + 负），纵轴 0–100%。没有数据的赛季线会断开。',
            ),
          ],
        ),
        const SizedBox(height: Sp.betweenGroups),
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
            '只读到 S$first 一个赛季，不画折线。',
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
          Semantics(header: true, child: Text('各赛季数据', style: Ty.section)),
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
      tableLabel: '各赛季各职责数据',
      columns: [
        Col(
          id: 'season',
          label: '赛季',
          width: 84,
          cell: (_, p) => Text('S${p.season ?? '?'}'),
        ),
        Col(
          id: 'role',
          label: '职责',
          width: 72,
          flex: true,
          tooltip: roleLegend,
          cell: (_, p) => RoleIcon(p.role, size: 18, showLabel: true),
        ),
        Col(
          id: 'matches',
          label: '场次',
          width: 64,
          numeric: true,
          cell: (_, p) => Text(fmtInt(p.matches)),
        ),
        Col(
          id: 'win',
          label: '胜率',
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
          label: '赛季末段位',
          width: 120,
          cell: (_, p) => RankBadge(
            p.current,
            catalog: AppScope.read(context).catalog,
            showText: true,
          ),
        ),
        Col(
          id: 'peak',
          label: '最高段位',
          width: 120,
          cell: (_, p) => RankBadge(
            p.peak,
            catalog: AppScope.read(context).catalog,
            showText: true,
          ),
        ),
      ],
      rows: rows,
      rowLabel: (p) =>
          '第${p.season}赛季，${p.role.label}，${fmtInt(p.matches)} 场，胜率${fmtPct(p.winRatePct)}，赛季末${p.current?.label ?? '未定级'}，最高${p.peak?.label ?? '未定级'}',
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
        ? '${role.label}：这些赛季没有可用数据。'
        : '${role.label}：S${range.first} 到 S${range.last}，最近一个有数据的赛季为 ${fmtInt(known.last)}${metric == 'rank' ? ' 分' : '%'}。';
    return SizedBox(
      width: 420,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          Sp.withinGroup,
          Sp.betweenGroups,
          Sp.withinGroup,
          Sp.withinGroup,
        ),
        decoration: BoxDecoration(
          color: c.raised,
          borderRadius: BorderRadius.circular(Radii.container),
          border: Border.all(color: c.border),
        ),
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
                  label: metric == 'rank' ? '赛季末' : '胜率',
                  color: c.ally,
                  values: current,
                ),
                if (metric == 'rank')
                  ChartSeries(
                    label: '最高',
                    color: c.enemy,
                    values: peak,
                    dashed: true,
                  ),
              ],
              xLabels: [for (final s in range) 'S$s'],
              pointNotes: [
                for (final s in range)
                  mine[s] == null
                      ? '没有数据'
                      : '${fmtInt(mine[s]!.matches)} 场 · ${mine[s]!.current?.label ?? '未定级'}',
              ],
              valueFormat: (x) =>
                  metric == 'rank' ? fmtInt(x) : '${fmtInt(x)}%',
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
    return Container(
      width: 360,
      padding: const EdgeInsets.all(Sp.betweenGroups),
      decoration: BoxDecoration(
        color: c.raised,
        borderRadius: BorderRadius.circular(Radii.container),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              RoleIcon(p.role, size: 22, showLabel: true),
              const Spacer(),
              Text(
                'S${p.season ?? '?'}',
                style: Ty.num(Ty.body).copyWith(color: c.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: Sp.betweenGroups),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              stat('场次', fmtInt(p.matches)),
              stat('胜率', fmtPct(p.winRatePct)),
              stat('KDA', fmtTwo(p.kda)),
            ],
          ),
          if (p.current != null || p.peak != null) ...[
            const SizedBox(height: Sp.betweenGroups),
            Row(
              children: [
                Text('赛季末', style: Ty.meta.copyWith(color: c.textSecondary)),
                const SizedBox(width: 6),
                RankBadge(p.current, catalog: catalog, showText: true),
                const Spacer(),
                Text('最高', style: Ty.meta.copyWith(color: c.textSecondary)),
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
