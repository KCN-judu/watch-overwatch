import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/models.dart';
import '../l10n/strings.dart';
import 'interaction.dart';
import 'tokens.dart';
import 'net_pic.dart';

export 'interaction.dart';

// ---- Buttons ---------------------------------------------------------------

ButtonStyle buttonStyle(
  BuildContext context, {
  bool primary = false,
  bool quiet = false,
}) {
  final c = context.c;
  return ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size(0, 32)),
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12)),
    textStyle: WidgetStatePropertyAll(Ty.bodyStrong),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.control),
      ),
    ),
    elevation: const WidgetStatePropertyAll(0),
    backgroundColor: WidgetStateProperty.resolveWith((s) {
      if (s.contains(WidgetState.disabled)) {
        return primary ? c.border : Colors.transparent;
      }
      if (primary) return c.accent;
      return quiet ? Colors.transparent : c.raised;
    }),
    foregroundColor: WidgetStateProperty.resolveWith((s) {
      if (s.contains(WidgetState.disabled)) return c.textSecondary;
      return primary ? c.onAccent : c.textPrimary;
    }),
    overlayColor: WidgetStateProperty.resolveWith(
      (s) => s.contains(WidgetState.pressed)
          ? c.selected
          : (s.contains(WidgetState.hovered) ? c.hover : null),
    ),
    side: WidgetStateProperty.resolveWith((s) {
      // Focus ring: 2px, drawn over every other state.
      if (s.contains(WidgetState.focused)) {
        return BorderSide(color: primary ? c.textPrimary : c.accent, width: 2);
      }
      if (primary || quiet) return BorderSide.none;
      return BorderSide(color: c.border);
    }),
  );
}

class AppButton extends StatelessWidget {
  const AppButton(
    this.label, {
    super.key,
    this.onPressed,
    this.icon,
    this.primary = false,
    this.quiet = false,
    this.tooltip,
    this.disabledReason,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool primary, quiet;
  final String? tooltip;

  /// Shown as the tooltip while disabled, so the user can see why.
  final String? disabledReason;

  @override
  Widget build(BuildContext context) {
    final style = buttonStyle(context, primary: primary, quiet: quiet);
    final child = icon == null
        ? Text(label)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16),
              const SizedBox(width: 6),
              Text(label),
            ],
          );
    final button = TextButton(onPressed: onPressed, style: style, child: child);
    final tip = onPressed == null ? (disabledReason ?? tooltip) : tooltip;
    return tip == null ? button : Tooltip(message: tip, child: button);
  }
}

class IconAction extends StatelessWidget {
  const IconAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.shortcut,
  });
  final IconData icon;

  /// Names the action for tooltip and screen reader.
  final String label;
  final VoidCallback? onPressed;
  final String? shortcut;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Tooltip(
      message: shortcut == null ? label : '$label  $shortcut',
      child: IconButton(
        onPressed: onPressed,
        tooltip: null,
        icon: Icon(icon, size: 18),
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(32, 32)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.control),
            ),
          ),
          foregroundColor: WidgetStatePropertyAll(c.textPrimary),
          overlayColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.hovered) ? c.hover : null,
          ),
          side: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.focused)
                ? BorderSide(color: c.accent, width: 2)
                : BorderSide.none,
          ),
        ),
        // Semantics name comes from the label, not the glyph.
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      ),
    );
  }
}

// ---- Segmented control (radio group: one tab stop, arrows move) ----------------

class Segment<V> {
  const Segment(this.value, this.label, {this.hint, this.leading});
  final V value;
  final String label;
  final String? hint;

  /// Glyph shown before the label (an icon that backs the word up, not replaces it).
  final Widget? leading;
}

class SegmentedBar<V> extends StatefulWidget {
  const SegmentedBar({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
    this.disabledReason,
  });
  final List<Segment<V>> segments;
  final V value;

  /// `null` disables the whole bar: it shows its value but cannot be changed.
  final ValueChanged<V>? onChanged;
  final String semanticLabel;

  /// Shown as the tooltip while disabled, so the user can see why.
  final String? disabledReason;

  @override
  State<SegmentedBar<V>> createState() => _SegmentedBarState<V>();
}

