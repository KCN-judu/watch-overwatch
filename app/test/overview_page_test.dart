import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_overwatch/core/api.dart';
import 'package:watch_overwatch/core/models.dart';
import 'package:watch_overwatch/core/overview.dart';
import 'package:watch_overwatch/core/support.dart';
import 'package:watch_overwatch/design/chart_kit.dart';
import 'package:watch_overwatch/design/tokens.dart';
import 'package:watch_overwatch/design/widgets.dart';
import 'package:watch_overwatch/state/app_state.dart';
import 'package:watch_overwatch/ui/pages/overview_page.dart';

Map<String, Object?> record(int w, int l) => {
  'matches': w + l,
  'wins': w,
  'losses': l,
  'draws': 0,
  'win_rate_pct': w + l == 0 ? null : 100 * w / (w + l),
  'win_rate_low_pct': 40.0,
  'win_rate_high_pct': 70.0,
  'enough': w + l >= 5,
};

Map<String, Object?> agg(int w, int l, {double? kda}) => {
  'record': record(w, l),
  'per_match': <String, Object?>{},
  'kda': kda,
  'streaks': {'current': 0},
};

final map = {
  'kind': 'map',
  'guid': '576460752303424195',
  'official_id': '0x08000000000002C3',
  'name': '努巴尼',
};

Map<String, Object?> overviewJson({int listed = 40}) => {
  'enabled': true,
  'listed': listed,
  'overview': {
    'overall': agg(22, 18, kda: 2.5),
    'recent': agg(13, 7, kda: 3.1),
    'before': agg(9, 11, kda: 2.2),
    'windows': [
      {'window': 'today', 'aggregate': agg(2, 1)},
    ],
    'by_role': <Object?>[],
    'by_hero': <Object?>[],
    'by_map': [
      {
        'key': 'overwatch:map:0x08000000000002c3',
        'label': '努巴尼',
        'aggregate': agg(8, 2),
      },
    ],
    'heat': [
      for (var d = 0; d < 7; d++) [for (var h = 0; h < 24; h++) record(0, 0)],
    ],
    'sessions': <Object?>[],
    'form': [
      for (var i = 0; i < 3; i++)
        {
          'match_id': 'm$i',
          'started_at_ms': 1767283200000 + i,
          'outcome': i == 0 ? 'loss' : 'win',
          'role': 'support',
          'map': map,
        },
    ],
    'rolling_win_pct': [50.0, 60.0],
    'insights': [
      {
        'kind': 'map',
        'positive': true,
        'subject': '努巴尼',
        'value': 80.0,
        'other': 55.0,
        'n': 10,
        'key': 'overwatch:map:0x08000000000002c3',
      },
    ],
  },
};

({AppState app, PlayerWorkspace ws, Widget page}) setUp(
  Map<String, Object?> json,
) {
  final app = AppState(Backend(), UiState())..mode = Mode.quick;
  final ws = PlayerWorkspace(app, 'KCN#51896');
  ws.overviewFor(Mode.quick).value = OverviewResult(json);
  ws.matchesFor(Mode.quick).value = PlayerDataset({
    'generated_at_ms': 0,
    'matches': [
      {
        'id': 'm0',
        'kind': {'mode': 'quick'},
        'outcome': 'win',
        'map': map,
      },
    ],
  });
  final page = MaterialApp(
    theme: ThemeData(extensions: [AppColors.dark]),
    home: Scaffold(
      body: AppScope(
        state: app,
        child: ListenableBuilder(
          listenable: ws,
          builder: (_, _) => OverviewPage(workspace: ws),
        ),
      ),
    ),
  );
  return (app: app, ws: ws, page: page);
}

void main() {
  testWidgets('the headline says the recent rate against the one before', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final t = setUp(overviewJson());
    await tester.pumpWidget(t.page);
    await tester.pumpAndSettle();
    expect(find.text('65%'), findsOneWidget); // 13 of 20
    expect(find.text('比之前 20 场 +20%'), findsOneWidget);
    expect(find.text('13 胜 7 负', findRichText: true), findsOneWidget);
    expect(find.text('2 胜 1 负', findRichText: true), findsOneWidget); // today
    expect(find.textContaining('努巴尼 是该玩家的强图'), findsOneWidget);
    expect(find.text('什么时候打得好'), findsOneWidget);
  });

  testWidgets('a face in the form strip opens that match', (tester) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final t = setUp(overviewJson());
    await tester.pumpWidget(t.page);
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel(RegExp('^负 · 努巴尼')).first);
    expect(t.ws.openMatchId, 'm0');
    expect(t.app.tab, 'matches');
  });

  testWidgets('a map row filters the match list to that map', (tester) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final t = setUp(overviewJson());
    await tester.pumpWidget(t.page);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(IntervalBars),
        matching: find.text('努巴尼'),
      ),
    );
    expect(t.ws.filtersFor(Mode.quick).mapGuid, '576460752303424195');
    expect(t.app.tab, 'matches');
  });

  testWidgets('a place a fall came from opens the matches there', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final json = overviewJson();
    ((json['overview'] as Map)['insights'] as List).add({
      'kind': 'drivers',
      'positive': false,
      'value': 40.0,
      'n': 20,
      'items': [
        {
          'label': '努巴尼',
          'key': 'overwatch:map:0x08000000000002c3',
          'kind': 'map',
          'delta': -6,
        },
      ],
    });
    final t = setUp(json);
    await tester.pumpWidget(t.page);
    await tester.pumpAndSettle();
    expect(find.text('状态下滑主要来自 努巴尼（净胜 −6）'), findsOneWidget);
    await tester.tap(find.widgetWithText(AppButton, '努巴尼'));
    expect(t.ws.filtersFor(Mode.quick).mapGuid, '576460752303424195');
    expect(t.app.tab, 'matches');
  });

  testWidgets('a kind of finding can be hidden and brought back', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final t = setUp(overviewJson());
    await tester.pumpWidget(t.page);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('不再提示这类'));
    await tester.pumpAndSettle();
    expect(t.app.mutedInsights, {'map'});
    expect(find.textContaining('努巴尼 是该玩家的强图'), findsNothing);
    expect(find.text('已隐藏 1 类提示'), findsWidgets);
    await tester.tap(find.widgetWithText(AppButton, '全部恢复'));
    await tester.pumpAndSettle();
    expect(find.textContaining('努巴尼 是该玩家的强图'), findsOneWidget);
  });

  testWidgets('no stored matches: say so and point to the match list', (
    tester,
  ) async {
    final t = setUp(overviewJson(listed: 0));
    await tester.pumpWidget(t.page);
    await tester.pumpAndSettle();
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('打开对局页'), findsOneWidget);
  });
}
