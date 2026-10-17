import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/support.dart';
import '../../design/data_table.dart';
import '../../design/icons.dart';
import '../../state/match_view.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';
import '../../state/app_state.dart';
import '../player_view.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key, required this.workspace});
  final PlayerWorkspace workspace;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final ws = workspace;
    final mode = app.mode;
    final load = ws.matchesFor(mode);
    final c = context.c;
    if (load.failedWithoutData) {
      return ErrorPanel(
        what: '无法读取玩家档案',
        error: load.error!,
        onRetry: () => ws.loadMatches(mode, fresh: true),
      );
    }
    final data = load.value;
    if (data == null)
      return const AfterDelay(
        child: Center(child: RefreshingChip(label: '正在读取档案…')),
      );
    final p = data.profile;
    final career = data.career(mode);
    final scale = math.max(
      1.0,
      MediaQuery.textScalerOf(context).scale(13) / 13,
    );
    final roleCount =
        career?.roles.where((r) => Role.playable.contains(r.role)).length ?? 0;
    final tableH =
        context.density.rowHeight * scale * (math.max(roleCount, 1) + 1) + 4;

    return ListView(
      padding: const EdgeInsets.only(right: 16),
      children: [
        LoadStatusBar(
          at: load.at,
          loading: load.loading && load.has,
          error: load.error?.message,
          onRetry: () => ws.loadMatches(mode, fresh: true),
        ),
        const SizedBox(height: Sp.betweenGroups),
        _FactCard(
          title: '身份',
          facts: [
            ('战网昵称', p.name ?? ws.name),
            ('玩家编号', p.bnetId ?? missing),
            if (p.title != null) ('称号', p.title!),
            (
              '荣誉等级',
              p.endorsementLevel == null ? missing : '${p.endorsementLevel} 级',
            ),
            (
              '游戏时长',
              p.playTimeHours == null
                  ? missing
                  : '${fmtOne(p.playTimeHours)} 小时',
            ),
            ('总场次', fmtInt(p.totalMatches)),
            (
              '账号状态',
              p.suspended
                  ? '暂停${p.suspensionExpiresMs == null ? '' : '，到期 ${fmtDateTime(p.suspensionExpiresMs)}'}'
                  : '正常',
            ),
          ],
        ),
        const SizedBox(height: Sp.betweenSections),
        _Recent(rows: data.matches, mode: mode),
        const SizedBox(height: Sp.betweenSections),
        Semantics(
          header: true,
          child: Text(
            '${mode.label}生涯 · 第 ${career?.season ?? app.currentSeason} 赛季',
            style: Ty.section,
          ),
        ),
        const SizedBox(height: Sp.withinGroup),
        SizedBox(
          height: tableH,
          child: AppTable<RoleCareer>(
            tableLabel: '${mode.label}各职责生涯',
            columns: [
              Col(
                id: 'role',
                label: '职责',
                width: 100,
                flex: true,
                tooltip: roleLegend,
                cell: (_, r) => RoleIcon(r.role, size: 18, showLabel: true),
              ),
              Col(
                id: 'cur',
                label: '当前段位',
                width: 124,
                cell: (_, r) => RankBadge(
                  r.current,
                  catalog: app.catalog,
                  showText: true,
                  stadium: mode == Mode.stadium,
                ),
              ),
              Col(
                id: 'peak',
                label: '最高段位',
                width: 124,
                cell: (_, r) => RankBadge(
                  r.peak,
                  catalog: app.catalog,
                  showText: true,
                  stadium: mode == Mode.stadium,
                ),
              ),
              Col(
                id: 'm',
                label: '场次',
                width: 64,
                numeric: true,
                cell: (_, r) => Text(fmtInt(r.matches)),
              ),
              Col(
                id: 'w',
                label: '胜率',
                width: 76,
                numeric: true,
                cell: (_, r) => Text(fmtPct(r.winRatePct)),
              ),
              Col(
                id: 'k',
                label: 'KDA',
                width: 64,
                numeric: true,
                cell: (_, r) => Text(fmtTwo(r.kda)),
              ),
              Col(
                id: 's',
                label: '最长连胜',
                width: 88,
                numeric: true,
                cell: (_, r) => Text(fmtInt(r.maxWinStreak)),
              ),
            ],
            rows:
                career?.roles
                    .where((r) => Role.playable.contains(r.role))
                    .toList() ??
                const [],
            rowLabel: (r) =>
                '${r.role.label}，当前${r.current?.label ?? '未定级'}，最高${r.peak?.label ?? '未定级'}，${fmtInt(r.matches)} 场，胜率${fmtPct(r.winRatePct)}',
            empty: Center(
              child: Text(
                '${mode.label}本赛季没有分职责的生涯数据。',
                style: Ty.body.copyWith(color: c.textSecondary),
              ),
            ),
          ),
        ),
        if (mode != Mode.competitive)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${mode.label}不提供段位，段位列为 —。',
              style: Ty.meta.copyWith(color: c.textSecondary),
            ),
          ),
        if (career?.behavior != null) ...[
          const SizedBox(height: Sp.betweenSections),
          _FactCard(
            title: '行为与荣誉',
            facts: [
              ('收到的荣誉', fmtInt(career!.behavior!.honorsReceived)),
              ('送出的荣誉', fmtInt(career.behavior!.honorsSent)),
              ('被举报次数', fmtInt(career.behavior!.reports)),
              if (career.behavior!.comment != null)
                ('本周评语', career.behavior!.comment!),
            ],
          ),
        ],
        if (career != null && career.provinceRanks.isNotEmpty) ...[
          const SizedBox(height: Sp.betweenSections),
          _FactCard(
            title: '省榜排名',
            facts: [
              for (final r in career.provinceRanks)
                (
                  '${r.role.label.isEmpty ? '综合' : r.role.label}${r.province == null ? '' : ' · ${r.province}'}',
                  '第 ${fmtInt(r.rank)} 名',
                ),
            ],
          ),
        ],
        const SizedBox(height: Sp.betweenSections),
      ],
    );
  }
}

