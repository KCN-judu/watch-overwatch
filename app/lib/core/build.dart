import 'package:flutter/foundation.dart';

/// Whether this build offers the sample player: development builds do, a release build
/// only when built with `--dart-define=WATCH_DEMO=true` (the published package does
/// not). Constant, so a release build leaves the sample's buttons out entirely. The
/// service has its own switch (`watch_core::DEMO_AVAILABLE`); the app asks both.
const demoBuild = bool.fromEnvironment(
  'WATCH_DEMO',
  defaultValue: !kReleaseMode,
);
