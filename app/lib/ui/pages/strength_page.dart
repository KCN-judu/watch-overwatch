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
import '../player_view.dart';

/// Minus sign U+2212 matches digit stroke weight and keeps columns aligned.
String _signed(double? v) {
  if (v == null) return missing;
  final r = v.round();
  if (r == 0) return '0';
  return r > 0 ? '+${fmtInt(r)}' : '−${fmtInt(-r)}';
}

String _slotName(Role? r) => r == null ? tr.analysis.overallSlot : r.label;

/// Role glyph, or the "everyone" glyph for the overall slot.
Widget _slotIcon(Role? r, {double size = 15, bool tooltip = false}) => r == null
    ? Icon(Icons.groups_2_outlined, size: size)
    : RoleIcon(r, size: size, tooltip: tooltip);

class StrengthPage extends StatefulWidget {
  const StrengthPage({super.key, required this.workspace});
  final PlayerWorkspace workspace;
  @override
  State<StrengthPage> createState() => _StrengthPageState();
}

class _StrengthPageState extends State<StrengthPage> {
  Role? _slot; // null = 综合
  bool _tiers = true;

  String _fmt(double? v) {
    if (v == null) return missing;
    return _tiers ? (ratingLabel(v) ?? missing) : fmtInt(v);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final ws = widget.workspace;
    final mode = app.mode;
    final load = ws.strengthFor(mode);
    final result = load.value;

    return ListView(
      padding: const EdgeInsets.only(right: 16),
      children: [
        Row(
          children: [
            SectionHeader(tr.analysis.strengthTitle),
            InfoTip(tr.analysis.strengthInfo(quick: mode == Mode.quick)),
          ],
        ),
        const SizedBox(height: Sp.withinGroup),
        _Controls(
          workspace: ws,
          mode: mode,
          load: load,
          tiers: _tiers,
          onTiers: (v) => setState(() => _tiers = v),
        ),
        const SizedBox(height: Sp.betweenGroups),
        if (load.failedWithoutData)
          SizedBox(
            height: 260,
            child: ErrorPanel(
              what: tr.analysis.strengthFailed,
              error: load.error!,
              onRetry: () => ws.runStrength(mode),
              extra: [
                if (load.error!.isAuth)
                  AppButton(
                    tr.common.openSettings,
                    onPressed: () => app.showSettings(true),
                  ),
              ],
            ),
          )
        else if (result == null && !load.loading)
          _Intro(workspace: ws, mode: mode)
        else if (result == null)
          _Running(workspace: ws, mode: mode)
        else
          ..._result(context, app, ws, mode, load, result),
      ],
    );
  }

