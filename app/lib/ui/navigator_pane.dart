import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/support.dart';
import '../design/tokens.dart';
import '../design/widgets.dart';
import '../l10n/strings.dart';
import '../state/app_state.dart';
import 'shell.dart';

class NavigatorPane extends StatefulWidget {
  const NavigatorPane({super.key, required this.collapsed});
  final bool collapsed;
  @override
  State<NavigatorPane> createState() => _NavigatorPaneState();
}

class _NavigatorPaneState extends State<NavigatorPane> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _submit(AppState app) async {
    final ok = await app.openPlayer(_text.text);
    if (ok) _text.clear();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final scope = ShellScope.of(context);
    final c = context.c;
    if (widget.collapsed) return _Rail(app: app, scope: scope);

    return ColoredBox(
      color: c.nav,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Sp.betweenItems,
              Sp.betweenItems,
              Sp.betweenItems,
              0,
            ),
            child: Semantics(
              textField: true,
              label: tr.shell.battleTag,
              child: TextField(
                controller: _text,
                focusNode: scope.searchFocus,
                enabled: app.status == BackendStatus.ready,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _submit(app),
                onChanged: (_) => app.clearSearchError(),
                decoration: InputDecoration(
                  hintText: tr.shell.battleTagHint,
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: app.searching
                      ? const Padding(
                          padding: EdgeInsets.all(Sp.withinGroup),
                          child: Spinner(),
                        )
                      : null,
                ),
              ),
            ),
          ),
          if (app.searchError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Sp.betweenItems,
                Sp.withinGroup,
                Sp.betweenItems,
                0,
              ),
              child: Semantics(
                liveRegion: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Not found / bad input: the service's own sentence says what to
                    // type. Anything else: the fixed sentence for its kind.
                    Text(
                      app.searchError!.isLookup
                          ? tr.shell.playerNotFound
                          : tr.shell.searchFailed,
                      style: Ty.bodyStrong.copyWith(color: c.error),
                    ),
                    Text(
                      app.searchError!.isLookup
                          ? app.searchError!.message
                          : tr.shell.errorSentence(app.searchError!.kind),
                      style: Ty.meta.copyWith(color: c.textSecondary),
                    ),
                    if (app.searchError!.isAuth)
                      Padding(
                        padding: const EdgeInsets.only(top: Sp.withinControl),
                        child: AppButton(
                          tr.common.openSettings,
                          quiet: true,
                          onPressed: () => app.showSettings(true),
                        ),
                      ),
                  ],
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Sp.betweenItems,
                Sp.iconGap,
                Sp.betweenItems,
                0,
              ),
              child: Text(
                tr.shell.searchHint,
                style: Ty.meta.copyWith(color: c.textSecondary),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Sp.betweenItems,
              Sp.betweenGroups,
              Sp.betweenItems,
              Sp.withinControl,
            ),
            child: Text(
              tr.shell.playerLibraryCount(app.players.length),
              style: Ty.meta.copyWith(
                color: c.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: app.players.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(Sp.betweenItems),
                    child: Text(
                      tr.shell.playerLibraryEmpty,
                      style: Ty.body.copyWith(color: c.textSecondary),
                    ),
                  )
                : _PlayerList(app: app),
          ),
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.border)),
            ),
            padding: const EdgeInsets.all(Sp.withinGroup),
            child: Row(
              children: [
                Expanded(
                  child: AppButton(
                    tr.shell.settings,
                    quiet: true,
                    icon: Icons.settings_outlined,
                    tooltip: 'Ctrl+,',
                    onPressed: () => app.showSettings(true),
                  ),
                ),
                IconAction(
                  icon: Icons.keyboard_double_arrow_left,
                  label: tr.shell.collapseLibrary,
                  shortcut: 'Ctrl+B',
                  onPressed: () => app.setNav(collapsed: true),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerList extends StatefulWidget {
  const _PlayerList({required this.app});
  final AppState app;
  @override
  State<_PlayerList> createState() => _PlayerListState();
}

class _PlayerListState extends State<_PlayerList> {
  final _focus = FocusNode(debugLabel: 'players');
  int? _cursor;
  int? _hover;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  int _indexOfCurrent() {
    final cur = widget.app.current?.name.toLowerCase();
    return widget.app.players.indexWhere((p) => p.toLowerCase() == cur);
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final c = context.c;
    final players = app.players;
    final cursor = (_cursor ?? math.max(0, _indexOfCurrent())).clamp(
      0,
      players.length - 1,
    );
    return Focus(
      focusNode: _focus,
      onKeyEvent: (_, e) {
        if (e is KeyUpEvent) return KeyEventResult.ignored;
        final k = e.logicalKey;
        if (k == LogicalKeyboardKey.arrowDown) {
          setState(() => _cursor = math.min(players.length - 1, cursor + 1));
        } else if (k == LogicalKeyboardKey.arrowUp) {
          setState(() => _cursor = math.max(0, cursor - 1));
        } else if (k == LogicalKeyboardKey.enter) {
          app.selectPlayer(players[cursor]);
        } else if (k == LogicalKeyboardKey.delete) {
          app.removePlayer(players[cursor]);
        } else {
          return KeyEventResult.ignored;
        }
        return KeyEventResult.handled;
      },
      child: ListenableBuilder(
        listenable: _focus,
        builder: (context, _) {
          final focused = _focus.hasFocus && keyboardModality;
          return ListView.builder(
            padding: const EdgeInsets.only(right: scrollGutter),
            itemCount: players.length,
            itemExtent: 40,
            itemBuilder: (context, i) {
              final name = players[i];
              final selected =
                  app.current?.name.toLowerCase() == name.toLowerCase() &&
                  !app.settingsOpen;
              final (main, tag) = splitTag(name);
              final isCursor = focused && i == cursor;
              final showRemove = _hover == i || isCursor || selected;
              return Semantics(
                button: true,
                selected: selected,
                label: selected
                    ? tr.shell.playerItemCurrent(name)
                    : tr.shell.playerItem(name),
                excludeSemantics: true,
                onTap: () => app.selectPlayer(name),
                onDismiss: () => app.removePlayer(name),
                child: MouseRegion(
                  onEnter: (_) => setState(() => _hover = i),
                  onExit: (_) =>
                      setState(() => _hover = _hover == i ? null : _hover),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      _focus.requestFocus();
                      setState(() => _cursor = i);
                      app.selectPlayer(name);
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: Sp.iconGap,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: c.itemFill(
                          selected: selected,
                          hovered: _hover == i,
                        ),
                        borderRadius: BorderRadius.circular(Radii.control),
                        border: c.itemOutline(
                          selected: selected,
                          focused: isCursor,
                        ),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: Sp.betweenItems),
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: main,
                                    style: Ty.body.copyWith(
                                      fontWeight: selected
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                    ),
                                  ),
                                  TextSpan(
                                    text: tag,
                                    style: Ty.meta.copyWith(
                                      color: c.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // Shown on hover, focus and for the open player, so it is reachable without a pointer.
                          if (showRemove)
                            IconAction(
                              icon: Icons.close,
                              label: tr.shell.removeFromLibrary(name),
                              shortcut: 'Delete',
                              onPressed: () => app.removePlayer(name),
                            )
                          else
                            const SizedBox(width: Sp.page),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({required this.app, required this.scope});
  final AppState app;
  final ShellScope scope;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return ColoredBox(
      color: c.nav,
      child: Column(
        children: [
          const SizedBox(height: Sp.withinGroup),
          IconAction(
            icon: Icons.search,
            label: tr.shell.findPlayer,
            shortcut: 'Ctrl+L',
            onPressed: scope.actions.focusSearch,
          ),
          const SizedBox(height: Sp.withinControl),
          IconAction(
            icon: Icons.keyboard_double_arrow_right,
            label: tr.shell.expandLibrary,
            shortcut: 'Ctrl+B',
            onPressed: () => app.setNav(collapsed: false),
          ),
          const Divider(height: 16, indent: 12, endIndent: 12),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(right: scrollGutter),
              children: [
                for (final name in app.players)
                  Builder(
                    builder: (context) {
                      final selected =
                          app.current?.name.toLowerCase() ==
                              name.toLowerCase() &&
                          !app.settingsOpen;
                      return Tooltip(
                        message: name,
                        child: Semantics(
                          button: true,
                          selected: selected,
                          label: tr.shell.playerItem(name),
                          excludeSemantics: true,
                          onTap: () => app.selectPlayer(name),
                          child: InkWell(
                            onTap: () => app.selectPlayer(name),
                            child: Container(
                              height: 40,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: c.itemFill(selected: selected),
                                border: c.itemOutline(selected: selected),
                              ),
                              child: Text(
                                name.characters.first.toUpperCase(),
                                style: Ty.bodyStrong,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          const SizedBox(height: Sp.withinGroup),
          IconAction(
            icon: Icons.settings_outlined,
            label: tr.shell.settings,
            shortcut: 'Ctrl+,',
            onPressed: () => app.showSettings(true),
          ),
          const SizedBox(height: Sp.withinGroup),
        ],
      ),
    );
  }
}