class _SegmentedBarState<V> extends State<SegmentedBar<V>> {
  final _focus = FocusNode();
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _key(KeyEvent e) {
    final onChanged = widget.onChanged;
    if (e is KeyUpEvent || onChanged == null) return KeyEventResult.ignored;
    final i = widget.segments.indexWhere((s) => s.value == widget.value);
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowRight ||
        k == LogicalKeyboardKey.arrowDown) {
      onChanged(
        widget.segments[math.min(widget.segments.length - 1, i + 1)].value,
      );
    } else if (k == LogicalKeyboardKey.arrowLeft ||
        k == LogicalKeyboardKey.arrowUp) {
      onChanged(widget.segments[math.max(0, i - 1)].value);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final onChanged = widget.onChanged;
    final bar = Semantics(
      container: true,
      label: widget.semanticLabel,
      enabled: onChanged != null,
      child: Focus(
        focusNode: _focus,
        canRequestFocus: onChanged != null,
        onKeyEvent: (_, e) => _key(e),
        child: ListenableBuilder(
          listenable: _focus,
          builder: (context, _) {
            final ring = _focus.hasFocus && keyboardModality;
            return Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: c.window,
                borderRadius: BorderRadius.circular(Radii.control + 2),
                border: Border.all(
                  color: ring ? c.accent : c.border,
                  width: ring ? 2 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final s in widget.segments)
                    _SegmentButton(
                      label: s.label,
                      hint: s.hint,
                      leading: s.leading,
                      selected: s.value == widget.value,
                      onTap: onChanged == null
                          ? null
                          : () {
                              _focus.requestFocus();
                              onChanged(s.value);
                            },
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
    final reason = widget.disabledReason;
    return onChanged == null && reason != null
        ? Tooltip(message: reason, child: bar)
        : bar;
  }
}

class _SegmentButton extends StatefulWidget {
  const _SegmentButton({
    required this.label,
    required this.hint,
    required this.leading,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final String? hint;
  final Widget? leading;
  final bool selected;

  /// `null` while the bar is disabled.
  final VoidCallback? onTap;

  @override
  State<_SegmentButton> createState() => _SegmentButtonState();
}

class _SegmentButtonState extends State<_SegmentButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final selected = widget.selected;
    final enabled = widget.onTap != null;
    final body = Semantics(
      inMutuallyExclusiveGroup: true,
      selected: selected,
      checked: selected,
      button: true,
      enabled: enabled,
      label: widget.label,
      excludeSemantics: true,
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 28, minWidth: 40),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.itemFill(
                selected: selected,
                hovered: _hovered && enabled,
              ),
              borderRadius: BorderRadius.circular(Radii.control),
            ),
            child: Opacity(
              opacity: enabled ? 1 : 0.55,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Selected state is carried by weight and a check, not by colour alone.
                  if (selected) ...[
                    Icon(Icons.check, size: 13, color: c.accent),
                    const SizedBox(width: Sp.withinControl),
                  ],
                  if (widget.leading != null) ...[
                    widget.leading!,
                    const SizedBox(width: 5),
                  ],
                  Text(
                    widget.label,
                    style: Ty.body.copyWith(
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: selected ? c.textPrimary : c.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final hint = widget.hint;
    return hint == null || !enabled
        ? body
        : Tooltip(message: hint, child: body);
  }
}

// ---- Result, team and rank marks -------------------------------------------

class OutcomeMark extends StatelessWidget {
  const OutcomeMark(
    this.outcome, {
    super.key,
    this.textless = false,
    this.stacked = false,
  });
  final Outcome outcome;

  /// Icon only (filter buttons); the name stays in the accessibility tree.
  final bool textless;

  /// Icon above the word, for tall rows.
  final bool stacked;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final color = c.outcome(outcome.id);
    final icon = switch (outcome) {
      Outcome.win => Icons.check_rounded,
      Outcome.loss => Icons.close_rounded,
      Outcome.draw => Icons.remove_rounded,
      Outcome.unknown => Icons.help_outline_rounded,
    };
    if (textless) {
      return Semantics(
        label: outcome.label,
        excludeSemantics: true,
        child: Icon(icon, size: 17, color: color),
      );
    }
    if (stacked) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 22, color: color),
          Text(outcome.label, style: Ty.bodyStrong.copyWith(color: color)),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 3),
        Text(
          outcome.label,
          style: Ty.cell.copyWith(color: color, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class TeamTag extends StatelessWidget {
  const TeamTag({super.key, required this.ally});
  final bool ally;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final color = ally ? c.ally : c.enemy;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.control),
        border: Border.all(color: color),
      ),
      child: Text(
        ally ? tr.common.ally : tr.common.enemy,
        style: Ty.meta.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class NetImage extends StatelessWidget {
  const NetImage(
    this.url, {
    super.key,
    required this.size,
    this.fallback = '?',
    this.radius = 4,
  });
  final String? url;
  final double size;
  final String fallback;
  final double radius;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final box = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.header,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Text(
        fallback.isEmpty ? '?' : fallback.characters.first,
        style: Ty.meta.copyWith(color: c.textSecondary),
      ),
    );
    if (url == null) return ExcludeSemantics(child: box);
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: NetPic(
          url!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          radius: radius,
          // Images are recognition aids; a missing one must never break the row.
          error: box,
        ),
      ),
    );
  }
}

/// Magnitude bar behind a number: tall, left-anchored, in the stat's own colour. The
/// number is always printed; the bar only shows how it compares with the others.
class DataBar extends StatelessWidget {
  const DataBar({
    super.key,
    required this.value,
    required this.max,
    required this.color,
    required this.child,
  });
  final double? value;
  final double max;
  final Color color;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final frac = value == null || max <= 0
        ? 0.0
        : (value! / max).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Stack(
        fit: StackFit.expand,
        alignment: Alignment.centerRight,
        children: [
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: frac,
                heightFactor: 0.74,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.barFill(color),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Status surfaces ---------------------------------------------------------

enum Severity { info, warning, error }

class StatusBanner extends StatelessWidget {
  const StatusBanner({
    super.key,
    required this.severity,
    required this.title,
    this.detail,
    this.actions = const [],
  });
  final Severity severity;
  final String title;
  final String? detail;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final color = switch (severity) {
      Severity.info => c.accent,
      Severity.warning => c.warning,
      Severity.error => c.error,
    };
    final icon = switch (severity) {
      Severity.info => Icons.info_outline,
      Severity.warning => Icons.warning_amber_rounded,
      Severity.error => Icons.error_outline,
    };
    return Semantics(
      container: true,
      liveRegion: severity != Severity.info,
      label: tr.shell.banner(
        switch (severity) {
          Severity.info => tr.shell.severityInfo,
          Severity.warning => tr.shell.severityWarning,
          Severity.error => tr.shell.severityError,
        },
        title,
        detail,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: c.raised,
          borderRadius: BorderRadius.circular(Radii.container),
          border: Border(
            left: BorderSide(color: color, width: 3),
            top: BorderSide(color: c.border),
            right: BorderSide(color: c.border),
            bottom: BorderSide(color: c.border),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Ty.bodyStrong.copyWith(color: c.textPrimary),
                  ),
                  if (detail != null)
                    Text(
                      detail!,
                      style: Ty.body.copyWith(color: c.textSecondary),
                    ),
                ],
              ),
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(width: 12),
              Wrap(spacing: 8, children: actions),
            ],
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.body,
    this.actions = const [],
    this.icon,
  });
  final String title;
  final String body;
  final List<Widget> actions;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(Sp.betweenSections),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 28, color: c.textSecondary),
                const SizedBox(height: Sp.withinGroup),
              ],
              Text(title, style: Ty.section, textAlign: TextAlign.center),
              const SizedBox(height: Sp.withinControl),
              Text(
                body,
                style: Ty.body.copyWith(color: c.textSecondary),
                textAlign: TextAlign.center,
              ),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: Sp.betweenGroups),
                Wrap(
                  spacing: Sp.withinGroup,
                  runSpacing: Sp.withinGroup,
                  alignment: WrapAlignment.center,
                  children: actions,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// What happened · why · what to do next · copyable details.
class ErrorPanel extends StatelessWidget {
  const ErrorPanel({
    super.key,
    required this.error,
    required this.what,
    this.onRetry,
    this.extra = const [],
    this.dataSafe,
  });
  final ApiError error;
  final String what;
  final VoidCallback? onRetry;
  final List<Widget> extra;

  /// Whether saved data is affected; defaults to [ShellStrings.nothingChanged].
  final String? dataSafe;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(Sp.betweenSections),
          child: Semantics(
            liveRegion: true,
            container: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.error_outline, color: c.error, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text(what, style: Ty.section)),
                  ],
                ),
                const SizedBox(height: Sp.withinGroup),
                // A fixed sentence by kind; the raw message is only in 复制详情.
                Text(tr.shell.errorSentence(error.kind), style: Ty.body),
                const SizedBox(height: Sp.withinControl),
                Text(
                  dataSafe ?? tr.shell.nothingChanged,
                  style: Ty.body.copyWith(color: c.textSecondary),
                ),
                const SizedBox(height: Sp.betweenGroups),
                Wrap(
                  spacing: Sp.withinGroup,
                  runSpacing: Sp.withinGroup,
                  children: [
                    if (onRetry != null)
                      AppButton(
                        tr.common.retry,
                        onPressed: onRetry,
                        primary: true,
                        icon: Icons.refresh,
                      ),
                    ...extra,
                    AppButton(
                      tr.common.copyDetails,
                      quiet: true,
                      icon: Icons.copy,
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: error.details),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(tr.common.detailsCopied),
                              duration: const Duration(seconds: 4),
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---- Loading ------------------------------------------------------------------
//
// One set of loading marks (docs/ui-design.md §5), by how long the wait is:
//  - under [Dur.loadingHint]: nothing (wrap the mark in [AfterDelay]);
//  - a page or list whose layout is known: a skeleton of that layout ([Skeleton]);
//  - a refresh while old data stays on screen, or one small part: [Spinner] or
//    [RefreshingChip];
//  - a long job with steps (over ~10 s): steps with a [ProgressLine] and time left.

/// Renders nothing until [Dur.loadingHint] has passed, so fast loads never flash a
/// loading mark.
class AfterDelay extends StatefulWidget {
  const AfterDelay({
    super.key,
    required this.child,
    this.delay = Dur.loadingHint,
  });
  final Widget child;
  final Duration delay;
  @override
  State<AfterDelay> createState() => _AfterDelayState();
}

class _AfterDelayState extends State<AfterDelay> {
  bool _show = false;
  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.delay, () {
      if (mounted) setState(() => _show = true);
    });
  }

  @override
  Widget build(BuildContext context) =>
      _show ? widget.child : const SizedBox.shrink();
}

/// The one spinner: 14px, 2px stroke, secondary text colour unless told otherwise.
class Spinner extends StatelessWidget {
  const Spinner({super.key, this.color});
  final Color? color;
  static const size = 14.0;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CircularProgressIndicator(
      strokeWidth: 2,
      color: color ?? context.c.textSecondary,
    ),
  );
}

/// The one progress bar: 3px, accent on the border colour. `value` null is indeterminate.
class ProgressLine extends StatelessWidget {
  const ProgressLine({super.key, required this.value, this.color});
  final double? value;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: LinearProgressIndicator(
        value: value,
        minHeight: 3,
        color: color ?? c.accent,
        backgroundColor: c.border,
      ),
    );
  }
}

