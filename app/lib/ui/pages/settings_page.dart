import 'dart:math' as math;
import 'package:flutter/services.dart';

import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/support.dart';
import '../../design/data_table.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';
import '../../state/app_state.dart';
import '../shell.dart' show ShellScope;

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
      _nameError = name.isEmpty ? '填写一个账号名称，用来在列表里区分。' : null;
      _roleError = role == null || role <= 0 ? 'role_id 是一串数字。' : null;
      _tokenError = token.isEmpty ? '粘贴 token。' : null;
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
      app.toast?.call('已保存账号 $name');
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
      app.toast?.call('已复制获取脚本。到 ds.163.com 的控制台粘贴运行。');
    } catch (_) {
      app.toast?.call('无法复制脚本，请看 docs/credentials.md。');
    }
  }

  Future<void> _remove(AppState app, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('移除账号“$name”？', style: Ty.section),
        content: SizedBox(
          width: 420,
          child: Text(
            '这会删除本机保存的该账号的 role_id 和 token。token 不会再显示，需要重新添加时必须再次粘贴。',
            style: Ty.body,
          ),
        ),
        actions: [
          // Safe action first and focused; the destructive verb names the destruction.
          AppButton('保留账号', onPressed: () => Navigator.of(context).pop(false)),
          AppButton(
            '移除账号',
            primary: true,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await app.api.removeAccount(name);
      await app.refreshServer();
      app.toast?.call('已移除账号 $name');
    } on ApiError catch (e) {
      app.toast?.call('无法移除账号：${e.message}');
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
            padding: const EdgeInsets.only(right: 12),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text('设置', style: Ty.page),
                    ),
                  ),
                  AppButton(
                    '返回',
                    icon: Icons.arrow_back,
                    onPressed: () => app.showSettings(false),
                    tooltip: 'Esc',
                  ),
                ],
              ),
              const SizedBox(height: Sp.betweenSections),

              // ---- Accounts
              Semantics(header: true, child: Text('大神账号', style: Ty.section)),
              const SizedBox(height: 4),
              Text(
                '查询需要至少一个大神账号。凭据只存在本机，多个账号轮流使用。',
                style: Ty.body.copyWith(color: c.textSecondary),
              ),
              const SizedBox(height: Sp.withinGroup),
              SizedBox(
                height: rowH * (math.max(accounts.length, 1) + 1) + 4,
                child: AppTable<Json>(
                  tableLabel: '大神账号',
                  columns: [
                    Col(
                      id: 'name',
                      label: '名称',
                      width: 160,
                      flex: true,
                      cell: (_, a) => Text('${a['name']}'),
                    ),
                    Col(
                      id: 'status',
                      label: '状态',
                      width: 220,
                      cell: (_, a) => _AccountStatus(a),
                    ),
                    Col(
                      id: 'remove',
                      label: '操作',
                      width: 120,
                      cell: (_, a) => AppButton(
                        '移除账号',
                        quiet: true,
                        onPressed: () => _remove(app, '${a['name']}'),
                      ),
                    ),
                  ],
                  rows: accounts,
                  rowLabel: (a) => '账号 ${a['name']}，${_statusText(a)}',
                  empty: Center(
                    child: Text(
                      '还没有账号。在下面添加第一个。',
                      style: Ty.body.copyWith(color: c.textSecondary),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: Sp.betweenGroups),
              Text('添加或更新账号', style: Ty.bodyStrong),
              Text(
                '名称相同会更新已有账号。token 留空不会保留旧值，请重新粘贴。',
                style: Ty.meta.copyWith(color: c.textSecondary),
              ),
              const SizedBox(height: Sp.withinGroup),
              Wrap(
                spacing: Sp.withinGroup,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  AppButton(
                    '复制获取脚本',
                    icon: Icons.content_copy,
                    onPressed: () => _copyTokenScript(app),
                  ),
                  Text(
                    '登录 ds.163.com，按 F12 打开控制台，粘贴运行；token 会自动复制到剪贴板。',
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
                  SizedBox(width: 180, child: _field(_name, '名称', _nameError)),
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
                      _saving ? '正在保存…' : '保存账号',
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
                    '无法保存：${_saveError!.message}',
                    style: Ty.body.copyWith(color: c.error),
                  ),
                ),

              // ---- Appearance
              const SizedBox(height: Sp.betweenSections),
              Semantics(header: true, child: Text('外观', style: Ty.section)),
              const SizedBox(height: Sp.withinGroup),
              _row(
                '主题',
                SegmentedBar<ThemeMode>(
                  semanticLabel: '主题',
                  value: app.themeMode,
                  onChanged: app.setTheme,
                  segments: const [
                    Segment(ThemeMode.system, '跟随系统'),
                    Segment(ThemeMode.light, '浅色'),
                    Segment(ThemeMode.dark, '深色'),
                  ],
                ),
              ),
              _row(
                '表格行高',
                SegmentedBar<DensityMode>(
                  semanticLabel: '表格行高',
                  value: app.density,
                  onChanged: app.setDensity,
                  segments: [
                    for (final d in DensityMode.values)
                      Segment(d, d.label, hint: '${d.rowHeight.round()} px'),
                  ],
                ),
              ),
              _row(
                '界面布局',
                AppButton(
                  '重置界面布局',
                  onPressed: () {
                    app.setNav(width: 248, collapsed: false);
                    app.setDensity(DensityMode.standard);
                  },
                ),
              ),

              // ---- Data
              const SizedBox(height: Sp.betweenSections),
              Semantics(
                header: true,
                child: Text('数据与本地服务', style: Ty.section),
              ),
              const SizedBox(height: Sp.withinGroup),
              _info('账号凭据位置', secretsPath ?? missing),
              _info(
                '导出文件夹',
                secretsPath == null
                    ? missing
                    : '${secretsPath.substring(0, math.max(0, secretsPath.lastIndexOf(RegExp(r'[\\/]'))))}\\exports',
              ),
              _info('最近导出', app.lastExportPath ?? '还没有导出'),
              _cacheRow(app),
              _info(
                '本地服务',
                '${app.backend.api.base}${app.backend.binaryPath == null ? '' : '  ·  ${app.backend.binaryPath}'}',
              ),
              const SizedBox(height: Sp.withinGroup),
              Align(
                alignment: Alignment.centerLeft,
                child: AppButton(
                  '快捷键参考',
                  icon: Icons.keyboard_outlined,
                  tooltip: 'F1',
                  onPressed: ShellScope.of(context).actions.openShortcuts,
                ),
              ),

              // ---- Request log
              const SizedBox(height: Sp.betweenSections),
              Semantics(header: true, child: Text('请求记录', style: Ty.section)),
              const SizedBox(height: 4),
              Text(
                '最近 ${metrics.length} 次对大神的请求。不含 token 或参数。',
                style: Ty.meta.copyWith(color: c.textSecondary),
              ),
              const SizedBox(height: Sp.withinGroup),
              SizedBox(
                height:
                    rowH * (math.min(math.max(metrics.length, 2), 12) + 1) + 4,
                child: AppTable<Json>(
                  tableLabel: '请求记录',
                  columns: [
                    Col(
                      id: 'at',
                      label: '时间',
                      width: 96,
                      cell: (_, m) =>
                          Text(fmtDateTime((m['at_ms'] as num?)?.toInt())),
                    ),
                    Col(
                      id: 'ep',
                      label: '接口',
                      width: 220,
                      flex: true,
                      cell: (_, m) => Text('${m['endpoint']}'),
                    ),
                    Col(
                      id: 'st',
                      label: '结果',
                      width: 110,
                      cell: (_, m) => _MetricStatus('${m['status']}'),
                    ),
                    Col(
                      id: 'code',
                      label: '状态码',
                      width: 72,
                      numeric: true,
                      cell: (_, m) => Text('${m['status_code'] ?? missing}'),
                    ),
                    Col(
                      id: 'q',
                      label: '排队 ms',
                      width: 80,
                      numeric: true,
                      cell: (_, m) => Text(fmtInt(m['queue_ms'] as num?)),
                    ),
                    Col(
                      id: 'd',
                      label: '耗时 ms',
                      width: 80,
                      numeric: true,
                      cell: (_, m) => Text(fmtInt(m['duration_ms'] as num?)),
                    ),
                    Col(
                      id: 'a',
                      label: '尝试',
                      width: 56,
                      numeric: true,
                      cell: (_, m) => Text(fmtInt(m['attempts'] as num?)),
                    ),
                  ],
                  rows: metrics,
                  rowLabel: (m) =>
                      '${m['endpoint']}，${m['status']}，耗时 ${fmtInt(m['duration_ms'] as num?)} 毫秒',
                  empty: Center(
                    child: Text(
                      '还没有请求。',
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
        padding: const EdgeInsets.only(bottom: 4),
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
    padding: const EdgeInsets.symmetric(vertical: 4),
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
    final size = bytes >= 1048576
        ? '${(bytes / 1048576).toStringAsFixed(1)} MB'
        : '${(bytes / 1024).round()} KB';
    final text = s == null
        ? '不可用'
        : '${s['matches']} 场对局、${s['players']} 名玩家，$size';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              '强度缓存',
              style: Ty.body.copyWith(color: context.c.textSecondary),
            ),
          ),
          Flexible(child: Text(text, style: Ty.body)),
          const SizedBox(width: Sp.withinGroup),
          AppButton(
            '清除缓存',
            quiet: true,
            onPressed: s == null ? null : app.clearStrengthCache,
          ),
        ],
      ),
    );
  }

  Widget _info(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
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
  'ready' => '可用',
  'cooldown' => '冷却中，约 ${((a['cooldown_ms'] as num? ?? 0) / 1000).ceil()} 秒后恢复',
  'expired' => 'token 已失效，需要更新',
  _ => '未知',
};

class _AccountStatus extends StatelessWidget {
  const _AccountStatus(this.a);
  final Json a;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final (icon, color) = switch (a['status']) {
      'ready' => (Icons.check_rounded, c.win),
      'cooldown' => (Icons.schedule, c.warning),
      _ => (Icons.error_outline, c.error),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
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
          color: ok ? c.win : c.error,
        ),
        const SizedBox(width: 4),
        Text(ok ? '成功' : status),
      ],
    );
  }
}
