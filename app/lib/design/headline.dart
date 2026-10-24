import 'package:flutter/material.dart';

import '../core/gamedata.dart';
import '../core/models.dart';
import '../l10n/strings.dart';
import 'net_pic.dart';
import 'tokens.dart';
import 'widgets.dart';

/// The colour of a hero from the game files, kept clear of the page; null without one.
Color? heroTint(BuildContext context, EntityRef? hero) {
  final color = GameData.loaded?.hero(hero?.name)?.color;
  return color == null ? null : legibleOn(color, context.c.raised, ratio: 3);
}

/// A record as figures: the counts in the display face, the words small beside them,
/// so "8 胜 12 负" reads as two numbers.
class RecordText extends StatelessWidget {
  const RecordText(
    this.wins,
    this.losses, {
    super.key,
    this.draws = 0,
    this.style,
  });
  final int wins, losses, draws;

  /// The numbers' style; the words are a third of it.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final big = Ty.num(style ?? Ty.display);
    final word = Ty.bodyStrong.copyWith(color: c.textSecondary);
    final parts = [
      (wins, tr.core.outcomeWin),
      (losses, tr.core.outcomeLoss),
      if (draws > 0) (draws, tr.core.outcomeDraw),
    ];
    return Text.rich(
      TextSpan(
        children: [
          for (final (i, (v, s)) in parts.indexed) ...[
            if (i > 0) TextSpan(text: ' ', style: word),
            TextSpan(text: '$v', style: big),
            TextSpan(text: ' $s', style: word),
          ],
        ],
      ),
      semanticsLabel: tr.overview.record(wins, losses, draws),
    );
  }
}

/// One figure of a headline: small label, the figure, a coloured line under it.
class HeadlineFigure extends StatelessWidget {
  const HeadlineFigure({
    super.key,
    required this.label,
    this.value,
    this.child,
    this.note,
    this.noteColor,
    this.trailing,
    this.small = false,
  }) : assert(value != null || child != null);
  final String label;
  final String? value;

  /// In place of [value]: a [RecordText] or a badge.
  final Widget? child;
  final String? note;
  final Color? noteColor;
  final Widget? trailing;

  /// A phrase rather than a number: one step smaller.
  final bool small;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      container: true,
      label: [label, ?value, ?note].join('，'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Ty.meta.copyWith(color: c.textSecondary)),
          const SizedBox(height: Sp.hairline),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              child ??
                  (small
                      ? Text(value!, style: Ty.section)
                      : FigureText(value!, animate: true)),
              if (trailing != null) ...[
                const SizedBox(width: Sp.betweenGroups),
                Padding(
                  padding: const EdgeInsets.only(bottom: Sp.iconGap),
                  child: trailing!,
                ),
              ],
            ],
          ),
          if (note != null)
            Text(
              note!,
              style: Ty.meta.copyWith(color: noteColor ?? c.textSecondary),
            ),
        ],
      ),
    );
  }
}

/// A page's anchor (docs: the skill's visual-direction.md): a picture — a hero's banner,
/// a map — fading in from the right behind a dense scrim, over the hexagon texture and a
/// glow in the subject's colour; the page's title, and one row of display-size figures.
/// A thin bar down the left in the subject's own colour; the top-right corner is cut.
class HeadlineBand extends StatelessWidget {
  const HeadlineBand({
    super.key,
    this.art,
    this.artAlignment = const Alignment(0.6, -0.2),
    this.tint,
    this.eyebrow,
    this.title,
    this.actions = const [],
    required this.figures,
  });

  /// The picture's address; none leaves the scrim alone.
  final String? art;
  final Alignment artAlignment;

  /// The subject's colour (a hero's); the accent without one.
  final Color? tint;

  /// The small line above everything (what the figures are worked out from).
  final Widget? eyebrow;

  /// A title in the page size (a date, a map's name).
  final String? title;

  /// At the top right (回顾, share, previous / next).
  final List<Widget> actions;
  final List<Widget> figures;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final shape = CutBorder(
      cut: cornerCut * 2,
      side: BorderSide(color: c.border),
    );
    return ShapeClip(
      shape: shape,
      child: Stack(
        children: [
          // The texture is the bottom layer: the picture and the scrim lie over it.
          Positioned.fill(child: HexBackdrop(tint: tint)),
          if (art != null)
            Positioned.fill(
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (rect) => const LinearGradient(
                  begin: Alignment.centerRight,
                  end: Alignment.centerLeft,
                  colors: AppColors.artFade,
                  stops: [0, 0.6, 1],
                ).createShader(rect),
                child: Opacity(
                  opacity: 0.55,
                  child: NetPic(
                    art!,
                    fit: BoxFit.cover,
                    alignment: artAlignment,
                  ),
                ),
              ),
            ),
          Container(
            width: double.infinity,
            foregroundDecoration: ShapeDecoration(shape: shape),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  for (final a in AppColors.headlineScrim)
                    c.raised.withValues(alpha: a),
                ],
              ),
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: accentBar, color: tint ?? c.accent),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(Sp.betweenSections),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (eyebrow != null || actions.isNotEmpty)
                            Row(
                              children: [
                                Expanded(child: eyebrow ?? const SizedBox()),
                                ...actions,
                              ],
                            ),
                          if (title != null) ...[
                            const SizedBox(height: Sp.withinControl),
                            Text(title!, style: Ty.page),
                          ],
                          const SizedBox(height: Sp.betweenGroups),
                          Wrap(
                            spacing: Sp.page,
                            runSpacing: Sp.betweenGroups,
                            crossAxisAlignment: WrapCrossAlignment.start,
                            children: figures,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
