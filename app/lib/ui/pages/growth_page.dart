import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/support.dart';
import '../../design/cards.dart';
import '../../design/charts.dart';
import '../../design/icons.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';
import '../../state/app_state.dart';
import '../player_view.dart';

/// The growth panel: a few measures of how the player is doing, each as a line over their
/// matches with its trend. Read from what is stored locally, so it opens at once. More
/// measures are added by describing them in [_measures] and giving the service a value
/// for each match.
class GrowthPage extends StatefulWidget {
  const GrowthPage({super.key, required this.workspace});
  final PlayerWorkspace workspace;
  @override
  State<GrowthPage> createState() => _GrowthPageState();
}

/// Matches averaged by each chart's moving-average line.
const _window = 10;

String _two(int v) => v.toString().padLeft(2, '0');

String _clock(double v) => fmtClock(v);

/// One measure of the panel: what it is called, how its figures read, and where in a
/// match point it lives.
class _Measure {
  const _Measure({
    required this.metric,
    required this.title,
    required this.info,
    required this.value,
    required this.format,
    required this.axisFormat,
    required this.noteOf,
    required this.card,
    required this.changeText,
    this.shieldMeaning,
  });
  final GrowthMetric metric;
  final String title, info;
  final double? Function(GrowthPoint) value;

  /// A figure in the readout and the trend line; `axisFormat` on the chart's axis.
  final String Function(double) format, axisFormat;

  /// The line under the date in the readout about one match.
  final String Function(GrowthPoint) noteOf;

  /// What the trend card calls the thing that is rising or falling ("保活能力").
  final String card;

  /// A change of this size in the measure's own unit, signed.
  final String Function(double) changeText;

  /// What a shield on a point means for this measure (null: no shields).
  final String? shieldMeaning;
}

final _measures = [
  _Measure(
    metric: GrowthMetric.life,
    title: '存活时长（保活能力）',
    info:
        '每次阵亡之间平均隔多久 = 对局时长 ÷ 阵亡次数。上游只给阵亡次数、不给每次阵亡的时间点，所以只能这样平均着算。'
        '没有死亡的对局取整局时长（实际只会更长），用盾牌标出，背后的底色填满这一局；含重生等待。',
    value: (p) => p.lifeS,
    format: _clock,
    axisFormat: _clock,
    noteOf: (p) => p.deathless
        ? '对局时长 ${fmtClock(p.durationS)} · 没有死亡'
        : '对局时长 ${fmtClock(p.durationS)} · 阵亡 ${fmtInt(p.deaths)} 次',
    card: '保活能力',
    changeText: (d) => '${d < 0 ? '−' : '+'}${fmtInt(d.abs())} 秒',
    shieldMeaning: '盾牌：这一局没有死亡，数值是整局时长，实际更长。',
  ),
  _Measure(
    metric: GrowthMetric.fleta,
    title: 'Fleta 指数',
    info:
        '最后一击 ÷（本队最后一击合计 × 0.5）× 100%。100% 表示拿下了本队一半的最后一击。'
        '只和本队比、不分职责，辅助和重装通常偏低，输出偏高，所以按职责看更有意义。',
    value: (p) => p.fleta,
    format: (v) => fmtPct(v, digits: 0),
    axisFormat: (v) => fmtPct(v, digits: 0),
    noteOf: (_) => '',
    card: 'Fleta 指数',
    changeText: (d) => '${d < 0 ? '−' : '+'}${fmtInt(d.abs())} 个百分点',
  ),
  _Measure(
    metric: GrowthMetric.kda,
    title: 'KDA',
    info: '（消灭 + 助攻）÷ 阵亡。没有死亡的对局按 1 次阵亡算，用盾牌标出。',
    value: (p) => p.kda,
    format: fmtOne,
    axisFormat: fmtOne,
    noteOf: (p) => p.deathless ? '没有死亡' : '阵亡 ${fmtInt(p.deaths)} 次',
    card: 'KDA',
    changeText: (d) => '${d < 0 ? '−' : '+'}${fmtOne(d.abs())}',
    shieldMeaning: '盾牌：这一局没有死亡，按 1 次阵亡算。',
  ),
  _Measure(
    metric: GrowthMetric.healing,
    title: '治疗量',
    info: '每 10 分钟的治疗量（含自我治疗）。只算你打辅助的对局：别的职责的治疗是副产品，混进来会把数字拉低。',
    value: (p) => p.healing10,
    format: (v) => '${fmtInt(v)} / 10 分钟',
    axisFormat: fmtInt,
    noteOf: (_) => '',
    card: '治疗量',
    changeText: (d) => '${d < 0 ? '−' : '+'}${fmtInt(d.abs())}',
  ),
  _Measure(
    metric: GrowthMetric.mitigation,
    title: '阻挡量',
    info: '每 10 分钟阻挡或减免的伤害。只算你打重装的对局：别的职责的阻挡量很少，混进来没有意义。',
    value: (p) => p.mitigation10,
    format: (v) => '${fmtInt(v)} / 10 分钟',
    axisFormat: fmtInt,
    noteOf: (_) => '',
    card: '阻挡量',
    changeText: (d) => '${d < 0 ? '−' : '+'}${fmtInt(d.abs())}',
  ),
];

