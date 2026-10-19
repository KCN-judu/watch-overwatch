import 'package:flutter_test/flutter_test.dart';
import 'package:watch_overwatch/core/models.dart';

Map<String, dynamic> growth(String trend, double older, double newer) => {
  'matches': 9,
  'older_mean': older,
  'newer_mean': newer,
  'change': newer - older,
  'change_pct': (newer - older) / older * 100,
  'slope_per_match': 2.5,
  'p': 0.02,
  'trend': trend,
};

void main() {
  final json = {
    'enabled': true,
    'listed': 12,
    'stored': 10,
    'report': {
      'skipped': 1,
      'points': [
        {
          'match_id': 'a',
          'started_at_ms': 1000,
          'role': 'support',
          'outcome': 'win',
          'duration_s': 300.0,
          'deaths': 1.0,
          'life_s': 300.0,
          'deathless': false,
          'fleta': 40.0,
          'kda': 10.0,
        },
        {
          'match_id': 'b',
          'started_at_ms': 2000,
          'role': 'tank',
          'outcome': 'loss',
          'duration_s': 600.0,
          'deaths': 0.0,
          'life_s': 600.0,
          'deathless': true,
        },
      ],
      'metrics': [
        {
          'metric': 'life',
          'matches': 2,
          'mean': 450.0,
          'growth': growth('up', 80, 100),
          'by_role': [
            {
              'role': 'support',
              'matches': 9,
              'mean': 90.0,
              'growth': growth('flat', 70, 71),
            },
            {'role': 'tank', 'matches': 3, 'mean': 60.0},
          ],
        },
      ],
    },
  };

  test('a growth answer reads into points and each measure\'s trend', () {
    final r = GrowthResult(json);
    expect(r.listed, 12);
    expect(r.stored, 10);
    expect(r.skipped, 1);
    expect(r.points, hasLength(2));
    expect(r.points.first.lifeS, 300);
    expect(r.points.first.deathless, isFalse);
    expect(r.points.last.deathless, isTrue);
    // A figure the service left out stays missing, not zero.
    expect(r.points.last.fleta, isNull);
    expect(r.points.last.kda, isNull);
    final life = r.metric(GrowthMetric.life)!;
    expect(life.growthFor(null)!.trend, Trend.up);
    expect(life.growthFor(Role.support)!.trend, Trend.flat);
    // A role with too few matches has no trend, not a flat one.
    expect(life.growthFor(Role.tank), isNull);
    expect(r.metric(GrowthMetric.kda), isNull);
    expect(r.roles, [Role.tank, Role.support]);
  });

  test(
    'an answer from a service without a local store is empty, not an error',
    () {
      final r = GrowthResult({'enabled': false});
      expect(r.enabled, isFalse);
      expect(r.points, isEmpty);
      expect(r.metrics, isEmpty);
    },
  );
}
