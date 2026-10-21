import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

/// Whether the last input was the keyboard, so focus rings appear for keyboard users
/// only (Flutter has no `:focus-visible`). Flutter's own highlight mode cannot tell:
/// on desktop it stays "traditional" for the mouse too, so a clicked tab would show
/// a ring. A key press turns rings on; a pointer press turns them off.
bool get keyboardModality {
  _InputModality.install();
  return _InputModality.keyboard;
}

abstract final class _InputModality {
  static bool keyboard = false;
  static bool _installed = false;

  static void install() {
    if (_installed) return;
    _installed = true;
    HardwareKeyboard.instance.addHandler((e) {
      if (e is KeyDownEvent) keyboard = true;
      return false;
    });
    GestureBinding.instance.pointerRouter.addGlobalRoute((e) {
      if (e is PointerDownEvent) keyboard = false;
    });
  }
}

/// The one way anything the user can pick shows its state (docs/ui-design.md §4):
///
///  - selected: the `selected` fill and a 1px accent outline;
///  - hovered: the `hover` fill, laid over the selection so it still shows;
///  - keyboard focus: a 2px accent outline, drawn over everything else;
///  - disabled: secondary text, no fill, no hover, the basic cursor.
///
/// A coloured bar on the leading edge is never a selection mark: it carries data
/// (a result, a win rate, a severity). Tabs are the one exception to the outline:
/// the selected tab is underlined, because it names the page below it.
extension ItemState on AppColors {
  Color? itemFill({bool selected = false, bool hovered = false}) {
    if (selected && hovered) return Color.alphaBlend(hover, this.selected);
    if (selected) return this.selected;
    if (hovered) return hover;
    return null;
  }

  Border? itemOutline({bool selected = false, bool focused = false}) {
    if (focused) return Border.all(color: accent, width: 2);
    if (selected) return Border.all(color: accent.withValues(alpha: 0.7));
    return null;
  }
}

/// A tappable surface painted with [ItemState]: pointer cursor, hover, focus ring,
/// Enter/Space activation and a button node for screen readers.
///
/// Inside a list or group that manages focus itself (one tab stop, arrow keys move),
/// pass `focusable: false` and the list's own cursor as [focused].
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.onTap,
    required this.child,
    required this.semanticLabel,
    this.selected = false,
    this.toggle = false,
    this.focusable = true,
    this.focused,
    this.radius = Radii.control,
    this.padding,
    this.height,
    this.outlineAtRest = false,
    this.tooltip,
  });

  /// `null` disables it.
  final VoidCallback? onTap;
  final Widget child;
  final String semanticLabel;
  final bool selected;

  /// Announced as a toggle (on / off) rather than as a selected item.
  final bool toggle;
  final bool focusable;

  /// Focus decided by an enclosing list; overrides this widget's own focus.
  final bool? focused;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final double? height;

  /// Draws the plain border while unselected (chips that sit on the page, not in a list).
  final bool outlineAtRest;
  final String? tooltip;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _hovered = false;
  bool _focused = false;

  bool get _enabled => widget.onTap != null;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final focused = widget.focused ?? (_focused && keyboardModality);
    final selected = widget.selected;
    final outline =
        c.itemOutline(selected: selected, focused: focused) ??
        (widget.outlineAtRest ? Border.all(color: c.border) : null);
    Widget body = Container(
      height: widget.height,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: _enabled
            ? c.itemFill(selected: selected, hovered: _hovered)
            : null,
        borderRadius: BorderRadius.circular(widget.radius),
        border: outline,
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: _enabled ? null : c.textSecondary),
        child: widget.child,
      ),
    );
    body = MouseRegion(
      cursor: _enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: body,
      ),
    );
    if (widget.focusable) {
      body = Focus(
        canRequestFocus: _enabled,
        onFocusChange: (f) => setState(() => _focused = f),
        onKeyEvent: (_, e) {
          if (e is! KeyDownEvent || !_enabled) return KeyEventResult.ignored;
          if (e.logicalKey == LogicalKeyboardKey.enter ||
              e.logicalKey == LogicalKeyboardKey.numpadEnter ||
              e.logicalKey == LogicalKeyboardKey.space) {
            widget.onTap!();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: body,
      );
    }
    body = Semantics(
      button: true,
      enabled: _enabled,
      selected: widget.toggle ? null : selected,
      toggled: widget.toggle ? selected : null,
      label: widget.semanticLabel,
      excludeSemantics: true,
      onTap: widget.onTap,
      child: body,
    );
    final tip = widget.tooltip;
    return tip == null || tip.isEmpty
        ? body
        : Tooltip(message: tip, child: body);
  }
}
