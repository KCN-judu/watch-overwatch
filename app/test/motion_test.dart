import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_overwatch/design/card_list.dart';
import 'package:watch_overwatch/design/motion.dart';
import 'package:watch_overwatch/design/tokens.dart';

Widget host(Widget child, {bool reduce = false}) => MaterialApp(
  theme: ThemeData(extensions: [AppColors.dark]),
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduce),
    child: Scaffold(body: child),
  ),
);

void main() {
  testWidgets(
    'fade-through shows both while switching, then only the new one',
    (tester) async {
      await tester.pumpWidget(
        host(const FadeThrough(childKey: 'a', child: Text('A'))),
      );
      await tester.pumpWidget(
        host(const FadeThrough(childKey: 'b', child: Text('B'))),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('A'), findsNothing);
      expect(find.text('B'), findsOneWidget);
    },
  );

  testWidgets('with reduced motion the switch is immediate', (tester) async {
    await tester.pumpWidget(
      host(const FadeThrough(childKey: 'a', child: Text('A')), reduce: true),
    );
    await tester.pumpWidget(
      host(const FadeThrough(childKey: 'b', child: Text('B')), reduce: true),
    );
    await tester.pump();
    expect(find.text('A'), findsNothing);
    expect(find.text('B'), findsOneWidget);
  });

  testWidgets('a changed figure fades in place; the first one just appears', (
    tester,
  ) async {
    await tester.pumpWidget(host(const AnimatedValueText('12')));
    expect(find.byType(FadeTransition), findsWidgets);
    expect(find.text('12'), findsOneWidget);
    await tester.pumpWidget(host(const AnimatedValueText('13')));
    await tester.pump(const Duration(milliseconds: 40));
    expect(find.text('12'), findsOneWidget);
    expect(find.text('13'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('12'), findsNothing);
  });

  testWidgets('only rows that arrive after the list is shown play in', (
    tester,
  ) async {
    Widget list(List<String> rows) => host(
      SizedBox(
        height: 600,
        child: CardList<String>(
          rows: rows,
          itemExtent: 60,
          rowKey: (r) => r,
          rowLabel: (r) => r,
          listLabel: 'list',
          builder: (_, r, _) => Text(r),
        ),
      ),
    );
    await tester.pumpWidget(list(['old 1', 'old 2']));
    expect(find.byType(ArriveOnce), findsNothing);
    await tester.pumpWidget(list(['new', 'old 1', 'old 2']));
    expect(
      find.ancestor(of: find.text('new'), matching: find.byType(ArriveOnce)),
      findsOneWidget,
    );
    expect(
      find.ancestor(of: find.text('old 1'), matching: find.byType(ArriveOnce)),
      findsNothing,
    );
    await tester.pumpAndSettle();
    // Built again (a rebuild, or scrolled away and back): it does not play again.
    await tester.pumpWidget(list(['new', 'old 1', 'old 2']));
    expect(find.byType(ArriveOnce), findsNothing);
  });
}
