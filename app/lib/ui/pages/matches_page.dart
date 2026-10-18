import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/support.dart';
import '../../design/card_list.dart';
import '../../design/icons.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';
import '../../state/app_state.dart';
import '../../state/match_view.dart';
import '../player_view.dart';
import '../shell.dart' show ShellScope;
import 'match_detail_page.dart';
import '../../design/net_pic.dart';

/// Height of one match row. Tall on purpose: the row is a picture the player
/// recognises, with room to breathe, not a line of numbers.
const _rowExtent = 84.0;

class MatchesPage extends StatelessWidget {
  const MatchesPage({super.key, required this.workspace});
  final PlayerWorkspace workspace;

  @override
  Widget build(BuildContext context) {
    // A match opened in another queue stays remembered but is not shown here.
    final app = AppScope.of(context);
    if (workspace.openMatchId != null &&
        (workspace.openMatchMode ?? app.mode) == app.mode) {
      return MatchDetailPage(
        workspace: workspace,
        key: ValueKey(workspace.openMatchId),
      );
    }
    return _MatchList(workspace: workspace);
  }
}

class _MatchList extends StatefulWidget {
  const _MatchList({required this.workspace});
  final PlayerWorkspace workspace;
  @override
  State<_MatchList> createState() => _MatchListState();
}

class _MatchListState extends State<_MatchList> {
  final _query = TextEditingController();

  @override
  void initState() {
    super.initState();
    final app = AppScope.read(context);
    _query.text = widget.workspace.filtersFor(app.mode).query;
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _clear(PlayerWorkspace ws, MatchFilters filters) {
    filters.clear();
    _query.clear();
    ws.touch();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final ws = widget.workspace;
    final mode = app.mode;
    final load = ws.matchesFor(mode);
    final filters = ws.filtersFor(mode);
    final data = load.value;

    if (load.failedWithoutData) {
      return ErrorPanel(
        what: '无法读取${mode.label}的对局',
        error: load.error!,
        onRetry: () => ws.loadMatches(mode, fresh: true),
        extra: [
          if (load.error!.isAuth)
            AppButton('打开设置', onPressed: () => app.showSettings(true)),
        ],
      );
    }

    final all = data?.matches ?? const <MatchSummary>[];
    // The list is a recognition surface ordered by time; only the direction can change.
    final visible = sorted(
      all.where(filters.accepts).toList(),
      'time',
      ws.sortAscending,
    );
    final coverage = data?.coverage.matchLists
        .where((l) => l.mode == mode)
        .firstOrNull;
    final catalog = app.catalog;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FilterBar(
          workspace: ws,
          mode: mode,
          all: all,
          queryController: _query,
        ),
        const SizedBox(height: Sp.withinGroup),
        _ScopeLine(
          all: all,
          filters: filters,
          workspace: ws,
          mode: mode,
          coverage: coverage,
          load: load,
          onClear: () => _clear(ws, filters),
        ),
        const SizedBox(height: Sp.withinGroup),
        Expanded(
          child: CardList<MatchSummary>(
            listLabel: '${mode.label}对局列表',
            itemExtent: _rowExtent,
            rows: visible,
            loading: load.firstLoad,
            controller: ws.scroll,
            activeIndex: ws.activeMatchId == null
                ? -1
                : visible.indexWhere((m) => m.id == ws.activeMatchId),
            onActiveChanged: (i) => ws.activeMatchId = visible[i].id,
            rowLabel: _rowLabel,
            onOpen: (m, i) =>
                ws.openMatch(mode, m.id, [for (final r in visible) r.id]),
            builder: (context, m, state) =>
                _MatchCard(match: m, catalog: catalog, state: state),
            empty: load.loading
                ? const AfterDelay(child: SizedBox.shrink())
                : _emptyState(app, ws, mode, all.isEmpty, filters),
          ),
        ),
      ],
    );
  }

  Widget _emptyState(
    AppState app,
    PlayerWorkspace ws,
    Mode mode,
    bool noData,
    MatchFilters filters,
  ) {
    if (noData) {
      return EmptyState(
        icon: Icons.sports_esports_outlined,
        title: '${ws.name} 在${mode.label}没有对局记录',
        body: '该模式没有打过，或资料为私密。可换个模式。',
        actions: [
          for (final m in Mode.values.where((m) => m != mode))
            AppButton('切换到${m.label}', onPressed: () => app.setMode(m)),
        ],
      );
    }
    final parts = <String>[
      if (filters.outcomes.isNotEmpty)
        '结果：${filters.outcomes.map((o) => o.label).join('、')}',
      if (filters.role != null) '职责：${filters.role!.label}',
      if (filters.heroGuid != null) '英雄',
      if (filters.mapGuid != null) '地图',
      if (filters.query.trim().isNotEmpty) '搜索“${filters.query.trim()}”',
    ];
    return EmptyState(
      icon: Icons.filter_alt_off_outlined,
      title: '没有符合筛选的对局',
      body:
          '已读取的 ${ws.matchesFor(mode).value?.matches.length ?? 0} 场对局中，没有满足：${parts.join('，')}。',
      actions: [
        AppButton('清除筛选', primary: true, onPressed: () => _clear(ws, filters)),
      ],
    );
  }

  static String _rowLabel(MatchSummary m) =>
      '${m.outcome.label}，比分${fmtScore(m.scoreTeam, m.scoreOpponent)}，${m.map?.label ?? '未知地图'}，${m.hero?.label ?? '未知英雄'}，${fmtDateTime(m.startedAtMs)}';
}

