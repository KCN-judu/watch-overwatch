import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_overwatch/design/cards.dart';
import 'package:watch_overwatch/design/tokens.dart';
import 'package:watch_overwatch/design/widgets.dart';

Widget host(Widget child) => MaterialApp(
  theme: ThemeData(extensions: [AppColors.dark]),
  home: Scaffold(
    body: Center(
      child: SizedBox(width: 400, child: CardGrid(minWidth: 300, [child])),
    ),
  ),
);

void main() {
  testWidgets('an info card centres its icon and its text on the card height', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const InfoCard(
          name: '组队',
          description: '没有组队信息',
          glyph: Icons.groups_outlined,
          accent: Colors.blue,
        ),
      ),
    );
    final card = tester.getRect(find.byType(CardSurface));
    final icon = tester.getRect(find.byIcon(Icons.groups_outlined));
    final name = tester.getRect(find.text('组队'));
    final text = tester.getRect(find.text('没有组队信息'));
    expect(icon.center.dy, closeTo(card.center.dy, 1));
    // The two lines of text, taken together, sit on the middle of the card too.
    final block = Rect.fromLTRB(name.left, name.top, text.right, text.bottom);
    expect(block.center.dy, closeTo(card.center.dy, 2));
  });

  testWidgets('cards are plain rectangles', (tester) async {
    await tester.pumpWidget(
      host(const StatCard(label: '消灭', value: '12', accent: Colors.blue)),
    );
    final box = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byType(CardSurface),
        matching: find.byType(DecoratedBox),
      ),
    );
    expect((box.decoration as BoxDecoration).borderRadius, isNull);
    expect(find.byType(ClipRRect), findsNothing);
  });

  testWidgets('a perk card shows its tier only when given one', (tester) async {
    await tester.pumpWidget(
      host(const PerkCard(name: '灵利卜师', level: 1, accent: Colors.blue)),
    );
    expect(find.text('一级威能'), findsOneWidget);
    await tester.pumpWidget(
      host(const PerkCard(name: '灵利卜师', accent: Colors.blue)),
    );
    expect(find.text('一级威能'), findsNothing);
  });

  testWidgets('a fold section hides its content when folded and opens again', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const FoldSection(
          title: '每 10 分钟',
          accent: Colors.blue,
          child: Text('内容'),
        ),
      ),
    );
    expect(find.text('内容'), findsOneWidget);
    await tester.tap(find.text('每 10 分钟'));
    await tester.pump();
    expect(find.text('内容'), findsNothing);
    await tester.tap(find.text('每 10 分钟'));
    await tester.pump();
    expect(find.text('内容'), findsOneWidget);
  });

  testWidgets('a status banner of every severity paints', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [AppColors.dark]),
        home: const Scaffold(
          body: Column(
            children: [
              StatusBanner(severity: Severity.info, title: '提示'),
              StatusBanner(severity: Severity.warning, title: '注意'),
              StatusBanner(severity: Severity.error, title: '出错', detail: '详情'),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('注意'), findsOneWidget);
  });
}
