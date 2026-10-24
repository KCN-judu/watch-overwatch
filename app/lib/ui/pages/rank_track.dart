import 'package:flutter/material.dart';

import '../../core/metric_doc.dart';
import '../../core/models.dart';
import '../../core/ranks.dart';
import '../../core/support.dart';
import '../../design/cards.dart';
import '../../design/charts.dart';
import '../../design/icons.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';
import '../../l10n/strings.dart';
import '../../state/app_state.dart';

/// The rating each role's matches reported, one stepped line per role with season
/// dividers (`watch_core::ranks`); a point opens its match. Below it, the recent
/// stretches of lost rating and how strong the other side was in them.
class RankTrackSection extends StatefulWidget {
  const RankTrackSection({
    super.key,
    required this.workspace,
    required this.mode,
    required this.seasonMatches,
  });
  final PlayerWorkspace workspace;
  final Mode mode;

  /// Each season's career match count, from the season trend.
  final Map<int, int> seasonMatches;

  @override
  State<RankTrackSection> createState() => _RankTrackSectionState();
}

class _RankTrackSectionState extends State<RankTrackSection> {
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(RankTrackSection old) {
    super.didUpdateWidget(old);
    if (old.mode != widget.mode ||
        !_same(old.seasonMatches, widget.seasonMatches)) {
      _load();
    }
  }

  static bool _same(Map<int, int> a, Map<int, int> b) =>
      a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

  void _load() => WidgetsBinding.instance.addPostFrameCallback(
    (_) => widget.workspace.loadRanks(widget.mode, widget.seasonMatches),
  );

  void _open(String id, List<String> ids) {
    widget.workspace.openMatch(widget.mode, id, ids);
    AppScope.read(context).setTab('matches');
  }

  String _label(double v) =>
      ratingLabel(v, stadium: widget.mode == Mode.stadium) ??
      tr.analysis.points(fmtInt(v));

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final load = widget.workspace.ranksFor(widget.mode);
    final r = load.value;
    final Widget body;
    if (load.failedWithoutData) {
      body = ErrorPanel(
        what: tr.analysis.tracksTitle,
        error: load.error!,
        onRetry: _load,
      );
    } else if (r == null) {
      body = const AfterDelay(child: Center(child: Spinner()));
    } else if (r.roles.every((t) => t.points.isEmpty)) {
      body = Text(
        tr.analysis.tracksNone,
        style: Ty.body.copyWith(color: c.textSecondary),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final t in r.roles)
            if (t.points.isNotEmpty) ...[
              _track(context, t),
              const SizedBox(height: Sp.betweenGroups),
            ],
          if (r.drops.isNotEmpty) ...[
            SectionHeader(
              tr.analysis.dropsTitle,
              info: tr.analysis.dropsTip,
              infoDoc: MetricDoc.strength,
            ),
            const SizedBox(height: SectionHeader.below),
            for (final d in r.drops) _drop(context, d),
          ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          tr.analysis.tracksTitle,
          info: tr.analysis.tracksTip,
          infoDoc: MetricDoc.rating,
        ),
        const SizedBox(height: SectionHeader.below),
        body,
      ],
    );
  }

  Widget _track(BuildContext context, RoleTrack t) {
    final c = context.c;
    final summary = tr.analysis.trackSummary(
      t.role.label,
      _label(t.points.first.skillRating.toDouble()),
      _label(t.points.last.skillRating.toDouble()),
      t.points.length,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            RoleIcon(t.role, size: 18, showLabel: true),
            const SizedBox(width: Sp.withinGroup),
            Expanded(
              child: Text(
                summary,
                style: Ty.meta.copyWith(color: c.textSecondary),
              ),
            ),
          ],
        ),
        const SizedBox(height: Sp.withinControl),
        Panel(
          padding: PanelPadding.chart,
          child: LineChart(
            height: 180,
            tickStep: 100,
            series: [
              ChartSeries(
                label: t.role.label,
                color: c.accent,
                stepped: true,
                values: [for (final p in t.points) p.skillRating.toDouble()],
              ),
            ],
            xLabels: [for (final p in t.points) fmtDate(p.atMs)],
            pointNotes: [
              for (final p in t.points)
                [
                  p.outcome.label,
                  if (p.season != null) tr.common.season(p.season!),
                ].join(tr.common.sep),
            ],
            hollow: [for (final p in t.points) p.outcome == Outcome.loss],
            hollowMeaning: tr.analysis.hollowMeaning,
            markers: [
              for (var i = 1; i < t.points.length; i++)
                if (t.points[i].season != null &&
                    t.points[i].season != t.points[i - 1].season)
                  (
                    index: i,
                    label: tr.analysis.seasonMark(t.points[i].season!),
                  ),
            ],
            valueFormat: _label,
            axisFormat: _label,
            detailFormat: widget.mode == Mode.stadium
                ? null
                : (v) => tr.analysis.points(fmtInt(v)),
            summary: summary,
            onOpen: (i) => _open(t.points[i].matchId, [
              for (final p in t.points.reversed) p.matchId,
            ]),
            openHint: tr.analysis.trackOpenHint,
          ),
        ),
      ],
    );
  }

  Widget _drop(BuildContext context, RankDrop d) {
    final c = context.c;
    final edge = d.meanEnemyEdge;
    final String? edgeText;
    if (edge == null) {
      edgeText = null;
    } else if (edge.round().abs() < 25) {
      edgeText = tr.analysis.edgeEven;
    } else if (edge > 0) {
      edgeText = tr.analysis.edgeHigher(edge.round());
    } else {
      edgeText = tr.analysis.edgeLower(-edge.round());
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.withinGroup),
      child: IntrinsicHeight(
        child: CardSurface(
          accent: c.negative,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr.analysis.drop(
                        d.role.label,
                        fmtDate(d.fromMs),
                        fmtDate(d.toMs),
                        d.fromRating - d.toRating,
                        d.matches,
                        d.wins,
                        d.losses,
                      ),
                      style: Ty.bodyStrong,
                    ),
                    const SizedBox(height: Sp.hairline),
                    Text(
                      edgeText == null
                          ? tr.analysis.dropNoEdge
                          : tr.analysis.dropEdge(d.rated, edgeText),
                      style: Ty.meta.copyWith(color: c.textSecondary),
                    ),
                  ],
                ),
              ),
              AppButton(
                tr.analysis.openDropMatch,
                quiet: true,
                onPressed: () => _open(d.toMatchId, [d.toMatchId]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
