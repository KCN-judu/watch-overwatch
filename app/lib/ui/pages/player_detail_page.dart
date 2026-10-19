import 'package:flutter/material.dart';

import '../../core/gamedata.dart';
import '../../core/models.dart';
import '../../core/support.dart';
import '../../design/cards.dart';
import '../../design/icons.dart';
import '../../design/net_pic.dart';
import '../../design/tokens.dart';

/// One player of a match, as a page of cards: who they are, how they played, the Fleta
/// index, their perks, who they queued with and who endorsed them.
class PlayerDetailPage extends StatelessWidget {
  const PlayerDetailPage({
    super.key,
    required this.detail,
    required this.player,
    required this.ally,
    required this.catalog,
    required this.ratingsLoading,
  });
  final MatchDetail detail;
  final Participant player;

  /// Whether the player is on the queried player's own team.
  final bool ally;
  final Catalog catalog;

  /// The ranks of the match's players are still being looked up.
  final bool ratingsLoading;

  List<Participant> get _team => ally ? detail.allies : detail.enemies;

  /// What `value` makes up of the team's total, when both are known and the total is not 0.
  double? _teamShare(double? Function(StatLine) of) {
    final mine = of(player.stats);
    final total = _team.fold<double>(0, (s, p) => s + (of(p.stats) ?? 0));
    if (mine == null || total <= 0) return null;
    return mine / total;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final hero = player.hero;
    final game = GameData.load();
    final heroColor = c.accent;
    final portrait = catalog.heroPortrait(hero);
    final s = player.stats;
    final name = player.name ?? '未知玩家';

    String shareText(double? share) =>
        share == null ? '' : '占本队 ${fmtPct(share * 100, digits: 0)}';

    final kda = (s.kills != null && s.assists != null && (s.deaths ?? 0) > 0)
        ? fmtOne((s.kills! + s.assists!) / s.deaths!)
        : missing;

    Widget stat(
      String label,
      double? value, {
      double? Function(StatLine)? of,
      String? tooltip,
    }) {
      final share = of == null ? null : _teamShare(of);
      return StatCard(
        label: label,
        value: fmtInt(value),
        accent: heroColor,
        share: share,
        caption: share == null ? null : shareText(share),
        tooltip: tooltip,
      );
    }

    final teamFinals = _team.fold<double>(
      0,
      (sum, p) => sum + (p.stats.finalBlows ?? 0),
    );

    Widget header() => Container(
      padding: const EdgeInsets.all(Sp.betweenGroups),
      decoration: BoxDecoration(
        color: c.raised,
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.control),
            child: portrait == null
                ? SizedBox(
                    width: 72,
                    height: 72,
                    child: Center(child: RoleIcon(player.role, size: 28)),
                  )
                : NetPic(
                    portrait,
                    width: 72,
                    height: 72,
                    fit: BoxFit.cover,
                    error: SizedBox(
                      width: 72,
                      height: 72,
                      child: Center(child: RoleIcon(player.role, size: 28)),
                    ),
                  ),
          ),
          const SizedBox(width: Sp.betweenGroups),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: Ty.page, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      ally ? '己方' : '对方',
                      style: Ty.bodyStrong.copyWith(
                        color: ally ? c.ally : c.enemy,
                      ),
                    ),
                    if (player.isSubject)
                      Text(
                        '查询对象',
                        style: Ty.body.copyWith(color: c.textSecondary),
                      ),
                    RoleIcon(player.role, size: 16, showLabel: true),
                    Text(hero?.label ?? '未知英雄', style: Ty.body),
                    ratingsLoading &&
                            player.rank == null &&
                            player.careerRank == null
                        ? Text(
                            '段位查询中',
                            style: Ty.body.copyWith(color: c.textSecondary),
                          )
                        : RankBadge(
                            player.rank ?? player.careerRank,
                            catalog: catalog,
                            stadium:
                                detail.mode == Mode.stadium &&
                                player.rank != null,
                            current:
                                player.rank == null &&
                                player.careerRank != null,
                            otherRoles:
                                player.rank == null && player.careerOtherRoles,
                            showText: true,
                          ),
                    if (player.suspended)
                      Tooltip(
                        message: '这个账号正处于处罚或风险状态。',
                        child: Text(
                          '账号受限',
                          style: Ty.body.copyWith(color: c.warning),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );

    // Names of the match's players for a list of bnet ids; the ones not in the match
    // are counted, not named.
    String peopleText(List<String> ids, String none) {
      if (ids.isEmpty) return none;
      final byId = {
        for (final p in [...detail.allies, ...detail.enemies])
          if (p.bnetId != null) p.bnetId!: p.name ?? '未知玩家',
      };
      final names = [for (final id in ids) ?byId[id]];
      final rest = ids.length - names.length;
      return [
        if (names.isNotEmpty) names.join('、'),
        if (rest > 0) '另有 $rest 名不在这场对局里',
      ].join('；');
    }

    return FutureBuilder<GameData>(
      future: game,
      builder: (context, snapshot) {
        final gameHero = snapshot.data?.hero(hero?.label);
        final perks = <Widget>[
          for (final pick in player.perks)
            () {
              GamePerk? info;
              for (final g in gameHero?.perks ?? const <GamePerk>[]) {
                if (g.name == pick.perk.label) info = g;
              }
              return PerkCard(
                name: pick.perk.label,
                level: pick.level,
                description: info?.description ?? '',
                asset: info?.asset,
                fallbackIconUrl: catalog.perkIcon(pick.perk),
                accent: heroColor,
              );
            }(),
        ];
        final stadium = player.stadium;
        return ListView(
          padding: const EdgeInsets.only(right: 12),
          children: [
            header(),
            const SizedBox(height: Sp.betweenSections),
            AccentTitle(
              '本场数据',
              accent: heroColor,
              info: '占本队的比例按本队 5 人的合计算；— 表示上游没有提供，不等于 0。',
            ),
            const SizedBox(height: Sp.withinGroup + 2),
            CardGrid(minWidth: 200, height: 124, [
              stat('消灭', s.kills, of: (l) => l.kills),
              stat('助攻', s.assists, of: (l) => l.assists),
              stat('阵亡', s.deaths, of: (l) => l.deaths),
              StatCard(
                label: 'KDA',
                value: kda,
                accent: heroColor,
                caption: '（消灭 + 助攻）÷ 阵亡',
              ),
              stat('伤害', s.damage, of: (l) => l.damage),
              stat('治疗', s.healing, of: (l) => l.healing),
              stat('阻挡', s.mitigation, of: (l) => l.mitigation),
              stat('最后一击', s.finalBlows, of: (l) => l.finalBlows),
              stat('单独消灭', s.soloKills),
              stat('承受伤害', s.damageTaken),
              stat('承受治疗', s.healingTaken),
              StatCard(
                label: '目标争夺',
                value: s.objectiveTimeS == null
                    ? missing
                    : fmtClock(s.objectiveTimeS),
                accent: heroColor,
              ),
            ]),
            const SizedBox(height: Sp.betweenSections),
            AccentTitle(
              'Fleta 指数',
              accent: heroColor,
              info:
                  '最后一击 ÷（本队最后一击合计 × 0.5）× 100%。100% 表示拿下了本队一半的最后一击；'
                  '越高，说明这支队伍的击杀越多是由他收尾的。只看这一场、只和本队比，不分职责，'
                  '辅助和重装通常偏低，输出偏高。',
            ),
            const SizedBox(height: Sp.withinGroup + 2),
            CardGrid(minWidth: 320, height: 124, [
              StatCard(
                label: 'Fleta 指数',
                value: player.fleta == null
                    ? missing
                    : fmtPct(player.fleta, digits: 1),
                accent: heroColor,
                share: player.fleta == null ? null : player.fleta! / 200,
                caption: player.fleta == null
                    ? '没有最后一击数据，或本队没有最后一击'
                    : '最后一击 ${fmtInt(s.finalBlows)} ÷（本队 ${fmtInt(teamFinals)} × 0.5）',
              ),
            ]),
            if (perks.isNotEmpty) ...[
              const SizedBox(height: Sp.betweenSections),
              AccentTitle('威能', accent: heroColor),
              const SizedBox(height: Sp.withinGroup + 2),
              CardGrid(perks),
            ],
            const SizedBox(height: Sp.betweenSections),
            AccentTitle('组队与点赞', accent: heroColor),
            const SizedBox(height: Sp.withinGroup + 2),
            CardGrid([
              InfoCard(
                name: '组队',
                description: player.partyBnetIds.isEmpty
                    ? '没有组队信息'
                    : '与 ${player.partyBnetIds.length} 名玩家组队：${peopleText(player.partyBnetIds, '')}',
                glyph: Icons.groups_outlined,
                accent: heroColor,
              ),
              InfoCard(
                name: '获得点赞',
                description: player.endorsedBy.isEmpty
                    ? '没有收到点赞'
                    : '${player.endorsedBy.length} 人：${peopleText(player.endorsedBy, '')}',
                glyph: Icons.thumb_up_outlined,
                accent: heroColor,
              ),
            ]),
            if (stadium != null) ...[
              const SizedBox(height: Sp.betweenSections),
              AccentTitle('角斗构筑', accent: heroColor),
              const SizedBox(height: Sp.withinGroup + 2),
              CardGrid([
                StatCard(
                  label: '局内货币',
                  value: fmtInt(stadium.worth),
                  accent: heroColor,
                ),
                for (final e in stadium.powers)
                  InfoCard(name: e.label, tag: '异能', accent: heroColor),
                for (final e in stadium.items)
                  InfoCard(name: e.label, tag: '装备', accent: heroColor),
              ]),
            ],
            const SizedBox(height: Sp.betweenSections),
          ],
        );
      },
    );
  }
}
