import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/benchmark.dart';
import '../core/build.dart';
import '../core/daily.dart';
import '../core/maps.dart';
import '../core/people.dart';
import '../core/ranks.dart';
import '../core/stadium.dart';
import '../core/export_file.dart';
import '../core/models.dart';
import '../core/overview.dart';
import '../core/stats.dart';
import '../core/support.dart';
import '../core/update.dart';
import '../design/tokens.dart';
import '../l10n/strings.dart';
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

const tabIds = [
  'overview',
  'daily',
  'matches',
  'heroes',
  'maps',
  'strength',
  'people',
  'growth',
  'trend',
  'profile',
];
Map<String, String> get tabLabels => {
  'overview': tr.core.tabOverview,
  'daily': tr.core.tabDaily,
  'matches': tr.core.tabMatches,
  'heroes': tr.core.tabHeroes,
  'maps': tr.core.tabMaps,
  'strength': tr.core.tabStrength,
  'people': tr.core.tabPeople,
  'growth': tr.core.tabGrowth,
  'trend': tr.core.tabTrend,
  'profile': tr.core.tabProfile,
};

/// Everything about one queried player. Kept alive while the app runs so that
/// switching away and back restores scroll position, filters, sort and the open match.
class PlayerWorkspace extends ChangeNotifier {
  PlayerWorkspace(this.app, this.name);
  final AppState app;
  String name;

  String? _session;
  Json? identity;

  /// The lookup under way, shared by every load that needs a session meanwhile: at
  /// start several pages ask at once, and they wait for one lookup instead of each
  /// sending their own.
  Future<String>? _lookup;

  final matches = <Mode, Load<PlayerDataset>>{};
  final competitive = Load<CareerSnapshot>();
  final trend = <Mode, Load<List<SeasonPoint>>>{};
  final growth = <Mode, Load<GrowthResult>>{};
  final overview = <Mode, Load<OverviewResult>>{};
  final benchmark = <Mode, Load<BenchmarkResult>>{};
  final maps = <Mode, Load<MapsResult>>{};
  final daily = <Mode, Load<DailyResult>>{};

