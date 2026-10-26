import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:watch_overwatch/core/api.dart';
import 'package:watch_overwatch/core/models.dart';
import 'package:watch_overwatch/core/support.dart';
import 'package:watch_overwatch/state/app_state.dart';

/// Counts lookups; each one waits for [answer] so several callers overlap.
class CountingApi extends Api {
  CountingApi() : super(0);
  int searches = 0;
  Completer<void> answer = Completer();
  bool fail = false;

  @override
  Future<({String session, Json identity})> search(String name) async {
    searches++;
    await answer.future;
    if (fail) throw ApiError('empty', '大神返回成功，但没有数据');
    return (session: 's$searches', identity: <String, dynamic>{'name': name});
  }
}

class FakeBackend extends Backend {
  FakeBackend(this.fake);
  final CountingApi fake;
  @override
  Api get api => fake;
}

void main() {
  test('loads that need a session at the same time share one lookup', () async {
    final api = CountingApi();
    final ws = PlayerWorkspace(AppState(FakeBackend(api), UiState()), 'A#1');
    final waiting = [
      ws.ensureSession(),
      ws.ensureSession(),
      ws.ensureSession(),
    ];
    api.answer.complete();
    expect(await Future.wait(waiting), ['s1', 's1', 's1']);
    expect(api.searches, 1);
    // Once there is a session, no further lookup.
    expect(await ws.ensureSession(), 's1');
    expect(api.searches, 1);
  });

  test(
    'a failed lookup is not kept: the next request looks up again',
    () async {
      final api = CountingApi()..fail = true;
      final ws = PlayerWorkspace(AppState(FakeBackend(api), UiState()), 'A#1');
      final both = [ws.ensureSession(), ws.ensureSession()];
      api.answer.complete();
      for (final f in both) {
        await expectLater(f, throwsA(isA<ApiError>()));
      }
      expect(api.searches, 1);
      api
        ..fail = false
        ..answer = (Completer()..complete());
      expect(await ws.ensureSession(), 's2');
      expect(api.searches, 2);
    },
  );
}
