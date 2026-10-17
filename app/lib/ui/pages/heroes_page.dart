import 'package:flutter/material.dart';

import '../../core/hero_stats.dart';
import '../../core/models.dart';
import '../../core/support.dart';
import '../../design/card_list.dart';
import '../../design/icons.dart';
import '../../design/net_pic.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';
import '../../state/app_state.dart';
import '../player_view.dart';
import 'hero_detail_page.dart';

/// Win rates over fewer matches than this carry an annotation, not a colour.
const _minSample = 5;

const _rowExtent = 84.0;

/// What the list can be ordered by, and the label of the figure it then highlights.
const _sorts = [
  ('matches', '场次'),
  ('win', '胜率'),
  ('time', '时长'),
  ('level', '熟练度'),
  ('kills', '消灭'),
  ('damage', '伤害'),
  ('healing', '治疗'),
  ('mitigation', '阻挡'),
];

class HeroesPage extends StatefulWidget {
  const HeroesPage({super.key, required this.workspace});
  final PlayerWorkspace workspace;
  @override
  State<HeroesPage> createState() => _HeroesPageState();
}

class _HeroesPageState extends State<HeroesPage> {
  String _sort = 'matches';
  bool _asc = false;
  String _query = '';
  String? _activeKey;

  // Per-10-minute figures follow the rule in HeroStats: a number (0 included) where
  // the hero can produce the stat, a dash where it cannot.
  late Catalog _cat;
  Map<String, List<MatchSummary>> _recent = const {};
  List<MatchSummary> _of(HeroUsage h) => _recent[h.hero.guid] ?? const [];

  double? _kills(HeroUsage h) =>
      HeroStats.cell10(h, _cat, _of(h), (n) => n == '消灭');
  double? _damage(HeroUsage h) =>
      HeroStats.cell10(h, _cat, _of(h), (n) => n == '对英雄伤害量');
  // Self-healing is already folded into 治疗量 by HeroStats.rows.
  double? _healing(HeroUsage h) =>
      HeroStats.cell10(h, _cat, _of(h), (n) => n == '治疗量') ??
      // Hero-specific healing stats (a staff, an orb) also mean it can heal.
      HeroStats.cell10(
        h,
        _cat,
        _of(h),
        (n) => n.contains('治疗量') && !n.contains('承受') && !n.contains('阻碍'),
      );
  double? _mitigation(HeroUsage h) => HeroStats.mitigation10(h, _cat, _of(h));

