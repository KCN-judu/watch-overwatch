import 'dart:math' as math;
import 'package:flutter/services.dart';

import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/support.dart';
import '../../design/cards.dart';
import '../../design/data_table.dart';
import '../../design/dialog.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';
import '../../l10n/strings.dart';
import '../../state/app_state.dart';
import '../shell.dart' show ShellScope;
import '../update_dialog.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _name = TextEditingController();
  final _role = TextEditingController();
  final _token = TextEditingController();
  String? _nameError, _roleError, _tokenError;
  ApiError? _saveError;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _role.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _save(AppState app) async {
    final name = _name.text.trim();
    final role = int.tryParse(_role.text.trim());
    final token = _token.text.trim();
    setState(() {
      _nameError = name.isEmpty ? tr.shell.accountNameRequired : null;
      _roleError = role == null || role <= 0 ? tr.shell.roleIdInvalid : null;
      _tokenError = token.isEmpty ? tr.shell.tokenRequired : null;
      _saveError = null;
    });
    if (_nameError != null || _roleError != null || _tokenError != null) return;
    setState(() => _saving = true);
    try {
      await app.api.saveAccount(name, role!, token);
      _name.clear();
      _role.clear();
      _token.clear();
      await app.refreshServer();
      app.toast?.call(tr.shell.accountSaved(name));
    } on ApiError catch (e) {
      setState(() => _saveError = e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// The script that fetches the token on the Dashen site, as ready-to-paste text.
  Future<void> _copyTokenScript(AppState app) async {
    try {
      final script = await rootBundle.loadString('assets/tools/get-token.js');
      await Clipboard.setData(ClipboardData(text: script));
      app.toast?.call(tr.shell.tokenScriptCopied);
    } catch (_) {
      app.toast?.call(tr.shell.tokenScriptCopyFailed);
    }
  }

  Future<void> _remove(AppState app, String name) async {
    final ok = await confirmDanger(
      context,
      title: tr.shell.removeAccountTitle(name),
      body: tr.shell.removeAccountBody,
      keep: tr.shell.keepAccount,
      destroy: tr.shell.removeAccount,
    );
    if (!ok) return;
    try {
      await app.api.removeAccount(name);
      await app.refreshServer();
      app.toast?.call(tr.shell.accountRemoved(name));
    } on ApiError catch (e) {
      app.toast?.call(
        tr.shell.removeAccountFailed(tr.shell.errorSentence(e.kind)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = context.c;
    final scale = math.max(
      1.0,
      MediaQuery.textScalerOf(context).scale(13) / 13,
    );
    final rowH = context.density.rowHeight * scale;
    final accounts = app.accounts;
    final metrics = app.metrics.reversed.take(100).toList();
    final secretsPath = app.server?['secrets_path'] as String?;

    // Forms and short tables read badly stretched across a wide window.
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 940),
        child: Padding(
          padding: const EdgeInsets.all(Sp.betweenGroups),
          child: ListView(
            padding: const EdgeInsets.only(right: scrollGutter),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(tr.shell.settings, style: Ty.page),
                    ),
                  ),
                  AppButton(
                    tr.common.back,
                    icon: Icons.arrow_back,
                    onPressed: () => app.showSettings(false),
                    tooltip: 'Esc',
                  ),
                ],
              ),
              const SizedBox(height: Sp.betweenSections),

              // ---- Accounts
              SectionHeader(tr.shell.dashenAccounts),
              const SizedBox(height: Sp.withinControl),
              Text(
                tr.shell.dashenAccountsNote,
                style: Ty.body.copyWith(color: c.textSecondary),
              ),
              const SizedBox(height: Sp.withinGroup),
              SizedBox(
                height: rowH * (math.max(accounts.length, 1) + 1) + 4,
                child: AppTable<Json>(
                  tableLabel: tr.shell.dashenAccounts,
                  columns: [
                    Col(
                      id: 'name',
                      label: tr.shell.columnName,
                      width: 160,
                      flex: true,
                      cell: (_, a) => Text('${a['name']}'),
                    ),
                    Col(
                      id: 'status',
                      label: tr.shell.columnStatus,
                      width: 220,
                      cell: (_, a) => _AccountStatus(a),
                    ),
                    Col(
                      id: 'remove',
                      label: tr.shell.columnActions,
                      width: 120,
                      cell: (_, a) => AppButton(
                        tr.shell.removeAccount,
                        quiet: true,
                        onPressed: () => _remove(app, '${a['name']}'),
                      ),
                    ),
                  ],
                  rows: accounts,
                  rowLabel: (a) =>
                      tr.shell.accountRow('${a['name']}', _statusText(a)),
                  empty: Center(
                    child: Text(
                      tr.shell.noAccounts,
                      style: Ty.body.copyWith(color: c.textSecondary),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: Sp.betweenGroups),
              Text(tr.shell.addOrUpdateAccount, style: Ty.bodyStrong),
              Text(
                tr.shell.addOrUpdateNote,
                style: Ty.meta.copyWith(color: c.textSecondary),
              ),
              const SizedBox(height: Sp.withinGroup),
              Wrap(
                spacing: Sp.withinGroup,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  AppButton(
                    tr.shell.copyTokenScript,
                    icon: Icons.content_copy,
                    onPressed: () => _copyTokenScript(app),
                  ),
                  Text(
                    tr.shell.copyTokenScriptNote,
                    style: Ty.meta.copyWith(color: c.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: Sp.withinGroup),
              Wrap(
                spacing: Sp.withinGroup,
                runSpacing: Sp.withinGroup,
                crossAxisAlignment: WrapCrossAlignment.start,
                children: [
                  SizedBox(
                    width: 180,
                    child: _field(_name, tr.shell.columnName, _nameError),
                  ),
                  SizedBox(
                    width: 180,
                    child: _field(_role, 'role_id', _roleError, number: true),
                  ),
                  SizedBox(
                    width: 340,
                    child: _field(_token, 'token', _tokenError, obscure: true),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 0),
                    child: AppButton(
                      _saving ? tr.shell.saving : tr.shell.saveAccount,
                      primary: true,
                      onPressed: _saving ? null : () => _save(app),
                    ),
                  ),
                ],
              ),
              if (_saveError != null)
                Padding(
                  padding: const EdgeInsets.only(top: Sp.withinGroup),
                  child: Text(
                    tr.shell.saveFailed(
                      tr.shell.errorSentence(_saveError!.kind),
                    ),
                    style: Ty.body.copyWith(color: c.error),
                  ),
                ),

              // ---- Appearance
              const SizedBox(height: Sp.betweenSections),
              SectionHeader(tr.shell.appearance),
              const SizedBox(height: Sp.withinGroup),
              _row(
                tr.shell.theme,
                SegmentedBar<ThemeMode>(
                  semanticLabel: tr.shell.theme,
                  value: app.themeMode,
                  onChanged: app.setTheme,
                  segments: [
                    Segment(ThemeMode.system, tr.shell.themeSystem),
                    Segment(ThemeMode.light, tr.shell.themeLight),
                    Segment(ThemeMode.dark, tr.shell.themeDark),
                  ],
                ),
              ),
              _row(
                tr.shell.rowHeight,
                SegmentedBar<DensityMode>(
                  semanticLabel: tr.shell.rowHeight,
                  value: app.density,
                  onChanged: app.setDensity,
                  segments: [
                    for (final d in DensityMode.values)
                      Segment(d, d.label, hint: '${d.rowHeight.round()} px'),
                  ],
                ),
              ),
              _row(
                tr.recap.maskNames,
                SegmentedBar<bool>(
                  semanticLabel: tr.recap.maskNames,
                  value: app.maskNames,
                  onChanged: app.setMaskNames,
                  segments: [
                    Segment(false, tr.recap.namesShown),
                    Segment(
                      true,
                      tr.recap.namesHidden,
                      hint: tr.recap.maskNamesTip,
                    ),
                  ],
                ),
              ),
              _row(
                tr.shell.layout,
                AppButton(
                  tr.shell.resetLayout,
                  onPressed: () {
                    app.setNav(width: 248, collapsed: false);
                    app.setDensity(DensityMode.standard);
                  },
                ),
              ),

              // ---- Data
              const SizedBox(height: Sp.betweenSections),
              SectionHeader(tr.shell.dataAndBackend),
              const SizedBox(height: SectionHeader.below),
              _info(tr.shell.credentialsPath, secretsPath ?? missing),
              _info(
                tr.shell.lastExportLabel,
                app.lastExportPath ?? tr.shell.noExportYet,
              ),
              _cacheRow(app),
              _info(
                tr.shell.backend,
                '${app.backend.api.base}${app.backend.binaryPath == null ? '' : '  ·  ${app.backend.binaryPath}'}',
              ),
              const SizedBox(height: Sp.withinGroup),
              Align(
                alignment: Alignment.centerLeft,
                child: AppButton(
                  tr.shell.shortcuts,
                  icon: Icons.keyboard_outlined,
                  tooltip: 'F1',
                  onPressed: ShellScope.of(context).actions.openShortcuts,
                ),
              ),

              // ---- Updates
              const SizedBox(height: Sp.betweenSections),
              SectionHeader(tr.update.title),
              const SizedBox(height: Sp.withinGroup),
              _row(
                tr.update.version,
                Row(
                  children: [
                    Text(
                      '${app.server?['version'] ?? app.update?.current ?? missing}',
                      style: Ty.num(Ty.bodyStrong),
                    ),
                    const SizedBox(width: Sp.betweenItems),
                    if (app.update case final u?
                        when u.newer && u.latest != null)
                      AppButton(
                        tr.update.newVersion(u.latest!.version),
                        icon: Icons.system_update_alt,
                        primary: true,
                        onPressed: () => showUpdateDialog(context),
                      )
                    else
                      AppButton(
                        tr.update.check,
                        onPressed: () => showUpdateDialog(context, check: true),
                      ),
                  ],
                ),
              ),
              _row(
                tr.update.autoCheck,
                SegmentedBar<bool>(
                  semanticLabel: tr.update.autoCheck,
                  value: app.autoCheckUpdates,
                  onChanged: app.setAutoCheckUpdates,
                  segments: [
                    Segment(true, tr.update.autoOn, hint: tr.update.privacy),
                    Segment(false, tr.update.autoOff),
                  ],
                ),
              ),

              // ---- Request log
              const SizedBox(height: Sp.betweenSections),
              SectionHeader(tr.shell.requestLog),
              const SizedBox(height: Sp.withinControl),
              Text(
                tr.shell.requestLogNote(metrics.length),
                style: Ty.meta.copyWith(color: c.textSecondary),
              ),
              const SizedBox(height: Sp.withinGroup),
              SizedBox(
                height:
                    rowH * (math.min(math.max(metrics.length, 2), 12) + 1) + 4,
                child: AppTable<Json>(
                  tableLabel: tr.shell.requestLog,
                  columns: [
                    Col(
                      id: 'at',
                      label: tr.shell.columnTime,
                      width: 96,
                      cell: (_, m) =>
                          Text(fmtDateTime((m['at_ms'] as num?)?.toInt())),
                    ),
                    Col(
                      id: 'ep',
                      label: tr.shell.columnEndpoint,
                      width: 220,
                      flex: true,
                      cell: (_, m) => Text('${m['endpoint']}'),
                    ),
                    Col(
                      id: 'st',
                      label: tr.shell.columnResult,
                      width: 110,
                      cell: (_, m) => _MetricStatus('${m['status']}'),
                    ),
                    Col(
                      id: 'code',
                      label: tr.shell.columnStatusCode,
                      width: 72,
                      numeric: true,
                      cell: (_, m) => Text('${m['status_code'] ?? missing}'),
                    ),
                    Col(
                      id: 'q',
                      label: tr.shell.columnQueueMs,
                      width: 80,
                      numeric: true,
                      cell: (_, m) => Text(fmtInt(m['queue_ms'] as num?)),
                    ),
                    Col(
                      id: 'd',
                      label: tr.shell.columnDurationMs,
                      width: 80,
                      numeric: true,
                      cell: (_, m) => Text(fmtInt(m['duration_ms'] as num?)),
                    ),
                    Col(
                      id: 'a',
                      label: tr.shell.columnAttempts,
                      width: 56,
                      numeric: true,
                      cell: (_, m) => Text(fmtInt(m['attempts'] as num?)),
                    ),
                  ],
                  rows: metrics,
                  rowLabel: (m) => tr.shell.requestRow(
                    '${m['endpoint']}',
                    '${m['status']}',
                    fmtInt(m['duration_ms'] as num?),
                  ),
                  empty: Center(
                    child: Text(
                      tr.shell.noRequests,
                      style: Ty.body.copyWith(color: c.textSecondary),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: Sp.betweenSections),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController ctl,
    String label,
    String? error, {
    bool obscure = false,
    bool number = false,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: Sp.withinControl),
        child: Text(
          label,
          style: Ty.meta.copyWith(color: context.c.textSecondary),
        ),
      ),
      Semantics(
        label: label,
        textField: true,
        child: TextField(
          controller: ctl,
          obscureText: obscure,
          enableSuggestions: false,
          autocorrect: false,
          keyboardType: number ? TextInputType.number : TextInputType.text,
          decoration: InputDecoration(
            errorText: error,
            errorStyle: Ty.meta.copyWith(color: context.c.error),
          ),
        ),
      ),
    ],
  );

  Widget _row(String label, Widget control) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Sp.withinControl),
    child: Row(
      children: [
        SizedBox(
          width: 140,
          child: Text(
            label,
            style: Ty.body.copyWith(color: context.c.textSecondary),
          ),
        ),
        control,
      ],
    ),
  );

  /// What the strength cache holds, with a button to empty it.
  Widget _cacheRow(AppState app) {
    final s = app.cacheStats;
    final bytes = (s?['bytes'] as num?)?.toInt() ?? 0;
    final size = fmtBytes(bytes);
    final text = s == null
        ? tr.shell.unavailable
        : tr.shell.cacheStats(
            s['listed'],
            s['matches'],
            s['participants'],
            s['players'],
            size,
          );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Sp.withinControl),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              tr.shell.localCache,
              style: Ty.body.copyWith(color: context.c.textSecondary),
            ),
          ),
          Flexible(child: Text(text, style: Ty.body)),
          const SizedBox(width: Sp.withinGroup),
          AppButton(
            tr.shell.clearCache,
            quiet: true,
            onPressed: s == null ? null : app.clearStrengthCache,
          ),
        ],
      ),
    );
  }

  Widget _info(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Sp.withinControl),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(
            label,
            style: Ty.body.copyWith(color: context.c.textSecondary),
          ),
        ),
        Expanded(child: SelectableText(value, style: Ty.body)),
      ],
    ),
  );
}

String _statusText(Json a) => switch (a['status']) {
  'ready' => tr.shell.accountReady,
  'cooldown' => tr.shell.accountCooldown(
    ((a['cooldown_ms'] as num? ?? 0) / 1000).ceil(),
  ),
  'expired' => tr.shell.accountExpired,
  _ => tr.shell.accountUnknown,
};

class _AccountStatus extends StatelessWidget {
  const _AccountStatus(this.a);
  final Json a;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final (icon, color) = switch (a['status']) {
      'ready' => (Icons.check_rounded, c.success),
      'cooldown' => (Icons.schedule, c.warning),
      _ => (Icons.error_outline, c.error),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: Sp.withinControl),
        Flexible(child: Text(_statusText(a), overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}

class _MetricStatus extends StatelessWidget {
  const _MetricStatus(this.status);
  final String status;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final ok = status == 'ok';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          ok ? Icons.check_rounded : Icons.close_rounded,
          size: 14,
          color: ok ? c.success : c.error,
        ),
        const SizedBox(width: Sp.withinControl),
        Text(ok ? tr.shell.requestOk : status),
      ],
    );
  }
}