class _GrowthPageState extends State<GrowthPage> {
  /// The role the page is about; null for all of them together.
  Role? _role;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final ws = widget.workspace;
    final mode = app.mode;
    final load = ws.growthFor(mode);
    final c = context.c;

    if (load.failedWithoutData) {
      return ErrorPanel(
        what: '无法读取成长数据',
        error: load.error!,
        onRetry: () => ws.loadGrowth(mode),
      );
    }
    final data = load.value;
    if (data == null) {
      return const AfterDelay(
        child: Center(child: RefreshingChip(label: '正在读取成长数据…')),
      );
    }
    if (!data.enabled || data.points.isEmpty) {
      return EmptyState(
        icon: Icons.trending_up,
        title: '还没有可分析的${mode.label}对局',
        body: data.listed == 0
            ? '先在“对局”页读取对局列表。'
            : '已读取 ${data.listed} 场，但它们的详情还没存到本机（需要对局时长和阵亡数）。'
                  '打开几场对局，或等后台准备完成后再来。',
        actions: [AppButton('重新读取', onPressed: () => ws.loadGrowth(mode))],
      );
    }

    final roles = data.roles;
    // A role the mode has no matches for cannot stay selected.
    final role = roles.contains(_role) ? _role : null;
    final points = [
      for (final p in data.points)
        if (role == null || p.role == role) p,
    ];
    // A measure with no figure for the matches on screen (healing for a tank) is left out.
    final shown = [
      for (final m in _measures)
        if (points.any((p) => m.value(p) != null)) m,
    ];

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
              child: Text('${mode.label} · 成长', style: Ty.section),
            ),
            if (roles.length > 1)
              SegmentedBar<Role?>(
                semanticLabel: '职责',
                value: role,
                onChanged: (v) => setState(() => _role = v),
                segments: [
                  const Segment<Role?>(null, '全部'),
                  for (final r in roles) Segment<Role?>(r, r.label),
                ],
              ),
            LoadStatusBar(
              compact: true,
              at: load.at,
              loading: load.loading,
              error: load.error?.message,
              onRetry: () => ws.loadGrowth(mode),
            ),
            const InfoTip(
              '每个指标一张图：一个点是一局，粗线是最近 10 局的平均；空心点是败局。'
              '图上面一行是走势：把对局分成较早一半和较新一半比平均值，并做趋势检验。'
              '不同职责的数值本来就不一样，换职责会让“全部”变化，所以以分职责的结果为准。',
            ),
          ],
        ),
        if (data.stored < data.listed || data.skipped > 0) ...[
          const SizedBox(height: Sp.withinGroup),
          Text(
            [
              '已分析 ${data.points.length} 场（对局列表共 ${data.listed} 场）',
              if (data.stored < data.listed)
                '其余 ${data.listed - data.stored} 场的详情还没存到本机，后台准备好后会算进来',
              if (data.skipped > 0) '${data.skipped} 场太短或没有阵亡数，没有计入',
            ].join('；'),
            style: Ty.meta.copyWith(color: c.textSecondary),
          ),
        ],
        const SizedBox(height: Sp.betweenSections),
        CardGrid(minWidth: 230, height: 84, [
          for (final m in shown)
            _TrendCard(m, data.metric(m.metric)?.growthFor(role)),
        ]),
        const SizedBox(height: Sp.withinGroup),
        Text(
          'p：如果其实没有变化、只是每局运气有高有低，也出现这么明显走势的可能性。小于 0.1 才说有趋势，越小越可信；不到 8 场不下结论。',
          style: Ty.meta.copyWith(color: c.textSecondary),
        ),
        for (final m in shown) ...[
          const SizedBox(height: Sp.betweenSections),
          AccentTitle(m.title, accent: c.accent, info: m.info),
          const SizedBox(height: Sp.withinGroup + 2),
          _MeasureChart(m, points),
        ],
        const SizedBox(height: Sp.betweenSections),
      ],
    );
  }
}

