import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_overwatch/core/api.dart';
import 'package:watch_overwatch/core/daily.dart';
import 'package:watch_overwatch/core/models.dart';
import 'package:watch_overwatch/core/support.dart';
import 'package:watch_overwatch/design/tokens.dart';
import 'package:watch_overwatch/design/widgets.dart';
import 'package:watch_overwatch/state/app_state.dart';
import 'package:watch_overwatch/ui/pages/daily_page.dart';

Map<String, Object?> record(int w, int l) => {
  'matches': w + l,
  'wins': w,
  'losses': l,
  'draws': 0,
  'win_rate_pct': 100 * w / (w + l),
  'enough': w + l >= 5,
};

final map = {'kind': 'map', 'guid': 'm1', 'name': '努巴尼'};
final hero = {'kind': 'hero', 'guid': 'h1', 'name': '安娜'};

Map<String, Object?> dailyJson() => {
  'enabled': true,
  'daily': {
    'days': [
      {'day': '2026-10-22', 'record': record(4, 1)},
      {'day': '2026-10-21', 'record': record(1, 2)},
    ],
    'summary': {
      'day': '2026-10-22',
      'aggregate': {
        'record': record(4, 1),
        'per_match': {'kills': 15.0},
        'kda': 4.2,
      },
      'sittings': 2,
      'first_ms': 1792666800000,
      'last_ms': 1792681200000,
      'play_s': 3900.0,
      'play_samples': 5,
      'heroes': [
        {
          'key': 'h1',
          'label': '安娜',
          'aggregate': {'record': record(4, 1)},
        },
      ],
      'maps': [
        {
          'key': 'm1',
          'label': '努巴尼',
          'aggregate': {'record': record(2, 0)},
        },
      ],
      'rank_changes': [
        {'role': 'support', 'from': 2400, 'to': 2500},
      ],
      'highlights': [
        {
          'kind': 'personal_record',
          'stat': 'kills',
          'value': 31.0,
          'previous': 24.0,
          'match_id': 'b',
          'hero': hero,
          'map': map,
        },
        {'kind': 'lobby_top', 'stat': 'healing', 'value': 2.0},
        {'kind': 'streak', 'stat': '', 'value': 4.0},
      ],
      'versus_role': 'support',
      'versus': [
        {
          'stat': 'kills',
          'today': 15.0,
          'usual': 12.0,
          'today_n': 5,
          'usual_n': 25,
        },
      ],
      'match_ids': ['b'],
    },
  },
};

void main() {
  testWidgets(
    'a day lays out, says what stood out, and a highlight opens its match',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final app = AppState(Backend(), UiState())..mode = Mode.competitive;
      final ws = PlayerWorkspace(app, 'KCN#51896');
      ws.dailyFor(Mode.competitive).value = DailyResult(dailyJson());
      ws.matchesFor(Mode.competitive).value = PlayerDataset({
        'generated_at_ms': 0,
        'matches': [
          {
            'id': 'b',
            'kind': {'mode': 'competitive'},
            'outcome': 'win',
            'started_at_ms': 1792666800000,
            'map': map,
            'hero': hero,
            'stats': {'kills': 31, 'deaths': 0, 'assists': 9},
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
                builder: (_, _) => DailyPage(workspace: ws),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('每日总结 · 2026-10-22 周四'), findsOneWidget);
      expect(find.text('刷新纪录：消灭'), findsOneWidget);
      expect(find.text('之前本机最高 24'), findsOneWidget);
      expect(find.text('全场 10 人里最高'), findsOneWidget);
      expect(find.textContaining('治疗 ×', findRichText: true), findsOneWidget);
      expect(find.text('4 连胜'), findsOneWidget);
      expect(find.text('+25%'), findsOneWidget);
      expect(find.text('31/0/9'), findsOneWidget);
      await tester.tap(find.text('刷新纪录：消灭'));
      expect(ws.openMatchId, 'b');
      expect(app.tab, 'matches');
    },
  );

  testWidgets('no matches: say so', (tester) async {
    final app = AppState(Backend(), UiState());
    final ws = PlayerWorkspace(app, 'KCN#51896');
    ws.dailyFor(app.mode).value = DailyResult({
      'enabled': true,
      'daily': {'days': <Object?>[]},
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [AppColors.dark]),
        home: Scaffold(
          body: AppScope(
            state: app,
            child: DailyPage(workspace: ws),
          ),
        ),
      ),
    );
    expect(find.byType(EmptyState), findsOneWidget);
  });
}
