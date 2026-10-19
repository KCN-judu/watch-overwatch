import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';
import '../core/support.dart';
import '../design/data_table.dart' show keyboardModality;
import '../design/icons.dart';
import '../design/tokens.dart';
import '../design/widgets.dart';
import '../state/app_state.dart';
import 'pages/heroes_page.dart';
import 'pages/matches_page.dart';
import 'pages/profile_page.dart';
import 'pages/strength_page.dart';
import 'pages/growth_page.dart';
import 'pages/trend_page.dart';
import 'shell.dart' show ShellScope;
import '../design/net_pic.dart';

const tabIcons = {
  'matches': Icons.sports_esports_outlined,
  'heroes': Icons.groups_2_outlined,
  'strength': Icons.balance,
  'growth': Icons.trending_up,
  'trend': Icons.show_chart,
  'profile': Icons.badge_outlined,
};

class PlayerView extends StatelessWidget {
  const PlayerView({super.key, required this.workspace});
  final PlayerWorkspace workspace;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return ListenableBuilder(
      listenable: workspace,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PlayerHeader(workspace: workspace),
            TabStrip(app: app),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Sp.betweenGroups,
                  Sp.betweenGroups,
                  Sp.betweenGroups,
                  Sp.betweenGroups,
                ),
                child: switch (app.tab) {
                  'heroes' => HeroesPage(workspace: workspace),
                  'strength' => StrengthPage(workspace: workspace),
                  'growth' => GrowthPage(workspace: workspace),
                  'trend' => TrendPage(workspace: workspace),
                  'profile' => ProfilePage(workspace: workspace),
                  _ => MatchesPage(workspace: workspace),
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class PlayerHeader extends StatelessWidget {
  const PlayerHeader({super.key, required this.workspace});
  final PlayerWorkspace workspace;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = context.c;
    final profile = workspace.profile;
    final (name, tag) = splitTag(workspace.name);
    final avatar =
        profile?.avatarUrl ?? (workspace.identity?['icon'] as String?);
    final endorsementUrl = app.catalog.endorsementIcon(
      profile?.endorsementLevel,
    );
    Widget fact(Widget icon, String value, String name) => Tooltip(
      message: name,
      child: Semantics(
        label: '$name $value',
        excludeSemantics: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(width: 4),
            Text(
              value,
              style: Ty.num(Ty.meta).copyWith(color: c.textSecondary),
            ),
          ],
        ),
      ),
    );
    final facts = <Widget>[
      if (profile?.endorsementLevel != null)
        fact(
          endorsementUrl == null
              ? Icon(Icons.thumb_up_outlined, size: 14, color: c.textSecondary)
              : NetPic(
                  endorsementUrl,
                  width: 18,
                  height: 18,
                  error: Icon(
                    Icons.thumb_up_outlined,
                    size: 14,
                    color: c.textSecondary,
                  ),
                ),
          '${profile!.endorsementLevel}',
          '荣誉等级',
        ),
      if (profile?.playTimeHours != null)
        fact(
          Icon(Icons.schedule, size: 14, color: c.textSecondary),
          '${fmtOne(profile!.playTimeHours)} 小时',
          '游戏时长',
        ),
      if (profile?.totalMatches != null)
        fact(
          Icon(Icons.sports_esports_outlined, size: 14, color: c.textSecondary),
          '${fmtInt(profile!.totalMatches)} 场',
          '总场次',
        ),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(
        Sp.betweenGroups,
        Sp.betweenGroups,
        Sp.betweenGroups,
        Sp.withinGroup,
      ),
      child: Wrap(
        spacing: Sp.betweenGroups,
        runSpacing: Sp.withinGroup,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Avatar(
                url: avatar,
                heroUrl: app.catalog.heroIcon(workspace.topHero),
                heroName: workspace.topHero?.label,
                fallback: name,
              ),
              const SizedBox(width: Sp.withinGroup + 4),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: name, style: Ty.page),
                          TextSpan(
                            text: tag,
                            style: Ty.page.copyWith(
                              color: c.textSecondary,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  facts.isEmpty
                      ? Text(
                          '正在读取玩家资料…',
                          style: Ty.meta.copyWith(color: c.textSecondary),
                        )
                      : Wrap(
                          spacing: Sp.betweenGroups,
                          runSpacing: 2,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            ...facts,
                            _RankLine(workspace: workspace),
                          ],
                        ),
                  if (profile?.suspended == true)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 14,
                            color: c.warning,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '账号处于暂停状态${profile!.suspensionExpiresMs == null ? '' : '，到期 ${fmtDateTime(profile.suspensionExpiresMs)}'}',
                            style: Ty.meta.copyWith(color: c.warning),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedBar<Mode>(
                semanticLabel: '模式',
                value: app.mode,
                onChanged: app.setMode,
                segments: [
                  for (final (i, m) in Mode.values.indexed)
                    Segment(
                      m,
                      m.shortLabel,
                      hint: '${m.label}  Alt+${i + 1}',
                      leading: Icon(m.icon, size: 15),
                    ),
                ],
              ),
              const SizedBox(width: Sp.withinGroup),
              IconAction(
                icon: Icons.refresh,
                label: '刷新数据',
                shortcut: 'F5',
                onPressed: app.refreshCurrent,
              ),
              IconAction(
                icon: Icons.ios_share,
                label: '导出数据集',
                shortcut: 'Ctrl+E',
                onPressed: app.exporting
                    ? null
                    : ShellScope.of(context).actions.openExport,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The player's avatar; when the account has none, its most played hero stands in.
class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.url,
    required this.heroUrl,
    required this.heroName,
    required this.fallback,
  });
  final String? url, heroUrl, heroName;
  final String fallback;
  @override
  Widget build(BuildContext context) {
    const size = 56.0;
    if (url != null && url!.isNotEmpty) {
      return NetImage(url, size: size, fallback: fallback, radius: 8);
    }
    return Tooltip(
      message: heroName == null ? '未设置头像' : '未设置头像，显示最常用英雄：$heroName',
      child: NetImage(heroUrl, size: size, fallback: fallback, radius: 8),
    );
  }
}

class _RankLine extends StatelessWidget {
  const _RankLine({required this.workspace});
  final PlayerWorkspace workspace;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final catalog = AppScope.of(context).catalog;
    final l = workspace.competitive;
    final career = l.value;
    final label = Ty.meta.copyWith(color: c.textSecondary);
    if (career == null) {
      if (l.error != null) {
        return Text('竞技段位暂时无法读取：${l.error!.message}', style: label);
      }
      return Text('竞技段位  —', style: label);
    }
    return Wrap(
      spacing: Sp.betweenGroups,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Tooltip(
          message: '竞技段位',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.emoji_events_outlined,
                size: 14,
                color: c.textSecondary,
              ),
              const SizedBox(width: 4),
              Text('竞技', style: label),
            ],
          ),
        ),
        for (final r in Role.playable)
          Builder(
            builder: (context) {
              final rc = career.role(r);
              final detail = rc == null
                  ? '本赛季没有${r.label}的竞技记录'
                  : '${r.label}：当前 ${rc.current?.label ?? '未定级'}（${fmtInt(rc.current?.skillRating)} 分），最高 ${rc.peak?.label ?? '—'}，${fmtInt(rc.matches)} 场';
              return Tooltip(
                message: detail,
                child: Semantics(
                  label: detail,
                  excludeSemantics: true,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RoleIcon(r, size: 16, tooltip: false),
                      const SizedBox(width: 6),
                      rc?.current == null
                          ? Text('未定级', style: label)
                          : RankBadge(
                              rc!.current,
                              catalog: catalog,
                              size: 20,
                              showText: true,
                            ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

/// Navigation tabs: peer views of one object. One tab stop; arrows move between tabs.
class TabStrip extends StatefulWidget {
  const TabStrip({super.key, required this.app});
  final AppState app;
  @override
  State<TabStrip> createState() => _TabStripState();
}

class _TabStripState extends State<TabStrip> {
  final _focus = FocusNode(debugLabel: 'tabs');
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final app = widget.app;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.betweenGroups),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Semantics(
        container: true,
        label: '玩家视图',
        child: Focus(
          focusNode: _focus,
          onKeyEvent: (_, e) {
            if (e is KeyUpEvent) return KeyEventResult.ignored;
            final i = tabIds.indexOf(app.tab);
            if (e.logicalKey == LogicalKeyboardKey.arrowRight) {
              app.setTab(tabIds[(i + 1).clamp(0, tabIds.length - 1)]);
            } else if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
              app.setTab(tabIds[(i - 1).clamp(0, tabIds.length - 1)]);
            } else {
              return KeyEventResult.ignored;
            }
            return KeyEventResult.handled;
          },
          child: ListenableBuilder(
            listenable: _focus,
            builder: (context, _) {
              final ring = _focus.hasFocus && keyboardModality;
              return Row(
                children: [
                  for (final (i, id) in tabIds.indexed)
                    _Tab(
                      icon: tabIcons[id]!,
                      label: tabLabels[id]!,
                      hint: 'Ctrl+${i + 1}',
                      selected: app.tab == id,
                      ring: ring && app.tab == id,
                      onTap: () {
                        _focus.requestFocus();
                        app.setTab(id);
                      },
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.icon,
    required this.label,
    required this.hint,
    required this.selected,
    required this.ring,
    required this.onTap,
  });
  final IconData icon;
  final String label, hint;
  final bool selected, ring;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Tooltip(
      message: hint,
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        excludeSemantics: true,
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: selected ? c.accent : Colors.transparent,
                    width: 2,
                  ),
                ),
                color: ring ? c.selected : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 16,
                    color: selected ? c.accent : c.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: Ty.body.copyWith(
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: selected ? c.textPrimary : c.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Honest status for one loaded dataset: when it was collected, whether a refresh is
/// running, and what happened if the refresh failed while older data stays on screen.
/// `compact` shows the time as a clock icon and keeps the wording for problems only.
class LoadStatusBar extends StatelessWidget {
  const LoadStatusBar({
    super.key,
    required this.at,
    required this.loading,
    required this.error,
    required this.onRetry,
    this.extra = const [],
    this.compact = false,
  });
  final DateTime? at;
  final bool loading;
  final Object? error;
  final VoidCallback onRetry;
  final List<String> extra;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final style = Ty.meta.copyWith(color: c.textSecondary);
    final stale =
        at != null &&
        DateTime.now().difference(at!) > const Duration(minutes: 5);
    Widget stamp() {
      final text = fmtTime(at!);
      final tip = '采集于 $text${stale ? '，已超过 5 分钟，可以刷新' : ''}';
      return Tooltip(
        message: tip,
        child: Semantics(
          label: tip,
          excludeSemantics: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                stale ? Icons.history_toggle_off : Icons.schedule,
                size: 14,
                color: stale ? c.warning : c.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                text,
                style: Ty.num(
                  Ty.meta,
                ).copyWith(color: stale ? c.warning : c.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    return Wrap(
      spacing: Sp.betweenGroups,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (at != null)
          if (compact)
            stamp()
          else
            Text(
              '采集于 ${fmtTime(at!)}${stale ? '（已超过 5 分钟）' : ''}',
              style: style,
            ),
        for (final e in extra) Text(e, style: style),
        if (loading) const RefreshingChip(),
        if (error != null && !loading)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 14, color: c.error),
              const SizedBox(width: 4),
              Text(
                '刷新失败，显示的是旧数据：$error',
                style: Ty.meta.copyWith(color: c.error),
              ),
              const SizedBox(width: 4),
              AppButton('重试', quiet: true, onPressed: onRetry),
            ],
          ),
      ],
    );
  }
}

/// Renders nothing for the first 300 ms so fast loads never flash a skeleton.
class AfterDelay extends StatefulWidget {
  const AfterDelay({
    super.key,
    required this.child,
    this.delay = const Duration(milliseconds: 300),
  });
  final Widget child;
  final Duration delay;
  @override
  State<AfterDelay> createState() => _AfterDelayState();
}

class _AfterDelayState extends State<AfterDelay> {
  bool _show = false;
  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.delay, () {
      if (mounted) setState(() => _show = true);
    });
  }

  @override
  Widget build(BuildContext context) =>
      _show ? widget.child : const SizedBox.shrink();
}
