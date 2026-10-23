import 'models.dart';

/// A published release (`/api/update/check`).
class ReleaseInfo {
  ReleaseInfo(Json j)
    : version = '${j['version'] ?? ''}',
      name = '${j['name'] ?? ''}',
      notes = '${j['notes'] ?? ''}',
      publishedAt = DateTime.tryParse('${j['published_at']}')?.toLocal(),
      pageUrl = j['page_url'] as String?,
      zipSize = (j['zip_size'] as num?)?.toInt() ?? 0;
  final String version, name;

  /// What changed, in Markdown.
  final String notes;
  final DateTime? publishedAt;
  final String? pageUrl;
  final int zipSize;
}

/// The download of a release: `idle`, `downloading`, `verifying`, `ready`, `failed`.
class UpdateDownload {
  UpdateDownload(Json? j)
    : state = '${j?['state'] ?? 'idle'}',
      version = j?['version'] as String?,
      received = (j?['received'] as num?)?.toInt() ?? 0,
      total = (j?['total'] as num?)?.toInt() ?? 0,
      error = j?['error'] as String?;
  final String state;
  final String? version;
  final int received, total;
  final String? error;
  bool get busy => state == 'downloading' || state == 'verifying';
  bool get ready => state == 'ready';
  bool get failed => state == 'failed';
  double? get share => total <= 0 ? null : received / total;
}

/// This version against the latest release.
class UpdateInfo {
  UpdateInfo(Json j)
    : current = '${j['current'] ?? ''}',
      latest = j['latest'] is Map
          ? ReleaseInfo((j['latest'] as Map).cast<String, dynamic>())
          : null,
      newer = j['newer'] == true,
      installable = j['installable'] == true,
      download = UpdateDownload(
        (j['download'] as Map?)?.cast<String, dynamic>(),
      );
  final String current;
  final ReleaseInfo? latest;
  final bool newer;

  /// Whether this copy is a release folder an update can replace.
  final bool installable;
  final UpdateDownload download;
}
