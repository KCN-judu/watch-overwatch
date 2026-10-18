import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:watch_overwatch/core/export_file.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('wo-export-'));
  tearDown(() => dir.deleteSync(recursive: true));

  test(
    'writes indented JSON to exactly the chosen path, leaving no temporary file',
    () async {
      final path = '${dir.path}${Platform.pathSeparator}我的 数据.json';
      final size = await writeJsonFile(path, {'hero': '安娜', 'n': 1});
      final text = File(path).readAsStringSync();
      expect(jsonDecode(text), {'hero': '安娜', 'n': 1});
      expect(text.endsWith('\n'), isTrue);
      expect(text.contains('\n  "hero"'), isTrue, reason: 'indented');
      expect(File(path).lengthSync(), size);
      expect(dir.listSync().map((e) => e.path), [path]);
    },
  );

  test('replaces an existing file the user agreed to overwrite', () async {
    final path = '${dir.path}${Platform.pathSeparator}a.json';
    File(path).writeAsStringSync('old');
    await writeJsonFile(path, {'v': 2});
    expect(jsonDecode(File(path).readAsStringSync()), {'v': 2});
  });

  test(
    'a location that cannot be written throws and leaves nothing behind',
    () async {
      final path =
          '${dir.path}${Platform.pathSeparator}missing${Platform.pathSeparator}a.json';
      await expectLater(
        writeJsonFile(path, {}),
        throwsA(isA<FileSystemException>()),
      );
      expect(dir.listSync(), isEmpty);
    },
  );
}
