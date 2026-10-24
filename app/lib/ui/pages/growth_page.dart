import 'package:flutter/material.dart';

import '../../core/metric_doc.dart';
import '../../core/models.dart';
import '../../core/stats.dart';
import '../../core/support.dart';
import '../../design/cards.dart';
import '../../design/charts.dart';
import '../../design/icons.dart';
import '../../design/share.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';
import '../../l10n/strings.dart';
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

  /// Its section of the metrics page.
  MetricDoc get doc => switch (metric) {
    GrowthMetric.life => MetricDoc.life,
    GrowthMetric.fleta => MetricDoc.fleta,
    GrowthMetric.kda => MetricDoc.kda,
    GrowthMetric.healing || GrowthMetric.mitigation => MetricDoc.per10,
  };
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
    title: tr.analysis.lifeTitle,
    info: tr.analysis.lifeInfo,
    value: (p) => p.lifeS,
    format: _clock,
    axisFormat: _clock,
    noteOf: (p) => p.deathless
        ? tr.analysis.lifeNoteDeathless(fmtClock(p.durationS))
        : tr.analysis.lifeNote(fmtClock(p.durationS), fmtInt(p.deaths)),
    card: tr.analysis.lifeCard,
    changeText: (d) =>
        tr.analysis.seconds('${d < 0 ? '−' : '+'}${fmtInt(d.abs())}'),
    shieldMeaning: tr.analysis.lifeShield,
  ),
  _Measure(
    metric: GrowthMetric.fleta,
    title: tr.analysis.fletaTitle,
    info: tr.analysis.fletaInfo,
    value: (p) => p.fleta,
    format: (v) => fmtPct(v, digits: 0),
    axisFormat: (v) => fmtPct(v, digits: 0),
    noteOf: (_) => '',
    card: tr.analysis.fletaCard,
    changeText: (d) =>
        tr.analysis.percentagePoints('${d < 0 ? '−' : '+'}${fmtInt(d.abs())}'),
  ),
  _Measure(
    metric: GrowthMetric.kda,
    title: 'KDA',
    info: tr.analysis.kdaInfo,
    value: (p) => p.kda,
    format: fmtOne,
    axisFormat: fmtOne,
    noteOf: (p) => p.deathless
        ? tr.analysis.deathless
        : tr.analysis.deaths(fmtInt(p.deaths)),
    card: 'KDA',
    changeText: (d) => '${d < 0 ? '−' : '+'}${fmtOne(d.abs())}',
    shieldMeaning: tr.analysis.kdaShield,
  ),
  _Measure(
    metric: GrowthMetric.healing,
    title: tr.analysis.healingTitle,
    info: tr.analysis.healingInfo,
    value: (p) => p.healing10,
    format: (v) => tr.analysis.per10Min(fmtInt(v)),
    axisFormat: fmtInt,
    noteOf: (_) => '',
    card: tr.analysis.healingTitle,
    changeText: (d) => '${d < 0 ? '−' : '+'}${fmtInt(d.abs())}',
  ),
  _Measure(
    metric: GrowthMetric.mitigation,
    title: tr.analysis.mitigationTitle,
    info: tr.analysis.mitigationInfo,
    value: (p) => p.mitigation10,
    format: (v) => tr.analysis.per10Min(fmtInt(v)),
    axisFormat: fmtInt,
    noteOf: (_) => '',
    card: tr.analysis.mitigationTitle,
    changeText: (d) => '${d < 0 ? '−' : '+'}${fmtInt(d.abs())}',
  ),
];

class _GrowthPageState extends State<GrowthPage> {
  /// The role the page is about; null for all of them together.
  Role? _role;

  /// The latest stretch against the one before it, match by match.
  bool _compare = false;

  /// The match pointed at in any chart: every chart shows the same one, as they all run
  /// over the same matches.
  final _cursor = ValueNotifier<int?>(null);

