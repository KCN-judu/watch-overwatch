import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/stadium.dart';
import '../../core/support.dart';
import '../../design/cards.dart';
import '../../design/icons.dart';
import '../../design/net_pic.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';
import '../../state/app_state.dart';
import '../../l10n/strings.dart';
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
          tr.matches.matchList,
          icon: Icons.arrow_back,
          quiet: true,
          tooltip: onPlayerPage ? null : tr.matches.backShortcut,
          onPressed: ws.closeMatch,
        ),
        Text('›', style: Ty.body.copyWith(color: c.textSecondary)),
        const SizedBox(width: Sp.withinGroup),
        Expanded(
          child: onPlayerPage
              ? Row(
                  children: [
                    Flexible(
                      child: AppButton(
                        title,
                        quiet: true,
                        tooltip: tr.matches.backToMatchTip,
                        onPressed: ws.closePlayer,
                      ),
                    ),
                    Text('›', style: Ty.body.copyWith(color: c.textSecondary)),
                    const SizedBox(width: Sp.withinGroup),
                    Flexible(
                      child: Text(
                        player.name ?? tr.common.unknownPlayer,
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
            tr.matches.playerPosition(playerIndex + 1, playerCount),
            style: Ty.num(Ty.meta).copyWith(color: c.textSecondary),
          )
        else if (index >= 0)
          Text(
            tr.matches.matchPosition(index + 1, ws.navIds.length),
            style: Ty.num(Ty.meta).copyWith(color: c.textSecondary),
          ),
        IconAction(
          icon: Icons.chevron_left,
          label: onPlayerPage
              ? tr.matches.previousPlayer
              : tr.matches.previousMatch,
          shortcut: '[',
          onPressed: onPlayerPage
              ? (playerIndex > 0 ? () => ws.stepOpenPlayer(-1) : null)
              : (index > 0 ? () => ws.stepMatch(-1) : null),
        ),
        IconAction(
          icon: Icons.chevron_right,
          label: onPlayerPage ? tr.matches.nextPlayer : tr.matches.nextMatch,
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
        what: tr.matches.cannotReadDetail,
        error: load.error!,
        onRetry: () => ws.loadDetail(mode, id),
        extra: [AppButton(tr.matches.backToList, onPressed: ws.closeMatch)],
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
    // The page's own layout (result line, two team tables), in the shared skeleton.
    Widget block(double h) => Padding(
      padding: const EdgeInsets.only(bottom: Sp.betweenGroups),
      child: Skeleton(height: h, radius: 0),
    );
    return Semantics(
      label: tr.matches.readingDetail,
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
      padding: const EdgeInsets.only(right: scrollGutter),
      children: [
        // Result line
        Padding(
          padding: const EdgeInsets.only(bottom: Sp.betweenGroups),
          child: Wrap(
            spacing: Sp.betweenGroups,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              MapThumb.large(app.catalog.mapImage(detail.map)),
              Semantics(
                header: true,
                child: Text(
                  detail.map?.label ?? tr.common.unknownMap,
                  style: Ty.page,
                ),
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
                  tr.matches.duration(fmtClock(detail.durationS)),
                  style: Ty.num(Ty.body).copyWith(color: c.textSecondary),
                ),
              if (detail.outcomeFromScore)
                Tooltip(
                  message: tr.matches.outcomeFromScoreTip,
                  child: Text(
                    tr.matches.outcomeFromScore,
                    style: Ty.meta.copyWith(color: c.textSecondary),
                  ),
                ),
              if (refreshing) const RefreshingChip(),
            ],
          ),
        ),
        TeamTable(
          title: tr.common.ally,
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
          title: tr.common.enemy,
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
          tr.matches.openPlayerHint,
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
          _Rounds(rounds: detail.rounds, steps: detail.stadiumTimeline),
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
        const SizedBox(width: Sp.withinGroup),
        Text(tr.matches.bans, style: Ty.meta.copyWith(color: c.textSecondary)),
        const SizedBox(width: Sp.withinGroup),
        if (heroes.isEmpty)
          Text(missing)
        else
          for (final h in heroes) ...[
            NetImage(catalog.heroIcon(h), size: 22, fallback: h.label),
            const SizedBox(width: Sp.withinControl),
            Text(h.label, style: Ty.body),
            const SizedBox(width: Sp.withinGroup),
          ],
      ],
    );
    return Wrap(
      spacing: Sp.betweenSections,
      runSpacing: Sp.withinGroup,
      children: [
        side(tr.common.ally, detail.bansAlly, true),
        side(tr.common.enemy, detail.bansEnemy, false),
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
        SectionHeader(tr.matches.subjectHeroes),
        const SizedBox(height: SectionHeader.below),
        for (final s in segments) ...[
          Panel(
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
                    const SizedBox(width: Sp.withinGroup),
                    Text(s.hero.label, style: Ty.bodyStrong),
                    const SizedBox(width: Sp.betweenItems),
                    Text(
                      s.share == null
                          ? tr.matches.heroPlayTime(fmtClock(s.playTimeS))
                          : tr.matches.heroPlayTimeShare(
                              fmtClock(s.playTimeS),
                              fmtPct(s.share! * 100, digits: 0),
                            ),
                      style: Ty.num(Ty.meta).copyWith(color: c.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: Sp.iconGap),
                Builder(
                  builder: (context) {
                    final named = s.stats
                        .where((v) => v.stat.name != null)
                        .toList();
                    final unnamed = s.stats.length - named.length;
                    if (named.isEmpty) {
                      return Text(
                        tr.matches.statsAllUnnamed(s.stats.length),
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
                            tr.matches.statsSomeUnnamed(unnamed),
                            style: Ty.meta.copyWith(color: c.textSecondary),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: Sp.withinGroup),
        ],
      ],
    );
  }
}

class _Rounds extends StatelessWidget {
  const _Rounds({required this.rounds, this.steps = const []});
  final List<Round> rounds;

  /// Stadium: what the player took each round and how the round went.
  final List<RoundStep> steps;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final catalog = AppScope.of(context).catalog;
    String line(Round r) => tr.matches.round(
      r.index + 1,
      fmtScore(r.scoreTeam, r.scoreOpponent),
      fmtClock(r.durationS),
    );
    if (steps.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(tr.matches.rounds),
          const SizedBox(height: Sp.withinGroup),
          Wrap(
            spacing: Sp.betweenGroups,
            runSpacing: 4,
            children: [
              for (final r in rounds)
                Text(
                  line(r),
                  style: Ty.num(Ty.body).copyWith(color: c.textPrimary),
                ),
            ],
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(tr.matches.rounds, info: tr.matches.timelineTip),
        const SizedBox(height: SectionHeader.below),
        for (final (i, r) in rounds.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Sp.withinControl),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 24,
                  child: switch (i < steps.length ? steps[i].won : null) {
                    true => const OutcomeMark(Outcome.win),
                    false => const OutcomeMark(Outcome.loss),
                    null => const SizedBox.shrink(),
                  },
                ),
                SizedBox(
                  width: 220,
                  child: Text(
                    line(r),
                    style: Ty.num(Ty.body).copyWith(color: c.textPrimary),
                  ),
                ),
                Expanded(
                  child: Wrap(
                    spacing: Sp.withinGroup,
                    runSpacing: 4,
                    children: [
                      if (i < steps.length)
                        for (final (e, kind) in [
                          for (final e in steps[i].powers)
                            (e, tr.matches.power),
                          for (final e in steps[i].items) (e, tr.matches.item),
                        ])
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              NetImage(
                                catalog.stadiumUpgrade(e)?.icon,
                                size: 20,
                                fallback: '',
                              ),
                              const SizedBox(width: Sp.withinControl),
                              Text(
                                catalog.stadiumUpgrade(e)?.name ?? e.label,
                                style: Ty.body,
                              ),
                              Text(
                                ' $kind',
                                style: Ty.meta.copyWith(color: c.textSecondary),
                              ),
                            ],
                          ),
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
