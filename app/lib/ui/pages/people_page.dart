import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/overview.dart';
import '../../core/people.dart';
import '../../core/support.dart';
import '../../design/cards.dart';
import '../../design/icons.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';
import '../../l10n/strings.dart';
import '../../state/app_state.dart';

/// Who the player meets (`watch_core::party`): their results in a group against alone,
/// the players seen most often on their side and against them, and one player's shared
/// matches side by side, each opening the match. Only stored details count; nothing here
/// labels a player, it only says what happened.
class PeoplePage extends StatefulWidget {
  const PeoplePage({super.key, required this.workspace});
  final PlayerWorkspace workspace;

  @override
  State<PeoplePage> createState() => _PeoplePageState();
}

class _PeoplePageState extends State<PeoplePage> {
  String? _picked;

  void _pick(Mode mode, String key) {
    setState(() => _picked = key);
    widget.workspace.loadDuo(mode, key);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final ws = widget.workspace;
    final mode = app.mode;
    final load = ws.peopleFor(mode);
    final r = load.value;
    if (load.failedWithoutData) {
      return ErrorPanel(
        what: tr.people.matesTitle,
        error: load.error!,
        onRetry: () => ws.loadPeople(mode),
      );
    }
    if (r == null) {
      return load.loading || !load.has
          ? const AfterDelay(child: Center(child: Spinner()))
          : const SizedBox.shrink();
    }
    if (r.details == 0) {
      return EmptyState(
        icon: Icons.people_outline,
        title: tr.people.emptyTitle,
        body: tr.people.emptyBody(mode.label),
        actions: [
          AppButton(
            tr.people.openMatchList,
            primary: true,
            onPressed: () => app.setTab('matches'),
          ),
        ],
      );
    }
    final picked =
        r.mates.where((m) => m.key == _picked).firstOrNull ??
        r.mates.firstOrNull;
    if (picked != null && _picked == null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => ws.loadDuo(mode, picked.key),
      );
    }
    final list = _List(
      result: r,
      picked: picked?.key,
      onPick: (k) => _pick(mode, k),
    );
    final duo = picked == null
        ? const SizedBox.shrink()
        : _Duo(workspace: ws, mode: mode, mate: picked);
    return LayoutBuilder(
      builder: (context, box) {
        const pad = EdgeInsets.only(right: Sp.betweenGroups, bottom: Sp.page);
        if (box.maxWidth < 1000) {
          return ListView(
            padding: pad,
            children: [
              list,
              const SizedBox(height: Sp.betweenSections),
              duo,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: ListView(padding: pad, children: [list]),
            ),
            const SizedBox(width: Sp.betweenSections),
            Expanded(
              flex: 3,
              child: ListView(padding: pad, children: [duo]),
            ),
          ],
        );
      },
    );
  }
}

String _rate(OverviewRecord r) => fmtPct(r.winRatePct, digits: 0);

String? _range(OverviewRecord r) => r.lowPct == null || r.highPct == null
    ? null
    : tr.people.rangeNote(
        r.decided,
        fmtPct(r.lowPct, digits: 0),
        fmtPct(r.highPct, digits: 0),
      );

KpiTile _recordTile(String label, OverviewRecord r) => KpiTile(
  label,
  _rate(r),
  note: _range(r) ?? tr.people.matchesNote(r.matches),
);

class _List extends StatelessWidget {
  const _List({
    required this.result,
    required this.picked,
    required this.onPick,
  });
  final PeopleResult result;
  final String? picked;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                tr.people.coverage(result.details, app.mode.label),
                style: Ty.meta.copyWith(color: c.textSecondary),
              ),
            ),
            InfoTip(tr.people.coverageTip),
          ],
        ),
        const SizedBox(height: Sp.betweenGroups),
        SectionHeader(tr.people.partyTitle, info: tr.people.partyTip),
        const SizedBox(height: SectionHeader.below),
        Wrap(
          spacing: Sp.withinGroup,
          runSpacing: Sp.withinGroup,
          children: [
            _recordTile(tr.people.partyRate, result.party),
            _recordTile(tr.people.soloRate, result.solo),
          ],
        ),
        const SizedBox(height: Sp.betweenSections),
        SectionHeader(tr.people.matesTitle, info: tr.people.matesTip),
        const SizedBox(height: SectionHeader.below),
        if (result.mates.isEmpty)
          Text(tr.people.none, style: Ty.body.copyWith(color: c.textSecondary))
        else
          Panel(
            padding: PanelPadding.chart,
            child: Column(
              children: [
                for (final m in result.mates)
                  Pressable(
                    onTap: () => onPick(m.key),
                    selected: m.key == picked,
                    semanticLabel: [
                      m.name ?? tr.people.anonymous,
                      tr.people.shared(m.shared),
                    ].join(' · '),
                    padding: const EdgeInsets.symmetric(
                      horizontal: Sp.withinGroup,
                      vertical: 6,
                    ),
                    child: _MateRow(mate: m),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MateRow extends StatelessWidget {
  const _MateRow({required this.mate});
  final Mate mate;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final m = mate;
    final meta = Ty.meta.copyWith(color: c.textSecondary);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                m.name ?? tr.people.anonymous,
                style: Ty.bodyStrong,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                [
                  if (m.asAlly.matches > 0)
                    tr.people.allyLine(m.asAlly.matches, _rate(m.asAlly)),
                  if (m.asEnemy.matches > 0)
                    tr.people.enemyLine(m.asEnemy.matches, _rate(m.asEnemy)),
                  if (m.inParty > 0) tr.people.partyLine(m.inParty),
                ].join(' · '),
                style: meta,
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(tr.people.shared(m.shared), style: Ty.num(Ty.body)),
            if (m.lastMs != null)
              Text(
                tr.people.lastSeen(fmtDateTime(m.lastMs).substring(0, 5)),
                style: meta,
              ),
          ],
        ),
      ],
    );
  }
}

