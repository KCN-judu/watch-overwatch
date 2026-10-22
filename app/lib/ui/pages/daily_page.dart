import 'package:flutter/material.dart';

import '../../core/daily.dart';
import '../../core/models.dart';
import '../../core/overview.dart';
import '../../core/support.dart';
import '../../design/cards.dart';
import '../../design/icons.dart';
import '../../design/share.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';
import '../../l10n/strings.dart';
import '../../state/app_state.dart';

/// One day at a time (`watch_core::daily`): how it went, what stood out, how it compares
/// with the month before, the heroes and maps, and the day's matches. Every day with
/// matches is listed beside it, and the summary saves as one picture.
class DailyPage extends StatelessWidget {
  const DailyPage({super.key, required this.workspace});
  final PlayerWorkspace workspace;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final ws = workspace;
    final mode = app.mode;
    final load = ws.dailyFor(mode);
    final r = load.value;
    if (load.failedWithoutData) {
      return ErrorPanel(
        what: tr.daily.emptyTitle,
        error: load.error!,
        onRetry: () => ws.loadDaily(mode),
      );
    }
    if (r == null) {
      return load.loading || !load.has
          ? const AfterDelay(child: Center(child: Spinner()))
          : const SizedBox.shrink();
    }
    final s = r.summary;
    if (s == null || r.days.isEmpty) {
      return EmptyState(
        icon: Icons.today_outlined,
        title: tr.daily.emptyTitle,
        body: tr.daily.emptyBody(mode.label),
        actions: [
          AppButton(
            tr.daily.openMatchList,
            primary: true,
            onPressed: () => app.setTab('matches'),
          ),
        ],
      );
    }
    final index = r.days.indexWhere((d) => d.day == s.day);
    void go(String day) => ws.loadDaily(mode, day);
    const pad = EdgeInsets.only(right: Sp.betweenGroups, bottom: Sp.page);
    final list = _Days(days: r.days, picked: s.day, onPick: go);
    final body = _Summary(
      workspace: ws,
      mode: mode,
      s: s,
      older: index >= 0 && index < r.days.length - 1
          ? r.days[index + 1].day
          : null,
      newer: index > 0 ? r.days[index - 1].day : null,
      onGo: go,
    );
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth < 900) {
          return ListView(padding: pad, children: [body]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 240, child: list),
            const SizedBox(width: Sp.betweenSections),
            Expanded(
              child: ListView(padding: pad, children: [body]),
            ),
          ],
        );
      },
    );
  }
}

String _weekday(String day) {
  final d = DateTime.tryParse(day);
  return d == null ? '' : tr.daily.weekdays[d.weekday - 1];
}

/// `10-22` from `2026-10-22`.
String _short(String day) => day.length >= 10 ? day.substring(5) : day;

