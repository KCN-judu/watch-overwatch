import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/strings.dart';
import 'interaction.dart';
import 'net_pic.dart';
import 'tokens.dart';
import 'widgets.dart' show AfterDelay;

/// One column. Identity column goes first; numeric columns are right-aligned
/// with fixed widths so digits keep their place across sorts and refreshes.
class Col<T> {
  const Col({
    required this.id,
    required this.label,
    required this.cell,
    this.width = 80,
    this.flex = false,
    this.numeric = false,
    this.sortKey,
    this.tooltip,
    this.headerChild,
    this.bleed = false,
  });
  final String id;
  final String label;
  final double width;

  /// Absorbs leftover width (never narrower than [width]).
  final bool flex;
  final bool numeric;
  final Comparable<Object>? Function(T row)? sortKey;
  final String? tooltip;

  /// Replaces the text label in the header (an icon). [label] still names the column
  /// for screen readers and the tooltip.
  final Widget? headerChild;

  /// The cell fills its whole box with no padding or alignment (row artwork).
  final bool bleed;
  final Widget Function(BuildContext context, T row) cell;
  bool get sortable => sortKey != null;
}

class AppTable<T> extends StatefulWidget {
  const AppTable({
    super.key,
    required this.columns,
    required this.rows,
    required this.rowLabel,
    required this.tableLabel,
    this.onOpen,
    this.sortId,
    this.sortAscending = false,
    this.onSort,
    this.summary,
    this.footer,
    this.empty,
    this.loading = false,
    this.controller,
    this.activeIndex,
    this.onActiveChanged,
    this.rowMarker,
    this.rowHeight,
  });

  /// Overrides the density row height (rows with two lines of content).
  final double? rowHeight;
  final List<Col<T>> columns;
  final List<T> rows;

  /// Spoken and tooltip description of a whole row.
  final String Function(T row) rowLabel;
  final String tableLabel;
  final void Function(T row, int index)? onOpen;
  final String? sortId;
  final bool sortAscending;
  final void Function(String id)? onSort;

  /// Pinned between header and body (aggregates).
  final Widget? summary;
  final Widget? footer;

  /// Replaces the body when [rows] is empty; the header stays.
  final Widget? empty;

  /// Skeleton rows in the real column layout.
  final bool loading;
  final ScrollController? controller;
  final int? activeIndex;
  final ValueChanged<int>? onActiveChanged;

  /// Optional thin marker drawn at the row's leading edge (e.g. result colour + shape is the caller's job).
  final Color? Function(T row)? rowMarker;

  @override
  State<AppTable<T>> createState() => _AppTableState<T>();
}

class _AppTableState<T> extends State<AppTable<T>> {
  late final ScrollController _own = ScrollController();
  ScrollController get _scroll => widget.controller ?? _own;
  final _bodyFocus = FocusNode(debugLabel: 'table body');
  final _headFocus = FocusNode(debugLabel: 'table header');
  int _active = -1;
  int _headCol = 0;
  int? _hover;

  /// -1 means nothing is selected yet: no row carries the selection marker until the user acts.
  int get active =>
      math.min(widget.activeIndex ?? _active, widget.rows.length - 1);

  @override
  void dispose() {
    _own.dispose();
    _bodyFocus.dispose();
    _headFocus.dispose();
    super.dispose();
  }

  void _setActive(int i, double rowH, double viewport) {
    if (widget.rows.isEmpty) return;
    i = i.clamp(0, widget.rows.length - 1);
    setState(() => _active = i);
    widget.onActiveChanged?.call(i);
    if (_scroll.hasClients) {
      final top = i * rowH, bottom = top + rowH;
      final off = _scroll.offset;
      if (top < off) {
        _scroll.jumpTo(top);
      } else if (bottom > off + viewport) {
        _scroll.jumpTo(bottom - viewport);
      }
    }
  }

