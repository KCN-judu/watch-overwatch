import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_overwatch/design/chart_kit.dart';
import 'package:watch_overwatch/design/charts.dart';
import 'package:watch_overwatch/design/tokens.dart';

Widget host(Widget child) => MaterialApp(
  theme: ThemeData(extensions: [AppColors.dark]),
  home: Scaffold(
    body: SizedBox(width: 800, child: SingleChildScrollView(child: child)),
  ),
);

String pct(double v) => '${v.toStringAsFixed(0)}%';

void main() {
  testWidgets('a sparkline says where it starts and ends', (tester) async {
    await tester.pumpWidget(
      host(
        Sparkline(values: const [40, null, 45, 52], label: '胜率', format: pct),
      ),
    );
    expect(find.bySemanticsLabel('胜率：从 40% 到 52%'), findsOneWidget);
  });

  testWidgets('interval bars say value, range and count, and press through', (
    tester,
  ) async {
    var opened = '';
    await tester.pumpWidget(
      host(
        IntervalBars(
          format: pct,
          reference: 50,
          referenceMeaning: '50%',
          rows: [
            IntervalRow(
              label: '66号公路',
              value: 62,
              low: 48,
              high: 74,
              n: 21,
              onTap: () => opened = '66号公路',
            ),
            const IntervalRow(label: '花村', value: 100, n: 2, enough: false),
          ],
        ),
      ),
    );
    expect(find.bySemanticsLabel('66号公路：62%（区间 48%–74%），21 场'), findsOneWidget);
    expect(find.bySemanticsLabel('花村：100%，只有 2 场，样本太少'), findsOneWidget);
    await tester.tap(find.text('66号公路'));
    expect(opened, '66号公路');
  });

  testWidgets('heatmap cells with too few matches stay empty and say why', (
    tester,
  ) async {
    final cells = [
      for (var d = 0; d < 7; d++)
        [for (var h = 0; h < 24; h++) const HeatCell(null, 0)],
    ];
    cells[0][20] = const HeatCell(70, 10);
    cells[0][21] = const HeatCell(90, 1);
    await tester.pumpWidget(
      host(HourHeatmap(cells: cells, format: pct, metric: '胜率')),
    );
    expect(find.byTooltip('周一 20 点：70%，10 场'), findsOneWidget);
    expect(find.byTooltip('周一 21 点：1 场，太少不计'), findsOneWidget);
    final filled = tester
        .widgetList<Container>(find.byType(Container))
        .where(
          (c) =>
              c.decoration is BoxDecoration &&
              (c.decoration! as BoxDecoration).color != Colors.transparent &&
              (c.decoration! as BoxDecoration).color != null,
        );
    expect(filled.length, 1);
  });

  testWidgets('charts that share a cursor follow the one pointed at', (
    tester,
  ) async {
    final cursor = ValueNotifier<int?>(null);
    Widget chart() => LineChart(
      sync: cursor,
      series: const [
        ChartSeries(label: 'a', color: Colors.blue, values: [1, 2, 3, 4]),
      ],
      xLabels: const ['1', '2', '3', '4'],
      summary: 's',
      valueFormat: (v) => '$v',
    );
    await tester.pumpWidget(host(Column(children: [chart(), chart()])));
    await tester.pumpAndSettle();
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    final box = tester.getRect(find.byType(LineChart).first);
    await gesture.addPointer(location: box.center);
    await gesture.moveTo(Offset(box.right - 100, box.center.dy));
    await tester.pump();
    expect(cursor.value, 3);
    cursor.value = 0;
    await tester.pump();
    expect(cursor.value, 0);
    await gesture.removePointer();
  });
}
