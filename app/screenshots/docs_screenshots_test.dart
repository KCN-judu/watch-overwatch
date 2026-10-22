// Regenerates the documentation's screenshots of the pages that are drawn from local
// data alone, so they never go stale:
//
//   cd app
//   flutter test --update-goldens screenshots
//
// Not part of `flutter test` (it only runs `test/`): it needs the Windows fonts, and
// the pictures are written into `docs/images/`. The data is made up here.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_overwatch/core/api.dart';
import 'package:watch_overwatch/core/maps.dart';
import 'package:watch_overwatch/core/models.dart';
import 'package:watch_overwatch/core/overview.dart';
import 'package:watch_overwatch/core/people.dart';
import 'package:watch_overwatch/core/support.dart';
import 'package:watch_overwatch/design/tokens.dart';
import 'package:watch_overwatch/state/app_state.dart';
import 'package:watch_overwatch/ui/pages/maps_page.dart';
import 'package:watch_overwatch/ui/pages/overview_page.dart';
import 'package:watch_overwatch/ui/pages/people_page.dart';

Future<void> _font(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final p in paths) {
    final f = File(p);
    if (f.existsSync()) {
      loader.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
    }
  }
  await loader.load();
}

Future<void> _fonts() async {
  const win = r'C:\Windows\Fonts';
  for (final family in ['Microsoft YaHei UI', 'Microsoft YaHei']) {
    await _font(family, ['$win\\msyh.ttc', '$win\\msyhbd.ttc']);
  }
  await _font('Segoe UI', ['$win\\segoeui.ttf']);
  final flutter = Platform.environment['FLUTTER_ROOT'] ?? r'C:\dev\flutter';
  await _font('MaterialIcons', [
    '$flutter\\bin\\cache\\artifacts\\material_fonts\\materialicons-regular.otf',
  ]);
}

Map<String, Object?> record(int w, int l) {
  final n = w + l;
  final p = n == 0 ? 0.0 : w / n;
  final half = n == 0 ? 0.0 : 98 / (n + 4).toDouble();
  return {
    'matches': n,
    'wins': w,
    'losses': l,
    'draws': 0,
    'win_rate_pct': n == 0 ? null : 100 * p,
    'win_rate_low_pct': n == 0 ? null : (100 * p - half).clamp(0, 100),
    'win_rate_high_pct': n == 0 ? null : (100 * p + half).clamp(0, 100),
    'enough': n >= 5,
  };
}

Map<String, Object?> agg(int w, int l) => {
  'record': record(w, l),
  'per_match': {
    'kills': 14.2,
    'deaths': 6.1,
    'assists': 9.8,
    'damage': 7400.0,
    'healing': 5300.0,
  },
  'kda': 3.9,
  'streaks': {'current': 3},
};

Map<String, Object?> ref(String kind, String guid, String name) => {
  'kind': kind,
  'guid': guid,
  'name': name,
};

const maps = [
  ('1', '努巴尼', 9, 3),
  ('2', '伊利奥斯', 7, 6),
  ('3', '国王大道', 5, 6),
  ('4', '多拉多', 4, 2),
  ('5', '新渣客城', 2, 5),
  ('6', '苏拉瓦萨', 3, 1),
];
const heroes = [
  ('h1', '安娜', 14, 8),
  ('h2', '雾子', 9, 7),
  ('h3', '莱因哈特', 6, 6),
  ('h4', '索杰恩', 4, 2),
];

Map<String, Object?> overviewJson() => {
  'enabled': true,
  'listed': 96,
  'overview': {
    'overall': agg(52, 44),
    'recent': agg(13, 7),
    'before': agg(9, 11),
    'windows': [
      {'window': 'today', 'aggregate': agg(3, 1)},
      {'window': 'week', 'aggregate': agg(11, 6)},
    ],
    'by_role': <Object?>[],
    'by_hero': [
      for (final h in heroes)
        {'key': h.$1, 'label': h.$2, 'aggregate': agg(h.$3, h.$4)},
    ],
    'by_map': [
      for (final m in maps)
        {'key': m.$1, 'label': m.$2, 'aggregate': agg(m.$3, m.$4)},
    ],
    'heat': [
      for (var d = 0; d < 7; d++)
        [
          for (var h = 0; h < 24; h++)
            h >= 19 && h <= 23
                ? record(2 + (d + h) % 3, 1 + (d * h) % 3)
                : record(0, 0),
        ],
    ],
    'sessions': <Object?>[],
    'form': [
      for (var i = 0; i < 20; i++)
        {
          'match_id': 'm$i',
          'started_at_ms': 1767283200000 + i * 3600000,
          'outcome': (i * 7) % 3 == 0 ? 'loss' : 'win',
          'role': 'support',
          'map': ref('map', maps[i % maps.length].$1, maps[i % maps.length].$2),
          'hero': ref('hero', 'h1', '安娜'),
        },
    ],
    'rolling_win_pct': [45.0, 50.0, 55.0, 60.0, 65.0],
    'insights': [
      {'kind': 'streak', 'positive': true, 'n': 3, 'value': 0},
      {
        'kind': 'map',
        'positive': true,
        'subject': '努巴尼',
        'value': 75.0,
        'other': 54.0,
        'n': 12,
        'key': '1',
      },
      {
        'kind': 'fatigue',
        'positive': false,
        'value': 38.0,
        'other': 61.0,
        'n': 26,
        'p': 0.04,
      },
    ],
  },
};

