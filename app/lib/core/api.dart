import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../l10n/strings.dart';
import 'benchmark.dart';
import 'daily.dart';
import 'maps.dart';
import 'people.dart';
import 'ranks.dart';
import 'stadium.dart';
import 'models.dart';
import 'update.dart';
import 'overview.dart';

/// A failure reported by `watchd` or by reaching it.
class ApiError implements Exception {
  ApiError(this.kind, this.message, {this.retryAfterMs, this.status});
  final String kind;
  final String message;
  final int? retryAfterMs;
  final int? status;

  bool get isAuth => kind == 'auth' || kind == 'no_account';
  bool get isOffline => kind == 'offline';

  /// A player lookup that got an answer: not found, or a malformed name. Its message is
  /// the service's own sentence about what to type.
  bool get isLookup => kind == 'business' || kind == 'validation';
  bool get isExpiredSession =>
      kind == 'validation' && message.contains('会话已过期');

  /// Copyable details for a bug report; never contains credentials.
  String get details =>
      'kind=$kind${status == null ? '' : ' status=$status'}\n$message';
  @override
  String toString() => message;
}

class Cancelled implements Exception {}

/// One cancellable request. Closing the client drops the connection, and the
/// server abandons the work when its client goes away.
class CancelToken {
  http.Client? _client;
  bool cancelled = false;
  void cancel() {
    cancelled = true;
    _client?.close();
  }
}

class Api {
  Api(this.port);
  final int port;
  String get base => 'http://127.0.0.1:$port';

  Future<Json> _send(
    String method,
    String path, {
    Json? body,
    CancelToken? cancel,
    Duration timeout = const Duration(seconds: 200),
  }) async {
    final client = http.Client();
    cancel?._client = client;
    try {
      final request = http.Request(method, Uri.parse('$base$path'))
        ..headers['content-type'] = 'application/json'
        ..headers['x-watch-client'] = 'watch-overwatch';
      if (body != null) request.body = jsonEncode(body);
      final streamed = await client.send(request).timeout(timeout);
      final text = await streamed.stream.bytesToString();
      dynamic value;
      try {
        value = jsonDecode(text);
      } catch (_) {
        value = null;
      }
      if (streamed.statusCode >= 400) {
        final e = value is Map ? value['error'] : null;
        throw ApiError(
          e is Map ? '${e['kind'] ?? 'upstream'}' : 'upstream',
          e is Map
              ? '${e['message'] ?? tr.core.requestFailed}'
              : tr.core.unreadableResponse,
          retryAfterMs: e is Map
              ? (e['retry_after_ms'] as num?)?.toInt()
              : null,
          status: streamed.statusCode,
        );
      }
      return value is Map<String, dynamic> ? value : {'list': value};
    } on ApiError {
      rethrow;
    } on TimeoutException {
      throw ApiError('timeout', tr.core.serviceTimeout(timeout.inSeconds));
    } catch (e) {
      if (cancel?.cancelled ?? false) throw Cancelled();
      throw ApiError('offline', tr.core.serviceUnreachable(port));
    } finally {
      client.close();
    }
  }

  Future<Json> get(String path, {CancelToken? cancel}) =>
      _send('GET', path, cancel: cancel);
  Future<Json> post(
    String path,
    Json body, {
    CancelToken? cancel,
    Duration? timeout,
  }) => _send(
    'POST',
    path,
    body: body,
    cancel: cancel,
    timeout: timeout ?? const Duration(seconds: 200),
  );

