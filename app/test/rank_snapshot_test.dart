import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_overwatch/core/models.dart';
import 'package:watch_overwatch/core/support.dart';
import 'package:watch_overwatch/design/icons.dart';
import 'package:watch_overwatch/design/tokens.dart';

Widget host(Widget child) => MaterialApp(
  theme: ThemeData(extensions: [AppColors.dark]),
  home: Scaffold(body: child),
);

void main() {
  test('the snapshot is three roles, each in one of three states', () {
    final career = RoleRanks.fromJson({
      'tank': {
        'state': 'ranked',
        'rank': {'skill_rating': 2600},
      },
      'damage': {'state': 'unranked'},
    });
    expect(career.tank, isA<Ranked>());
    expect(career.damage, isA<Unranked>());
    expect(career.support, isA<Querying>(), reason: 'missing is not known');
  });

  test(
    'what is shown comes from the service; an older answer from the match',
    () {
      expect(
        ShownRank.fromJson({
          'state': 'ranked',
          'rank': {'skill_rating': 2600},
          'basis': 'other_roles',
        }, null),
        isA<ShownRanked>().having(
          (r) => r.basis,
          'basis',
          RankBasis.otherRoles,
        ),
      );
      expect(
        ShownRank.fromJson({'state': 'unranked'}, null),
        isA<ShownUnranked>(),
      );
      expect(
        ShownRank.fromJson({'state': 'querying'}, null),
        isA<ShownQuerying>(),
      );
      expect(
        ShownRank.fromJson(null, const Rank('Gold', 2, null, 1850)),
        isA<ShownRanked>().having((r) => r.basis, 'basis', RankBasis.match),
      );
    },
  );

  testWidgets('each shown state draws its own cell, the roles on hover', (
    tester,
  ) async {
    const career = RoleRanks(
      Ranked(Rank(null, null, null, 2600)),
      Unranked(),
      Querying(),
    );
    Future<void> show(ShownRank s) => tester.pumpWidget(
      host(RankCell(s, career: career, catalog: Catalog(null))),
    );
    await show(const ShownUnranked());
    expect(find.text('未定级'), findsOneWidget);
    await show(const ShownQuerying());
    expect(find.text('查询中'), findsOneWidget);
    final tip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tip.message, contains('重装'));
    expect(tip.message, contains('未定级'));
    await show(
      const ShownRanked(Rank(null, null, null, 2600), RankBasis.otherRoles),
    );
    expect(find.byType(RankBadge), findsOneWidget);
    final badge = tester.widget<RankBadge>(find.byType(RankBadge));
    expect((badge.snapshot, badge.otherRoles), (true, true));
  });

  test('the background job reads its state, retries included', () {
    final job = RankJob({'state': 'paused', 'done': 4, 'remaining': 12});
    expect(job.state, RankJobState.paused);
    expect(job.finished, isFalse);
    final retry = RankJob({
      'state': 'retrying',
      'remaining': 3,
      'retry_in_s': 30,
    });
    expect(
      (retry.state, retry.retryInS, retry.finished),
      (RankJobState.retrying, 30, false),
    );
    expect(RankJob.opt(null), isNull);
    expect(RankJob.opt({'state': 'done'})!.finished, isTrue);
  });
}
