import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/support.dart';
import '../../design/cards.dart';
import '../../design/data_table.dart';
import '../../design/icons.dart';
import '../../design/net_pic.dart';
import '../../state/match_view.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';
import '../../state/app_state.dart';
import '../player_view.dart';
import '../../l10n/strings.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key, required this.workspace});
  final PlayerWorkspace workspace;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final ws = workspace;
    final mode = app.mode;
    final load = ws.matchesFor(mode);
    final c = context.c;
    if (load.failedWithoutData) {
      return ErrorPanel(
        what: tr.heroes.profileLoadFailed,
        error: load.error!,
        onRetry: () => ws.loadMatches(mode, fresh: true),
      );
    }
    final data = load.value;
    if (data == null) {
      return AfterDelay(
        child: Center(child: RefreshingChip(label: tr.heroes.profileLoading)),
      );
    }
    final p = data.profile;
    final career = data.career(mode);
    final scale = math.max(
      1.0,
      MediaQuery.textScalerOf(context).scale(13) / 13,
    );
    final roleCount =
        career?.roles.where((r) => Role.playable.contains(r.role)).length ?? 0;
    final tableH =
        context.density.rowHeight * scale * (math.max(roleCount, 1) + 1) + 4;

    return ListView(
      padding: const EdgeInsets.only(right: 16),
      children: [
        LoadStatusBar(
          at: load.at,
          loading: load.loading && load.has,
          error: load.error?.message,
          onRetry: () => ws.loadMatches(mode, fresh: true),
        ),
        const SizedBox(height: Sp.betweenGroups),
        _FactCard(
          title: tr.heroes.identity,
          icons: {
            tr.heroes.title: p.titleIconUrl,
            tr.heroes.endorsement: app.catalog.endorsementIcon(
              p.endorsementLevel,
            ),
          },
          facts: [
            (tr.heroes.battleTag, p.name ?? ws.name),
            (tr.heroes.playerId, p.bnetId ?? missing),
            if (p.title != null) (tr.heroes.title, p.title!),
            (
              tr.heroes.endorsement,
              p.endorsementLevel == null
                  ? missing
                  : tr.heroes.endorsementLevel(p.endorsementLevel!),
            ),
            (
              tr.heroes.totalPlayTime,
              p.playTimeHours == null
                  ? missing
                  : tr.heroes.hours(fmtOne(p.playTimeHours)),
            ),
            (tr.heroes.totalMatches, fmtInt(p.totalMatches)),
            (
              tr.heroes.accountStatus,
              !p.suspended
                  ? tr.heroes.accountNormal
                  : p.suspensionExpiresMs == null
                  ? tr.heroes.accountSuspended
                  : tr.heroes.accountSuspendedUntil(
                      fmtDateTime(p.suspensionExpiresMs),
                    ),
            ),
          ],
        ),
        const SizedBox(height: Sp.betweenSections),
        _Recent(rows: data.matches, mode: mode),
        const SizedBox(height: Sp.betweenSections),
        Semantics(
          header: true,
          child: Text(
            tr.heroes.careerHeading(
              mode.label,
              career?.season ?? app.currentSeason,
            ),
            style: Ty.section,
          ),
        ),
        const SizedBox(height: Sp.withinGroup),
        SizedBox(
          height: tableH,
          child: AppTable<RoleCareer>(
            tableLabel: tr.heroes.careerTableLabel(mode.label),
            columns: [
              Col(
                id: 'role',
                label: tr.heroes.colRole,
                width: 100,
                flex: true,
                tooltip: roleLegend,
                cell: (_, r) => RoleIcon(r.role, size: 18, showLabel: true),
              ),
              Col(
                id: 'cur',
                label: tr.heroes.colCurrentRank,
                width: 124,
                cell: (_, r) => RankBadge(
                  r.current,
                  catalog: app.catalog,
                  showText: true,
                  stadium: mode == Mode.stadium,
                ),
              ),
              Col(
                id: 'peak',
                label: tr.heroes.colPeakRank,
                width: 124,
                cell: (_, r) => RankBadge(
                  r.peak,
                  catalog: app.catalog,
                  showText: true,
                  stadium: mode == Mode.stadium,
                ),
              ),
              Col(
                id: 'm',
                label: tr.heroes.matchesLabel,
                width: 64,
                numeric: true,
                cell: (_, r) => Text(fmtInt(r.matches)),
              ),
              Col(
                id: 'w',
                label: tr.heroes.winRateLabel,
                width: 76,
                numeric: true,
                cell: (_, r) => Text(fmtPct(r.winRatePct)),
              ),
              Col(
                id: 'k',
                label: 'KDA',
                width: 64,
                numeric: true,
                cell: (_, r) => Text(fmtTwo(r.kda)),
              ),
              Col(
                id: 's',
                label: tr.heroes.colMaxStreak,
                width: 88,
                numeric: true,
                cell: (_, r) => Text(fmtInt(r.maxWinStreak)),
              ),
            ],
            rows:
                career?.roles
                    .where((r) => Role.playable.contains(r.role))
                    .toList() ??
                const [],
            rowLabel: (r) => tr.heroes.careerRowLabel(
              r.role.label,
              r.current?.label ?? tr.common.unranked,
              r.peak?.label ?? tr.common.unranked,
              fmtInt(r.matches),
              fmtPct(r.winRatePct),
            ),
            empty: Center(
              child: Text(
                tr.heroes.noCareer(mode.label),
                style: Ty.body.copyWith(color: c.textSecondary),
              ),
            ),
          ),
        ),
        if (mode != Mode.competitive)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              tr.heroes.noRanksInMode(mode.label),
              style: Ty.meta.copyWith(color: c.textSecondary),
            ),
          ),
        if (career?.behavior != null) ...[
          const SizedBox(height: Sp.betweenSections),
          _FactCard(
            title: tr.heroes.behavior,
            facts: [
              (
                tr.heroes.honorsReceived,
                fmtInt(career!.behavior!.honorsReceived),
              ),
              (tr.heroes.honorsSent, fmtInt(career.behavior!.honorsSent)),
              (tr.heroes.reports, fmtInt(career.behavior!.reports)),
              if (career.behavior!.comment != null)
                (tr.heroes.weeklyComment, career.behavior!.comment!),
            ],
          ),
        ],
        if (career != null && career.provinceRanks.isNotEmpty) ...[
          const SizedBox(height: Sp.betweenSections),
          _FactCard(
            title: tr.heroes.provinceRanks,
            facts: [
              for (final r in career.provinceRanks)
                (
                  tr.heroes.provinceRankLabel(r.role.label, r.province),
                  tr.heroes.rankPosition(fmtInt(r.rank)),
                ),
            ],
          ),
        ],
        const SizedBox(height: Sp.betweenSections),
      ],
    );
  }
}

