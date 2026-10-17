import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/models.dart';
import '../core/support.dart';
import '../design/tokens.dart';
import 'match_view.dart';
import '../core/image_store.dart';

/// One async value with its last good result kept while a refresh runs or fails.
class Load<T> {
  T? value;
  ApiError? error;
  bool loading = false;
  DateTime? at;
  bool get has => value != null;
  bool get firstLoad => loading && value == null;
  bool get failedWithoutData => error != null && value == null;
}

enum BackendStatus { starting, ready, offline }

const tabIds = ['matches', 'heroes', 'strength', 'trend', 'profile'];
const tabLabels = {
  'matches': '对局',
  'heroes': '英雄',
  'strength': '对局强度',
  'trend': '赛季走势',
  'profile': '档案',
};

/// Everything about one queried player. Kept alive while the app runs so that
/// switching away and back restores scroll position, filters, sort and the open match.
class PlayerWorkspace extends ChangeNotifier {
  PlayerWorkspace(this.app, this.name);
  final AppState app;
  String name;

  String? _session;
  Json? identity;

  final matches = <Mode, Load<PlayerDataset>>{};
  final competitive = Load<CareerSnapshot>();
  final trend = <Mode, Load<List<SeasonPoint>>>{};
  final strength = <Mode, Load<StrengthResult>>{};
  final _strengthCancel = <Mode, CancelToken>{};

  /// Latest progress of a running analysis, per mode.
  final strengthProgress = <Mode, AnalysisProgress>{};
  final details = <String, Load<MatchDetail>>{};
  final pages = <Mode, int>{};
  final filters = <Mode, MatchFilters>{};
  final strengthDetails = <Mode, int>{};

  String sortId = 'time';
  bool sortAscending = false;
  final scroll = ScrollController();

  /// The row the user last selected, by match id so it survives re-sorting and tab changes.
  String? activeMatchId;

  /// Hero open in its detail page (`queue|guid`) and the table order it was opened from.
  String? openHeroKey;
  List<String> heroNavKeys = const [];
  static String heroKey(HeroUsage h) => '${h.queue.id}|${h.hero.guid}';

  void openHero(HeroUsage h, List<HeroUsage> ordered) {
    openHeroKey = heroKey(h);
    heroNavKeys = [for (final x in ordered) heroKey(x)];
    notifyListeners();
  }

  void closeHero() {
    openHeroKey = null;
    notifyListeners();
  }

  void stepHero(int delta) {
    final i = heroNavKeys.indexOf(openHeroKey ?? '');
    final j = i + delta;
    if (i < 0 || j < 0 || j >= heroNavKeys.length) return;
    openHeroKey = heroNavKeys[j];
    notifyListeners();
  }

  /// Match open in the detail page, and the visible order it was opened from.
  String? openMatchId;
  Mode? openMatchMode;
  List<String> navIds = const [];

  Load<PlayerDataset> matchesFor(Mode m) => matches.putIfAbsent(m, Load.new);
  Load<List<SeasonPoint>> trendFor(Mode m) => trend.putIfAbsent(m, Load.new);
  Load<StrengthResult> strengthFor(Mode m) => strength.putIfAbsent(m, Load.new);
  MatchFilters filtersFor(Mode m) => filters.putIfAbsent(m, MatchFilters.new);
  int pagesFor(Mode m) => pages[m] ?? 3;
  int strengthCount(Mode m) => strengthDetails[m] ?? 10;

  /// Most played hero across the loaded matches, standing in for a missing avatar.
  EntityRef? get topHero {
    final counts = <String, int>{};
    final heroes = <String, EntityRef>{};
    for (final l in matches.values) {
      for (final m in l.value?.matches ?? const <MatchSummary>[]) {
        final h = m.hero;
        if (h == null) continue;
        counts[h.guid] = (counts[h.guid] ?? 0) + 1;
        heroes[h.guid] = h;
      }
    }
    if (counts.isEmpty) return null;
    final best = counts.entries.reduce((a, b) => b.value > a.value ? b : a);
    return heroes[best.key];
  }

