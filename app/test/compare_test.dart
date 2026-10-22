import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_overwatch/core/api.dart';
import 'package:watch_overwatch/core/models.dart';
import 'package:watch_overwatch/core/overview.dart';
import 'package:watch_overwatch/core/support.dart';
import 'package:watch_overwatch/design/tokens.dart';
import 'package:watch_overwatch/design/widgets.dart';
import 'package:watch_overwatch/state/app_state.dart';
import 'package:watch_overwatch/ui/pages/hero_compare.dart';
import 'package:watch_overwatch/ui/pages/player_compare.dart';

Map<String, Object?> hero(String guid, String name, int n, int w) => {
  'queue': 'role_queue',
  'hero': {'kind': 'hero', 'guid': guid, 'name': name},
  'matches': n,
  'wins': w,
  'win_rate_pct': 100 * w / n,
  'kda': 3.0,
  'play_time_s': 600.0 * n,
  'per_match': <Object?>[],
  'per_10min': <Object?>[],
};

Map<String, Object?> record(int w, int l) => {
  'matches': w + l,
  'wins': w,
  'losses': l,
  'draws': 0,
  'win_rate_pct': 100 * w / (w + l),
  'enough': true,
};

Map<String, Object?> overview(int listed, int w, int l, double kills) => {
  'enabled': true,
  'listed': listed,
  'overview': {
    'overall': {
      'record': record(w, l),
      'per_match': {'kills': kills},
      'kda': 2.0,
    },
    'recent': {'record': record(w, l), 'per_match': <String, Object?>{}},
  },
};

Widget host(AppState app, Listenable ws, Widget Function() child) =>
    MaterialApp(
      theme: ThemeData(extensions: [AppColors.dark]),
      home: Scaffold(
        body: AppScope(
          state: app,
          child: ListenableBuilder(
            listenable: ws,
            builder: (_, _) => SingleChildScrollView(child: child()),
          ),
        ),
      ),
    );

void main() {
  testWidgets('two heroes side by side say when there is too little to go on', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final app = AppState(Backend(), UiState());
    final ws = PlayerWorkspace(app, 'KCN#51896');
    final a = HeroUsage(hero('1', '安娜', 40, 24));
    final b = HeroUsage(hero('2', '雾子', 3, 1));
    await tester.pumpWidget(
      host(
        app,
        ws,
        () => SizedBox(
          height: 1200,
          child: HeroComparePage(workspace: ws, a: a, b: b, all: [a, b]),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('安娜 对比 雾子'), findsOneWidget);
    expect(find.text('雾子 只有 3 场，数字很不稳定。'), findsOneWidget);
    expect(find.text('+26.7（+80%）'), findsOneWidget); // 60% − 33.3%
    await tester.tap(find.widgetWithText(AppButton, '换一个'));
    expect(ws.comparingHero, isTrue);
    expect(ws.compareHeroKey, isNull);
  });

  testWidgets('another player is compared in the same mode, samples stated', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final app = AppState(Backend(), UiState());
    final me = PlayerWorkspace(app, 'KCN#51896');
    final other = PlayerWorkspace(app, '小明#5123');
    app.workspaces['kcn#51896'] = me;
    app.workspaces['小明#5123'] = other;
    other.overviewFor(Mode.quick).value = OverviewResult(
      overview(10, 4, 6, 15),
    );
    await tester.pumpWidget(
      host(
        app,
        me,
        () => PlayerCompareSection(
          workspace: me,
          mode: Mode.quick,
          mine: OverviewResult(overview(40, 24, 16, 20)),
        ),
      ),
    );
    await tester.tap(find.widgetWithText(AppButton, '小明#5123'));
    await tester.pump();
    expect(find.text('+20%'), findsWidgets); // 60% − 40%
    expect(find.text('+5.0'), findsOneWidget); // kills
    expect(find.text('KCN#51896 用了 40 场，小明#5123 用了 10 场。'), findsOneWidget);
    expect(find.text('双方场次相差较大，样本少的一方数字更不稳定。'), findsOneWidget);
  });
}