/// Read-only facts as label-over-value blocks in one card: grouped by the card,
/// scanned as a row instead of a two-column list with a wide empty right half.
class _FactCard extends StatelessWidget {
  const _FactCard({
    required this.title,
    required this.facts,
    this.icons = const {},
  });
  final String title;
  final List<(String, String)> facts;

  /// Picture shown before a fact's value, by the fact's label (from the image cache).
  final Map<String, String?> icons;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title),
        const SizedBox(height: Sp.withinGroup),
        Panel(
          width: double.infinity,
          child: Wrap(
            spacing: 40,
            runSpacing: Sp.withinGroup + 4,
            children: [
              for (final f in facts)
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 96,
                    maxWidth: 260,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        f.$1,
                        style: Ty.meta.copyWith(color: c.textSecondary),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (icons[f.$1] case final url?) ...[
                            NetPic(
                              url,
                              width: 22,
                              height: 22,
                              error: const SizedBox.shrink(),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Flexible(
                            child: SelectableText(
                              f.$2,
                              style: Ty.num(Ty.title),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Averages over the matches that were read. The match list no longer carries these:
/// the list is for recognising a match, this is for judging recent form.
class _Recent extends StatelessWidget {
  const _Recent({required this.rows, required this.mode});
  final List<MatchSummary> rows;
  final Mode mode;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final a = Agg(rows);
    String mean(String f) => a.mean[f] == null ? missing : fmtInt(a.mean[f]);
    String? partial(String f) => a.mean[f] != null && a.samples[f]! < a.matches
        ? 'n=${a.samples[f]}'
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Semantics(
              header: true,
              child: Text(
                tr.heroes.recentHeading(mode.label),
                style: Ty.section,
              ),
            ),
            InfoTip(tr.heroes.recentFormInfo),
          ],
        ),
        const SizedBox(height: Sp.withinGroup),
        if (rows.isEmpty)
          Text(
            tr.heroes.noMatchesRead,
            style: Ty.body.copyWith(color: c.textSecondary),
          )
        else
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              KpiTile(tr.heroes.matchesLabel, '${a.matches}'),
              KpiTile(
                tr.heroes.record,
                tr.heroes.winLoss(a.wins, a.losses),
                note: a.draws + a.unknown > 0
                    ? tr.heroes.drawsNote(a.draws, a.unknown)
                    : null,
              ),
              KpiTile(tr.heroes.winRateLabel, fmtPct(a.winRatePct)),
              KpiTile('KDA', fmtTwo(a.kda)),
              const SizedBox(width: 100000, height: 0),
              KpiTile(
                tr.heroes.avgDamage,
                mean('damage'),
                note: partial('damage'),
                color: c.statDamage,
              ),
              KpiTile(
                tr.heroes.avgHealing,
                mean('healing'),
                note: partial('healing'),
                color: c.statHealing,
              ),
              KpiTile(
                tr.heroes.avgMitigation,
                mean('mitigation'),
                note: partial('mitigation'),
                color: c.statMitigation,
              ),
            ],
          ),
      ],
    );
  }
}