/// One match, recognisable at a glance: the map is the background and fades out toward
/// the right, the score is the largest thing on the row, and the hero's head sits flush
/// at the right end: its right edge is the row's edge. A hard vertical bar on the left
/// carries the result. Everything numeric beyond the score lives on the detail page.
class _MatchCard extends StatelessWidget {
  const _MatchCard({
    required this.match,
    required this.catalog,
    required this.state,
  });
  final MatchSummary match;
  final Catalog catalog;
  final CardState state;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final m = match;
    final outcome = c.outcome(m.outcome.id);
    final role = m.role != Role.unknown ? m.role : catalog.heroRole(m.hero);
    final mapMode = catalog.mapMode(m.map);
    final light = Theme.of(context).brightness == Brightness.light;
    final mapUrl = catalog.mapImage(m.map);
    final overlay = state.active
        ? c.selected
        : (state.hovered ? c.hover : null);

    return LayoutBuilder(
      builder: (context, box) {
        // The head is a square the height of the row.
        final side = box.maxHeight;
        return Container(
          // Sharp rectangle: no rounding. Only selection and keyboard focus draw an outline.
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
                // 1. Map art with a scrim for the text, faded to fully transparent at the right edge.
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
                        if (mapUrl != null)
                          ExcludeSemantics(
                            child: NetPic(
                              mapUrl,
                              fit: BoxFit.cover,
                              alignment: const Alignment(0, -0.15),
                              placeholder: const SizedBox.expand(
                                child: Skeleton(radius: 0),
                              ),
                            ),
                          ),
                        // Scrim: dense on the left for text, thinning to the right.
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                c.raised.withValues(alpha: light ? 0.88 : 0.94),
                                c.raised.withValues(alpha: light ? 0.50 : 0.70),
                                c.raised.withValues(alpha: light ? 0.08 : 0.25),
                              ],
                              stops: const [0, 0.5, 1],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // 2. Hero head: a plain square flush with the right edge.
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: side,
                  child: PortraitCell(catalog.heroPortrait(m.hero)),
                ),
                // 3. Selection / hover tint.
                if (overlay != null)
                  Positioned.fill(child: ColoredBox(color: overlay)),
                // 4. Content.
                Positioned.fill(
                  child: Row(
                    children: [
                      // The result: a hard vertical bar (colour) plus icon and word (shape and text).
                      Container(width: 4, color: outcome),
                      const SizedBox(width: Sp.betweenGroups),
                      SizedBox(
                        width: 44,
                        child: Center(
                          child: OutcomeMark(m.outcome, stacked: true),
                        ),
                      ),
                      const SizedBox(width: Sp.betweenGroups),
                      SizedBox(
                        width: 92,
                        child: Text(
                          fmtScore(
                            m.scoreTeam,
                            m.scoreOpponent,
                          ).replaceAll(':', ' : '),
                          style: Ty.num(Ty.figure),
                          maxLines: 1,
                        ),
                      ),
                      const SizedBox(width: Sp.betweenGroups),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              m.map?.label ?? '未知地图',
                              style: Ty.section,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Row(
                              children: [
                                if (ModeGlyph.has(mapMode)) ...[
                                  ModeGlyph(mapMode, size: 16),
                                  const SizedBox(width: 6),
                                ],
                                Flexible(
                                  child: Text(
                                    [
                                      fmtDateTime(m.startedAtMs),
                                      if (mapMode != null && mapMode.isNotEmpty)
                                        mapMode,
                                    ].join('  ·  '),
                                    style: Ty.num(
                                      Ty.meta,
                                    ).copyWith(color: c.textSecondary),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          RoleIcon(role, size: 22),
                          const SizedBox(width: 8),
                          Text(m.hero?.label ?? '未知英雄', style: Ty.title),
                        ],
                      ),
                      // Keeps the text clear of the head.
                      SizedBox(width: side + Sp.betweenGroups),
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

// ---- Filters ---------------------------------------------------------------------------

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.workspace,
    required this.mode,
    required this.all,
    required this.queryController,
  });
  final PlayerWorkspace workspace;
  final Mode mode;
  final List<MatchSummary> all;
  final TextEditingController queryController;

  @override
  Widget build(BuildContext context) {
    final f = workspace.filtersFor(mode);
    final scope = ShellScope.of(context);
    void change(void Function() fn) {
      fn();
      workspace.touch();
    }

    final roleCounts = facetCounts(all, f, 'role');
    final heroCounts = facetCounts(all, f, 'hero');
    final mapCounts = facetCounts(all, f, 'map');
    final heroes = <String, String>{};
    final maps = <String, String>{};
    for (final m in all) {
      if (m.hero != null) heroes[m.hero!.guid] = m.hero!.label;
      if (m.map != null) maps[m.map!.guid] = m.map!.label;
    }
    List<_FacetOption> options(
      Map<String, String> names,
      Map<String, int> counts,
    ) {
      final out = [
        for (final e in names.entries)
          _FacetOption(e.key, e.value, counts[e.key] ?? 0),
      ];
      out.sort(
        (a, b) => b.count != a.count
            ? b.count.compareTo(a.count)
            : a.label.compareTo(b.label),
      );
      return out;
    }

    return Wrap(
      spacing: Sp.withinGroup,
      runSpacing: Sp.withinGroup,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 220,
          child: Semantics(
            textField: true,
            label: '筛选对局，匹配英雄、地图、职责与结果',
            child: TextField(
              controller: queryController,
              focusNode: scope.filterFocus,
              onChanged: (v) => change(() => f.query = v),
              decoration: InputDecoration(
                hintText: '搜索英雄、地图  Ctrl+F',
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: f.query.isEmpty
                    ? null
                    : IconAction(
                        icon: Icons.close,
                        label: '清除搜索',
                        onPressed: () {
                          queryController.clear();
                          change(() => f.query = '');
                        },
                      ),
              ),
            ),
          ),
        ),
        for (final o in [Outcome.win, Outcome.loss, Outcome.draw])
          _ToggleChip(
            leading: OutcomeMark(o, textless: true),
            name: o.label,
            selected: f.outcomes.contains(o),
            count: all.where((m) => m.outcome == o).length,
            onTap: () => change(
              () => f.outcomes.contains(o)
                  ? f.outcomes.remove(o)
                  : f.outcomes.add(o),
            ),
          ),
        // Roles are the game's own glyphs; the legend sits on the tooltip.
        for (final r in Role.playable)
          _ToggleChip(
            leading: RoleIcon(r, size: 16, tooltip: false),
            name: r.label,
            selected: f.role == r,
            count: roleCounts[r.id] ?? 0,
            onTap: () => change(() => f.role = f.role == r ? null : r),
            tip: '${r.label}（$roleLegend）',
          ),
        _FacetMenu(
          title: '英雄',
          icon: Icons.person_outline,
          value: f.heroGuid == null ? null : heroes[f.heroGuid],
          options: options(heroes, heroCounts),
          onSelect: (id) => change(() => f.heroGuid = id),
        ),
        _FacetMenu(
          title: '地图',
          icon: Icons.map_outlined,
          value: f.mapGuid == null ? null : maps[f.mapGuid],
          options: options(maps, mapCounts),
          onSelect: (id) => change(() => f.mapGuid = id),
        ),
      ],
    );
  }
}

class _FacetOption {
  const _FacetOption(this.id, this.label, this.count);
  final String id, label;
  final int count;
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({
    required this.leading,
    required this.name,
    required this.selected,
    required this.count,
    required this.onTap,
    this.tip,
  });
  final Widget leading;
  final String name;
  final bool selected;
  final int count;
  final VoidCallback onTap;
  final String? tip;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final chip = Semantics(
      button: true,
      toggled: selected,
      label: '$name，$count 场',
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.control),
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected ? c.selected : null,
            borderRadius: BorderRadius.circular(Radii.control),
            border: Border.all(color: selected ? c.accent : c.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              leading,
              const SizedBox(width: 6),
              Text(
                '$count',
                style: Ty.num(Ty.body).copyWith(
                  color: selected ? c.textPrimary : c.textSecondary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Tooltip(message: tip ?? name, child: chip);
  }
}

class _FacetMenu extends StatelessWidget {
  const _FacetMenu({
    required this.title,
    required this.icon,
    required this.value,
    required this.options,
    required this.onSelect,
  });
  final String title;
  final IconData icon;
  final String? value;
  final List<_FacetOption> options;
  final ValueChanged<String?> onSelect;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          onPressed: () => onSelect(null),
          child: Text('全部$title'),
        ),
        for (final o in options)
          Tooltip(
            message: o.count == 0 ? '在其他筛选条件下没有对局' : '',
            child: MenuItemButton(
              onPressed: o.count == 0 ? null : () => onSelect(o.id),
              trailingIcon: Text(
                '${o.count}',
                style: Ty.num(Ty.meta).copyWith(color: c.textSecondary),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 120),
                child: Text(o.label),
              ),
            ),
          ),
      ],
      builder: (context, controller, _) => OutlinedButton(
        style: buttonStyle(context).copyWith(
          minimumSize: const WidgetStatePropertyAll(Size(0, 34)),
          side: WidgetStateProperty.resolveWith(
            (s) => BorderSide(
              color: s.contains(WidgetState.focused)
                  ? c.accent
                  : (value != null ? c.accent : c.border),
              width: s.contains(WidgetState.focused) ? 2 : 1,
            ),
          ),
          backgroundColor: WidgetStatePropertyAll(
            value != null ? c.selected : null,
          ),
        ),
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 6),
            Text(value ?? title),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
    );
  }
}

