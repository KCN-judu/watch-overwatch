import 'package:flutter/material.dart';

import '../../core/gamedata.dart';
import '../../core/hero_stats.dart';
import '../../core/models.dart';
import '../../core/support.dart';
import '../../design/cards.dart';
import '../../design/icons.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';
import '../../state/app_state.dart';
import '../../state/match_view.dart';
import 'peer_bench.dart';
import 'stadium_builds.dart';
import '../../design/net_pic.dart';
import '../../l10n/strings.dart';

/// Second-level page for one hero, laid out like a poster: banner and art up top with
/// the headline numbers set large, then season data, recent matches and the kit.
/// Gaps in the provider's numbers are shown as gaps, with the reason.
class HeroDetailPage extends StatefulWidget {
  const HeroDetailPage({
    super.key,
    required this.workspace,
    required this.hero,
  });
  final PlayerWorkspace workspace;
  final HeroUsage hero;

  @override
  State<HeroDetailPage> createState() => _HeroDetailPageState();
}

class _HeroDetailPageState extends State<HeroDetailPage> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => widget.workspace.loadHeroBoard(),
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final ws = widget.workspace;
    final hero = widget.hero;
    final c = context.c;
    final keys = ws.heroNavKeys;
    final index = keys.indexOf(PlayerWorkspace.heroKey(hero));
    final role = app.catalog.heroRole(hero.hero);
    final recent = [
      for (final m
          in ws.matchesFor(app.mode).value?.matches ?? const <MatchSummary>[])
        if (m.hero?.guid == hero.hero.guid) m,
    ];

    final bar = Row(
      children: [
        AppButton(
          tr.heroes.heroList,
          icon: Icons.arrow_back,
          quiet: true,
          tooltip: tr.heroes.backShortcut,
          onPressed: ws.closeHero,
        ),
        Text('›', style: Ty.body.copyWith(color: c.textSecondary)),
        const SizedBox(width: Sp.withinGroup),
        Expanded(
          child: Text(
            hero.hero.label,
            style: Ty.bodyStrong,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        AppButton(
          tr.compare.compareHero,
          icon: Icons.compare_arrows,
          quiet: true,
          tooltip: tr.compare.compareHeroTip,
          onPressed: () => ws.compareHero(null),
        ),
        const SizedBox(width: Sp.withinGroup),
        if (index >= 0)
          Text(
            tr.heroes.position(index + 1, keys.length),
            style: Ty.num(Ty.meta).copyWith(color: c.textSecondary),
          ),
        IconAction(
          icon: Icons.chevron_left,
          label: tr.heroes.previousHero,
          shortcut: '[',
          onPressed: index > 0 ? () => ws.stepHero(-1) : null,
        ),
        IconAction(
          icon: Icons.chevron_right,
          label: tr.heroes.nextHero,
          shortcut: ']',
          onPressed: index >= 0 && index < keys.length - 1
              ? () => ws.stepHero(1)
              : null,
        ),
      ],
    );

    return FutureBuilder<GameData>(
      future: GameData.load(),
      initialData: GameData.loaded,
      builder: (context, snap) {
        final game = snap.data?.hero(hero.hero.name);
        // The hero's own colour from the game.
        // The hero's colour, kept clear of the page in either theme.
        final accent = legibleOn(game?.color ?? c.accent, c.raised, ratio: 3);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            bar,
            const SizedBox(height: Sp.withinGroup),
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.only(
                  right: Sp.betweenGroups,
                  bottom: 28,
                ),
                children: [
                  _Poster(
                    hero: hero,
                    role: role,
                    game: game,
                    accent: accent,
                    art: app.catalog.heroArt(hero.hero),
                    banner: app.catalog.heroBanner(hero.hero),
                    recentKda: Agg(recent).kda,
                    board: ws.heroBoard.value
                        ?.where(
                          (e) =>
                              e.hero?.guid == hero.hero.guid &&
                              e.queue == hero.queue &&
                              e.rank != null,
                        )
                        .firstOrNull,
                  ),
                  const SizedBox(height: Sp.betweenSections + 8),
                  _SeasonStats(hero: hero, accent: accent, recent: recent),
                  const SizedBox(height: Sp.betweenSections + 8),
                  if (app.mode == Mode.stadium)
                    StadiumBuildsSection(
                      workspace: ws,
                      hero: hero.hero,
                      accent: accent,
                    )
                  else
                    PeerBenchSection(
                      workspace: ws,
                      mode: app.mode,
                      hero: hero.hero,
                      accent: accent,
                    ),
                  const SizedBox(height: Sp.betweenSections + 8),
                  _Recent(
                    workspace: ws,
                    hero: hero,
                    rows: recent,
                    accent: accent,
                  ),
                  if (game != null && game.kit.isNotEmpty) ...[
                    const SizedBox(height: Sp.betweenSections + 8),
                    _Kit(game: game, accent: accent),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---- Poster ---------------------------------------------------------------------

class _Poster extends StatelessWidget {
  const _Poster({
    required this.hero,
    required this.role,
    required this.game,
    required this.accent,
    required this.art,
    required this.banner,
    required this.recentKda,
    this.board,
  });

  /// The hero's place on the provider's hero board, when it has one.
  final HeroBoardEntry? board;
  final HeroUsage hero;
  final Role role;
  final GameHero? game;
  final Color accent;
  final String? art, banner;
  final double? recentKda;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final name = hero.hero.label;
    final ink = c.textPrimary;

    Widget stat(String label, String value, {String? note, Color? color}) =>
        Padding(
          padding: const EdgeInsets.only(right: 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Ty.meta.copyWith(color: c.textSecondary)),
              Text(
                value,
                style: Ty.num(Ty.posterFigure).copyWith(color: color ?? ink),
              ),
              SizedBox(
                height: 16,
                child: note == null
                    ? null
                    : Text(
                        note,
                        style: Ty.meta.copyWith(color: c.textSecondary),
                      ),
              ),
            ],
          ),
        );

    final winColor = hero.winRatePct == null
        ? null
        : (hero.winRatePct! >= 50 ? c.win : c.loss);

    return ClipRect(
      child: SizedBox(
        height: 360,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Colour wash from the hero's own colour.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [
                    accent.withValues(alpha: dark ? 0.55 : 0.40),
                    c.raised,
                  ],
                ),
              ),
            ),
            if (banner != null)
              Opacity(
                opacity: dark ? 0.38 : 0.28,
                child: NetPic(
                  banner!,
                  fit: BoxFit.cover,
                  alignment: Alignment.centerLeft,
                ),
              ),
            // Dense on the right for the type, open on the left for the art.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerRight,
                  end: Alignment.centerLeft,
                  colors: [
                    for (final a in AppColors.posterScrim)
                      c.raised.withValues(alpha: a),
                  ],
                  stops: const [0, 0.5, 0.78],
                ),
              ),
            ),
            // The art, standing on the bottom edge on the left, clear of the banner's own scene.
            Positioned(
              left: 24,
              top: 14,
              bottom: 0,
              width: 400,
              child: HeroPortrait(art, name: name, width: 400, height: 346),
            ),
            Positioned(
              left: 440,
              top: 30,
              bottom: 26,
              right: 36,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 18,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      RoleIcon(role, size: 22, showLabel: true),
                      if (game?.subrole != null)
                        Tooltip(
                          message: game!.subrolePassive ?? '',
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SubroleIcon(name, size: 22),
                              const SizedBox(width: Sp.iconGap),
                              Text(game!.subrole!, style: Ty.bodyStrong),
                            ],
                          ),
                        ),
                      if (hero.queue.label.isNotEmpty)
                        Text(
                          hero.queue.label,
                          style: Ty.body.copyWith(color: c.textSecondary),
                        ),
                      if (board != null)
                        Tooltip(
                          message: tr.heroes.heroBoardTip(
                            board!.matches ?? 0,
                            fmtPct(board!.winRatePct),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.leaderboard_outlined,
                                size: 18,
                                color: accent,
                              ),
                              const SizedBox(width: Sp.iconGap),
                              Text(
                                tr.heroes.heroBoard(
                                  board!.province ?? '',
                                  board!.rank!,
                                ),
                                style: Ty.bodyStrong,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: Sp.withinControl),
                  Semantics(
                    header: true,
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Ty.posterName.copyWith(color: ink),
                    ),
                  ),
                  Container(
                    width: 72,
                    height: 4,
                    margin: const EdgeInsets.only(
                      top: Sp.hairline,
                      bottom: Sp.withinGroup,
                    ),
                    color: accent,
                  ),
                  if (game != null && game!.description.isNotEmpty)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Text(
                        game!.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Ty.body.copyWith(color: c.textSecondary),
                      ),
                    ),
                  const Spacer(),
                  Wrap(
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.end,
                    children: [
                      stat(tr.heroes.matchesLabel, fmtInt(hero.matches)),
                      stat(
                        tr.heroes.winRateLabel,
                        fmtPct(hero.winRatePct),
                        note: hero.matches == null
                            ? null
                            : tr.heroes.winsOfMatches(
                                hero.wins ?? 0,
                                hero.matches!,
                              ),
                        color: winColor,
                      ),
                      stat(
                        tr.heroes.playTimeLabel,
                        hero.playTimeS == null
                            ? missing
                            : fmtPlayTime(hero.playTimeS),
                        note: hero.avgMatchSeconds == null
                            ? null
                            : tr.heroes.avgMatchTime(
                                fmtClock(hero.avgMatchSeconds),
                              ),
                      ),
                      if (hero.kda != null)
                        stat('KDA', fmtTwo(hero.kda))
                      else
                        stat(
                          'KDA',
                          fmtTwo(recentKda),
                          note: recentKda == null
                              ? tr.heroes.notProvided
                              : tr.heroes.recentMatchesNote,
                        ),
                      stat(
                        tr.heroes.proficiency,
                        hero.heroLevel == null ? missing : '${hero.heroLevel}',
                        note: hero.heroLevel == null
                            ? tr.heroes.notProvided
                            : null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // The proficiency badge as a stamp on the art.
            if (hero.heroLevel != null)
              Positioned(
                left: 36,
                top: 24,
                child: LevelBadge(hero.heroLevel, size: 40),
              ),
          ],
        ),
      ),
    );
  }
}

