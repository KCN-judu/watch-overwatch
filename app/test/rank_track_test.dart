import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_overwatch/core/api.dart';
import 'package:watch_overwatch/core/models.dart';
import 'package:watch_overwatch/core/ranks.dart';
import 'package:watch_overwatch/core/support.dart';
import 'package:watch_overwatch/design/charts.dart';
import 'package:watch_overwatch/design/tokens.dart';
import 'package:watch_overwatch/design/widgets.dart';
import 'package:watch_overwatch/state/app_state.dart';
import 'package:watch_overwatch/ui/pages/rank_track.dart';

Map<String, Object?> point(String id, int at, int sr, String outcome, int? s) =>
    {
      'match_id': id,
      'at_ms': at,
      'outcome': outcome,
      'skill_rating': sr,
      'season': s,
    };

const day = 86400000;
const t0 = 1767283200000;

Map<String, Object?> ranksJson() => {
  'enabled': true,
  'ranks': {
    'roles': [
      {
        'role': 'support',
        'points': [
          point('a', t0, 2300, 'win', 24),
          point('b', t0 + day, 2350, 'win', 25),
          point('c', t0 + 2 * day, 2200, 'loss', 25),
        ],
      },
    ],
    'seasons': [
      {'season': 25, 'start_ms': t0 + day, 'matches': 2},
    ],
    'drops': [
      {
        'role': 'support',
        'from_match_id': 'b',
        'to_match_id': 'c',
        'from_ms': t0 + day,
        'to_ms': t0 + 2 * day,
        'from_rating': 2350,
        'to_rating': 2200,
        'matches': 1,
        'wins': 0,
        'losses': 1,
        'rated': 1,
        'mean_enemy_edge': 140.0,
      },
    ],
  },
};

void main() {
  testWidgets(
    'a role track marks the new season and a drop says who was stronger',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final app = AppState(Backend(), UiState())..mode = Mode.competitive;
      final ws = PlayerWorkspace(app, 'KCN#51896');
      ws.ranksFor(Mode.competitive).value = RanksResult(ranksJson());
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [AppColors.dark]),
          home: Scaffold(
            body: AppScope(
              state: app,
              child: ListenableBuilder(
                listenable: ws,
                builder: (_, _) => SingleChildScrollView(
                  child: RankTrackSection(
                    workspace: ws,
                    mode: Mode.competitive,
                    seasonMatches: const {25: 2},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final chart = tester.widget<LineChart>(find.byType(LineChart));
      expect(chart.markers.single.index, 1);
      expect(chart.markers.single.label, 'S25');
      expect(find.textContaining('掉了 150 分'), findsOneWidget);
      expect(find.text('其中 1 场有对局强度：对面平均高 140 分'), findsOneWidget);
      chart.onOpen!(0);
      expect(ws.openMatchId, 'a');
      expect(app.tab, 'matches');
      app.setTab('trend');
      await tester.pump();
      await tester.tap(find.widgetWithText(AppButton, '打开最后一场'));
      expect(ws.openMatchId, 'c');
    },
  );
}
