import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/strings.dart';
import 'interaction.dart';
import 'motion.dart';
import 'tokens.dart';

class ChartSeries {
  const ChartSeries({
    required this.label,
    required this.color,
    required this.values,
    this.dashed = false,
    this.lows,
    this.highs,
    this.counts,
    this.countNotes,
    this.stepped = false,
  });
  final String label;
  final Color color;
  final List<double?>
  values; // null = no data: the line breaks, never drops to zero
  final bool dashed;

  /// Holds each value until the next one (a rank stays until it changes), instead of
  /// drawing a slope between them.
  final bool stepped;

  /// Optional spread behind each value (lowest and highest of what the value
  /// averages), drawn as a vertical bar through the point.
  final List<double?>? lows, highs;

  /// How many players each value averages (shown in the readout of that series).
  final List<int?>? counts;

  /// A line under the count in the readout of that value, when there is something to say.
  final List<String?>? countNotes;
  bool hasRange(int i) =>
      lows != null &&
      highs != null &&
      i < lows!.length &&
      i < highs!.length &&
      lows![i] != null &&
      highs![i] != null;
}

/// A shaded range behind the lines: what counts as usual (the player's own recent
/// spread, a peer range). A point outside it is the one worth looking at.
class ChartBand {
  const ChartBand({
    required this.lows,
    required this.highs,
    required this.meaning,
  });
  final List<double?> lows, highs;

  /// Said under the chart: what the band is.
  final String meaning;
}

/// Line chart with direct end labels, round-number ticks, quiet horizontal grid,
/// hover/keyboard readout of exact values, and a stated axis range.
/// Gaps are shown as gaps. Point shape can encode a second fact (filled vs hollow).
class LineChart extends StatefulWidget {
  const LineChart({
    super.key,
    required this.series,
    required this.xLabels,
    required this.summary,
    required this.valueFormat,
    this.hollow,
    this.pointNotes,
    this.height = 220,
    this.hollowMeaning,
    this.shielded,
    this.shieldMeaning,
    this.rangeMeaning,
    this.axisFormat,
    this.detailFormat,
    this.countFormat,
    this.tickStep,
    this.yMin,
    this.yMax,
    this.band,
    this.sync,
  });
  final List<ChartSeries> series;

  /// Shaded behind the lines (see [ChartBand]); part of the axis range.
  final ChartBand? band;

  /// Shared by charts over the same x positions (the same matches): pointing at a
  /// column in one shows that column in all of them.
  final ValueNotifier<int?>? sync;
  final List<String> xLabels;

  /// Spoken description of the finding; also the semantics label.
  final String summary;
  final String Function(double) valueFormat;

  /// Per x index: draw points hollow (e.g. a lost match).
  final List<bool>? hollow;

  /// Extra line in the readout per x index (e.g. result and map).
  final List<String>? pointNotes;
  final double height;
  final String? hollowMeaning;

  /// Per x index: a column the first series has no real value for in the usual sense (a
  /// match without a death). Its point is drawn as a shield and the column behind it is
  /// filled, so the stretch reads as "nothing happened here" rather than a data point.
  final List<bool>? shielded;
  final String? shieldMeaning;

  /// What the vertical bars show, when a series has [ChartSeries.lows].
  final String? rangeMeaning;

  /// Axis ticks and end labels (e.g. a rank name); defaults to [valueFormat].
  final String Function(double)? axisFormat;

  /// Exact numbers shown in the readout beside the value (e.g. the rating behind a rank).
  final String Function(double)? detailFormat;

  /// How the player count is worded in the readout (e.g. `已评定 3 人`).
  final String Function(int)? countFormat;

  /// Force tick spacing (e.g. 100 = one rank division); otherwise round numbers.
  final double? tickStep;

  /// Force the same scale across charts the user will compare.
  final double? yMin, yMax;

  @override
  State<LineChart> createState() => _LineChartState();
}

class _LineChartState extends State<LineChart> {
  int? _ownIndex;

