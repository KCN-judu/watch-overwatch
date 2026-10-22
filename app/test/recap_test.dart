import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_overwatch/core/api.dart';
import 'package:watch_overwatch/core/models.dart';
import 'package:watch_overwatch/core/overview.dart';
import 'package:watch_overwatch/core/share_image.dart';
import 'package:watch_overwatch/core/support.dart';
import 'package:watch_overwatch/design/share.dart';
import 'package:watch_overwatch/design/tokens.dart';
import 'package:watch_overwatch/design/widgets.dart';
import 'package:watch_overwatch/state/app_state.dart';
import 'package:watch_overwatch/ui/pages/recap.dart';

Map<String, Object?> record(int w, int l, {double low = 40}) => {
  'matches': w + l,
  'wins': w,
  'losses': l,
  'draws': 0,
  'win_rate_pct': 100 * w / (w + l),
  'win_rate_low_pct': low,
  'win_rate_high_pct': 80.0,
  'enough': w + l >= 5,
};

Map<String, Object?> group(
  String key,
  String label,
  int w,
  int l,
  double low,
) => {
  'key': key,
  'label': label,
  'aggregate': {'record': record(w, l, low: low)},
};

Overview overview() => Overview({
  'overall': {'record': record(30, 20)},
  'recent': {'record': record(12, 8)},
  'before': {'record': record(10, 10)},
  'windows': [
    {
      'window': 'week',
      'aggregate': {'record': record(5, 2)},
    },
  ],
  'by_hero': [group('h', '安娜', 20, 10, 50)],
  'by_map': [
    group('a', '努巴尼', 8, 4, 40),
    group('b', '伊利奥斯', 9, 2, 55),
    group('c', '国王大道', 5, 5, 25),
  ],
});

void main() {
  testWidgets('the recap goes step by step and the best map is guessed first', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final app = AppState(Backend(), UiState());
    final ws = PlayerWorkspace(app, 'KCN#51896');
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [AppColors.dark]),
        home: AppScope(
          state: app,
          child: Scaffold(
            body: Builder(
              builder: (context) => AppButton(
                'open',
                onPressed: () => showRecap(
                  context,
                  workspace: ws,
                  mode: Mode.competitive,
                  overview: overview(),
                  listed: 50,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('50 场'), findsOneWidget);
    expect(find.textContaining('本周 5 胜 2 负'), findsOneWidget);
    await tester.tap(find.text('下一步'));
    await tester.pump();
    expect(find.text('安娜'), findsOneWidget);
    await tester.tap(find.text('下一步'));
    await tester.pump();
    expect(find.text('?'), findsOneWidget);
    await tester.tap(find.text('努巴尼'));
    await tester.pump();
    // 伊利奥斯 has the best evidence (low end 55).
    expect(find.text('伊利奥斯'), findsOneWidget);
    expect(find.textContaining('不是它'), findsOneWidget);
    await tester.tap(find.widgetWithText(AppButton, '全部显示').first);
    await tester.pump();
    expect(find.byType(Shareable), findsOneWidget);
    expect(find.text('安娜'), findsOneWidget);
  });

  testWidgets('a picture of a boundary is a PNG', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [AppColors.dark]),
        home: Center(
          child: RepaintBoundary(
            key: key,
            child: const SizedBox(width: 40, height: 20, child: Text('图')),
          ),
        ),
      ),
    );
    final bytes = await tester.runAsync(
      () => capturePng(
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary,
        pixelRatio: 1,
      ),
    );
    expect(bytes, isNotNull);
    expect(bytes!.sublist(1, 4), 'PNG'.codeUnits);
  });

  test('names are hidden in pictures when asked', () {
    final app = AppState(Backend(), UiState());
    expect(app.maskName('KCN#51896'), 'KCN#51896');
    app.ui.shareMaskNames = true;
    expect(app.maskName('KCN#51896'), '玩家');
  });
}
