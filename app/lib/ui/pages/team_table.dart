import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/support.dart';
import '../../design/data_table.dart';
import '../../design/icons.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';

/// Largest value of each stat across all ten players, so bars on both teams share a scale.
typedef StatMaxes = ({double damage, double healing, double mitigation});

/// One table line: a player, or the team total.
class _Line {
  const _Line.player(Participant this.player) : isTotal = false;
  const _Line.total() : player = null, isTotal = true;
  final Participant? player;
  final bool isTotal;
}

/// A team as a comparison table. The first cell identifies the player (hero picture,
/// name, role glyph, hero name) so the row reads as one person; the three stats follow
/// as bars behind their numbers, each in its own colour (damage red, healing green,
/// mitigation blue), and a total row closes the team.
class TeamTable extends StatelessWidget {
  const TeamTable({
    super.key,
    required this.title,
    required this.ally,
    required this.players,
    required this.maxes,
    required this.onSelect,
    required this.catalog,
    required this.stadium,
    this.ratingsLoading = false,
  });
  final String title;
  final bool ally;
  final List<Participant> players;
  final StatMaxes maxes;
  final ValueChanged<Participant> onSelect;
  final Catalog catalog;
  final bool stadium;

  /// The players' ranks are still being looked up: a cell with none says so instead of a dash.
  final bool ratingsLoading;

  /// Two-line rows (name over hero) need more height than the density default.
  static const _rowHeight = 54.0;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final scale = math.max(
      1.0,
      MediaQuery.textScalerOf(context).scale(13) / 13,
    );
    final rowH = _rowHeight * scale;

    // Team-best marker: highest positive value among values the team actually supplied; ties all count.
    double? best(double? Function(Participant) f) {
      final vs = players.map(f).whereType<double>().where((v) => v > 0);
      return vs.isEmpty ? null : vs.reduce(math.max);
    }

    final bestDamage = best((p) => p.stats.damage);
    final bestHealing = best((p) => p.stats.healing);
    final bestMit = best((p) => p.stats.mitigation);
    double sum(double? Function(Participant) f) =>
        players.map(f).whereType<double>().fold(0.0, (a, b) => a + b);
    int have(double? Function(Participant) f) =>
        players.where((p) => f(p) != null).length;

