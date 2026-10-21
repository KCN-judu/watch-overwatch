import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';
import '../design/tokens.dart';
import '../l10n/strings.dart';
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

String? _needPlayer(AppState a) => tr.core.needPlayer;

List<Cmd> buildCommands() {
  Cmd tab(String id, LogicalKeyboardKey key, String n) => Cmd(
    id: 'view.tab.$id',
    label: tabLabels[id]!,
    category: tr.core.categoryView,
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
    category: tr.core.categoryMode,
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
      label: tr.core.cmdFindPlayer,
      category: tr.core.categoryFile,
      shortcut: const SingleActivator(LogicalKeyboardKey.keyL, control: true),
      shortcutLabel: 'Ctrl+L',
      run: (a, s) => s.focusSearch(),
      keywords: 'search battletag',
    ),
    Cmd(
      id: 'data.export',
      label: tr.core.cmdExport,
      category: tr.core.categoryFile,
      opensDialog: true,
      shortcut: const SingleActivator(LogicalKeyboardKey.keyE, control: true),
      shortcutLabel: 'Ctrl+E',
      enabled: (a) => a.current != null && !a.exporting,
      disabledReason: (a) =>
          a.exporting ? tr.core.exportBusy : tr.core.needPlayer,
      run: (a, s) => s.openExport(),
      keywords: 'export json',
    ),
    Cmd(
      id: 'app.settings',
      label: tr.core.cmdSettings,
      category: tr.core.categoryFile,
      opensDialog: false,
      shortcut: const SingleActivator(LogicalKeyboardKey.comma, control: true),
      shortcutLabel: 'Ctrl+,',
      run: (a, s) => s.showSettings(),
      keywords: tr.core.settingsKeywords,
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
          LogicalKeyboardKey.digit6,
        ][i],
        '${i + 1}',
      ),
    mode(Mode.competitive, LogicalKeyboardKey.digit1, '1'),
    mode(Mode.quick, LogicalKeyboardKey.digit2, '2'),
    mode(Mode.stadium, LogicalKeyboardKey.digit3, '3'),
    Cmd(
      id: 'data.refresh',
      label: tr.core.cmdRefresh,
      category: tr.core.categoryMatches,
      shortcut: const SingleActivator(LogicalKeyboardKey.f5),
      shortcutLabel: 'F5',
      enabled: (a) => a.current != null,
      disabledReason: _needPlayer,
      run: (a, s) => a.refreshCurrent(),
      keywords: 'reload refresh',
    ),
    Cmd(
      id: 'list.filter',
      label: tr.core.cmdSearchList,
      category: tr.core.categoryMatches,
      shortcut: const SingleActivator(LogicalKeyboardKey.keyF, control: true),
      shortcutLabel: 'Ctrl+F',
      enabled: (a) => a.current != null && a.tab == 'matches' && !detailOpen(a),
      disabledReason: (a) => tr.core.onlyInMatchList,
      run: (a, s) => s.focusFilter(),
      keywords: 'filter search',
    ),
    Cmd(
      id: 'match.prev',
      label: tr.core.cmdPrevItem,
      category: tr.core.categoryMatches,
      shortcut: const SingleActivator(LogicalKeyboardKey.bracketLeft),
      shortcutLabel: '[',
      singleKey: true,
      enabled: (a) => detailOpen(a) || heroOpen(a),
      disabledReason: (a) => tr.core.needOpenItem,
      run: (a, s) => heroOpen(a)
          ? a.current?.stepHero(-1)
          : a.current?.openPlayerKey != null
          ? a.current?.stepOpenPlayer(-1)
          : a.current?.stepMatch(-1),
    ),
    Cmd(
      id: 'match.next',
      label: tr.core.cmdNextItem,
      category: tr.core.categoryMatches,
      shortcut: const SingleActivator(LogicalKeyboardKey.bracketRight),
      shortcutLabel: ']',
      singleKey: true,
      enabled: (a) => detailOpen(a) || heroOpen(a),
      disabledReason: (a) => tr.core.needOpenItem,
      run: (a, s) => heroOpen(a)
          ? a.current?.stepHero(1)
          : a.current?.openPlayerKey != null
          ? a.current?.stepOpenPlayer(1)
          : a.current?.stepMatch(1),
    ),
    Cmd(
      id: 'match.back',
      label: tr.core.cmdBackToList,
      category: tr.core.categoryMatches,
      shortcut: const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true),
      shortcutLabel: 'Alt+←  /  Esc',
      enabled: (a) => detailOpen(a) || heroOpen(a),
      disabledReason: (a) => tr.core.needOpenItem,
      run: (a, s) => heroOpen(a)
          ? a.current?.closeHero()
          : a.current?.openPlayerKey != null
          ? a.current?.closePlayer()
          : a.current?.closeMatch(),
    ),
    Cmd(
      id: 'view.nav.toggle',
      label: tr.core.cmdToggleNav,
      category: tr.core.categoryView,
      shortcut: const SingleActivator(LogicalKeyboardKey.keyB, control: true),
      shortcutLabel: 'Ctrl+B',
      run: (a, s) => a.setNav(collapsed: !a.navCollapsed),
    ),
    Cmd(
      id: 'view.pane.next',
      label: tr.core.cmdNextPane,
      category: tr.core.categoryView,
      shortcut: const SingleActivator(LogicalKeyboardKey.f6),
      shortcutLabel: 'F6',
      run: (a, s) => s.focusPane(true),
    ),
    Cmd(
      id: 'view.pane.prev',
      label: tr.core.cmdPrevPane,
      category: tr.core.categoryView,
      shortcut: const SingleActivator(LogicalKeyboardKey.f6, shift: true),
      shortcutLabel: 'Shift+F6',
      run: (a, s) => s.focusPane(false),
    ),
    for (final d in DensityMode.values)
      Cmd(
        id: 'view.density.${d.id}',
        label: tr.core.cmdDensity(d.label),
        category: tr.core.categoryAppearance,
        run: (a, s) => a.setDensity(d),
        keywords: tr.core.densityKeywords,
      ),
    Cmd(
      id: 'view.theme.system',
      label: tr.core.cmdThemeSystem,
      category: tr.core.categoryAppearance,
      run: (a, s) => a.setTheme(ThemeMode.system),
      keywords: tr.core.themeKeywords,
    ),
    Cmd(
      id: 'view.theme.light',
      label: tr.core.cmdThemeLight,
      category: tr.core.categoryAppearance,
      run: (a, s) => a.setTheme(ThemeMode.light),
      keywords: tr.core.themeKeywords,
    ),
    Cmd(
      id: 'view.theme.dark',
      label: tr.core.cmdThemeDark,
      category: tr.core.categoryAppearance,
      run: (a, s) => a.setTheme(ThemeMode.dark),
      keywords: tr.core.themeKeywords,
    ),
    Cmd(
      id: 'view.layout.reset',
      label: tr.core.cmdResetLayout,
      category: tr.core.categoryAppearance,
      run: (a, s) {
        a.setNav(width: 248, collapsed: false);
        a.setDensity(DensityMode.standard);
      },
    ),
    Cmd(
      id: 'help.palette',
      label: tr.core.cmdPalette,
      category: tr.core.categoryHelp,
      shortcut: const SingleActivator(LogicalKeyboardKey.keyK, control: true),
      shortcutLabel: 'Ctrl+K',
      run: (a, s) => s.openPalette(),
    ),
    Cmd(
      id: 'help.shortcuts',
      label: tr.core.cmdShortcuts,
      category: tr.core.categoryHelp,
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
