import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/support.dart';
import '../../design/icons.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';
import '../../state/app_state.dart';
import '../player_view.dart';
import 'player_detail_page.dart';
import 'team_table.dart';

class MatchDetailPage extends StatefulWidget {
  const MatchDetailPage({super.key, required this.workspace});
  final PlayerWorkspace workspace;
  @override
  State<MatchDetailPage> createState() => _MatchDetailPageState();
}

class _MatchDetailPageState extends State<MatchDetailPage> {
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final ws = widget.workspace;
    final id = ws.openMatchId!;
    final mode = ws.openMatchMode ?? app.mode;
    final load = ws.detailFor(mode, id);
    final c = context.c;
    final index = ws.navIds.indexOf(id);
    final summary = ws
        .matchesFor(mode)
        .value
        ?.matches
        .where((m) => m.id == id)
        .firstOrNull;

    // The player whose page is open, when one is.
    final playerKey = ws.openPlayerKey;
    Participant? player;
    var playerIndex = -1;
    var playerCount = 0;
    var playerIsAlly = true;
    final loaded = load.value;
    if (playerKey != null && loaded != null) {
      final parts = playerKey.split(':');
      playerIsAlly = parts[0] == 'ally';
      final team = playerIsAlly ? loaded.allies : loaded.enemies;
      final i = int.tryParse(parts[1]) ?? -1;
      if (i >= 0 && i < team.length) {
        player = team[i];
        playerIndex = (playerIsAlly ? 0 : loaded.allies.length) + i;
        playerCount = loaded.allies.length + loaded.enemies.length;
      }
    }
    final onPlayerPage = player != null;
    final title =
        '${fmtDateTime(summary?.startedAtMs ?? load.value?.startedAtMs)}  ${summary?.map?.label ?? load.value?.map?.label ?? ''}';

