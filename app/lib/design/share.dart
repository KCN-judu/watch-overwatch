import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../core/metric_doc.dart';
import '../core/share_image.dart';
import '../l10n/strings.dart';
import '../state/app_state.dart';
import 'cards.dart';
import 'tokens.dart';
import 'widgets.dart';

/// A titled block that can be copied or saved as a picture. The picture is the block on
/// the page's own background, with a line under it that says what the figures are worked
/// out from and when ([caption]), and the app's name; never a credential.
class Shareable extends StatefulWidget {
  const Shareable({
    super.key,
    required this.title,
    required this.caption,
    required this.fileName,
    required this.child,
    this.info,
    this.infoDoc,
    this.accent,
    this.trailing,
  });
  final String title;
  final String? info;
  final MetricDoc? infoDoc;
  final Color? accent;

  /// Shown before the share actions in the heading row.
  final Widget? trailing;

  /// What the figures are worked out from, for the picture's footer.
  final String caption;

  /// Suggested file name, without extension.
  final String fileName;
  final Widget child;

  @override
  State<Shareable> createState() => _ShareableState();
}

class _ShareableState extends State<Shareable> {
  final _boundary = GlobalKey();

  /// While a picture is taken: the footer shows and the actions hide.
  bool _capturing = false;

  Future<dynamic> _png() async {
    setState(() => _capturing = true);
    await WidgetsBinding.instance.endOfFrame;
    try {
      final box = _boundary.currentContext?.findRenderObject();
      return box is RenderRepaintBoundary ? await capturePng(box) : null;
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _copy() async {
    final app = AppScope.read(context);
    final bytes = await _png();
    if (bytes == null) return;
    final ok = await copyPngToClipboard(bytes);
    app.toast?.call(ok ? tr.recap.shareCopied : tr.recap.shareCopyFailed);
  }

  Future<void> _save() async {
    final app = AppScope.read(context);
    final path = await pickPngSaveLocation('${widget.fileName}.png');
    if (path == null) return;
    final bytes = await _png();
    if (bytes == null) return;
    try {
      await writePng(path, bytes);
      app.toast?.call(tr.recap.shareSaved(path));
    } catch (e) {
      app.toast?.call(tr.recap.shareSaveFailed('$e'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ?widget.trailing,
        IconAction(
          icon: Icons.content_copy_sharp,
          label: tr.recap.shareCopy,
          onPressed: _capturing ? null : _copy,
        ),
        IconAction(
          icon: Icons.image_sharp,
          label: tr.recap.shareSave,
          onPressed: _capturing ? null : _save,
        ),
      ],
    );
    return RepaintBoundary(
      key: _boundary,
      child: Container(
        color: _capturing ? c.window : null,
        padding: _capturing ? const EdgeInsets.all(Sp.betweenGroups) : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              widget.title,
              info: _capturing ? null : widget.info,
              infoDoc: widget.infoDoc,
              accent: widget.accent,
              trailing: _capturing ? null : actions,
            ),
            const SizedBox(height: SectionHeader.below),
            widget.child,
            if (_capturing) ...[
              const SizedBox(height: Sp.withinGroup),
              Text(
                tr.recap.shareFooter(widget.caption),
                style: Ty.meta.copyWith(color: c.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
