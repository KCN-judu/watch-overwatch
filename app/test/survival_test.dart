import 'package:flutter_test/flutter_test.dart';
import 'package:watch_overwatch/core/models.dart';

void main() {
  final json = {
    'enabled': true,
    'listed': 12,
    'stored': 10,
    'report': {
      'skipped': 1,
      'samples': [
        {
          'match_id': 'a',
          'started_at_ms': 1000,
          'role': 'support',
          'outcome': 'win',
          'duration_s': 600.0,
          'deaths': 3.0,
          'life_s': 150.0,
        },
      ],
      'growth': {
        'matches': 9,
        'older_mean_s': 80.0,
        'newer_mean_s': 100.0,
        'change_s': 20.0,
        'change_pct': 25.0,
        'slope_s_per_match': 2.5,
        'p': 0.02,
        'trend': 'longer',
      },
      'by_role': [
        {
          'role': 'support',
          'stat': {'matches': 9, 'mean_s': 90.0},
          'growth': {
            'matches': 9,
            'older_mean_s': 70.0,
            'newer_mean_s': 110.0,
            'change_s': 40.0,
            'change_pct': 57.0,
            'slope_s_per_match': 5.0,
            'p': 0.01,
            'trend': 'longer',
          },
        },
        {
          'role': 'tank',
          'stat': {'matches': 3, 'mean_s': 60.0},
        },
      ],
    },
  };

  test(
    'a survival answer reads into samples, overall growth and per-role growth',
    () {
      final r = SurvivalResult(json);
      expect(r.listed, 12);
      expect(r.stored, 10);
      expect(r.skipped, 1);
      expect(r.samples.single.lifeS, 150);
      expect(r.samples.single.outcome, Outcome.win);
      expect(r.growthFor(null)!.trend, LifeTrend.longer);
      expect(r.growthFor(null)!.newerMeanS, 100);
      expect(r.growthFor(Role.support)!.changeS, 40);
      // A role with too few matches has no growth, not a zero one.
      expect(r.growthFor(Role.tank), isNull);
      expect(r.growthFor(Role.damage), isNull);
    },
  );

  test(
    'an answer from a service without a local store is empty, not an error',
    () {
      final r = SurvivalResult({'enabled': false});
      expect(r.enabled, isFalse);
      expect(r.samples, isEmpty);
      expect(r.growthFor(null), isNull);
    },
  );
}