/// Small non-blocking marker that a refresh is running while old data stays on screen.
class RefreshingChip extends StatelessWidget {
  const RefreshingChip({super.key, this.label});

  /// Defaults to [CommonStrings.refreshing].
  final String? label;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final label = this.label ?? tr.common.refreshing;
    return Semantics(
      liveRegion: true,
      label: label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Spinner(),
          const SizedBox(width: 6),
          Text(label, style: Ty.meta.copyWith(color: c.textSecondary)),
        ],
      ),
    );
  }
}

/// Applied filter, individually removable.
class FilterTag extends StatelessWidget {
  const FilterTag({super.key, required this.label, required this.onRemove});
  final String label;
  final VoidCallback onRemove;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // An applied filter is on, so it is drawn selected; hover and focus show over it.
    return Pressable(
      onTap: onRemove,
      selected: true,
      semanticLabel: tr.shell.removeFilterLabel(label),
      tooltip: tr.shell.removeFilter,
      height: 28,
      padding: const EdgeInsets.fromLTRB(8, 0, 4, 0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: Ty.meta.copyWith(color: c.textPrimary)),
          const SizedBox(width: 2),
          Icon(Icons.close, size: 14, color: c.textSecondary),
        ],
      ),
    );
  }
}

/// Keyboard hint pill.
class Kbd extends StatelessWidget {
  const Kbd(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: c.border),
      ),
      child: Text(text, style: Ty.meta.copyWith(color: c.textSecondary)),
    );
  }
}

