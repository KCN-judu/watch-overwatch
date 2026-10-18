import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/export_file.dart';
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

  /// Which role the next analysis covers (`null` = all three), per mode, and which the
  /// result on screen covers.
  final strengthScope = <Mode, Role?>{};
  final strengthRanScope = <Mode, Role?>{};
  Role? scopeFor(Mode m) => strengthScope[m];
  void setStrengthScope(Mode m, Role? r) {
    strengthScope[m] = r;
    notifyListeners();
  }

  final details = <String, Load<MatchDetail>>{};
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
    _closed = true;
    scroll.dispose();
    super.dispose();
  }

  bool _closed = false;

  /// Matches of a mode still waiting for their players' ranks to be looked up in the
  /// background; absent when nothing is running.
  final prepareRemaining = <Mode, int>{};
  final _preparing = <Mode>{};

  /// Looks the ranks up for the newest matches a few at a time, after the list has been
  /// updated, so that the strength analysis (and a match's detail) later only has to
  /// compute. It waits while an analysis runs, and stops when a batch makes no progress.
  Future<void> prepareInBackground(Mode mode) async {
    if (mode == Mode.stadium || _closed || !_preparing.add(mode)) return;
    try {
      var last = -1;
      while (!_closed) {
        if (strengthFor(mode).loading) {
          await Future<void>.delayed(const Duration(seconds: 2));
          continue;
        }
        // Every match of the list, newest first: the strength analysis can reach any of
        // them (older ones when a role has too few), and a match's detail shows ranks too.
        final r = await _call((s) => app.api.prepare(s, mode, window: 300));
        if (!r.enabled || r.remaining == 0) break;
        prepareRemaining[mode] = r.remaining;
        notifyListeners();
        // A batch that left as many waiting as before could not be prepared: stop.
        if (last != -1 && r.remaining >= last) break;
        last = r.remaining;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    } on ApiError {
      // A nicety: whatever is missing is looked up when it is needed.
    } finally {
      _preparing.remove(mode);
      prepareRemaining.remove(mode);
      if (!_closed) notifyListeners();
    }
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

  final _listSync = <Mode, Future<void>>{};

  /// Reads the match list into the service's local store and shows it: matches newer than
  /// the newest stored first, then older ones until each of [roles] has [quota] matches
  /// (the whole history when [quota] is null). The list on screen grows as it goes.
  /// Reads queue up per mode, so a later one sees what an earlier one stored; [fresh]
  /// asks the upstream again for the newest page instead of reusing a recent answer.
  Future<void> loadMatches(
    Mode mode, {
    bool fresh = false,
    int? quota,
    Iterable<Role> roles = const [],
  }) {
    final next = (_listSync[mode] ?? Future<void>.value()).then(
      (_) => _readList(mode, fresh, quota, roles),
    );
    _listSync[mode] = next;
    return next;
  }

  /// Whether [read] holds [quota] matches of each of [roles] (all three when empty).
  static bool quotaMet(
    List<MatchSummary> read,
    int quota,
    Iterable<Role> roles,
  ) {
    final wanted = roles.isEmpty ? Role.playable : roles;
    return wanted.every((r) => read.where((m) => m.role == r).length >= quota);
  }

  /// Whether the stored list is known to reach the player's oldest match.
  bool listExhausted(Mode mode) =>
      matchesFor(
        mode,
      ).value?.coverage.matchLists.any((l) => l.mode == mode && l.exhausted) ??
      false;

  Future<void> _readList(
    Mode mode,
    bool fresh,
    int? quota,
    Iterable<Role> roles,
  ) async {
    final l = matchesFor(mode);
    final shown = l.value?.matches ?? const <MatchSummary>[];
    if (!fresh &&
        l.has &&
        (listExhausted(mode) ||
            (quota != null && quotaMet(shown, quota, roles)))) {
      return;
    }
    l.loading = true;
    l.error = null;
    notifyListeners();
    try {
      var first = true;
      while (true) {
        final before = l.value?.matches.length ?? 0;
        final ds = await _call(
          (s) => app.api.dataset(
            s,
            mode,
            fresh: fresh && first,
            quota: quota,
            roles: roles,
          ),
        );
        l.value = ds;
        l.at = DateTime.now();
        notifyListeners();
        final cover = ds.coverage.matchLists
            .where((c) => c.mode == mode)
            .firstOrNull;
        if (cover == null || cover.exhausted) break;
        if (quota != null && quotaMet(ds.matches, quota, roles)) break;
        // A call that added nothing would only repeat itself.
        if (!first && ds.matches.length <= before) break;
        first = false;
      }
    } on Cancelled {
      // Keep what was there.
    } on ApiError catch (e) {
      l.error = e;
    } finally {
      l.loading = false;
      notifyListeners();
    }
    // The list is up to date: get the new matches' players looked up while it is quiet.
    if (l.has && l.error == null) unawaited(prepareInBackground(mode));
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

  /// What the strength analysis is doing before the service starts (reading more of the
  /// match list), and how many matches it chose.
  final strengthStatus = <Mode, String>{};
  final strengthSelected = <Mode, int>{};

  /// The newest [n] matches of each of [roles] among the matches already read.
  static List<MatchSummary> pickPerRole(
    List<MatchSummary> read,
    int n,
    Iterable<Role> roles,
  ) {
    final taken = <Role, int>{};
    return [
      for (final m in read)
        if (roles.contains(m.role) &&
            (taken[m.role] = (taken[m.role] ?? 0) + 1) <= n)
          m,
    ];
  }

  Future<void> runStrength(Mode mode, {bool fresh = false}) async {
    final scope = strengthScope[mode];
    final roles = scope == null ? Role.playable : [scope];
    final n = strengthCount(mode);
    final result = strengthFor(mode);
    // A run already going keeps its cancel token and progress; a second request is ignored.
    if (result.loading) return;
    final before = result.at;
    final token = CancelToken();
    _strengthCancel[mode] = token;
    strengthProgress.remove(mode);
    strengthSelected.remove(mode);
    result.loading = true;
    result.error = null;
    strengthStatus[mode] = '正在读取对局…';
    notifyListeners();

    StrengthResult? latest;
    ApiError? failure;
    try {
      // Look at the newest page first: anything newer than what the local store holds is
      // added to it, then the list is read back until each role has [n] matches (older
      // ones come from the store). The analysis picks its matches from that list.
      await loadMatches(mode, fresh: true, quota: n, roles: roles);

      // Analyse the newest [n] matches of each role. A match in which nobody can be
      // rated drops out of the result, so when a role ends up with fewer than [n]
      // analysable matches, take a few more from the read list and go again: matches
      // already looked up come from the cache, so a further round is cheap. Only when
      // the read list has no more of that role is more of the list read.
      final take = {for (final r in roles) r: n};
      var rounds = 0;
      while (!token.cancelled && rounds < 8) {
        rounds++;
        final read = matchesFor(mode).value?.matches ?? const <MatchSummary>[];
        final ids = <String>{
          for (final r in roles)
            ...read.where((m) => m.role == r).take(take[r]!).map((m) => m.id),
        };
        final chosen = [
          for (final m in read)
            if (ids.contains(m.id)) m,
        ];
        strengthSelected[mode] = chosen.length;
        if (chosen.isEmpty) {
          // The whole history holds none of these roles: show the empty answer, do not ask
          // the service to go and find matches on its own.
          latest = StrengthResult(const {});
          break;
        }

        strengthStatus[mode] = rounds == 1
            ? ''
            : '第 $rounds 轮：有对局没有可评定的玩家，再多取几场…';
        final id =
            '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${mode.id}';
        String? lastPhase;
        DateTime? since;
        var polling = false;
        // Ask the service how far it is while the single long request runs.
        final timer = Timer.periodic(const Duration(milliseconds: 600), (
          _,
        ) async {
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
        final StrengthResult r;
        try {
          r = await _call(
            (s) => app.api.strength(
              s,
              mode,
              perRole: n,
              role: scope,
              known: chosen,
              fresh: fresh && rounds == 1,
              progressId: id,
              cancel: token,
            ),
          );
        } on Cancelled {
          break;
        } on ApiError catch (e) {
          failure = e;
          break;
        } finally {
          timer.cancel();
          strengthProgress.remove(mode);
        }

        latest = r;
        // Which roles still lack analysable matches, and can take more?
        final got = r.lobby.matches.where((m) => m.hasData).toList();
        var extended = false;
        var stillShort = false;
        var wanted = 0;
        for (final r in roles) {
          final have = got.where((m) => m.subjectRole == r).length;
          final avail = read.where((m) => m.role == r).length;
          if (have >= n) continue;
          stillShort = true;
          final target = take[r]! + (n - have);
          wanted = math.max(wanted, target);
          if (take[r]! < avail) {
            take[r] = math.min(avail, target);
            extended = true;
          }
        }
        if (extended) continue;
        if (!stillShort || listExhausted(mode)) break;
        // Every stored match of the short role is already used: read older ones.
        strengthStatus[mode] = '对局不够，正在读取更早的对局…';
        notifyListeners();
        final had = read.length;
        await loadMatches(mode, quota: wanted, roles: roles);
        if ((matchesFor(mode).value?.matches.length ?? 0) <= had) break;
      }
    } finally {
      strengthStatus.remove(mode);
      strengthProgress.remove(mode);
      result.loading = false;
    }

    if (token.cancelled) {
      notifyListeners();
      return;
    }
    if (failure != null) {
      result.error = failure;
    } else if (latest != null) {
      result.value = latest;
      result.at = DateTime.now();
    }
    // The result on screen now covers the scope this run used.
    if (result.at != before) strengthRanScope[mode] = scope;
    notifyListeners();
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

  /// Shows the save dialog; replaced in tests.
  SavePicker pickSavePath = pickJsonSaveLocation;
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
    await refreshCacheStats();
    notifyListeners();
  }

  /// What the strength cache holds (`matches`, `players`, `bytes`); null when unknown.
  Json? cacheStats;

  Future<void> refreshCacheStats() async {
    try {
      cacheStats = await api.cacheStats();
    } on ApiError {
      cacheStats = null;
    }
    notifyListeners();
  }

  Future<void> clearStrengthCache() async {
    try {
      cacheStats = await api.clearCache();
      toast?.call('已清除强度缓存');
    } on ApiError catch (e) {
      toast?.call('无法清除缓存：${e.message}');
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
    // The refresh button only looks for new matches. Looking every player's rank up
    // again is a few hundred requests, so it stays with "强制刷新" on the strength page.
    if (tab == 'strength' && ws.strengthFor(mode).has) {
      jobs.add(ws.runStrength(mode));
    }
    await Future.wait(jobs);
  }

  // ---- Export ------------------------------------------------------------------

  /// What the export is doing right now (shown beside the cancel button).
  String? exportStatus;

  /// Exports the newest [count] matches of each of [modes] (all when null), each with its
  /// detail, and with the players' ranks when [ratings]. Where the file goes is asked
  /// first; then each mode's list is read as far as needed and its matches are prepared in
  /// small batches (what is already kept locally is not read again); the file is written
  /// last.
  Future<String?> exportDataset({
    required List<Mode> modes,
    required int? count,
    required bool ratings,
  }) async {
    final ws = current;
    if (ws == null || exporting) return null;
    exporting = true;
    final token = _exportCancel = CancelToken();
    exportStatus = '请选择保存位置…';
    notifyListeners();
    try {
      // Asked before the long read so a cancelled dialog costs nothing.
      final safe = ws.name.replaceAll('#', '-');
      final path = await pickSavePath('$safe-数据集.json');
      if (path == null) return null;
      for (final mode in modes) {
        await _exportReadList(ws, mode, count, token);
        await _exportPrepare(ws, mode, count, ratings, token);
      }
      exportStatus = '正在整理导出内容…';
      notifyListeners();
      final session = await ws.ensureSession();
      final content = await api.exportDataset(
        session,
        modes,
        count: count,
        ratings: ratings,
        cancel: token,
      );
      await writeJsonFile(path, content);
      lastExportPath = path;
      toast?.call('数据集已保存：$path');
      return path;
    } on Cancelled {
      toast?.call('已取消导出，没有写入文件。');
      return null;
    } on FileSystemException {
      toast?.call('无法保存到所选位置。请换一个文件夹，并检查权限和剩余空间。');
      return null;
    } on ApiError catch (e) {
      toast?.call('导出失败：${e.message}');
      return null;
    } finally {
      exporting = false;
      exportStatus = null;
      _exportCancel = null;
      notifyListeners();
    }
  }

  /// Reads the list of [mode] into the local store until it holds [count] matches (all of
  /// them when null) or has reached the oldest.
  Future<void> _exportReadList(
    PlayerWorkspace ws,
    Mode mode,
    int? count,
    CancelToken token,
  ) async {
    var first = true;
    var seen = 0;
    while (!token.cancelled) {
      exportStatus =
          '读取${mode.shortLabel}对局列表${seen > 0 ? '（已读 $seen 场）' : ''}…';
      notifyListeners();
      final ds = await ws._call(
        (s) => api.dataset(s, mode, fresh: first, cancel: token),
      );
      first = false;
      final cover = ds.coverage.matchLists
          .where((c) => c.mode == mode)
          .firstOrNull;
      if (cover == null || cover.exhausted) return;
      if (count != null && ds.matches.length >= count) return;
      if (ds.matches.length <= seen) return;
      seen = ds.matches.length;
    }
    throw Cancelled();
  }

  /// Has each of the newest [count] matches of [mode] read in (with the players' ranks
  /// when [ratings]), a few at a time, so that the export itself finds everything ready.
  Future<void> _exportPrepare(
    PlayerWorkspace ws,
    Mode mode,
    int? count,
    bool ratings,
    CancelToken token,
  ) async {
    // Stadium has no lobby ranks; its matches are only read in.
    final withRanks = ratings && mode != Mode.stadium;
    var last = -1;
    while (!token.cancelled) {
      final r = await ws._call(
        (s) => api.prepare(
          s,
          mode,
          window: count ?? 5000,
          batch: 5,
          ratings: withRanks,
          cancel: token,
        ),
      );
      if (!r.enabled) return;
      exportStatus =
          '准备${mode.shortLabel}对局数据 ${r.total - r.remaining}/${r.total}…';
      notifyListeners();
      if (r.remaining == 0) return;
      // A batch that left as many waiting as before could not be prepared: go on without.
      if (last != -1 && r.remaining >= last) return;
      last = r.remaining;
    }
    throw Cancelled();
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
