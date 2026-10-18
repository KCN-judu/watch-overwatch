import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';

/// Asks where to save, with the system's save dialog, starting from [suggestedName].
/// Returns the path the user chose (the dialog already asked about overwriting), or null
/// when they cancelled.
typedef SavePicker = Future<String?> Function(String suggestedName);

Future<String?> pickJsonSaveLocation(String suggestedName) async {
  final location = await getSaveLocation(
    suggestedName: suggestedName,
    acceptedTypeGroups: const [
      XTypeGroup(label: 'JSON', extensions: ['json']),
    ],
    confirmButtonText: '保存',
  );
  return location?.path;
}

/// Writes [content] to [path] as indented JSON and returns the size in bytes. It goes to a
/// temporary file beside the target first and is moved into place, so an interrupted write
/// never leaves half a file where the user's file was. Throws [FileSystemException] when
/// the location cannot be written.
Future<int> writeJsonFile(String path, Object? content) async {
  final bytes = utf8.encode(
    '${const JsonEncoder.withIndent('  ').convert(content)}\n',
  );
  final temporary = File('$path.part');
  try {
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(path);
  } catch (_) {
    try {
      await temporary.delete();
    } catch (_) {
      // Nothing was written, or it is already gone.
    }
    rethrow;
  }
  return bytes.length;
}
