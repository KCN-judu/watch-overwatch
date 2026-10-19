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

/// Survival time: how long the player lasts per life in a match, whether that is growing,
/// and the match-by-match line. Read from what is stored locally, so it opens at once.
class GrowthPage extends StatefulWidget {
  const GrowthPage({super.key, required this.workspace});
  final PlayerWorkspace workspace;
  @override
  State<GrowthPage> createState() => _GrowthPageState();
}

/// Matches averaged by the moving-average line.
const _window = 10;

String _secs(double? v) => v == null ? missing : '${fmtInt(v)} 秒';

String _signed(double v, {int digits = 0}) {
  final n = digits == 0 ? fmtInt(v.abs()) : fmtOne(v.abs());
  return '${v < 0 ? '−' : '+'}$n';
}

class _GrowthPageState extends State<GrowthPage> {
  /// The role the page is about; null for all of them together.
  Role? _role;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final ws = widget.workspace;
    final mode = app.mode;
    final load = ws.survivalFor(mode);
    final c = context.c;

    if (load.failedWithoutData) {
      return ErrorPanel(
        what: '无法读取存活时长',
        error: load.error!,
        onRetry: () => ws.loadSurvival(mode),
      );
    }
    final data = load.value;
    if (data == null) {
      return const AfterDelay(
        child: Center(child: RefreshingChip(label: '正在读取存活时长…')),
      );
    }
    if (!data.enabled || data.samples.isEmpty) {
      return EmptyState(
        icon: Icons.trending_up,
        title: '还没有可分析的${mode.label}对局',
        body: data.listed == 0
            ? '先在“对局”页读取对局列表。'
            : '已读取 ${data.listed} 场，但它们的详情还没存到本机（需要对局时长和阵亡数）。'
                  '打开几场对局，或等后台准备完成后再来。',
        actions: [AppButton('重新读取', onPressed: () => ws.loadSurvival(mode))],
      );
    }

    final roles = [for (final r in data.byRole) r.role];
    // A role the mode has no matches for cannot stay selected.
    final role = roles.contains(_role) ? _role : null;
    final samples = [
      for (final s in data.samples)
        if (role == null || s.role == role) s,
    ];
    final growth = data.growthFor(role);

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
              child: Text('${mode.label} · 存活时长', style: Ty.section),
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
              onRetry: () => ws.loadSurvival(mode),
            ),
            const InfoTip(
              '一局的平均存活时长 = 这局的时长 ÷（阵亡次数 + 1）：打了 10 分钟、死 3 次，就是每条命约 150 秒。'
              '上游没有直接给存活时间，这个数里含重生等待，所以比真正活着的时间略长，但每一局偏差一样，适合互相比较。'
              '不足 2 分钟的对局不算。',
            ),
          ],
        ),
        if (data.stored < data.listed || data.skipped > 0) ...[
          const SizedBox(height: Sp.withinGroup),
          Text(
            [
              '已分析 ${data.samples.length} 场（对局列表共 ${data.listed} 场）',
              if (data.stored < data.listed)
                '其余 ${data.listed - data.stored} 场的详情还没存到本机，后台准备好后会算进来',
              if (data.skipped > 0) '${data.skipped} 场太短或没有阵亡数，没有计入',
            ].join('；'),
            style: Ty.meta.copyWith(color: c.textSecondary),
          ),
        ],
        const SizedBox(height: Sp.betweenSections),
        AccentTitle('单局平均存活时长', accent: c.accent),
        const SizedBox(height: Sp.withinGroup + 2),
        _SummaryCards(samples: samples, accent: c.accent),
        const SizedBox(height: Sp.betweenSections),
        AccentTitle(
          '成长分析',
          accent: c.accent,
          info:
              '把对局按时间分成较早的一半和较新的一半比平均值，再用 Mann-Kendall 趋势检验看整条走势。'
              'p 是“如果其实没有变化，也会出现这么明显走势”的可能性，小于 0.1 才说有变化，否则说没有明显变化。'
              '不同职责活得不一样长，换职责会让“全部”变化，所以先看分职责的结果。',
        ),
        const SizedBox(height: Sp.withinGroup + 2),
        _GrowthCards(growth: growth, accent: c.accent),
        if (role == null && data.byRole.length > 1) ...[
          const SizedBox(height: Sp.betweenGroups),
          Text('分职责', style: Ty.meta.copyWith(color: c.textSecondary)),
          const SizedBox(height: 6),
          CardGrid(minWidth: 260, height: 96, [
            for (final r in data.byRole) _RoleCard(r, accent: c.accent),
          ]),
        ],
        const SizedBox(height: Sp.betweenSections),
        AccentTitle('局间存活时长', accent: c.accent),
        const SizedBox(height: Sp.withinGroup + 2),
        _LifeChart(samples: samples),
        const SizedBox(height: Sp.betweenSections),
      ],
    );
  }
}

