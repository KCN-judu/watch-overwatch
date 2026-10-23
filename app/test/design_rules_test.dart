import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:watch_overwatch/design/tokens.dart';

/// Every Dart file under lib/, path relative to the app folder with `/` separators.
Map<String, String> sources() => {
  for (final f in Directory('lib').listSync(recursive: true))
    if (f is File && f.path.endsWith('.dart'))
      f.path.replaceAll(r'\', '/'): f.readAsStringSync(),
};

/// `file:line: text` for every line matching [pattern] outside [allowed] files.
List<String> offenders(RegExp pattern, Set<String> allowed) => [
  for (final MapEntry(key: path, value: text) in sources().entries)
    if (!allowed.contains(path))
      for (final (i, line) in text.split('\n').indexed)
        if (pattern.hasMatch(line) && !line.trimLeft().startsWith('//'))
          '$path:${i + 1}: ${line.trim()}',
];

// ---- Colour vision deficiency ------------------------------------------------------
// Machado, Oliveira & Fernandes (2009), severity 1, applied in linear RGB.

const _deutan = [
  [0.367322, 0.860646, -0.227968],
  [0.280085, 0.672501, 0.047413],
  [-0.011820, 0.042940, 0.968881],
];
const _protan = [
  [0.152286, 1.052583, -0.204868],
  [0.114503, 0.786281, 0.099216],
  [-0.003882, -0.048116, 1.051998],
];
const _tritan = [
  [1.255528, -0.076749, -0.178779],
  [-0.078411, 0.930809, 0.147602],
  [0.004733, 0.691367, 0.303900],
];

double _lin(double v) =>
    v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();

List<double> _simulate(Color c, List<List<double>> m) {
  final rgb = [_lin(c.r), _lin(c.g), _lin(c.b)];
  return [
    for (final row in m)
      (row[0] * rgb[0] + row[1] * rgb[1] + row[2] * rgb[2]).clamp(0.0, 1.0),
  ];
}

/// CIE L*a*b* of a linear-RGB triple (sRGB primaries, D65).
List<double> _lab(List<double> rgb) {
  final x = 0.4124 * rgb[0] + 0.3576 * rgb[1] + 0.1805 * rgb[2];
  final y = 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2];
  final z = 0.0193 * rgb[0] + 0.1192 * rgb[1] + 0.9505 * rgb[2];
  double f(double t) =>
      t > 0.008856 ? math.pow(t, 1 / 3).toDouble() : 7.787 * t + 16 / 116;
  final (fx, fy, fz) = (f(x / 0.95047), f(y), f(z / 1.08883));
  return [116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)];
}

/// CIE76 colour difference after simulating [m].
double distance(Color a, Color b, List<List<double>> m) {
  final (p, q) = (_lab(_simulate(a, m)), _lab(_simulate(b, m)));
  return math.sqrt(
    math.pow(p[0] - q[0], 2) +
        math.pow(p[1] - q[1], 2) +
        math.pow(p[2] - q[2], 2),
  );
}

void main() {
  test('colours come from AppColors, not from literals in pages', () {
    // gamedata.dart parses each hero's own colour from the game files.
    final found = offenders(RegExp(r'Color\(0x|\bColors\.(?!transparent)'), {
      'lib/design/tokens.dart',
      'lib/core/gamedata.dart',
    });
    expect(found, isEmpty);
  });

  test('wording comes from the string table (lib/l10n)', () {
    // The allowed files hold game and provider data (hero, map-mode and stat names
    // matched against upstream values), not wording.
    final found = offenders(RegExp(r"'[^']*[一-鿿][^']*'"), {
      for (final f in sources().keys)
        if (f.startsWith('lib/l10n/')) f,
      'lib/core/api.dart',
      'lib/core/gamedata.dart',
      'lib/core/hero_stats.dart',
      'lib/core/models.dart',
      'lib/core/support.dart',
      'lib/ui/pages/hero_detail_page.dart',
      'lib/ui/pages/heroes_page.dart',
    });
    expect(found, isEmpty);
  });

  test('spacing comes from the Sp scale', () {
    // A gap between things is a step of the scale; sizes of things (a card, a column)
    // are not spacing and may be any number.
    final found = offenders(
      RegExp(
        r'SizedBox\((?:width|height): (?:[1-9]|[12][0-9]|3[0-2])(?:\.0)?\)',
      ),
      {'lib/design/tokens.dart'},
    );
    expect(found, isEmpty);
  });

  test('every vertical scroll area leaves the scrollbar its lane', () {
    // A scroll view's arguments (the lines up to its first child) name scrollGutter,
    // or it does not scroll vertically / shows no bar.
    final opener = RegExp(
      r'\b(ListView|ListView\.builder|ListView\.separated|GridView\.builder|SingleChildScrollView)\(',
    );
    final found = <String>[];
    for (final MapEntry(key: path, value: text) in sources().entries) {
      final lines = text.split('\n');
      for (final (i, line) in lines.indexed) {
        final m = opener.firstMatch(line);
        if (m == null || line.trimLeft().startsWith('//')) continue;
        final args = [
          line.substring(m.start),
          ...lines.skip(i + 1).take(8),
        ].join('\n');
        final head = args
            .split(RegExp(r'\b(children|child|itemBuilder):'))
            .first;
        if (!RegExp(
          r'scrollGutter|NeverScrollableScrollPhysics|Axis\.horizontal|EdgeInsets\.all\(Sp\.page\)',
        ).hasMatch(head)) {
          found.add('$path:${i + 1}: ${line.trim()}');
        }
      }
    }
    expect(found, isEmpty, reason: found.join('\n'));
  });

  test('type sizes come from Ty', () {
    final found = offenders(RegExp(r'fontSize: \d'), {
      'lib/design/tokens.dart',
    });
    expect(found, isEmpty);
  });

  test('spinners and progress bars are the shared ones', () {
    final found = offenders(
      RegExp(r'CircularProgressIndicator|LinearProgressIndicator'),
      {'lib/design/widgets.dart'},
    );
    expect(found, isEmpty);
  });

  test('selection and focus are painted through ItemState', () {
    // A hand-made 2px accent ring is the sign of a widget drawing its own focus.
    final found = offenders(
      RegExp(r'Border\.all\(color: c\.accent, width: 2\)'),
      {'lib/design/interaction.dart'},
    );
    expect(found, isEmpty);
  });

  for (final MapEntry(key: theme, value: c) in {
    'dark': AppColors.dark,
    'light': AppColors.light,
  }.entries) {
    // Pairs that tell two series apart in one chart by colour, with the smallest CIE76
    // difference allowed. Ally and enemy rely on colour most (both are solid lines with
    // the same marks), so they need the most; the reference series is also dashed.
    final pairs = {
      'ally / enemy': (c.ally, c.enemy, 20.0),
      'main / reference series': (c.accent, c.textSecondary, 15.0),
    };
    for (final MapEntry(key: name, value: (a, b, min)) in pairs.entries) {
      for (final MapEntry(key: kind, value: m) in {
        'deuteranopia': _deutan,
        'protanopia': _protan,
        'tritanopia': _tritan,
      }.entries) {
        test('$theme: $name stay apart with $kind', () {
          expect(distance(a, b, m), greaterThanOrEqualTo(min));
        });
      }
    }
  }
}