  KeyEventResult _bodyKey(KeyEvent e, double rowH, double viewport) {
    if (e is KeyUpEvent || widget.rows.isEmpty) return KeyEventResult.ignored;
    final page = math.max(1, (viewport / rowH).floor() - 1);
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowDown) {
      _setActive(active + 1, rowH, viewport);
    } else if (k == LogicalKeyboardKey.arrowUp) {
      _setActive(active <= 0 ? 0 : active - 1, rowH, viewport);
    } else if (k == LogicalKeyboardKey.home) {
      _setActive(0, rowH, viewport);
    } else if (k == LogicalKeyboardKey.end) {
      _setActive(widget.rows.length - 1, rowH, viewport);
    } else if (k == LogicalKeyboardKey.pageDown) {
      _setActive(active + page, rowH, viewport);
    } else if (k == LogicalKeyboardKey.pageUp) {
      _setActive(active - page, rowH, viewport);
    } else if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.space) {
      if (active < 0) return KeyEventResult.handled;
      widget.onOpen?.call(widget.rows[active], active);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  KeyEventResult _headKeyEvent(KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowRight) {
      setState(
        () => _headCol = math.min(widget.columns.length - 1, _headCol + 1),
      );
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      setState(() => _headCol = math.max(0, _headCol - 1));
    } else if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.space) {
      final col = widget.columns[_headCol];
      if (col.sortable) widget.onSort?.call(col.id);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final density = context.density;
    final scale = math.max(
      1.0,
      MediaQuery.textScalerOf(context).scale(13) / 13,
    );
    final rowH = (widget.rowHeight ?? density.rowHeight) * scale;

    return LayoutBuilder(
      builder: (context, box) {
        // The scrollbar gets its own column at the right, so it never covers a cell.
        const gutter = scrollGutter;
        final minTotal =
            widget.columns.fold<double>(0, (s, col) => s + col.width) + 3;
        final scrollsX = minTotal + gutter > box.maxWidth;
        final contentW = scrollsX ? minTotal + gutter : box.maxWidth;
        final flexCount = widget.columns.where((col) => col.flex).length;
        final extra = flexCount == 0
            ? 0.0
            : (contentW - gutter - minTotal) / flexCount;
        final widths = [
          for (final col in widget.columns)
            col.width + (col.flex ? math.max(0, extra) : 0),
        ];

        Widget header() {
          return Focus(
            focusNode: _headFocus,
            onKeyEvent: (_, e) => _headKeyEvent(e),
            child: ListenableBuilder(
              listenable: _headFocus,
              builder: (context, _) {
                final focused = _headFocus.hasFocus && keyboardModality;
                return Container(
                  height: rowH,
                  padding: const EdgeInsets.only(
                    left: accentBar,
                    right: gutter,
                  ),
                  decoration: BoxDecoration(
                    color: c.header,
                    border: Border(bottom: BorderSide(color: c.border)),
                  ),
                  child: Row(
                    children: [
                      for (var i = 0; i < widget.columns.length; i++)
                        _HeaderCell(
                          col: widget.columns[i],
                          width: widths[i],
                          sorted: widget.sortId == widget.columns[i].id,
                          ascending: widget.sortAscending,
                          focused: focused && _headCol == i,
                          onTap: widget.columns[i].sortable
                              ? () {
                                  setState(() => _headCol = i);
                                  widget.onSort?.call(widget.columns[i].id);
                                }
                              : null,
                        ),
                    ],
                  ),
                );
              },
            ),
          );
        }

        Widget body() {
          if (widget.loading && widget.rows.isEmpty) {
            return AfterDelay(
              child: _SkeletonRows(widths: widths, rowH: rowH, count: 8),
            );
          }
          if (widget.rows.isEmpty) {
            return widget.empty ?? const SizedBox.shrink();
          }
          return LayoutBuilder(
            builder: (context, b) {
              final viewport = b.maxHeight;
              return Focus(
                focusNode: _bodyFocus,
                onKeyEvent: (_, e) => _bodyKey(e, rowH, viewport),
                child: ListenableBuilder(
                  listenable: _bodyFocus,
                  builder: (context, _) {
                    final focused = _bodyFocus.hasFocus;
                    return ListView.builder(
                      controller: _scroll,
                      itemExtent: rowH,
                      itemCount: widget.rows.length,
                      padding: const EdgeInsets.only(right: scrollGutter),
                      itemBuilder: (context, i) {
                        final row = widget.rows[i];
                        final isActive = i == active;
                        return _BodyRow<T>(
                          key: ValueKey(i),
                          row: row,
                          columns: widget.columns,
                          widths: widths,
                          label: widget.rowLabel(row),
                          active: isActive,
                          showRing: isActive && focused && keyboardModality,
                          hovered: _hover == i,
                          marker: widget.rowMarker?.call(row),
                          onHover: (h) => setState(
                            () =>
                                _hover = h ? i : (_hover == i ? null : _hover),
                          ),
                          onTap: () {
                            _bodyFocus.requestFocus();
                            _setActive(i, rowH, viewport);
                            widget.onOpen?.call(row, i);
                          },
                        );
                      },
                    );
                  },
                ),
              );
            },
          );
        }

        final table = SizedBox(
          width: contentW,
          child: Column(
            children: [
              header(),
              if (widget.summary != null)
                Padding(
                  padding: const EdgeInsets.only(right: gutter),
                  child: widget.summary!,
                ),
              Expanded(child: body()),
            ],
          ),
        );

        return Semantics(
          container: true,
          label: widget.tableLabel,
          child: Column(
            children: [
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.raised,
                    borderRadius: BorderRadius.circular(Radii.container),
                    border: Border.all(color: c.border),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.container - 1),
                    child: scrollsX
                        ? SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: table,
                          )
                        : table,
                  ),
                ),
              ),
              if (widget.footer != null) widget.footer!,
            ],
          ),
        );
      },
    );
  }
}