  Future<bool> healthy() async {
    try {
      final j = await _send(
        'GET',
        '/healthz',
        timeout: const Duration(seconds: 2),
      );
      return j['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<List<String>> players() async {
    final j = await get('/api/players');
    return [for (final e in (j['list'] as List? ?? const [])) '$e'];
  }

  Future<List<String>> savePlayer(String name, {bool remove = false}) async {
    final j = await post('/api/players', {'name': name, 'remove': remove});
    return [for (final e in (j['list'] as List? ?? const [])) '$e'];
  }

  Future<({String session, Json identity})> search(String name) async {
    final j = await post('/api/player/search', {'name': name});
    return (
      session: '${j['session']}',
      identity: (j['identity'] as Map).cast<String, dynamic>(),
    );
  }

  /// The match list of one mode, read through the service's local store: matches newer
  /// than the newest stored come first, then older ones until `quota` matches of each of
  /// `roles` are stored (everything when `quota` is null). At most `pages` list pages are
  /// requested per call; `coverage.exhausted` says whether the history is complete.
  Future<PlayerDataset> dataset(
    String session,
    Mode mode, {
    int pages = 10,
    bool fresh = false,
    int? quota,
    Iterable<Role> roles = const [],
    CancelToken? cancel,
  }) async {
    final j = await post('/api/player/dataset', {
      'session': session,
      'fresh': fresh,
      'plan': {
        'modes': [mode.id],
        'max_pages': pages,
        'max_details': 0,
        'hero_board': false,
        'list_quota': ?quota,
        if (quota != null && roles.isNotEmpty)
          'roles': [for (final r in roles) r.id],
      },
    }, cancel: cancel);
    return PlayerDataset((j['dataset'] as Map).cast<String, dynamic>());
  }

  Future<CareerSnapshot> career(
    String session,
    Mode mode, {
    bool fresh = false,
    int? season,
  }) async {
    final j = await post('/api/player/view', {
      'session': session,
      'view': 'profile',
      'mode': mode.provider,
      'fresh': fresh,
      'season': ?season,
    });
    return CareerSnapshot((j['ir'] as Map).cast<String, dynamic>());
  }

  /// Where the player's heroes stand on the provider's hero boards (province ranks).
  Future<List<HeroBoardEntry>> heroBoard(String session) async {
    final j = await post('/api/player/view', {
      'session': session,
      'view': 'heroes',
      'mode': Mode.competitive.provider,
    });
    return [
      for (final e in (j['ir'] as List?) ?? const [])
        if (e is Map<String, dynamic>) HeroBoardEntry(e),
    ];
  }

  Future<MatchDetail> detail(
    String session,
    Mode mode,
    String matchId, {
    CancelToken? cancel,
  }) async {
    final j = await post('/api/player/view', {
      'session': session,
      'view': 'detail',
      'mode': mode.provider,
      'match_id': matchId,
    }, cancel: cancel);
    return MatchDetail(
      (j['ir'] as Map).cast<String, dynamic>(),
      ratingsPending: j['ratings_pending'] == true,
    );
  }

  Future<List<SeasonPoint>> trend(
    String session,
    Mode mode, {
    int? endSeason,
    int count = 5,
    bool fresh = false,
  }) async {
    final j = await post('/api/player/view', {
      'session': session,
      'view': 'history',
      'mode': mode.provider,
      'fresh': fresh,
      'season': ?endSeason,
      if (endSeason != null)
        'start_season': (endSeason - count + 1).clamp(1, 100),
    });
    final ir = j['ir'] as Map? ?? const {};
    return [
      for (final e in (ir['trend'] as List? ?? const []))
        if (e is Map<String, dynamic>) SeasonPoint(e),
    ];
  }

  /// Lobby strength from the newest `perRole` matches the subject played on each
  /// role (fewer when they have fewer). Paging continues until every role has enough.
  Future<StrengthResult> strength(
    String session,
    Mode mode, {
    int perRole = 10,
    Role? role,
    List<MatchSummary> known = const [],
    bool fresh = false,
    String? progressId,
    CancelToken? cancel,
  }) async {
    final j = await post(
      '/api/player/dataset',
      {
        'session': session,
        'fresh': fresh,
        'progress_id': ?progressId,
        'plan': {
          'modes': [mode.id],
          'max_pages': 20,
          'max_details': 0,
          'details_per_role': perRole,
          'roles': [?role?.id],
          // The match rows already read; the service does not read the list again.
          if (known.isNotEmpty) 'known_matches': [for (final m in known) m.raw],
          'hero_board': false,
          // Only the lobby analysis is wanted here, not the profile.
          'profile': false,
          'lobby_ratings': true,
          'max_rated_players': (perRole * 30).clamp(1, 600),
        },
      },
      cancel: cancel,
      timeout: const Duration(seconds: 200),
    );
    return StrengthResult(j);
  }

  /// Peer benchmarks for the player's heroes, from every match stored locally.
  /// Maps by mode type, from the stored match list (no upstream request).
  Future<MapsResult> maps(String session, Mode mode) async => MapsResult(
    await post('/api/player/maps', {'session': session, 'mode': mode.id}),
  );

  /// Stadium builds per hero, from the stored Stadium matches (no upstream request).
  Future<StadiumResult> stadium(String session, BuildSample scope) async =>
      StadiumResult(
        await post('/api/player/stadium', {
          'session': session,
          'scope': scope.id,
        }),
      );

  /// Rank tracks per role from the stored match list; [seasonMatches] (each season's
  /// career match count) places matches in seasons.
  Future<RanksResult> ranks(
    String session,
    Mode mode,
    Map<int, int> seasonMatches,
  ) async => RanksResult(
    await post('/api/player/ranks', {
      'session': session,
      'mode': mode.id,
      'season_matches': {
        for (final e in seasonMatches.entries) '${e.key}': e.value,
      },
    }),
  );

  /// Players met in the stored matches, and group against solo results.
  Future<PeopleResult> people(String session, Mode mode) async => PeopleResult(
    await post('/api/player/people', {'session': session, 'mode': mode.id}),
  );

  /// The shared matches with one player (a [Mate.key]).
  Future<DuoResult> duo(String session, Mode mode, String other) async =>
      DuoResult(
        await post('/api/player/duo', {
          'session': session,
          'mode': mode.id,
          'other': other,
        }),
      );

  /// A day's summary and the days with matches; [day] is `YYYY-MM-DD` (newest when null).
  Future<DailyResult> daily(String session, Mode mode, String? day) async =>
      DailyResult(
        await post('/api/player/daily', {
          'session': session,
          'mode': mode.id,
          'day': ?day,
        }),
      );

  Future<BenchmarkResult> benchmark(String session, Mode mode) async =>
      BenchmarkResult(
        await post('/api/player/benchmark', {
          'session': session,
          'mode': mode.id,
        }),
      );

  /// The overview (records, groups, form, findings) from the stored match list.
  Future<OverviewResult> overview(String session, Mode mode) async =>
      OverviewResult(
        await post('/api/player/overview', {
          'session': session,
          'mode': mode.id,
        }),
      );

  /// The growth measures (survival time, Fleta index, KDA) match by match, with their
  /// trends, from the details already stored on this machine (no upstream request).
  Future<GrowthResult> growth(String session, Mode mode) async => GrowthResult(
    await post('/api/player/growth', {'session': session, 'mode': mode.id}),
  );

  /// Starts (or moves up) the service's background job that takes the rank snapshots of
  /// the player's newest matches; null without a local store.
  Future<RankJob?> startRankJob(String session, Mode mode) async => RankJob.opt(
    (await post('/api/ranks/start', {
      'session': session,
      'mode': mode.id,
    }))['job'],
  );

  /// Where that job stands; null when none was started in this run of the service.
  Future<RankJob?> rankJob(String session, Mode mode) async => RankJob.opt(
    (await post('/api/ranks/status', {
      'session': session,
      'mode': mode.id,
    }))['job'],
  );

  /// Has the service look up the ranks of the players in a small batch of the newest
  /// matches that are not ready for the strength analysis yet. `remaining` is how many of
  /// the newest [window] matches are still waiting; `enabled` is false without a local store.
  Future<({int prepared, int remaining, int total, bool enabled})> prepare(
    String session,
    Mode mode, {
    int window = 300,
    int batch = 3,
    bool ratings = true,
    String? matchId,
    CancelToken? cancel,
  }) async {
    final j = await post(
      '/api/player/prepare',
      {
        'session': session,
        'mode': mode.id,
        'window': window,
        'batch': batch,
        'ratings': ratings,
        'match_id': ?matchId,
      },
      cancel: cancel,
      timeout: const Duration(seconds: 150),
    );
    return (
      prepared: (j['prepared'] as num?)?.toInt() ?? 0,
      remaining: (j['remaining'] as num?)?.toInt() ?? 0,
      total: (j['total'] as num?)?.toInt() ?? 0,
      enabled: j['enabled'] == true,
    );
  }

  /// What is already stored locally for a name, with no request to the upstream: the
  /// matches read so far (and the last profile) shaped like a dataset. Null for a name
  /// never looked up before.
  Future<PlayerDataset?> stored(String name, Mode mode) async {
    final j = await post('/api/player/stored', {
      'name': name,
      'mode': mode.id,
    }, timeout: const Duration(seconds: 5));
    if (j['known'] != true) return null;
    return PlayerDataset((j['dataset'] as Map).cast<String, dynamic>());
  }

  /// What the local strength cache holds: matches, players, bytes. Null if it is unavailable.
  Future<Json?> cacheStats() async =>
      (await get('/api/cache'))['store'] as Json?;

  /// Empties the strength cache and returns what is left.
  Future<Json?> clearCache() async =>
      (await post('/api/cache/clear', const {}))['store'] as Json?;

  /// Live progress of an analysis started with `progressId`; null until it exists.
  Future<Json?> progress(String id) async {
    try {
      return await get('/api/progress?id=$id');
    } on ApiError catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  /// Full dataset for export, as raw JSON: the newest [count] matches of each mode (all
  /// when null), each with its detail, and with the players' ranks when [ratings].
  Future<Json> exportDataset(
    String session,
    List<Mode> modes, {
    int? count,
    required bool ratings,
    CancelToken? cancel,
  }) => post('/api/player/dataset', {
    'session': session,
    'plan': {
      'modes': [for (final m in modes) m.id],
      'max_pages': 10,
      'max_details': ((count ?? 5000) * modes.length).clamp(1, 5000),
      'match_limit': ?count,
      'hero_board': true,
      'lobby_ratings': ratings,
      'max_rated_players': 5000,
    },
  }, cancel: cancel);

  /// This version against the latest release; [force] asks GitHub again instead of
  /// reusing the last answer.
  Future<UpdateInfo> checkUpdate({bool force = false}) async => UpdateInfo(
    await post('/api/update/check', {
      'force': force,
    }, timeout: const Duration(seconds: 40)),
  );

  /// Starts (or rejoins) the download of the latest release.
  Future<UpdateDownload> downloadUpdate() async => UpdateDownload(
    (await post('/api/update/download', const {}))['download'] as Json?,
  );

  Future<UpdateDownload> updateStatus() async => UpdateDownload(
    (await post('/api/update/status', const {}))['download'] as Json?,
  );

  /// Hands over to the installer; the service exits right after answering.
  Future<void> applyUpdate() => post('/api/update/apply', const {});

  Future<Json> state() => get('/api/state');
  Future<Json> catalog() => get('/api/catalog');

  Future<void> saveAccount(String name, int roleId, String token) => post(
    '/api/accounts',
    {'name': name, 'role_id': roleId, 'token': token},
  ).then((_) {});
  Future<void> removeAccount(String name) => post('/api/accounts', {
    'name': name,
    'role_id': 1,
    'token': '',
    'remove': true,
  }).then((_) {});
}

/// Finds, starts and supervises the local `watchd` process.
class Backend {
  Backend({this.port = 18280});
  final int port;
  late final Api api = Api(port);
  Process? _process;
  String? lastLaunchError;
  String? binaryPath;

  /// Looks beside the app, then up the tree for a repository build.
  List<String> candidates() {
    final env = Platform.environment['WATCHD_PATH'];
    final out = <String>[if (env != null && env.isNotEmpty) env];
    var dir = File(Platform.resolvedExecutable).parent;
    for (var i = 0; i < 9; i++) {
      out.add('${dir.path}${Platform.pathSeparator}watchd.exe');
      for (final profile in ['release', 'debug']) {
        out.add(
          '${dir.path}${Platform.pathSeparator}target${Platform.pathSeparator}$profile${Platform.pathSeparator}watchd.exe',
        );
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return out;
  }

  String? locate() {
    final found = candidates().where((p) => File(p).existsSync()).toList();
    if (found.isEmpty) return null;
    // Prefer the most recently built binary; stale builds lack newer endpoints.
    found.sort(
      (a, b) =>
          File(b).lastModifiedSync().compareTo(File(a).lastModifiedSync()),
    );
    return found.first;
  }

  Future<bool> ensureRunning() async {
    if (await api.healthy()) return true;
    binaryPath = locate();
    if (binaryPath == null) {
      lastLaunchError = tr.core.serviceNotFound;
      return false;
    }
    try {
      _process = await Process.start(
        binaryPath!,
        const [],
        environment: {'WATCHD_PORT': '$port', 'WATCHD_EXIT_ON_STDIN_EOF': '1'},
        workingDirectory: File(binaryPath!).parent.path,
      );
      // Drain output so the pipe never fills.
      _process!.stdout.drain<void>();
      _process!.stderr.drain<void>();
    } catch (e) {
      lastLaunchError = tr.core.serviceStartFailed(e);
      return false;
    }
    // The service is up in about half a second: look often, so the app does not sit
    // idle for most of a polling interval after it is ready.
    for (var i = 0; i < 125; i++) {
      if (await api.healthy()) return true;
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    lastLaunchError = tr.core.serviceStartTimeout;
    return false;
  }

  void stop() {
    _process?.kill();
    _process = null;
  }
}
