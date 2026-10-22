import 'dart:io';

/// A section of `docs/metrics.md`, the page that defines every figure the app shows.
/// The ids are the page's anchors; a test checks each one exists there.
enum MetricDoc {
  winRateRange('win-rate-range'),
  threshold('threshold'),
  confidence('confidence'),
  baseline('baseline'),
  life('life'),
  fleta('fleta'),
  kda('kda'),
  per10('per-10'),
  strength('strength'),
  percentile('percentile'),
  rating('rating'),
  net('net');

  const MetricDoc(this.anchor);
  final String anchor;

  static const page =
      'https://github.com/KCN-judu/watch-overwatch/blob/main/docs/metrics.md';
  String get url => '$page#$anchor';

  /// Opens the section in the system browser (the user clicked "口径说明").
  Future<void> open() async {
    // Never from a test run: that would open a real browser.
    if (!Platform.isWindows ||
        Platform.environment.containsKey('FLUTTER_TEST')) {
      return;
    }
    try {
      await Process.run('rundll32', ['url.dll,FileProtocolHandler', url]);
    } catch (_) {}
  }
}
