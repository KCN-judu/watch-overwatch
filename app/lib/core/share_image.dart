import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/rendering.dart';

import '../l10n/strings.dart';

/// Renders the boundary behind [key]'s render object as PNG bytes, at [pixelRatio]
/// device pixels per logical pixel (2 keeps text sharp when the image is scaled down).
Future<Uint8List?> capturePng(
  RenderRepaintBoundary boundary, {
  double pixelRatio = 2,
}) async {
  final image = await boundary.toImage(pixelRatio: pixelRatio);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// Asks where to save a picture, starting from [suggestedName].
Future<String?> pickPngSaveLocation(String suggestedName) async {
  final location = await getSaveLocation(
    suggestedName: suggestedName,
    acceptedTypeGroups: const [
      XTypeGroup(label: 'PNG', extensions: ['png']),
    ],
    confirmButtonText: tr.core.save,
  );
  return location?.path;
}

/// Writes [bytes] beside [path] and moves them into place, like the JSON export.
Future<void> writePng(String path, Uint8List bytes) async {
  final part = File('$path.part');
  await part.writeAsBytes(bytes, flush: true);
  await part.rename(path);
}

/// Puts the picture on the Windows clipboard. Flutter's clipboard holds text only, so the
/// picture goes through a temporary file and the system's own image clipboard
/// (PowerShell, Windows Forms). Returns false when that is not available.
Future<bool> copyPngToClipboard(Uint8List bytes) async {
  if (!Platform.isWindows) return false;
  final dir = await Directory.systemTemp.createTemp('watch-overwatch-share');
  final file = File('${dir.path}${Platform.pathSeparator}card.png');
  try {
    await file.writeAsBytes(bytes, flush: true);
    final path = file.path.replaceAll("'", "''");
    final r = await Process.run('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-STA',
      '-Command',
      'Add-Type -AssemblyName System.Windows.Forms; '
          'Add-Type -AssemblyName System.Drawing; '
          "\$img = [System.Drawing.Image]::FromFile('$path'); "
          '[System.Windows.Forms.Clipboard]::SetImage(\$img); '
          '\$img.Dispose()',
    ]);
    return r.exitCode == 0;
  } catch (_) {
    return false;
  } finally {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  }
}
