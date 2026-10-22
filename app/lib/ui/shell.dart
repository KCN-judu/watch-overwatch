import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../design/tokens.dart';
import '../design/widgets.dart';
import '../l10n/strings.dart';
import '../state/app_state.dart';
import '../state/commands.dart';
import 'navigator_pane.dart';
import 'overlays.dart';
import 'pages/settings_page.dart';
import 'player_view.dart';
import '../design/net_pic.dart';

/// Hands pane-level handles to descendants.
class ShellScope extends InheritedWidget {
  const ShellScope({
    super.key,
    required this.searchFocus,
    required this.filterFocus,
    required this.actions,
    required super.child,
  });
  final FocusNode searchFocus;
  final FocusNode filterFocus;
  final ShellActions actions;
  static ShellScope of(BuildContext c) =>
      c.dependOnInheritedWidgetOfExactType<ShellScope>()!;
  @override
  bool updateShouldNotify(ShellScope old) => false;
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> implements ShellActions {
  final _navScope = FocusScopeNode(debugLabel: 'player library');
  final _workScope = FocusScopeNode(debugLabel: 'work area');
  final _searchFocus = FocusNode(debugLabel: 'search');
  final _filterFocus = FocusNode(debugLabel: 'filter');
  final _commands = buildCommands();
  late final AppState _app = AppScope.read(context);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _app.toast = _showToast;
      _app.focusSearch = focusSearch;
      _app.boot();
    });
  }

  @override
  void dispose() {
    _navScope.dispose();
    _workScope.dispose();
    _searchFocus.dispose();
    _filterFocus.dispose();
    super.dispose();
  }

  void _showToast(String message, {String? actionLabel, VoidCallback? action}) {
    if (!mounted) return;
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(
      SnackBar(
        content: Text(message),
        // Undo toasts last 7 s; plain acknowledgements 5 s. All are keyboard-dismissible via the action/close.
        duration: Duration(seconds: action == null ? 5 : 7),
        showCloseIcon: true,
        action: action == null
            ? null
            : SnackBarAction(
                label: actionLabel ?? tr.shell.undo,
                onPressed: action,
              ),
      ),
    );
  }

  // ---- ShellActions -------------------------------------------------------------

  @override
  void openPalette() => showCommandPalette(context, _app, this, _commands);
  @override
  void openShortcuts() => showShortcuts(context, _commands);
  @override
  void openExport() => showExportDialog(context, _app);
  @override
  void showSettings() => _app.showSettings(true);
  @override
  void focusSearch() {
    if (_app.navCollapsed) _app.setNav(collapsed: false);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _searchFocus.requestFocus(),
    );
  }

  @override
  void focusPane(bool forward) {
    if (_navScope.hasFocus) {
      _workScope.requestFocus();
    } else {
      _navScope.requestFocus();
    }
  }

  @override
  void focusFilter() => _filterFocus.requestFocus();

  // ---- Build --------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = context.c;
    final shortcuts = <ShortcutActivator, Intent>{
      for (final cmd in _commands)
        if (cmd.shortcut != null) cmd.shortcut!: CmdIntent(cmd.id),
      escapeActivator: const CmdIntent('match.back'),
    };
    return ShellScope(
      searchFocus: _searchFocus,
      filterFocus: _filterFocus,
      actions: this,
      child: Shortcuts(
        shortcuts: shortcuts,
        child: Actions(
          actions: {
            CmdIntent: _CmdAction(_app, this, {
              for (final c in _commands) c.id: c,
            }),
          },
          // Something inside the shortcut scope must always hold focus, otherwise key
          // events never reach it (for example right after launch).
          child: Focus(
            autofocus: true,
            debugLabel: 'app root',
            child: Scaffold(
              backgroundColor: c.window,
              body: Column(
                children: [
                  _MenuBarRow(commands: _commands, app: app, shell: this),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, box) {
                        // Below ~1100px a two-pane layout crushes the work surface: the
                        // library re-prioritises to an icon rail instead.
                        final collapsed =
                            app.navCollapsed || box.maxWidth < 1100;
                        final maxNav = math.max(180.0, box.maxWidth - 720 - 8);
                        final navW = collapsed
                            ? 56.0
                            : app.navWidth
                                  .clamp(180.0, math.min(360.0, maxNav))
                                  .toDouble();
                        return Row(
                          children: [
                            SizedBox(
                              width: navW,
                              child: _PaneFrame(
                                scope: _navScope,
                                label: tr.shell.playerLibrary,
                                color: c.nav,
                                child: NavigatorPane(collapsed: collapsed),
                              ),
                            ),
                            if (!collapsed)
                              Splitter(
                                onDrag: (dx) => app.setNav(
                                  width: (app.navWidth + dx)
                                      .clamp(180.0, math.min(360.0, maxNav))
                                      .toDouble(),
                                ),
                                onReset: () => app.setNav(width: 248),
                              )
                            else
                              Container(width: 1, color: c.border),
                            Expanded(
                              child: _PaneFrame(
                                scope: _workScope,
                                label: tr.shell.workArea,
                                color: c.window,
                                child: const _WorkArea(),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  const _StatusBar(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Marks which pane owns keyboard focus: a 2px accent edge, separate from any widget's focus ring.
class _PaneFrame extends StatelessWidget {
  const _PaneFrame({
    required this.scope,
    required this.label,
    required this.color,
    required this.child,
  });
  final FocusScopeNode scope;
  final String label;
  final Color color;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: label,
      child: FocusScope(
        node: scope,
        child: ListenableBuilder(
          listenable: scope,
          builder: (context, _) => Container(
            color: color,
            child: Column(
              children: [
                Container(
                  height: 2,
                  color: scope.hasFocus && keyboardModality
                      ? c.accent
                      : Colors.transparent,
                ),
                Expanded(child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Runs a registry command from a shortcut. Printable single-key shortcuts
/// stand down while the user is typing.
class _CmdAction extends Action<CmdIntent> {
  _CmdAction(this.app, this.shell, this.byId);
  final AppState app;
  final ShellActions shell;
  final Map<String, Cmd> byId;

  @override
  bool isEnabled(CmdIntent intent) {
    final cmd = byId[intent.id];
    if (cmd == null || !cmd.isEnabled(app)) return false;
    if (cmd.singleKey && editingText()) return false;
    // Esc and Alt+Left must not steal keys from an open text field's own editing.
    if (intent.id == 'match.back' && editingText()) return false;
    return true;
  }

  @override
  Object? invoke(CmdIntent intent) {
    byId[intent.id]!.run(app, shell);
    return null;
  }
}

// ---- Menu bar (generated from the same registry) ---------------------------------

class _MenuBarRow extends StatelessWidget {
  const _MenuBarRow({
    required this.commands,
    required this.app,
    required this.shell,
  });
  final List<Cmd> commands;
  final AppState app;
  final ShellActions shell;

  // Matched against Cmd.category, so these are the same entries the commands use.
  static final order = [
    tr.core.categoryFile,
    tr.core.categoryView,
    tr.core.categoryMode,
    tr.core.categoryMatches,
    tr.core.categoryAppearance,
    tr.core.categoryHelp,
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final byCat = <String, List<Cmd>>{};
    for (final cmd in commands) {
      byCat.putIfAbsent(cmd.category, () => []).add(cmd);
    }
    return Container(
      height: 30,
      decoration: BoxDecoration(
        color: c.nav,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: MenuBar(
              style: MenuStyle(
                backgroundColor: const WidgetStatePropertyAll(
                  Colors.transparent,
                ),
                elevation: const WidgetStatePropertyAll(0),
                shadowColor: const WidgetStatePropertyAll(Colors.transparent),
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 4),
                ),
                minimumSize: const WidgetStatePropertyAll(Size.fromHeight(30)),
                maximumSize: const WidgetStatePropertyAll(Size.fromHeight(30)),
              ),
              children: [
                for (final cat in order)
                  if (byCat[cat] != null)
                    SubmenuButton(
                      style: ButtonStyle(
                        padding: const WidgetStatePropertyAll(
                          EdgeInsets.symmetric(horizontal: 10),
                        ),
                        minimumSize: const WidgetStatePropertyAll(Size(0, 30)),
                      ),
                      menuChildren: [
                        for (final cmd in byCat[cat]!) _item(context, cmd),
                      ],
                      child: Text(cat),
                    ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: AppButton(
              tr.shell.commandPalette,
              quiet: true,
              icon: Icons.search,
              onPressed: shell.openPalette,
              tooltip: 'Ctrl+K',
            ),
          ),
        ],
      ),
    );
  }

  Widget _item(BuildContext context, Cmd cmd) {
    final c = context.c;
    final enabled = cmd.isEnabled(app);
    final button = MenuItemButton(
      onPressed: enabled ? () => cmd.run(app, shell) : null,
      // Shortcut text is shown here; the shortcut itself is registered once, in the shell.
      trailingIcon: cmd.shortcutLabel == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(left: 24),
              child: Text(
                cmd.shortcutLabel!,
                style: Ty.meta.copyWith(color: c.textSecondary),
              ),
            ),
      child: Text(cmd.menuLabel),
    );
    final reason = cmd.reason(app);
    return reason == null ? button : Tooltip(message: reason, child: button);
  }
}

// ---- Work area ---------------------------------------------------------------------

class _WorkArea extends StatelessWidget {
  const _WorkArea();
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (app.status == BackendStatus.starting) {
      return EmptyState(
        title: tr.shell.backendStartingTitle,
        body: tr.shell.backendStartingBody,
        icon: Icons.hourglass_empty,
      );
    }
    if (app.status == BackendStatus.offline) {
      return Center(
        child: ErrorPanel(
          what: tr.shell.backendNotRunning,
          error: ApiError(
            'offline',
            app.backendError ?? tr.shell.backendUnreachable,
          ),
          dataSafe: tr.shell.backendDataSafe,
          onRetry: app.boot,
        ),
      );
    }
    if (app.settingsOpen) return const SettingsPage();
    final ws = app.current;
    return Column(
      children: [
        if (app.noAccount)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Sp.betweenGroups,
              Sp.betweenGroups,
              Sp.betweenGroups,
              0,
            ),
            child: StatusBanner(
              severity: Severity.warning,
              title: tr.shell.noAccountTitle,
              detail: tr.shell.noAccountDetail,
              actions: [
                AppButton(
                  tr.shell.addAccount,
                  primary: true,
                  onPressed: () => app.showSettings(true),
                ),
              ],
            ),
          )
        else if (app.server != null && !app.anyAccountReady)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Sp.betweenGroups,
              Sp.betweenGroups,
              Sp.betweenGroups,
              0,
            ),
            child: StatusBanner(
              severity: Severity.warning,
              title: tr.shell.noReadyAccountTitle,
              detail: tr.shell.noReadyAccountDetail,
              actions: [
                AppButton(
                  tr.common.openSettings,
                  onPressed: () => app.showSettings(true),
                ),
              ],
            ),
          ),
        Expanded(
          child: ws == null
              ? FirstRun(hasAccount: !app.noAccount)
              : PlayerView(key: ValueKey(ws.name), workspace: ws),
        ),
      ],
    );
  }
}

/// The work area before any player is open: the three steps to see one's own data, and
/// the sample player to look around with first.
class FirstRun extends StatelessWidget {
  const FirstRun({super.key, required this.hasAccount});
  final bool hasAccount;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final scope = ShellScope.of(context);
    final c = context.c;
    if (app.players.isNotEmpty) {
      return EmptyState(
        icon: Icons.person_search_outlined,
        title: tr.shell.choosePlayer,
        body: tr.shell.choosePlayerBody,
        actions: [
          AppButton(
            tr.shell.findPlayer,
            primary: true,
            icon: Icons.search,
            onPressed: scope.actions.focusSearch,
            tooltip: 'Ctrl+L',
          ),
          AppButton(
            tr.shell.openSample,
            icon: Icons.science_outlined,
            tooltip: tr.shell.trySampleBody,
            onPressed: app.searching
                ? null
                : () => app.openPlayer(tr.shell.sampleName),
          ),
        ],
      );
    }
    Widget step(
      int n,
      String title,
      String body,
      Widget? action, {
      bool done = false,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: Sp.betweenGroups),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: done ? c.positive : c.accent,
              shape: BoxShape.circle,
            ),
            child: done
                ? Icon(Icons.check, size: 16, color: c.onAccent)
                : Text('$n', style: Ty.bodyStrong.copyWith(color: c.onAccent)),
          ),
          const SizedBox(width: Sp.betweenGroups),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  done ? tr.shell.stepAccountDone : title,
                  style: Ty.bodyStrong,
                ),
                const SizedBox(height: 2),
                Text(body, style: Ty.body.copyWith(color: c.textSecondary)),
                if (action != null) ...[
                  const SizedBox(height: Sp.withinGroup),
                  action,
                ],
              ],
            ),
          ),
        ],
      ),
    );
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Sp.page),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr.shell.welcomeTitle, style: Ty.title),
              const SizedBox(height: Sp.withinControl),
              Text(
                tr.shell.welcomeBody,
                style: Ty.body.copyWith(color: c.textSecondary),
              ),
              const SizedBox(height: Sp.betweenSections),
              step(
                1,
                tr.shell.stepAccount,
                tr.shell.stepAccountBody,
                hasAccount
                    ? null
                    : AppButton(
                        tr.shell.addAccount,
                        primary: true,
                        onPressed: () => app.showSettings(true),
                      ),
                done: hasAccount,
              ),
              step(
                2,
                tr.shell.stepFind,
                tr.shell.stepFindBody,
                AppButton(
                  tr.shell.findPlayer,
                  primary: hasAccount,
                  icon: Icons.search,
                  onPressed: scope.actions.focusSearch,
                  tooltip: 'Ctrl+L',
                ),
              ),
              step(3, tr.shell.stepRead, tr.shell.stepReadBody, null),
              const SizedBox(height: Sp.withinGroup),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(Sp.betweenGroups),
                decoration: BoxDecoration(
                  color: c.raised,
                  border: Border.all(color: c.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr.shell.trySample, style: Ty.bodyStrong),
                    const SizedBox(height: 2),
                    Text(
                      tr.shell.trySampleBody,
                      style: Ty.body.copyWith(color: c.textSecondary),
                    ),
                    const SizedBox(height: Sp.withinGroup),
                    AppButton(
                      tr.shell.openSample,
                      icon: Icons.science_outlined,
                      onPressed: app.searching
                          ? null
                          : () => app.openPlayer(tr.shell.sampleName),
                    ),
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

// ---- Status bar -----------------------------------------------------------------------

class _StatusBar extends StatelessWidget {
  const _StatusBar();
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = context.c;
    final (icon, text) = switch (app.status) {
      BackendStatus.ready => (
        Icons.check_circle_outline,
        tr.shell.backendConnected,
      ),
      BackendStatus.starting => (
        Icons.hourglass_empty,
        tr.shell.backendStarting,
      ),
      BackendStatus.offline => (
        Icons.error_outline,
        tr.shell.backendDisconnected,
      ),
    };
    final ready = app.accounts.where((a) => a['status'] == 'ready').length;
    final style = Ty.meta.copyWith(color: c.textSecondary);
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: c.nav,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 13,
            color: app.status == BackendStatus.offline
                ? c.error
                : c.textSecondary,
          ),
          const SizedBox(width: 4),
          Text(text, style: style),
          if (app.server != null) ...[
            const SizedBox(width: 12),
            Text(
              tr.shell.accountsReady(ready, app.accounts.length),
              style: style,
            ),
          ],
          const SizedBox(width: 12),
          if (app.currentSeason case final season?)
            Text(tr.common.season(season), style: style),
          const Spacer(),
          const ImageProgress(),
          const SizedBox(width: 12),
          if (app.exporting) ...[
            RefreshingChip(label: app.exportStatus ?? tr.shell.exporting),
            const SizedBox(width: 8),
            AppButton(
              tr.shell.cancelExport,
              quiet: true,
              onPressed: app.cancelExport,
            ),
          ] else if (app.lastExportPath != null)
            Flexible(
              child: Tooltip(
                message: app.lastExportPath!,
                child: Text(
                  tr.shell.lastExport(app.lastExportPath!),
                  style: style,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
