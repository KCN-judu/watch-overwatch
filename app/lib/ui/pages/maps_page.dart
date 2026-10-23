import 'package:flutter/material.dart';

import '../../core/maps.dart';
import '../../core/metric_doc.dart';
import '../../core/models.dart';
import '../../core/overview.dart';
import '../../core/support.dart';
import '../../design/cards.dart';
import '../../design/chart_kit.dart';
import '../../design/headline.dart';
import '../../design/icons.dart';
import '../../design/net_pic.dart';
import '../../design/share.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';
import '../../l10n/strings.dart';
import '../../state/app_state.dart';

/// Maps in two levels: mode type (escort, control, push …), then the maps of each with
/// their win rate, range and match count; a map opens beside the list with how long its
/// matches run, the figures per match and the heroes played on it. Maps with too few
/// matches are listed after the rest, grey, and take no part in the order. Worked out
/// from the stored match list, like the overview.
class MapsPage extends StatefulWidget {
  const MapsPage({super.key, required this.workspace});
  final PlayerWorkspace workspace;

  @override
  State<MapsPage> createState() => _MapsPageState();
}

class _MapsPageState extends State<MapsPage> {
  String? _picked;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final ws = widget.workspace;
    final mode = app.mode;
    final load = ws.mapsFor(mode);
    final result = load.value;
    if (load.failedWithoutData) {
      return ErrorPanel(
        what: tr.maps.emptyTitle,
        error: load.error!,
        onRetry: () => ws.loadMaps(mode),
      );
    }
    if (result == null) {
      return load.loading || !load.has
          ? const AfterDelay(child: Center(child: Spinner()))
          : const SizedBox.shrink();
    }
    if (result.listed == 0 || result.modes.isEmpty) {
      return EmptyState(
        icon: Icons.map_outlined,
        title: tr.maps.emptyTitle,
        body: tr.maps.emptyBody(mode.label),
        actions: [
          AppButton(
            tr.maps.openMatchList,
            primary: true,
            onPressed: () => app.setTab('matches'),
          ),
        ],
      );
    }
    final all = [
      for (final g in result.modes)
        for (final m in g.maps) (g, m),
    ];
    final picked =
        all.where((e) => e.$2.key == _picked).firstOrNull ?? all.first;
    final list = _List(
      workspace: ws,
      result: result,
      picked: picked.$2.key,
      onPick: (key) => setState(() => _picked = key),
    );
    final detail = _Detail(
      workspace: ws,
      mode: mode,
      group: picked.$1,
      row: picked.$2,
    );
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth < 1000) {
          return ListView(
            padding: const EdgeInsets.only(
              right: scrollGutter,
              bottom: Sp.page,
            ),
            children: [
              list,
              const SizedBox(height: Sp.betweenSections),
              detail,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: ListView(
                padding: const EdgeInsets.only(
                  right: scrollGutter,
                  bottom: Sp.page,
                ),
                children: [list],
              ),
            ),
            const SizedBox(width: Sp.betweenSections),
            Expanded(
              flex: 2,
              child: ListView(
                padding: const EdgeInsets.only(
                  right: scrollGutter,
                  bottom: Sp.page,
                ),
                children: [detail],
              ),
            ),
          ],
        );
      },
    );
  }
}

String _modeName(ModeGroup g) => g.mode ?? tr.maps.otherMode;

