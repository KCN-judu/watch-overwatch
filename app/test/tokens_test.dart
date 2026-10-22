import 'dart:ui' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_overwatch/design/tokens.dart';

void main() {
  for (final entry in {
    'dark': AppColors.dark,
    'light': AppColors.light,
  }.entries) {
    test(
      '${entry.key}: every text token reaches 4.5:1 on every surface it can sit on',
      () {
        final failures = <String>[];
        for (final (name, fg, bg) in entry.value.textPairs()) {
          final r = contrastRatio(fg, bg);
          if (r < 4.5) failures.add('$name = ${r.toStringAsFixed(2)}');
        }
        expect(failures, isEmpty);
      },
    );

    test(
      '${entry.key}: focus, selection and data marks reach 3:1 on the raised surface',
      () {
        final c = entry.value;
        expect(contrastRatio(c.accent, c.raised), greaterThanOrEqualTo(3));
        expect(contrastRatio(c.ally, c.raised), greaterThanOrEqualTo(3));
        expect(contrastRatio(c.enemy, c.raised), greaterThanOrEqualTo(3));
      },
    );

    test(
      '${entry.key}: win and loss are different colours (they also carry ✓/✕ and a text label)',
      () {
        final c = entry.value;
        expect(c.win, isNot(c.loss));
      },
    );
  }

  test('a hero colour too close to the page is moved just far enough', () {
    const page = Color(0xFF12141A);
    const dim = Color(0xFF2A3550);
    final text = legibleOn(dim, page);
    expect(contrastRatio(text, page), greaterThanOrEqualTo(4.5));
    // Already readable: unchanged.
    const bright = Color(0xFFF0C040);
    expect(legibleOn(bright, page), bright);
    expect(
      contrastRatio(legibleOn(dim, page, ratio: 3), page),
      greaterThanOrEqualTo(3),
    );
  });
}
