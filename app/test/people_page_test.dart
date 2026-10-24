import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_overwatch/core/api.dart';
import 'package:watch_overwatch/core/models.dart';
import 'package:watch_overwatch/core/people.dart';
import 'package:watch_overwatch/core/support.dart';
import 'package:watch_overwatch/design/tokens.dart';
import 'package:watch_overwatch/design/widgets.dart';
import 'package:watch_overwatch/state/app_state.dart';
import 'package:watch_overwatch/ui/pages/people_page.dart';

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

const t0 = 1767283200000;

Map<String, Object?> peopleJson({int details = 12}) => {
  'enabled': true,
  'people': {
    'details': details,
    'mates': [
      {
        'key': 'f',
        'name': '小明#5123',
        'as_ally': record(4, 1),
        'as_enemy': record(1, 0),
        'in_party': 5,
        'last_ms': t0,
        'match_ids': ['m1', 'm2', 'm3', 'm4', 'm5', 'm6'],
      },
    ],
    'party': record(6, 2),
    'solo': record(2, 2),
    'party_size': {'m1': 2},
  },
};

Map<String, Object?> duoJson() => {
  'enabled': true,
  'duo': {
    'name': '小明#5123',
    'with': record(4, 1),
    'without': record(3, 4),
    'against': record(1, 0),
    'matches': [
      {
        'match_id': 'm1',
        'started_at_ms': t0,
        'outcome': 'win',
        'same_side': true,
        'grouped': true,
        'me': {'kills': 20, 'deaths': 3, 'assists': 9},
        'them': {'kills': 11, 'deaths': 5, 'assists': 14},
      },
    ],
  },
};

({AppState app, PlayerWorkspace ws, Widget page}) setUp(
  Map<String, Object?> people,
) {
  final app = AppState(Backend(), UiState())..mode = Mode.competitive;
  final ws = PlayerWorkspace(app, 'KCN#51896');
  ws.peopleFor(Mode.competitive).value = PeopleResult(people);
  ws.duoFor(Mode.competitive, 'f').value = DuoResult(duoJson());
  final page = MaterialApp(
    theme: ThemeData(extensions: [AppColors.dark]),
    home: Scaffold(
      body: AppScope(
        state: app,
        child: ListenableBuilder(
          listenable: ws,
          builder: (_, _) => PeoplePage(workspace: ws),
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

  testWidgets(
    'group against solo, then the frequent player with shared matches',
    (tester) async {
      bigWindow(tester);
      final t = setUp(peopleJson());
      await tester.pumpWidget(t.page);
      await tester.pump();
      expect(find.text('组排胜率'), findsOneWidget);
      expect(find.text('75%'), findsOneWidget); // 6 of 8 in a group
      expect(find.text('小明#5123'), findsWidgets);
      expect(find.text('共同 6 场'), findsOneWidget);
      expect(find.textContaining('同队 5 场，胜率 80%'), findsOneWidget);
      expect(find.text('同队，组排'), findsOneWidget);
      expect(find.text('20/3/9'), findsOneWidget);
      await tester.tap(find.text('20/3/9'));
      expect(t.ws.openMatchId, 'm1');
      expect(t.app.tab, 'matches');
    },
  );

  testWidgets('no stored details: say where they come from', (tester) async {
    final t = setUp(peopleJson(details: 0));
    await tester.pumpWidget(t.page);
    await tester.pump();
    expect(find.byType(EmptyState), findsOneWidget);
  });
}