// ---- Season stats -----------------------------------------------------------------

enum _Group { combat, damage, healing, defense, hero }

String _groupTitle(_Group g) => switch (g) {
  _Group.combat => tr.heroes.groupCombat,
  _Group.damage => tr.heroes.groupDamage,
  _Group.healing => tr.heroes.groupHealing,
  _Group.defense => tr.heroes.groupDefense,
  _Group.hero => tr.heroes.groupHero,
};

_Group _groupOf(String n) {
  if (n.contains('阵亡') ||
      n.contains('助攻') ||
      n.contains('最后一击') ||
      n.contains('单独消灭') ||
      n.endsWith('消灭')) {
    return _Group.combat;
  }
  if (n.contains('承受') || n.contains('阻挡') || n.contains('减免')) {
    return _Group.defense;
  }
  if (n.contains('治疗') || n.contains('拯救') || n.contains('净化')) {
    return _Group.healing;
  }
  if (n.contains('伤害') || n.contains('命中') || n.contains('暴击')) {
    return _Group.damage;
  }
  return _Group.hero;
}

String _fmtStat(String name, double v) => fmtHeroStat(name, v);

class _SeasonStats extends StatelessWidget {
  const _SeasonStats({
    required this.hero,
    required this.accent,
    required this.recent,
  });
  final HeroUsage hero;
  final Color accent;
  final List<MatchSummary> recent;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final catalog = AppScope.of(context).catalog;
    final rows = HeroStats.rows(hero, catalog, recent);

