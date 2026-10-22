import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_overwatch/design/charts.dart';
import 'package:watch_overwatch/design/tokens.dart';

void main() {
  testWidgets('a chart draws shielded columns and says what the shield means', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [AppColors.dark]),
        home: Scaffold(
          body: SizedBox(
            width: 600,
            child: LineChart(
              yMin: 0,
              series: const [
                ChartSeries(
                  label: '存活时长',
                  color: Colors.grey,
                  values: [120, 300, null, 90],
                ),
              ],
              xLabels: const ['10-01', '10-02', '10-03', '10-04'],
              summary: '四场',
              valueFormat: (v) => '${v.round()}',
              shielded: const [false, true, false, true],
              shieldMeaning: '盾牌：没有死亡',
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('盾牌：没有死亡'), findsOneWidget);
  });

  testWidgets('a second click on the column in the readout opens it', (
    tester,
  ) async {
    int? opened;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [AppColors.dark]),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 600,
              child: LineChart(
                series: const [
                  ChartSeries(
                    label: '段位分',
                    color: Colors.grey,
                    values: [2000, 2100, 2050],
                    stepped: true,
                  ),
                ],
                xLabels: const ['10-01', '10-02', '10-03'],
                summary: '三场',
                valueFormat: (v) => '${v.round()}',
                markers: const [(index: 1, label: 'S25')],
                onOpen: (i) => opened = i,
                openHint: '点两下打开',
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('点两下打开'), findsOneWidget);
    final chart = find.byType(CustomPaint).last;
    final box = tester.getRect(chart);
    // Column 1 sits in the middle of the plot (48 px gutter left, 96 px right).
    final at = Offset(box.left + 48 + (box.width - 144) / 2, box.center.dy);
    await tester.tapAt(at);
    await tester.pump();
    expect(opened, isNull);
    await tester.tapAt(at);
    expect(opened, 1);
  });
}
