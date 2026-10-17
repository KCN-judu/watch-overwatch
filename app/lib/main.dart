import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/api.dart';
import 'core/support.dart';
import 'design/tokens.dart';
import 'state/app_state.dart';
import 'ui/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Many small pictures and a few large ones; keep them decoded across tab switches.
  PaintingBinding.instance.imageCache
    ..maximumSize = 4000
    ..maximumSizeBytes = 600 << 20;
  // Read the saved appearance before the first frame so there is no theme flash.
  final saved = UiState.load();
  final app = AppState(Backend(), saved);
  runApp(WatchApp(app: app));
}

class WatchApp extends StatefulWidget {
  const WatchApp({super.key, required this.app});
  final AppState app;
  @override
  State<WatchApp> createState() => _WatchAppState();
}

class _WatchAppState extends State<WatchApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // The local service is ours: stop it with the window.
    _lifecycle = AppLifecycleListener(
      onExitRequested: () async {
        widget.app.backend.stop();
        return ui.AppExitResponse.exit;
      },
      onDetach: widget.app.backend.stop,
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    widget.app.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: widget.app,
      child: Builder(
        builder: (context) {
          final app = AppScope.of(context);
          return DensityScope(
            density: app.density,
            child: MaterialApp(
              title: 'Watch Overwatch',
              debugShowCheckedModeBanner: false,
              themeMode: app.themeMode,
              theme: buildTheme(Brightness.light),
              darkTheme: buildTheme(Brightness.dark),
              locale: const Locale('zh', 'CN'),
              supportedLocales: const [Locale('zh', 'CN')],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: const Shell(),
            ),
          );
        },
      ),
    );
  }
}
