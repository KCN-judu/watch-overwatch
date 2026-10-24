import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_overwatch/core/api.dart';
import 'package:watch_overwatch/core/models.dart';
import 'package:watch_overwatch/core/stadium.dart';
import 'package:watch_overwatch/core/support.dart';
import 'package:watch_overwatch/design/tokens.dart';
import 'package:watch_overwatch/state/app_state.dart';
import 'package:watch_overwatch/ui/pages/stadium_builds.dart';

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

Map<String, Object?> up(String guid, String name) => {
  'kind': 'stadium_upgrade',
  'guid': guid,
  'name': name,
};

const ana = EntityRef('hero', 'h1', '安娜', null);

Map<String, Object?> stadiumJson() => {
  'enabled': true,
  'stadium': {
    'scope': 'own',
    'details': 9,
    'heroes': [
      {
        'hero': {'kind': 'hero', 'guid': 'h1', 'name': '安娜'},
        'matches': 8,
        'own_matches': 8,
        'record': record(5, 3),
        'powers': [
          {
            'upgrade': up('p1', '纳米强化'),
            'round': 3,
            'picks': 6,
            'pick_rate_pct': 75.0,
            'record': record(4, 2),
            'match_ids': ['m1', 'm2'],
          },
          {
            'upgrade': up('p2', '睡眠专精'),
            'round': 1,
            'picks': 2,
            'pick_rate_pct': 25.0,
            'record': record(1, 1),
            'match_ids': <String>[],
          },
        ],
        'items': <Object?>[],
        'builds': [
          {
            'powers': [up('p1', '纳米强化'), up('p2', '睡眠专精')],
            'record': record(1, 1),
            'pick_rate_pct': 25.0,
            'match_ids': ['m1'],
          },
        ],
      },
    ],
  },
};

void main() {
  testWidgets(
    'powers say their round, pick rate and record; one lists its matches',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final app = AppState(Backend(), UiState())..mode = Mode.stadium;
      final ws = PlayerWorkspace(app, 'KCN#51896');
      ws.stadiumFor(BuildSample.own).value = StadiumResult(stadiumJson());
      ws.matchesFor(Mode.stadium).value = PlayerDataset({
        'generated_at_ms': 0,
        'matches': [
          {
            'id': 'm1',
            'kind': {'mode': 'stadium'},
            'outcome': 'win',
            'started_at_ms': 1767283200000,
          },
        ],
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [AppColors.dark]),
          home: Scaffold(
            body: AppScope(
              state: app,
              child: ListenableBuilder(
                listenable: ws,
                builder: (_, _) => SingleChildScrollView(
                  child: StadiumBuildsSection(
                    workspace: ws,
                    hero: ana,
                    accent: const Color(0xFF3366FF),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('纳米强化 · 第 3 回合 · 选取率 75%'), findsOneWidget);
      expect(find.text('纳米强化、睡眠专精'), findsOneWidget);
      expect(find.textContaining('8 场本人对局'), findsOneWidget);
      await tester.tap(find.text('纳米强化 · 第 3 回合 · 选取率 75%'));
      await tester.pump();
      expect(find.text('本人使用它的 2 场对局'), findsOneWidget);
      await tester.tap(find.text(fmtDateTime(1767283200000)));
      expect(ws.openMatchId, 'm1');
      expect(app.tab, 'matches');
    },
  );
}
