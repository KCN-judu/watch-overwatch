import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_overwatch/core/models.dart';
import 'package:watch_overwatch/core/support.dart';
import 'package:watch_overwatch/design/icons.dart';
import 'package:watch_overwatch/design/tokens.dart';

void main() {
  testWidgets('a looked-up rank says it is the snapshot taken for the match', (
    tester,
  ) async {
    final at = DateTime(2026, 10, 22, 21, 5).millisecondsSinceEpoch;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [AppColors.dark]),
        home: Scaffold(
          body: RankBadge(
            const Rank(null, null, null, 2600),
            catalog: Catalog(null),
            snapshotMs: at,
          ),
        ),
      ),
    );
    final tip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tip.message, contains('快照'));
    expect(tip.message, contains(fmtDateTime(at)));
  });

  test('the background job reads its state', () {
    final job = RankJob({'state': 'paused', 'done': 4, 'remaining': 12});
    expect(job.paused, isTrue);
    expect(job.finished, isFalse);
    expect(RankJob.opt(null), isNull);
    expect(RankJob.opt({'state': 'done'})!.finished, isTrue);
  });

  test(
    'the three states come from the service, an older answer from the match',
    () {
      final ranked = RankState.fromJson({
        'state': 'ranked',
        'source': 'snapshot',
        'rank': {'skill_rating': 2600},
        'other_roles': true,
        'at_ms': 5,
      }, null);
      expect(
        ranked,
        isA<Ranked>()
            .having((r) => r.fromMatch, 'fromMatch', false)
            .having((r) => r.otherRoles, 'otherRoles', true)
            .having((r) => r.atMs, 'atMs', 5),
      );
      expect(
        RankState.fromJson({'state': 'unranked', 'at_ms': 7}, null),
        isA<Unranked>().having((u) => u.atMs, 'atMs', 7),
      );
      expect(RankState.fromJson({'state': 'querying'}, null), isA<Querying>());
      const inMatch = Rank('Gold', 2, null, 1850);
      expect(
        RankState.fromJson(null, inMatch),
        isA<Ranked>().having((r) => r.fromMatch, 'fromMatch', true),
      );
      expect(RankState.fromJson(null, null), isA<Querying>());
    },
  );

  testWidgets('each state draws its own cell', (tester) async {
    Future<void> show(RankState s) => tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [AppColors.dark]),
        home: Scaffold(body: RankCell(s, catalog: Catalog(null))),
      ),
    );
    await show(const Unranked(atMs: 0));
    expect(find.text('未定级'), findsOneWidget);
    await show(const Querying());
    expect(find.text('查询中'), findsOneWidget);
    await show(const Ranked(Rank(null, null, null, 2600), fromMatch: false));
    expect(find.text('未定级'), findsNothing);
    expect(find.text('查询中'), findsNothing);
    expect(find.byType(RankBadge), findsOneWidget);
  });
}
