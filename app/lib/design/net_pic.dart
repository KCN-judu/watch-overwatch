import 'dart:async';

import 'package:flutter/material.dart';

import '../core/image_store.dart';
import '../l10n/strings.dart';
import 'tokens.dart';
import 'widgets.dart' show ProgressLine;

/// One slow clock for every skeleton on screen, so a hundred placeholders animate
/// from a single timer, and the timer only runs while any is visible.
class _ShimmerClock extends ChangeNotifier {
  _ShimmerClock._();
  static final instance = _ShimmerClock._();
  Timer? _timer;
  double t = 0;

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    _timer ??= Timer.periodic(const Duration(milliseconds: 50), (_) {
      t = (DateTime.now().millisecondsSinceEpoch % 1600) / 1600;
      notifyListeners();
    });
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) {
      _timer?.cancel();
      _timer = null;
    }
  }
}

/// Placeholder block shown where a picture will be: same size, a soft moving highlight.
class Skeleton extends StatelessWidget {
  const Skeleton({super.key, this.width, this.height, this.radius = 4});
  final double? width, height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final base = c.header;
    final shine = Color.alphaBlend(c.textPrimary.withValues(alpha: 0.07), base);
    if (reduce) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: base,
          borderRadius: BorderRadius.circular(radius),
        ),
      );
    }
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _ShimmerClock.instance,
        builder: (_, _) {
          final t = _ShimmerClock.instance.t;
          return Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              gradient: LinearGradient(
                begin: Alignment(-1.6 + t * 3.2, -0.3),
                end: Alignment(-0.6 + t * 3.2, 0.3),
                colors: [base, shine, base],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A picture from the shared [ImageStore]: a skeleton of the same size while it loads,
/// then the picture; [error] if it cannot be had.
class NetPic extends StatelessWidget {
  const NetPic(
    this.url, {
    super.key,
    this.width,
    this.height,
    this.fit,
    this.alignment = Alignment.center,
    this.color,
    this.blend,
    this.error,
    this.placeholder,
    this.radius = 4,
  });
  final String url;
  final double? width, height;
  final BoxFit? fit;
  final AlignmentGeometry alignment;
  final Color? color;
  final BlendMode? blend;

  /// Shown when the picture fails; nothing by default.
  final Widget? error;

  /// Shown while loading; a skeleton when the size is known, otherwise nothing.
  final Widget? placeholder;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final wait =
        placeholder ??
        (width != null && height != null
            ? Skeleton(width: width, height: height, radius: radius)
            : const SizedBox.shrink());
    return Image(
      image: CachedImage(url),
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      color: color,
      colorBlendMode: blend,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      excludeFromSemantics: true,
      frameBuilder: (context, child, frame, sync) =>
          sync || frame != null ? child : wait,
      errorBuilder: (_, _, _) => error ?? const SizedBox.shrink(),
    );
  }
}

/// Status-bar progress of picture loading. Appears only when loading has taken a
/// moment, so cache hits do not flash it.
class ImageProgress extends StatefulWidget {
  const ImageProgress({super.key});
  @override
  State<ImageProgress> createState() => _ImageProgressState();
}

class _ImageProgressState extends State<ImageProgress> {
  bool _show = false;
  Timer? _delay;

  @override
  void initState() {
    super.initState();
    ImageStore.instance.stats.addListener(_changed);
  }

  void _changed() {
    final busy = ImageStore.instance.stats.value.busy;
    if (busy && !_show && _delay == null) {
      _delay = Timer(const Duration(milliseconds: 350), () {
        _delay = null;
        if (mounted && ImageStore.instance.stats.value.busy) {
          setState(() => _show = true);
        }
      });
    }
    if (!busy) {
      _delay?.cancel();
      _delay = null;
      if (_show && mounted) setState(() => _show = false);
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    ImageStore.instance.stats.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return const SizedBox.shrink();
    final c = context.c;
    return ValueListenableBuilder<ImageLoadStats>(
      valueListenable: ImageStore.instance.stats,
      builder: (context, s, _) {
        return Semantics(
          liveRegion: true,
          label: tr.shell.loadingImagesLabel(s.done, s.total),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 96, child: ProgressLine(value: s.fraction)),
              const SizedBox(width: Sp.withinGroup),
              Text(
                tr.shell.loadingImages(s.done, s.total),
                style: Ty.num(Ty.meta).copyWith(color: c.textSecondary),
              ),
            ],
          ),
        );
      },
    );
  }
}