    final header = Row(
      children: [
        AppButton(
          '对局列表',
          icon: Icons.arrow_back,
          quiet: true,
          tooltip: onPlayerPage ? null : 'Esc 或 Alt+←',
          onPressed: ws.closeMatch,
        ),
        Text('›', style: Ty.body.copyWith(color: c.textSecondary)),
        const SizedBox(width: 8),
        Expanded(
          child: onPlayerPage
              ? Row(
                  children: [
                    Flexible(
                      child: AppButton(
                        title,
                        quiet: true,
                        tooltip: '回到整场对局（Esc 或 Alt+←）',
                        onPressed: ws.closePlayer,
                      ),
                    ),
                    Text('›', style: Ty.body.copyWith(color: c.textSecondary)),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        player.name ?? '未知玩家',
                        style: Ty.bodyStrong,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                )
              : Text(
                  title,
                  style: Ty.bodyStrong,
                  overflow: TextOverflow.ellipsis,
                ),
        ),
        if (onPlayerPage)
          Text(
            '第 ${playerIndex + 1} / $playerCount 位',
            style: Ty.num(Ty.meta).copyWith(color: c.textSecondary),
          )
        else if (index >= 0)
          Text(
            '第 ${index + 1} / ${ws.navIds.length} 场',
            style: Ty.num(Ty.meta).copyWith(color: c.textSecondary),
          ),
        IconAction(
          icon: Icons.chevron_left,
          label: onPlayerPage ? '上一位' : '上一场',
          shortcut: '[',
          onPressed: onPlayerPage
              ? (playerIndex > 0 ? () => ws.stepOpenPlayer(-1) : null)
              : (index > 0 ? () => ws.stepMatch(-1) : null),
        ),
        IconAction(
          icon: Icons.chevron_right,
          label: onPlayerPage ? '下一位' : '下一场',
          shortcut: ']',
          onPressed: onPlayerPage
              ? (playerIndex < playerCount - 1
                    ? () => ws.stepOpenPlayer(1)
                    : null)
              : (index >= 0 && index < ws.navIds.length - 1
                    ? () => ws.stepMatch(1)
                    : null),
        ),
      ],
    );

    Widget body;
    if (load.failedWithoutData) {
      body = ErrorPanel(
        what: '无法读取这场对局的详情',
        error: load.error!,
        onRetry: () => ws.loadDetail(mode, id),
        extra: [AppButton('返回列表', onPressed: ws.closeMatch)],
      );
    } else if (!load.has) {
      body = const AfterDelay(child: _DetailSkeleton());
    } else if (onPlayerPage) {
      body = PlayerDetailPage(
        key: ValueKey(playerKey),
        detail: load.value!,
        player: player,
        ally: playerIsAlly,
        catalog: app.catalog,
        ratingsLoading:
            ws.ratingsLoading(mode, id) && load.value!.ratingsPending,
      );
    } else {
      body = _Body(
        detail: load.value!,
        summary: summary,
        onOpenPlayer: (p) {
          final d = load.value!;
          final a = d.allies.indexOf(p);
          if (a >= 0) {
            ws.openPlayer('ally', a);
          } else {
            ws.openPlayer('enemy', d.enemies.indexOf(p));
          }
        },
        refreshing: load.loading,
        ratingsLoading: ws.ratingsLoading(mode, id),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const SizedBox(height: Sp.withinGroup),
        Expanded(child: body),
      ],
    );
  }
}

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Widget block(double h) => Container(
      height: h,
      margin: const EdgeInsets.only(bottom: Sp.betweenGroups),
      decoration: BoxDecoration(
        color: c.hover.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(Radii.container),
      ),
    );
    return Semantics(
      label: '正在加载对局详情',
      liveRegion: true,
      child: ExcludeSemantics(
        child: Column(children: [block(56), block(250), block(250)]),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.detail,
    required this.summary,
    required this.onOpenPlayer,
    required this.refreshing,
    required this.ratingsLoading,
  });
  final MatchDetail detail;
  final MatchSummary? summary;
  final ValueChanged<Participant> onOpenPlayer;
  final bool refreshing;

  /// The players' ranks are being looked up: cells without one say so.
  final bool ratingsLoading;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final app = AppScope.of(context);
    final all = [...detail.allies, ...detail.enemies];
    double maxOf(double? Function(Participant) f) =>
        all.map(f).whereType<double>().fold(0.0, math.max);
    final maxes = (
      damage: maxOf((p) => p.stats.damage),
      healing: maxOf((p) => p.stats.healing),
      mitigation: maxOf((p) => p.stats.mitigation),
    );
    final outcomeColor = c.outcome(detail.outcome.id);
    return ListView(
      // Room for the scrollbar, so it does not sit on the tables.
      padding: const EdgeInsets.only(right: 12),
      children: [
        // Result line
        Padding(
          padding: const EdgeInsets.only(bottom: Sp.betweenGroups),
          child: Wrap(
            spacing: Sp.betweenGroups,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              MapThumb(
                app.catalog.mapImage(detail.map),
                width: 88,
                height: 48,
                radius: 6,
              ),
              Semantics(
                header: true,
                child: Text(detail.map?.label ?? '未知地图', style: Ty.page),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [OutcomeMark(detail.outcome)],
              ),
              Text(
                fmtScore(detail.scoreTeam, detail.scoreOpponent),
                style: Ty.num(Ty.page).copyWith(color: outcomeColor),
              ),
              Text(
                detail.mode.label,
                style: Ty.body.copyWith(color: c.textSecondary),
              ),
              if (detail.durationS != null)
                Text(
                  '用时 ${fmtClock(detail.durationS)}',
                  style: Ty.num(Ty.body).copyWith(color: c.textSecondary),
                ),
              if (detail.outcomeFromScore)
                Tooltip(
                  message: '角斗领域详情没有提供胜负字段，结果按最终比分判断。',
                  child: Text(
                    '结果按比分判断',
                    style: Ty.meta.copyWith(color: c.textSecondary),
                  ),
                ),
              if (refreshing) const RefreshingChip(),
            ],
          ),
        ),
        TeamTable(
          title: '己方',
          ally: true,
          players: detail.allies,
          maxes: maxes,
          onSelect: onOpenPlayer,
          catalog: app.catalog,
          stadium: detail.mode == Mode.stadium,
          ratingsLoading: ratingsLoading && detail.ratingsPending,
        ),
        const SizedBox(height: Sp.betweenSections),
        TeamTable(
          title: '对方',
          ally: false,
          players: detail.enemies,
          maxes: maxes,
          onSelect: onOpenPlayer,
          catalog: app.catalog,
          stadium: detail.mode == Mode.stadium,
          ratingsLoading: ratingsLoading && detail.ratingsPending,
        ),
        const SizedBox(height: Sp.withinGroup),
        Text(
          '点一名玩家（或用方向键选中后按 Enter）打开他的详情页：威能、Fleta 指数、组队和点赞。',
          style: Ty.meta.copyWith(color: c.textSecondary),
        ),
        if (detail.bansAlly.isNotEmpty || detail.bansEnemy.isNotEmpty) ...[
          const SizedBox(height: Sp.betweenSections),
          _Bans(detail: detail, catalog: app.catalog),
        ],
        if (detail.subjectHeroes.isNotEmpty) ...[
          const SizedBox(height: Sp.betweenSections),
          _SubjectHeroes(segments: detail.subjectHeroes, catalog: app.catalog),
        ],
        if (detail.rounds.isNotEmpty) ...[
          const SizedBox(height: Sp.betweenSections),
          _Rounds(rounds: detail.rounds),
        ],
        const SizedBox(height: Sp.betweenSections),
      ],
    );
  }
}