  /// The column the readout is about: this chart's own, or the one another chart
  /// sharing [LineChart.sync] points at.
  int? get _index => _ownIndex;
  set _index(int? i) {
    _ownIndex = i;
    final sync = widget.sync;
    if (sync != null && sync.value != i) sync.value = i;
  }

  void _followSync() {
    final i = widget.sync?.value;
    if (i != _ownIndex && mounted) {
      setState(() => _ownIndex = i == null ? null : math.min(i, _n - 1));
    }
  }

  @override
  void initState() {
    super.initState();
    widget.sync?.addListener(_followSync);
  }

  @override
  void didUpdateWidget(LineChart old) {
    super.didUpdateWidget(old);
    if (old.sync != widget.sync) {
      old.sync?.removeListener(_followSync);
      widget.sync?.addListener(_followSync);
    }
  }

  /// Which series the readout is about, when each series has its own detail.
  int _series = 0;
  final _focus = FocusNode();

  bool get _perSeries => widget.series.any((s) => s.counts != null);

  /// The series whose point (or spread bar) is nearest to [p] at column [i]; keeps the
  /// current one when no series has a value there.
  int _nearestSeries(_Geom g, _Axis axis, Offset p, int i) {
    double y(double v) =>
        _Geom.top + g.h * (1 - (v - axis.min) / (axis.max - axis.min));
    var best = _series, bestD = double.infinity;
    for (final (k, s) in widget.series.indexed) {
      final v = s.values[i];
      if (v == null) continue;
      // Points and bars of every series sit on one vertical line. Touching a point picks
      // that point; otherwise a touch inside a bar picks the narrowest bar there;
      // otherwise the nearest point.
      final dxp = (p.dx - g.x(i)).abs();
      var d = math.sqrt(dxp * dxp + math.pow(p.dy - y(v), 2));
      if (d <= 7) {
        d -= 1000;
      } else if (s.hasRange(i) &&
          dxp <= _barHalf(k, widget.series.length) &&
          p.dy >= y(s.highs![i]!) &&
          p.dy <= y(s.lows![i]!)) {
        d = -1 / _barHalf(k, widget.series.length);
      }
      if (d < bestD) {
        bestD = d;
        best = k;
      }
    }
    return best;
  }

  @override
  void dispose() {
    widget.sync?.removeListener(_followSync);
    _focus.dispose();
    super.dispose();
  }

