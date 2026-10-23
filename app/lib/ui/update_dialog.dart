import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/support.dart';
import '../design/dialog.dart';
import '../design/tokens.dart';
import '../design/widgets.dart';
import '../l10n/strings.dart';
import '../state/app_state.dart';

/// The update dialog: whether a newer version is out, what changed in it, its download
/// and the restart that installs it. [check] asks GitHub again on opening (the menu's
/// 检查更新); from the status bar the answer already in hand is shown.
Future<void> showUpdateDialog(BuildContext context, {bool check = false}) =>
    showDialog<void>(
      context: context,
      builder: (_) => _UpdateDialog(check: check),
    );

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.check});
  final bool check;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _checking = false;
  bool _restarting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final app = AppScope.read(context);
    if (widget.check || app.update == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    }
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      await AppScope.read(context).checkUpdate(force: true);
    } on ApiError {
      _error = tr.update.checkFailed;
    }
    if (mounted) setState(() => _checking = false);
  }

  Future<void> _restart(AppState app) async {
    setState(() => _restarting = true);
    try {
      await app.applyUpdate();
    } on ApiError catch (e) {
      if (mounted) {
        setState(() {
          _restarting = false;
          _error = tr.update.failed(e.message);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = context.c;
    final info = app.update;
    final release = info?.latest;
    final d = app.updateDownload;
    final newer = info != null && info.newer && release != null;
    final meta = Ty.meta.copyWith(color: c.textSecondary);

    final Widget body;
    if (_checking) {
      body = Row(
        children: [
          const Spinner(),
          const SizedBox(width: Sp.withinGroup),
          Text(tr.update.checking, style: Ty.body),
        ],
      );
    } else if (_error != null && !newer) {
      body = Text(_error!, style: Ty.body.copyWith(color: c.error));
    } else if (!newer) {
      body = Row(
        children: [
          Icon(Icons.check_circle_outline, color: c.success, size: 20),
          const SizedBox(width: Sp.withinGroup),
          Text(tr.update.upToDate(info?.current ?? ''), style: Ty.bodyStrong),
        ],
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr.update.available(release.version, info.current),
            style: Ty.title,
          ),
          const SizedBox(height: Sp.withinControl),
          Text(
            [
              if (release.publishedAt != null)
                tr.update.published(
                  fmtDate(release.publishedAt!.millisecondsSinceEpoch),
                ),
              if (release.zipSize > 0) fmtBytes(release.zipSize),
            ].join(' · '),
            style: meta,
          ),
          const SizedBox(height: Sp.betweenGroups),
          Text(tr.update.notesTitle, style: Ty.bodyStrong),
          const SizedBox(height: Sp.withinControl),
          Flexible(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(Sp.betweenItems),
              decoration: BoxDecoration(
                color: c.raised,
                border: Border.all(color: c.border),
              ),
              child: SingleChildScrollView(child: _Notes(release.notes)),
            ),
          ),
          const SizedBox(height: Sp.betweenGroups),
          if (!info.installable)
            Text(tr.update.devBuild, style: meta)
          else if (d != null && d.busy) ...[
            ProgressLine(value: d.share ?? 0),
            const SizedBox(height: Sp.withinControl),
            Text(
              d.state == 'verifying'
                  ? tr.update.verifying
                  : tr.update.downloading(
                      fmtBytes(d.received),
                      fmtBytes(d.total),
                    ),
              style: Ty.num(Ty.meta).copyWith(color: c.textSecondary),
            ),
          ] else if (d != null && d.ready)
            Text(tr.update.ready, style: Ty.body.copyWith(color: c.success))
          else if (d != null && d.failed)
            Text(
              tr.update.failed(d.error ?? ''),
              style: Ty.body.copyWith(color: c.error),
            ),
          if (_error != null)
            Text(_error!, style: Ty.body.copyWith(color: c.error)),
        ],
      );
    }

    final ready = d != null && d.ready && d.version == release?.version;
    return AppDialog(
      title: tr.update.title,
      width: 600,
      actions: [
        if (newer && release.pageUrl != null)
          AppButton(
            tr.update.openPage,
            quiet: true,
            onPressed: () => openUrl(release.pageUrl!),
          ),
        if (!newer && !_checking) AppButton(tr.update.check, onPressed: _check),
        if (newer)
          AppButton(
            tr.update.later,
            onPressed: () => Navigator.of(context).pop(),
          ),
        if (newer && info.installable)
          ready
              ? AppButton(
                  tr.update.restart,
                  primary: true,
                  autofocus: true,
                  onPressed: _restarting ? null : () => _restart(app),
                )
              : AppButton(
                  d != null && d.failed ? tr.update.retry : tr.update.download,
                  primary: true,
                  onPressed: d != null && d.busy
                      ? null
                      : app.startUpdateDownload,
                ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 460),
            child: body,
          ),
          const SizedBox(height: Sp.betweenGroups),
          Text(tr.update.privacy, style: meta),
        ],
      ),
    );
  }
}

/// Release notes in Markdown, drawn plainly: headings bold, list items with a dot,
/// emphasis and links reduced to their text.
class _Notes extends StatelessWidget {
  const _Notes(this.text);
  final String text;

  static String _plain(String s) => s
      .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]+\)'), (m) => m[1]!)
      .replaceAllMapped(RegExp(r'<(https?://[^>]+)>'), (m) => m[1]!)
      .replaceAll(RegExp(r'\*\*|__|`'), '');

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final lines = text.replaceAll('\r', '').split('\n');
    if (lines.every((l) => l.trim().isEmpty)) {
      return Text(
        tr.update.noNotes,
        style: Ty.body.copyWith(color: c.textSecondary),
      );
    }
    final out = <Widget>[];
    for (final raw in lines) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        if (out.isNotEmpty) out.add(const SizedBox(height: Sp.withinControl));
        continue;
      }
      final heading = RegExp(r'^#{1,6}\s+(.*)$').firstMatch(line);
      final item = RegExp(r'^(\s*)[-*]\s+(.*)$').firstMatch(line);
      if (heading != null) {
        out.add(
          Padding(
            padding: const EdgeInsets.only(top: Sp.withinGroup),
            child: Text(_plain(heading[1]!), style: Ty.bodyStrong),
          ),
        );
      } else if (item != null) {
        final indent = item[1]!.length >= 2 ? Sp.betweenGroups : 0.0;
        out.add(
          Padding(
            padding: EdgeInsets.only(left: indent, top: Sp.hairline),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('·  ', style: Ty.body.copyWith(color: c.textSecondary)),
                Expanded(child: Text(_plain(item[2]!), style: Ty.body)),
              ],
            ),
          ),
        );
      } else {
        out.add(Text(_plain(line.trim()), style: Ty.body));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: out);
  }
}
