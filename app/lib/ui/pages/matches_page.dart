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
import '../../l10n/strings.dart';
import 'match_detail_page.dart';

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
    final open =
        workspace.openMatchId != null &&
        (workspace.openMatchMode ?? app.mode) == app.mode;
    // List ↔ detail, and one match's detail to the next, fade through; the list keeps
    // its scroll position (the workspace holds it) for the way back.
    return FadeThrough(
      childKey: open ? workspace.openMatchId! : '',
      child: open
          ? MatchDetailPage(
              workspace: workspace,
              key: ValueKey(workspace.openMatchId),
            )
          : _MatchList(workspace: workspace),
    );
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
        what: tr.matches.cannotReadMatches(mode.label),
        error: load.error!,
        onRetry: () => ws.loadMatches(mode, fresh: true),
        extra: [
          if (load.error!.isAuth)
            AppButton(
              tr.common.openSettings,
              onPressed: () => app.showSettings(true),
            ),
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
            listLabel: tr.matches.listLabel(mode.label),
            itemExtent: _rowExtent,
            rows: visible,
            loading: load.firstLoad,
            controller: ws.scroll,
            activeIndex: ws.activeMatchId == null
                ? -1
                : visible.indexWhere((m) => m.id == ws.activeMatchId),
            onActiveChanged: (i) => ws.activeMatchId = visible[i].id,
            rowLabel: _rowLabel,
            rowKey: (m) => m.id,
            onOpen: (m, i) =>
                ws.openMatch(mode, m.id, [for (final r in visible) r.id]),
            builder: (context, m, state) => _MatchCard(
              match: m,
              catalog: catalog,
              state: state,
              party: ws.peopleFor(mode).value?.partySize[m.id],
            ),
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
        title: tr.matches.noRecord(ws.name, mode.label),
        body: tr.matches.noRecordBody,
        actions: [
          for (final m in Mode.values.where((m) => m != mode))
            AppButton(
              tr.matches.switchToMode(m.label),
              onPressed: () => app.setMode(m),
            ),
        ],
      );
    }
    final parts = <String>[
      if (filters.outcomes.isNotEmpty)
        tr.matches.filterOutcome(
          tr.common.list(filters.outcomes.map((o) => o.label)),
        ),
      if (filters.role != null) tr.matches.filterRole(filters.role!.label),
      if (filters.heroGuid != null) tr.matches.filterHero,
      if (filters.mapGuid != null) tr.matches.filterMap,
      if (filters.query.trim().isNotEmpty)
        tr.matches.filterSearchQuoted(filters.query.trim()),
    ];
    return EmptyState(
      icon: Icons.filter_alt_off_outlined,
      title: tr.matches.noMatchingMatches,
      body: tr.matches.noMatchingBody(
        ws.matchesFor(mode).value?.matches.length ?? 0,
        tr.matches.conditions(parts),
      ),
      actions: [
        AppButton(
          tr.common.clearFilters,
          primary: true,
          onPressed: () => _clear(ws, filters),
        ),
      ],
    );
  }

  static String _rowLabel(MatchSummary m) => tr.matches.rowLabel(
    m.outcome.label,
    fmtScore(m.scoreTeam, m.scoreOpponent),
    m.map?.label ?? tr.common.unknownMap,
    m.hero?.label ?? tr.common.unknownHero,
    fmtDateTime(m.startedAtMs),
  );
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
    this.party,
  });
  final MatchSummary match;

  /// Group size, where the match's detail is stored (1 = alone).
  final int? party;
  final Catalog catalog;
  final CardState state;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final m = match;
    final outcome = c.outcome(m.outcome.id);
    final role = m.role != Role.unknown ? m.role : catalog.heroRole(m.hero);
    final mapMode = catalog.mapMode(m.map);

    return ArtRow(
      state: state,
      art: catalog.mapImage(m.map),
      artAlignment: const Alignment(0, -0.15),
      // The hero's head: a plain square flush with the right edge.
      layers: (side) => [
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          width: side,
          child: PortraitCell(catalog.heroPortrait(m.hero)),
        ),
      ],
      content: (side) => Row(
        children: [
          // The result: a hard vertical bar (colour) plus icon and word (shape and text).
          Container(width: 4, color: outcome),
          const SizedBox(width: Sp.betweenGroups),
          SizedBox(
            width: 44,
            child: Center(child: OutcomeMark(m.outcome, stacked: true)),
          ),
          const SizedBox(width: Sp.betweenGroups),
          SizedBox(
            width: 92,
            child: Text(
              fmtScore(m.scoreTeam, m.scoreOpponent).replaceAll(':', ' : '),
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
                  m.map?.label ?? tr.common.unknownMap,
                  style: Ty.section,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  children: [
                    if (ModeGlyph.has(mapMode)) ...[
                      ModeGlyph(mapMode, size: 16),
                      const SizedBox(width: Sp.iconGap),
                    ],
                    Flexible(
                      child: Text(
                        [
                          fmtDateTime(m.startedAtMs),
                          if (mapMode != null && mapMode.isNotEmpty) mapMode,
                          if ((party ?? 1) > 1) tr.people.partyTag(party!),
                        ].join('  ·  '),
                        style: Ty.num(Ty.meta).copyWith(color: c.textSecondary),
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
              const SizedBox(width: Sp.withinGroup),
              Text(m.hero?.label ?? tr.common.unknownHero, style: Ty.title),
            ],
          ),
          // Keeps the text clear of the head.
          SizedBox(width: side + Sp.betweenGroups),
        ],
      ),
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
            label: tr.matches.searchLabel,
            child: TextField(
              controller: queryController,
              focusNode: scope.filterFocus,
              onChanged: (v) => change(() => f.query = v),
              decoration: InputDecoration(
                hintText: tr.matches.searchHint,
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: f.query.isEmpty
                    ? null
                    : IconAction(
                        icon: Icons.close,
                        label: tr.matches.clearSearch,
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
          title: tr.matches.filterHero,
          icon: Icons.person_outline,
          value: f.heroGuid == null ? null : heroes[f.heroGuid],
          options: options(heroes, heroCounts),
          onSelect: (id) => change(() => f.heroGuid = id),
        ),
        _FacetMenu(
          title: tr.matches.filterMap,
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
    return Pressable(
      onTap: onTap,
      selected: selected,
      toggle: true,
      outlineAtRest: true,
      semanticLabel: tr.matches.chipLabel(name, count),
      tooltip: tip ?? name,
      height: Ctl.regular,
      padding: const EdgeInsets.symmetric(horizontal: Sp.withinGroup),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          leading,
          const SizedBox(width: Sp.iconGap),
          Text(
            '$count',
            style: Ty.num(Ty.body).copyWith(
              color: selected ? c.textPrimary : c.textSecondary,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
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
          child: Text(tr.matches.facetAll(title)),
        ),
        for (final o in options)
          Tooltip(
            message: o.count == 0 ? tr.matches.facetOptionEmpty : '',
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
          minimumSize: const WidgetStatePropertyAll(Size(0, Ctl.regular)),
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
            const SizedBox(width: Sp.iconGap),
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
      message: tr.matches.recordCount(name, n),
      child: Semantics(
        label: tr.matches.recordCount(name, n),
        excludeSemantics: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: Sp.hairline),
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
              ? tr.matches.shownOfTotal(rows.length, all.length)
              : tr.common.matchCount(all.length),
          style: Ty.num(Ty.bodyStrong),
        ),
        if (all.isNotEmpty) ...[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              record(Icons.check_rounded, c.win, a.wins, Outcome.win.label),
              const SizedBox(width: Sp.withinGroup),
              record(Icons.close_rounded, c.loss, a.losses, Outcome.loss.label),
              const SizedBox(width: Sp.withinGroup),
              record(Icons.remove_rounded, c.draw, a.draws, Outcome.draw.label),
            ],
          ),
          Tooltip(
            message: tr.matches.winRateTip(decided),
            child: Text(
              tr.matches.winRate(
                a.winRatePct == null ? missing : fmtPct(a.winRatePct),
              ),
              style: secondary,
            ),
          ),
        ],
        for (final o in filters.outcomes)
          FilterTag(
            label: tr.matches.filterOutcome(o.label),
            onRemove: () => change(() => filters.outcomes.remove(o)),
          ),
        if (filters.role != null)
          FilterTag(
            label: tr.matches.filterRole(filters.role!.label),
            onRemove: () => change(() => filters.role = null),
          ),
        if (filters.heroGuid != null)
          FilterTag(
            label: tr.matches.filterHero,
            onRemove: () => change(() => filters.heroGuid = null),
          ),
        if (filters.mapGuid != null)
          FilterTag(
            label: tr.matches.filterMap,
            onRemove: () => change(() => filters.mapGuid = null),
          ),
        if (filters.query.trim().isNotEmpty)
          FilterTag(
            label: tr.matches.filterSearch(filters.query.trim()),
            onRemove: () => change(() => filters.query = ''),
          ),
        if (filters.active)
          AppButton(tr.common.clearFilters, quiet: true, onPressed: onClear),
        if (coverage != null)
          if (coverage!.exhausted)
            Tooltip(
              message: tr.matches.allSavedTip(coverage!.totalMatches),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.done_all, size: 15, color: c.textSecondary),
                  const SizedBox(width: Sp.withinControl),
                  Text(
                    coverage!.newMatches > 0
                        ? tr.matches.allReadWithNew(coverage!.newMatches)
                        : tr.matches.allRead,
                    style: secondary,
                  ),
                ],
              ),
            )
          else if (load.loading)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Spinner(color: c.accent),
                const SizedBox(width: Sp.iconGap),
                Text(
                  tr.matches.readingOlder(load.value?.matches.length ?? 0),
                  style: secondary,
                ),
              ],
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Tooltip(
                  message: tr.matches.olderUnreadTip,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 15,
                        color: c.warning,
                      ),
                      const SizedBox(width: Sp.withinControl),
                      Text(
                        tr.matches.notAllRead,
                        style: Ty.num(Ty.body).copyWith(color: c.warning),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Sp.withinControl),
                AppButton(
                  tr.matches.continueReading,
                  quiet: true,
                  icon: Icons.add,
                  onPressed: () => ws.loadMatches(mode),
                  tooltip: tr.matches.continueReadingTip,
                ),
              ],
            ),
        if (ws.prepareRemaining[mode] != null)
          Tooltip(
            message: tr.matches.preparingTip,
            child: Text(
              ws.preparePaused.contains(mode)
                  ? tr.matches.preparingPaused(ws.prepareRemaining[mode]!)
                  : tr.matches.preparing(ws.prepareRemaining[mode]!),
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
          label: ws.sortAscending
              ? tr.matches.sortOldestFirst
              : tr.matches.sortNewestFirst,
          onPressed: () => change(() => ws.sortAscending = !ws.sortAscending),
        ),
        InfoTip(tr.matches.listInfo),
      ],
    );
  }
}
