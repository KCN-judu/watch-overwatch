import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';
import '../core/support.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../design/widgets.dart';
import '../l10n/strings.dart';
import '../state/app_state.dart';
import 'pages/heroes_page.dart';
import 'pages/daily_page.dart';
import 'pages/maps_page.dart';
import 'pages/people_page.dart';
import 'pages/matches_page.dart';
import 'pages/overview_page.dart';
import 'pages/profile_page.dart';
import 'pages/strength_page.dart';
import 'pages/growth_page.dart';
import 'pages/trend_page.dart';
import 'shell.dart' show ShellScope;
import '../design/net_pic.dart';

const tabIcons = {
  'overview': Icons.dashboard_sharp,
  'daily': Icons.today_sharp,
  'matches': Icons.sports_esports_sharp,
  'heroes': Icons.groups_2_sharp,
  'maps': Icons.map_sharp,
  'people': Icons.people_outline_sharp,
  'strength': Icons.balance_sharp,
  'growth': Icons.trending_up_sharp,
  'trend': Icons.show_chart_sharp,
  'profile': Icons.badge_sharp,
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
            // The page head: the player and the tabs on the hexagon texture.
            ColoredBox(
              color: context.c.nav,
              child: HexBackdrop(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PlayerHeader(workspace: workspace),
                    TabStrip(app: app),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Sp.betweenGroups,
                  Sp.betweenGroups,
                  Sp.betweenGroups,
                  Sp.betweenGroups,
                ),
                // A new tab or player is new content: fade through. Switching the mode keeps
                // the page (and its sort, scope and other local choices).
                child: FadeThrough(
                  childKey: (app.tab, workspace.name),
                  child: switch (app.tab) {
                    'overview' => OverviewPage(workspace: workspace),
                    'daily' => DailyPage(workspace: workspace),
                    'heroes' => HeroesPage(workspace: workspace),
                    'maps' => MapsPage(workspace: workspace),
                    'people' => PeoplePage(workspace: workspace),
                    'strength' => StrengthPage(workspace: workspace),
                    'growth' => GrowthPage(workspace: workspace),
                    'trend' => TrendPage(workspace: workspace),
                    'profile' => ProfilePage(workspace: workspace),
                    _ => MatchesPage(workspace: workspace),
                  },
                ),
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
            const SizedBox(width: Sp.withinControl),
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
              ? Icon(Icons.thumb_up_sharp, size: 14, color: c.textSecondary)
              : NetPic(
                  endorsementUrl,
                  width: 18,
                  height: 18,
                  error: Icon(
                    Icons.thumb_up_sharp,
                    size: 14,
                    color: c.textSecondary,
                  ),
                ),
          '${profile!.endorsementLevel}',
          tr.shell.endorsementLevel,
        ),
      if (profile?.playTimeHours != null)
        fact(
          Icon(Icons.schedule_sharp, size: 14, color: c.textSecondary),
          tr.shell.playTimeHours(fmtOne(profile!.playTimeHours)),
          tr.shell.playTime,
        ),
      if (profile?.totalMatches != null)
        fact(
          Icon(Icons.sports_esports_sharp, size: 14, color: c.textSecondary),
          tr.shell.matchCountFormatted(fmtInt(profile!.totalMatches)),
          tr.shell.totalMatches,
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
                  const SizedBox(height: Sp.hairline),
                  facts.isEmpty
                      ? Text(
                          tr.shell.loadingProfile,
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
                      padding: const EdgeInsets.only(top: Sp.withinControl),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.warning_amber_sharp,
                            size: 14,
                            color: c.warning,
                          ),
                          const SizedBox(width: Sp.withinControl),
                          Text(
                            profile!.suspensionExpiresMs == null
                                ? tr.shell.accountSuspended
                                : tr.shell.accountSuspendedUntil(
                                    fmtDateTime(profile.suspensionExpiresMs),
                                  ),
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
                semanticLabel: tr.shell.mode,
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
                icon: Icons.refresh_sharp,
                label: tr.shell.refreshData,
                shortcut: 'F5',
                onPressed: app.refreshCurrent,
              ),
              IconAction(
                icon: Icons.ios_share_sharp,
                label: tr.shell.exportDataset,
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
      message: heroName == null
          ? tr.shell.noAvatar
          : tr.shell.noAvatarShowingHero(heroName!),
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
        return Text(
          tr.shell.rankUnavailable(tr.shell.errorSentence(l.error!.kind)),
          style: label,
        );
      }
      return Text(tr.shell.rankMissing, style: label);
    }
    return Wrap(
      spacing: Sp.betweenGroups,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Tooltip(
          message: tr.shell.competitiveRank,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.emoji_events_sharp, size: 14, color: c.textSecondary),
              const SizedBox(width: Sp.withinControl),
              Text(tr.shell.competitive, style: label),
            ],
          ),
        ),
        for (final r in Role.playable)
          Builder(
            builder: (context) {
              final rc = career.role(r);
              final detail = rc == null
                  ? tr.shell.noRoleRankThisSeason(r.label)
                  : tr.shell.roleRank(
                      r.label,
                      rc.current?.labelOn(
                            stadium: AppScope.of(context).mode == Mode.stadium,
                          ) ??
                          tr.common.unranked,
                      fmtInt(rc.current?.skillRating),
                      rc.peak?.labelOn(
                            stadium: AppScope.of(context).mode == Mode.stadium,
                          ) ??
                          tr.common.missing,
                      fmtInt(rc.matches),
                    );
              return Tooltip(
                message: detail,
                child: Semantics(
                  label: detail,
                  excludeSemantics: true,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RoleIcon(r, size: 16, tooltip: false),
                      const SizedBox(width: Sp.iconGap),
                      rc?.current == null
                          ? Text(tr.common.unranked, style: label)
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
        label: tr.shell.playerViews,
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

/// A tab is the one item whose selection is not an outline ([ItemState]): the selected
/// tab is a solid accent plate leaning like every picked thing ([SlantBorder]), as the
/// game's menus mark theirs. Hover and focus are the usual ones.
class _Tab extends StatefulWidget {
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
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final (icon, label, selected) = (
      widget.icon,
      widget.label,
      widget.selected,
    );
    final onTap = widget.onTap;
    return Tooltip(
      message: widget.hint,
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        excludeSemantics: true,
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Container(
              height: Ctl.large,
              margin: const EdgeInsets.symmetric(vertical: Sp.withinControl),
              padding: const EdgeInsets.symmetric(horizontal: Sp.betweenGroups),
              alignment: Alignment.center,
              decoration: ShapeDecoration(
                color: selected
                    ? (_hovered
                          ? Color.alphaBlend(c.hover, c.accent)
                          : c.accent)
                    : c.itemFill(hovered: _hovered),
                shape: const SlantBorder(),
              ),
              foregroundDecoration: widget.ring
                  ? ShapeDecoration(
                      shape: SlantBorder(
                        side: BorderSide(color: c.textPrimary, width: 2),
                      ),
                    )
                  : null,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 16,
                    color: selected ? c.onAccent : c.textSecondary,
                  ),
                  const SizedBox(width: Sp.iconGap),
                  Text(
                    label,
                    style: Ty.body.copyWith(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                      color: selected ? c.onAccent : c.textSecondary,
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
      final tip = stale
          ? tr.shell.updatedAtStaleTip(text)
          : tr.shell.updatedAt(text);
      return Tooltip(
        message: tip,
        child: Semantics(
          label: tip,
          excludeSemantics: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                stale ? Icons.history_toggle_off_sharp : Icons.schedule_sharp,
                size: 14,
                color: stale ? c.warning : c.textSecondary,
              ),
              const SizedBox(width: Sp.withinControl),
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
              stale
                  ? tr.shell.updatedAtStale(fmtTime(at!))
                  : tr.shell.updatedAt(fmtTime(at!)),
              style: style,
            ),
        for (final e in extra) Text(e, style: style),
        if (loading) const RefreshingChip(),
        if (error != null && !loading)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_sharp, size: 14, color: c.error),
              const SizedBox(width: Sp.withinControl),
              Text(
                tr.shell.refreshFailedShowingOld('$error'),
                style: Ty.meta.copyWith(color: c.error),
              ),
              const SizedBox(width: Sp.withinControl),
              AppButton(tr.common.retry, quiet: true, onPressed: onRetry),
            ],
          ),
      ],
    );
  }
}