double _median(List<double> v) {
  final s = [...v]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

double _mean(Iterable<double> v) => v.reduce((a, b) => a + b) / v.length;

class _SummaryCards extends StatelessWidget {
  const _SummaryCards({required this.samples, required this.accent});
  final List<LifeSample> samples;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final lives = [for (final s in samples) s.lifeS];
    List<double> of(Outcome o) => [
      for (final s in samples)
        if (s.outcome == o) s.lifeS,
    ];
    final won = of(Outcome.win), lost = of(Outcome.loss);
    Widget card(String label, double? value, String caption) => StatCard(
      label: label,
      value: _secs(value),
      caption: caption,
      accent: accent,
    );
    return CardGrid(minWidth: 200, height: 96, [
      card('平均', _mean(lives), '${samples.length} 场的平均'),
      card('中位数', _median(lives), '一半的对局比这长'),
      card('最短', lives.reduce((a, b) => a < b ? a : b), '死得最快的一局'),
      card('最长', lives.reduce((a, b) => a > b ? a : b), '活得最久的一局'),
      card('胜局平均', won.isEmpty ? null : _mean(won), '${won.length} 场胜利'),
      card('败局平均', lost.isEmpty ? null : _mean(lost), '${lost.length} 场失败'),
    ]);
  }
}

String _verdict(LifeGrowth g) => switch (g.trend) {
  LifeTrend.longer => '活得更久了',
  LifeTrend.shorter => '活得更短了',
  LifeTrend.flat => '没有明显变化',
};

String _pText(double p) =>
    p < 0.001 ? 'p < 0.001' : 'p = ${p.toStringAsFixed(3)}';

class _GrowthCards extends StatelessWidget {
  const _GrowthCards({required this.growth, required this.accent});
  final LifeGrowth? growth;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final g = growth;
    if (g == null) {
      return Text(
        '这个范围的对局不到 8 场，看不出走势。',
        style: Ty.body.copyWith(color: context.c.textSecondary),
      );
    }
    return CardGrid(minWidth: 240, height: 100, [
      StatCard(
        label: '走势',
        value: _verdict(g),
        caption: '${_pText(g.p)}，共 ${g.matches} 场',
        accent: accent,
      ),
      StatCard(
        label: '较早一半 → 较新一半',
        value: '${fmtInt(g.olderMeanS)} → ${fmtInt(g.newerMeanS)} 秒',
        caption: '${_signed(g.changeS)} 秒（${_signed(g.changePct)}%）',
        accent: accent,
      ),
      StatCard(
        label: '平均每打一局',
        value: '${_signed(g.slopeSPerMatch, digits: 2)} 秒',
        caption: '整条走势的拟合斜率',
        accent: accent,
      ),
    ]);
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard(this.r, {required this.accent});
  final RoleLife r;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final g = r.growth;
    return StatCard(
      label: '${r.role.label}（${r.matches} 场，平均 ${_secs(r.meanS)}）',
      value: g == null
          ? '场次太少'
          : '${fmtInt(g.olderMeanS)} → ${fmtInt(g.newerMeanS)} 秒',
      caption: g == null
          ? '不到 8 场，看不出走势'
          : '${_signed(g.changePct)}% · ${_verdict(g)}（${_pText(g.p)}）',
      accent: accent,
    );
  }
}

class _LifeChart extends StatelessWidget {
  const _LifeChart({required this.samples});
  final List<LifeSample> samples;

  static String _two(int v) => v.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final lives = [for (final s in samples) s.lifeS];
    // Trailing average of the last [_window] matches (fewer at the start).
    final average = <double?>[
      for (var i = 0; i < lives.length; i++)
        _mean(lives.sublist((i - _window + 1).clamp(0, i), i + 1)),
    ];
    String date(LifeSample s) {
      final t = DateTime.fromMillisecondsSinceEpoch(s.startedAtMs ?? 0);
      return '${_two(t.month)}-${_two(t.day)}';
    }

    String note(LifeSample s) {
      final t = DateTime.fromMillisecondsSinceEpoch(s.startedAtMs ?? 0);
      return [
        '${_two(t.month)}-${_two(t.day)} ${_two(t.hour)}:${_two(t.minute)}',
        s.hero?.label ?? s.role.label,
        s.outcome.label,
        '阵亡 ${fmtInt(s.deaths)} 次 · 时长 ${fmtClock(s.durationS)}',
      ].join(' · ');
    }

    final last = lives.last;
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
        height: 280,
        yMin: 0,
        series: [
          ChartSeries(label: '每局', color: c.textSecondary, values: lives),
          ChartSeries(
            label: '最近 $_window 局平均',
            color: c.accent,
            values: average,
          ),
        ],
        xLabels: [for (final s in samples) date(s)],
        pointNotes: [for (final s in samples) note(s)],
        hollow: [for (final s in samples) s.outcome == Outcome.loss],
        hollowMeaning: '实心点：胜或平；空心点：负。',
        valueFormat: (v) => '${fmtInt(v)} 秒',
        summary:
            '${samples.length} 场的每局存活时长，最近一局 ${fmtInt(last)} 秒，'
            '最近 $_window 局平均 ${fmtInt(average.last)} 秒。',
      ),
    );
  }
}