  @override
  void dispose() {
    _cursor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final ws = widget.workspace;
    final mode = app.mode;
    final load = ws.growthFor(mode);
    final c = context.c;

    if (load.failedWithoutData) {
      return ErrorPanel(
        what: tr.analysis.growthFailed,
        error: load.error!,
        onRetry: () => ws.loadGrowth(mode),
      );
    }
    final data = load.value;
    if (data == null) {
      return AfterDelay(
        child: Center(child: RefreshingChip(label: tr.analysis.growthLoading)),
      );
    }
    if (!data.enabled || data.points.isEmpty) {
      return EmptyState(
        icon: Icons.trending_up_sharp,
        title: tr.analysis.noGrowthMatches(mode.label),
        body: data.listed == 0
            ? tr.analysis.readMatchListFirst
            : tr.analysis.detailsNotStored(data.listed),
        actions: [
          AppButton(tr.common.refresh, onPressed: () => ws.loadGrowth(mode)),
        ],
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
      padding: const EdgeInsets.only(right: scrollGutter),
      children: [
        Wrap(
          spacing: Sp.betweenGroups,
          runSpacing: Sp.withinGroup,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Semantics(
              header: true,
              child: Text(
                tr.analysis.growthTitle(mode.label),
                style: Ty.section,
              ),
            ),
            if (roles.length > 1)
              SegmentedBar<Role?>(
                semanticLabel: tr.analysis.roleSemantic,
                value: role,
                onChanged: (v) => setState(() => _role = v),
                segments: [
                  Segment<Role?>(null, tr.analysis.all),
                  for (final r in roles) Segment<Role?>(r, r.label),
                ],
              ),
            AppButton(
              tr.compare.compareTime,
              icon: Icons.compare_arrows_sharp,
              quiet: !_compare,
              primary: _compare,
              tooltip: tr.compare.compareTimeTip,
              onPressed: () => setState(() => _compare = !_compare),
            ),
            LoadStatusBar(
              compact: true,
              at: load.at,
              loading: load.loading,
              error: load.error?.message,
              onRetry: () => ws.loadGrowth(mode),
            ),
            InfoTip(tr.analysis.growthInfo, doc: MetricDoc.confidence),
          ],
        ),
        if (data.stored < data.listed || data.skipped > 0) ...[
          const SizedBox(height: Sp.withinGroup),
          Text(
            tr.analysis.growthCoverage(
              analysed: data.points.length,
              listed: data.listed,
              notStored: data.stored < data.listed
                  ? data.listed - data.stored
                  : 0,
              skipped: data.skipped,
            ),
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
          tr.analysis.confidenceMeaning,
          style: Ty.meta.copyWith(color: c.textSecondary),
        ),
        for (final m in shown) ...[
          const SizedBox(height: Sp.betweenSections),
          Shareable(
            title: m.title,
            accent: c.accent,
            info: m.info,
            infoDoc: m.doc,
            caption: tr.recap.caption(
              app.maskName(ws.name),
              mode.label,
              points.length,
            ),
            fileName: m.title,
            child: _compare
                ? _CompareChart(m, points, sync: _cursor)
                : _MeasureChart(m, points, sync: _cursor),
          ),
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
      null => (
        tr.analysis.trendTooFew(m.card),
        Icons.remove_sharp,
        c.textSecondary,
      ),
      Trend.up => (
        tr.analysis.trendUp(m.card),
        Icons.trending_up_sharp,
        c.positive,
      ),
      Trend.down => (
        tr.analysis.trendDown(m.card),
        Icons.trending_down_sharp,
        c.negative,
      ),
      Trend.flat => (
        tr.analysis.trendFlat(m.card),
        Icons.trending_flat_sharp,
        c.textSecondary,
      ),
    };
    final pText = g == null
        ? null
        : g.p < 0.001
        ? 'p < 0.001'
        : 'p = ${g.p.toStringAsFixed(3)}';
    final changePct = g == null
        ? ''
        : '${g.changePct < 0 ? '−' : '+'}${fmtInt(g.changePct.abs())}';
    // What the card says under its headline: how big the change is, and how sure.
    final p = g == null
        ? tr.analysis.trendNeedsEight
        : tr.analysis.trendEffect(changePct, g.confidence.label);
    final card = CardSurface(
      accent: color,
      child: Row(
        children: [
          Icon(icon, size: 32, color: color),
          const SizedBox(width: Sp.betweenItems),
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
                const SizedBox(height: Sp.hairline),
                Text(
                  p,
                  style: Ty.body.copyWith(color: c.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return g == null
        ? card
        : Tooltip(
            message: tr.analysis.trendTip(
              older: m.format(g.olderMean),
              newer: m.format(g.newerMean),
              change: m.changeText(g.change),
              changePct:
                  '${g.changePct < 0 ? '−' : '+'}${fmtInt(g.changePct.abs())}',
              matches: g.matches,
              p: pText!,
            ),
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
  const _MeasureChart(this.m, this.points, {required this.sync});
  final ValueNotifier<int?> sync;
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
    ].where((s) => s.isNotEmpty).join(tr.common.sep);

    final known = values.whereType<double>();
    return Panel(
      padding: PanelPadding.chart,
      child: LineChart(
        sync: sync,
        band: () {
          final b = baselineBand(values);
          return ChartBand(
            lows: b.lows,
            highs: b.highs,
            meaning: tr.analysis.baselineMeaning,
          );
        }(),
        height: 260,
        yMin: 0,
        series: [
          ChartSeries(label: m.card, color: c.textSecondary, values: values),
          ChartSeries(
            label: tr.analysis.movingAverage(_window),
            color: c.accent,
            values: average,
          ),
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
        hollowMeaning: tr.analysis.hollowMeaning,
        shielded: m.shieldMeaning == null
            ? null
            : [for (final p in points) p.deathless],
        shieldMeaning: m.shieldMeaning,
        valueFormat: m.format,
        axisFormat: m.axisFormat,
        summary: known.isEmpty
            ? tr.analysis.chartEmpty(m.title)
            : tr.analysis.growthChartSummary(
                title: m.title,
                n: known.length,
                last: m.format(known.last),
                window: _window,
                average: m.format(average.whereType<double>().last),
              ),
      ),
    );
  }
}

/// The latest stretch of matches against the same number just before it, aligned by
/// position (first match of each, second …), with both means and the difference.
class _CompareChart extends StatelessWidget {
  const _CompareChart(this.m, this.points, {required this.sync});
  final ValueNotifier<int?> sync;
  final _Measure m;
  final List<GrowthPoint> points;

  /// Matches per stretch: half the matches, at most 30.
  static int stretch(int matches) => (matches ~/ 2).clamp(0, 30);

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final n = stretch(points.length);
    if (n < 5) {
      return Text(
        tr.compare.timeTooFew,
        style: Ty.body.copyWith(color: c.textSecondary),
      );
    }
    final recent = points.sublist(points.length - n);
    final earlier = points.sublist(points.length - 2 * n, points.length - n);
    final now = [for (final p in recent) m.value(p)];
    final before = [for (final p in earlier) m.value(p)];
    double? mean(List<double?> v) {
      final k = v.whereType<double>();
      return k.isEmpty ? null : k.reduce((a, b) => a + b) / k.length;
    }

    final a = mean(now), b = mean(before);
    final String diff;
    if (a == null || b == null) {
      diff = '';
    } else if (m.format(a) == m.format(b)) {
      diff = tr.compare.same;
    } else {
      diff = tr.compare.diffWord(
        a > b ? tr.compare.higher : tr.compare.lower,
        m.format((a - b).abs()),
      );
    }
    final summary = a == null || b == null
        ? tr.analysis.chartEmpty(m.title)
        : tr.compare.timeDiff(
            m.format(a),
            m.format(b),
            diff,
            now.whereType<double>().length,
            before.whereType<double>().length,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(summary, style: Ty.body),
        const SizedBox(height: Sp.withinControl),
        Panel(
          padding: PanelPadding.chart,
          child: LineChart(
            sync: sync,
            height: 220,
            yMin: 0,
            series: [
              ChartSeries(
                label: tr.compare.recentStretch(n),
                color: c.accent,
                values: now,
              ),
              ChartSeries(
                label: tr.compare.earlierStretch(n),
                color: c.textSecondary,
                values: before,
                dashed: true,
              ),
            ],
            xLabels: [for (var i = 0; i < n; i++) tr.compare.nth(i + 1)],
            valueFormat: m.format,
            axisFormat: m.axisFormat,
            summary: summary,
          ),
        ),
      ],
    );
  }
}
