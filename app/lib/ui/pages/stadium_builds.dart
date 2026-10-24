import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/overview.dart';
import '../../core/stadium.dart';
import '../../core/support.dart';
import '../../design/cards.dart';
import '../../design/chart_kit.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';
import '../../l10n/strings.dart';
import '../../state/app_state.dart';

/// Stadium builds on one hero (`watch_core::stadium`): how often each power and item is
/// taken, in which round, and how those matches went; the commonest power sets. Over the
/// player's own stored matches or everyone in them; entries with too few matches are
/// listed after the rest, grey. An entry opens the player's matches with it.
class StadiumBuildsSection extends StatefulWidget {
  const StadiumBuildsSection({
    super.key,
    required this.workspace,
    required this.hero,
    required this.accent,
  });
  final PlayerWorkspace workspace;
  final EntityRef hero;
  final Color accent;

  @override
  State<StadiumBuildsSection> createState() => _StadiumBuildsSectionState();
}

class _StadiumBuildsSectionState extends State<StadiumBuildsSection> {
  BuildSample _scope = BuildSample.own;

  /// The entry whose matches are listed: `power:guid`, `item:guid` or `set:index`.
  String? _open;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => widget.workspace.loadStadium(_scope),
    );
  }

  void _setScope(BuildSample s) {
    setState(() {
      _scope = s;
      _open = null;
    });
    widget.workspace.loadStadium(s);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final load = widget.workspace.stadiumFor(_scope);
    final result = load.value;
    final builds = result?.of(widget.hero);
    final Widget body;
    if (load.failedWithoutData) {
      body = ErrorPanel(
        what: tr.heroes.buildsTitle,
        error: load.error!,
        onRetry: () => widget.workspace.loadStadium(_scope, fresh: true),
      );
    } else if (result == null) {
      body = const AfterDelay(child: Center(child: Spinner()));
    } else if (builds == null || builds.matches == 0) {
      body = Text(
        tr.heroes.buildsNone,
        style: Ty.body.copyWith(color: c.textSecondary),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr.heroes.buildsSource(
              builds.matches,
              builds.ownMatches,
              result.details,
            ),
            style: Ty.meta.copyWith(color: c.textSecondary),
          ),
          for (final (title, kind, list) in [
            (tr.heroes.buildsPowers, 'power', builds.powers),
            (tr.heroes.buildsItems, 'item', builds.items),
          ])
            if (list.isNotEmpty) ...[
              const SizedBox(height: Sp.betweenGroups),
              Text(title, style: Ty.bodyStrong),
              const SizedBox(height: Sp.withinControl),
              _bars(context, builds, [
                for (final u in list)
                  (
                    key: '$kind:${u.upgrade.guid}',
                    label: _upgradeLabel(u),
                    icon: AppScope.of(
                      context,
                    ).catalog.stadiumUpgrade(u.upgrade)?.icon,
                    record: u.record,
                    ids: u.matchIds,
                  ),
              ]),
            ],
          if (builds.builds.isNotEmpty) ...[
            const SizedBox(height: Sp.betweenGroups),
            Text(tr.heroes.buildsSets, style: Ty.bodyStrong),
            const SizedBox(height: Sp.withinControl),
            _bars(context, builds, [
              for (final (i, b) in builds.builds.indexed)
                (
                  key: 'set:$i',
                  label: tr.common.list([
                    for (final p in b.powers) _name(context, p),
                  ]),
                  icon: null,
                  record: b.record,
                  ids: b.matchIds,
                ),
            ]),
          ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          tr.heroes.buildsTitle,
          accent: widget.accent,
          info: tr.heroes.buildsTip,
          trailing: SegmentedBar<BuildSample>(
            semanticLabel: tr.heroes.buildsTitle,
            value: _scope,
            onChanged: _setScope,
            segments: [
              Segment(BuildSample.own, tr.heroes.scopeOwn),
              Segment(BuildSample.everyone, tr.heroes.scopeEveryone),
            ],
          ),
        ),
        const SizedBox(height: SectionHeader.below),
        Panel(child: body),
      ],
    );
  }

  String _name(BuildContext context, EntityRef e) =>
      AppScope.of(context).catalog.stadiumUpgrade(e)?.name ?? e.label;

  String _upgradeLabel(UpgradeStat u) {
    final name =
        AppScope.of(context).catalog.stadiumUpgrade(u.upgrade)?.name ??
        u.upgrade.label;
    final rate = tr.heroes.pickRate(fmtPct(u.pickRatePct, digits: 0));
    return u.round == null
        ? [name, rate].join(tr.common.sep)
        : [name, tr.heroes.roundTag(u.round!), rate].join(tr.common.sep);
  }

  Widget _bars(
    BuildContext context,
    HeroBuilds builds,
    List<
      ({
        String key,
        String label,
        String? icon,
        OverviewRecord record,
        List<String> ids,
      })
    >
    rows,
  ) {
    final open = rows.where((r) => r.key == _open).firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IntervalBars(
          format: (v) => fmtPct(v, digits: 0),
          reference: builds.record.winRatePct,
          referenceMeaning: builds.record.winRatePct == null
              ? null
              : tr.overview.overallRate(
                  fmtPct(builds.record.winRatePct, digits: 0),
                ),
          labelWidth: 300,
          rows: [
            for (final r in rows)
              IntervalRow(
                label: r.label,
                value: r.record.winRatePct ?? 0,
                low: r.record.lowPct,
                high: r.record.highPct,
                n: r.record.decided,
                enough: r.record.enough,
                selected: r.key == _open,
                leading: r.icon == null
                    ? null
                    : NetImage(r.icon, size: 22, fallback: ''),
                onTap: () =>
                    setState(() => _open = _open == r.key ? null : r.key),
              ),
          ],
        ),
        if (open != null) _Matches(workspace: widget.workspace, ids: open.ids),
      ],
    );
  }
}

/// The player's matches with a build entry: date, map and result; one opens the match.
class _Matches extends StatelessWidget {
  const _Matches({required this.workspace, required this.ids});
  final PlayerWorkspace workspace;
  final List<String> ids;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = context.c;
    final rows = {
      for (final m
          in workspace.matchesFor(Mode.stadium).value?.matches ?? const [])
        m.id: m,
    };
    return Padding(
      padding: const EdgeInsets.only(top: Sp.withinGroup, left: Sp.withinGroup),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ids.isEmpty
                ? tr.heroes.noOwnMatches
                : tr.heroes.ownMatches(ids.length),
            style: Ty.meta.copyWith(color: c.textSecondary),
          ),
          for (final id in ids)
            Pressable(
              onTap: () {
                workspace.openMatch(Mode.stadium, id, ids);
                app.setTab('matches');
              },
              semanticLabel: [
                fmtDateTime(rows[id]?.startedAtMs),
                rows[id]?.map?.label ?? tr.common.unknownMap,
                rows[id]?.outcome.label ?? '',
              ].join(tr.common.sep),
              padding: const EdgeInsets.symmetric(
                horizontal: Sp.withinGroup,
                vertical: Sp.withinControl,
              ),
              child: Row(
                children: [
                  if (rows[id] != null) ...[
                    OutcomeMark(rows[id]!.outcome),
                    const SizedBox(width: Sp.withinGroup),
                  ],
                  Text(
                    fmtDateTime(rows[id]?.startedAtMs),
                    style: Ty.num(Ty.body),
                  ),
                  const SizedBox(width: Sp.betweenGroups),
                  Text(
                    rows[id]?.map?.label ?? tr.common.unknownMap,
                    style: Ty.body.copyWith(color: c.textSecondary),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
