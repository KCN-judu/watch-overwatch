import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data_table.dart' show keyboardModality;
import 'tokens.dart';

class CardState {
  const CardState({
    required this.active,
    required this.hovered,
    required this.ring,
  });

  /// The row the user selected (persistent marker).
  final bool active;
  final bool hovered;

  /// Keyboard focus is on this row (shown for keyboard users only).
  final bool ring;
}

/// A virtualised list of tall "recognition" rows: each row is a picture-led card the
/// user identifies at a glance, not a line of comparable numbers. It follows the
/// same keyboard contract as [AppTable] (one tab stop; arrows, Home/End,
/// PageUp/PageDown, Enter) so lists feel the same everywhere.
class CardList<T> extends StatefulWidget {
  const CardList({
    super.key,
    required this.rows,
    required this.itemExtent,
    required this.builder,
    required this.rowLabel,
    required this.listLabel,
    this.onOpen,
    this.activeIndex,
    this.onActiveChanged,
    this.controller,
    this.empty,
    this.loading = false,
  });

  final List<T> rows;
  final double itemExtent;
  final Widget Function(BuildContext context, T row, CardState state) builder;
  final String Function(T row) rowLabel;
  final String listLabel;
  final void Function(T row, int index)? onOpen;

  /// -1 = nothing selected.
  final int? activeIndex;
  final ValueChanged<int>? onActiveChanged;
  final ScrollController? controller;
  final Widget? empty;
  final bool loading;

  @override
  State<CardList<T>> createState() => _CardListState<T>();
}

class _CardListState<T> extends State<CardList<T>> {
  late final ScrollController _own = ScrollController();
  ScrollController get _scroll => widget.controller ?? _own;
  final _focus = FocusNode(debugLabel: 'card list');
  int _active = -1;
  int? _hover;

  int get active =>
      math.min(widget.activeIndex ?? _active, widget.rows.length - 1);

  @override
  void dispose() {
    _own.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _setActive(int i, double viewport) {
    if (widget.rows.isEmpty) return;
    i = i.clamp(0, widget.rows.length - 1);
    setState(() => _active = i);
    widget.onActiveChanged?.call(i);
    if (_scroll.hasClients) {
      final h = widget.itemExtent;
      final top = i * h, bottom = top + h;
      if (top < _scroll.offset) {
        _scroll.jumpTo(top);
      } else if (bottom > _scroll.offset + viewport) {
        _scroll.jumpTo(bottom - viewport);
      }
    }
  }

  KeyEventResult _key(KeyEvent e, double viewport) {
    if (e is KeyUpEvent || widget.rows.isEmpty) return KeyEventResult.ignored;
    final page = math.max(1, (viewport / widget.itemExtent).floor() - 1);
    final k = e.logicalKey;
    final cur = active;
    if (k == LogicalKeyboardKey.arrowDown) {
      _setActive(cur + 1, viewport);
    } else if (k == LogicalKeyboardKey.arrowUp) {
      _setActive(cur <= 0 ? 0 : cur - 1, viewport);
    } else if (k == LogicalKeyboardKey.home) {
      _setActive(0, viewport);
    } else if (k == LogicalKeyboardKey.end) {
      _setActive(widget.rows.length - 1, viewport);
    } else if (k == LogicalKeyboardKey.pageDown) {
      _setActive(cur + page, viewport);
    } else if (k == LogicalKeyboardKey.pageUp) {
      _setActive(cur - page, viewport);
    } else if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.space) {
      if (cur >= 0) widget.onOpen?.call(widget.rows[cur], cur);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final scale = math.max(
      1.0,
      MediaQuery.textScalerOf(context).scale(13) / 13,
    );
    final extent = widget.itemExtent * scale;
    return LayoutBuilder(
      builder: (context, box) {
        if (widget.loading && widget.rows.isEmpty)
          return _Skeleton(extent: extent);
        if (widget.rows.isEmpty) return widget.empty ?? const SizedBox.shrink();
        final viewport = box.maxHeight;
        return Semantics(
          container: true,
          label: widget.listLabel,
          child: Focus(
            focusNode: _focus,
            onKeyEvent: (_, e) => _key(e, viewport),
            child: ListenableBuilder(
              listenable: _focus,
              builder: (context, _) {
                final focused = _focus.hasFocus && keyboardModality;
                return ListView.builder(
                  controller: _scroll,
                  itemExtent: extent,
                  itemCount: widget.rows.length,
                  padding: const EdgeInsets.only(right: 12),
                  itemBuilder: (context, i) {
                    final row = widget.rows[i];
                    final state = CardState(
                      active: i == active,
                      hovered: _hover == i,
                      ring: focused && i == active,
                    );
                    return Semantics(
                      container: true,
                      label: widget.rowLabel(row),
                      selected: state.active,
                      button: true,
                      onTap: () => widget.onOpen?.call(row, i),
                      child: ExcludeSemantics(
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          onEnter: (_) => setState(() => _hover = i),
                          onExit: (_) => setState(
                            () => _hover = _hover == i ? null : _hover,
                          ),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              _focus.requestFocus();
                              _setActive(i, viewport);
                              widget.onOpen?.call(row, i);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: widget.builder(context, row, state),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton({required this.extent});
  final double extent;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      label: '正在加载',
      liveRegion: true,
      child: ExcludeSemantics(
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (var i = 0; i < 6; i++)
              SizedBox(
                height: extent,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: c.hover.withValues(alpha: 0.10),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
