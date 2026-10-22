import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/overview.dart';
import '../../core/support.dart';
import '../../design/cards.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';
import '../../l10n/strings.dart';
import '../../state/app_state.dart';

/// The overview's figures for this player and another one looked up in this session,
/// in the same mode and worked out the same way (stored matches only), with the
/// difference and both sample sizes; says so when the samples differ a lot.
class PlayerCompareSection extends StatefulWidget {
  const PlayerCompareSection({
    super.key,
    required this.workspace,
    required this.mode,
    required this.mine,
  });
  final PlayerWorkspace workspace;
  final Mode mode;
  final OverviewResult mine;

  @override
  State<PlayerCompareSection> createState() => _PlayerCompareSectionState();
}

class _PlayerCompareSectionState extends State<PlayerCompareSection> {
  String? _other;

  void _pick(AppState app, String name) {
    setState(() => _other = name);
    app.workspaceFor(name).loadOverview(widget.mode);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = context.c;
    // Everyone in the library and everyone looked up this run, but this player.
    final me = widget.workspace.name.toLowerCase();
    final names = <String>{};
    for (final n in [
      ...app.players,
      for (final w in app.workspaces.values) w.name,
    ]) {
      if (n.toLowerCase() != me &&
          !names.any((x) => x.toLowerCase() == n.toLowerCase())) {
        names.add(n);
      }
    }
    final others = names.toList();
    final other = _other == null ? null : app.workspaceFor(_other!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(tr.compare.playersTitle, info: tr.compare.playersTip),
        const SizedBox(height: SectionHeader.below),
        if (others.isEmpty)
          Text(
            tr.compare.playersNone,
            style: Ty.body.copyWith(color: c.textSecondary),
          )
        else ...[
          Wrap(
            spacing: Sp.withinGroup,
            runSpacing: Sp.withinGroup,
            children: [
              for (final n in others)
                AppButton(
                  n,
                  quiet: n != _other,
                  primary: n == _other,
                  onPressed: () => _pick(app, n),
                ),
            ],
          ),
          if (other != null) ...[
            const SizedBox(height: Sp.betweenGroups),
            ListenableBuilder(
              listenable: other,
              builder: (context, _) {
                final load = other.overviewFor(widget.mode);
                final theirs = load.value;
                if (load.failedWithoutData) {
                  return ErrorPanel(
                    what: tr.compare.playersTitle,
                    error: load.error!,
                    onRetry: () => other.loadOverview(widget.mode),
                  );
                }
                if (theirs?.overview == null) {
                  return Text(
                    tr.compare.loadingOther,
                    style: Ty.meta.copyWith(color: c.textSecondary),
                  );
                }
                return _Table(
                  a: widget.workspace.name,
                  b: other.name,
                  mine: widget.mine,
                  theirs: theirs!,
                );
              },
            ),
          ],
        ],
      ],
    );
  }
}

class _Table extends StatelessWidget {
  const _Table({
    required this.a,
    required this.b,
    required this.mine,
    required this.theirs,
  });
  final String a, b;
  final OverviewResult mine, theirs;

  static String _diff(double? x, double? y, String Function(double) f) {
    if (x == null || y == null) return tr.compare.onlyOne;
    final d = x - y;
    if (f(d.abs()) == f(0)) return '±${f(0)}';
    return '${d > 0 ? '+' : '−'}${f(d.abs())}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final x = mine.overview!, y = theirs.overview!;
    String pct(double v) => fmtPct(v, digits: 0);
    final rows = <(String, double?, double?, String Function(double))>[
      (
        tr.compare.rowRecentRate,
        x.recent.record.winRatePct,
        y.recent.record.winRatePct,
        pct,
      ),
      (
        tr.compare.rowOverallRate,
        x.overall.record.winRatePct,
        y.overall.record.winRatePct,
        pct,
      ),
      (tr.compare.rowKda, x.overall.kda, y.overall.kda, fmtTwo),
      (
        tr.compare.rowKills,
        x.overall.perMatch.kills,
        y.overall.perMatch.kills,
        fmtOne,
      ),
      (
        tr.compare.rowDeaths,
        x.overall.perMatch.deaths,
        y.overall.perMatch.deaths,
        fmtOne,
      ),
      (
        tr.compare.rowDamage,
        x.overall.perMatch.damage,
        y.overall.perMatch.damage,
        fmtInt,
      ),
      (
        tr.compare.rowHealing,
        x.overall.perMatch.healing,
        y.overall.perMatch.healing,
        fmtInt,
      ),
    ];
    final n = mine.listed, m = theirs.listed;
    final head = Ty.meta.copyWith(color: c.textSecondary);
    TableRow line(List<String> cells, {bool top = false}) => TableRow(
      decoration: top
          ? null
          : BoxDecoration(
              border: Border(top: BorderSide(color: c.grid)),
            ),
      children: [
        for (final (i, t) in cells.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(
              vertical: Sp.iconGap,
              horizontal: Sp.withinGroup,
            ),
            child: Text(
              t,
              textAlign: i == 0 ? TextAlign.left : TextAlign.right,
              style: top ? head : (i == 0 ? Ty.body : Ty.num(Ty.body)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
    final uneven = n > 0 && m > 0 && (n > 3 * m || m > 3 * n);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (uneven)
          Padding(
            padding: const EdgeInsets.only(bottom: Sp.withinGroup),
            child: StatusBanner(
              severity: Severity.warning,
              title: tr.compare.samplesDiffer,
            ),
          ),
        Panel(
          child: Table(
            columnWidths: const {0: FlexColumnWidth(1.4)},
            children: [
              line([
                tr.compare.statColumn,
                a,
                b,
                tr.compare.diffColumn,
              ], top: true),
              for (final (label, vx, vy, f) in rows)
                line([
                  label,
                  vx == null ? tr.compare.onlyOne : f(vx),
                  vy == null ? tr.compare.onlyOne : f(vy),
                  _diff(vx, vy, f),
                ]),
            ],
          ),
        ),
        const SizedBox(height: Sp.withinGroup),
        Text(tr.compare.samples(a, n, b, m), style: head),
      ],
    );
  }
}
