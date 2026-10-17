import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';
import '../design/tokens.dart';
import '../design/widgets.dart';
import '../state/app_state.dart';
import '../state/commands.dart';

// ---- Command palette ---------------------------------------------------------

class _Entry {
  _Entry.command(this.cmd, this.app)
    : player = null,
      label = cmd!.menuLabel,
      group = '命令';
  _Entry.player(this.player, this.app)
    : cmd = null,
      label = '打开玩家  $player',
      group = '玩家';
  final Cmd? cmd;
  final String? player;
  final AppState app;
  final String label;
  final String group;

  String? get disabledReason => cmd?.reason(app);
  bool get enabled => cmd == null || cmd!.isEnabled(app);
}

List<_Entry> _search(AppState app, List<Cmd> cmds, String q) {
  final query = q.trim().toLowerCase();
  final all = <(int, _Entry)>[];
  for (final p in app.players) {
    if (query.isEmpty) {
      all.add((5, _Entry.player(p, app)));
    } else if (p.toLowerCase().contains(query)) {
      all.add((
        p.toLowerCase().startsWith(query) ? 0 : 1,
        _Entry.player(p, app),
      ));
    }
  }
  for (final c in cmds) {
    if (query.isEmpty) {
      all.add((6, _Entry.command(c, app)));
      continue;
    }
    final label = c.label.toLowerCase();
    final score = label.startsWith(query)
        ? 0
        : label.contains(query)
        ? 1
        : c.category.contains(query)
        ? 2
        : (c.keywords.toLowerCase().contains(query) || c.id.contains(query))
        ? 3
        : null;
    if (score != null) all.add((score, _Entry.command(c, app)));
  }
  // Stable: ties keep registry order; disabled entries sort after enabled ones of equal score.
  final indexed = [
    for (final (i, e) in all.indexed) (e.$1, e.$2.enabled ? 0 : 1, i, e.$2),
  ];
  indexed.sort((a, b) {
    final c1 = a.$1.compareTo(b.$1);
    if (c1 != 0) return c1;
    final c2 = a.$2.compareTo(b.$2);
    return c2 != 0 ? c2 : a.$3.compareTo(b.$3);
  });
  return [for (final e in indexed) e.$4];
}

Future<void> showCommandPalette(
  BuildContext context,
  AppState app,
  ShellActions shell,
  List<Cmd> cmds,
) async {
  final result = await showGeneralDialog<_Entry>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭命令面板',
    barrierColor: Colors.black.withValues(alpha: 0.28),
    transitionDuration: Dur.of(context, Dur.fast),
    pageBuilder: (context, _, _) => Align(
      alignment: const Alignment(0, -0.55),
      child: _Palette(app: app, cmds: cmds),
    ),
  );
  if (result == null) return;
  // Run after the dialog is gone so focus returns to where the user was.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (result.player != null) {
      app.openPlayer(result.player!);
    } else {
      result.cmd!.run(app, shell);
    }
  });
}

class _Palette extends StatefulWidget {
  const _Palette({required this.app, required this.cmds});
  final AppState app;
  final List<Cmd> cmds;
  @override
  State<_Palette> createState() => _PaletteState();
}