class _List extends StatelessWidget {
  const _List({
    required this.workspace,
    required this.result,
    required this.picked,
    required this.onPick,
  });
  final PlayerWorkspace workspace;
  final MapsResult result;
  final String picked;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              tr.maps.coverage(result.listed, app.mode.label),
              style: Ty.meta.copyWith(color: c.textSecondary),
            ),
            InfoTip(tr.maps.coverageTip),
          ],
        ),
        const SizedBox(height: Sp.betweenGroups),
        for (final (i, g) in result.modes.indexed) ...[
          if (i > 0) const SizedBox(height: Sp.betweenSections),
          Shareable(
            title: _modeName(g),
            info: i == 0 ? tr.maps.modeTip : null,
            infoDoc: MetricDoc.winRateRange,
            caption: tr.recap.caption(
              app.maskName(workspace.name),
              app.mode.label,
              g.record.matches,
            ),
            fileName: _modeName(g),
            trailing: Text(
              tr.maps.modeSummary(
                g.record.matches,
                fmtPct(g.record.winRatePct, digits: 0),
              ),
              style: Ty.num(Ty.meta).copyWith(color: c.textSecondary),
            ),
            child: Panel(
              child: IntervalBars(
                format: (v) => fmtPct(v, digits: 0),
                reference: g.record.winRatePct,
                referenceMeaning: g.record.winRatePct == null
                    ? null
                    : tr.maps.typeRate(fmtPct(g.record.winRatePct, digits: 0)),
                labelWidth: 220,
                rows: [
                  for (final m in g.maps)
                    IntervalRow(
                      label: m.map.label,
                      value: m.aggregate.record.winRatePct ?? 0,
                      low: m.aggregate.record.lowPct,
                      high: m.aggregate.record.highPct,
                      n: m.aggregate.record.decided,
                      enough: m.ranked,
                      selected: m.key == picked,
                      leading: MapThumb(app.catalog.mapImage(m.map)),
                      onTap: () => onPick(m.key),
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({
    required this.workspace,
    required this.mode,
    required this.group,
    required this.row,
  });
  final PlayerWorkspace workspace;
  final Mode mode;
  final ModeGroup group;
  final MapRow row;

  /// The hero behind a group key, from the stored matches (for the icon and the filter).
  EntityRef? _hero(String key) {
    for (final m in workspace.matchesFor(mode).value?.matches ?? const []) {
      final h = m.hero;
      if (h != null && groupKey(h) == key) return h;
    }
    return null;
  }

  void _open(AppState app, {EntityRef? hero}) {
    final f = workspace.filtersFor(mode)..clear();
    f.mapGuid = row.map.guid;
    if (hero != null) f.heroGuid = hero.guid;
    workspace.touch();
    app.setTab('matches');
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = context.c;
    final a = row.aggregate;
    final r = a.record;
    final rate = r.winRatePct;
    final art = app.catalog.mapImage(row.map);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: c.raised,
            border: Border.all(color: c.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The map's picture, fading out into the panel below it.
              if (art != null)
                SizedBox(
                  height: 140,
                  child: ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (rect) => const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: AppColors.artFade,
                      stops: [0, 0.6, 1],
                    ).createShader(rect),
                    child: NetPic(art, fit: BoxFit.cover, radius: 0),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(Sp.betweenGroups),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(row.map.label, style: Ty.page),
                    Text(
                      _modeName(group),
                      style: Ty.meta.copyWith(color: c.textSecondary),
                    ),
                    if (!row.ranked) ...[
                      const SizedBox(height: Sp.withinControl),
                      Text(
                        tr.maps.notRanked,
                        style: Ty.meta.copyWith(color: c.textSecondary),
                      ),
                    ],
                    const SizedBox(height: Sp.betweenGroups),
                    // The two that answer "how do I do here", large; the rest as tiles.
                    Wrap(
                      spacing: Sp.page,
                      runSpacing: Sp.betweenGroups,
                      children: [
                        HeadlineFigure(
                          label: tr.maps.winRate,
                          value: fmtPct(rate, digits: 0),
                          note: r.lowPct == null || r.highPct == null
                              ? null
                              : tr.maps.range(
                                  fmtPct(r.lowPct, digits: 0),
                                  fmtPct(r.highPct, digits: 0),
                                ),
                        ),
                        HeadlineFigure(
                          label: tr.maps.record,
                          note: tr.common.matchCount(r.matches),
                          child: RecordText(r.wins, r.losses, draws: r.draws),
                        ),
                      ],
                    ),
                    const SizedBox(height: Sp.betweenGroups),
                    Wrap(
                      spacing: Sp.withinGroup,
                      runSpacing: Sp.withinGroup,
                      children: [
                        KpiTile(
                          tr.maps.duration,
                          fmtClock(row.durationS),
                          note: row.durationSamples == 0
                              ? tr.maps.noDuration
                              : tr.maps.durationNote(row.durationSamples),
                        ),
                        KpiTile(tr.maps.kda, fmtTwo(a.kda)),
                        KpiTile(tr.maps.kills, fmtOne(a.perMatch.kills)),
                        KpiTile(tr.maps.damage, fmtInt(a.perMatch.damage)),
                        KpiTile(tr.maps.healing, fmtInt(a.perMatch.healing)),
                      ],
                    ),
                    const SizedBox(height: Sp.betweenGroups),
                    AppButton(
                      tr.maps.openMatches,
                      icon: Icons.filter_alt_outlined,
                      onPressed: () => _open(app),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (row.heroes.isNotEmpty) ...[
          const SizedBox(height: Sp.betweenSections),
          SectionHeader(tr.maps.heroesTitle, info: tr.maps.heroesTip),
          const SizedBox(height: SectionHeader.below),
          Panel(
            child: IntervalBars(
              format: (v) => fmtPct(v, digits: 0),
              reference: rate,
              referenceMeaning: rate == null
                  ? null
                  : tr.maps.mapRate(fmtPct(rate, digits: 0)),
              labelWidth: 150,
              rows: [
                for (final g in row.heroes)
                  () {
                    final h = _hero(g.key);
                    final hr = g.aggregate.record;
                    return IntervalRow(
                      label: g.label ?? h?.label ?? g.key,
                      value: hr.winRatePct ?? 0,
                      low: hr.lowPct,
                      high: hr.highPct,
                      n: hr.decided,
                      enough: hr.enough,
                      leading: NetImage(
                        app.catalog.heroIcon(h),
                        size: 24,
                        fallback: g.label ?? '',
                      ),
                      onTap: h == null ? null : () => _open(app, hero: h),
                    );
                  }(),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
