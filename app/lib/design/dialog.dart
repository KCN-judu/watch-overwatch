import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import 'tokens.dart';
import 'widgets.dart';

/// Every dialog's frame: the title with a close button in its row, the body, and the
/// actions at the bottom right — the safe one first, the main (or destructive) one last.
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
    this.width = 520,
    this.maxHeight,
    this.onClose,
  });
  final String title;
  final Widget child;
  final List<Widget> actions;
  final double width;

  /// When set, the body fills up to this height (scrolling lists, the recap).
  final double? maxHeight;

  /// Defaults to closing the dialog with no result.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final close = onClose ?? () => Navigator.of(context).pop();
    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: width,
          maxHeight: maxHeight ?? double.infinity,
        ),
        child: Padding(
          padding: const EdgeInsets.all(Sp.betweenSections),
          child: Column(
            mainAxisSize: maxHeight == null
                ? MainAxisSize.min
                : MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text(title, style: Ty.section)),
                  IconAction(
                    icon: Icons.close,
                    label: tr.common.close,
                    onPressed: close,
                  ),
                ],
              ),
              const SizedBox(height: Sp.withinGroup),
              if (maxHeight == null) child else Expanded(child: child),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: Sp.betweenGroups),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    for (final (i, a) in actions.indexed) ...[
                      if (i > 0) const SizedBox(width: Sp.withinGroup),
                      a,
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks before something that cannot be taken back. The safe answer is first and has
/// the focus; the destructive one names what it destroys and is drawn as dangerous.
Future<bool> confirmDanger(
  BuildContext context, {
  required String title,
  required String body,
  required String keep,
  required String destroy,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AppDialog(
      title: title,
      width: 460,
      onClose: () => Navigator.of(context).pop(false),
      actions: [
        AppButton(
          keep,
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppButton(
          destroy,
          danger: true,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
      child: Text(body, style: Ty.body),
    ),
  );
  return ok == true;
}
