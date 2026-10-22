import 'models.dart';
import 'overview.dart';

/// One map of a mode type (`watch_core::maps::MapRow`).
class MapRow {
  MapRow(Json j)
    : map = EntityRef.fromJson((j['map'] as Json?) ?? const {}),
      key = (j['key'] as String?) ?? '',
      aggregate = OverviewAggregate(j['aggregate'] as Json?),
      durationS = (j['duration_s'] as num?)?.toDouble(),
      durationSamples = (j['duration_samples'] as num?)?.toInt() ?? 0,
      heroes = [
        for (final g in (j['heroes'] as List?) ?? const [])
          if (g is Map<String, dynamic>) OverviewGroup(g),
      ],
      ranked = j['ranked'] == true;
  final EntityRef map;
  final String key;
  final OverviewAggregate aggregate;

  /// Mean match length over [durationSamples] matches with a stored detail.
  final double? durationS;
  final int durationSamples;
  final List<OverviewGroup> heroes;

  /// Enough matches to take part in the order; the rest follow, greyed.
  final bool ranked;
}

/// Maps of one mode type (escort, control …); `mode` is null for maps the catalog
/// does not place.
class ModeGroup {
  ModeGroup(Json j)
    : mode = j['mode'] as String?,
      record = OverviewRecord(j['record'] as Json?),
      maps = [
        for (final m in (j['maps'] as List?) ?? const [])
          if (m is Map<String, dynamic>) MapRow(m),
      ];
  final String? mode;
  final OverviewRecord record;
  final List<MapRow> maps;
}

class MapsResult {
  MapsResult(Json j)
    : enabled = j['enabled'] == true,
      listed = (j['listed'] as num?)?.toInt() ?? 0,
      modes = [
        for (final g in ((j['maps'] as Json?)?['modes'] as List?) ?? const [])
          if (g is Map<String, dynamic>) ModeGroup(g),
      ];
  final bool enabled;
  final int listed;
  final List<ModeGroup> modes;
}
