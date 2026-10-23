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
}
