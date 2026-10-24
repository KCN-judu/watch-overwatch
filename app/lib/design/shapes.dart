import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'tokens.dart';

/// Which edges of a [SlantBorder] lean.
enum SlantEdges { both, leading, trailing }

/// A parallelogram leaning right by [slant] (docs/ui-design.md §7): the one shape of
/// everything that is picked or names a result — the selected tab, segments, buttons,
/// result plates, the section mark. [edges] keeps one side straight where the shape
/// meets the edge of its container.
class SlantBorder extends OutlinedBorder {
  const SlantBorder({super.side, this.edges = SlantEdges.both});
  final SlantEdges edges;

  Path _path(Rect r) {
    final dx = r.height * slant;
    final lead = edges != SlantEdges.trailing ? dx : 0.0;
    final trail = edges != SlantEdges.leading ? dx : 0.0;
    return Path()
      ..moveTo(r.left + lead, r.top)
      ..lineTo(r.right, r.top)
      ..lineTo(r.right - trail, r.bottom)
      ..lineTo(r.left, r.bottom)
      ..close();
  }

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _path(rect.deflate(side.width));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => _path(rect);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width == 0) return;
    canvas.drawPath(
      _path(rect.deflate(side.width / 2)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = side.width
        ..color = side.color,
    );
  }

  @override
  ShapeBorder scale(double t) => SlantBorder(side: side.scale(t), edges: edges);

  @override
  SlantBorder copyWith({BorderSide? side, SlantEdges? edges}) =>
      SlantBorder(side: side ?? this.side, edges: edges ?? this.edges);
}

/// A rectangle with its top-right corner cut off by [cut]: panels, cards, banners.
class CutBorder extends OutlinedBorder {
  const CutBorder({super.side, this.cut = cornerCut});
  final double cut;

  Path _path(Rect r) {
    final k = math.min(cut, math.min(r.width, r.height) / 2);
    return Path()
      ..moveTo(r.left, r.top)
      ..lineTo(r.right - k, r.top)
      ..lineTo(r.right, r.top + k)
      ..lineTo(r.right, r.bottom)
      ..lineTo(r.left, r.bottom)
      ..close();
  }

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _path(rect.deflate(side.width));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => _path(rect);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width == 0) return;
    canvas.drawPath(
      _path(rect.deflate(side.width / 2)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = side.width
        ..color = side.color,
    );
  }

  @override
  ShapeBorder scale(double t) => CutBorder(side: side.scale(t), cut: cut * t);

  @override
  CutBorder copyWith({BorderSide? side, double? cut}) =>
      CutBorder(side: side ?? this.side, cut: cut ?? this.cut);
}

/// Clips its child to a [SlantBorder] or [CutBorder] (or any shape).
class ShapeClip extends StatelessWidget {
  const ShapeClip({super.key, required this.shape, required this.child});
  final ShapeBorder shape;
  final Widget child;
  @override
  Widget build(BuildContext context) => ClipPath(
    clipper: ShapeBorderClipper(shape: shape),
    child: child,
  );
}

/// The section mark: a short leaning bar before a heading, in the accent or the
/// subject's own colour. Not a data bar: those stay upright ([accentBar]).
class SectionMark extends StatelessWidget {
  const SectionMark({super.key, required this.color, this.height = 18});
  final Color color;
  final double height;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: height * slant + 4,
    height: height,
    child: DecoratedBox(
      decoration: ShapeDecoration(color: color, shape: const SlantBorder()),
    ),
  );
}

/// The app's own texture: a faint hexagon lattice that thins out toward the left,
/// under a glow of [tint] from the top right. Only behind page heads (the player
/// header, [HeadlineBand]); the body of a page stays a flat surface.
class HexBackdrop extends StatelessWidget {
  const HexBackdrop({super.key, this.tint, this.child});
  final Color? tint;
  final Widget? child;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final light = Theme.of(context).brightness == Brightness.light;
    return CustomPaint(
      painter: _HexPainter(
        line: c.textPrimary.withValues(alpha: light ? 0.06 : 0.05),
        glow: (tint ?? c.accent).withValues(alpha: light ? 0.10 : 0.16),
      ),
      child: child,
    );
  }
}

class _HexPainter extends CustomPainter {
  const _HexPainter({required this.line, required this.glow});
  final Color line, glow;

  /// Hexagon circumradius.
  static const _r = 16.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0.9, -1.2),
          radius: 1.1,
          colors: [glow, glow.withValues(alpha: 0)],
        ).createShader(rect),
    );
    // Pointy-top lattice; drawn once per row of hexagons as a single path.
    final w = math.sqrt(3) * _r;
    final path = Path();
    var row = 0;
    for (var y = 0.0; y < size.height + _r * 2; y += _r * 1.5, row++) {
      final shift = row.isOdd ? w / 2 : 0.0;
      for (var x = -w + shift; x < size.width + w; x += w) {
        for (var k = 0; k < 6; k++) {
          final a = math.pi / 180 * (60 * k - 30);
          final p = Offset(x + _r * math.cos(a), y + _r * math.sin(a));
          k == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
        }
        path.close();
      }
    }
    canvas.saveLayer(rect, Paint());
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = line,
    );
    // Fade the lattice out toward the left, where the text sits.
    canvas.drawRect(
      rect,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = const LinearGradient(
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
          colors: AppColors.fade,
          stops: [0.1, 0.85],
        ).createShader(rect),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HexPainter old) => old.line != line || old.glow != glow;
}
