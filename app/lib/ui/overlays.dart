import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';
import '../design/dialog.dart';
import '../design/tokens.dart';
import '../design/widgets.dart';
import '../l10n/strings.dart';
import '../state/app_state.dart';
import '../state/commands.dart';

// ---- Command palette ---------------------------------------------------------

class _Entry {
  _Entry.command(this.cmd, this.app)
    : player = null,
      label = cmd!.menuLabel,
      group = tr.shell.paletteGroupCommands;
  _Entry.player(this.player, this.app)
    : cmd = null,
      label = tr.shell.openPlayer(player!),
      group = tr.shell.paletteGroupPlayers;
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
    barrierLabel: tr.shell.closePalette,
    barrierColor: AppColors.barrier,
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
                color: AppColors.shadow,
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
                  decoration: InputDecoration(
                    hintText: tr.shell.paletteHint,
                    prefixIcon: const Icon(Icons.search, size: 18),
                  ),
                ),
              ),
              Flexible(
                child: shown.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(Sp.betweenSections),
                        child: Text(
                          tr.shell.paletteNoMatch(_text.text.trim()),
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
                  horizontal: Sp.betweenItems,
                  vertical: Sp.iconGap,
                ),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: c.border)),
                ),
                child: Row(
                  children: [
                    Text(
                      results.length > _limit
                          ? tr.shell.paletteShowing(_limit, results.length)
                          : tr.shell.paletteTotal(results.length),
                      style: Ty.meta.copyWith(color: c.textSecondary),
                    ),
                    const Spacer(),
                    const Kbd('↑↓'),
                    const SizedBox(width: Sp.withinControl),
                    Text(
                      tr.shell.paletteSelect,
                      style: Ty.meta.copyWith(color: c.textSecondary),
                    ),
                    const SizedBox(width: Sp.betweenItems),
                    const Kbd('Enter'),
                    const SizedBox(width: Sp.withinControl),
                    Text(
                      tr.shell.paletteRun,
                      style: Ty.meta.copyWith(color: c.textSecondary),
                    ),
                    const SizedBox(width: Sp.betweenItems),
                    const Kbd('Esc'),
                    const SizedBox(width: Sp.withinControl),
                    Text(
                      tr.common.close,
                      style: Ty.meta.copyWith(color: c.textSecondary),
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
            padding: const EdgeInsets.fromLTRB(
              Sp.betweenItems,
              Sp.withinGroup,
              Sp.betweenItems,
              Sp.hairline,
            ),
            child: Text(
              entry.group,
              style: Ty.meta.copyWith(color: c.textSecondary),
            ),
          ),
        Semantics(
          button: true,
          enabled: enabled,
          selected: active,
          label: tr.shell.paletteEntry(
            entry.label,
            category: cmd?.category,
            unavailable: enabled ? null : entry.disabledReason ?? '',
          ),
          excludeSemantics: true,
          onTap: onTap,
          child: InkWell(
            onTap: onTap,
            child: Container(
              decoration: BoxDecoration(
                color: c.itemFill(selected: active),
                border: c.itemOutline(selected: active),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: Sp.betweenItems,
                vertical: Sp.iconGap,
              ),
              child: Row(
                children: [
                  const SizedBox(width: Sp.betweenItems),
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
                    const SizedBox(width: Sp.withinGroup),
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
      return AppDialog(
        title: tr.shell.shortcutsTitle,
        width: 560,
        maxHeight: 620,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr.shell.shortcutsNote,
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
                        padding: const EdgeInsets.symmetric(
                          vertical: Sp.withinControl,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(cmd.menuLabel, style: Ty.body),
                            ),
                            if (cmd.shortcutLabel != null)
                              Kbd(cmd.shortcutLabel!)
                            else
                              Text(
                                tr.common.missing,
                                style: Ty.meta.copyWith(color: c.textSecondary),
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
      );
    },
  );
}

// ---- Export dialog -------------------------------------------------------------

Future<void> showExportDialog(BuildContext context, AppState app) async {
  final ws = app.current;
  if (ws == null) return;
  final modes = {...Mode.values.where((m) => m == app.mode)};
  // How many of the newest matches of each mode: a preset, all (0), or the typed number (-1).
  // Everything already read is kept locally, so "all" is the default.
  var choice = 0;
  final custom = TextEditingController(text: '200');
  var ratings = false;
  int? count() {
    if (choice == 0) return null;
    if (choice > 0) return choice;
    return (int.tryParse(custom.text) ?? 0).clamp(1, 5000);
  }

  final go = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final c = context.c;
        final n = count();
        return AppDialog(
          title: tr.shell.exportTitle(ws.name),
          onClose: () => Navigator.of(context).pop(false),
          actions: [
            AppButton(
              tr.common.cancel,
              onPressed: () => Navigator.of(context).pop(false),
            ),
            AppButton(
              tr.shell.startExport,
              primary: true,
              onPressed: modes.isEmpty || (choice == -1 && n == null)
                  ? null
                  : () => Navigator.of(context).pop(true),
              disabledReason: modes.isEmpty
                  ? tr.shell.exportNeedMode
                  : tr.shell.exportNeedCount,
            ),
          ],
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr.shell.exportIntro,
                style: Ty.body.copyWith(color: c.textSecondary),
              ),
              const SizedBox(height: Sp.betweenGroups),
              Text(tr.shell.exportModes, style: Ty.bodyStrong),
              CheckboxListTile(
                dense: true,
                tristate: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(tr.shell.exportAllModes, style: Ty.body),
                value: modes.length == Mode.values.length
                    ? true
                    : modes.isEmpty
                    ? false
                    : null,
                onChanged: (v) => setState(() {
                  if (modes.length == Mode.values.length) {
                    modes.clear();
                  } else {
                    modes.addAll(Mode.values);
                  }
                }),
              ),
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
              Text(tr.shell.exportCount, style: Ty.bodyStrong),
              const SizedBox(height: Sp.withinControl),
              SegmentedBar<int>(
                semanticLabel: tr.shell.exportCountLabel,
                value: choice,
                onChanged: (v) => setState(() => choice = v),
                segments: [
                  Segment(20, tr.common.matchCount(20)),
                  Segment(50, tr.common.matchCount(50)),
                  Segment(100, tr.common.matchCount(100)),
                  Segment(0, tr.shell.exportCountAll),
                  Segment(-1, tr.shell.exportCountCustom),
                ],
              ),
              if (choice == -1) ...[
                const SizedBox(height: Sp.withinControl),
                SizedBox(
                  width: 160,
                  child: TextField(
                    controller: custom,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                    decoration: InputDecoration(
                      labelText: tr.shell.exportCountField,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
              const SizedBox(height: Sp.withinGroup),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(tr.shell.exportRanks, style: Ty.body),
                subtitle: Text(
                  tr.shell.exportRanksNote,
                  style: Ty.meta.copyWith(color: c.textSecondary),
                ),
                value: ratings,
                onChanged: (v) => setState(() => ratings = v == true),
              ),
              const SizedBox(height: Sp.withinGroup),
              Text(
                tr.shell.exportReadNote,
                style: Ty.meta.copyWith(color: c.textSecondary),
              ),
            ],
          ),
        );
      },
    ),
  );
  final chosen = count();
  custom.dispose();
  if (go == true) {
    app.exportDataset(modes: modes.toList(), count: chosen, ratings: ratings);
  }
}