  PlayerProfile? get profile {
    for (final l in matches.values) {
      if (l.value != null) return l.value!.profile;
    }
    return null;
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  void touch() => notifyListeners();

  // ---- Session ---------------------------------------------------------------

  Future<String> ensureSession() async {
    if (_session != null) return _session!;
    final r = await app.api.search(name);
    _session = r.session;
    identity = r.identity;
    final canonical = r.identity['name'];
    if (canonical is String && canonical.isNotEmpty) name = canonical;
    return _session!;
  }

  Future<R> _call<R>(Future<R> Function(String session) f) async {
    var s = await ensureSession();
    try {
      return await f(s);
    } on ApiError catch (e) {
      if (!e.isExpiredSession) rethrow;
      _session = null;
      s = await ensureSession();
      return f(s);
    }
  }

  Future<void> _run<T>(Load<T> l, Future<T> Function() f) async {
    if (l.loading) return;
    l.loading = true;
    l.error = null;
    notifyListeners();
    try {
      l.value = await f();
      l.at = DateTime.now();
    } on Cancelled {
      // The user cancelled; keep whatever was there.
    } on ApiError catch (e) {
      l.error = e;
    } finally {
      l.loading = false;
      notifyListeners();
    }
  }

  // ---- Loads -----------------------------------------------------------------

  Future<void> loadMatches(Mode mode, {bool fresh = false}) => _run(
    matchesFor(mode),
    () => _call(
      (s) => app.api.dataset(s, mode, pages: pagesFor(mode), fresh: fresh),
    ),
  );

  Future<void> loadMore(Mode mode) {
    pages[mode] = (pagesFor(mode) + 2).clamp(1, 20);
    return loadMatches(mode, fresh: false);
  }

  Future<void> loadCompetitive({bool fresh = false}) => _run(
    competitive,
    () => _call((s) => app.api.career(s, Mode.competitive, fresh: fresh)),
  );

  Future<void> loadTrend(Mode mode, {bool fresh = false}) => _run(
    trendFor(mode),
    () => _call(
      (s) => app.api.trend(
        s,
        mode,
        endSeason: app.currentSeason,
        count: 6,
        fresh: fresh,
      ),
    ),
  );

  Future<void> runStrength(Mode mode, {bool fresh = false}) async {
    final token = CancelToken();
    _strengthCancel[mode] = token;
    final id =
        '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${mode.id}';
    strengthProgress.remove(mode);
    String? lastPhase;
    DateTime? since;
    var polling = false;
    // Ask the service how far it is while the single long request runs.
    final timer = Timer.periodic(const Duration(milliseconds: 600), (_) async {
      if (polling) return;
      polling = true;
      try {
        final j = await app.api.progress(id);
        if (j == null) return;
        final phase = (j['progress'] as Map?)?['phase'] as String?;
        if (phase != lastPhase) {
          lastPhase = phase;
          since = DateTime.now();
        }
        strengthProgress[mode] = AnalysisProgress(j, phaseSince: since);
        notifyListeners();
      } catch (_) {
        // Progress is a nicety; the analysis itself reports real errors.
      } finally {
        polling = false;
      }
    });
    try {
      await _run(
        strengthFor(mode),
        () => _call(
          (s) => app.api.strength(
            s,
            mode,
            perRole: strengthCount(mode),
            fresh: fresh,
            progressId: id,
            cancel: token,
          ),
        ),
      );
    } finally {
      timer.cancel();
      strengthProgress.remove(mode);
      notifyListeners();
    }
  }

  void cancelStrength(Mode mode) {
    _strengthCancel[mode]?.cancel();
  }

  void setStrengthCount(Mode mode, int n) {
    strengthDetails[mode] = n;
    notifyListeners();
  }

  Future<void> loadDetail(Mode mode, String id) => _run(
    details.putIfAbsent('${mode.id}:$id', Load.new),
    () => _call((s) => app.api.detail(s, mode, id)),
  );

  Load<MatchDetail> detailFor(Mode mode, String id) =>
      details.putIfAbsent('${mode.id}:$id', Load.new);

  // ---- Navigation inside the workspace ------------------------------------------

  void openMatch(Mode mode, String id, List<String> orderedIds) {
    openMatchId = id;
    activeMatchId = id;
    openMatchMode = mode;
    navIds = orderedIds;
    notifyListeners();
    loadDetail(mode, id);
  }

  void closeMatch() {
    openMatchId = null;
    notifyListeners();
  }

  /// Step to the previous (-1) or next (+1) match in the order the detail was opened from.
  void stepMatch(int delta) {
    final id = openMatchId, mode = openMatchMode;
    if (id == null || mode == null) return;
    final i = navIds.indexOf(id);
    if (i < 0) return;
    final j = i + delta;
    if (j < 0 || j >= navIds.length) return;
    openMatchId = navIds[j];
    activeMatchId = navIds[j];
    notifyListeners();
    loadDetail(mode, navIds[j]);
  }
}

class AppState extends ChangeNotifier {
  AppState(this.backend, this.ui)
    : mode = Mode.parse(ui.mode),
      tab = tabIds.contains(ui.tab) ? ui.tab : 'matches',
      density = DensityMode.parse(ui.density),
      themeMode =
          {'light': ThemeMode.light, 'dark': ThemeMode.dark}[ui.theme] ??
          ThemeMode.system,
      navWidth = ui.navWidth,
      navCollapsed = ui.navCollapsed;

