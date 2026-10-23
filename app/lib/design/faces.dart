import 'package:flutter/material.dart';

import '../core/models.dart';
import 'icons.dart';
import 'tokens.dart';
import 'widgets.dart';

/// One face of a [FaceStrip]: a match as the hero played, with its result.
typedef Face = ({
  String? portrait,
  Outcome outcome,
  String tip,
  VoidCallback? onTap,
});

/// A run of matches as heroes' faces on one line, each with a result bar under it
/// (colour and word, never colour alone). Faces shrink to keep the line whole.
class FaceStrip extends StatelessWidget {
  const FaceStrip({super.key, required this.faces, this.maxSize = 52});
  final List<Face> faces;
  final double maxSize;

  static const _gap = Sp.iconGap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return LayoutBuilder(
      builder: (context, box) {
        final n = faces.length;
        final fit = n == 0 ? maxSize : (box.maxWidth - _gap * (n - 1)) / n;
        final size = fit.clamp(28.0, maxSize);
        return Wrap(
          spacing: _gap,
          runSpacing: _gap,
          children: [
            for (final f in faces)
              Pressable(
                onTap: f.onTap,
                semanticLabel: f.tip,
                tooltip: f.tip,
                radius: 0,
                child: SizedBox(
                  width: size,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: size,
                        height: size,
                        child: PortraitCell(f.portrait),
                      ),
                      Container(
                        height: 14,
                        alignment: Alignment.center,
                        color: c.outcome(f.outcome.id),
                        child: Text(
                          f.outcome.label,
                          style: Ty.micro.copyWith(color: c.onAccent),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
