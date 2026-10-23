import 'package:flutter/material.dart';

import '../../core/gamedata.dart';
import '../../core/models.dart';
import '../../core/support.dart';
import '../../design/cards.dart';
import '../../design/icons.dart';
import '../../design/net_pic.dart';
import '../../design/tokens.dart';
import '../../l10n/strings.dart';

/// One player of a match, as a page of cards: who they are, how they played, the Fleta
/// index, their perks, who they queued with and who endorsed them.
class PlayerDetailPage extends StatelessWidget {
  const PlayerDetailPage({
    super.key,
    required this.detail,
    required this.player,
    required this.ally,
    required this.catalog,
  });
  final MatchDetail detail;
  final Participant player;

  /// Whether the player is on the queried player's own team.
  final bool ally;
  final Catalog catalog;

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
    final name = player.name ?? tr.common.unknownPlayer;

    String shareText(double? share) => share == null
        ? ''
        : tr.matches.shareOfTeam(fmtPct(share * 100, digits: 0));

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

    Widget header() => Panel(
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
                const SizedBox(height: Sp.withinControl),
                Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      ally ? tr.common.ally : tr.common.enemy,
                      style: Ty.bodyStrong.copyWith(
                        color: ally ? c.ally : c.enemy,
                      ),
                    ),
                    if (player.isSubject)
                      Text(
                        tr.matches.subject,
                        style: Ty.body.copyWith(color: c.textSecondary),
                      ),
                    RoleIcon(player.role, size: 16, showLabel: true),
                    Text(hero?.label ?? tr.common.unknownHero, style: Ty.body),
                    RankCell(
                      player.rankState,
                      catalog: catalog,
                      stadium: detail.mode == Mode.stadium,
                      long: true,
                    ),
                    if (player.suspended)
                      Tooltip(
                        message: tr.matches.restrictedTip,
                        child: Text(
                          tr.matches.restricted,
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
          if (p.bnetId != null) p.bnetId!: p.name ?? tr.common.unknownPlayer,
      };
      final names = [for (final id in ids) ?byId[id]];
      final rest = ids.length - names.length;
      return tr.matches.peopleParts([
        if (names.isNotEmpty) tr.common.list(names),
        if (rest > 0) tr.matches.peopleNotInMatch(rest),
      ]);
    }

    return FutureBuilder<GameData>(
      future: game,
      initialData: GameData.loaded,
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
          padding: const EdgeInsets.only(right: scrollGutter),
          children: [
            header(),
            const SizedBox(height: Sp.betweenSections),
            SectionHeader(
              tr.matches.matchStats,
              accent: heroColor,
              info: tr.matches.matchStatsInfo,
            ),
            const SizedBox(height: Sp.withinGroup + 2),
            CardGrid(minWidth: 200, height: 124, [
              stat(tr.matches.kills, s.kills, of: (l) => l.kills),
              stat(tr.matches.assists, s.assists, of: (l) => l.assists),
              stat(tr.matches.deaths, s.deaths, of: (l) => l.deaths),
              StatCard(
                label: 'KDA',
                value: kda,
                accent: heroColor,
                caption: tr.matches.kdaFormula,
              ),
              stat(tr.matches.damage, s.damage, of: (l) => l.damage),
              stat(tr.matches.healing, s.healing, of: (l) => l.healing),
              stat(
                tr.matches.mitigation,
                s.mitigation,
                of: (l) => l.mitigation,
              ),
              stat(
                tr.matches.finalBlows,
                s.finalBlows,
                of: (l) => l.finalBlows,
              ),
              stat(tr.matches.soloKills, s.soloKills),
              stat(tr.matches.damageTaken, s.damageTaken),
              stat(tr.matches.healingTaken, s.healingTaken),
              StatCard(
                label: tr.matches.objectiveTime,
                value: s.objectiveTimeS == null
                    ? missing
                    : fmtClock(s.objectiveTimeS),
                accent: heroColor,
              ),
            ]),
            const SizedBox(height: Sp.betweenSections),
            SectionHeader(
              tr.matches.fleta,
              accent: heroColor,
              info: tr.matches.fletaInfo,
            ),
            const SizedBox(height: Sp.withinGroup + 2),
            CardGrid(minWidth: 320, height: 124, [
              StatCard(
                label: tr.matches.fleta,
                value: player.fleta == null
                    ? missing
                    : fmtPct(player.fleta, digits: 1),
                accent: heroColor,
                share: player.fleta == null ? null : player.fleta! / 200,
                caption: player.fleta == null
                    ? tr.matches.fletaNoData
                    : tr.matches.fletaFormula(
                        fmtInt(s.finalBlows),
                        fmtInt(teamFinals),
                      ),
              ),
            ]),
            if (perks.isNotEmpty) ...[
              const SizedBox(height: Sp.betweenSections),
              SectionHeader(tr.matches.perks, accent: heroColor),
              const SizedBox(height: Sp.withinGroup + 2),
              CardGrid(perks),
            ],
            const SizedBox(height: Sp.betweenSections),
            SectionHeader(tr.matches.partyAndEndorsements, accent: heroColor),
            const SizedBox(height: Sp.withinGroup + 2),
            CardGrid([
              InfoCard(
                name: tr.matches.party,
                description: player.partyBnetIds.isEmpty
                    ? tr.matches.noParty
                    : tr.matches.partyWith(
                        player.partyBnetIds.length,
                        peopleText(player.partyBnetIds, ''),
                      ),
                glyph: Icons.groups_outlined,
                accent: heroColor,
              ),
              InfoCard(
                name: tr.matches.endorsements,
                description: player.endorsedBy.isEmpty
                    ? tr.matches.noEndorsements
                    : tr.matches.endorsedBy(
                        player.endorsedBy.length,
                        peopleText(player.endorsedBy, ''),
                      ),
                glyph: Icons.thumb_up_outlined,
                accent: heroColor,
              ),
            ]),
            if (stadium != null) ...[
              const SizedBox(height: Sp.betweenSections),
              SectionHeader(tr.matches.stadiumBuild, accent: heroColor),
              const SizedBox(height: Sp.withinGroup + 2),
              CardGrid([
                StatCard(
                  label: tr.matches.stadiumCash,
                  value: fmtInt(stadium.worth),
                  accent: heroColor,
                ),
                for (final (e, kind) in [
                  for (final e in stadium.powers) (e, tr.matches.power),
                  for (final e in stadium.items) (e, tr.matches.item),
                ])
                  _upgradeCard(catalog, e, kind, heroColor),
              ]),
            ],
            const SizedBox(height: Sp.betweenSections),
          ],
        );
      },
    );
  }
}

/// One Stadium power or item: its picture (in its own colours), kind and rarity, and
/// the game's description, from the catalog. Only the name when the catalog lacks it.
Widget _upgradeCard(
  Catalog catalog,
  EntityRef upgrade,
  String kind,
  Color accent,
) {
  final u = catalog.stadiumUpgrade(upgrade);
  return InfoCard(
    name: u?.name ?? upgrade.label,
    description: u?.plainText ?? '',
    tag: tr.matches.upgradeTag(u?.category ?? kind, u?.rarity),
    iconUrl: u?.icon,
    tintIcon: false,
    accent: accent,
  );
}
