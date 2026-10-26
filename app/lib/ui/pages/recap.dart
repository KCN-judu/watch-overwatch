import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/overview.dart';
import '../../core/support.dart';
import '../../design/dialog.dart';
import '../../design/headline.dart';
import '../../design/share.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';
import '../../l10n/strings.dart';
import '../../state/app_state.dart';

/// A recap of the stored matches told one step at a time: how many and how they went,
/// the hero played most, the best map (guess first, then see), the measure that improved
/// most, the best match. Every step can be shown at once and saved as one long picture.
Future<void> showRecap(
  BuildContext context, {
  required PlayerWorkspace workspace,
  required Mode mode,
  required Overview overview,
  required int listed,
}) {
  workspace.loadGrowth(mode);
  return showDialog<void>(
    context: context,
    builder: (context) => AppDialog(
      title: tr.recap.title,
      width: 720,
      maxHeight: 720,
      child: ListenableBuilder(
        listenable: workspace,
        builder: (context, _) => _Recap(
          workspace: workspace,
          mode: mode,
          o: overview,
          listed: listed,
        ),
      ),
    ),
  );
}

/// One step: a heading, the big figure and what it means, over the step's picture (a
/// hero's banner, a map) in the hero's colour.
typedef _Step = ({
  String title,
  String value,
  String note,
  Widget? extra,
  String? art,
  EntityRef? hero,
});

class _Recap extends StatefulWidget {
  const _Recap({
    required this.workspace,
    required this.mode,
    required this.o,
    required this.listed,
  });
  final PlayerWorkspace workspace;
  final Mode mode;
  final Overview o;

  /// Stored matches the overview is worked out from.
  final int listed;

  @override
  State<_Recap> createState() => _RecapState();
}

class _RecapState extends State<_Recap> {
  int _at = 0;
  bool _all = false;

  /// The map the user guessed as their best, before it is revealed.
  String? _guess;

  Overview get _o => widget.o;

  /// The map with the best evidence of a high rate (low end of its range), among maps
  /// with enough matches; then the three most played of those as the choices.
  List<OverviewGroup> get _mapChoices {
    final enough = _o.byMap
        .where((g) => g.key != 'unknown' && g.aggregate.record.enough)
        .toList();
    return enough.take(3).toList();
  }

  OverviewGroup? get _bestMap {
    final choices = _mapChoices;
    if (choices.isEmpty) return null;
    return choices.reduce(
      (a, b) =>
          (a.aggregate.record.lowPct ?? 0) >= (b.aggregate.record.lowPct ?? 0)
          ? a
          : b,
    );
  }

  /// The winning match with the best KDA among the stored ones.
  MatchSummary? get _bestMatch {
    MatchSummary? best;
    double? bestKda;
    for (final m
        in widget.workspace.matchesFor(widget.mode).value?.matches ??
            const <MatchSummary>[]) {
      if (m.outcome != Outcome.win) continue;
      final k = m.stats.kills, a = m.stats.assists, d = m.stats.deaths;
      if (k == null || a == null || d == null) continue;
      final kda = (k + a) / (d == 0 ? 1 : d);
      if (bestKda == null || kda > bestKda) {
        best = m;
        bestKda = kda;
      }
    }
    return best;
  }

  String _metricName(GrowthMetric m) => switch (m) {
    GrowthMetric.life => tr.analysis.lifeCard,
    GrowthMetric.fleta => tr.analysis.fletaCard,
    GrowthMetric.kda => 'KDA',
    GrowthMetric.healing => tr.analysis.healingTitle,
    GrowthMetric.mitigation => tr.analysis.mitigationTitle,
  };

