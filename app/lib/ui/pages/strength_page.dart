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

/// Minus sign U+2212 matches digit stroke weight and keeps columns aligned.
String _signed(double? v) {
  if (v == null) return missing;
  final r = v.round();
  if (r == 0) return '0';
  return r > 0 ? '+${fmtInt(r)}' : '−${fmtInt(-r)}';
}

String _slotName(Role? r) => r == null ? '综合' : r.label;

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

    final how = mode == Mode.quick
        ? '快速比赛没有段位，用每名玩家本赛季的竞技段位代替（没有取上赛季），职责按他这局所打的。'
        : '使用每名参与者在这一局里的段位。';

    return ListView(
      padding: const EdgeInsets.only(right: 16),
      children: [
        Row(
          children: [
            Semantics(header: true, child: Text('对局强度', style: Ty.section)),
            InfoTip('比较己方与对方的平均段位。重装、输出、支援只平均打这个职责的玩家，综合是全部。$how'),
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
              what: '无法完成对局强度分析',
              error: load.error!,
              onRetry: () => ws.runStrength(mode),
              extra: [
                if (load.error!.isAuth)
                  AppButton('打开设置', onPressed: () => app.showSettings(true)),
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
    final unrated = requested - lobby.matches.length;

    if (lobby.matches.isEmpty) {
      return [
        EmptyState(
          icon: Icons.analytics_outlined,
          title: '没有可计算强度的对局',
          body: requested == 0
              ? '该玩家在${mode.label}没有读取到对局。'
              : '读取了 $read / $requested 场详情，但没有玩家能确定段位。快速比赛要求玩家有竞技段位，竞技要求对局里带段位。',
          actions: [
            AppButton(
              '重新分析',
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
      if (byMode != null) byMode,
      ...lobby.bySubjectRole.where((g) => g.mode == mode),
    ];
    final chronological = lobby.matches.reversed
        .toList(); // oldest → newest for the chart
    final byId = {for (final m in r.dataset.matches) m.id: m};
    final perRole = {
      for (final role in Role.playable)
        role: lobby.matches.where((m) => m.subjectRole == role).length,
    };

    return [
      Wrap(
        spacing: Sp.betweenGroups,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('${lobby.matches.length} 场', style: Ty.num(Ty.bodyStrong)),
          // Per-role coverage: the target is n each; a role with fewer is marked, not hidden.
          for (final role in Role.playable)
            Tooltip(
              message: perRole[role]! >= n
                  ? '${role.label}：取了最近 $n 场'
                  : '${role.label}：只有 ${perRole[role]} 场可用，不足 $n 场，已取全部',
              child: Semantics(
                label: '${role.label} ${perRole[role]} 场',
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
          Tooltip(
            message: '已评定的参与者 / 全部参与者',
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
          InfoTip(
            '未定级或资料不可见的玩家不计入平均，也不会当作 0。${unrated > 0 ? '有 $unrated 场没有任何已评定的参与者，未计入。' : ''}',
          ),
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
          Semantics(header: true, child: Text('按你所打的职责', style: Ty.section)),
          const InfoTip('同职责 = 你打的职责。差 = 己方 − 对方，正数表示己方更强。'),
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
          Semantics(header: true, child: Text('逐场明细', style: Ty.section)),
          const InfoTip('点击一行打开这场对局。加粗的列是你所打的职责。'),
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
            message: '${fmtInt(v)} 分 · ${ratingLabel(v) ?? ''}',
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
      tooltip: '$label · 同职责平均',
      width: 104,
      numeric: true,
      cell: (_, g) {
        final v = pick(g).slot(g.subjectRole);
        return tipped(v, Text(_fmt(v)));
      },
    );
    return AppTable<StrengthGroup>(
      tableLabel: '按你所打职责汇总的对局强度',
      columns: [
        Col(
          id: 'role',
          label: '你打的职责',
          width: 130,
          flex: true,
          cell: (_, g) => g.subjectRole == null
              ? const Row(
                  children: [
                    Icon(Icons.groups_2_outlined, size: 18),
                    SizedBox(width: 8),
                    Text('全部', style: TextStyle(fontWeight: FontWeight.w600)),
                  ],
                )
              : RoleIcon(g.subjectRole!, size: 18, showLabel: true),
        ),
        Col(
          id: 'n',
          label: '场次',
          width: 60,
          numeric: true,
          cell: (_, g) => Text('${g.matches}'),
        ),
        Col(
          id: 'wr',
          label: '胜率',
          width: 84,
          numeric: true,
          tooltip: '胜 ÷ （胜 + 负）',
          cell: (_, g) => Text(fmtPct(g.winRatePct)),
        ),
        side('ally', '己方', c.ally, (g) => g.ally),
        side('enemy', '对方', c.enemy, (g) => g.enemy),
        Col(
          id: 'diff',
          label: '差',
          width: 100,
          numeric: true,
          tooltip: '己方同职责平均 − 对方同职责平均，单位：段位分',
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
          label: '全场',
          width: 92,
          numeric: true,
          tooltip: '双方合计的同职责平均',
          cell: (_, g) => Text(_fmt(g.lobby.slot(g.subjectRole))),
        ),
        Col(
          id: 'all',
          label: '综合差',
          width: 92,
          numeric: true,
          tooltip: '所有已评定玩家的平均差（己方 − 对方）',
          cell: (_, g) => Text(_signed(g.diff.overall)),
        ),
      ],
      rows: groups,
      rowLabel: (g) =>
          '${g.subjectRole?.label ?? '全部'}，${g.matches} 场，胜率${fmtPct(g.winRatePct)}，己方同职责${_fmt(g.ally.slot(g.subjectRole))}，对方同职责${_fmt(g.enemy.slot(g.subjectRole))}，差${_signed(g.diff.slot(g.subjectRole))}',
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
        label: '对局',
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
        label: '结果',
        width: 64,
        cell: (_, m) => OutcomeMark(m.outcome),
      ),
      Col(
        id: 'role',
        label: '职责',
        width: 56,
        tooltip: roleLegend,
        cell: (_, m) => RoleIcon(m.subjectRole, size: 18),
      ),
      for (final s in slots) ...[
        Col(
          id: 'a${s?.id}',
          label: '${_slotName(s)} 己方',
          headerChild: header(s, '己', c.ally),
          width: 78,
          numeric: true,
          tooltip: '${_slotName(s)} · 己方平均${s == null ? '（所有已评定玩家）' : ''}',
          cell: (_, m) => _bold(m, s, valueOf(m.ally.mean, s)),
        ),
        Col(
          id: 'e${s?.id}',
          label: '${_slotName(s)} 对方',
          headerChild: header(s, '对', c.enemy),
          width: 78,
          numeric: true,
          tooltip: '${_slotName(s)} · 对方平均${s == null ? '（所有已评定玩家）' : ''}',
          cell: (_, m) => _bold(m, s, valueOf(m.enemy.mean, s)),
        ),
      ],
      Col(
        id: 'rated',
        label: '已评定',
        headerChild: const Icon(Icons.how_to_reg_outlined, size: 15),
        width: 76,
        numeric: true,
        tooltip: '已评定人数 / 总人数（己方 + 对方）',
        cell: (_, m) => Text(
          '${m.ally.rated.overall + m.enemy.rated.overall}/${m.ally.players + m.enemy.players}',
        ),
      ),
    ];
    final ids = [for (final m in lobby.matches) m.matchId];
    return AppTable<MatchStrength>(
      tableLabel: '逐场对局强度',
      columns: cols,
      rows: lobby.matches,
      rowLabel: (m) =>
          '${fmtDateTime(m.startedAtMs)}，${byId[m.matchId]?.map?.label ?? ''}，${m.outcome.label}，你打${m.subjectRole.label}，综合 己方${valueOf(m.ally.mean, null)} 对方${valueOf(m.enemy.mean, null)}，'
          '重装 己方${valueOf(m.ally.mean, Role.tank)} 对方${valueOf(m.enemy.mean, Role.tank)}，输出 己方${valueOf(m.ally.mean, Role.damage)} 对方${valueOf(m.enemy.mean, Role.damage)}，支援 己方${valueOf(m.ally.mean, Role.support)} 对方${valueOf(m.enemy.mean, Role.support)}',
      onOpen: (m, _) {
        ws.openMatch(mode, m.matchId, ids);
        app.setTab('matches');
      },
    );
  }

  Widget _bold(MatchStrength m, Role? slot, String text) => Text(
    text,
    style: slot != null && slot == m.subjectRole
        ? const TextStyle(fontWeight: FontWeight.w600)
        : null,
  );
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
            // The three role glyphs say "per role"; the number is how many matches of each.
            Tooltip(
              message: '每个职责各取最近多少场（$roleLegend）',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final r in Role.playable) ...[
                    RoleIcon(r, size: 18, tooltip: false),
                    const SizedBox(width: 10),
                  ],
                  const SizedBox(width: 4),
                  Text('各取最近', style: Ty.body),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SegmentedBar<int>(
              semanticLabel: '每个职责取的场数',
              value: n,
              onChanged: load.loading
                  ? (_) {}
                  : (v) => ws.setStrengthCount(mode, v),
              segments: const [
                Segment(5, '5 场'),
                Segment(10, '10 场'),
                Segment(20, '20 场'),
              ],
            ),
          ],
        ),
        if (load.loading)
          AppButton(
            '取消',
            icon: Icons.stop_circle_outlined,
            onPressed: () => ws.cancelStrength(mode),
          )
        else
          AppButton(
            load.has ? '重新分析' : '开始分析',
            primary: true,
            icon: Icons.analytics_outlined,
            onPressed: () => ws.runStrength(mode, fresh: load.has),
          ),
        SegmentedBar<bool>(
          semanticLabel: '数值显示',
          value: tiers,
          onChanged: onTiers,
          segments: const [
            Segment(true, '段位', hint: '如 白金 2'),
            Segment(false, '段位分', hint: '500–5000'),
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
    final n = workspace.strengthCount(mode);
    // Up to 3 roles × n matches; quick play also looks up every participant.
    final requests = mode == Mode.quick ? n * 3 * 10 + 20 : n * 3 + 20;
    return Container(
      padding: const EdgeInsets.all(Sp.betweenSections),
      decoration: BoxDecoration(
        color: c.raised,
        borderRadius: BorderRadius.circular(Radii.container),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          Icon(Icons.analytics_outlined, size: 28, color: c.textSecondary),
          const SizedBox(width: Sp.betweenGroups),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('还没有分析${mode.label}', style: Ty.bodyStrong),
                Text(
                  '每个职责取最近 $n 场，不足就取全部。最多约 $requests 次请求${mode == Mode.quick ? '，约 1–2 分钟' : ''}；后台进行，可随时取消。',
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
      if (here != null && here.total > 0)
        count = '${here.done} / ${here.total}';
      if (here != null && index == 0) {
        count = '第 ${here.done} 页 · 已找到 ${here.matchesFound} 场';
      }
      final eta = here?.remainingSeconds;
      final color = done
          ? c.win
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
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: color,
                          ),
                        )
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
                    '无需查询（该模式对局里已有段位）',
                    style: Ty.meta.copyWith(color: c.textSecondary),
                  )
                else ...[
                  if (eta != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Text(
                        '约剩 ${_clock(eta)}',
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
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: fraction,
                    minHeight: 4,
                    color: color,
                    backgroundColor: c.border,
                  ),
                ),
              ),
              if (current && (here?.note ?? '').isNotEmpty && index != 0)
                Padding(
                  padding: const EdgeInsets.only(left: 30, top: 4),
                  child: Text(
                    index == 1 ? '正在读取：${here!.note}' : '正在查询：${here!.note}',
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
          ? '正在分析，每个职责最近 $n 场'
          : '正在分析，第 ${active + 1} 步，已完成 ${p.done} / ${p.total}',
      child: Container(
        padding: const EdgeInsets.all(Sp.betweenSections),
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
                Text('正在分析', style: Ty.section),
                const SizedBox(width: 10),
                Text(
                  '每个职责最近 $n 场',
                  style: Ty.body.copyWith(color: c.textSecondary),
                ),
                const Spacer(),
                if (p != null)
                  Text(
                    '已用 ${_clock((p.elapsedMs / 1000).round())}',
                    style: Ty.num(Ty.body).copyWith(color: c.textSecondary),
                  ),
              ],
            ),
            const SizedBox(height: Sp.withinGroup),
            if (p == null)
              Text('正在连接…', style: Ty.body.copyWith(color: c.textSecondary)),
            step(0, '读取对局列表', '分页读取，直到每个职责都凑够场数'),
            step(1, '读取对局详情', '每场一次请求，取得双方全部玩家'),
            step(
              2,
              '查询参与者段位',
              quick ? '快速比赛没有段位，逐个查询每名玩家的竞技段位' : '该模式对局里已有段位，不需要查询',
            ),
            step(3, '整合计算', '合并每场强度并按职责汇总'),
            if (p != null && p.requests > 0) ...[
              const Divider(height: 24),
              Row(
                children: [
                  Text(
                    '已发出 ${p.requests} 次请求',
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
                      '${p.failures} 次失败，不计入平均',
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
    final name = role == null ? '全部职责' : '你打${role.label}';
    final days = {
      for (final m in shown) fmtDateTime(m.startedAtMs).substring(0, 5),
    };
    final sameDay = days.length == 1;
    String axisFmt(double v) =>
        tiers ? (ratingLabel(v) ?? fmtInt(v)) : fmtInt(v);
    final summary = known == 0
        ? '$name：这些对局里没有已评定的玩家，无法绘制。'
        : '$name，${shown.length} 场：己方平均 ${allyMean == null ? '无数据' : fmtInt(allyMean)}，对方平均 ${enemyMean == null ? '无数据' : fmtInt(enemyMean)}。';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: Sp.betweenGroups,
          runSpacing: Sp.withinGroup,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Semantics(header: true, child: Text('逐场走势', style: Ty.section)),
            SegmentedBar<Role?>(
              semanticLabel: '你所打的职责',
              value: role,
              onChanged: onRole,
              segments: [
                Segment(null, '全部', leading: _slotIcon(null, size: 15)),
                // Only roles the player actually played in these matches.
                for (final r in Role.playable)
                  if ((perRole[r] ?? 0) > 0)
                    Segment(
                      r,
                      r.label,
                      hint: '${perRole[r]} 场',
                      leading: RoleIcon(r, size: 14, tooltip: false),
                    ),
              ],
            ),
            const InfoTip(
              '按你打的职责筛选对局。竖条是该队已评定玩家的最低到最高段位，圆点是平均，悬停看分数；斜线阴影是没有已评定玩家的场次。',
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(summary, style: Ty.body),
        const SizedBox(height: Sp.withinGroup),
        Container(
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
          child: LineChart(
            tickStep: _tickStep(shown),
            axisFormat: axisFmt,
            detailFormat: tiers ? (v) => '${fmtInt(v)} 分' : null,
            series: [
              ChartSeries(
                label: '己方',
                color: c.ally,
                values: ally,
                lows: [for (final m in shown) m.ally.min.overall],
                highs: [for (final m in shown) m.ally.max.overall],
              ),
              ChartSeries(
                label: '对方',
                color: c.enemy,
                values: enemy,
                dashed: true,
                lows: [for (final m in shown) m.enemy.min.overall],
                highs: [for (final m in shown) m.enemy.max.overall],
              ),
            ],
            rangeMeaning:
                '竖条：该队已评定玩家的最低到最高${tiers ? '段位' : '分'}，圆点是平均。斜线阴影：这些场没有已评定的玩家。',
            // When every match is on one day the date says nothing, so show the time instead.
            xLabels: [
              for (final m in shown)
                sameDay
                    ? fmtDateTime(m.startedAtMs).substring(6)
                    : fmtDateTime(m.startedAtMs).substring(0, 5),
            ],
            pointNotes: [
              for (final m in shown)
                '${m.outcome.label} · 你打${m.subjectRole.label.isEmpty ? '?' : m.subjectRole.label} · 已评定 ${m.ally.rated.overall}+${m.enemy.rated.overall} 人',
            ],
            hollow: [for (final m in shown) m.outcome == Outcome.loss],
            hollowMeaning: '实心点：胜或平；空心点：负。',
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
      title: Text('以表格查看图中的数值', style: Ty.body),
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
                  '${fmtDateTime(m.startedAtMs)}  己方 ${fmtInt(m.ally.mean.slot(slot))}  对方 ${fmtInt(m.enemy.mean.slot(slot))}  差 ${_signed(m.diff.slot(slot))}',
                  style: Ty.num(Ty.meta).copyWith(color: c.textSecondary),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