  /// The day the daily summary shows, per mode; null for the newest.
  final dailyDay = <Mode, String?>{};
  final people = <Mode, Load<PeopleResult>>{};
  final duos = <(Mode, String), Load<DuoResult>>{};
  final ranks = <Mode, Load<RanksResult>>{};
  final stadium = <BuildSample, Load<StadiumResult>>{};
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
    comparingHero = false;
    compareHeroKey = null;
    notifyListeners();
  }

  /// The open hero is being compared: with [compareHeroKey], or still picking one.
  bool comparingHero = false;
  String? compareHeroKey;

  void compareHero(String? key) {
    comparingHero = true;
    compareHeroKey = key;
    notifyListeners();
  }

  void closeHeroCompare() {
    comparingHero = false;
    compareHeroKey = null;
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
  Load<GrowthResult> growthFor(Mode m) => growth.putIfAbsent(m, Load.new);
  Load<OverviewResult> overviewFor(Mode m) => overview.putIfAbsent(m, Load.new);
  Load<MapsResult> mapsFor(Mode m) => maps.putIfAbsent(m, Load.new);
  Load<DailyResult> dailyFor(Mode m) => daily.putIfAbsent(m, Load.new);
  Load<PeopleResult> peopleFor(Mode m) => people.putIfAbsent(m, Load.new);
  Load<DuoResult> duoFor(Mode m, String key) =>
      duos.putIfAbsent((m, key), Load.new);
  Load<RanksResult> ranksFor(Mode m) => ranks.putIfAbsent(m, Load.new);
  Load<StadiumResult> stadiumFor(BuildSample s) =>
      stadium.putIfAbsent(s, Load.new);
  Load<BenchmarkResult> benchmarkFor(Mode m) =>
      benchmark.putIfAbsent(m, Load.new);
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

  /// The background rank job of each mode while it runs; absent when nothing does.
  final prepareJobs = <Mode, RankJob>{};
  final _preparing = <Mode>{};

  /// After the list has been updated, has the service take the rank snapshots of the
  /// newest matches in the background, and follows it: the job gives way to every other
  /// query and carries on by itself, so this only reads where it stands.
  Future<void> prepareInBackground(Mode mode) async {
    if (mode == Mode.stadium || _closed || !_preparing.add(mode)) return;
    try {
      RankJob? job = await _call<RankJob?>(
        (s) => app.api.startRankJob(s, mode),
      );
      while (!_closed && job != null && !job.finished) {
        prepareJobs[mode] = job;
        notifyListeners();
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        job = await _call<RankJob?>((s) => app.api.rankJob(s, mode));
      }
    } on ApiError {
      // A nicety: whatever is missing is looked up when it is needed.
    } finally {
      _preparing.remove(mode);
      prepareJobs.remove(mode);
      if (!_closed) notifyListeners();
    }
  }

  void touch() => notifyListeners();

  // ---- Session ---------------------------------------------------------------

  Future<String> ensureSession() {
    if (_session != null) return Future.value(_session!);
    return _lookup ??= _lookUp().whenComplete(() => _lookup = null);
  }

  Future<String> _lookUp() async {
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
    // The overview is worked out from the stored list: follow it when it changes.
    unawaited(
      next.then((_) {
        if (app.current != this || app.mode != mode) return null;
        if (app.tab == 'overview') return loadOverview(mode);
        if (app.tab == 'maps') return loadMaps(mode);
        if (app.tab == 'daily') return loadDaily(mode);
        return null;
      }),
    );
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

  /// When each mode's list was last read from the upstream's newest page.
  final _newestChecked = <Mode, DateTime>{};

  Future<void> _readList(
    Mode mode,
    bool requestedFresh,
    int? quota,
    Iterable<Role> roles,
  ) async {
    // The refresh button and an analysis both ask for a fresh look at the newest page;
    // one done a few seconds ago answers both.
    final checked = _newestChecked[mode];
    final fresh =
        requestedFresh &&
        (checked == null ||
            DateTime.now().difference(checked) > const Duration(seconds: 10));
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
    // Nothing on screen yet: show what is already stored for this player right away, while
    // the real read (who they are, what is new) is under way. No request goes upstream.
    if (!l.has) {
      try {
        final kept = await app.api.stored(name, mode);
        if (kept != null && kept.matches.isNotEmpty && !l.has) {
          l.value = kept;
          notifyListeners();
        }
      } on ApiError {
        // Only a head start: the real read follows.
      }
    }
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
        if (first && fresh) _newestChecked[mode] = DateTime.now();
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

  /// The player's places on the hero boards; read once while the app runs.
  final heroBoard = Load<List<HeroBoardEntry>>();
  Future<void> loadHeroBoard() {
    if (heroBoard.has || heroBoard.loading) return Future.value();
    return _run(heroBoard, () => _call((s) => app.api.heroBoard(s)));
  }

  Future<void> loadCompetitive({bool fresh = false}) => _run(
    competitive,
    () => _call((s) => app.api.career(s, Mode.competitive, fresh: fresh)),
  );

  Future<void> loadTrend(
    Mode mode, {
    bool fresh = false,
  }) => _run(trendFor(mode), () async {
    // The service may have noticed a new season since the status was last read.
    await app.refreshServer();
    return _call(
      (s) => app.api.trend(
        s,
        mode,
        endSeason: app.currentSeason,
        count: 6,
        fresh: fresh,
      ),
    );
  });

  /// Reads the growth measures from what is stored locally: quick (a few milliseconds),
  /// so it is read again whenever the tab is shown.
  Future<void> loadGrowth(Mode mode) =>
      _run(growthFor(mode), () => _call((s) => app.api.growth(s, mode)));

  /// The overview, from the stored match list (no upstream request): read again after
  /// every match-list update, so it always matches the list.
  Future<void> loadOverview(Mode mode) =>
      _run(overviewFor(mode), () => _call((s) => app.api.overview(s, mode)));

  /// A day's summary (no upstream request); [day] null for the newest day.
  Future<void> loadDaily(Mode mode, [String? day]) {
    if (day != null) dailyDay[mode] = day;
    final d = dailyDay[mode];
    return _run(dailyFor(mode), () => _call((s) => app.api.daily(s, mode, d)));
  }

  /// Maps by mode type, from the stored list like the overview, and followed the same way.
  Future<void> loadMaps(Mode mode) =>
      _run(mapsFor(mode), () => _call((s) => app.api.maps(s, mode)));

  /// Rank tracks, from the stored list (no upstream request); [seasonMatches] comes
  /// from the season trend.
  Future<void> loadRanks(Mode mode, Map<int, int> seasonMatches) => _run(
    ranksFor(mode),
    () => _call((s) => app.api.ranks(s, mode, seasonMatches)),
  );

  /// Players met (no upstream request), from the stored details: read whenever the tab
  /// or the match list shows, as more details may have been stored.
  Future<void> loadPeople(Mode mode) =>
      _run(peopleFor(mode), () => _call((s) => app.api.people(s, mode)));

  Future<void> loadDuo(Mode mode, String key) =>
      _run(duoFor(mode, key), () => _call((s) => app.api.duo(s, mode, key)));

  /// Stadium builds (no upstream request); read once per scope while the app runs, and
  /// again with [fresh].
  Future<void> loadStadium(BuildSample scope, {bool fresh = false}) {
    final l = stadiumFor(scope);
    if (!fresh && (l.has || l.loading)) return Future.value();
    return _run(l, () => _call((s) => app.api.stadium(s, scope)));
  }

  /// Peer benchmarks (no upstream request); read once per mode while the app runs, and
  /// again with [fresh] (after more matches are stored).
  Future<void> loadBenchmark(Mode mode, {bool fresh = false}) {
    final l = benchmarkFor(mode);
    if (!fresh && (l.has || l.loading)) return Future.value();
    return _run(l, () => _call((s) => app.api.benchmark(s, mode)));
  }

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
    strengthStatus[mode] = tr.core.strengthReading;
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

        strengthStatus[mode] = rounds == 1 ? '' : tr.core.strengthRound(rounds);
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
        strengthStatus[mode] = tr.core.strengthReadingOlder;
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

  /// Reads a match's detail. The table comes back at once with the ranks already known;
  /// when the players' ranks are still to be looked up that happens next, and the table is
  /// filled in as soon as it is done.
  Future<void> loadDetail(Mode mode, String id) async {
    final l = details.putIfAbsent('${mode.id}:$id', Load.new);
    await _run(l, () => _call((s) => app.api.detail(s, mode, id)));
    if (l.value?.ratingsPending == true) {
      unawaited(_completeRatings(mode, id));
    }
  }

  final _completing = <String>{};

  Future<void> _completeRatings(Mode mode, String id) async {
    final key = '${mode.id}:$id';
    if (_closed || !_completing.add(key)) return;
    notifyListeners();
    try {
      await _call(
        (s) => app.api.prepare(s, mode, matchId: id, batch: 1, window: 5000),
      );
      final detail = await _call((s) => app.api.detail(s, mode, id));
      details[key]?.value = detail;
    } on ApiError {
      // The ranks stay as they were; the cells show a dash again.
    } finally {
      _completing.remove(key);
      if (!_closed) notifyListeners();
    }
  }

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
    openPlayerKey = null;
    notifyListeners();
  }

  /// The player whose page is open inside the open match: `ally:2` is the third of the
  /// player's own team, `enemy:0` the first of the other team.
  String? openPlayerKey;

  void openPlayer(String side, int index) {
    openPlayerKey = '$side:$index';
    notifyListeners();
  }

  /// Steps through the players of the match that is open (see [stepPlayer]).
  void stepOpenPlayer(int delta) {
    final id = openMatchId, mode = openMatchMode;
    final d = id == null || mode == null ? null : detailFor(mode, id).value;
    if (d != null) stepPlayer(delta, d.allies.length, d.enemies.length);
  }

  /// Back from a player's page to the whole match.
  void closePlayer() {
    openPlayerKey = null;
    notifyListeners();
  }

  /// Steps through the match's players, own team first. Stops at either end.
  void stepPlayer(int delta, int allies, int enemies) {
    final key = openPlayerKey;
    if (key == null) return;
    final parts = key.split(':');
    final index = (parts[0] == 'ally' ? 0 : allies) + int.parse(parts[1]);
    final next = index + delta;
    if (next < 0 || next >= allies + enemies) return;
    openPlayerKey = next < allies ? 'ally:$next' : 'enemy:${next - allies}';
    notifyListeners();
  }

  /// Step to the previous (-1) or next (+1) match in the order the detail was opened from.
  void stepMatch(int delta) {
    final id = openMatchId, mode = openMatchMode;
    if (id == null || mode == null) return;
    openPlayerKey = null;
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
      tab = tabIds.contains(ui.tab) ? ui.tab : 'overview',
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

  /// The provider's current season as the service knows it (it follows a season change
  /// the catalog has not caught up with); null until the service has said.
  /// Fewest matches before a hero, map or other group is compared (from the service).
  int get minGroupMatches =>
      ((server?['thresholds'] as Map?)?['group'] as num?)?.toInt() ??
      fallbackMinGroupMatches;

  int? get currentSeason =>
      (server?['current_season'] as num?)?.toInt() ?? catalog.currentSeason;
  List<Json> get accounts => [
    for (final a in (server?['accounts'] as List? ?? const []))
      (a as Map).cast<String, dynamic>(),
  ];
  List<Json> get metrics => [
    for (final a in (server?['metrics'] as List? ?? const []))
      (a as Map).cast<String, dynamic>(),
  ];
  bool get noAccount => server != null && accounts.isEmpty;

  /// Whether the sample player can be opened: this build has it and so does the service.
  bool get demoAvailable => demoBuild && server?['demo'] != false;
  bool get anyAccountReady => accounts.any((a) => a['status'] == 'ready');

  /// The sample player is on screen: it needs no account, so no account warning shows.
  bool get viewingSample =>
      current?.name.toLowerCase() == tr.shell.sampleName.toLowerCase();

  // ---- Boot -------------------------------------------------------------------

  Future<void> boot() async {
    status = BackendStatus.starting;
    backendError = null;
    notifyListeners();
    if (!await backend.ensureRunning()) {
      status = BackendStatus.offline;
      backendError = backend.lastLaunchError ?? tr.core.serviceUnavailable;
      notifyListeners();
      return;
    }
    status = BackendStatus.ready;
    notifyListeners();
    try {
      players = await api.players();
      catalog = Catalog(await api.catalog());
      // Ranks name their tiers from the catalog (the provider's own names).
      rankNames = catalog.rankName;
      // Fill the picture cache in the background; screens show skeletons until then.
      unawaited(ImageStore.instance.preload(catalog.preloadUrls()));
      await refreshServer();
      if (ui.autoCheckUpdates) {
        // After the first screen is up; a failed check stays quiet.
        unawaited(
          Future<void>.delayed(
            const Duration(seconds: 3),
          ).then((_) => checkUpdate().catchError((_) => null)),
        );
      }
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
      toast?.call(tr.core.cacheCleared);
    } on ApiError catch (e) {
      toast?.call(tr.core.cacheClearFailed(tr.shell.errorSentence(e.kind)));
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

  /// A library player's workspace, without opening them (comparisons read their data).
  PlayerWorkspace workspaceFor(String name) =>
      workspaces[name.toLowerCase()] ?? _workspace(name);

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
      toast?.call(
        tr.core.playerRemoveFailed(name, tr.shell.errorSentence(e.kind)),
      );
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
      tr.core.playerRemoved(name),
      actionLabel: tr.core.undo,
      action: () async {
        try {
          players = await api.savePlayer(name);
          notifyListeners();
          if (wasCurrent) await selectPlayer(name);
        } on ApiError catch (e) {
          toast?.call(
            tr.core.playerRestoreFailed(name, tr.shell.errorSentence(e.kind)),
          );
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

  /// Kinds of overview findings not to show again (kept with the layout).
  Set<String> get mutedInsights => ui.mutedInsights;

  void muteInsight(String kind) {
    ui.mutedInsights.add(kind);
    ui.save();
    notifyListeners();
  }

  void unmuteInsights() {
    ui.mutedInsights.clear();
    ui.save();
    notifyListeners();
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

  /// Whether share pictures hide player names.
  bool get maskNames => ui.shareMaskNames;

  void setMaskNames(bool on) {
    ui.shareMaskNames = on;
    ui.save();
    notifyListeners();
  }

  /// A player's name as a share picture shows it.
  String maskName(String name) => maskNames ? tr.recap.masked : name;

  // ---- Updates ----------------------------------------------------------------

  /// The last answer about a newer version; null until one has been asked for.
  UpdateInfo? update;
  UpdateDownload? updateDownload;
  Timer? _updatePoll;

  bool get autoCheckUpdates => ui.autoCheckUpdates;

  void setAutoCheckUpdates(bool on) {
    ui.autoCheckUpdates = on;
    ui.save();
    notifyListeners();
  }

  /// Asks the service whether a newer release is out (it asks GitHub).
  Future<UpdateInfo?> checkUpdate({bool force = false}) async {
    final info = await api.checkUpdate(force: force);
    update = info;
    updateDownload ??= info.download.state == 'idle' ? null : info.download;
    notifyListeners();
    return info;
  }

  /// Downloads the newer release, following it until it is ready or has failed.
  Future<void> startUpdateDownload() async {
    updateDownload = await api.downloadUpdate();
    notifyListeners();
    _updatePoll?.cancel();
    _updatePoll = Timer.periodic(const Duration(milliseconds: 400), (t) async {
      try {
        final d = await api.updateStatus();
        updateDownload = d;
        if (!d.busy) t.cancel();
      } on ApiError catch (e) {
        updateDownload = UpdateDownload({
          'state': 'failed',
          'error': e.message,
        });
        t.cancel();
      }
      notifyListeners();
    });
  }

  /// Starts the installer and quits; the new version opens by itself.
  Future<void> applyUpdate() async {
    await api.applyUpdate();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    exit(0);
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
    if (!ws.competitive.has && !ws.competitive.loading) {
      jobs.add(ws.loadCompetitive());
    }
    if (tab == 'trend') {
      final t = ws.trendFor(mode);
      if (!t.has && !t.loading) jobs.add(ws.loadTrend(mode));
    }
    if (tab == 'growth') jobs.add(ws.loadGrowth(mode));
    if (tab == 'overview') jobs.add(ws.loadOverview(mode));
    if (tab == 'maps') jobs.add(ws.loadMaps(mode));
    if (tab == 'daily') jobs.add(ws.loadDaily(mode));
    if (tab == 'people') jobs.add(ws.loadPeople(mode));
    // The match list only marks group sizes: read once, the people tab keeps it fresh.
    if (tab == 'matches' &&
        !ws.peopleFor(mode).has &&
        !ws.peopleFor(mode).loading) {
      jobs.add(ws.loadPeople(mode));
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
    if (tab == 'growth') jobs.add(ws.loadGrowth(mode));
    if (tab == 'overview') jobs.add(ws.loadOverview(mode));
    if (tab == 'maps') jobs.add(ws.loadMaps(mode));
    if (tab == 'daily') jobs.add(ws.loadDaily(mode));
    if (tab == 'people') jobs.add(ws.loadPeople(mode));
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
    exportStatus = tr.core.exportPickLocation;
    notifyListeners();
    try {
      // Asked before the long read so a cancelled dialog costs nothing.
      final safe = ws.name.replaceAll('#', '-');
      final path = await pickSavePath(tr.core.exportFileName(safe));
      if (path == null) return null;
      for (final mode in modes) {
        await _exportReadList(ws, mode, count, token);
        await _exportPrepare(ws, mode, count, ratings, token);
      }
      exportStatus = tr.core.exportAssembling;
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
      toast?.call(tr.core.exportSaved(path));
      return path;
    } on Cancelled {
      toast?.call(tr.core.exportCancelled);
      return null;
    } on FileSystemException {
      toast?.call(tr.core.exportWriteFailed);
      return null;
    } on ApiError catch (e) {
      toast?.call(tr.core.exportFailed(tr.shell.errorSentence(e.kind)));
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
      exportStatus = tr.core.exportReadingList(mode.shortLabel, seen);
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
      exportStatus = tr.core.exportPreparing(
        mode.shortLabel,
        r.total - r.remaining,
        r.total,
      );
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
