import 'package:flutter/material.dart';

import '../../core/metric_doc.dart';
import '../../core/hero_stats.dart';
import '../../core/models.dart';
import '../../core/support.dart';
import '../../design/card_list.dart';
import '../../design/icons.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';
import '../../core/stats.dart';
import '../../state/app_state.dart';
import '../player_view.dart';
import 'hero_compare.dart';
import 'hero_detail_page.dart';
import '../../l10n/strings.dart';

const _rowExtent = 84.0;

/// What the list can be ordered by, and the label of the figure it then highlights.
final _sorts = [
  ('matches', tr.heroes.matchesLabel),
  ('win', tr.heroes.winRateLabel),
  ('time', tr.heroes.sortTime),
  ('level', tr.heroes.proficiency),
  ('kills', tr.heroes.sortKills),
  ('damage', tr.heroes.sortDamage),
  ('healing', tr.heroes.sortHealing),
  ('mitigation', tr.heroes.sortMitigation),
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
  final _queryController = TextEditingController();

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  void _clearQuery() {
    _queryController.clear();
    setState(() => _query = '');
  }

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
    // Ordered by what the record says the rate is at least (Wilson lower bound), so 2 of
    // 2 does not outrank 30 of 50; the row still shows the rate itself.
    'win' => wilsonPct(h.wins ?? 0, h.matches ?? 0)?.$1,
    'time' => h.playTimeS,
    'level' => h.heroLevel?.toDouble(),
    'kills' => _kills(h),
    'damage' => _damage(h),
    'healing' => _healing(h),
    'mitigation' => _mitigation(h),
    _ => null,
  };

  @override
  Widget build(BuildContext context) => FadeThrough(
    // List ↔ a hero's page, and one hero to the next, fade through.
    childKey:
        '${widget.workspace.openHeroKey ?? ''}|${widget.workspace.comparingHero}',
    child: Builder(builder: _content),
  );

  Widget _content(BuildContext context) {
    final app = AppScope.of(context);
    final ws = widget.workspace;
    final mode = app.mode;
    final load = ws.matchesFor(mode);
    final career = load.value?.career(mode);
    final c = context.c;

    if (load.failedWithoutData) {
      return ErrorPanel(
        what: tr.heroes.loadFailed(mode.label),
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
    if (opened != null && ws.comparingHero) {
      final key = ws.compareHeroKey;
      return HeroComparePage(
        key: ValueKey('compare|$openKey|$key'),
        workspace: ws,
        a: opened,
        b: key == null
            ? null
            : all.where((h) => PlayerWorkspace.heroKey(h) == key).firstOrNull,
        all: all,
      );
    }
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
                controller: _queryController,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: tr.heroes.searchHint,
                  prefixIcon: const Icon(Icons.search, size: 18),
                ),
              ),
            ),
            Text(
              _query.trim().isEmpty
                  ? tr.heroes.heroCount(all.length)
                  : tr.heroes.heroCountFiltered(rows.length, all.length),
              style: Ty.num(Ty.bodyStrong),
            ),
            if (_query.trim().isNotEmpty)
              AppButton(
                tr.heroes.clearSearch,
                quiet: true,
                onPressed: _clearQuery,
              ),
            Text(
              tr.heroes.seasonTotal(season),
              style: Ty.body.copyWith(color: c.textSecondary),
            ),
            LoadStatusBar(
              compact: true,
              at: load.at,
              loading: load.loading && load.has,
              error: load.error?.message,
              onRetry: () => ws.loadMatches(mode, fresh: true),
            ),
            InfoTip(tr.heroes.listInfo, doc: MetricDoc.winRateRange),
          ],
        ),
        const SizedBox(height: Sp.withinGroup),
        Wrap(
          spacing: Sp.withinGroup,
          runSpacing: Sp.withinGroup,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              tr.heroes.sortBy,
              style: Ty.body.copyWith(color: c.textSecondary),
            ),
            SegmentedBar<String>(
              semanticLabel: tr.heroes.sortBasis,
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
                      'mitigation' => tr.heroes.per10Hint(label),
                      _ => null,
                    },
                  ),
              ],
            ),
            IconAction(
              icon: _asc ? Icons.arrow_upward : Icons.arrow_downward,
              label: _asc
                  ? tr.heroes.sortAscending(sortLabel)
                  : tr.heroes.sortDescending(sortLabel),
              onPressed: () => setState(() => _asc = !_asc),
            ),
          ],
        ),
        const SizedBox(height: Sp.withinGroup),
        Expanded(
          child: CardList<HeroUsage>(
            listLabel: tr.heroes.listLabel(mode.label),
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
            rowLabel: (h) => tr.heroes.heroRowLabel(
              h.hero.label,
              _cat.heroRole(h.hero).label,
              fmtInt(h.matches),
              fmtPct(h.winRatePct),
              fmtPlayTime(h.playTimeS),
            ),
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
                    title: tr.heroes.noHeroesTitle(season, mode.label),
                    body: tr.heroes.noHeroesBody,
                    actions: [
                      for (final m in Mode.values.where((m) => m != mode))
                        AppButton(
                          tr.heroes.switchTo(m.label),
                          onPressed: () => app.setMode(m),
                        ),
                    ],
                  )
                : EmptyState(
                    icon: Icons.search_off,
                    title: tr.heroes.noSearchMatchTitle(_query.trim()),
                    body: tr.heroes.noSearchMatchBody(all.length),
                    actions: [
                      AppButton(
                        tr.heroes.clearSearch,
                        primary: true,
                        onPressed: _clearQuery,
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
    return minutes < 60 ? tr.heroes.minutes(minutes) : fmtPlayTime(seconds);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final h = hero;
    final role = catalog.heroRole(h.hero);
    final banner = catalog.heroBanner(h.hero);
    final subKey = heroSubroles[h.hero.name];
    final subName = subKey == null
        ? null
        : subroleNames[subKey]!.split(' ').first;
    final enough = (h.matches ?? 0) >= AppScope.of(context).minGroupMatches;
    final bar = h.winRatePct == null || !enough
        ? c.textSecondary.withValues(alpha: Alpha.muted)
        : (h.winRatePct! >= 50 ? c.win : c.loss);

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

    // The hero's banner, dense behind the text and faded out to the right.
    return ArtRow(
      state: state,
      art: banner,
      artAlignment: const Alignment(0.2, -0.2),
      content: (side) => Row(
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
                const SizedBox(height: Sp.withinControl),
                Row(
                  children: [
                    RoleIcon(role, size: 18),
                    const SizedBox(width: Sp.withinGroup),
                    SubroleIcon(h.hero.name, size: 18),
                    if (subName != null) ...[
                      const SizedBox(width: Sp.iconGap),
                      Text(
                        subName,
                        style: Ty.meta.copyWith(color: c.textSecondary),
                      ),
                    ],
                    if (h.queue.label.isNotEmpty) ...[
                      const SizedBox(width: Sp.betweenItems),
                      Text(
                        h.queue.label,
                        style: Ty.meta.copyWith(color: c.textSecondary),
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
          metric(tr.heroes.matchesLabel, fmtInt(h.matches), width: 76),
          metric(
            tr.heroes.winRateLabel,
            fmtPct(h.winRatePct),
            width: 96,
            color: enough ? null : c.textSecondary,
            tip: enough ? _rangeTip(h) : tr.heroes.smallSample(h.matches ?? 0),
          ),
          metric(tr.heroes.playTimeLabel, _time(h.playTimeS), width: 108),
          if (extraSort)
            metric(
              tr.heroes.per10Metric(sortLabel),
              sortValue == null ? missing : fmtInt(sortValue),
              width: 116,
              color: extraColor,
              tip: sortValue == null ? tr.heroes.cannotProduce : null,
            ),
          const SizedBox(width: Sp.betweenGroups),
        ],
      ),
    );
  }
}

/// The plausible range of a hero's win rate, for the figure's tooltip.
String? _rangeTip(HeroUsage h) {
  final r = wilsonPct(h.wins ?? 0, h.matches ?? 0);
  return r == null
      ? null
      : tr.heroes.winRateRange(
          fmtPct(r.$1),
          fmtPct(r.$2),
          h.wins ?? 0,
          h.matches!,
        );
}
