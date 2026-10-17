import 'package:flutter_test/flutter_test.dart';
import 'package:watch_overwatch/core/hero_stats.dart';
import 'package:watch_overwatch/core/models.dart';
import 'package:watch_overwatch/core/support.dart';

const _hero = '111';
Map<String, dynamic> stat(String guid, String name) => {
  'kind': 'stat',
  'guid': guid,
  'name': name,
};

void main() {
  // A hero whose game list has kills, deaths, assists and damage, but no healing.
  final catalog = Catalog({
    'heroes': {
      _hero: {'name': '测试', 'role': 'tank'},
    },
    'statistics': [
      for (final (g, n) in [
        ('1', '消灭'),
        ('2', '阵亡'),
        ('3', '助攻'),
        ('4', '对英雄伤害量'),
      ])
        {'heroGuid': _hero, 'valueGuid': g, 'valueText': n},
    ],
  });

  HeroUsage usage({List<Map<String, dynamic>> perMatch = const []}) =>
      HeroUsage({
        'queue': 'role_queue',
        'hero': {'kind': 'hero', 'guid': _hero, 'name': '测试'},
        'matches': 10,
        'play_time_s': 6000.0, // 600 s a match
        'per_match': perMatch,
        'per_10min': [
          {'stat': stat('1', '消灭'), 'value': 20.0},
        ],
      });

  final heroRef = const EntityRef('hero', _hero, '测试', null);
  MatchSummary match(double kills) => MatchSummary({
    'id': 'm$kills',
    'hero': {'kind': 'hero', 'guid': _hero, 'name': '测试'},
    'stats': {'kills': kills, 'mitigation': 3000.0},
  });

  test('a stat the hero cannot produce has no figure', () {
    final h = usage();
    expect(
      HeroStats.cell10(h, catalog, const [], (n) => n.contains('治疗量')),
      isNull,
    );
  });

  test(
    'matches that show healing make it producible even if the list lacks it',
    () {
      final h = usage();
      // The catalog lists no healing for this hero, but recent matches heal.
      final healed = MatchSummary({
        'id': 'x',
        'hero': {'kind': 'hero', 'guid': _hero, 'name': '测试'},
        'stats': {'healing': 1200.0},
      });
      final v = HeroStats.cell10(h, catalog, [healed], (n) => n == '治疗量');
      expect(v, closeTo(1200, 0.01)); // 1200 a match, 600 s a match
    },
  );

  test(
    'self-healing counts as healing when a hero has no total-healing stat',
    () {
      final cat = Catalog({
        'heroes': {
          _hero: {'name': '测试', 'role': 'tank'},
        },
        'statistics': [
          {'heroGuid': _hero, 'valueGuid': '7', 'valueText': '自我治疗量'},
        ],
      });
      final v =
          HeroStats.cell10(usage(), cat, const [], (n) => n == '治疗量') ??
          HeroStats.cell10(usage(), cat, const [], (n) => n == '自我治疗量');
      expect(v, 0); // it can heal itself, none was recorded: zero, not a dash
    },
  );

  test('kills and damage are never a dash; supports always have healing', () {
    final bare = Catalog({
      'heroes': {
        _hero: {'name': '测试', 'role': 'healer'},
      },
      'statistics': [
        {'heroGuid': _hero, 'valueGuid': '9', 'valueText': '灌注永生权杖治疗量'},
      ],
    });
    bool kills(String n) => n == '消灭';
    expect(HeroStats.cell10(usage(), bare, const [], kills), isNotNull);
    expect(HeroStats.cell10(usage(), bare, const [], (n) => n == '对英雄伤害量'), 0);
    expect(
      HeroStats.cell10(usage(), bare, const [], (n) => n.contains('治疗量')),
      0,
    );
    // A tank gets no invented healing.
    expect(
      HeroStats.cell10(usage(), catalog, const [], (n) => n.contains('治疗量')),
      isNull,
    );
  });

  test('a stat the hero can produce but nobody recorded is zero', () {
    final rows = HeroStats.rows(usage(), catalog, const []);
    final assists = rows.firstWhere((r) => r.name == '助攻');
    expect(assists.perMatch, 0);
    expect(assists.per10, 0);
    expect(assists.perMatchSource, StatSource.zero);
  });

  test('a missing per-10 figure is worked out from the per-match average', () {
    final h = usage(
      perMatch: [
        {'stat': stat('4', '对英雄伤害量'), 'value': 5000.0},
        {'stat': stat('99', '累计游戏时间'), 'value': 600.0},
      ],
    );
    final damage = HeroStats.rows(
      h,
      catalog,
      const [],
    ).firstWhere((r) => r.name == '对英雄伤害量');
    expect(
      damage.per10,
      closeTo(5000, 0.01),
    ); // 5000 per 600 s = 5000 per 10 min
    expect(damage.per10Source, StatSource.derived);
  });

  test('the provider figure is kept when it exists', () {
    final kills = HeroStats.rows(
      usage(),
      catalog,
      const [],
    ).firstWhere((r) => r.name == '消灭');
    expect(kills.per10, 20);
    expect(kills.per10Source, StatSource.provider);
  });

  test('recent matches fill a per-match stat the provider left out', () {
    final kills = HeroStats.rows(usage(), catalog, [
      match(6),
      match(10),
    ]).firstWhere((r) => r.name == '消灭');
    expect(kills.perMatch, 8);
    expect(kills.perMatchSource, StatSource.recent);
  });

  test(
    'mitigation: tanks always have a figure, others only when matches show it',
    () {
      final h = usage();
      expect(HeroStats.mitigation10(h, catalog, const []), 0);
      final support = Catalog({
        'heroes': {
          _hero: {'name': '测试', 'role': 'healer'},
        },
      });
      expect(HeroStats.mitigation10(h, support, const []), isNull);
      expect(
        HeroStats.mitigation10(h, support, [match(5)]),
        closeTo(3000, 0.01),
      );
      expect(heroRef.guid, _hero);
    },
  );
}