/// One measure's trend as a card: what is rising or falling, and the p value under it.
class _TrendCard extends StatelessWidget {
  const _TrendCard(this.m, this.g);
  final _Measure m;
  final Growth? g;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final g = this.g;
    final (text, icon, color) = switch (g?.trend) {
      null => ('${m.card}：场次不足', Icons.remove, c.textSecondary),
      Trend.up => ('${m.card}呈现上升趋势', Icons.trending_up, c.win),
      Trend.down => ('${m.card}呈现下降趋势', Icons.trending_down, c.loss),
      Trend.flat => ('${m.card}没有明显趋势', Icons.trending_flat, c.textSecondary),
    };
    final p = g == null
        ? '不到 8 场，看不出走势'
        : g.p < 0.001
        ? 'p < 0.001'
        : 'p = ${g.p.toStringAsFixed(3)}';
    final card = CardSurface(
      accent: color,
      child: Row(
        children: [
          Icon(icon, size: 32, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: Ty.bodyStrong.copyWith(color: color),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(p, style: Ty.body.copyWith(color: c.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
    return g == null
        ? card
        : Tooltip(
            message:
                '较早一半 ${m.format(g.olderMean)} → 较新一半 ${m.format(g.newerMean)}'
                '（${m.changeText(g.change)}，${g.changePct < 0 ? '−' : '+'}${fmtInt(g.changePct.abs())}%），共 ${g.matches} 场',
            child: card,
          );
  }
}

/// The mean of the last [_window] values that exist; null where there are none.
List<double?> _moving(List<double?> v) => [
  for (var i = 0; i < v.length; i++)
    () {
      final seen = [
        for (var k = (i - _window + 1).clamp(0, i); k <= i; k++)
          if (v[k] != null) v[k]!,
      ];
      return seen.isEmpty ? null : seen.reduce((a, b) => a + b) / seen.length;
    }(),
];

class _MeasureChart extends StatelessWidget {
  const _MeasureChart(this.m, this.points);
  final _Measure m;
  final List<GrowthPoint> points;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final values = [for (final p in points) m.value(p)];
    final average = _moving(values);
    String when(GrowthPoint p) {
      final t = DateTime.fromMillisecondsSinceEpoch(p.startedAtMs ?? 0);
      return '${_two(t.month)}-${_two(t.day)} ${_two(t.hour)}:${_two(t.minute)}';
    }

    String note(GrowthPoint p) => [
      when(p),
      p.hero?.label ?? p.role.label,
      p.outcome.label,
      m.noteOf(p),
    ].where((s) => s.isNotEmpty).join(' · ');

    final known = values.whereType<double>();
    return Container(
      padding: const EdgeInsets.fromLTRB(
        Sp.withinGroup,
        Sp.betweenGroups,
        Sp.withinGroup,
        Sp.withinGroup,
      ),
      decoration: BoxDecoration(
        color: c.raised,
        border: Border.all(color: c.border),
      ),
      child: LineChart(
        height: 260,
        yMin: 0,
        series: [
          ChartSeries(label: m.card, color: c.textSecondary, values: values),
          ChartSeries(label: '$_window 局平均', color: c.accent, values: average),
        ],
        xLabels: [
          for (final p in points)
            () {
              final t = DateTime.fromMillisecondsSinceEpoch(p.startedAtMs ?? 0);
              return '${_two(t.month)}-${_two(t.day)}';
            }(),
        ],
        pointNotes: [for (final p in points) note(p)],
        hollow: [for (final p in points) p.outcome == Outcome.loss],
        hollowMeaning: '实心点：胜或平；空心点：负。',
        shielded: m.shieldMeaning == null
            ? null
            : [for (final p in points) p.deathless],
        shieldMeaning: m.shieldMeaning,
        valueFormat: m.format,
        axisFormat: m.axisFormat,
        summary: known.isEmpty
            ? '${m.title}：没有数据。'
            : '${m.title}：${known.length} 场，最近一局 ${m.format(known.last)}，'
                  '最近 $_window 局平均 ${m.format(average.whereType<double>().last)}。',
      ),
    );
  }
}
