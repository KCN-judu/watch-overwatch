import 'package:flutter/material.dart';

import 'tokens.dart';

/// Motion that helps the eye follow a change, never decoration (docs/ui-design.md §7).
/// Every duration goes through [Dur.of], so the system's reduced-motion setting turns
/// all of it into an instant change; nothing here waits for an animation to finish.
abstract final class Motion {
  /// Things arriving: start fast, settle gently.
  static const enter = Curves.easeOutCubic;

  /// Things leaving: quick, out of the way.
  static const exit = Curves.easeInCubic;

  /// How far arriving content rises while it fades in.
  static const rise = 6.0;
}

/// Replaces its child with a fade-through when [childKey] changes: the old content
/// fades out quickly, the new one fades in rising a few pixels. For tabs, pages and the
/// list ↔ detail switch, where the two contents are unrelated (no shared positions to
/// carry over, so nothing slides across).
class FadeThrough extends StatelessWidget {
  const FadeThrough({super.key, required this.childKey, required this.child});

  /// What the content is; a new value means new content.
  final Object childKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: Dur.of(context, Dur.normal),
      reverseDuration: Dur.of(context, Dur.fast),
      switchInCurve: Motion.enter,
      switchOutCurve: Motion.exit,
      // The new page takes the space at once; the old one only fades on top of nothing.
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.passthrough,
        children: [
          for (final p in previous) Positioned.fill(child: p),
          ?current,
        ],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: AnimatedBuilder(
          animation: animation,
          builder: (_, child) => Transform.translate(
            offset: Offset(0, Motion.rise * (1 - animation.value)),
            child: child,
          ),
          child: child,
        ),
      ),
      child: KeyedSubtree(key: ValueKey(childKey), child: child),
    );
  }
}

/// A short text (a figure) that, when it changes, fades the new value in place instead
/// of jumping, so a changed number is noticed. The first value just appears: nothing
/// counts up from zero.
class AnimatedValueText extends StatelessWidget {
  const AnimatedValueText(
    this.text, {
    super.key,
    this.style,
    this.maxLines = 1,
  });
  final String text;
  final TextStyle? style;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: Dur.of(context, Dur.short),
      reverseDuration: Dur.of(context, Dur.fast),
      switchInCurve: Motion.enter,
      switchOutCurve: Motion.exit,
      layoutBuilder: (current, previous) => Stack(
        alignment: AlignmentDirectional.centerStart,
        children: [...previous, ?current],
      ),
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: Text(text, key: ValueKey(text), style: style, maxLines: maxLines),
    );
  }
}

/// Plays its child in once, when it is first built: a fade and a small rise. For a row
/// that has just arrived in a list that was already on screen (a new match after a
/// refresh), so the eye finds what is new.
class ArriveOnce extends StatelessWidget {
  const ArriveOnce({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Dur.of(context, Dur.long),
      curve: Motion.enter,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, Motion.rise * 1.5 * (1 - t)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// Reveals a chart from left to right when [dataKey] changes (first shown, or showing
/// different data), so the line reads as drawn in time order. The chart is fully
/// interactive at once; only its painting is clipped while it reveals.
class RevealLeftToRight extends StatelessWidget {
  const RevealLeftToRight({
    super.key,
    required this.dataKey,
    required this.child,
  });
  final Object dataKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(dataKey),
      tween: Tween(begin: 0, end: 1),
      duration: Dur.of(context, Dur.long),
      curve: Motion.enter,
      builder: (context, t, child) =>
          t >= 1 ? child! : ClipRect(clipper: _LeftPart(t), child: child),
      child: child,
    );
  }
}

class _LeftPart extends CustomClipper<Rect> {
  const _LeftPart(this.fraction);
  final double fraction;
  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * fraction, size.height);
  @override
  bool shouldReclip(_LeftPart old) => old.fraction != fraction;
}
