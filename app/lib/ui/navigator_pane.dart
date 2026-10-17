import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/support.dart';
import '../design/data_table.dart' show keyboardModality;
import '../design/tokens.dart';
import '../design/widgets.dart';
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
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Semantics(
              textField: true,
              label: '战网昵称',
              child: TextField(
                controller: _text,
                focusNode: scope.searchFocus,
                enabled: app.status == BackendStatus.ready,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _submit(app),
                onChanged: (_) => app.clearSearchError(),
                decoration: InputDecoration(
                  hintText: '战网昵称，如 Player#12345',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: app.searching
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                ),
              ),
            ),
          ),
          if (app.searchError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Semantics(
                liveRegion: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '没有找到这名玩家',
                      style: Ty.bodyStrong.copyWith(color: c.error),
                    ),
                    Text(
                      app.searchError!.message,
                      style: Ty.meta.copyWith(color: c.textSecondary),
                    ),
                    if (app.searchError!.isAuth)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: AppButton(
                          '打开设置',
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
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: Text(
                '输入完整昵称后按 Enter。',
                style: Ty.meta.copyWith(color: c.textSecondary),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 4),
            child: Text(
              '玩家库 · ${app.players.length}',
              style: Ty.meta.copyWith(
                color: c.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: app.players.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      '还没有玩家。查找成功的玩家会保存在这里，重启后仍然可选。',
                      style: Ty.body.copyWith(color: c.textSecondary),
                    ),
                  )
                : _PlayerList(app: app),
          ),
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.border)),
            ),
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: AppButton(
                    '设置',
                    quiet: true,
                    icon: Icons.settings_outlined,
                    tooltip: 'Ctrl+,',
                    onPressed: () => app.showSettings(true),
                  ),
                ),
                IconAction(
                  icon: Icons.keyboard_double_arrow_left,
                  label: '折叠玩家库',
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
                label: '玩家 $name${selected ? '，当前' : ''}',
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
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? c.selected
                            : (_hover == i ? c.hover : null),
                        borderRadius: BorderRadius.circular(Radii.control),
                        border: isCursor
                            ? Border.all(color: c.accent, width: 2)
                            : null,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 3,
                            height: 20,
                            margin: const EdgeInsets.only(left: 2, right: 8),
                            color: selected ? c.accent : Colors.transparent,
                          ),
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
                              label: '从玩家库移除 $name',
                              shortcut: 'Delete',
                              onPressed: () => app.removePlayer(name),
                            )
                          else
                            const SizedBox(width: 32),
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
          const SizedBox(height: 8),
          IconAction(
            icon: Icons.search,
            label: '查找玩家',
            shortcut: 'Ctrl+L',
            onPressed: scope.actions.focusSearch,
          ),
          const SizedBox(height: 4),
          IconAction(
            icon: Icons.keyboard_double_arrow_right,
            label: '展开玩家库',
            shortcut: 'Ctrl+B',
            onPressed: () => app.setNav(collapsed: false),
          ),
          const Divider(height: 16, indent: 12, endIndent: 12),
          Expanded(
            child: ListView(
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
                          label: '玩家 $name',
                          excludeSemantics: true,
                          onTap: () => app.selectPlayer(name),
                          child: InkWell(
                            onTap: () => app.selectPlayer(name),
                            child: Container(
                              height: 40,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: selected ? c.selected : null,
                                border: Border(
                                  left: BorderSide(
                                    color: selected
                                        ? c.accent
                                        : Colors.transparent,
                                    width: 3,
                                  ),
                                ),
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
          const SizedBox(height: 8),
          IconAction(
            icon: Icons.settings_outlined,
            label: '设置',
            shortcut: 'Ctrl+,',
            onPressed: () => app.showSettings(true),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