  List<_Step> _steps(BuildContext context) {
    final o = _o;
    final r = o.overall.record;
    final week = o.windows['week']?.record;
    final hero = o.byHero.where((g) => g.key != 'unknown').firstOrNull;
    final best = _bestMap;
    final growth = widget.workspace.growthFor(widget.mode).value;
    final improved = [
      for (final m in growth?.metrics ?? const <MetricGrowth>[])
        if (m.metric != null && m.growth?.trend == Trend.up) m,
    ]..sort((a, b) => b.growth!.changePct.compareTo(a.growth!.changePct));
    final match = _bestMatch;
    final catalog = widget.workspace.app.catalog;
    final heroRef = hero == null ? null : _heroRef(hero.key);
    final banner = catalog.heroBanner(heroRef);
    final shown = !(_guess == null && !_all);
    return [
      (
        title: tr.recap.stepMatches,
        value: tr.common.matchCount(r.matches),
        note: tr.recap.matchesNote(
          fmtPct(r.winRatePct, digits: 0),
          r.wins,
          r.losses,
          week == null || week.matches == 0
              ? null
              : tr.overview.record(week.wins, week.losses, week.draws),
        ),
        extra: null,
        art: banner,
        hero: heroRef,
      ),
      if (hero != null)
        (
          title: tr.recap.stepHero,
          value: hero.label ?? hero.key,
          note: tr.recap.heroNote(
            hero.aggregate.record.matches,
            fmtPct(hero.aggregate.record.winRatePct, digits: 0),
          ),
          extra: null,
          art: banner,
          hero: heroRef,
        ),
      if (best != null)
        (
          title: tr.recap.stepMap,
          value: _guess == null && !_all ? '?' : (best.label ?? best.key),
          note: _guess == null && !_all
              ? tr.recap.guessPrompt
              : tr.recap.mapNote(
                  best.aggregate.record.matches,
                  fmtPct(best.aggregate.record.winRatePct, digits: 0),
                  _guess == null
                      ? null
                      : _guess == best.key
                      ? tr.recap.guessRight
                      : tr.recap.guessWrong,
                ),
          extra: _guess == null && !_all
              ? Wrap(
                  spacing: Sp.withinGroup,
                  children: [
                    for (final g in _mapChoices)
                      AppButton(
                        g.label ?? g.key,
                        onPressed: () => setState(() => _guess = g.key),
                      ),
                  ],
                )
              : null,
          art: shown ? catalog.mapImage(_mapRef(best.key)) : null,
          hero: null,
        ),
      if (improved.isNotEmpty)
        (
          title: tr.recap.stepImproved,
          value: _metricName(improved.first.metric!),
          note: tr.recap.improvedNote(
            fmtPct(improved.first.growth!.changePct.abs(), digits: 0),
            improved.first.growth!.matches,
          ),
          extra: null,
          art: null,
          hero: null,
        ),
      if (match != null)
        (
          title: tr.recap.stepBest,
          value: fmtEad(match.stats),
          note: tr.recap.bestNote(
            match.hero?.label ?? tr.common.unknownHero,
            match.map?.label ?? tr.common.unknownMap,
            fmtDateTime(match.startedAtMs),
          ),
          extra: AppButton(
            tr.recap.openBest,
            quiet: true,
            onPressed: () {
              Navigator.of(context).pop();
              widget.workspace.openMatch(widget.mode, match.id, [match.id]);
              widget.workspace.app.setTab('matches');
            },
          ),
          art: catalog.heroBanner(match.hero),
          hero: match.hero,
        ),
    ];
  }

  /// A group's key back to the hero (or map) of a stored match, for its picture.
  EntityRef? _heroRef(String key) => _find(key, (m) => m.hero);
  EntityRef? _mapRef(String key) => _find(key, (m) => m.map);
  EntityRef? _find(String key, EntityRef? Function(MatchSummary) of) {
    for (final m
        in widget.workspace.matchesFor(widget.mode).value?.matches ??
            const <MatchSummary>[]) {
      final e = of(m);
      if (e != null && groupKey(e) == key) return e;
    }
    return null;
  }

  Widget _card(BuildContext context, _Step s, {bool big = false}) {
    final c = context.c;
    final style = big ? Ty.display : Ty.figure;
    final hasDigits = s.value.contains(RegExp('[0-9]'));
    return HeadlineBand(
      art: s.art,
      tint: heroTint(context, s.hero),
      eyebrow: Text(s.title, style: Ty.meta.copyWith(color: c.textSecondary)),
      figures: [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasDigits)
              FigureText(s.value, style: style)
            else
              Text(s.value, style: big ? Ty.display : Ty.title),
            const SizedBox(height: Sp.withinControl),
            Text(s.note, style: Ty.body),
            if (s.extra != null) ...[
              const SizedBox(height: Sp.betweenGroups),
              s.extra!,
            ],
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final steps = _steps(context);
    final at = _at.clamp(0, steps.length - 1);
    final name = widget.workspace.app.maskName(widget.workspace.name);
    final caption = tr.recap.caption(name, widget.mode.label, widget.listed);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                caption,
                style: Ty.meta.copyWith(color: c.textSecondary),
              ),
            ),
            AppButton(
              _all ? tr.recap.stepByStep : tr.recap.showAll,
              quiet: true,
              onPressed: () => setState(() => _all = !_all),
            ),
          ],
        ),
        const SizedBox(height: Sp.betweenGroups),
        Expanded(
          child: _all
              ? SingleChildScrollView(
                  padding: const EdgeInsets.only(right: scrollGutter),
                  child: Shareable(
                    title: tr.recap.title,
                    caption: caption,
                    fileName: tr.recap.fileName,
                    child: Column(
                      children: [
                        for (final s in steps) ...[
                          _card(context, s),
                          const SizedBox(height: Sp.withinGroup),
                        ],
                      ],
                    ),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Center(
                        child: _card(context, steps[at], big: true),
                      ),
                    ),
                    const SizedBox(height: Sp.betweenGroups),
                    Row(
                      children: [
                        AppButton(
                          tr.recap.previous,
                          quiet: true,
                          onPressed: at > 0
                              ? () => setState(() => _at = at - 1)
                              : null,
                        ),
                        Expanded(
                          child: Text(
                            tr.recap.position(at + 1, steps.length),
                            textAlign: TextAlign.center,
                            style: Ty.num(
                              Ty.meta,
                            ).copyWith(color: c.textSecondary),
                          ),
                        ),
                        AppButton(
                          at < steps.length - 1
                              ? tr.recap.next
                              : tr.recap.showAll,
                          primary: true,
                          onPressed: () => setState(() {
                            if (at < steps.length - 1) {
                              _at = at + 1;
                            } else {
                              _all = true;
                            }
                          }),
                        ),
                      ],
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}
