import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/strings.dart';
import 'interaction.dart';
import 'motion.dart';
import 'net_pic.dart';
import 'tokens.dart';
import 'widgets.dart' show AfterDelay;

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

/// A recognition row drawn over a picture (a map, a hero banner): the picture is
/// dense behind the text on the left and fades out to the right, under a scrim that
/// keeps the text readable. Selection, hover and focus are painted as everywhere
/// else ([ItemState]). Shared by the match and hero lists so the two stay identical.
class ArtRow extends StatelessWidget {
  const ArtRow({
    super.key,
    required this.state,
    required this.art,
    required this.content,
    this.artAlignment = Alignment.center,
    this.layers,
  });
  final CardState state;
  final String? art;
  final Alignment artAlignment;

  /// Drawn over the picture and under the selection tint, given the row height.
  final List<Widget> Function(double side)? layers;

  /// The row's content, given the row height (a square portrait is that wide).
  final Widget Function(double side) content;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final light = Theme.of(context).brightness == Brightness.light;
    final fill = c.itemFill(selected: state.active, hovered: state.hovered);
    final outline = c.itemOutline(selected: state.active, focused: state.ring);
    return LayoutBuilder(
      builder: (context, box) {
        final side = box.maxHeight;
        // Sharp rectangle: no rounding.
        return Container(
          foregroundDecoration: outline == null
              ? null
              : BoxDecoration(border: outline),
          child: ClipRect(
            child: Stack(
              children: [
                Positioned.fill(
                  child: ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (rect) => const LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: AppColors.artFade,
                      stops: [0, 0.55, 1],
                    ).createShader(rect),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(color: c.raised),
                        if (art != null)
                          ExcludeSemantics(
                            child: NetPic(
                              art!,
                              fit: BoxFit.cover,
                              alignment: artAlignment,
                              placeholder: const SizedBox.expand(
                                child: Skeleton(radius: 0),
                              ),
                            ),
                          ),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                for (final a in AppColors.artScrim(light))
                                  c.raised.withValues(alpha: a),
                              ],
                              stops: const [0, 0.5, 1],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                ...?layers?.call(side),
                if (fill != null)
                  Positioned.fill(child: ColoredBox(color: fill)),
                Positioned.fill(child: content(side)),
              ],
            ),
          ),
        );
      },
    );
  }
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
    this.rowKey,
  });

  /// A row's identity. With it, rows that appear while the list is already on screen
  /// (new matches after a refresh) play in ([ArriveOnce]); rows already there stay put.
  final Object Function(T row)? rowKey;

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

  /// Keys of the rows shown so far, and of those that arrived since the last build.
  final Set<Object> _seen = {};
  final Set<Object> _arrived = {};

  @override
  void initState() {
    super.initState();
    _remember(arrive: false);
  }

  @override
  void didUpdateWidget(CardList<T> old) {
    super.didUpdateWidget(old);
    // The first rows of a list just appear; only later ones play in.
    _remember(arrive: _seen.isNotEmpty);
  }

  /// A row that has just arrived plays in, once: it is no longer "arrived" after this
  /// frame, so scrolling it away and back does not replay it.
  Widget _arrive(T row, Widget child) {
    final key = widget.rowKey?.call(row);
    if (key == null || !_arrived.remove(key)) return child;
    return ArriveOnce(child: child);
  }

  void _remember({required bool arrive}) {
    final key = widget.rowKey;
    if (key == null) return;
    for (final row in widget.rows) {
      final k = key(row);
      if (_seen.add(k) && arrive) _arrived.add(k);
    }
  }

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
        if (widget.loading && widget.rows.isEmpty) {
          return AfterDelay(child: _Skeleton(extent: extent));
        }
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
                  padding: const EdgeInsets.only(right: scrollGutter),
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
                              padding: const EdgeInsets.symmetric(
                                vertical: Sp.withinControl,
                              ),
                              child: _arrive(
                                row,
                                widget.builder(context, row, state),
                              ),
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
    return Semantics(
      label: tr.common.loading,
      liveRegion: true,
      child: ExcludeSemantics(
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (var i = 0; i < 6; i++)
              SizedBox(
                height: extent,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: Sp.withinControl),
                  child: Skeleton(radius: 0),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