/// Read-only facts as label-over-value blocks in one card: grouped by the card,
/// scanned as a row instead of a two-column list with a wide empty right half.
class _FactCard extends StatelessWidget {
  const _FactCard({required this.title, required this.facts});
  final String title;
  final List<(String, String)> facts;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(header: true, child: Text(title, style: Ty.section)),
        const SizedBox(height: Sp.withinGroup),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(Sp.betweenGroups),
          decoration: BoxDecoration(
            color: c.raised,
            borderRadius: BorderRadius.circular(Radii.container),
            border: Border.all(color: c.border),
          ),
          child: Wrap(
            spacing: 40,
            runSpacing: Sp.withinGroup + 4,
            children: [
              for (final f in facts)
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 96,
                    maxWidth: 260,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        f.$1,
                        style: Ty.meta.copyWith(color: c.textSecondary),
                      ),
                      const SizedBox(height: 2),
                      SelectableText(f.$2, style: Ty.num(Ty.title)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One headline number: label above, big figure, optional note, optional stat colour.
class _Tile extends StatelessWidget {
  const _Tile(this.label, this.value, {this.note, this.color});
  final String label, value;
  final String? note;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      width: 176,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: color == null ? c.raised : c.barFill(color!),
        border: Border(left: BorderSide(color: color ?? c.border, width: 3)),
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Ty.meta.copyWith(color: c.textSecondary)),
          Text(value, style: Ty.num(Ty.figure)),
          if (note != null)
            Text(note!, style: Ty.meta.copyWith(color: c.textSecondary)),
        ],
      ),
    );
  }
}

/// Averages over the matches that were read. The match list no longer carries these:
/// the list is for recognising a match, this is for judging recent form.
class _Recent extends StatelessWidget {
  const _Recent({required this.rows, required this.mode});
  final List<MatchSummary> rows;
  final Mode mode;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final a = Agg(rows);
    String mean(String f) => a.mean[f] == null ? missing : fmtInt(a.mean[f]);
    String? partial(String f) => a.mean[f] != null && a.samples[f]! < a.matches
        ? 'n=${a.samples[f]}'
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Semantics(
              header: true,
              child: Text('近期表现 · ${mode.label}', style: Ty.section),
            ),
            const InfoTip(
              '只统计“对局”页已读取的对局。胜率 = 胜 ÷ （胜 + 负）；平均值只计入提供了该数据的对局，数量不足时标注 n。',
            ),
          ],
        ),
        const SizedBox(height: Sp.withinGroup),
        if (rows.isEmpty)
          Text('还没有读取到对局。', style: Ty.body.copyWith(color: c.textSecondary))
        else
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _Tile('场次', '${a.matches}'),
              _Tile(
                '战绩',
                '${a.wins} 胜 ${a.losses} 负',
                note: a.draws + a.unknown > 0
                    ? '${a.draws} 平${a.unknown > 0 ? ' · ${a.unknown} 未知' : ''}'
                    : null,
              ),
              _Tile('胜率', fmtPct(a.winRatePct)),
              _Tile('KDA', fmtTwo(a.kda)),
              const SizedBox(width: 100000, height: 0),
              _Tile(
                '场均伤害',
                mean('damage'),
                note: partial('damage'),
                color: c.statDamage,
              ),
              _Tile(
                '场均治疗',
                mean('healing'),
                note: partial('healing'),
                color: c.statHealing,
              ),
              _Tile(
                '场均阻挡',
                mean('mitigation'),
                note: partial('mitigation'),
                color: c.statMitigation,
              ),
            ],
          ),
      ],
    );
  }
}
