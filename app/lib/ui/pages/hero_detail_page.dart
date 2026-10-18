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
import '../../design/net_pic.dart';

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
          '英雄列表',
          icon: Icons.arrow_back,
          quiet: true,
          tooltip: 'Esc 或 Alt+←',
          onPressed: ws.closeHero,
        ),
        Text('›', style: Ty.body.copyWith(color: c.textSecondary)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            hero.hero.label,
            style: Ty.bodyStrong,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (index >= 0)
          Text(
            '第 ${index + 1} / ${keys.length} 位',
            style: Ty.num(Ty.meta).copyWith(color: c.textSecondary),
          ),
        IconAction(
          icon: Icons.chevron_left,
          label: '上一位英雄',
          shortcut: '[',
          onPressed: index > 0 ? () => ws.stepHero(-1) : null,
        ),
        IconAction(
          icon: Icons.chevron_right,
          label: '下一位英雄',
          shortcut: ']',
          onPressed: index >= 0 && index < keys.length - 1
              ? () => ws.stepHero(1)
              : null,
        ),
      ],
    );

    return FutureBuilder<GameData>(
      future: GameData.load(),
      builder: (context, snap) {
        final game = snap.data?.hero(hero.hero.name);
        // The hero's own colour from the game.
        final accent = game?.color ?? c.accent;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            bar,
            const SizedBox(height: Sp.withinGroup),
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.only(right: 16, bottom: 28),
                children: [
                  _Poster(
                    hero: hero,
                    role: role,
                    game: game,
                    accent: accent,
                    art: app.catalog.heroArt(hero.hero),
                    banner: app.catalog.heroBanner(hero.hero),
                    recentKda: Agg(recent).kda,
                  ),
                  const SizedBox(height: Sp.betweenSections + 8),
                  _SeasonStats(hero: hero, accent: accent, recent: recent),
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
  });
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
    final losses = (hero.matches ?? 0) - (hero.wins ?? 0);
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
                style: Ty.num(Ty.figure).copyWith(
                  fontSize: 34,
                  height: 1.1,
                  fontWeight: FontWeight.w700,
                  color: color ?? ink,
                ),
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

    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.container),
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
                    c.raised.withValues(alpha: 0.96),
                    c.raised.withValues(alpha: 0.78),
                    c.raised.withValues(alpha: 0.0),
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
                              const SizedBox(width: 6),
                              Text(game!.subrole!, style: Ty.bodyStrong),
                            ],
                          ),
                        ),
                      if (hero.queue.label.isNotEmpty)
                        Text(
                          hero.queue.label,
                          style: Ty.body.copyWith(color: c.textSecondary),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Semantics(
                    header: true,
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: Ty.family,
                        fontFamilyFallback: Ty.fallback,
                        fontSize: 68,
                        height: 1.12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1,
                        color: ink,
                      ),
                    ),
                  ),
                  Container(
                    width: 72,
                    height: 4,
                    margin: const EdgeInsets.only(top: 2, bottom: 10),
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
                      stat('场次', fmtInt(hero.matches)),
                      stat(
                        '胜率',
                        fmtPct(hero.winRatePct),
                        note: hero.matches == null
                            ? null
                            : '${hero.wins ?? 0} 胜 $losses 负',
                        color: winColor,
                      ),
                      stat(
                        '使用时长',
                        hero.playTimeS == null
                            ? missing
                            : '${(hero.playTimeS! / 3600).toStringAsFixed(1)} 小时',
                        note: hero.avgMatchSeconds == null
                            ? null
                            : '场均 ${fmtClock(hero.avgMatchSeconds)}',
                      ),
                      if (hero.kda != null)
                        stat('KDA', fmtTwo(hero.kda))
                      else
                        stat(
                          'KDA',
                          fmtTwo(recentKda),
                          note: recentKda == null ? '上游没有提供' : '近期对局',
                        ),
                      stat(
                        '熟练度',
                        hero.heroLevel == null ? missing : '${hero.heroLevel}',
                        note: hero.heroLevel == null ? '上游没有提供' : null,
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

const _groupTitles = {
  _Group.combat: '战斗',
  _Group.damage: '伤害与命中',
  _Group.healing: '治疗与支援',
  _Group.defense: '防护',
  _Group.hero: '英雄特色',
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

String _fmtStat(String name, double v) {
  if (name.contains('游戏时间')) return fmtClock(v);
  // Hit rates arrive as fractions of one.
  if (name.endsWith('率') && v <= 1.0001) return fmtPct(v * 100, digits: 0);
  return v.abs() >= 100 ? fmtInt(v) : fmtOne(v);
}

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
      StatSource.derived => '上游没给这一项，由每场平均 × 600 ÷ 场均时长推算',
      StatSource.recent => '上游没给这一项，取自已读取的近期对局',
      StatSource.zero => '这个英雄能产出这项数据，但上游没有记录，按 0 计',
      StatSource.provider => null,
    };

    Widget cell(HeroStatRow r, double? v, StatSource src) => SizedBox(
      width: 130,
      child: v == null
          ? Tooltip(
              message: '这个英雄无法产出这项数据',
              child: Text(
                missing,
                textAlign: TextAlign.right,
                style: Ty.num(Ty.body).copyWith(color: c.textSecondary),
              ),
            )
          : Tooltip(
              message: why(src) ?? '',
              child: Text(
                '${src == StatSource.derived || src == StatSource.recent ? '≈ ' : ''}${_fmtStat(r.name, v)}',
                textAlign: TextAlign.right,
                style: Ty.num(Ty.body).copyWith(
                  color: src == StatSource.provider
                      ? c.textPrimary
                      : c.textSecondary,
                  fontWeight: src == StatSource.provider
                      ? FontWeight.w600
                      : FontWeight.w400,
                ),
              ),
            ),
    );

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AccentTitle(
          '赛季数据',
          accent: accent,
          info:
              '整个赛季的累计，来自大神。上游常漏项，缺的按这个英雄能产出的内容补全：≈ 是推算或取自近期对局，灰色 0 是上游没有记录，— 是这个英雄无法产出。',
        ),
        const SizedBox(height: Sp.withinGroup + 2),
        if (rows.isEmpty)
          Text('没有这个英雄的统计项。', style: Ty.body.copyWith(color: c.textSecondary))
        else
          Container(
            padding: const EdgeInsets.fromLTRB(
              Sp.betweenGroups + 4,
              Sp.withinGroup,
              Sp.betweenGroups + 4,
              Sp.withinGroup,
            ),
            decoration: BoxDecoration(
              color: c.raised,
              borderRadius: BorderRadius.circular(Radii.container),
              border: Border.all(color: c.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Spacer(),
                    for (final h in const ['每 10 分钟', '每场平均'])
                      SizedBox(
                        width: 130,
                        child: Text(
                          h,
                          textAlign: TextAlign.right,
                          style: Ty.meta.copyWith(color: c.textSecondary),
                        ),
                      ),
                  ],
                ),
                for (final (g, list) in groups) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 14, bottom: 4),
                    child: Text(
                      _groupTitles[g]!,
                      style: Ty.bodyStrong.copyWith(color: accent),
                    ),
                  ),
                  for (final r in list)
                    Container(
                      height: 34,
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: c.grid)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 3,
                            height: 18,
                            margin: const EdgeInsets.only(right: 10),
                            color: stripe(r) ?? Colors.transparent,
                          ),
                          Expanded(
                            child: Text(
                              r.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          cell(r, r.per10, r.per10Source),
                          cell(r, r.perMatch, r.perMatchSource),
                        ],
                      ),
                    ),
                ],
                if (unnamed > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      '另有 $unnamed 项统计目录里没有名称，未显示。',
                      style: Ty.meta.copyWith(color: c.textSecondary),
                    ),
                  ),
              ],
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
        AccentTitle(
          '近期对局',
          accent: accent,
          info: '已读取的 $total 场里你用${hero.hero.label}打的。平均值来自这些对局，不是赛季累计。',
        ),
        const SizedBox(height: Sp.withinGroup + 2),
        if (rows.isEmpty)
          Text(
            '已读取的 $total 场里没有用${hero.hero.label}打的。到“对局”页读取更多。',
            style: Ty.body.copyWith(color: c.textSecondary),
          )
        else ...[
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              KpiTile('场次', '${a.matches}'),
              KpiTile(
                '胜率',
                fmtPct(a.winRatePct),
                note: '${a.wins} 胜 ${a.losses} 负',
              ),
              KpiTile('KDA', fmtTwo(a.kda)),
              KpiTile('场均消灭', mean('kills')),
              KpiTile('场均阵亡', mean('deaths')),
              KpiTile('场均助攻', mean('assists')),
              KpiTile('场均伤害', mean('damage'), color: c.statDamage),
              KpiTile('场均治疗', mean('healing'), color: c.statHealing),
              KpiTile('场均阻挡', mean('mitigation'), color: c.statMitigation),
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
                padding: const EdgeInsets.symmetric(horizontal: 8),
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
                    MapThumb(
                      app.catalog.mapImage(m.map),
                      width: 60,
                      height: 34,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        m.map?.label ?? '未知地图',
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
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '还有 ${rows.length - 12} 场，在“对局”页筛选这个英雄查看。',
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
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(title, style: Ty.meta.copyWith(color: c.textSecondary)),
        ),
        CardGrid([
          for (final p in perks)
            card(asset: p.asset, name: p.name, description: p.description),
        ]),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AccentTitle(
          '技能',
          accent: accent,
          info: '来自本机安装的游戏资料（国服 2.25），名称和说明与游戏内一致。',
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
          AccentTitle('威能', accent: accent),
          const SizedBox(height: Sp.withinGroup + 2),
          perkRow('一级威能（二选一）', minor),
          const SizedBox(height: Sp.betweenGroups),
          perkRow('二级威能（二选一）', major),
        ],
      ],
    );
  }
}

/// Equal-size cards in as many equal columns as fit: same width, same height, so the
