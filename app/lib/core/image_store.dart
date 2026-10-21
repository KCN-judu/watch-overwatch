import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;

import '../l10n/strings.dart';

/// How many images are still loading, for the progress bar.
class ImageLoadStats {
  const ImageLoadStats(this.done, this.total);
  final int done, total;
  int get pending => total - done;
  bool get busy => pending > 0;
  double get fraction => total == 0 ? 1 : done / total;
}

/// One place that fetches pictures: a picture is downloaded at most once ever
/// (kept on disk), at most once at a time (shared in-flight request), and decoded at
/// most once per run (the framework's image cache, keyed by the same address).
class ImageStore {
  ImageStore._();
  static final ImageStore instance = ImageStore._();

  final Map<String, Future<Uint8List>> _inflight = {};
  final stats = ValueNotifier<ImageLoadStats>(const ImageLoadStats(0, 0));
  Directory? _dir;
  Timer? _reset;
  final http.Client _client = http.Client();

  Directory get _cacheDir {
    final base =
        Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path;
    return _dir ??= Directory(
      '$base${Platform.pathSeparator}Watch Overwatch${Platform.pathSeparator}img-cache',
    )..createSync(recursive: true);
  }

  /// FNV-1a 64-bit, as a file name; the address itself can be long and has odd characters.
  static String _name(String url) {
    var h = BigInt.parse('cbf29ce484222325', radix: 16);
    final prime = BigInt.parse('100000001b3', radix: 16);
    final mask = (BigInt.one << 64) - BigInt.one;
    for (final b in url.codeUnits) {
      h = ((h ^ BigInt.from(b & 0xff)) * prime) & mask;
      h = ((h ^ BigInt.from(b >> 8)) * prime) & mask;
    }
    final dot = url.lastIndexOf('.');
    final ext = dot > url.length - 6 && dot > 0
        ? url.substring(dot).replaceAll(RegExp(r'[^A-Za-z0-9.]'), '')
        : '';
    return '${h.toRadixString(16).padLeft(16, '0')}$ext';
  }

  void _count({required bool started}) {
    final s = stats.value;
    stats.value = started
        ? ImageLoadStats(s.done, s.total + 1)
        : ImageLoadStats(s.done + 1, s.total);
    _reset?.cancel();
    if (!stats.value.busy) {
      // Start a fresh count once things have been quiet for a moment.
      _reset = Timer(const Duration(milliseconds: 800), () {
        if (!stats.value.busy) stats.value = const ImageLoadStats(0, 0);
      });
    }
  }

  /// The picture's bytes: from disk when seen before, otherwise downloaded and kept.
  Future<Uint8List> bytes(String url) {
    final existing = _inflight[url];
    if (existing != null) return existing;
    _count(started: true);
    final f = _load(url).whenComplete(() {
      _inflight.remove(url);
      _count(started: false);
    });
    _inflight[url] = f;
    return f;
  }

  Future<Uint8List> _load(String url) async {
    final file = File(
      '${_cacheDir.path}${Platform.pathSeparator}${_name(url)}',
    );
    try {
      if (await file.exists()) {
        final data = await file.readAsBytes();
        if (data.isNotEmpty) return data;
      }
    } catch (_) {
      // A damaged cache file just means downloading again.
    }
    Object? last;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final r = await _client
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 25));
        if (r.statusCode == 200 && r.bodyBytes.isNotEmpty) {
          try {
            final tmp = File('${file.path}.part');
            await tmp.writeAsBytes(r.bodyBytes, flush: true);
            await tmp.rename(file.path);
          } catch (_) {
            // Not being able to keep it only costs a download next time.
          }
          return r.bodyBytes;
        }
        last = 'HTTP ${r.statusCode}';
      } catch (e) {
        last = e;
      }
    }
    throw StateError(tr.core.imageLoadFailed(url, last));
  }

  /// Fetches [urls] ahead of use, a few at a time, so they are on disk and the first
  /// screen does not fill in piece by piece. Failures are ignored.
  Future<void> preload(Iterable<String> urls, {int concurrency = 6}) async {
    final queue = urls.toSet().toList();
    var next = 0;
    Future<void> worker() async {
      while (next < queue.length) {
        final url = queue[next++];
        try {
          await bytes(url);
        } catch (_) {}
      }
    }

    await Future.wait([for (var i = 0; i < concurrency; i++) worker()]);
  }
}

/// A network picture served by [ImageStore]. Two widgets asking for the same address
/// share one decoded image in the framework cache.
@immutable
class CachedImage extends ImageProvider<CachedImage> {
  const CachedImage(this.url);
  final String url;

  @override
  Future<CachedImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<CachedImage>(this);

  @override
  ImageStreamCompleter loadImage(CachedImage key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _codec(key, decode),
      scale: 1.0,
      debugLabel: key.url,
    );
  }

  Future<ui.Codec> _codec(CachedImage key, ImageDecoderCallback decode) async {
    final data = await ImageStore.instance.bytes(key.url);
    final buffer = await ui.ImmutableBuffer.fromUint8List(data);
    return decode(buffer);
  }

  @override
  bool operator ==(Object other) => other is CachedImage && other.url == url;
  @override
  int get hashCode => url.hashCode;
  @override
  String toString() => 'CachedImage($url)';
}
