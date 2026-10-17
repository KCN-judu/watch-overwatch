import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_overwatch/design/data_table.dart';
import 'package:watch_overwatch/design/tokens.dart';

Widget host(Widget child) => MaterialApp(
  theme: buildTheme(Brightness.dark),
  home: DensityScope(
    density: DensityMode.standard,
    child: Scaffold(
      body: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  ),
);

void main() {
  embeddedTests();
  final rows = List.generate(40, (i) => i);
  List<Col<int>> cols() => [
    Col(
      id: 'n',
      label: '序号',
      width: 80,
      flex: true,
      cell: (_, r) => Text('行 $r'),
      sortKey: (r) => r,
    ),
    Col(
      id: 'v',
      label: '数值',
      width: 80,
      numeric: true,
      cell: (_, r) => Text('${r * 100}'),
    ),
  ];

  testWidgets(
    'a table opens at the top, with the header and first row visible',
    (t) async {
      final ctl = ScrollController();
      await t.pumpWidget(
        host(
          SizedBox(
            height: 400,
            child: AppTable<int>(
              tableLabel: '测试表',
              columns: cols(),
              rows: rows,
              rowLabel: (r) => '行 $r',
              controller: ctl,
            ),
          ),
        ),
      );
      expect(ctl.offset, 0);
      expect(find.text('行 0'), findsOneWidget);
      expect(find.text('序号'), findsOneWidget);
    },
  );

  testWidgets(
    'arrow keys move the active row and keep it in view; Enter opens it',
    (t) async {
      final ctl = ScrollController();
      int? opened;
      await t.pumpWidget(
        host(
          SizedBox(
            height: 400,
            child: AppTable<int>(
              tableLabel: '测试表',
              columns: cols(),
              rows: rows,
              rowLabel: (r) => '行 $r',
              controller: ctl,
              onOpen: (r, _) => opened = r,
            ),
          ),
        ),
      );
      await t.tap(find.text('行 2')); // focuses the body and opens row 2
      await t.pump();
      expect(opened, 2);
      await t.sendKeyEvent(LogicalKeyboardKey.end);
      await t.pump();
      expect(ctl.offset, greaterThan(0));
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(opened, 39);
      await t.sendKeyEvent(LogicalKeyboardKey.home);
      await t.pump();
      expect(ctl.offset, 0);
    },
  );

  testWidgets('an empty table keeps its header and shows the empty state', (
    t,
  ) async {
    await t.pumpWidget(
      host(
        SizedBox(
          height: 300,
          child: AppTable<int>(
            tableLabel: '测试表',
            columns: cols(),
            rows: const [],
            rowLabel: (r) => '',
            empty: const Center(child: Text('没有数据')),
          ),
        ),
      ),
    );
    expect(find.text('序号'), findsOneWidget);
    expect(find.text('没有数据'), findsOneWidget);
  });
}

void embeddedTests() {
  testWidgets('a table inside a scrolling page still opens a row when tapped', (
    t,
  ) async {
    int? opened;
    await t.pumpWidget(
      host(
        ListView(
          children: [
            const SizedBox(height: 300),
            SizedBox(
              height: 300,
              child: AppTable<int>(
                tableLabel: '嵌套表',
                columns: [
                  Col(
                    id: 'n',
                    label: '序号',
                    width: 80,
                    flex: true,
                    cell: (_, r) => Text('行 $r'),
                  ),
                ],
                rows: const [0, 1, 2],
                rowLabel: (r) => '行 $r',
                onOpen: (r, _) => opened = r,
              ),
            ),
          ],
        ),
      ),
    );
    await t.tap(find.text('行 1'));
    await t.pump();
    expect(opened, 1);
  });
}
