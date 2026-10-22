import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import 'interaction.dart';
import 'tokens.dart';

// The smaller charts beside [LineChart]. Each answers one question (docs/ui-design.md §7):
//  - [Sparkline]: which way is it going? (no axes, a shape and a last point);
//  - [IntervalBars]: which of these is highest, and is the difference real? (bars from
//    zero, the plausible range as a whisker, the sample size, a reference line);
//  - [HourHeatmap]: when does it go well? (weekday × hour, cells too thin left empty).
// They are built from widgets, not painted, so every value is reachable by a screen
// reader and the rows can be pressed.

/// A tiny line without axes: only the direction. The last point is marked; `null`
/// values break the line. Always next to the number it belongs to.
class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.values,
    required this.label,
    required this.format,
    this.color,
    this.width = 80,
    this.height = 24,
  });
  final List<double?> values;
  final String label;
  final String Function(double) format;
  final Color? color;
  final double width, height;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final known = values.whereType<double>().toList();
    final summary = known.length < 2
        ? label
        : tr.shell.sparkline(label, format(known.first), format(known.last));
    return Semantics(
      label: summary,
      excludeSemantics: true,
      child: CustomPaint(
        size: Size(width, height),
        painter: _SparkPainter(values, color ?? c.accent, c.raised),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values, this.color, this.back);
  final List<double?> values;
  final Color color, back;

  @override
  void paint(Canvas canvas, Size size) {
    final known = values.whereType<double>();
    if (known.length < 2) return;
    final lo = known.reduce(math.min), hi = known.reduce(math.max);
    final span = hi - lo < 1e-9 ? 1.0 : hi - lo;
    const pad = 3.0;
    double x(int i) =>
        pad +
        (size.width - 2 * pad) *
            (values.length <= 1 ? 0.5 : i / (values.length - 1));
    double y(double v) => pad + (size.height - 2 * pad) * (1 - (v - lo) / span);
    final line = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    Path? run;
    Offset? last;
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (v == null) {
        if (run != null) canvas.drawPath(run, line);
        run = null;
        continue;
      }
      final p = Offset(x(i), y(v));
      run == null ? run = (Path()..moveTo(p.dx, p.dy)) : run.lineTo(p.dx, p.dy);
      last = p;
    }
    if (run != null) canvas.drawPath(run, line);
    if (last != null) {
      canvas.drawCircle(last, 3, Paint()..color = back);
      canvas.drawCircle(last, 2.5, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.values != values || old.color != color;
}

/// One row of [IntervalBars].
class IntervalRow {
  const IntervalRow({
    required this.label,
    required this.value,
    required this.n,
    this.low,
    this.high,
    this.leading,
    this.enough = true,
    this.onTap,
    this.selected = false,
  });
  final String label;
  final double value;
  final double? low, high;

  /// How many matches the value is over; always shown.
  final int n;

  /// False when [n] is too small to compare: the row is drawn grey and says so.
  final bool enough;
  final Widget? leading;

  /// Drill down (filter the match list to this map, open this hero).
  final VoidCallback? onTap;

  /// The row whose details are shown beside the bars.
  final bool selected;
}

/// Horizontal bars from zero, one per thing compared (maps, heroes), with the plausible
/// range as a thin whisker and the match count beside every value, against an optional
/// reference line (50 %, or the player's overall rate). Bars of rows with too few matches
/// are grey: they are listed, not ranked.
class IntervalBars extends StatelessWidget {
  const IntervalBars({
    super.key,
    required this.rows,
    required this.format,
    this.max = 100,
    this.reference,
    this.referenceMeaning,
    this.labelWidth = 150,
  });
  final List<IntervalRow> rows;
  final String Function(double) format;

  /// The scale's right end (100 for percentages).
  final double max;
  final double? reference;

  /// What the reference line is, said under the bars (e.g. “该玩家的总胜率 51%”).
  final String? referenceMeaning;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final r in rows) _row(context, r),
        if (referenceMeaning != null) ...[
          const SizedBox(height: Sp.withinControl),
          Text(
            tr.shell.intervalMeaning(referenceMeaning!),
            style: Ty.meta.copyWith(color: c.textSecondary),
          ),
        ],
      ],
    );
  }

  Widget _row(BuildContext context, IntervalRow r) {
    final c = context.c;
    final color = r.enough ? c.accent : c.textSecondary.withValues(alpha: 0.5);
    final range = r.low != null && r.high != null
        ? '${format(r.low!)}–${format(r.high!)}'
        : null;
    final spoken = r.enough && range != null
        ? tr.shell.intervalRow(r.label, format(r.value), range, r.n)
        : tr.shell.intervalRowTooFew(r.label, format(r.value), r.n);
    final body = SizedBox(
      height: 32,
      child: Row(
        children: [
          SizedBox(
            width: labelWidth,
            child: Row(
              children: [
                if (r.leading != null) ...[
                  r.leading!,
                  const SizedBox(width: Sp.withinGroup),
                ],
                Expanded(
                  child: Text(
                    r.label,
                    style: Ty.body,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                double x(double v) => box.maxWidth * (v / max).clamp(0.0, 1.0);
                return Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    Container(height: 10, color: c.grid),
                    Container(width: x(r.value), height: 10, color: color),
                    if (r.low != null && r.high != null)
                      Positioned(
                        left: x(r.low!),
                        width: math.max(1, x(r.high!) - x(r.low!)),
                        child: Container(
                          height: 2,
                          color: c.textPrimary.withValues(alpha: 0.7),
                        ),
                      ),
                    if (reference != null)
                      Positioned(
                        left: x(reference!) - 0.5,
                        top: 4,
                        bottom: 4,
                        child: Container(width: 1, color: c.textSecondary),
                      ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(width: Sp.withinGroup),
          SizedBox(
            width: 112,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: format(r.value),
                    style: Ty.num(Ty.bodyStrong).copyWith(
                      color: r.enough ? c.textPrimary : c.textSecondary,
                    ),
                  ),
                  TextSpan(
                    text: '  ${tr.common.matchCount(r.n)}',
                    style: Ty.num(Ty.meta).copyWith(color: c.textSecondary),
                  ),
                ],
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
    if (r.onTap == null) {
      return Semantics(label: spoken, excludeSemantics: true, child: body);
    }
    return Pressable(
      onTap: r.onTap,
      semanticLabel: spoken,
      selected: r.selected,
      radius: 0,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: body,
    );
  }
}

/// One cell of [HourHeatmap]: a value over [n] matches (e.g. a win rate).
class HeatCell {
  const HeatCell(this.value, this.n);
  final double? value;
  final int n;
}

/// Weekday × hour of day. A cell is coloured by how far its value is from [center]
/// (above in the positive colour, below in the negative one, the further the stronger);
/// cells with fewer than [minN] matches are left empty, so thin evidence is not
/// painted as a pattern. Every cell says its exact value and count on hover.
class HourHeatmap extends StatelessWidget {
  const HourHeatmap({
    super.key,
    required this.cells,
    required this.format,
    required this.metric,
    this.center = 50,
    this.spread = 25,
    this.minN = 3,
  });

  /// `cells[weekday][hour]`, Monday first.
  final List<List<HeatCell>> cells;
  final String Function(double) format;

  /// What the value is, for the explanation (e.g. 胜率).
  final String metric;
  final double center, spread;
  final int minN;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final days = tr.shell.weekdaysShort;
    Color fill(HeatCell cell) {
      final v = cell.value;
      if (v == null || cell.n < minN) return Colors.transparent;
      final t = ((v - center) / spread).clamp(-1.0, 1.0);
      final base = t >= 0 ? c.positive : c.negative;
      return base.withValues(alpha: 0.12 + 0.68 * t.abs());
    }

    return LayoutBuilder(
      builder: (context, box) {
        const labelW = 24.0;
        final side = math.min(22.0, (box.maxWidth - labelW) / 24 - 2);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var d = 0; d < 7 && d < cells.length; d++)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  children: [
                    SizedBox(
                      width: labelW,
                      child: Text(
                        days[d],
                        style: Ty.meta.copyWith(color: c.textSecondary),
                      ),
                    ),
                    for (var h = 0; h < 24 && h < cells[d].length; h++)
                      Padding(
                        padding: const EdgeInsets.only(right: 2),
                        child: Tooltip(
                          message:
                              cells[d][h].n < minN || cells[d][h].value == null
                              ? tr.shell.heatCellTooFew(
                                  days[d],
                                  h,
                                  cells[d][h].n,
                                )
                              : tr.shell.heatCell(
                                  days[d],
                                  h,
                                  format(cells[d][h].value!),
                                  cells[d][h].n,
                                ),
                          child: Container(
                            width: side,
                            height: side,
                            decoration: BoxDecoration(
                              color: fill(cells[d][h]),
                              border: Border.all(color: c.grid),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(left: labelW),
              child: SizedBox(
                width: (side + 2) * 24,
                child: Row(
                  children: [
                    for (var h = 0; h < 24; h += 3)
                      SizedBox(
                        width: (side + 2) * 3,
                        child: Text(
                          tr.shell.hourTick(h),
                          style: Ty.num(
                            Ty.meta,
                          ).copyWith(color: c.textSecondary),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Sp.withinControl),
            Text(
              tr.shell.heatMeaning(metric, minN),
              style: Ty.meta.copyWith(color: c.textSecondary),
            ),
          ],
        );
      },
    );
  }
}
