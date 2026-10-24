import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_overwatch/core/api.dart';
import 'package:watch_overwatch/core/support.dart';
import 'package:watch_overwatch/design/tokens.dart';
import 'package:watch_overwatch/state/app_state.dart';
import 'package:watch_overwatch/state/commands.dart';
import 'package:watch_overwatch/ui/shell.dart';

class FakeActions implements ShellActions {
  int searches = 0;
  @override
  void focusSearch() => searches++;
  @override
  void noSuchMethod(Invocation invocation) {}
}

Widget host(AppState app, FakeActions actions, bool hasAccount) => MaterialApp(
  theme: ThemeData(extensions: [AppColors.dark]),
  home: Scaffold(
    body: AppScope(
      state: app,
      child: ShellScope(
        searchFocus: FocusNode(),
        filterFocus: FocusNode(),
        actions: actions,
        child: FirstRun(hasAccount: hasAccount),
      ),
    ),
  ),
);

void main() {
  testWidgets('a new user sees three steps and the sample player', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final app = AppState(Backend(), UiState());
    final actions = FakeActions();
    await tester.pumpWidget(host(app, actions, false));
    expect(find.text('添加大神账号'), findsOneWidget);
    expect(find.text('添加账号'), findsOneWidget);
    expect(find.text('输入战网昵称'), findsOneWidget);
    expect(find.text('打开示例玩家'), findsOneWidget);
    await tester.tap(find.text('查找玩家'));
    expect(actions.searches, 1);

    await tester.pumpWidget(host(app, actions, true));
    expect(find.text('已添加账号'), findsOneWidget);
    expect(find.text('添加账号'), findsNothing);
  });

  testWidgets('a service built without the sample player offers no sample', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final app = AppState(Backend(), UiState())
      ..server = {'demo': false, 'accounts': <Object?>[]};
    await tester.pumpWidget(host(app, FakeActions(), false));
    expect(find.text('输入战网昵称'), findsOneWidget);
    expect(find.text('打开示例玩家'), findsNothing);
    expect(find.text('三步查看战绩。'), findsOneWidget);
  });
}
