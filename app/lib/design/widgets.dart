import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/models.dart';
import 'data_table.dart';
import 'tokens.dart';
import 'net_pic.dart';

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
  });
  final List<Segment<V>> segments;
  final V value;
  final ValueChanged<V> onChanged;
  final String semanticLabel;

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
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final i = widget.segments.indexWhere((s) => s.value == widget.value);
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowRight ||
        k == LogicalKeyboardKey.arrowDown) {
      widget.onChanged(
        widget.segments[math.min(widget.segments.length - 1, i + 1)].value,
      );
    } else if (k == LogicalKeyboardKey.arrowLeft ||
        k == LogicalKeyboardKey.arrowUp) {
      widget.onChanged(widget.segments[math.max(0, i - 1)].value);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      container: true,
      label: widget.semanticLabel,
      child: Focus(
        focusNode: _focus,
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
                      onTap: () {
                        _focus.requestFocus();
                        widget.onChanged(s.value);
                      },
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
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
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final body = Semantics(
      inMutuallyExclusiveGroup: true,
      selected: selected,
      checked: selected,
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 28, minWidth: 40),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? c.selected : null,
              borderRadius: BorderRadius.circular(Radii.control),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Selected state is carried by weight and a check, not by colour alone.
                if (selected) ...[
                  Icon(Icons.check, size: 13, color: c.accent),
                  const SizedBox(width: 4),
                ],
                if (leading != null) ...[leading!, const SizedBox(width: 5)],
                Text(
                  label,
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
    );
    return hint == null ? body : Tooltip(message: hint!, child: body);
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
        ally ? '己方' : '对方',
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
      label:
          '${{Severity.info: '提示', Severity.warning: '警告', Severity.error: '错误'}[severity]}：$title${detail == null ? '' : '。$detail'}',
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
    this.dataSafe = '没有保存或修改任何数据。',
  });
  final ApiError error;
  final String what;
  final VoidCallback? onRetry;
  final List<Widget> extra;
  final String dataSafe;
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
                Text(error.message, style: Ty.body),
                const SizedBox(height: Sp.withinControl),
                Text(dataSafe, style: Ty.body.copyWith(color: c.textSecondary)),
                const SizedBox(height: Sp.betweenGroups),
                Wrap(
                  spacing: Sp.withinGroup,
                  runSpacing: Sp.withinGroup,
                  children: [
                    if (onRetry != null)
                      AppButton(
                        '重试',
                        onPressed: onRetry,
                        primary: true,
                        icon: Icons.refresh,
                      ),
                    ...extra,
                    AppButton(
                      '复制详情',
                      quiet: true,
                      icon: Icons.copy,
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: error.details),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('详情已复制'),
                              duration: Duration(seconds: 4),
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

/// Small non-blocking marker that a refresh is running while old data stays on screen.
class RefreshingChip extends StatelessWidget {
  const RefreshingChip({super.key, this.label = '正在刷新…'});
  final String label;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      liveRegion: true,
      label: label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: c.textSecondary,
            ),
          ),
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
    return Semantics(
      button: true,
      label: '移除筛选：$label',
      excludeSemantics: true,
      onTap: onRemove,
      child: Tooltip(
        message: '移除此筛选',
        child: InkWell(
          onTap: onRemove,
          borderRadius: BorderRadius.circular(Radii.control),
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 3, 4, 3),
            decoration: BoxDecoration(
              color: c.selected,
              borderRadius: BorderRadius.circular(Radii.control),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: Ty.meta.copyWith(color: c.textPrimary)),
                const SizedBox(width: 2),
                Icon(Icons.close, size: 14, color: c.textSecondary),
              ],
            ),
          ),
        ),
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
        width: 150,
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          color: color == null ? c.window : c.barFill(color!),
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