/// Count, record, how much history was read, and when. Wording is kept for problems
/// (history not fully read, a refresh that failed); the rest is icons with tooltips.
class _ScopeLine extends StatelessWidget {
  const _ScopeLine({
    required this.all,
    required this.filters,
    required this.workspace,
    required this.mode,
    required this.coverage,
    required this.load,
    required this.onClear,
  });
  final List<MatchSummary> all;
  final MatchFilters filters;
  final PlayerWorkspace workspace;
  final Mode mode;
  final ListCoverage? coverage;
  final Load<PlayerDataset> load;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final ws = workspace;
    void change(void Function() fn) {
      fn();
      ws.touch();
    }

    final rows = all.where(filters.accepts).toList();
    final a = Agg(rows);
    final decided = a.wins + a.losses;
    final secondary = Ty.num(Ty.body).copyWith(color: c.textSecondary);
    Widget record(IconData icon, Color color, int n, String name) => Tooltip(
      message: '$name $n 场',
      child: Semantics(
        label: '$name $n 场',
        excludeSemantics: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 2),
            Text('$n', style: Ty.num(Ty.bodyStrong)),
          ],
        ),
      ),
    );

    return Wrap(
      spacing: Sp.betweenGroups,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          filters.active
              ? '${rows.length} / ${all.length} 场'
              : '${all.length} 场',
          style: Ty.num(Ty.bodyStrong),
        ),
        if (all.isNotEmpty) ...[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              record(Icons.check_rounded, c.win, a.wins, '胜'),
              const SizedBox(width: 10),
              record(Icons.close_rounded, c.loss, a.losses, '负'),
              const SizedBox(width: 10),
              record(Icons.remove_rounded, c.draw, a.draws, '平'),
            ],
          ),
          Tooltip(
            message: '胜 ÷ （胜 + 负），共 $decided 场；平局、未知不计。',
            child: Text(
              '胜率 ${a.winRatePct == null ? missing : fmtPct(a.winRatePct)}',
              style: secondary,
            ),
          ),
        ],
        for (final o in filters.outcomes)
          FilterTag(
            label: '结果：${o.label}',
            onRemove: () => change(() => filters.outcomes.remove(o)),
          ),
        if (filters.role != null)
          FilterTag(
            label: '职责：${filters.role!.label}',
            onRemove: () => change(() => filters.role = null),
          ),
        if (filters.heroGuid != null)
          FilterTag(
            label: '英雄',
            onRemove: () => change(() => filters.heroGuid = null),
          ),
        if (filters.mapGuid != null)
          FilterTag(
            label: '地图',
            onRemove: () => change(() => filters.mapGuid = null),
          ),
        if (filters.query.trim().isNotEmpty)
          FilterTag(
            label: '搜索：${filters.query.trim()}',
            onRemove: () => change(() => filters.query = ''),
          ),
        if (filters.active) AppButton('清除筛选', quiet: true, onPressed: onClear),
        if (coverage != null)
          if (coverage!.exhausted)
            Tooltip(
              message:
                  '本地已保存全部对局（${coverage!.totalMatches} 场）。'
                  '每次打开只读取比已保存的最新一场更新的对局。',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.done_all, size: 15, color: c.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    coverage!.newMatches > 0
                        ? '已读完，新增 ${coverage!.newMatches} 场'
                        : '已读完',
                    style: secondary,
                  ),
                ],
              ),
            )
          else if (load.loading)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(
                  dimension: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: c.accent,
                  ),
                ),
                const SizedBox(width: 6),
                Text('正在读取更早的对局…', style: secondary),
              ],
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Tooltip(
                  message: '还有更早的对局没有读取',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 15,
                        color: c.warning,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '未读完',
                        style: Ty.num(Ty.body).copyWith(color: c.warning),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                AppButton(
                  '继续读取',
                  quiet: true,
                  icon: Icons.add,
                  onPressed: () => ws.loadMatches(mode),
                  tooltip: '读取全部更早的对局',
                ),
              ],
            ),
        if (ws.prepareRemaining[mode] != null)
          Tooltip(
            message: '正在后台查询新对局里玩家的段位，之后分析对局强度时就不用再等了。',
            child: Text(
              '正在准备对局数据，还剩 ${ws.prepareRemaining[mode]} 场…',
              style: secondary,
            ),
          ),
        LoadStatusBar(
          compact: true,
          at: load.at ?? load.value?.generatedAt,
          loading: load.loading && load.has,
          error: load.error?.message,
          onRetry: () => ws.loadMatches(mode, fresh: true),
        ),
        IconAction(
          icon: ws.sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
          label: ws.sortAscending ? '时间顺序：最早在前，点击改为最新在前' : '时间顺序：最新在前，点击改为最早在前',
          onPressed: () => change(() => ws.sortAscending = !ws.sortAscending),
        ),
        const InfoTip('筛选与排序只作用于已读取的对局。点击一行（或按 Enter）打开这一局的详细数据。'),
      ],
    );
  }
}