class _Days extends StatelessWidget {
  const _Days({required this.days, required this.picked, required this.onPick});
  final List<DayEntry> days;
  final String picked;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(tr.daily.daysTitle, info: tr.daily.daysTip),
        const SizedBox(height: SectionHeader.below),
        Expanded(
          child: ListView(
            children: [
              for (final d in days)
                Pressable(
                  onTap: () => onPick(d.day),
                  selected: d.day == picked,
                  semanticLabel: '${d.day} ${_weekday(d.day)}',
                  padding: const EdgeInsets.symmetric(
                    horizontal: Sp.withinGroup,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 86,
                        child: Text(
                          '${_short(d.day)} ${_weekday(d.day)}',
                          style: Ty.num(Ty.bodyStrong),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          tr.daily.groupRow(d.record.wins, d.record.losses),
                          style: Ty.num(
                            Ty.meta,
                          ).copyWith(color: c.textSecondary),
                        ),
                      ),
                      Text(
                        fmtPct(d.record.winRatePct, digits: 0),
                        style: Ty.num(Ty.body).copyWith(
                          color: (d.record.winRatePct ?? 50) >= 50
                              ? c.positive
                              : c.negative,
                        ),
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

String _stat(String stat) => switch (stat) {
  'kills' => tr.daily.statKills,
  'damage' => tr.daily.statDamage,
  'healing' => tr.daily.statHealing,
  'mitigation' => tr.daily.statMitigation,
  'deaths' => tr.daily.statDeaths,
  'kda' => tr.daily.statKda,
  _ => stat,
};

String _value(String stat, double v) =>
    stat == 'kda' || stat == 'fleta' ? fmtOne(v) : fmtInt(v);

class _Summary extends StatelessWidget {
  const _Summary({
    required this.workspace,
    required this.mode,
    required this.s,
    required this.older,
    required this.newer,
    required this.onGo,
  });
  final PlayerWorkspace workspace;
  final Mode mode;
  final DailySummary s;
  final String? older, newer;
  final ValueChanged<String> onGo;

  void _open(AppState app, String id) {
    workspace.openMatch(mode, id, s.matchIds);
    app.setTab('matches');
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = context.c;
    final r = s.aggregate.record;
    final rows = {
      for (final m in workspace.matchesFor(mode).value?.matches ?? const [])
        m.id: m,
    };
    final span = s.firstMs == null || s.lastMs == null
        ? null
        : tr.daily.timeSpan(
            fmtDateTime(s.firstMs).substring(6),
            fmtDateTime(s.lastMs).substring(6),
          );
    final caption = tr.daily.caption(
      app.maskName(workspace.name),
      mode.label,
      s.day,
      r.matches,
    );
    return Shareable(
      title: tr.daily.title(s.day, _weekday(s.day)),
      caption: caption,
      fileName: '${tr.daily.fileName} ${s.day}',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconAction(
            icon: Icons.chevron_left,
            label: tr.daily.previousDay,
            onPressed: older == null ? null : () => onGo(older!),
          ),
          IconAction(
            icon: Icons.chevron_right,
            label: tr.daily.nextDay,
            onPressed: newer == null ? null : () => onGo(newer!),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: Sp.withinGroup,
            runSpacing: Sp.withinGroup,
            children: [
              KpiTile(
                tr.daily.record,
                tr.overview.record(r.wins, r.losses, r.draws),
                note: tr.daily.sittings(s.sittings),
              ),
              KpiTile(
                tr.daily.winRate,
                fmtPct(r.winRatePct, digits: 0),
                note: r.lowPct == null
                    ? null
                    : '${fmtPct(r.lowPct, digits: 0)}–${fmtPct(r.highPct, digits: 0)}',
              ),
              KpiTile(tr.daily.matches, '${r.matches}', note: span),
              KpiTile(
                tr.daily.playTime,
                s.playS == null ? missing : fmtPlayTime(s.playS),
                note: s.playSamples == 0
                    ? tr.daily.noPlayTime
                    : tr.daily.playNote(s.playSamples, r.matches),
              ),
              KpiTile(tr.daily.kda, fmtTwo(s.aggregate.kda)),
              for (final rc in s.rankChanges)
                KpiTile(
                  rc.role.label,
                  ratingLabel(rc.to) ?? fmtInt(rc.to),
                  note: rc.to == rc.from
                      ? tr.daily.rankSame
                      : tr.daily.rankFrom(
                          ratingLabel(rc.from) ?? fmtInt(rc.from),
                          rc.to > rc.from ? '+' : '−',
                          (rc.to - rc.from).abs(),
                        ),
                  color: rc.to > rc.from
                      ? c.positive
                      : rc.to < rc.from
                      ? c.negative
                      : null,
                ),
            ],
          ),
          const SizedBox(height: Sp.betweenSections),
          SectionHeader(tr.daily.highlightsTitle, info: tr.daily.highlightsTip),
          const SizedBox(height: SectionHeader.below),
          if (s.highlights.isEmpty)
            Text(
              tr.daily.noHighlights,
              style: Ty.body.copyWith(color: c.textSecondary),
            )
          else
            Wrap(
              spacing: Sp.withinGroup,
              runSpacing: Sp.withinGroup,
              children: [
                for (final h in s.highlights)
                  _HighlightCard(
                    h: h,
                    onOpen: h.matchId == null
                        ? null
                        : () => _open(app, h.matchId!),
                  ),
              ],
            ),
          if (s.versus.isNotEmpty && s.versusRole != null) ...[
            const SizedBox(height: Sp.betweenSections),
            SectionHeader(
              tr.daily.versusTitle(s.versusRole!.label),
              info: tr.daily.versusTip,
            ),
            const SizedBox(height: SectionHeader.below),
            _VersusTable(rows: s.versus),
          ],
          const SizedBox(height: Sp.betweenSections),
          LayoutBuilder(
            builder: (context, box) {
              final heroes = _GroupList(
                title: tr.daily.heroesTitle,
                groups: s.heroes,
                icon: (g) => NetImage(
                  app.catalog.heroIcon(
                    rows.values
                        .where((m) => m.hero != null && _key(m.hero!) == g.key)
                        .firstOrNull
                        ?.hero,
                  ),
                  size: 24,
                  fallback: g.label ?? '',
                ),
              );
              final maps = _GroupList(
                title: tr.daily.mapsTitle,
                groups: s.maps,
                icon: (g) => MapThumb(
                  app.catalog.mapImage(
                    rows.values
                        .where((m) => m.map != null && _key(m.map!) == g.key)
                        .firstOrNull
                        ?.map,
                  ),
                  width: 40,
                  height: 22,
                ),
              );
              if (box.maxWidth < 700) {
                return Column(
                  children: [
                    heroes,
                    const SizedBox(height: Sp.betweenSections),
                    maps,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: heroes),
                  const SizedBox(width: Sp.betweenSections),
                  Expanded(child: maps),
                ],
              );
            },
          ),
          const SizedBox(height: Sp.betweenSections),
          SectionHeader(tr.daily.matchesTitle),
          const SizedBox(height: SectionHeader.below),
          Panel(
            padding: PanelPadding.chart,
            child: Column(
              children: [
                for (final id in s.matchIds)
                  if (rows[id] != null)
                    Pressable(
                      onTap: () => _open(app, id),
                      semanticLabel: [
                        rows[id]!.outcome.label,
                        fmtDateTime(rows[id]!.startedAtMs),
                        rows[id]!.map?.label ?? tr.common.unknownMap,
                      ].join(' · '),
                      padding: const EdgeInsets.symmetric(
                        horizontal: Sp.withinGroup,
                        vertical: 4,
                      ),
                      child: _MatchLine(m: rows[id]!),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _key(EntityRef e) => e.officialId != null
    ? 'overwatch:${e.kind}:${e.officialId!.toLowerCase()}'
    : 'dashen:${e.kind}:${e.guid}';

class _HighlightCard extends StatelessWidget {
  const _HighlightCard({required this.h, required this.onOpen});
  final DayHighlight h;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final (
      IconData icon,
      Color color,
      String title,
      String value,
      String? note,
    ) = switch (h.kind) {
      HighlightKind.lobbyTop => (
        Icons.emoji_events_outlined,
        c.warning,
        tr.daily.lobbyTop(_stat(h.stat)),
        '× ${h.value.round()}',
        tr.daily.lobbyTopNote(h.value.round()),
      ),
      HighlightKind.personalRecord => (
        Icons.auto_awesome,
        c.positive,
        tr.daily.newRecord(_stat(h.stat)),
        _value(h.stat, h.value),
        h.previous == null
            ? null
            : tr.daily.recordNote(_value(h.stat, h.previous!)),
      ),
      HighlightKind.dayBest => (
        Icons.trending_up,
        c.accent,
        tr.daily.dayBest(_stat(h.stat)),
        _value(h.stat, h.value),
        null,
      ),
      HighlightKind.streak => (
        Icons.local_fire_department_outlined,
        c.positive,
        tr.daily.streak(h.value.round()),
        '${h.value.round()}',
        tr.daily.streakNote,
      ),
      HighlightKind.deathless => (
        Icons.shield_outlined,
        c.accent,
        tr.daily.deathless(h.value.round()),
        '${h.value.round()}',
        tr.daily.deathlessNote,
      ),
      HighlightKind.bestMatch => (
        Icons.star_outline,
        c.positive,
        tr.daily.bestMatch,
        fmtTwo(h.value),
        tr.daily.bestMatchNote,
      ),
      HighlightKind.bestFleta => (
        Icons.gps_fixed,
        c.accent,
        tr.daily.bestFleta,
        fmtOne(h.value),
        tr.daily.bestFletaNote,
      ),
      HighlightKind.unknown => (Icons.info_outline, c.accent, '', '', null),
    };
    final where = h.hero == null && h.map == null
        ? null
        : tr.daily.where(
            h.hero?.label ?? tr.common.unknownHero,
            h.map?.label ?? tr.common.unknownMap,
          );
    // One size for every card, so the grid reads as a grid.
    final card = SizedBox(
      width: 236,
      height: 112,
      child: SizedBox.expand(
        child: CardSurface(
          accent: color,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: Sp.withinGroup),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Ty.bodyStrong),
                    Text(value, style: Ty.num(Ty.title)),
                    if (note != null)
                      Text(
                        note,
                        style: Ty.meta.copyWith(color: c.textSecondary),
                      ),
                    if (where != null)
                      Text(
                        where,
                        style: Ty.meta.copyWith(color: c.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (onOpen == null) return card;
    return Pressable(
      onTap: onOpen,
      semanticLabel: [title, value, ?where].join(' · '),
      radius: 0,
      child: card,
    );
  }
}

class _VersusTable extends StatelessWidget {
  const _VersusTable({required this.rows});
  final List<Versus> rows;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final head = Ty.meta.copyWith(color: c.textSecondary);
    TableRow line(List<Widget> cells, {bool top = false}) => TableRow(
      decoration: top
          ? null
          : BoxDecoration(
              border: Border(top: BorderSide(color: c.grid)),
            ),
      children: [
        for (final w in cells)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            child: w,
          ),
      ],
    );
    Widget num(String t, {TextStyle? style}) =>
        Text(t, textAlign: TextAlign.right, style: style ?? Ty.num(Ty.body));
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Table(
            columnWidths: const {0: FlexColumnWidth(1.4)},
            children: [
              line([
                Text(tr.daily.versusStat, style: head),
                num(tr.daily.versusToday, style: head),
                num(tr.daily.versusUsual, style: head),
                num(tr.daily.versusDiff, style: head),
              ], top: true),
              for (final v in rows)
                () {
                  final better = v.stat == 'deaths'
                      ? v.today < v.usual
                      : v.today > v.usual;
                  final pct = v.usual == 0
                      ? null
                      : (v.today - v.usual) / v.usual * 100;
                  return line([
                    Text(_stat(v.stat), style: Ty.body),
                    num(_value(v.stat, v.today)),
                    num(_value(v.stat, v.usual)),
                    num(
                      pct == null
                          ? missing
                          : '${pct >= 0 ? '+' : '−'}${fmtPct(pct.abs(), digits: 0)}',
                      style: Ty.num(Ty.bodyStrong).copyWith(
                        color: pct == null || pct.abs() < 5
                            ? c.textSecondary
                            : better
                            ? c.positive
                            : c.negative,
                      ),
                    ),
                  ]);
                }(),
            ],
          ),
          const SizedBox(height: Sp.withinControl),
          Text(
            tr.daily.versusNote(rows.first.todayN, rows.first.usualN),
            style: head,
          ),
        ],
      ),
    );
  }
}

class _GroupList extends StatelessWidget {
  const _GroupList({
    required this.title,
    required this.groups,
    required this.icon,
  });
  final String title;
  final List<OverviewGroup> groups;
  final Widget Function(OverviewGroup) icon;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title),
        const SizedBox(height: SectionHeader.below),
        Panel(
          padding: PanelPadding.chart,
          child: Column(
            children: [
              for (final g in groups)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Sp.withinGroup,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      icon(g),
                      const SizedBox(width: Sp.withinGroup),
                      Expanded(
                        child: Text(
                          g.label ?? g.key,
                          style: Ty.body,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        tr.daily.groupRow(
                          g.aggregate.record.wins,
                          g.aggregate.record.losses,
                        ),
                        style: Ty.num(Ty.meta).copyWith(color: c.textSecondary),
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

class _MatchLine extends StatelessWidget {
  const _MatchLine({required this.m});
  final MatchSummary m;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = context.c;
    final s = m.stats;
    return Row(
      children: [
        OutcomeMark(m.outcome),
        const SizedBox(width: Sp.withinGroup),
        SizedBox(
          width: 52,
          child: Text(
            fmtDateTime(m.startedAtMs).substring(6),
            style: Ty.num(Ty.body),
          ),
        ),
        NetImage(
          app.catalog.heroIcon(m.hero),
          size: 24,
          fallback: m.hero?.label ?? '',
        ),
        const SizedBox(width: Sp.withinGroup),
        SizedBox(
          width: 110,
          child: Text(
            m.hero?.label ?? tr.common.unknownHero,
            style: Ty.body,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Expanded(
          child: Text(
            m.map?.label ?? tr.common.unknownMap,
            style: Ty.meta.copyWith(color: c.textSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(
          tr.people.kda(fmtInt(s.kills), fmtInt(s.deaths), fmtInt(s.assists)),
          style: Ty.num(Ty.body),
        ),
      ],
    );
  }
}