Map<String, Object?> mapsJson() => {
  'enabled': true,
  'listed': 96,
  'maps': {
    'modes': [
      {
        'mode': '攻击/护送',
        'record': record(18, 11),
        'maps': [
          for (final m in maps.take(3))
            {
              'map': ref('map', m.$1, m.$2),
              'key': m.$1,
              'aggregate': agg(m.$3, m.$4),
              'duration_s': 742.0,
              'duration_samples': 9,
              'heroes': [
                for (final h in heroes.take(3))
                  {
                    'key': h.$1,
                    'label': h.$2,
                    'aggregate': agg(h.$3 ~/ 2, h.$4 ~/ 2),
                  },
              ],
              'ranked': true,
            },
        ],
      },
      {
        'mode': '占领要点',
        'record': record(9, 8),
        'maps': [
          for (final m in maps.skip(3))
            {
              'map': ref('map', m.$1, m.$2),
              'key': m.$1,
              'aggregate': agg(m.$3, m.$4),
              'duration_samples': 0,
              'heroes': <Object?>[],
              'ranked': m.$3 + m.$4 >= 5,
            },
        ],
      },
    ],
  },
};

Map<String, Object?> peopleJson() => {
  'enabled': true,
  'people': {
    'details': 48,
    'mates': [
      for (final (i, n) in ['晨星#1101', '青柠#2202', '北辰#3303'].indexed)
        {
          'key': 'p$i',
          'name': n,
          'as_ally': record(8 - i * 2, 4 - i),
          'as_enemy': record(i, 1),
          'in_party': 10 - i * 4,
          'last_ms': 1767283200000,
          'match_ids': [for (var k = 0; k < 14 - i * 3; k++) 'm$k'],
        },
    ],
    'party': record(18, 9),
    'solo': record(11, 10),
    'party_size': <String, int>{},
  },
};

Map<String, Object?> duoJson() => {
  'enabled': true,
  'duo': {
    'name': '晨星#1101',
    'with': record(8, 4),
    'without': record(21, 15),
    'against': record(0, 1),
    'matches': [
      for (var k = 0; k < 6; k++)
        {
          'match_id': 'm$k',
          'started_at_ms': 1767283200000 - k * 86400000,
          'map': ref('map', maps[k].$1, maps[k].$2),
          'outcome': k % 3 == 2 ? 'loss' : 'win',
          'same_side': k != 4,
          'grouped': k != 4,
          'me_hero': ref('hero', 'h1', '安娜'),
          'me': {'kills': 9 + k, 'deaths': 4, 'assists': 14},
          'them_hero': ref('hero', 'h3', '莱因哈特'),
          'them': {'kills': 18 - k, 'deaths': 6, 'assists': 7},
        },
    ],
  },
};

Future<void> shoot(
  WidgetTester tester,
  String file,
  Widget Function(PlayerWorkspace ws) page,
  void Function(PlayerWorkspace ws) fill,
) async {
  tester.view.physicalSize = const Size(1440, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final app = AppState(Backend(), UiState())..mode = Mode.competitive;
  final ws = PlayerWorkspace(app, '示例玩家#0000');
  fill(ws);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.dark),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(Sp.betweenGroups),
          child: AppScope(
            state: app,
            child: ListenableBuilder(
              listenable: ws,
              builder: (_, _) => page(ws),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('../../docs/images/$file'),
  );
}

void main() {
  setUpAll(_fonts);

  testWidgets('overview', (tester) async {
    await shoot(tester, 'overview.png', (ws) => OverviewPage(workspace: ws), (
      ws,
    ) {
      ws.overviewFor(Mode.competitive).value = OverviewResult(overviewJson());
    });
  });

  testWidgets('maps', (tester) async {
    await shoot(tester, 'maps.png', (ws) => MapsPage(workspace: ws), (ws) {
      ws.mapsFor(Mode.competitive).value = MapsResult(mapsJson());
    });
  });

  testWidgets('people', (tester) async {
    await shoot(tester, 'people.png', (ws) => PeoplePage(workspace: ws), (ws) {
      ws.peopleFor(Mode.competitive).value = PeopleResult(peopleJson());
      ws.duoFor(Mode.competitive, 'p0').value = DuoResult(duoJson());
    });
  });
}