class _Bans extends StatelessWidget {
  const _Bans({required this.detail, required this.catalog});
  final MatchDetail detail;
  final Catalog catalog;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Widget side(String title, List<EntityRef> heroes, bool ally) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TeamTag(ally: ally),
        const SizedBox(width: 8),
        Text('禁用', style: Ty.meta.copyWith(color: c.textSecondary)),
        const SizedBox(width: 8),
        if (heroes.isEmpty)
          Text(missing)
        else
          for (final h in heroes) ...[
            NetImage(catalog.heroIcon(h), size: 22, fallback: h.label),
            const SizedBox(width: 4),
            Text(h.label, style: Ty.body),
            const SizedBox(width: 10),
          ],
      ],
    );
    return Wrap(
      spacing: Sp.betweenSections,
      runSpacing: Sp.withinGroup,
      children: [
        side('己方', detail.bansAlly, true),
        side('对方', detail.bansEnemy, false),
      ],
    );
  }
}

class _SubjectHeroes extends StatelessWidget {
  const _SubjectHeroes({required this.segments, required this.catalog});
  final List<HeroSegment> segments;
  final Catalog catalog;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(header: true, child: Text('查询对象在本场使用的英雄', style: Ty.section)),
        const SizedBox(height: Sp.withinGroup),
        for (final s in segments)
          Container(
            margin: const EdgeInsets.only(bottom: Sp.withinGroup),
            padding: const EdgeInsets.all(Sp.withinGroup + 4),
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
                    NetImage(
                      catalog.heroIcon(s.hero),
                      size: 26,
                      fallback: s.hero.label,
                    ),
                    const SizedBox(width: 8),
                    Text(s.hero.label, style: Ty.bodyStrong),
                    const SizedBox(width: 12),
                    Text(
                      '使用 ${fmtClock(s.playTimeS)}${s.share == null ? '' : '（占本场 ${fmtPct((s.share ?? 0) * 100, digits: 0)}）'}',
                      style: Ty.num(Ty.meta).copyWith(color: c.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Builder(
                  builder: (context) {
                    final named = s.stats
                        .where((v) => v.stat.name != null)
                        .toList();
                    final unnamed = s.stats.length - named.length;
                    if (named.isEmpty) {
                      return Text(
                        '本场 ${s.stats.length} 项统计，目录里还没有它们的名称。',
                        style: Ty.meta.copyWith(color: c.textSecondary),
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 20,
                          runSpacing: 2,
                          children: [
                            for (final v in named)
                              Text(
                                '${v.stat.name}  ${fmtOne(v.value)}',
                                style: Ty.num(Ty.body),
                              ),
                          ],
                        ),
                        if (unnamed > 0)
                          Text(
                            '另有 $unnamed 项统计目录里没有名称，未显示。',
                            style: Ty.meta.copyWith(color: c.textSecondary),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Rounds extends StatelessWidget {
  const _Rounds({required this.rounds});
  final List<Round> rounds;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(header: true, child: Text('回合', style: Ty.section)),
        const SizedBox(height: Sp.withinGroup),
        Wrap(
          spacing: Sp.betweenGroups,
          runSpacing: 4,
          children: [
            for (final r in rounds)
              Text(
                '第 ${r.index + 1} 回合  ${fmtScore(r.scoreTeam, r.scoreOpponent)}  ${fmtClock(r.durationS)}',
                style: Ty.num(Ty.body).copyWith(color: c.textPrimary),
              ),
          ],
        ),
      ],
    );
  }
}
