import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_overwatch/core/api.dart';
import 'package:watch_overwatch/core/support.dart';
import 'package:watch_overwatch/core/update.dart';
import 'package:watch_overwatch/design/tokens.dart';
import 'package:watch_overwatch/state/app_state.dart';
import 'package:watch_overwatch/ui/update_dialog.dart';

Map<String, Object?> answer({bool installable = true, Object? download}) => {
  'current': '1.2.0',
  'newer': true,
  'installable': installable,
  'latest': {
    'version': '1.3.0',
    'name': 'Watch Overwatch 1.3.0',
    'notes':
        '# Watch Overwatch 1.3.0\n\n## 新增\n\n- **每日总结**：一天一页\n- 见[文档](https://example.test)',
    'published_at': '2026-10-24T08:00:00Z',
    'page_url': 'https://example.test/release',
    'zip_size': 24 * 1048576,
  },
  'download': download ?? {'state': 'idle'},
};

Future<AppState> open(WidgetTester tester, Map<String, Object?> j) async {
  tester.view.physicalSize = const Size(1200, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final app = AppState(Backend(), UiState())..update = UpdateInfo(j);
  app.updateDownload = app.update!.download.state == 'idle'
      ? null
      : app.update!.download;
  await tester.pumpWidget(
    // Above the app, as in main.dart, so the dialog's route sees it.
    AppScope(
      state: app,
      child: MaterialApp(
        theme: ThemeData(extensions: [AppColors.dark]),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showUpdateDialog(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return app;
}

void main() {
  testWidgets('a newer release shows its version, size and notes as text', (
    tester,
  ) async {
    await open(tester, answer());
    expect(find.text('1.3.0 可以更新（当前 1.2.0）'), findsOneWidget);
    expect(find.textContaining('24.0 MB'), findsOneWidget);
    expect(find.text('新增'), findsOneWidget);
    expect(find.text('每日总结：一天一页'), findsOneWidget); // ** dropped
    expect(find.text('见文档'), findsOneWidget); // link reduced to its text
    expect(find.text('下载更新'), findsOneWidget);
    expect(find.text('以后再说'), findsOneWidget);
  });

  testWidgets('a downloaded release offers the restart', (tester) async {
    await open(
      tester,
      answer(
        download: {
          'state': 'ready',
          'version': '1.3.0',
          'received': 10,
          'total': 10,
        },
      ),
    );
    expect(find.text('重启并更新'), findsOneWidget);
    expect(find.text('已下载并校验，重启后即为新版本。'), findsOneWidget);
  });

  testWidgets('a development build is told to download by hand', (
    tester,
  ) async {
    await open(tester, answer(installable: false));
    expect(find.text('当前是开发构建，不能自动安装。请到网页下载发布包。'), findsOneWidget);
    expect(find.text('下载更新'), findsNothing);
    expect(find.text('在网页查看'), findsOneWidget);
  });
}
