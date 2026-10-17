import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';
import '../design/tokens.dart';
import 'app_state.dart';

/// Shell-level actions commands can trigger. Implemented by the shell widget.
abstract class ShellActions {
  void openPalette();
  void openShortcuts();
  void openExport();
  void showSettings();
  void focusSearch();
  void focusPane(bool forward);
  void focusFilter();
}

class Cmd {
  const Cmd({
    required this.id,
    required this.label,
    required this.category,
    required this.run,
    this.shortcut,
    this.shortcutLabel,
    this.enabled,
    this.disabledReason,
    this.singleKey = false,
    this.keywords = '',
    this.opensDialog = false,
  });

  /// Stable identifier, never localised.
  final String id;
  final String label;
  final String category;
  final void Function(AppState app, ShellActions shell) run;
  final SingleActivator? shortcut;
  final String? shortcutLabel;
  final bool Function(AppState app)? enabled;
  final String? Function(AppState app)? disabledReason;

  /// Printable single-key shortcuts must stay silent while a text field has focus.
  final bool singleKey;
  final String keywords;

  /// Label gets an ellipsis: the command shows a dialog instead of executing at once.
  final bool opensDialog;

  bool isEnabled(AppState a) => enabled?.call(a) ?? true;
  String? reason(AppState a) => isEnabled(a) ? null : disabledReason?.call(a);
  String get menuLabel => opensDialog ? '$label…' : label;
}

String? _needPlayer(AppState a) => '先在左侧打开一名玩家。';