  int get _n => widget.xLabels.length;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final values = [
      for (final s in widget.series) ...[
        ...s.values.whereType<double>(),
        ...?s.lows?.whereType<double>(),
        ...?s.highs?.whereType<double>(),
      ],
      ...?widget.band?.lows.whereType<double>(),
      ...?widget.band?.highs.whereType<double>(),
    ];
    if (values.isEmpty || _n == 0) {
      return SizedBox(
        height: widget.height,
        child: Center(
          child: Text(
            tr.shell.chartNoData,
            style: Ty.body.copyWith(color: c.textSecondary),
          ),
        ),
      );
    }
    final axis = widget.yMin != null && widget.yMax != null
        ? _Axis.fixed(widget.yMin!, widget.yMax!)
        : widget.tickStep != null
        ? _Axis.stepped(
            values.reduce(math.min),
            values.reduce(math.max),
            widget.tickStep!,
          )
        : _Axis.nice(values.reduce(math.min), values.reduce(math.max));
    final axisFmt = widget.axisFormat ?? widget.valueFormat;
    final truncated = axis.min > 0;
    return Semantics(
      container: true,
      label: widget.summary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Focus(
            focusNode: _focus,
            onKeyEvent: (_, e) {
              if (e is KeyUpEvent) return KeyEventResult.ignored;
              if (e.logicalKey == LogicalKeyboardKey.arrowRight) {
                setState(() => _index = math.min(_n - 1, (_index ?? -1) + 1));
              } else if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
                setState(() => _index = math.max(0, (_index ?? _n) - 1));
              } else if (_perSeries &&
                  (e.logicalKey == LogicalKeyboardKey.arrowUp ||
                      e.logicalKey == LogicalKeyboardKey.arrowDown)) {
                final step = e.logicalKey == LogicalKeyboardKey.arrowDown
                    ? 1
                    : -1;
                setState(
                  () => _series =
                      (_series + step + widget.series.length) %
                      widget.series.length,
                );
              } else if (e.logicalKey == LogicalKeyboardKey.escape) {
                setState(() => _index = null);
              } else {
                return KeyEventResult.ignored;
              }
              return KeyEventResult.handled;
            },
            onFocusChange: (_) => setState(() {}),
            child: LayoutBuilder(
              builder: (context, box) {
                final geom = _Geom(Size(box.maxWidth, widget.height), _n);
                return MouseRegion(
                  onHover: (e) => setState(() {
                    _index = geom.nearest(e.localPosition.dx);
                    if (_perSeries) {
                      _series = _nearestSeries(
                        geom,
                        axis,
                        e.localPosition,
                        _index!,
                      );
                    }
                  }),
                  onExit: (_) =>
                      setState(() => _index = _focus.hasFocus ? _index : null),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) {
                      _focus.requestFocus();
                      setState(() {
                        _index = geom.nearest(d.localPosition.dx);
                        if (_perSeries) {
                          _series = _nearestSeries(
                            geom,
                            axis,
                            d.localPosition,
                            _index!,
                          );
                        }
                      });
                    },
                    child: Container(
                      height: widget.height,
                      decoration: _focus.hasFocus && keyboardModality
                          ? BoxDecoration(border: c.itemOutline(focused: true))
                          : null,
                      // Drawn left to right when it first shows or shows other data;
                      // hovering and keyboard stepping do not replay it.
                      child: RevealLeftToRight(
                        dataKey: Object.hashAll([
                          for (final s in widget.series) ...[
                            s.label,
                            ...s.values,
                          ],
                        ]),
                        child: CustomPaint(
                          size: Size(box.maxWidth, widget.height),
                          painter: _LinePainter(
                            colors: c,
                            axis: axis,
                            series: widget.series,
                            xLabels: widget.xLabels,
                            hollow: widget.hollow,
                            shielded: widget.shielded,
                            valueFormat: widget.valueFormat,
                            axisFormat: axisFmt,
                            detailFormat: widget.detailFormat,
                            index: _index,
                            seriesIndex: _perSeries ? _series : null,
                            countFormat: widget.countFormat,
                            notes: widget.pointNotes,
                            band: widget.band,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 16,
            runSpacing: 2,
            children: [
              Text(
                truncated
                    ? tr.shell.axisTruncated(
                        axisFmt(axis.min),
                        axisFmt(axis.max),
                      )
                    : tr.shell.axisFromZero,
                style: Ty.meta.copyWith(color: c.textSecondary),
              ),
              if (widget.hollowMeaning != null)
                Text(
                  widget.hollowMeaning!,
                  style: Ty.meta.copyWith(color: c.textSecondary),
                ),
              if (widget.shieldMeaning != null)
                Text(
                  widget.shieldMeaning!,
                  style: Ty.meta.copyWith(color: c.textSecondary),
                ),
              if (widget.rangeMeaning != null)
                Text(
                  widget.rangeMeaning!,
                  style: Ty.meta.copyWith(color: c.textSecondary),
                ),
              if (widget.band != null)
                Text(
                  widget.band!.meaning,
                  style: Ty.meta.copyWith(color: c.textSecondary),
                ),
              Text(
                _perSeries ? tr.shell.chartHintPerTeam : tr.shell.chartHint,
                style: Ty.meta.copyWith(color: c.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Axis {
  const _Axis(this.min, this.max, this.step);
  final double min, max, step;
  factory _Axis.fixed(double lo, double hi) {
    final raw = (hi - lo) / 4;
    final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    final step = [
      1,
      2,
      2.5,
      5,
      10,
    ].map((m) => m * mag).firstWhere((s) => s >= raw, orElse: () => 10 * mag);
    return _Axis(lo, hi, step);
  }

  /// Ticks every [step], padded so the data sits inside.
  factory _Axis.stepped(double lo, double hi, double step) {
    var a = (lo / step).floor() * step;
    var b = (hi / step).ceil() * step;
    if (b - a < step * 2) {
      a -= step;
      b += step;
    }
    return _Axis(a, b, step);
  }
  List<double> get ticks => [
    for (var v = min; v <= max + step * 0.01; v += step) v,
  ];

  /// Round-number ticks, 4–6 of them.
  factory _Axis.nice(double lo, double hi) {
    if (hi - lo < 1e-9) {
      lo -= 50;
      hi += 50;
    }
    final raw = (hi - lo) / 4;
    final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    final step = [
      1,
      2,
      2.5,
      5,
      10,
    ].map((m) => m * mag).firstWhere((s) => s >= raw, orElse: () => 10 * mag);
    final min = (lo / step).floor() * step;
    final max = (hi / step).ceil() * step;
    // Keep a zero baseline when the data is already close to it.
    return _Axis(min > 0 && min < (max - min) * 0.25 ? 0 : min, max, step);
  }
}

/// Half the width of series [k]'s spread bar: the first of [n] is the widest.
double _barHalf(int k, int n) => 3.5 + (n - 1 - k) * 3.0;

class _Geom {
  _Geom(this.size, this.n);
  final Size size;
  final int n;
  static const left = 48.0, right = 96.0, top = 10.0, bottom = 24.0;
  double get w => math.max(1, size.width - left - right);
  double get h => size.height - top - bottom;
  double x(int i) => left + (n <= 1 ? w / 2 : w * i / (n - 1));
  int nearest(double dx) =>
      n <= 1 ? 0 : (((dx - left) / w) * (n - 1)).round().clamp(0, n - 1);
}

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.colors,
    required this.axis,
    required this.series,
    required this.xLabels,
    required this.hollow,
    required this.shielded,
    required this.valueFormat,
    required this.axisFormat,
    required this.detailFormat,
    required this.index,
    required this.seriesIndex,
    required this.countFormat,
    required this.notes,
    required this.band,
  });
  final ChartBand? band;
  final AppColors colors;
  final _Axis axis;
  final List<ChartSeries> series;
  final List<String> xLabels;
  final List<bool>? hollow;
  final List<bool>? shielded;
  final String Function(double) valueFormat;
  final String Function(double) axisFormat;
  final String Function(double)? detailFormat;
  final int? index;

  /// When set, the readout is about this one series; otherwise it lists them all.
  final int? seriesIndex;
  final String Function(int)? countFormat;
  final List<String>? notes;

  /// A shield centred on [c], [r] wide on each side: filled, or an outline when [hollow].
  void _shield(
    Canvas canvas,
    Offset c,
    double r,
    Color color,
    Color back,
    bool hollow,
  ) {
    final path = Path()
      ..moveTo(c.dx - r, c.dy - r * 0.9)
      ..lineTo(c.dx + r, c.dy - r * 0.9)
      ..lineTo(c.dx + r, c.dy + r * 0.1)
      ..quadraticBezierTo(c.dx + r, c.dy + r * 0.75, c.dx, c.dy + r * 1.15)
      ..quadraticBezierTo(c.dx - r, c.dy + r * 0.75, c.dx - r, c.dy + r * 0.1)
      ..close();
    canvas.drawPath(path, Paint()..color = back);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = hollow ? PaintingStyle.stroke : PaintingStyle.fill
        ..strokeWidth = 2,
    );
  }

  TextPainter _text(
    String s, {
    Color? color,
    FontWeight? weight,
    double size = 12,
  }) => TextPainter(
    text: TextSpan(
      text: s,
      style: TextStyle(
        fontSize: size,
        height: 1.3,
        color: color ?? colors.textSecondary,
        fontWeight: weight,
        fontFamily: Ty.family,
        fontFamilyFallback: Ty.fallback,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    final g = _Geom(size, xLabels.length);
    double y(double v) =>
        _Geom.top + g.h * (1 - (v - axis.min) / (axis.max - axis.min));

    // Quiet horizontal grid with value labels.
    final grid = Paint()
      ..color = colors.grid
      ..strokeWidth = 1;
    for (final t in axis.ticks) {
      canvas.drawLine(
        Offset(_Geom.left, y(t)),
        Offset(_Geom.left + g.w, y(t)),
        grid,
      );
      final tp = _text(axisFormat(t));
      tp.paint(canvas, Offset(_Geom.left - 8 - tp.width, y(t) - tp.height / 2));
    }
    // Columns without a death: the match's whole stretch of the x axis is filled.
    final sh = shielded;
    if (sh != null) {
      final half = xLabels.length <= 1
          ? g.w / 2
          : g.w / (xLabels.length - 1) / 2;
      for (var i = 0; i < xLabels.length && i < sh.length; i++) {
        if (!sh[i]) continue;
        final left = math.max(_Geom.left, g.x(i) - half);
        final right = math.min(_Geom.left + g.w, g.x(i) + half);
        canvas.drawRect(
          Rect.fromLTRB(left, _Geom.top, right, _Geom.top + g.h),
          Paint()..color = series.first.color.withValues(alpha: 0.14),
        );
      }
    }
    // The band: a quiet fill between its lows and highs, broken where either is unknown.
    final b = band;
    if (b != null) {
      final fill = Paint()
        ..color = colors.textSecondary.withValues(alpha: 0.14);
      final n = math.min(b.lows.length, b.highs.length);
      var i = 0;
      while (i < n) {
        if (b.lows[i] == null || b.highs[i] == null) {
          i++;
          continue;
        }
        final start = i;
        while (i < n && b.lows[i] != null && b.highs[i] != null) {
          i++;
        }
        final path = Path()..moveTo(g.x(start), y(b.highs[start]!));
        for (var k = start + 1; k < i; k++) {
          path.lineTo(g.x(k), y(b.highs[k]!));
        }
        for (var k = i - 1; k >= start; k--) {
          path.lineTo(g.x(k), y(b.lows[k]!));
        }
        path.close();
        canvas.drawPath(path, fill);
      }
    }
    // X labels: at most ~8, always including the last.
    final every = math.max(1, (xLabels.length / 8).ceil());
    for (var i = 0; i < xLabels.length; i++) {
      if (i % every != 0 && i != xLabels.length - 1) continue;
      final tp = _text(xLabels[i]);
      final x = (g.x(i) - tp.width / 2).clamp(0.0, size.width - tp.width);
      tp.paint(canvas, Offset(x, size.height - _Geom.bottom + 6));
    }

    // Spread: lowest to highest, a sharp bar like a candlestick's range. The series'
    // bars are nested on the column's line (the first is the widest, behind the rest),
    // so a match's points and bars of every series stand on one vertical line.
    for (final (k, s) in series.indexed) {
      for (var i = 0; i < s.values.length; i++) {
        if (!s.hasRange(i)) continue;
        final half = _barHalf(k, series.length);
        final top = y(s.highs![i]!), bottom = y(s.lows![i]!);
        final bar = Rect.fromLTRB(
          g.x(i) - half,
          top,
          g.x(i) + half,
          math.max(bottom, top + 2),
        );
        canvas.drawRect(bar, Paint()..color = s.color.withValues(alpha: 0.30));
        canvas.drawRect(
          bar,
          Paint()
            ..color = s.color.withValues(alpha: 0.9)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }
    }

    final labelYs = <double>[];
    for (final s in series) {
      const dx = 0.0;
      // Gaps between two known points: a hatched ribbon, so the missing match
      // reads as "no data here" instead of the line just ending.
      int? prev;
      for (var i = 0; i < s.values.length; i++) {
        final v = s.values[i];
        if (v == null) continue;
        if (prev != null && i - prev > 1) {
          _hatch(
            canvas,
            Offset(g.x(prev) + dx, y(s.values[prev]!)),
            Offset(g.x(i) + dx, y(v)),
            s.color,
          );
        }
        prev = i;
      }
      final line = Paint()
        ..color = s.color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      Path? run;
      void flush() {
        if (run == null) return;
        if (s.dashed) {
          for (final m in run!.computeMetrics()) {
            for (var d = 0.0; d < m.length; d += 9) {
              canvas.drawPath(
                m.extractPath(d, math.min(m.length, d + 5)),
                line,
              );
            }
          }
        } else {
          canvas.drawPath(run!, line);
        }
        run = null;
      }

      double? lastY;
      for (var i = 0; i < s.values.length; i++) {
        final v = s.values[i];
        if (v == null) {
          flush();
          lastY = null;
          continue;
        }
        final p = Offset(g.x(i) + dx, y(v));
        if (run == null) {
          run = Path()..moveTo(p.dx, p.dy);
        } else {
          // A stepped line keeps the last value level until this column.
          if (s.stepped && lastY != null) run!.lineTo(p.dx, lastY);
          run!.lineTo(p.dx, p.dy);
        }
        lastY = p.dy;
      }
      flush();
      for (var i = 0; i < s.values.length; i++) {
        final v = s.values[i];
        if (v == null) continue;
        final p = Offset(g.x(i) + dx, y(v));
        final isHollow = hollow != null && i < hollow!.length && hollow![i];
        if (identical(s, series.first) &&
            sh != null &&
            i < sh.length &&
            sh[i]) {
          _shield(canvas, p, 7, s.color, colors.raised, isHollow);
          continue;
        }
        canvas.drawCircle(p, 4, Paint()..color = colors.raised);
        canvas.drawCircle(
          p,
          4,
          Paint()
            ..color = s.color
            ..style = isHollow ? PaintingStyle.stroke : PaintingStyle.fill
            ..strokeWidth = 2,
        );
      }
      // Direct label at the last known point, nudged to avoid overlapping another label.
      final last = s.values.lastIndexWhere((v) => v != null);
      if (last >= 0) {
        var ly = y(s.values[last]!);
        for (final other in labelYs) {
          if ((ly - other).abs() < 16) ly = other + (ly >= other ? 16 : -16);
        }
        labelYs.add(ly);
        final tp = _text(
          '${s.label} ${axisFormat(s.values[last]!)}',
          color: s.color,
          weight: FontWeight.w600,
        );
        tp.paint(canvas, Offset(g.x(last) + dx + 10, ly - tp.height / 2));
      }
    }

    // Crosshair and exact-value readout.
    final i = index;
    if (i != null && i < xLabels.length) {
      final x = g.x(i);
      canvas.drawLine(
        Offset(x, _Geom.top),
        Offset(x, _Geom.top + g.h),
        Paint()
          ..color = colors.textSecondary
          ..strokeWidth = 1,
      );
      final only = seriesIndex?.clamp(0, series.length - 1);
      final detail = detailFormat ?? valueFormat;
      if (only != null && series[only].values[i] != null) {
        canvas.drawCircle(
          Offset(x, y(series[only].values[i]!)),
          8,
          Paint()
            ..color = series[only].color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
      final lines = <(String, Color?, FontWeight?)>[
        (xLabels[i], null, FontWeight.w600),
        if (notes != null && i < notes!.length && notes![i].isNotEmpty)
          (notes![i], null, null),
        // One team: its rank, how many players it rests on, the rank and score spread.
        if (only != null) ...[
          () {
            final s = series[only];
            final v = s.values[i];
            return (
              tr.shell.chartValue(
                s.label,
                v == null ? tr.shell.chartValueMissing : valueFormat(v),
              ),
              s.color,
              FontWeight.w600,
            );
          }(),
          if (series[only].counts != null &&
              i < series[only].counts!.length &&
              series[only].counts![i] != null)
            (
              (countFormat ?? tr.shell.playerCount)(series[only].counts![i]!),
              null,
              null,
            ),
          if (series[only].countNotes != null &&
              i < series[only].countNotes!.length &&
              series[only].countNotes![i] != null)
            (series[only].countNotes![i]!, null, null),
          if (series[only].values[i] != null && series[only].hasRange(i)) ...[
            (
              tr.shell.chartRankRange(
                valueFormat(series[only].lows![i]!),
                valueFormat(series[only].highs![i]!),
              ),
              null,
              null,
            ),
            (
              tr.shell.chartSkillRatingRange(
                detail(series[only].lows![i]!),
                detail(series[only].highs![i]!),
              ),
              null,
              null,
            ),
          ],
          if (series[only].values[i] != null)
            (tr.shell.chartMean(detail(series[only].values[i]!)), null, null),
        ] else
          for (final s in series) ...[
            (
              tr.shell.chartValue(
                s.label,
                s.values[i] == null
                    ? tr.shell.chartValueMissing
                    : valueFormat(s.values[i]!),
              ),
              s.color,
              FontWeight.w600,
            ),
            if (s.values[i] != null)
              (
                s.hasRange(i)
                    ? (detailFormat != null
                          ? tr.shell.chartMeanAndRange(
                              detailFormat!(s.values[i]!),
                              detailFormat!(s.lows![i]!),
                              detailFormat!(s.highs![i]!),
                            )
                          : tr.shell.chartRange(
                              valueFormat(s.lows![i]!),
                              valueFormat(s.highs![i]!),
                            ))
                    : (detailFormat == null
                          ? ''
                          : '    ${detailFormat!(s.values[i]!)}'),
                null,
                null,
              ),
          ],
      ];
      final painters = [
        for (final l in lines)
          if (l.$1.isNotEmpty)
            _text(l.$1, color: l.$2 ?? colors.textPrimary, weight: l.$3),
      ];
      final bw = painters.map((p) => p.width).reduce(math.max) + 16;
      final bh = painters.fold<double>(0, (s, p) => s + p.height) + 12;
      var bx = x + 12;
      if (bx + bw > size.width) bx = x - 12 - bw;
      final by = _Geom.top + 4;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(bx, by, bw, bh),
        const Radius.circular(6),
      );
      canvas.drawRRect(rect, Paint()..color = colors.header);
      canvas.drawRRect(
        rect,
        Paint()
          ..color = colors.border
          ..style = PaintingStyle.stroke,
      );
      var ty = by + 6;
      for (final p in painters) {
        p.paint(canvas, Offset(bx + 8, ty));
        ty += p.height;
      }
    }
  }

  /// Diagonal-hatched band along the straight line from [a] to [b].
  void _hatch(Canvas canvas, Offset a, Offset b, Color color) {
    const half = 7.0;
    final path = Path()
      ..moveTo(a.dx, a.dy - half)
      ..lineTo(b.dx, b.dy - half)
      ..lineTo(b.dx, b.dy + half)
      ..lineTo(a.dx, a.dy + half)
      ..close();
    canvas.save();
    canvas.clipPath(path);
    final r = path.getBounds();
    final stroke = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    for (var x = r.left - r.height; x < r.right; x += 5) {
      canvas.drawLine(Offset(x, r.bottom), Offset(x + r.height, r.top), stroke);
    }
    canvas.restore();
    final edge = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    canvas.drawLine(a.translate(0, -half), b.translate(0, -half), edge);
    canvas.drawLine(a.translate(0, half), b.translate(0, half), edge);
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.index != index ||
      old.series != series ||
      old.xLabels != xLabels ||
      old.colors != colors ||
      old.hollow != hollow ||
      old.notes != notes;
}