class _PaletteState extends State<_Palette> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  int _active = 0;
  static const _limit = 12;

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final results = _search(widget.app, widget.cmds, _text.text);
    final shown = results.take(_limit).toList();
    _active = _active.clamp(0, math.max(0, shown.length - 1));
    return Material(
      color: Colors.transparent,
      child: Focus(
        onKeyEvent: (_, e) {
          if (e is KeyUpEvent) return KeyEventResult.ignored;
          if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
            setState(() => _active = math.min(shown.length - 1, _active + 1));
            return KeyEventResult.handled;
          }
          if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
            setState(() => _active = math.max(0, _active - 1));
            return KeyEventResult.handled;
          }
          if (e.logicalKey == LogicalKeyboardKey.enter &&
              shown.isNotEmpty &&
              shown[_active].enabled) {
            Navigator.of(context).pop(shown[_active]);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Container(
          width: 580,
          constraints: const BoxConstraints(maxHeight: 520),
          decoration: BoxDecoration(
            color: c.raised,
            borderRadius: BorderRadius.circular(Radii.container),
            border: Border.all(color: c.border),
            boxShadow: const [
              BoxShadow(
                color: Color(0x55000000),
                blurRadius: 24,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(Sp.withinGroup),
                child: TextField(
                  controller: _text,
                  focusNode: _focus,
                  autofocus: true,
                  onChanged: (_) => setState(() => _active = 0),
                  decoration: const InputDecoration(
                    hintText: '输入命令或玩家名，例如“导出”“快速”',
                    prefixIcon: Icon(Icons.search, size: 18),
                  ),
                ),
              ),
              Flexible(
                child: shown.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(Sp.betweenSections),
                        child: Text(
                          '没有匹配“${_text.text.trim()}”的命令或玩家。',
                          style: Ty.body.copyWith(color: c.textSecondary),
                        ),
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          for (final (i, e) in shown.indexed)
                            _PaletteRow(
                              entry: e,
                              active: i == _active,
                              showGroup:
                                  i == 0 || shown[i - 1].group != e.group,
                              onTap: e.enabled
                                  ? () => Navigator.of(context).pop(e)
                                  : null,
                            ),
                        ],
                      ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: c.border)),
                ),
                child: Row(
                  children: [
                    Text(
                      results.length > _limit
                          ? '显示 $_limit / ${results.length} 项'
                          : '共 ${results.length} 项',
                      style: Ty.meta.copyWith(color: c.textSecondary),
                    ),
                    const Spacer(),
                    const Kbd('↑↓'),
                    const SizedBox(width: 4),
                    Text('选择', style: Ty.meta.copyWith(color: c.textSecondary)),
                    const SizedBox(width: 12),
                    const Kbd('Enter'),
                    const SizedBox(width: 4),
                    Text('执行', style: Ty.meta.copyWith(color: c.textSecondary)),
                    const SizedBox(width: 12),
                    const Kbd('Esc'),
                    const SizedBox(width: 4),
                    Text('关闭', style: Ty.meta.copyWith(color: c.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaletteRow extends StatelessWidget {
  const _PaletteRow({
    required this.entry,
    required this.active,
    required this.showGroup,
    required this.onTap,
  });
  final _Entry entry;
  final bool active, showGroup;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final enabled = entry.enabled;
    final cmd = entry.cmd;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showGroup)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
            child: Text(
              entry.group,
              style: Ty.meta.copyWith(color: c.textSecondary),
            ),
          ),
        Semantics(
          button: true,
          enabled: enabled,
          selected: active,
          label:
              '${entry.label}${cmd == null ? '' : '，${cmd.category}'}${enabled ? '' : '，不可用：${entry.disabledReason ?? ''}'}',
          excludeSemantics: true,
          onTap: onTap,
          child: InkWell(
            onTap: onTap,
            child: Container(
              color: active ? c.selected : null,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  Container(
                    width: 3,
                    height: 20,
                    color: active ? c.accent : Colors.transparent,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.label,
                          style: Ty.body.copyWith(
                            color: enabled ? c.textPrimary : c.textSecondary,
                          ),
                        ),
                        if (!enabled && entry.disabledReason != null)
                          Text(
                            entry.disabledReason!,
                            style: Ty.meta.copyWith(color: c.textSecondary),
                          ),
                      ],
                    ),
                  ),
                  if (cmd != null)
                    Text(
                      cmd.category,
                      style: Ty.meta.copyWith(color: c.textSecondary),
                    ),
                  if (cmd?.shortcutLabel != null) ...[
                    const SizedBox(width: 8),
                    Kbd(cmd!.shortcutLabel!),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---- Shortcut reference (generated from the registry) --------------------------

Future<void> showShortcuts(BuildContext context, List<Cmd> cmds) {
  return showDialog<void>(
    context: context,
    builder: (context) {
      final c = context.c;
      final byCategory = <String, List<Cmd>>{};
      for (final cmd in cmds) {
        byCategory.putIfAbsent(cmd.category, () => []).add(cmd);
      }
      return Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 620),
          child: Padding(
            padding: const EdgeInsets.all(Sp.betweenSections),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('快捷键参考', style: Ty.section)),
                    AppButton(
                      '关闭',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: Sp.withinControl),
                Text(
                  '所有命令也在菜单和命令面板（Ctrl+K）里。输入文字时，单键快捷键不起作用。',
                  style: Ty.body.copyWith(color: c.textSecondary),
                ),
                const SizedBox(height: Sp.betweenGroups),
                Expanded(
                  child: ListView(
                    children: [
                      for (final e in byCategory.entries) ...[
                        Padding(
                          padding: const EdgeInsets.only(
                            top: Sp.withinGroup,
                            bottom: Sp.withinControl,
                          ),
                          child: Text(e.key, style: Ty.bodyStrong),
                        ),
                        for (final cmd in e.value)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(cmd.menuLabel, style: Ty.body),
                                ),
                                if (cmd.shortcutLabel != null)
                                  Kbd(cmd.shortcutLabel!)
                                else
                                  Text(
                                    '—',
                                    style: Ty.meta.copyWith(
                                      color: c.textSecondary,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

// ---- Export dialog -------------------------------------------------------------

Future<void> showExportDialog(BuildContext context, AppState app) async {
  final ws = app.current;
  if (ws == null) return;
  final modes = {...Mode.values.where((m) => m == app.mode)};
  var pages = 5;
  var details = 20;
  var lobby = false;
  final go = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final c = context.c;
        final estimate =
            1 +
            modes.length * (pages + 1) +
            details +
            (lobby ? (details * 10 * 1.3).round() : 0);
        return Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(Sp.betweenSections),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('导出 ${ws.name} 的数据集', style: Ty.section),
                  const SizedBox(height: Sp.withinControl),
                  Text(
                    '保存为新的 JSON 文件，不覆盖旧文件，不含凭据。',
                    style: Ty.body.copyWith(color: c.textSecondary),
                  ),
                  const SizedBox(height: Sp.betweenGroups),
                  Text('包含的模式', style: Ty.bodyStrong),
                  for (final m in Mode.values)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(m.label, style: Ty.body),
                      value: modes.contains(m),
                      onChanged: (v) => setState(
                        () => v == true ? modes.add(m) : modes.remove(m),
                      ),
                    ),
                  const SizedBox(height: Sp.withinGroup),
                  Row(
                    children: [
                      Expanded(child: Text('每个模式读取的对局页数', style: Ty.body)),
                      DropdownButton<int>(
                        value: pages,
                        items: [
                          for (final p in [1, 3, 5, 10, 20])
                            DropdownMenuItem(value: p, child: Text('$p 页')),
                        ],
                        onChanged: (v) => setState(() => pages = v ?? pages),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(child: Text('读取详情的最新对局数', style: Ty.body)),
                      DropdownButton<int>(
                        value: details,
                        items: [
                          for (final p in [0, 10, 20, 40, 100])
                            DropdownMenuItem(value: p, child: Text('$p 场')),
                        ],
                        onChanged: (v) =>
                            setState(() => details = v ?? details),
                      ),
                    ],
                  ),
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text('包含参与者段位（用于对局强度）', style: Ty.body),
                    subtitle: Text(
                      '每名参与者额外一次查询，明显更慢。',
                      style: Ty.meta.copyWith(color: c.textSecondary),
                    ),
                    value: lobby,
                    onChanged: details == 0
                        ? null
                        : (v) => setState(() => lobby = v == true),
                  ),
                  const SizedBox(height: Sp.withinGroup),
                  Text(
                    '约 $estimate 次请求，后台进行，可随时取消。',
                    style: Ty.meta.copyWith(color: c.textSecondary),
                  ),
                  const SizedBox(height: Sp.betweenGroups),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      AppButton(
                        '取消',
                        onPressed: () => Navigator.of(context).pop(false),
                      ),
                      const SizedBox(width: Sp.withinGroup),
                      AppButton(
                        '开始导出',
                        primary: true,
                        onPressed: modes.isEmpty
                            ? null
                            : () => Navigator.of(context).pop(true),
                        disabledReason: '至少选择一个模式。',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
  if (go == true) {
    app.exportDataset(
      modes: modes.toList(),
      pages: pages,
      details: details,
      lobby: lobby && details > 0,
    );
  }
}