List<Cmd> buildCommands() {
  Cmd tab(String id, LogicalKeyboardKey key, String n) => Cmd(
    id: 'view.tab.$id',
    label: tabLabels[id]!,
    category: '视图',
    shortcut: SingleActivator(key, control: true),
    shortcutLabel: 'Ctrl+$n',
    enabled: (a) => a.current != null,
    disabledReason: _needPlayer,
    run: (a, s) => a.setTab(id),
    keywords: 'tab page',
  );
  Cmd mode(Mode m, LogicalKeyboardKey key, String n) => Cmd(
    id: 'view.mode.${m.id}',
    label: m.label,
    category: '模式',
    shortcut: SingleActivator(key, alt: true),
    shortcutLabel: 'Alt+$n',
    run: (a, s) => a.setMode(m),
    keywords: 'mode',
  );

  bool detailOpen(AppState a) =>
      a.current?.openMatchId != null && a.tab == 'matches';
  bool heroOpen(AppState a) =>
      a.current?.openHeroKey != null && a.tab == 'heroes';

  return [
    Cmd(
      id: 'player.find',
      label: '查找玩家',
      category: '文件',
      shortcut: const SingleActivator(LogicalKeyboardKey.keyL, control: true),
      shortcutLabel: 'Ctrl+L',
      run: (a, s) => s.focusSearch(),
      keywords: 'search battletag',
    ),
    Cmd(
      id: 'data.export',
      label: '导出数据集',
      category: '文件',
      opensDialog: true,
      shortcut: const SingleActivator(LogicalKeyboardKey.keyE, control: true),
      shortcutLabel: 'Ctrl+E',
      enabled: (a) => a.current != null && !a.exporting,
      disabledReason: (a) => a.exporting ? '正在导出，请等待完成或取消。' : '先在左侧打开一名玩家。',
      run: (a, s) => s.openExport(),
      keywords: 'export json',
    ),
    Cmd(
      id: 'app.settings',
      label: '设置',
      category: '文件',
      opensDialog: false,
      shortcut: const SingleActivator(LogicalKeyboardKey.comma, control: true),
      shortcutLabel: 'Ctrl+,',
      run: (a, s) => s.showSettings(),
      keywords: 'account 账号 token 外观',
    ),
    for (final (i, id) in tabIds.indexed)
      tab(
        id,
        [
          LogicalKeyboardKey.digit1,
          LogicalKeyboardKey.digit2,
          LogicalKeyboardKey.digit3,
          LogicalKeyboardKey.digit4,
          LogicalKeyboardKey.digit5,
        ][i],
        '${i + 1}',
      ),
    mode(Mode.competitive, LogicalKeyboardKey.digit1, '1'),
    mode(Mode.quick, LogicalKeyboardKey.digit2, '2'),
    mode(Mode.stadium, LogicalKeyboardKey.digit3, '3'),
    Cmd(
      id: 'data.refresh',
      label: '刷新数据',
      category: '对局',
      shortcut: const SingleActivator(LogicalKeyboardKey.f5),
      shortcutLabel: 'F5',
      enabled: (a) => a.current != null,
      disabledReason: _needPlayer,
      run: (a, s) => a.refreshCurrent(),
      keywords: 'reload refresh',
    ),
    Cmd(
      id: 'list.filter',
      label: '筛选当前列表',
      category: '对局',
      shortcut: const SingleActivator(LogicalKeyboardKey.keyF, control: true),
      shortcutLabel: 'Ctrl+F',
      enabled: (a) => a.current != null && a.tab == 'matches' && !detailOpen(a),
      disabledReason: (a) => '在对局列表中可用。',
      run: (a, s) => s.focusFilter(),
      keywords: 'filter search',
    ),
    Cmd(
      id: 'list.more',
      label: '读取更多对局',
      category: '对局',
      enabled: (a) => a.current != null && a.tab == 'matches',
      disabledReason: (a) => '在对局列表中可用。',
      run: (a, s) => a.current?.loadMore(a.mode),
      keywords: 'load more page',
    ),
    Cmd(
      id: 'match.prev',
      label: '上一场',
      category: '对局',
      shortcut: const SingleActivator(LogicalKeyboardKey.bracketLeft),
      shortcutLabel: '[',
      singleKey: true,
      enabled: (a) => detailOpen(a) || heroOpen(a),
      disabledReason: (a) => '打开一场对局或一个英雄后可用。',
      run: (a, s) =>
          heroOpen(a) ? a.current?.stepHero(-1) : a.current?.stepMatch(-1),
    ),
    Cmd(
      id: 'match.next',
      label: '下一场',
      category: '对局',
      shortcut: const SingleActivator(LogicalKeyboardKey.bracketRight),
      shortcutLabel: ']',
      singleKey: true,
      enabled: (a) => detailOpen(a) || heroOpen(a),
      disabledReason: (a) => '打开一场对局或一个英雄后可用。',
      run: (a, s) =>
          heroOpen(a) ? a.current?.stepHero(1) : a.current?.stepMatch(1),
    ),
    Cmd(
      id: 'match.back',
      label: '返回对局列表',
      category: '对局',
      shortcut: const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true),
      shortcutLabel: 'Alt+←  /  Esc',
      enabled: (a) => detailOpen(a) || heroOpen(a),
      disabledReason: (a) => '打开一场对局或一个英雄后可用。',
      run: (a, s) =>
          heroOpen(a) ? a.current?.closeHero() : a.current?.closeMatch(),
    ),
    Cmd(
      id: 'view.nav.toggle',
      label: '折叠或展开玩家库',
      category: '视图',
      shortcut: const SingleActivator(LogicalKeyboardKey.keyB, control: true),
      shortcutLabel: 'Ctrl+B',
      run: (a, s) => a.setNav(collapsed: !a.navCollapsed),
    ),
    Cmd(
      id: 'view.pane.next',
      label: '切换窗格',
      category: '视图',
      shortcut: const SingleActivator(LogicalKeyboardKey.f6),
      shortcutLabel: 'F6',
      run: (a, s) => s.focusPane(true),
    ),
    Cmd(
      id: 'view.pane.prev',
      label: '反向切换窗格',
      category: '视图',
      shortcut: const SingleActivator(LogicalKeyboardKey.f6, shift: true),
      shortcutLabel: 'Shift+F6',
      run: (a, s) => s.focusPane(false),
    ),
    for (final d in DensityMode.values)
      Cmd(
        id: 'view.density.${d.id}',
        label: '表格密度：${d.label}',
        category: '外观',
        run: (a, s) => a.setDensity(d),
        keywords: 'density 行高',
      ),
    Cmd(
      id: 'view.theme.system',
      label: '外观：跟随系统',
      category: '外观',
      run: (a, s) => a.setTheme(ThemeMode.system),
      keywords: 'theme 主题',
    ),
    Cmd(
      id: 'view.theme.light',
      label: '外观：浅色',
      category: '外观',
      run: (a, s) => a.setTheme(ThemeMode.light),
      keywords: 'theme 主题',
    ),
    Cmd(
      id: 'view.theme.dark',
      label: '外观：深色',
      category: '外观',
      run: (a, s) => a.setTheme(ThemeMode.dark),
      keywords: 'theme 主题',
    ),
    Cmd(
      id: 'view.layout.reset',
      label: '重置界面布局',
      category: '外观',
      run: (a, s) {
        a.setNav(width: 248, collapsed: false);
        a.setDensity(DensityMode.standard);
      },
    ),
    Cmd(
      id: 'help.palette',
      label: '命令面板',
      category: '帮助',
      shortcut: const SingleActivator(LogicalKeyboardKey.keyK, control: true),
      shortcutLabel: 'Ctrl+K',
      run: (a, s) => s.openPalette(),
    ),
    Cmd(
      id: 'help.shortcuts',
      label: '快捷键参考',
      category: '帮助',
      shortcut: const SingleActivator(LogicalKeyboardKey.f1),
      shortcutLabel: 'F1',
      run: (a, s) => s.openShortcuts(),
    ),
  ];
}

/// Esc leaves the open match, but only when nothing closer has claimed it.
final escapeActivator = const SingleActivator(LogicalKeyboardKey.escape);

/// True while a text field has keyboard focus.
bool editingText() {
  final ctx = FocusManager.instance.primaryFocus?.context;
  return ctx != null &&
      ctx.findAncestorWidgetOfExactType<EditableText>() != null;
}

class CmdIntent extends Intent {
  const CmdIntent(this.id);
  final String id;
}