  final Backend backend;
  final UiState ui;
  Api get api => backend.api;

  BackendStatus status = BackendStatus.starting;
  String? backendError;
  Catalog catalog = Catalog(null);
  Json? server;
  List<String> players = [];
  final workspaces = <String, PlayerWorkspace>{};
  PlayerWorkspace? current;

  Mode mode;
  String tab;
  DensityMode density;
  ThemeMode themeMode;
  double navWidth;
  bool navCollapsed;

  bool settingsOpen = false;
  bool searching = false;
  ApiError? searchError;
  String? lastExportPath;
  bool exporting = false;
  CancelToken? _exportCancel;

  /// Shell hooks.
  void Function(String message, {String? actionLabel, VoidCallback? action})?
  toast;
  VoidCallback? focusSearch;

  int get currentSeason => (server?['current_season'] as num?)?.toInt() ?? 25;
  List<Json> get accounts => [
    for (final a in (server?['accounts'] as List? ?? const []))
      (a as Map).cast<String, dynamic>(),
  ];
  List<Json> get metrics => [
    for (final a in (server?['metrics'] as List? ?? const []))
      (a as Map).cast<String, dynamic>(),
  ];
  bool get noAccount => server != null && accounts.isEmpty;
  bool get anyAccountReady => accounts.any((a) => a['status'] == 'ready');

  // ---- Boot -------------------------------------------------------------------

  Future<void> boot() async {
    status = BackendStatus.starting;
    backendError = null;
    notifyListeners();
    if (!await backend.ensureRunning()) {
      status = BackendStatus.offline;
      backendError = backend.lastLaunchError ?? '无法连接本地服务。';
      notifyListeners();
      return;
    }
    status = BackendStatus.ready;
    notifyListeners();
    try {
      players = await api.players();
      catalog = Catalog(await api.catalog());
      // Fill the picture cache in the background; screens show skeletons until then.
      unawaited(ImageStore.instance.preload(catalog.preloadUrls()));
      await refreshServer();
    } on ApiError catch (e) {
      status = BackendStatus.offline;
      backendError = e.message;
    }
    notifyListeners();
    final last = ui.lastPlayer;
    if (last != null &&
        players.any((p) => p.toLowerCase() == last.toLowerCase())) {
      await selectPlayer(
        players.firstWhere((p) => p.toLowerCase() == last.toLowerCase()),
      );
    }
  }

  Future<void> refreshServer() async {
    try {
      server = await api.state();
    } on ApiError {
      // Status bar shows the connection state; keep the last known account list.
    }
    notifyListeners();
  }

  void clearSearchError() {
    if (searchError == null) return;
    searchError = null;
    notifyListeners();
  }

  void showSettings(bool open) {
    settingsOpen = open;
    notifyListeners();
    if (open) refreshServer();
  }

  // ---- Players -----------------------------------------------------------------

  PlayerWorkspace _workspace(String name) => workspaces.putIfAbsent(
    name.toLowerCase(),
    () => PlayerWorkspace(this, name),
  );

  /// Looks the player up, adds them to the library on success and opens them.
  Future<bool> openPlayer(String raw) async {
    final name = raw.trim().replaceAll('＃', '#');
    if (name.isEmpty) return false;
    searching = true;
    searchError = null;
    notifyListeners();
    final ws = _workspace(name);
    try {
      await ws.ensureSession();
      final canonical = ws.name;
      players = await api.savePlayer(canonical);
      workspaces[canonical.toLowerCase()] = ws;
      searching = false;
      await selectPlayer(canonical);
      return true;
    } on ApiError catch (e) {
      searchError = e;
      workspaces.remove(name.toLowerCase());
      searching = false;
      notifyListeners();
      if (e.isAuth) await refreshServer();
      return false;
    }
  }

  Future<void> selectPlayer(String name) async {
    final ws = _workspace(name);
    current = ws;
    settingsOpen = false;
    ui.lastPlayer = name;
    ui.save();
    notifyListeners();
    await ensureTabData();
  }