    Widget total(double? Function(Participant) f) {
      final n = have(f);
      if (n == 0) {
        return Text(missing, style: Ty.cell.copyWith(color: c.textSecondary));
      }
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (n < players.length)
            Tooltip(
              message: '只有 $n / ${players.length} 人有这项数据，合计不含其余的人',
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(
                  Icons.info_outline,
                  size: 13,
                  color: c.textSecondary,
                ),
              ),
            ),
          Text(
            fmtInt(sum(f)),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      );
    }

    Widget stat(
      _Line l,
      double? Function(Participant) f,
      double max,
      Color color,
      double? teamBest,
    ) {
      if (l.isTotal) {
        return Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 14),
            child: total(f),
          ),
        );
      }
      final v = f(l.player!);
      final isBest = v != null && teamBest != null && v == teamBest;
      return DataBar(
        value: v,
        max: max,
        color: color,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isBest)
              const Padding(
                padding: EdgeInsets.only(right: 3),
                child: Text('▲', style: TextStyle(fontSize: 9)),
              ),
            Text(
              fmtInt(v),
              style: isBest
                  ? const TextStyle(fontWeight: FontWeight.w600)
                  : null,
            ),
          ],
        ),
      );
    }

    // Header with a same-coloured square, so the colour is explained by the column's name.
    Widget head(String text, Color color) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: Theme.of(
            context,
          ).textTheme.labelMedium!.copyWith(color: c.textSecondary),
        ),
      ],
    );

    String kdaTotal() {
      if (players.every(
        (p) =>
            p.stats.kills == null &&
            p.stats.assists == null &&
            p.stats.deaths == null,
      )) {
        return missing;
      }
      return '${fmtInt(sum((p) => p.stats.kills))}/${fmtInt(sum((p) => p.stats.assists))}/${fmtInt(sum((p) => p.stats.deaths))}';
    }

    final cols = <Col<_Line>>[
      Col(
        id: 'player',
        label: '玩家',
        width: 220,
        flex: true,
        cell: (_, l) {
          if (l.isTotal) {
            return Text(
              '$title合计',
              style: const TextStyle(fontWeight: FontWeight.w600),
            );
          }
          final p = l.player!;
          final (name, tag) = splitTag(p.name ?? '未知玩家');
          final role = p.role.playableOr(catalog.heroRole(p.hero));
          return Row(
            children: [
              NetImage(
                catalog.heroIcon(p.hero),
                size: 34,
                fallback: p.hero?.label ?? '?',
                radius: 5,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: name,
                                  style: TextStyle(
                                    fontWeight: p.isSubject
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                                TextSpan(
                                  text: tag,
                                  style: Ty.meta.copyWith(
                                    color: c.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (p.isSubject) ...[
                          const SizedBox(width: 6),
                          Text(
                            '查询对象',
                            style: Ty.meta.copyWith(color: c.accent),
                          ),
                        ],
                        if (p.suspended) ...[
                          const SizedBox(width: 4),
                          Tooltip(
                            message: '该玩家账号处于暂停状态',
                            child: Icon(
                              Icons.warning_amber_rounded,
                              size: 14,
                              color: c.warning,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 1),
                    Row(
                      children: [
                        RoleIcon(role, size: 13, color: c.textSecondary),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            p.hero?.label ?? missing,
                            style: Ty.meta.copyWith(color: c.textSecondary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      Col(
        id: 'kda',
        label: 'K/A/D',
        width: 92,
        numeric: true,
        tooltip: 'Kills / Assists / Deaths：消灭 / 助攻 / 阵亡',
        cell: (_, l) => l.isTotal
            ? Text(
                kdaTotal(),
                style: const TextStyle(fontWeight: FontWeight.w600),
              )
            : Text(fmtKda(l.player!.stats)),
      ),
      Col(
        id: 'damage',
        label: '伤害',
        headerChild: head('伤害', c.statDamage),
        width: 136,
        numeric: true,
        bleed: true,
        tooltip: '对英雄伤害。条形长度按全场 10 人的最大值',
        cell: (_, l) => stat(
          l,
          (p) => p.stats.damage,
          maxes.damage,
          c.statDamage,
          bestDamage,
        ),
      ),
      Col(
        id: 'healing',
        label: '治疗',
        headerChild: head('治疗', c.statHealing),
        width: 136,
        numeric: true,
        bleed: true,
        tooltip: '治疗量。条形长度按全场 10 人的最大值',
        cell: (_, l) => stat(
          l,
          (p) => p.stats.healing,
          maxes.healing,
          c.statHealing,
          bestHealing,
        ),
      ),
      Col(
        id: 'mitigation',
        label: '阻挡',
        headerChild: head('阻挡', c.statMitigation),
        width: 136,
        numeric: true,
        bleed: true,
        tooltip: '阻挡或减免的伤害量，不是次数。条形长度按全场 10 人的最大值',
        cell: (_, l) => stat(
          l,
          (p) => p.stats.mitigation,
          maxes.mitigation,
          c.statMitigation,
          bestMit,
        ),
      ),
      Col(
        id: 'rank',
        label: '段位',
        width: 76,
        tooltip: '竞技、角斗显示该场的段位；快速比赛显示玩家当前的竞技段位。查不到的显示 —',
        cell: (_, l) {
          if (l.isTotal) return const SizedBox.shrink();
          final p = l.player!;
          if (ratingsLoading && p.rank == null && p.careerRank == null) {
            return Tooltip(
              message: '正在查询这名玩家的竞技段位',
              child: Text(
                '查询中',
                style: Ty.cell.copyWith(color: c.textSecondary),
              ),
            );
          }
          return RankBadge(
            p.rank ?? p.careerRank,
            catalog: catalog,
            stadium: stadium && p.rank != null,
            current: p.rank == null && p.careerRank != null,
            otherRoles: p.rank == null && p.careerOtherRoles,
          );
        },
      ),
      Col(
        id: 'portrait',
        label: '英雄立绘',
        width: 76,
        bleed: true,
        headerChild: const SizedBox.shrink(),
        cell: (_, l) => l.isTotal
            ? const SizedBox.shrink()
            : PortraitCell(catalog.heroPortrait(l.player!.hero)),
      ),
    ];

    final lines = [
      for (final p in players) _Line.player(p),
      if (players.isNotEmpty) const _Line.total(),
    ];
    final height = rowH * (lines.length + 1) + 2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: Sp.withinGroup),
          child: Row(
            children: [
              Semantics(header: true, child: TeamTag(ally: ally)),
              const SizedBox(width: Sp.withinGroup),
              Text(
                '${players.length} 人',
                style: Ty.meta.copyWith(color: c.textSecondary),
              ),
            ],
          ),
        ),
        SizedBox(
          height: players.isEmpty ? rowH * 3 : height,
          child: AppTable<_Line>(
            tableLabel: '$title队伍',
            rowHeight: _rowHeight,
            columns: cols,
            rows: lines,
            rowMarker: (l) => l.player?.isSubject == true ? c.accent : null,
            rowLabel: (l) {
              if (l.isTotal) {
                return '$title合计，伤害${fmtInt(sum((p) => p.stats.damage))}，治疗${fmtInt(sum((p) => p.stats.healing))}，阻挡${fmtInt(sum((p) => p.stats.mitigation))}';
              }
              final p = l.player!;
              return '${p.name ?? '未知玩家'}${p.isSubject ? '，查询对象' : ''}，${p.hero?.label ?? '未知英雄'}，${p.role.label}，'
                  '消灭${fmtInt(p.stats.kills)}助攻${fmtInt(p.stats.assists)}阵亡${fmtInt(p.stats.deaths)}，'
                  '伤害${fmtInt(p.stats.damage)}，治疗${fmtInt(p.stats.healing)}，阻挡${fmtInt(p.stats.mitigation)}';
            },
            onOpen: (l, _) {
              if (l.player != null) onSelect(l.player!);
            },
            empty: const EmptyState(title: '没有参与者数据', body: '上游没有返回这一方的名单。'),
          ),
        ),
      ],
    );
  }
}
