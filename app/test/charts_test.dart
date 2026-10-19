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
}