  Future<void> removePlayer(String name) async {
    try {
      players = await api.savePlayer(name, remove: true);
    } on ApiError catch (e) {
      toast?.call('无法移除 $name：${e.message}');
      return;
    }
    final wasCurrent = current?.name.toLowerCase() == name.toLowerCase();
    if (wasCurrent) {
      current = null;
      ui.lastPlayer = null;
      ui.save();
    }
    notifyListeners();
    // Removing from the library is cheap to reverse, so it is undone rather than confirmed.
    toast?.call(
      '已从玩家库移除 $name',
      actionLabel: '撤销',
      action: () async {
        try {
          players = await api.savePlayer(name);
          notifyListeners();
          if (wasCurrent) await selectPlayer(name);
        } on ApiError catch (e) {
          toast?.call('无法恢复 $name：${e.message}');
        }
      },
    );
  }

  // ---- View state ----------------------------------------------------------------

  Future<void> setMode(Mode m) async {
    if (m == mode) return;
    mode = m;
    ui.mode = m.id;
    ui.save();
    notifyListeners();
    await ensureTabData();
  }

  Future<void> setTab(String id) async {
    if (!tabIds.contains(id)) return;
    tab = id;
    ui.tab = id;
    ui.save();
    // Leaving the list for another tab keeps the open match; returning restores it.
    notifyListeners();
    await ensureTabData();
  }

  void setDensity(DensityMode d) {
    density = d;
    ui.density = d.id;
    ui.save();
    notifyListeners();
  }

  void setTheme(ThemeMode t) {
    themeMode = t;
    ui.theme =
        {ThemeMode.light: 'light', ThemeMode.dark: 'dark'}[t] ?? 'system';
    ui.save();
    notifyListeners();
  }

  void setNav({double? width, bool? collapsed}) {
    if (width != null) navWidth = width.clamp(180.0, 360.0);
    if (collapsed != null) navCollapsed = collapsed;
    ui.navWidth = navWidth;
    ui.navCollapsed = navCollapsed;
    ui.save();
    notifyListeners();
  }

  /// Loads whatever the current tab needs and has not loaded yet.
  Future<void> ensureTabData() async {
    final ws = current;
    if (ws == null) return;
    final jobs = <Future<void>>[];
    final m = ws.matchesFor(mode);
    if (!m.has && !m.loading) jobs.add(ws.loadMatches(mode));
    if (!ws.competitive.has && !ws.competitive.loading)
      jobs.add(ws.loadCompetitive());
    if (tab == 'trend') {
      final t = ws.trendFor(mode);
      if (!t.has && !t.loading) jobs.add(ws.loadTrend(mode));
    }
    await Future.wait(jobs);
  }

  /// Re-reads current data, bypassing the short server cache.
  Future<void> refreshCurrent() async {
    final ws = current;
    if (ws == null) return;
    final jobs = <Future<void>>[
      ws.loadMatches(mode, fresh: true),
      ws.loadCompetitive(fresh: true),
    ];
    if (tab == 'trend') jobs.add(ws.loadTrend(mode, fresh: true));
    if (tab == 'strength' && ws.strengthFor(mode).has)
      jobs.add(ws.runStrength(mode, fresh: true));
    await Future.wait(jobs);
  }

  // ---- Export ------------------------------------------------------------------

  Future<String?> exportDataset({
    required List<Mode> modes,
    required int pages,
    required int details,
    required bool lobby,
  }) async {
    final ws = current;
    if (ws == null || exporting) return null;
    exporting = true;
    _exportCancel = CancelToken();
    notifyListeners();
    try {
      final session = await ws.ensureSession();
      final content = await api.exportDataset(
        session,
        modes,
        pages: pages,
        details: details,
        lobby: lobby,
        cancel: _exportCancel,
      );
      final safe = ws.name.replaceAll('#', '-');
      final path = await api.saveExport('$safe-数据集', content);
      lastExportPath = path;
      toast?.call('数据集已保存：$path');
      return path;
    } on Cancelled {
      toast?.call('已取消导出，没有写入文件。');
      return null;
    } on ApiError catch (e) {
      toast?.call('导出失败：${e.message}');
      return null;
    } finally {
      exporting = false;
      _exportCancel = null;
      notifyListeners();
    }
  }

  void cancelExport() => _exportCancel?.cancel();

  @override
  void dispose() {
    backend.stop();
    for (final w in workspaces.values) {
      w.dispose();
    }
    super.dispose();
  }
}

/// Provides [AppState] to the tree.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
    : super(notifier: state);
  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
  static AppState read(BuildContext context) =>
      (context.getElementForInheritedWidgetOfExactType<AppScope>()!.widget
              as AppScope)
          .notifier!;
}