  List<Widget> _result(
    BuildContext context,
    AppState app,
    PlayerWorkspace ws,
    Mode mode,
    Load<StrengthResult> load,
    StrengthResult r,
  ) {
    final c = context.c;
    final lobby = r.lobby;
    final n = ws.strengthCount(mode);
    // Matches nobody could be rated in stay in the chart and table as gaps; the counts
    // and averages are about the ones with data.
    final rated = lobby.matches.where((m) => m.hasData).toList();
    final totalPlayers = lobby.matches.fold<int>(
      0,
      (s, m) => s + m.ally.players + m.enemy.players,
    );
    final ratedPlayers = lobby.matches.fold<int>(
      0,
      (s, m) => s + m.ally.rated.overall + m.enemy.rated.overall,
    );
    final requested = r.dataset.coverage.detailsRequested;
    final read = r.dataset.coverage.detailsOk;
    final unrated = lobby.matches.length - rated.length;

    if (rated.isEmpty) {
      return [
        EmptyState(
          icon: Icons.analytics_outlined,
          title: tr.analysis.noRatedMatches,
          body: requested == 0
              ? tr.analysis.noMatchesRead(mode.label)
              : tr.analysis.noRatedPlayers(read, requested),
          actions: [
            AppButton(
              tr.analysis.reanalyse,
              primary: true,
              onPressed: load.loading
                  ? null
                  : () => ws.runStrength(mode, fresh: true),
            ),
          ],
        ),
      ];
    }

    final byMode = lobby.byMode.where((g) => g.mode == mode).firstOrNull;
    final groups = [
      ?byMode,
      ...lobby.bySubjectRole.where((g) => g.mode == mode),
    ];
    final chronological = lobby.matches.reversed
        .toList(); // oldest → newest for the chart
    final byId = {for (final m in r.dataset.matches) m.id: m};
    // Only the roles this analysis covered get a coverage count.
    final ranScope = ws.strengthRanScope[mode];
    final coveredRoles = ranScope == null ? Role.playable : [ranScope];
    final perRole = {
      for (final role in Role.playable)
        role: rated.where((m) => m.subjectRole == role).length,
    };

    return [
      Wrap(
        spacing: Sp.betweenGroups,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            tr.common.matchCount(rated.length),
            style: Ty.num(Ty.bodyStrong),
          ),
          if (unrated > 0)
            Tooltip(
              message: tr.analysis.unratedMatchesTip(unrated),
              child: Text(
                tr.analysis.unratedMatches(unrated),
                style: Ty.body.copyWith(color: c.warning),
              ),
            ),
          // Per-role coverage: the target is n each; a role with fewer is marked, not hidden.
          for (final role in coveredRoles)
            Tooltip(
              message: perRole[role]! >= n
                  ? tr.analysis.roleCoverageFull(role.label, n)
                  : tr.analysis.roleCoverageShort(
                      role.label,
                      perRole[role]!,
                      n,
                    ),
              child: Semantics(
                label: tr.analysis.roleCount(role.label, perRole[role]!),
                excludeSemantics: true,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RoleIcon(role, size: 16, tooltip: false),
                    const SizedBox(width: 6),
                    Text(
                      '${perRole[role]}/$n',
                      style: Ty.num(Ty.body).copyWith(
                        color: perRole[role]! >= n ? c.textPrimary : c.warning,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (perRole[role]! < n) ...[
                      const SizedBox(width: 3),
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 14,
                        color: c.warning,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          if (r.dataset.coverage.cacheHits > 0)
            Tooltip(
              message: tr.analysis.cacheHitsTip(r.dataset.coverage.cacheHits),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bolt, size: 15, color: c.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    tr.analysis.cacheHits(r.dataset.coverage.cacheHits),
                    style: Ty.num(Ty.body).copyWith(color: c.textSecondary),
                  ),
                ],
              ),
            ),
          Tooltip(
            message: tr.analysis.ratedOfAllTip,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.how_to_reg_outlined,
                  size: 15,
                  color: c.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  '$ratedPlayers / $totalPlayers',
                  style: Ty.num(Ty.body).copyWith(color: c.textSecondary),
                ),
              ],
            ),
          ),
          InfoTip(tr.analysis.unratedNote(hasUnratedMatches: unrated > 0)),
          LoadStatusBar(
            compact: true,
            at: load.at,
            loading: load.loading,
            error: load.error?.message,
            onRetry: () => ws.runStrength(mode, fresh: true),
          ),
        ],
      ),
      const SizedBox(height: Sp.betweenSections),
      Row(
        children: [
          SectionHeader(tr.analysis.byRoleTitle),
          InfoTip(tr.analysis.byRoleInfo),
        ],
      ),
      const SizedBox(height: Sp.withinGroup),
      SizedBox(
        height: _tableHeight(context, groups.length),
        child: _byRoleTable(context, groups),
      ),
      const SizedBox(height: Sp.betweenSections),
      _ChartSection(
        matches: chronological,
        role: _slot,
        perRole: perRole,
        tiers: _tiers,
        onRole: (r) => setState(() => _slot = r),
      ),
      const SizedBox(height: Sp.betweenSections),
      Row(
        children: [
          SectionHeader(tr.analysis.perMatchTitle),
          InfoTip(tr.analysis.perMatchInfo),
        ],
      ),
      const SizedBox(height: Sp.withinGroup),
      SizedBox(
        height: _tableHeight(context, math.min(lobby.matches.length, 12)),
        child: _perMatchTable(context, app, ws, mode, lobby, byId),
      ),
      const SizedBox(height: Sp.betweenSections),
    ];
  }

  double _tableHeight(BuildContext context, int rows) {
    final scale = math.max(
      1.0,
      MediaQuery.textScalerOf(context).scale(13) / 13,
    );
    return context.density.rowHeight * scale * (rows + 1) + 4;
  }

  Widget _teamHeader(BuildContext context, String text, Color color) => Text(
    text,
    style: Theme.of(context).textTheme.labelMedium!.copyWith(
      color: color,
      fontWeight: FontWeight.w600,
    ),
  );

  Widget _byRoleTable(BuildContext context, List<StrengthGroup> groups) {
    final c = context.c;
    Widget tipped(double? v, Widget child) => v == null
        ? child
        : Tooltip(
            message: tr.analysis.ratingTip(fmtInt(v), ratingLabel(v) ?? ''),
            child: child,
          );
    Col<StrengthGroup> side(
      String id,
      String label,
      Color color,
      RoleMeans Function(StrengthGroup) pick,
    ) => Col(
      id: id,
      label: label,
      headerChild: _teamHeader(context, label, color),
      tooltip: tr.analysis.sideMeanTip(label),
      width: 104,
      numeric: true,
      cell: (context, g) {
        final v = pick(g).slot(g.subjectRole);
        // In tier mode the badge carries its own tooltip (tier and rating).
        return _tiers ? _rankCell(context, v) : tipped(v, Text(_fmt(v)));
      },
    );
    return AppTable<StrengthGroup>(
      tableLabel: tr.analysis.byRoleTable,
      columns: [
        Col(
          id: 'role',
          label: tr.analysis.playedRole,
          width: 130,
          flex: true,
          cell: (_, g) => g.subjectRole == null
              ? Row(
                  children: [
                    const Icon(Icons.groups_2_outlined, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      tr.analysis.all,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                )
              : RoleIcon(g.subjectRole!, size: 18, showLabel: true),
        ),
        Col(
          id: 'n',
          label: tr.analysis.matchesColumn,
          width: 60,
          numeric: true,
          cell: (_, g) => Text('${g.matches}'),
        ),
        Col(
          id: 'wr',
          label: tr.analysis.winRate,
          width: 84,
          numeric: true,
          tooltip: tr.analysis.winRateTip,
          cell: (_, g) => Text(fmtPct(g.winRatePct)),
        ),
        side('ally', tr.common.ally, c.ally, (g) => g.ally),
        side('enemy', tr.common.enemy, c.enemy, (g) => g.enemy),
        Col(
          id: 'diff',
          label: tr.analysis.diff,
          width: 100,
          numeric: true,
          tooltip: tr.analysis.diffTip,
          cell: (_, g) {
            final d = g.diff.slot(g.subjectRole);
            return Text(
              d == null
                  ? missing
                  : '${d > 0
                        ? '▲'
                        : d < 0
                        ? '▼'
                        : ''} ${_signed(d)}',
            );
          },
        ),
        Col(
          id: 'lobby',
          label: tr.analysis.lobby,
          width: 92,
          numeric: true,
          tooltip: tr.analysis.lobbyTip,
          cell: (context, g) => _rankCell(context, g.lobby.slot(g.subjectRole)),
        ),
        Col(
          id: 'all',
          label: tr.analysis.overallDiff,
          width: 92,
          numeric: true,
          tooltip: tr.analysis.overallDiffTip,
          cell: (_, g) => Text(_signed(g.diff.overall)),
        ),
      ],
      rows: groups,
      rowLabel: (g) => tr.analysis.byRoleRow(
        role: g.subjectRole?.label ?? tr.analysis.all,
        matches: g.matches,
        winRate: fmtPct(g.winRatePct),
        ally: _fmt(g.ally.slot(g.subjectRole)),
        enemy: _fmt(g.enemy.slot(g.subjectRole)),
        diff: _signed(g.diff.slot(g.subjectRole)),
      ),
    );
  }

  Widget _perMatchTable(
    BuildContext context,
    AppState app,
    PlayerWorkspace ws,
    Mode mode,
    LobbyStrength lobby,
    Map<String, MatchSummary> byId,
  ) {
    final c = context.c;
    final slots = <Role?>[null, Role.tank, Role.damage, Role.support];
    String valueOf(RoleMeans m, Role? s) => _fmt(m.slot(s));
    Widget header(Role? s, String team, Color color) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _slotIcon(s, size: 14),
        const SizedBox(width: 3),
        Text(
          team,
          style: Theme.of(context).textTheme.labelMedium!.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
    final cols = <Col<MatchStrength>>[
      // The same identity module as the match list: map picture first, so a row is recognisable.
      Col(
        id: 'match',
        label: tr.analysis.matchColumn,
        width: 190,
        flex: true,
        cell: (_, m) {
          final s = byId[m.matchId];
          return Row(
            children: [
              MapThumb(app.catalog.mapImage(s?.map), width: 46, height: 28),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s?.map?.label ?? missing,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      fmtDateTime(m.startedAtMs),
                      style: Ty.num(Ty.meta).copyWith(color: c.textSecondary),
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      Col(
        id: 'outcome',
        label: tr.analysis.outcomeColumn,
        width: 64,
        cell: (_, m) => OutcomeMark(m.outcome),
      ),
      Col(
        id: 'role',
        label: tr.analysis.roleColumn,
        width: 56,
        tooltip: roleLegend,
        cell: (_, m) => RoleIcon(m.subjectRole, size: 18),
      ),
      for (final s in slots) ...[
        Col(
          id: 'a${s?.id}',
          label: tr.analysis.slotAlly(_slotName(s)),
          headerChild: header(s, tr.analysis.allyShort, c.ally),
          width: 78,
          numeric: true,
          tooltip: tr.analysis.slotAllyMeanTip(
            _slotName(s),
            overall: s == null,
          ),
          cell: (context, m) =>
              _rankCell(context, m.ally.mean.slot(s), strong: _played(m, s)),
        ),
        Col(
          id: 'e${s?.id}',
          label: tr.analysis.slotEnemy(_slotName(s)),
          headerChild: header(s, tr.analysis.enemyShort, c.enemy),
          width: 78,
          numeric: true,
          tooltip: tr.analysis.slotEnemyMeanTip(
            _slotName(s),
            overall: s == null,
          ),
          cell: (context, m) =>
              _rankCell(context, m.enemy.mean.slot(s), strong: _played(m, s)),
        ),
      ],
      Col(
        id: 'rated',
        label: tr.analysis.ratedColumn,
        headerChild: const Icon(Icons.how_to_reg_outlined, size: 15),
        width: 76,
        numeric: true,
        tooltip: tr.analysis.ratedColumnTip,
        cell: (_, m) => Text(
          '${m.ally.rated.overall + m.enemy.rated.overall}/${m.ally.players + m.enemy.players}',
        ),
      ),
    ];
    final ids = [for (final m in lobby.matches) m.matchId];
    return AppTable<MatchStrength>(
      tableLabel: tr.analysis.perMatchTable,
      columns: cols,
      rows: lobby.matches,
      rowLabel: (m) => tr.analysis.perMatchRow(
        when: fmtDateTime(m.startedAtMs),
        map: byId[m.matchId]?.map?.label ?? '',
        outcome: m.outcome.label,
        role: m.subjectRole.label,
        allyAll: valueOf(m.ally.mean, null),
        enemyAll: valueOf(m.enemy.mean, null),
        allyTank: valueOf(m.ally.mean, Role.tank),
        enemyTank: valueOf(m.enemy.mean, Role.tank),
        allyDamage: valueOf(m.ally.mean, Role.damage),
        enemyDamage: valueOf(m.enemy.mean, Role.damage),
        allySupport: valueOf(m.ally.mean, Role.support),
        enemySupport: valueOf(m.enemy.mean, Role.support),
      ),
      onOpen: (m, _) {
        ws.openMatch(mode, m.matchId, ids);
        app.setTab('matches');
      },
    );
  }

  /// The column is the role the player played in this match (drawn bold).
  bool _played(MatchStrength m, Role? slot) =>
      slot != null && slot == m.subjectRole;

  /// One rating cell: the tier emblem and division (as the team tables show ranks) in
  /// tier mode, the rating number otherwise. Emblems come from the shared image cache.
  Widget _rankCell(BuildContext context, double? v, {bool strong = false}) {
    if (_tiers && v != null && ratingTier(v) != null) {
      final app = AppScope.of(context);
      return RankBadge(
        Rank(null, null, null, v.round()),
        catalog: app.catalog,
        // Stadium lobbies are rated on the Stadium ladder, which has its own emblems.
        stadium: app.mode == Mode.stadium,
        size: 18,
      );
    }
    return Text(
      _fmt(v),
      style: strong ? const TextStyle(fontWeight: FontWeight.w600) : null,
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.workspace,
    required this.mode,
    required this.load,
    required this.tiers,
    required this.onTiers,
  });
  final PlayerWorkspace workspace;
  final Mode mode;
  final Load<StrengthResult> load;
  final bool tiers;
  final ValueChanged<bool> onTiers;
  @override
  Widget build(BuildContext context) {
    final ws = workspace;
    final n = ws.strengthCount(mode);
    return Wrap(
      spacing: Sp.betweenGroups,
      runSpacing: Sp.withinGroup,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tr.analysis.scope,
              style: Ty.body.copyWith(color: context.c.textSecondary),
            ),
            const SizedBox(width: 8),
            SegmentedBar<Role?>(
              semanticLabel: tr.analysis.scopeSemantic,
              value: ws.scopeFor(mode),
              disabledReason: tr.analysis.busyDisabled,
              onChanged: load.loading
                  ? null
                  : (v) => ws.setStrengthScope(mode, v),
              segments: [
                Segment(null, tr.analysis.all, hint: tr.analysis.scopeAllHint),
                for (final r in Role.playable)
                  Segment(
                    r,
                    r.label,
                    hint: tr.analysis.scopeRoleHint(r.label),
                    leading: RoleIcon(r, size: 14, tooltip: false),
                  ),
              ],
            ),
            const SizedBox(width: Sp.betweenGroups),
            Text(
              tr.analysis.recentPrefix(eachRole: ws.scopeFor(mode) == null),
              style: Ty.body,
            ),
            const SizedBox(width: 8),
            SegmentedBar<int>(
              semanticLabel: tr.analysis.countSemantic,
              value: n,
              disabledReason: tr.analysis.busyDisabled,
              onChanged: load.loading
                  ? null
                  : (v) => ws.setStrengthCount(mode, v),
              segments: [
                for (final k in const [5, 10, 20])
                  Segment(k, tr.common.matchCount(k)),
              ],
            ),
          ],
        ),
        if (load.loading)
          AppButton(
            tr.common.cancel,
            icon: Icons.stop_circle_outlined,
            onPressed: () => ws.cancelStrength(mode),
          )
        else ...[
          AppButton(
            load.has ? tr.analysis.reanalyse : tr.analysis.startAnalysis,
            primary: true,
            icon: Icons.analytics_outlined,
            tooltip: load.has ? tr.analysis.reanalyseTip : null,
            onPressed: () => ws.runStrength(mode),
          ),
          if (load.has)
            AppButton(
              tr.analysis.requeryRanks,
              quiet: true,
              icon: Icons.refresh,
              tooltip: tr.analysis.requeryRanksTip,
              onPressed: () => ws.runStrength(mode, fresh: true),
            ),
        ],
        SegmentedBar<bool>(
          semanticLabel: tr.analysis.valueDisplay,
          value: tiers,
          onChanged: onTiers,
          segments: [
            Segment(
              true,
              tr.analysis.tierSegment,
              hint: tr.analysis.tierSegmentHint,
            ),
            Segment(
              false,
              tr.analysis.ratingSegment,
              hint: tr.analysis.ratingSegmentHint,
            ),
          ],
        ),
      ],
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro({required this.workspace, required this.mode});
  final PlayerWorkspace workspace;
  final Mode mode;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final ws0 = workspace;
    final n = workspace.strengthCount(mode);
    // Up to 3 roles × n matches; quick play also looks up every participant.
    final requests = mode == Mode.quick ? n * 3 * 10 + 20 : n * 3 + 20;
    return Panel(
      padding: PanelPadding.spacious,
      child: Row(
        children: [
          Icon(Icons.analytics_outlined, size: 28, color: c.textSecondary),
          const SizedBox(width: Sp.betweenGroups),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr.analysis.notAnalysed(mode.label), style: Ty.bodyStrong),
                Text(
                  tr.analysis.introBody(
                    role: ws0.scopeFor(mode)?.label,
                    n: n,
                    requests: ws0.scopeFor(mode) == null
                        ? requests
                        : requests ~/ 3 + 7,
                    quick: mode == Mode.quick,
                  ),
                  style: Ty.body.copyWith(color: c.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Running extends StatelessWidget {
  const _Running({required this.workspace, required this.mode});
  final PlayerWorkspace workspace;
  final Mode mode;

  static String _clock(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final n = workspace.strengthCount(mode);
    final p = workspace.strengthProgress[mode];
    final active = p?.phaseIndex ?? 0;
    final quick = mode == Mode.quick;

    // (label, how it reads when pending, count text, 0–1 fraction or null)
    Widget step(int index, String label, String hint) {
      final done = p != null && index < active;
      final current = index == active;
      final isRatings = index == 2;
      final skipped = isRatings && done && (p.total == 0 && !quick);
      final here = current ? p : null;
      final fraction = here == null || here.total <= 0
          ? (done ? 1.0 : null)
          : (here.done / here.total).clamp(0.0, 1.0);
      String count = '';
      if (here != null && here.total > 0) {
        count = '${here.done} / ${here.total}';
      }
      // Step 0 is the client's own: it picks matches from those already read.
      if (index == 0 && done) {
        count = tr.analysis.selectedMatches(
          workspace.strengthSelected[mode] ?? 0,
        );
      }
      final eta = here?.remainingSeconds;
      final color = done
          ? c.success
          : current
          ? c.accent
          : c.textSecondary;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 20,
                  child: done
                      ? Icon(Icons.check_circle, size: 18, color: color)
                      : current
                      ? Spinner(color: color)
                      : Icon(
                          Icons.radio_button_unchecked,
                          size: 18,
                          color: color,
                        ),
                ),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: current
                      ? Ty.bodyStrong
                      : Ty.body.copyWith(
                          color: done ? c.textPrimary : c.textSecondary,
                        ),
                ),
                const Spacer(),
                if (skipped)
                  Text(
                    tr.analysis.queryNotNeeded,
                    style: Ty.meta.copyWith(color: c.textSecondary),
                  )
                else ...[
                  if (eta != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Text(
                        tr.analysis.remaining(_clock(eta)),
                        style: Ty.num(Ty.meta).copyWith(color: c.textSecondary),
                      ),
                    ),
                  Text(
                    count,
                    style: Ty.num(Ty.body).copyWith(color: c.textSecondary),
                  ),
                ],
              ],
            ),
            if (current || done) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 30),
                child: ProgressLine(value: fraction, color: color),
              ),
              if (current && (here?.note ?? '').isNotEmpty && index != 0)
                Padding(
                  padding: const EdgeInsets.only(left: 30, top: 4),
                  child: Text(
                    index == 1
                        ? tr.analysis.readingNow(here!.note)
                        : tr.analysis.queryingNow(here!.note),
                    style: Ty.meta.copyWith(color: c.textSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ] else
              Padding(
                padding: const EdgeInsets.only(left: 30, top: 2),
                child: Text(
                  hint,
                  style: Ty.meta.copyWith(color: c.textSecondary),
                ),
              ),
          ],
        ),
      );
    }

    return Semantics(
      liveRegion: true,
      label: p == null
          ? tr.analysis.runningSemantic(n)
          : tr.analysis.runningStepSemantic(active + 1, p.done, p.total),
      child: Panel(
        padding: PanelPadding.spacious,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(tr.analysis.analysing, style: Ty.section),
                const SizedBox(width: 10),
                Text(
                  tr.analysis.eachRoleRecent(n),
                  style: Ty.body.copyWith(color: c.textSecondary),
                ),
                const Spacer(),
                if (p != null)
                  Text(
                    tr.analysis.elapsed(_clock((p.elapsedMs / 1000).round())),
                    style: Ty.num(Ty.body).copyWith(color: c.textSecondary),
                  ),
              ],
            ),
            const SizedBox(height: Sp.withinGroup),
            if ((workspace.strengthStatus[mode] ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  workspace.strengthStatus[mode]!,
                  style: Ty.body.copyWith(color: c.accent),
                ),
              ),
            step(0, tr.analysis.stepSelect, tr.analysis.stepSelectHint(n)),
            step(1, tr.analysis.stepDetails, tr.analysis.stepDetailsHint),
            step(
              2,
              tr.analysis.stepRanks,
              tr.analysis.stepRanksHint(quick: quick),
            ),
            step(3, tr.analysis.stepCombine, tr.analysis.stepCombineHint),
            if (p != null && p.requests > 0) ...[
              const Divider(height: 24),
              Row(
                children: [
                  Text(
                    tr.analysis.requestsSent(p.requests, p.cached),
                    style: Ty.meta.copyWith(color: c.textSecondary),
                  ),
                  if (p.failures > 0) ...[
                    const SizedBox(width: 12),
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 14,
                      color: c.warning,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      tr.analysis.failures(p.failures),
                      style: Ty.meta.copyWith(color: c.warning),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChartSection extends StatelessWidget {
  const _ChartSection({
    required this.matches,
    required this.role,
    required this.perRole,
    required this.tiers,
    required this.onRole,
  });
  final List<MatchStrength> matches; // oldest → newest, every role
  /// The role the queried player played; null shows all of their matches.
  final Role? role;
  final Map<Role, int> perRole;

  /// Show ranks (白银3) rather than rating points on the axis and in the readout.
  final bool tiers;
  final ValueChanged<Role?> onRole;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // A saved choice for a role this player has no matches in falls back to all.
    final role = this.role != null && (perRole[this.role!] ?? 0) > 0
        ? this.role
        : null;
    // Only matches where the queried player played this role.
    final shown = role == null
        ? matches
        : [
            for (final m in matches)
              if (m.subjectRole == role) m,
          ];
    final ally = [for (final m in shown) m.ally.mean.overall];
    final enemy = [for (final m in shown) m.enemy.mean.overall];
    final known =
        ally.whereType<double>().length + enemy.whereType<double>().length;
    final allyMean = _mean(ally);
    final enemyMean = _mean(enemy);
    final name = role == null
        ? tr.analysis.chartAllRoles
        : tr.analysis.chartRole(role.label);
    final days = {
      for (final m in shown) fmtDateTime(m.startedAtMs).substring(0, 5),
    };
    final sameDay = days.length == 1;
    String axisFmt(double v) =>
        tiers ? (ratingLabel(v) ?? fmtInt(v)) : fmtInt(v);
    final summary = known == 0
        ? tr.analysis.chartNoData(name)
        : tr.analysis.chartSummary(
            name,
            shown.length,
            allyMean == null ? null : fmtInt(allyMean),
            enemyMean == null ? null : fmtInt(enemyMean),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: Sp.betweenGroups,
          runSpacing: Sp.withinGroup,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SectionHeader(tr.analysis.chartTitle),
            SegmentedBar<Role?>(
              semanticLabel: tr.analysis.chartRoleSemantic,
              value: role,
              onChanged: onRole,
              segments: [
                Segment(
                  null,
                  tr.analysis.all,
                  leading: _slotIcon(null, size: 15),
                ),
                // Only roles the player actually played in these matches.
                for (final r in Role.playable)
                  if ((perRole[r] ?? 0) > 0)
                    Segment(
                      r,
                      r.label,
                      hint: tr.common.matchCount(perRole[r]!),
                      leading: RoleIcon(r, size: 14, tooltip: false),
                    ),
              ],
            ),
            InfoTip(tr.analysis.chartInfo),
          ],
        ),
        const SizedBox(height: 4),
        Text(summary, style: Ty.body),
        const SizedBox(height: Sp.withinGroup),
        Panel(
          padding: PanelPadding.chart,
          child: LineChart(
            tickStep: _tickStep(shown),
            axisFormat: axisFmt,
            detailFormat: tiers ? (v) => tr.analysis.points(fmtInt(v)) : null,
            series: [
              ChartSeries(
                label: tr.common.ally,
                color: c.ally,
                values: ally,
                lows: [for (final m in shown) m.ally.min.overall],
                highs: [for (final m in shown) m.ally.max.overall],
                counts: [for (final m in shown) m.ally.rated.overall],
                countNotes: [for (final m in shown) _otherRoleNote(m.ally)],
              ),
              ChartSeries(
                label: tr.common.enemy,
                color: c.enemy,
                values: enemy,
                dashed: true,
                lows: [for (final m in shown) m.enemy.min.overall],
                highs: [for (final m in shown) m.enemy.max.overall],
                counts: [for (final m in shown) m.enemy.rated.overall],
                countNotes: [for (final m in shown) _otherRoleNote(m.enemy)],
              ),
            ],
            countFormat: tr.analysis.ratedCount,
            rangeMeaning: tr.analysis.rangeMeaning(tiers: tiers),
            // When every match is on one day the date says nothing, so show the time instead.
            xLabels: [
              for (final m in shown)
                sameDay
                    ? fmtDateTime(m.startedAtMs).substring(6)
                    : fmtDateTime(m.startedAtMs).substring(0, 5),
            ],
            pointNotes: [
              for (final m in shown)
                tr.analysis.chartPointNote(
                  m.outcome.label,
                  m.subjectRole.label.isEmpty ? '?' : m.subjectRole.label,
                ),
            ],
            hollow: [for (final m in shown) m.outcome == Outcome.loss],
            hollowMeaning: tr.analysis.hollowMeaning,
            valueFormat: axisFmt,
            summary: summary,
          ),
        ),
        _ChartTable(matches: shown, slot: null),
      ],
    );
  }

  double? _mean(List<double?> v) {
    final x = v.whereType<double>().toList();
    return x.isEmpty ? null : x.reduce((a, b) => a + b) / x.length;
  }

  /// One rank division (100) when the data spans a few ranks, one tier (500) when wide.
  double _tickStep(List<MatchStrength> shown) {
    final all = [
      for (final m in shown) ...[
        m.ally.min.overall,
        m.ally.max.overall,
        m.enemy.min.overall,
        m.enemy.max.overall,
      ],
    ].whereType<double>();
    if (all.isEmpty) return 100;
    final spread = all.reduce(math.max) - all.reduce(math.min);
    return spread <= 900 ? 100 : 500;
  }
}

/// Text equivalent of the chart: the numbers behind it.
class _ChartTable extends StatelessWidget {
  const _ChartTable({required this.matches, required this.slot});
  final List<MatchStrength> matches;
  final Role? slot;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(tr.analysis.chartAsTable, style: Ty.body),
      shape: const Border(),
      collapsedShape: const Border(),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 24,
            runSpacing: 2,
            children: [
              for (final m in matches)
                Text(
                  tr.analysis.chartTableRow(
                    fmtDateTime(m.startedAtMs),
                    fmtInt(m.ally.mean.slot(slot)),
                    fmtInt(m.enemy.mean.slot(slot)),
                    _signed(m.diff.slot(slot)),
                  ),
                  style: Ty.num(Ty.meta).copyWith(color: c.textSecondary),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Said in the readout when some rated players have no rank for the role they played.
String? _otherRoleNote(SideStrength side) =>
    side.otherRole == 0 ? null : tr.analysis.otherRoleNote(side.otherRole);
