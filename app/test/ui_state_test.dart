import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:watch_overwatch/core/api.dart';
import 'package:watch_overwatch/core/support.dart';
import 'package:watch_overwatch/state/app_state.dart';

void main() {
  test("a test run leaves the user's saved layout alone", () async {
    final base = Platform.environment['LOCALAPPDATA'];
    final file = base == null
        ? null
        : File(
            '$base${Platform.pathSeparator}Watch Overwatch'
            '${Platform.pathSeparator}ui-state.json',
          );
    final before = file != null && file.existsSync()
        ? file.readAsStringSync()
        : null;
    final app = AppState(Backend(), UiState());
    await app.setTab('matches');
    app.setMaskNames(true);
    final after = file != null && file.existsSync()
        ? file.readAsStringSync()
        : null;
    expect(after, before);
    expect(UiState.load().tab, 'overview');
  });
}
