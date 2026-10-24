import 'package:flutter_test/flutter_test.dart';
import 'package:watch_overwatch/core/models.dart';
import 'package:watch_overwatch/core/stats.dart';

void main() {
  test('Wilson range: the same values as the service (watch_core::stats)', () {
    final (lo, hi) = wilsonPct(8, 10)!;
    expect(lo, closeTo(49.0, 0.1));
    expect(hi, closeTo(94.3, 0.1));
    expect(wilsonPct(0, 5)!.$1, 0);
    expect(wilsonPct(5, 5)!.$2, 100);
    expect(wilsonPct(0, 0), isNull);
  });

  test('a small perfect record ranks below a large good one', () {
    expect(wilsonPct(7, 8)!.$1, lessThan(wilsonPct(43, 64)!.$1));
  });

  test(
    'the baseline is the middle half of the matches before, once there are 8',
    () {
      final values = <double?>[for (var i = 1; i <= 10; i++) i.toDouble()];
      final b = baselineBand(values);
      // Nothing to compare with for the first eight matches.
      expect(b.lows.take(8), everyElement(isNull));
      // Before the ninth: 1..8, quartiles 2.75 and 6.25.
      expect(b.lows[8], closeTo(2.75, 1e-9));
      expect(b.highs[8], closeTo(6.25, 1e-9));
      // A missing value is skipped, not counted as zero.
      final gaps = baselineBand([...values.take(8), null, 9.0]);
      expect(gaps.lows[9], closeTo(2.75, 1e-9));
    },
  );

  test('the window only looks back so far', () {
    final values = <double?>[for (var i = 0; i < 30; i++) i < 10 ? 1000 : 1];
    final b = baselineBand(values, window: 20);
    // By the last match the thousands are out of the window.
    expect(b.highs.last, 1);
  });

  test('confidence comes from the service', () {
    expect(Confidence.parse('firm'), Confidence.firm);
    expect(Confidence.parse('too_few'), Confidence.tooFew);
    expect(Confidence.parse(null), Confidence.none);
    expect(Confidence.firm.label, '显著');
  });
}
