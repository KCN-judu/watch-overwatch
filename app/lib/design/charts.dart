import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data_table.dart' show keyboardModality;
import 'tokens.dart';

class ChartSeries {
  const ChartSeries({
    required this.label,
    required this.color,
    required this.values,
    this.dashed = false,
    this.lows,
    this.highs,
  });
  final String label;
  final Color color;
  final List<double?>
  values; // null = no data: the line breaks, never drops to zero
  final bool dashed;

  /// Optional spread behind each value (lowest and highest of what the value
  /// averages), drawn as a vertical bar through the point.
  final List<double?>? lows, highs;
  bool hasRange(int i) =>
      lows != null &&
      highs != null &&
      i < lows!.length &&
      i < highs!.length &&
      lows![i] != null &&
      highs![i] != null;
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
    this.rangeMeaning,
    this.axisFormat,
    this.detailFormat,
    this.tickStep,
    this.yMin,
    this.yMax,
  });
  final List<ChartSeries> series;
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

  /// What the vertical bars show, when a series has [ChartSeries.lows].
  final String? rangeMeaning;

  /// Axis ticks and end labels (e.g. a rank name); defaults to [valueFormat].
  final String Function(double)? axisFormat;

  /// Exact numbers shown in the readout beside the value (e.g. the rating behind a rank).
  final String Function(double)? detailFormat;

  /// Force tick spacing (e.g. 100 = one rank division); otherwise round numbers.
  final double? tickStep;

  /// Force the same scale across charts the user will compare.
  final double? yMin, yMax;

  @override
  State<LineChart> createState() => _LineChartState();
}

class _LineChartState extends State<LineChart> {
  int? _index;
  final _focus = FocusNode();

  @override
  void dispose() {
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
    ];
    if (values.isEmpty || _n == 0) {
      return SizedBox(
        height: widget.height,
        child: Center(
          child: Text(
            '没有可绘制的数据',
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
                  onHover: (e) =>
                      setState(() => _index = geom.nearest(e.localPosition.dx)),
                  onExit: (_) =>
                      setState(() => _index = _focus.hasFocus ? _index : null),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) {
                      _focus.requestFocus();
                      setState(() => _index = geom.nearest(d.localPosition.dx));
                    },
                    child: Container(
                      height: widget.height,
                      decoration: _focus.hasFocus && keyboardModality
                          ? BoxDecoration(
                              border: Border.all(color: c.accent, width: 2),
                              borderRadius: BorderRadius.circular(
                                Radii.control,
                              ),
                            )
                          : null,
                      child: CustomPaint(
                        size: Size(box.maxWidth, widget.height),
                        painter: _LinePainter(
                          colors: c,
                          axis: axis,
                          series: widget.series,
                          xLabels: widget.xLabels,
                          hollow: widget.hollow,
                          valueFormat: widget.valueFormat,
                          axisFormat: axisFmt,
                          detailFormat: widget.detailFormat,
                          index: _index,
                          notes: widget.pointNotes,
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
                    ? '纵轴范围 ${axisFmt(axis.min)}–${axisFmt(axis.max)}，不从 0 开始。'
                    : '纵轴从 0 开始。',
                style: Ty.meta.copyWith(color: c.textSecondary),
              ),
              if (widget.hollowMeaning != null)
                Text(
                  widget.hollowMeaning!,
                  style: Ty.meta.copyWith(color: c.textSecondary),
                ),
              if (widget.rangeMeaning != null)
                Text(
                  widget.rangeMeaning!,
                  style: Ty.meta.copyWith(color: c.textSecondary),
                ),
              Text(
                '点击图表或用 ←/→ 查看每个点的精确值。',
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
    required this.valueFormat,
    required this.axisFormat,
    required this.detailFormat,
    required this.index,
    required this.notes,
  });
  final AppColors colors;
  final _Axis axis;
  final List<ChartSeries> series;
  final List<String> xLabels;
  final List<bool>? hollow;
  final String Function(double) valueFormat;
  final String Function(double) axisFormat;
  final String Function(double)? detailFormat;
  final int? index;
  final List<String>? notes;

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
    // X labels: at most ~8, always including the last.
    final every = math.max(1, (xLabels.length / 8).ceil());
    for (var i = 0; i < xLabels.length; i++) {
      if (i % every != 0 && i != xLabels.length - 1) continue;
      final tp = _text(xLabels[i]);
      final x = (g.x(i) - tp.width / 2).clamp(0.0, size.width - tp.width);
      tp.paint(canvas, Offset(x, size.height - _Geom.bottom + 6));
    }

    // Series. With several, each is nudged sideways so the spread bars sit side by side.
    final labelYs = <double>[];
    for (final (k, s) in series.indexed) {
      final dx = (k - (series.length - 1) / 2) * 11.0;
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
      // Spread: lowest to highest, a sharp bar like a candlestick's range.
      for (var i = 0; i < s.values.length; i++) {
        if (!s.hasRange(i)) continue;
        final top = y(s.highs![i]!), bottom = y(s.lows![i]!);
        final bar = Rect.fromLTRB(
          g.x(i) + dx - 3.5,
          top,
          g.x(i) + dx + 3.5,
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

      for (var i = 0; i < s.values.length; i++) {
        final v = s.values[i];
        if (v == null) {
          flush();
          continue;
        }
        final p = Offset(g.x(i) + dx, y(v));
        if (run == null) {
          run = Path()..moveTo(p.dx, p.dy);
        } else {
          run!.lineTo(p.dx, p.dy);
        }
      }
      flush();
      for (var i = 0; i < s.values.length; i++) {
        final v = s.values[i];
        if (v == null) continue;
        final p = Offset(g.x(i) + dx, y(v));
        final isHollow = hollow != null && i < hollow!.length && hollow![i];
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
      final lines = <(String, Color?, FontWeight?)>[
        (xLabels[i], null, FontWeight.w600),
        if (notes != null && i < notes!.length && notes![i].isNotEmpty)
          (notes![i], null, null),
        for (final s in series) ...[
          (
            '${s.label}  ${s.values[i] == null ? '无数据' : valueFormat(s.values[i]!)}',
            s.color,
            FontWeight.w600,
          ),
          if (s.values[i] != null)
            (
              s.hasRange(i)
                  ? '    ${detailFormat != null ? '平均 ${detailFormat!(s.values[i]!)} · ' : ''}区间 ${(detailFormat ?? valueFormat)(s.lows![i]!)}–${(detailFormat ?? valueFormat)(s.highs![i]!)}'
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