/// Drag handle between two panes: 8px hit band around a 1px line, resize cursor
/// over the whole band, double-click restores the default.
class Splitter extends StatelessWidget {
  const Splitter({super.key, required this.onDrag, required this.onReset});
  final ValueChanged<double> onDrag;
  final VoidCallback onReset;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
        onDoubleTap: onReset,
        child: SizedBox(
          width: 8,
          child: Center(child: Container(width: 1, color: c.border)),
        ),
      ),
    );
  }
}

Widget gap(double h) => SizedBox(height: h);
Widget hgap(double w) => SizedBox(width: w);

/// One headline number: label above, big figure, optional note, optional stat colour.
/// The only tile of its kind: every page with a row of headline numbers uses it.
class KpiTile extends StatelessWidget {
  const KpiTile(this.label, this.value, {super.key, this.note, this.color});
  final String label, value;
  final String? note;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      container: true,
      label: '$label $value${note == null ? '' : '，$note'}',
      excludeSemantics: true,
      child: Container(
        width: 160,
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          color: color == null ? c.raised : c.barFill(color!),
          border: Border(left: BorderSide(color: color ?? c.border, width: 3)),
          borderRadius: const BorderRadius.horizontal(
            right: Radius.circular(2),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Ty.meta.copyWith(color: c.textSecondary)),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: Ty.num(Ty.figure), maxLines: 1),
            ),
            if (note != null)
              Text(note!, style: Ty.meta.copyWith(color: c.textSecondary)),
          ],
        ),
      ),
    );
  }
}