    // The game's stat list has no damage-mitigation stat; it comes from matches.
    final mit = HeroStats.mitigation10(hero, catalog, recent);
    final mitPerMatch = Agg(recent).mean['mitigation'];
    if (mit != null) {
      rows.add(
        HeroStatRow('mitigation', '阻挡伤害')
          ..per10 = mit
          ..perMatch = mitPerMatch ?? 0
          ..per10Source = mitPerMatch == null || mitPerMatch == 0
              ? StatSource.zero
              : StatSource.recent
          ..perMatchSource = mitPerMatch == null || mitPerMatch == 0
              ? StatSource.zero
              : StatSource.recent,
      );
    }
    // The catalog registers a few stats twice under one name; show each once.
    final seen = <String>{};
    rows.removeWhere(
      (r) => !seen.add('${r.name}|${r.perMatch?.toStringAsFixed(1)}'),
    );
    final unnamed =
        hero.per10min.where((v) => v.stat.name == null).length +
        hero.perMatch.where((v) => v.stat.name == null).length;

    Color? stripe(HeroStatRow r) {
      final g = _groupOf(r.name);
      if (g == _Group.defense) return c.statMitigation;
      if (g == _Group.healing &&
          r.name.contains('治疗量') &&
          !r.name.contains('承受')) {
        return c.statHealing;
      }
      if (g == _Group.damage &&
          r.name.contains('伤害') &&
          !r.name.contains('承受')) {
        return c.statDamage;
      }
      return null;
    }

