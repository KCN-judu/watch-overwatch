import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:watch_overwatch/core/metric_doc.dart';

void main() {
  test(
    'every metrics-page link the app has lands on a section of the page',
    () {
      final page = File('../docs/metrics.md').readAsStringSync();
      for (final d in MetricDoc.values) {
        expect(page, contains('<a id="${d.anchor}"></a>'), reason: d.name);
      }
    },
  );
}
