import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_overwatch/core/api.dart';
import 'package:watch_overwatch/core/maps.dart';
import 'package:watch_overwatch/core/models.dart';
import 'package:watch_overwatch/core/support.dart';
import 'package:watch_overwatch/design/tokens.dart';
import 'package:watch_overwatch/design/widgets.dart';
import 'package:watch_overwatch/state/app_state.dart';
import 'package:watch_overwatch/ui/pages/maps_page.dart';

Map<String, Object?> record(int w, int l) => {
  'matches': w + l,
  'wins': w,
  'losses': l,
  'draws': 0,
  'win_rate_pct': w + l == 0 ? null : 100 * w / (w + l),
  'win_rate_low_pct': 30.0,
  'win_rate_high_pct': 80.0,
  'enough': w + l >= 5,
};

Map<String, Object?> agg(int w, int l) => {
  'record': record(w, l),
  'per_match': {'kills': 18.0, 'damage': 9000.0},
  'kda': 3.2,
  'streaks': {'current': 0},
};

Map<String, Object?> entity(String kind, String guid, String name) => {
  'kind': kind,
  'guid': guid,
  'official_id': '0x0800000000000$guid',
  'name': name,
};

final nubani = entity('map', '2C3', '努巴尼');
final ilios = entity('map', '1A1', '伊利奥斯');
final ana = entity('hero', '13B', '安娜');

Map<String, Object?> mapsJson() => {
  'enabled': true,
  'listed': 14,
  'maps': {
    'modes': [
      {
        'mode': '攻击/护送',
        'record': record(8, 2),
        'maps': [
          {
            'map': nubani,
            'key': 'overwatch:map:0x08000000000002c3',
            'aggregate': agg(8, 2),
            'duration_s': 754.0,
            'duration_samples': 4,
            'heroes': [
              {
                'key': 'overwatch:hero:0x080000000000013b',
                'label': '安娜',
                'aggregate': agg(5, 1),
              },
            ],
            'ranked': true,
          },
        ],
      },
      {
        'mode': '占领要点',
        'record': record(1, 3),
        'maps': [
          {
            'map': ilios,
            'key': 'overwatch:map:0x08000000000001a1',
            'aggregate': agg(1, 3),
            'duration_samples': 0,
            'heroes': <Object?>[],
            'ranked': false,
          },
        ],
      },
    ],
  },
};

({AppState app, PlayerWorkspace ws, Widget page}) setUp(
  Map<String, Object?> json,
) {
  final app = AppState(Backend(), UiState())..mode = Mode.quick;
  final ws = PlayerWorkspace(app, 'KCN#51896');
  ws.mapsFor(Mode.quick).value = MapsResult(json);
  ws.matchesFor(Mode.quick).value = PlayerDataset({
    'generated_at_ms': 0,
    'matches': [
      {
        'id': 'm0',
        'kind': {'mode': 'quick'},
        'outcome': 'win',
        'map': nubani,
        'hero': ana,
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
          builder: (_, _) => MapsPage(workspace: ws),
        ),
      ),
    ),
  );
  return (app: app, ws: ws, page: page);
}

void main() {
  void bigWindow(WidgetTester tester) {
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('maps sit under their mode type; the first one is open', (
    tester,
  ) async {
    bigWindow(tester);
    final t = setUp(mapsJson());
    await tester.pumpWidget(t.page);
    await tester.pumpAndSettle();
    expect(find.text('攻击/护送'), findsWidgets);
    expect(find.text('占领要点'), findsWidgets);
    expect(find.text('10 场 · 胜率 80%'), findsOneWidget);
    expect(find.text('12:34'), findsOneWidget); // mean length
    expect(find.text('有详情的 4 场'), findsOneWidget);
    expect(find.text('本图英雄'), findsOneWidget);
  });

  testWidgets('a map with too few matches says it is not compared', (
    tester,
  ) async {
    bigWindow(tester);
    final t = setUp(mapsJson());
    await tester.pumpWidget(t.page);
    await tester.pumpAndSettle();
    await tester.tap(find.text('伊利奥斯').first);
    await tester.pumpAndSettle();
    expect(find.text('场次不足，不参与比较'), findsOneWidget);
    expect(find.text('需要对局详情'), findsOneWidget);
  });

  testWidgets('the open map leads to its matches, and a hero to those on it', (
    tester,
  ) async {
    bigWindow(tester);
    final t = setUp(mapsJson());
    await tester.pumpWidget(t.page);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(AppButton, '查看本图对局'));
    expect(t.ws.filtersFor(Mode.quick).mapGuid, '2C3');
    expect(t.ws.filtersFor(Mode.quick).heroGuid, isNull);
    expect(t.app.tab, 'matches');
    t.app.setTab('maps');
    await tester.pumpAndSettle();
    await tester.tap(find.text('安娜'));
    expect(t.ws.filtersFor(Mode.quick).mapGuid, '2C3');
    expect(t.ws.filtersFor(Mode.quick).heroGuid, '13B');
  });

  testWidgets('no stored matches: say so and point to the match list', (
    tester,
  ) async {
    final t = setUp({
      'enabled': true,
      'listed': 0,
      'maps': {'modes': []},
    });
    await tester.pumpWidget(t.page);
    await tester.pumpAndSettle();
    expect(find.byType(EmptyState), findsOneWidget);
  });
}