    String? why(StatSource s) => switch (s) {
      StatSource.derived => tr.heroes.sourceDerived,
      StatSource.recent => tr.heroes.sourceRecent,
      StatSource.zero => tr.heroes.sourceZero,
      StatSource.provider => null,
    };

    final groups = [
      for (final g in _Group.values)
        (
          g,
          [
            for (final r in rows)
              if (_groupOf(r.name) == g) r,
          ],
        ),
    ].where((e) => e.$2.isNotEmpty).toList();

    // One card per figure. A figure with no value for this basis (a hit rate has no
    // per-10-minutes reading) has no card there. Healing is the sum of healing others
    // and healing itself, and its bar shows how much of it was the hero's own.
    Widget card(HeroStatRow r, bool per10) {
      final v = per10 ? r.per10 : r.perMatch;
      final src = per10 ? r.per10Source : r.perMatchSource;
      final self = per10 ? r.partPer10 : r.partPerMatch;
      final approx = src == StatSource.derived || src == StatSource.recent;
      final split = v != null && v > 0 && self != null
          ? self.clamp(0.0, v).toDouble()
          : null;
      return StatCard(
        label: r.name,
        value: '${approx ? '≈ ' : ''}${_fmtStat(r.name, v!)}',
        accent: stripe(r) ?? accent,
        share: split == null ? null : split / v,
        caption: split == null
            ? null
            : tr.heroes.splitCaption(
                r.partName,
                _fmtStat(r.name, split),
                fmtPct(split / v * 100, digits: 0),
                r.restName,
                _fmtStat(r.name, v - split),
              ),
        tooltip: why(src),
      );
    }

    Widget partition(String title, bool per10) {
      final shown = [
        for (final (g, list) in groups)
          (
            g,
            [
              for (final r in list)
                if ((per10 ? r.per10 : r.perMatch) != null) r,
            ],
          ),
      ].where((e) => e.$2.isNotEmpty);
      return FoldSection(
        title: title,
        accent: accent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (g, list) in shown) ...[
              Padding(
                padding: const EdgeInsets.only(
                  top: Sp.withinGroup,
                  bottom: Sp.iconGap,
                ),
                child: Text(
                  _groupTitle(g),
                  style: Ty.meta.copyWith(color: c.textSecondary),
                ),
              ),
              CardGrid(
                minWidth: 200,
                height:
                    list.any(
                      (r) => (per10 ? r.partPer10 : r.partPerMatch) != null,
                    )
                    ? 124
                    : 88,
                [for (final r in list) card(r, per10)],
              ),
            ],
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          tr.heroes.seasonStats,
          accent: accent,
          info: tr.heroes.seasonStatsInfo,
        ),
        const SizedBox(height: Sp.withinGroup + 2),
        if (rows.isEmpty)
          Text(
            tr.heroes.noStats,
            style: Ty.body.copyWith(color: c.textSecondary),
          )
        else ...[
          partition(tr.heroes.per10, true),
          const SizedBox(height: Sp.betweenGroups),
          partition(tr.heroes.perMatch, false),
        ],
        if (unnamed > 0)
          Padding(
            padding: const EdgeInsets.only(top: Sp.withinGroup),
            child: Text(
              tr.heroes.unnamedStats(unnamed),
              style: Ty.meta.copyWith(color: c.textSecondary),
            ),
          ),
      ],
    );
  }
}

// ---- Recent matches with this hero --------------------------------------------------