class _HeaderCell<T> extends StatefulWidget {
  const _HeaderCell({
    required this.col,
    required this.width,
    required this.sorted,
    required this.ascending,
    required this.focused,
    required this.onTap,
  });
  final Col<T> col;
  final double width;
  final bool sorted, ascending, focused;
  final VoidCallback? onTap;

  @override
  State<_HeaderCell<T>> createState() => _HeaderCellState<T>();
}

class _HeaderCellState<T> extends State<_HeaderCell<T>> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final (col, width, sorted, ascending, focused, onTap) = (
      widget.col,
      widget.width,
      widget.sorted,
      widget.ascending,
      widget.focused,
      widget.onTap,
    );
    final label =
        col.headerChild ??
        Text(
          col.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelMedium!.copyWith(
            color: sorted ? c.textPrimary : c.textSecondary,
            fontWeight: sorted ? FontWeight.w600 : FontWeight.w400,
          ),
        );
    final arrow = sorted
        ? Icon(
            ascending ? Icons.arrow_upward_sharp : Icons.arrow_downward_sharp,
            size: 12,
            color: c.textPrimary,
          )
        : (col.sortable
              ? Icon(Icons.unfold_more_sharp, size: 12, color: c.textSecondary)
              : null);
    Widget child = Container(
      width: width,
      height: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: Sp.withinGroup),
      decoration: BoxDecoration(
        color: c.itemFill(hovered: _hovered && onTap != null),
        border: c.itemOutline(focused: focused),
      ),
      child: Row(
        mainAxisAlignment: col.numeric
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (col.numeric && arrow != null) ...[
            arrow,
            const SizedBox(width: Sp.hairline),
          ],
          Flexible(child: label),
          if (!col.numeric && arrow != null) ...[
            const SizedBox(width: Sp.hairline),
            arrow,
          ],
        ],
      ),
    );
    if (col.tooltip != null) {
      child = Tooltip(message: col.tooltip!, child: child);
    }
    return Semantics(
      header: true,
      button: onTap != null,
      sortKey: null,
      label: sorted ? tr.shell.sortedColumn(col.label, ascending) : col.label,
      excludeSemantics: true,
      onTap: onTap,
      child: MouseRegion(
        cursor: onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: child,
        ),
      ),
    );
  }
}

class _BodyRow<T> extends StatelessWidget {
  const _BodyRow({
    super.key,
    required this.row,
    required this.columns,
    required this.widths,
    required this.label,
    required this.active,
    required this.showRing,
    required this.hovered,
    required this.marker,
    required this.onHover,
    required this.onTap,
  });
  final T row;
  final List<Col<T>> columns;
  final List<double> widths;
  final String label;
  final bool active, showRing, hovered;
  final Color? marker;
  final ValueChanged<bool> onHover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // Selection, focus and hover are independent signals and may all be on at once.
    final fill = c.itemFill(selected: active, hovered: hovered);
    final outline = c.itemOutline(selected: active, focused: showRing);
    return Semantics(
      container: true,
      label: label,
      selected: active,
      button: true,
      onTap: onTap,
      child: ExcludeSemantics(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => onHover(true),
          onExit: (_) => onHover(false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Container(
              decoration: BoxDecoration(
                color: fill,
                border: Border(
                  bottom: BorderSide(
                    color: c.border.withValues(alpha: Alpha.muted),
                  ),
                ),
              ),
              foregroundDecoration: outline == null
                  ? null
                  : BoxDecoration(border: outline),
              child: Row(
                children: [
                  // Data only (e.g. the result); selection is the fill and outline.
                  Container(
                    width: accentBar,
                    color: marker ?? Colors.transparent,
                  ),
                  for (var i = 0; i < columns.length; i++)
                    SizedBox(
                      width: widths[i],
                      child: columns[i].bleed
                          ? DefaultTextStyle.merge(
                              style: columns[i].numeric
                                  ? Ty.num(Ty.cell)
                                  : Ty.cell,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              child: columns[i].cell(context, row),
                            )
                          : Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: Sp.withinGroup,
                              ),
                              child: Align(
                                alignment: columns[i].numeric
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: DefaultTextStyle.merge(
                                  style: columns[i].numeric
                                      ? Ty.num(Ty.cell)
                                      : Ty.cell,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  child: columns[i].cell(context, row),
                                ),
                              ),
                            ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SkeletonRows extends StatelessWidget {
  const _SkeletonRows({
    required this.widths,
    required this.rowH,
    required this.count,
  });
  final List<double> widths;
  final double rowH;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: tr.common.loading,
      liveRegion: true,
      child: ExcludeSemantics(
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (var r = 0; r < count; r++)
              SizedBox(
                height: rowH,
                child: Row(
                  children: [
                    const SizedBox(width: accentBar),
                    for (final w in widths)
                      SizedBox(
                        width: w,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: Sp.withinGroup,
                            vertical: Sp.withinGroup,
                          ),
                          child: const Skeleton(radius: 3),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
