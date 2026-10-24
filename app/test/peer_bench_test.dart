import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_overwatch/core/api.dart';
import 'package:watch_overwatch/core/benchmark.dart';
import 'package:watch_overwatch/core/models.dart';
import 'package:watch_overwatch/core/support.dart';
import 'package:watch_overwatch/design/tokens.dart';
import 'package:watch_overwatch/state/app_state.dart';
import 'package:watch_overwatch/ui/pages/peer_bench.dart';

const kiriko = EntityRef(
  'hero',
  '207165582859043685',
  '雾子',
  '0x02E0000000000365',
);

Map<String, Object?> bench({List<String> tiers = const ['Gold', 'Platinum']}) =>
    {
      'enabled': true,
      'matches': 210,
      'heroes': [
        {
          'hero': {
            'kind': 'hero',
            'guid': '207165582859043685',
            'official_id': '0x02E0000000000365',
            'name': '雾子',
          },
          'role': 'support',
          'matches': 88,
          'tier': 'Gold',
          'metrics': [
            {
              'metric': 'healing',
              'value': 5854.0,
              'peer_median': 7546.0,
              'percentile': 27.0,
              'band': 'subpar',
              'peers': {'tiers': tiers, 'matches': 99},
            },
          ],
        },
      ],
    };

Widget host(PlayerWorkspace ws, Mode mode, AppState app) => MaterialApp(
  theme: ThemeData(extensions: [AppColors.dark]),
  home: Scaffold(
    body: AppScope(
      state: app,
      child: PeerBenchSection(
        workspace: ws,
        mode: mode,
        hero: kiriko,
        accent: Colors.blue,
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'a metric says its percentile, band and the peers it is against',
    (tester) async {
      final app = AppState(Backend(), UiState());
      final ws = PlayerWorkspace(app, 'KCN#51896');
      ws.benchmarkFor(Mode.quick).value = BenchmarkResult(bench());
      await tester.pumpWidget(host(ws, Mode.quick, app));
      expect(
        find.bySemanticsLabel('治疗：5,854 /10分，第 27 百分位（偏低），同分段中位数 7,546'),
        findsOneWidget,
      );
      expect(find.textContaining('基准：黄金–白金的雾子，99 场'), findsOneWidget);
      expect(find.textContaining('不代表全服'), findsOneWidget);
    },
  );

  testWidgets('any rank is said as such', (tester) async {
    final app = AppState(Backend(), UiState());
    final ws = PlayerWorkspace(app, 'KCN#51896');
    ws.benchmarkFor(Mode.quick).value = BenchmarkResult(bench(tiers: const []));
    await tester.pumpWidget(host(ws, Mode.quick, app));
    expect(find.textContaining('基准：不限段位的雾子'), findsOneWidget);
  });

  testWidgets('without a benchmark for the hero it says what is missing', (
    tester,
  ) async {
    final app = AppState(Backend(), UiState());
    final ws = PlayerWorkspace(app, 'KCN#51896');
    ws.benchmarkFor(Mode.quick).value = BenchmarkResult({
      'enabled': true,
      'matches': 3,
      'heroes': <Object?>[],
    });
    await tester.pumpWidget(host(ws, Mode.quick, app));
    expect(find.textContaining('≥ 30 场'), findsOneWidget);
  });

  testWidgets('stadium has no benchmark', (tester) async {
    final app = AppState(Backend(), UiState());
    final ws = PlayerWorkspace(app, 'KCN#51896');
    await tester.pumpWidget(host(ws, Mode.stadium, app));
    expect(find.textContaining('角斗领域'), findsOneWidget);
  });
}