class _Recent extends StatelessWidget {
  const _Recent({
    required this.workspace,
    required this.hero,
    required this.rows,
    required this.accent,
  });
  final PlayerWorkspace workspace;
  final HeroUsage hero;
  final List<MatchSummary> rows;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = context.c;
    final mode = app.mode;
    final total = workspace.matchesFor(mode).value?.matches.length ?? 0;
    final a = Agg(rows);
    String mean(String f) => a.mean[f] == null ? missing : fmtInt(a.mean[f]);
    final ids = [for (final m in rows) m.id];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          tr.heroes.recentMatches,
          accent: accent,
          info: tr.heroes.recentInfo(total, hero.hero.label),
        ),
        const SizedBox(height: Sp.withinGroup + 2),
        if (rows.isEmpty)
          Text(
            tr.heroes.recentEmpty(total, hero.hero.label),
            style: Ty.body.copyWith(color: c.textSecondary),
          )
        else ...[
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              KpiTile(tr.heroes.matchesLabel, '${a.matches}'),
              KpiTile(
                tr.heroes.winRateLabel,
                fmtPct(a.winRatePct),
                note: tr.heroes.winLoss(a.wins, a.losses),
              ),
              KpiTile('KDA', fmtTwo(a.kda)),
              KpiTile(tr.heroes.avgKills, mean('kills')),
              KpiTile(tr.heroes.avgDeaths, mean('deaths')),
              KpiTile(tr.heroes.avgAssists, mean('assists')),
              KpiTile(tr.heroes.avgDamage, mean('damage'), color: c.statDamage),
              KpiTile(
                tr.heroes.avgHealing,
                mean('healing'),
                color: c.statHealing,
              ),
              KpiTile(
                tr.heroes.avgMitigation,
                mean('mitigation'),
                color: c.statMitigation,
              ),
            ],
          ),
          const SizedBox(height: Sp.betweenGroups),
          for (final m in rows.take(12))
            InkWell(
              onTap: () async {
                await app.setTab('matches');
                workspace.openMatch(mode, m.id, ids);
              },
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: Sp.withinGroup),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: c.grid)),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 48,
                      child: OutcomeMark(m.outcome, textless: true),
                    ),
                    SizedBox(
                      width: 80,
                      child: Text(
                        fmtScore(m.scoreTeam, m.scoreOpponent),
                        style: Ty.num(Ty.bodyStrong),
                      ),
                    ),
                    MapThumb.row(app.catalog.mapImage(m.map)),
                    const SizedBox(width: Sp.betweenItems),
                    Expanded(
                      child: Text(
                        m.map?.label ?? tr.common.unknownMap,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      fmtDateTime(m.startedAtMs),
                      style: Ty.num(Ty.meta).copyWith(color: c.textSecondary),
                    ),
                    SizedBox(
                      width: 110,
                      child: Text(
                        fmtKda(m.stats),
                        textAlign: TextAlign.right,
                        style: Ty.num(Ty.body),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (rows.length > 12)
            Padding(
              padding: const EdgeInsets.only(top: Sp.iconGap),
              child: Text(
                tr.heroes.moreMatches(rows.length - 12),
                style: Ty.meta.copyWith(color: c.textSecondary),
              ),
            ),
        ],
      ],
    );
  }
}

// ---- Kit: abilities and perks ---------------------------------------------------------

class _Kit extends StatelessWidget {
  const _Kit({required this.game, required this.accent});
  final GameHero game;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Widget card({
      required String? asset,
      required String name,
      String? tag,
      required String description,
    }) => InfoCard(
      asset: asset,
      name: name,
      tag: tag,
      description: description,
      accent: accent,
    );

    final minor = game.perks.take(2).toList();
    final major = game.perks.skip(2).toList();
    Widget perkRow(String title, List<GamePerk> perks) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: Sp.iconGap),
          child: Text(title, style: Ty.meta.copyWith(color: c.textSecondary)),
        ),
        CardGrid([
          for (final p in perks)
            PerkCard(
              asset: p.asset,
              name: p.name,
              description: p.description,
              accent: accent,
            ),
        ]),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          tr.heroes.abilities,
          accent: accent,
          info: tr.heroes.abilitiesInfo,
        ),
        const SizedBox(height: Sp.withinGroup + 2),
        CardGrid([
          for (final a in game.kit)
            card(
              asset: a.asset,
              name: a.name,
              tag: a.categoryLabel,
              description: a.description,
            ),
        ]),
        if (game.perks.length >= 4) ...[
          const SizedBox(height: Sp.betweenSections + 8),
          SectionHeader(tr.heroes.perks, accent: accent),
          const SizedBox(height: Sp.withinGroup + 2),
          perkRow(tr.heroes.minorPerks, minor),
          const SizedBox(height: Sp.betweenGroups),
          perkRow(tr.heroes.majorPerks, major),
        ],
      ],
    );
  }
}

/// Equal-size cards in as many equal columns as fit: same width, same height, so the