class _Duo extends StatelessWidget {
  const _Duo({required this.workspace, required this.mode, required this.mate});
  final PlayerWorkspace workspace;
  final Mode mode;
  final Mate mate;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = context.c;
    final load = workspace.duoFor(mode, mate.key);
    final d = load.value;
    final Widget body;
    if (load.failedWithoutData) {
      body = ErrorPanel(
        what: tr.people.sharedTitle,
        error: load.error!,
        onRetry: () => workspace.loadDuo(mode, mate.key),
      );
    } else if (d == null) {
      body = const AfterDelay(child: Center(child: Spinner()));
    } else {
      final ids = [for (final m in d.matches) m.matchId];
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: Sp.withinGroup,
            runSpacing: Sp.withinGroup,
            children: [
              _recordTile(tr.people.withThem, d.withThem),
              _recordTile(tr.people.without, d.without),
              if (d.against.matches > 0)
                _recordTile(tr.people.againstThem, d.against),
            ],
          ),
          const SizedBox(height: Sp.betweenSections),
          SectionHeader(tr.people.sharedTitle, info: tr.people.sharedTip),
          const SizedBox(height: SectionHeader.below),
          Panel(
            padding: PanelPadding.chart,
            child: Column(
              children: [
                for (final m in d.matches)
                  Pressable(
                    onTap: () {
                      workspace.openMatch(mode, m.matchId, ids);
                      app.setTab('matches');
                    },
                    semanticLabel: [
                      m.outcome.label,
                      fmtDateTime(m.startedAtMs),
                      m.map?.label ?? tr.common.unknownMap,
                      m.sameSide ? tr.people.sameSide : tr.people.otherSide,
                    ].join(' · '),
                    padding: const EdgeInsets.symmetric(
                      horizontal: Sp.withinGroup,
                      vertical: 6,
                    ),
                    child: _SharedRow(m: m),
                  ),
              ],
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(mate.name ?? tr.people.anonymous),
        const SizedBox(height: SectionHeader.below),
        body,
        Padding(
          padding: const EdgeInsets.only(top: Sp.withinGroup),
          child: Text(
            tr.people.coverageTip,
            style: Ty.meta.copyWith(color: c.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _SharedRow extends StatelessWidget {
  const _SharedRow({required this.m});
  final SharedMatch m;

  @override
  Widget build(BuildContext context) {
    final catalog = AppScope.of(context).catalog;
    final c = context.c;
    final meta = Ty.meta.copyWith(color: c.textSecondary);
    String kda(StatLine s) =>
        tr.people.kda(fmtInt(s.kills), fmtInt(s.deaths), fmtInt(s.assists));
    Widget side(EntityRef? hero, StatLine s) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        NetImage(catalog.heroIcon(hero), size: 24, fallback: hero?.label ?? ''),
        const SizedBox(width: 6),
        Text(kda(s), style: Ty.num(Ty.body)),
      ],
    );
    return Row(
      children: [
        OutcomeMark(m.outcome),
        const SizedBox(width: Sp.withinGroup),
        SizedBox(
          width: 150,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(fmtDateTime(m.startedAtMs), style: Ty.num(Ty.body)),
              Text(
                m.map?.label ?? tr.common.unknownMap,
                style: meta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        SizedBox(
          width: 90,
          child: Text(
            [
              m.sameSide ? tr.people.sameSide : tr.people.otherSide,
              if (m.grouped) tr.people.grouped,
            ].join(' · '),
            style: meta,
          ),
        ),
        Expanded(child: side(m.meHero, m.me)),
        Expanded(child: side(m.themHero, m.them)),
      ],
    );
  }
}