  double? _valueOf(HeroUsage h, String sort) => switch (sort) {
    'matches' => h.matches?.toDouble(),
    'win' => h.winRatePct,
    'time' => h.playTimeS,
    'level' => h.heroLevel?.toDouble(),
    'kills' => _kills(h),
    'damage' => _damage(h),
    'healing' => _healing(h),
    'mitigation' => _mitigation(h),
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final ws = widget.workspace;
    final mode = app.mode;
    final load = ws.matchesFor(mode);
    final career = load.value?.career(mode);
    final c = context.c;

    if (load.failedWithoutData) {
      return ErrorPanel(
        what: '无法读取${mode.label}的英雄统计',
        error: load.error!,
        onRetry: () => ws.loadMatches(mode, fresh: true),
      );
    }
    _cat = app.catalog;
    _recent = {};
    for (final m in load.value?.matches ?? const <MatchSummary>[]) {
      final g = m.hero?.guid;
      if (g != null) (_recent[g] ??= []).add(m);
    }
    final all = career?.heroes ?? const <HeroUsage>[];
    // A hero opened from the list gets its own page.
    final openKey = ws.openHeroKey;
    final opened = openKey == null
        ? null
        : all.where((h) => PlayerWorkspace.heroKey(h) == openKey).firstOrNull;
    if (opened != null) {
      return HeroDetailPage(
        key: ValueKey(openKey),
        workspace: ws,
        hero: opened,
      );
    }

    final rows = all.where((h) => matchesQuery(h.hero.label, _query)).toList();
    rows.sort((a, b) {
      final va = _valueOf(a, _sort), vb = _valueOf(b, _sort);
      if (va == null && vb == null) return 0;
      if (va == null) return 1;
      if (vb == null) return -1;
      final r = _asc ? va.compareTo(vb) : vb.compareTo(va);
      return r != 0 ? r : (b.matches ?? 0).compareTo(a.matches ?? 0);
    });

    final season = career?.season ?? app.currentSeason;
    final sortLabel = _sorts.firstWhere((s) => s.$1 == _sort).$2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: Sp.betweenGroups,
          runSpacing: Sp.withinGroup,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 220,
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(
                  hintText: '搜索英雄',
                  prefixIcon: Icon(Icons.search, size: 18),
                ),
              ),
            ),
            Text(
              _query.trim().isEmpty
                  ? '${all.length} 个英雄'
                  : '${rows.length} / ${all.length} 个英雄',
              style: Ty.num(Ty.bodyStrong),
            ),
            if (_query.trim().isNotEmpty)
              AppButton(
                '清除搜索',
                quiet: true,
                onPressed: () => setState(() => _query = ''),
              ),
            Text(
              '第 $season 赛季累计',
              style: Ty.body.copyWith(color: c.textSecondary),
            ),
            LoadStatusBar(
              compact: true,
              at: load.at,
              loading: load.loading && load.has,
              error: load.error?.message,
              onRetry: () => ws.loadMatches(mode, fresh: true),
            ),
            const InfoTip(
              '整个赛季的累计，来自大神，不是“对局”页读取的最近对局。点一个英雄看详情。消灭、伤害、治疗、阻挡为每 10 分钟；— 表示这个英雄无法产出。',
            ),
          ],
        ),
        const SizedBox(height: Sp.withinGroup),
        Wrap(
          spacing: Sp.withinGroup,
          runSpacing: Sp.withinGroup,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('排序', style: Ty.body.copyWith(color: c.textSecondary)),
            SegmentedBar<String>(
              semanticLabel: '排序依据',
              value: _sort,
              onChanged: (v) => setState(() {
                _sort = v;
                _asc = false;
              }),
              segments: [
                for (final (id, label) in _sorts)
                  Segment(
                    id,
                    label,
                    hint: switch (id) {
                      'kills' ||
                      'damage' ||
                      'healing' ||
                      'mitigation' => '$label，每 10 分钟',
                      _ => null,
                    },
                  ),
              ],
            ),
            IconAction(
              icon: _asc ? Icons.arrow_upward : Icons.arrow_downward,
              label: _asc ? '$sortLabel 从低到高' : '$sortLabel 从高到低',
              onPressed: () => setState(() => _asc = !_asc),
            ),
          ],
        ),
        const SizedBox(height: Sp.withinGroup),
        Expanded(
          child: CardList<HeroUsage>(
            listLabel: '${mode.label}英雄使用统计',
            itemExtent: _rowExtent,
            rows: rows,
            loading: load.firstLoad,
            activeIndex: _activeKey == null
                ? -1
                : rows.indexWhere(
                    (h) => PlayerWorkspace.heroKey(h) == _activeKey,
                  ),
            onActiveChanged: (i) =>
                _activeKey = PlayerWorkspace.heroKey(rows[i]),
            rowLabel: (h) =>
                '${h.hero.label}，${_cat.heroRole(h.hero).label}，${fmtInt(h.matches)} 场，胜率${fmtPct(h.winRatePct)}，使用${fmtPlayTime(h.playTimeS)}',
            onOpen: (h, _) => ws.openHero(h, rows),
            builder: (context, h, state) => _HeroCard(
              hero: h,
              catalog: app.catalog,
              state: state,
              sortId: _sort,
              sortLabel: sortLabel,
              sortValue: _valueOf(h, _sort),
            ),
            empty: load.loading
                ? const AfterDelay(child: SizedBox.shrink())
                : all.isEmpty
                ? EmptyState(
                    icon: Icons.groups_outlined,
                    title: '第 $season 赛季没有${mode.label}的英雄记录',
                    body: '该赛季没有打过这个模式，或资料为私密。可换个模式，或到“赛季走势”看往期。',
                    actions: [
                      for (final m in Mode.values.where((m) => m != mode))
                        AppButton(
                          '切换到${m.label}',
                          onPressed: () => app.setMode(m),
                        ),
                    ],
                  )
                : EmptyState(
                    icon: Icons.search_off,
                    title: '没有名称包含“${_query.trim()}”的英雄',
                    body: '已有 ${all.length} 个英雄记录。',
                    actions: [
                      AppButton(
                        '清除搜索',
                        primary: true,
                        onPressed: () => setState(() => _query = ''),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

/// One hero as a recognition row, like a match: the hero's banner behind, its face as
/// a square, name with role and subrole, then the few numbers that matter.
class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.hero,
    required this.catalog,
    required this.state,
    required this.sortId,
    required this.sortLabel,
    required this.sortValue,
  });
  final HeroUsage hero;
  final Catalog catalog;
  final CardState state;
  final String sortId, sortLabel;
  final double? sortValue;

  static String _time(double? seconds) {
    if (seconds == null) return missing;
    final minutes = (seconds / 60).round();
    return minutes < 60
        ? '$minutes 分钟'
        : '${(seconds / 3600).toStringAsFixed(1)} 小时';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final light = Theme.of(context).brightness == Brightness.light;
    final h = hero;
    final role = catalog.heroRole(h.hero);
    final banner = catalog.heroBanner(h.hero);
    final subKey = heroSubroles[h.hero.name];
    final subName = subKey == null
        ? null
        : subroleNames[subKey]!.split(' ').first;
    final enough = (h.matches ?? 0) >= _minSample;
    final bar = h.winRatePct == null || !enough
        ? c.textSecondary.withValues(alpha: 0.5)
        : (h.winRatePct! >= 50 ? c.win : c.loss);
    final overlay = state.active
        ? c.selected
        : (state.hovered ? c.hover : null);

    // The figure the list is currently ordered by, so the order is visible on the row.
    final extraSort = const {
      'kills',
      'damage',
      'healing',
      'mitigation',
    }.contains(sortId);
    final extraColor = switch (sortId) {
      'damage' => c.statDamage,
      'healing' => c.statHealing,
      'mitigation' => c.statMitigation,
      _ => null,
    };

    Widget metric(
      String label,
      String value, {
      double width = 92,
      Color? color,
      String? tip,
    }) {
      final body = SizedBox(
        width: width,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              value,
              maxLines: 1,
              style: Ty.num(Ty.figure).copyWith(color: color),
            ),
            Text(label, style: Ty.meta.copyWith(color: c.textSecondary)),
          ],
        ),
      );
      return tip == null ? body : Tooltip(message: tip, child: body);
    }

    return LayoutBuilder(
      builder: (context, box) {
        final side = box.maxHeight;
        return Container(
          decoration: BoxDecoration(
            border: state.ring
                ? Border.all(color: c.accent, width: 2)
                : state.active
                ? Border.all(color: c.accent.withValues(alpha: 0.7), width: 1)
                : null,
          ),
          child: ClipRect(
            child: Stack(
              children: [
                // The hero's banner, dense behind the text and faded out to the right.
                Positioned.fill(
                  child: ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (rect) => const LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Color(0xFF000000),
                        Color(0xB3000000),
                        Color(0x00000000),
                      ],
                      stops: [0, 0.55, 1],
                    ).createShader(rect),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(color: c.raised),
                        if (banner != null)
                          ExcludeSemantics(
                            child: NetPic(
                              banner,
                              fit: BoxFit.cover,
                              alignment: const Alignment(0.2, -0.2),
                              placeholder: const SizedBox.expand(
                                child: Skeleton(radius: 0),
                              ),
                            ),
                          ),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                c.raised.withValues(alpha: light ? 0.88 : 0.94),
                                c.raised.withValues(alpha: light ? 0.50 : 0.72),
                                c.raised.withValues(alpha: light ? 0.08 : 0.30),
                              ],
                              stops: const [0, 0.5, 1],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (overlay != null)
                  Positioned.fill(child: ColoredBox(color: overlay)),
                Positioned.fill(
                  child: Row(
                    children: [
                      // Win rate as a hard bar; grey while the sample is too small to judge.
                      Container(width: 4, color: bar),
                      // The hero's face, a plain square the height of the row.
                      SizedBox(
                        width: side,
                        child: PortraitCell(catalog.heroPortrait(h.hero)),
                      ),
                      const SizedBox(width: Sp.betweenGroups + 4),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              h.hero.label,
                              style: Ty.section,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                RoleIcon(role, size: 18),
                                const SizedBox(width: 8),
                                SubroleIcon(h.hero.name, size: 18),
                                if (subName != null) ...[
                                  const SizedBox(width: 6),
                                  Text(
                                    subName,
                                    style: Ty.meta.copyWith(
                                      color: c.textSecondary,
                                    ),
                                  ),
                                ],
                                if (h.queue.label.isNotEmpty) ...[
                                  const SizedBox(width: 12),
                                  Text(
                                    h.queue.label,
                                    style: Ty.meta.copyWith(
                                      color: c.textSecondary,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 78,
                        child: Center(child: LevelBadge(h.heroLevel, size: 28)),
                      ),
                      metric('场次', fmtInt(h.matches), width: 76),
                      metric(
                        '胜率',
                        fmtPct(h.winRatePct),
                        width: 96,
                        color: enough ? null : c.textSecondary,
                        tip: enough ? null : '只有 ${h.matches ?? 0} 场，样本太少，仅供参考',
                      ),
                      metric('使用时长', _time(h.playTimeS), width: 108),
                      if (extraSort)
                        metric(
                          '$sortLabel /10分',
                          sortValue == null ? missing : fmtInt(sortValue),
                          width: 116,
                          color: extraColor,
                          tip: sortValue == null ? '这个英雄无法产出这项数据' : null,
                        ),
                      const SizedBox(width: Sp.betweenGroups),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
