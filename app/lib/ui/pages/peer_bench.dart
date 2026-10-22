import 'package:flutter/material.dart';

import '../../core/benchmark.dart';
import '../../core/models.dart';
import '../../core/support.dart';
import '../../design/cards.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';
import '../../l10n/strings.dart';
import '../../state/app_state.dart';

/// How the player's typical match on a hero compares with other players on it, at about
/// their rank, in the matches stored here (`watch_core::benchmark`). Every figure says
/// whom it is compared with and how many matches that rests on, and that the sample is
/// this machine's, not the server's.
class PeerBenchSection extends StatefulWidget {
  const PeerBenchSection({
    super.key,
    required this.workspace,
    required this.mode,
    required this.hero,
    required this.accent,
  });
  final PlayerWorkspace workspace;
  final Mode mode;
  final EntityRef hero;
  final Color accent;

  @override
  State<PeerBenchSection> createState() => _PeerBenchSectionState();
}

class _PeerBenchSectionState extends State<PeerBenchSection> {
  @override
  void initState() {
    super.initState();
    if (widget.mode != Mode.stadium) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => widget.workspace.loadBenchmark(widget.mode),
      );
    }
  }

  static String _metric(BenchMetric m) => switch (m) {
    BenchMetric.damage => tr.heroes.metricDamage,
    BenchMetric.healing => tr.heroes.metricHealing,
    BenchMetric.mitigation => tr.heroes.metricMitigation,
    BenchMetric.eliminations => tr.heroes.metricEliminations,
    BenchMetric.finalBlows => tr.heroes.metricFinalBlows,
    BenchMetric.deaths => tr.heroes.metricDeaths,
    BenchMetric.unknown => '',
  };

  static String _band(Band b) => switch (b) {
    Band.poor => tr.heroes.bandPoor,
    Band.subpar => tr.heroes.bandSubpar,
    Band.average => tr.heroes.bandAverage,
    Band.good => tr.heroes.bandGood,
    Band.great => tr.heroes.bandGreat,
  };

  static String _figure(BenchMetric m, double v) =>
      m == BenchMetric.damage ||
          m == BenchMetric.healing ||
          m == BenchMetric.mitigation
      ? fmtInt(v)
      : fmtOne(v);

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final load = widget.workspace.benchmarkFor(widget.mode);
    final bench = load.value?.of(widget.hero);
    Widget body;
    if (widget.mode == Mode.stadium) {
      body = _note(context, tr.heroes.peerStadium);
    } else if (bench == null) {
      body = load.loading || !load.has
          ? AfterDelay(child: _note(context, tr.heroes.peerLoading))
          : _note(context, tr.heroes.peerNone);
    } else {
      final first = bench.metrics.first;
      final band = first.peerTiers.isEmpty
          ? tr.heroes.anyRank
          : tr.heroes.tierRange(
              tierName(first.peerTiers.first) ?? first.peerTiers.first,
              tierName(first.peerTiers.last) ?? first.peerTiers.last,
            );
      body = Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final m in bench.metrics.where(
              (m) => m.metric != BenchMetric.unknown,
            ))
              _row(context, m),
            const SizedBox(height: Sp.withinGroup),
            Text(
              tr.heroes.peerSource(
                band,
                widget.hero.label,
                first.peerMatches,
                load.value!.matches,
              ),
              style: Ty.meta.copyWith(color: c.textSecondary),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          tr.heroes.peerTitle,
          accent: widget.accent,
          info: tr.heroes.peerInfo,
        ),
        const SizedBox(height: SectionHeader.below),
        body,
      ],
    );
  }

  Widget _note(BuildContext context, String text) =>
      Text(text, style: Ty.body.copyWith(color: context.c.textSecondary));

  Widget _row(BuildContext context, MetricBench m) {
    final c = context.c;
    final p = m.percentile.round().clamp(0, 100);
    final color = switch (m.band) {
      Band.poor => c.negative,
      Band.subpar => c.negative.withValues(alpha: 0.6),
      Band.average => c.textSecondary,
      Band.good => c.positive.withValues(alpha: 0.7),
      Band.great => c.positive,
    };
    final name = _metric(m.metric);
    final value = tr.heroes.perTen(_figure(m.metric, m.value));
    return Semantics(
      label: tr.heroes.peerRow(
        name,
        value,
        p,
        _band(m.band),
        _figure(m.metric, m.peerMedian),
      ),
      excludeSemantics: true,
      child: SizedBox(
        height: 34,
        child: Row(
          children: [
            SizedBox(width: 80, child: Text(name, style: Ty.body)),
            SizedBox(
              width: 112,
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: Ty.num(Ty.bodyStrong),
              ),
            ),
            const SizedBox(width: Sp.betweenGroups),
            Expanded(
              child: Tooltip(
                message: tr.heroes.peerMedian(_figure(m.metric, m.peerMedian)),
                child: LayoutBuilder(
                  builder: (context, box) => Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      Container(height: 8, color: c.grid),
                      Container(
                        width: box.maxWidth * p / 100,
                        height: 8,
                        color: color,
                      ),
                      // The peers' middle: the 50th percentile.
                      Positioned(
                        left: box.maxWidth / 2 - 0.5,
                        top: 9,
                        bottom: 9,
                        child: Container(width: 1, color: c.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: Sp.betweenGroups),
            SizedBox(
              width: 130,
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: tr.heroes.percentile(p),
                      style: Ty.num(Ty.body),
                    ),
                    TextSpan(
                      text: '  ${_band(m.band)}',
                      style: Ty.meta.copyWith(color: color),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
