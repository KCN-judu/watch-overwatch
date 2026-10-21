import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_overwatch/core/api.dart';
import 'package:watch_overwatch/core/models.dart';
import 'package:watch_overwatch/core/support.dart';
import 'package:watch_overwatch/design/tokens.dart';
import 'package:watch_overwatch/design/widgets.dart';
import 'package:watch_overwatch/state/app_state.dart';
import 'package:watch_overwatch/state/commands.dart';
import 'package:watch_overwatch/ui/pages/matches_page.dart';
import 'package:watch_overwatch/ui/shell.dart' show ShellScope;

class _NoShell implements ShellActions {
  @override
  void openPalette() {}
  @override
  void openShortcuts() {}
  @override
  void openExport() {}
  @override
  void showSettings() {}
  @override
  void focusSearch() {}
  @override
  void focusPane(bool forward) {}
  @override
  void focusFilter() {}
}

/// A matches page for one player in quick play, with nothing talking to a service.
({AppState app, PlayerWorkspace ws, Widget page}) setUp() {
  final app = AppState(Backend(), UiState())..mode = Mode.quick;
  final ws = PlayerWorkspace(app, 'KCN#51896');
  final page = MaterialApp(
    theme: ThemeData(extensions: [AppColors.dark]),
    home: Scaffold(
      body: AppScope(
        state: app,
        child: ShellScope(
          searchFocus: FocusNode(),
          filterFocus: FocusNode(),
          actions: _NoShell(),
          // The player view rebuilds its page whenever the workspace changes.
          child: ListenableBuilder(
            listenable: ws,
            builder: (_, _) => MatchesPage(workspace: ws),
          ),
        ),
      ),
    ),
  );
  return (app: app, ws: ws, page: page);
}

PlayerDataset dataset(List<Map<String, Object?>> matches) =>
    PlayerDataset({'generated_at_ms': 0, 'matches': matches});

Map<String, Object?> match(String id, String outcome) => {
  'id': id,
  'started_at_ms': 1767283200000,
  'kind': {'mode': 'quick', 'queue': 'role_queue'},
  'outcome': outcome,
  'role': 'support',
  'score': {'team': 3, 'opponent': 0},
  'stats': <String, Object?>{},
};

void main() {
  testWidgets('a first load shows the list skeleton, not an empty state', (
    tester,
  ) async {
    final t = setUp();
    t.ws.matchesFor(Mode.quick).loading = true;
    await tester.pumpWidget(t.page);
    expect(find.byType(EmptyState), findsNothing);
    expect(find.byType(ErrorPanel), findsNothing);
    expect(find.bySemanticsLabel('正在加载'), findsOneWidget);
  });

  testWidgets('a failure with nothing read offers a retry', (tester) async {
    final t = setUp();
    t.ws.matchesFor(Mode.quick).error = ApiError('upstream', '网络错误');
    await tester.pumpWidget(t.page);
    expect(find.byType(ErrorPanel), findsOneWidget);
    expect(find.textContaining('无法读取快速比赛的对局'), findsOneWidget);
    expect(find.text('打开设置'), findsNothing);
  });

  testWidgets('an auth failure also points to the settings', (tester) async {
    final t = setUp();
    t.ws.matchesFor(Mode.quick).error = ApiError('auth', '凭据失效');
    await tester.pumpWidget(t.page);
    expect(find.text('打开设置'), findsOneWidget);
  });

  testWidgets(
    'no matches in the mode is said so, with the other modes offered',
    (tester) async {
      final t = setUp();
      t.ws.matchesFor(Mode.quick).value = dataset(const []);
      await tester.pumpWidget(t.page);
      expect(find.text('KCN#51896 在快速比赛没有对局记录'), findsOneWidget);
      expect(find.text('切换到竞技比赛'), findsOneWidget);
      expect(find.text('切换到角斗领域'), findsOneWidget);
    },
  );

  testWidgets(
    'matches are listed, and filtering them all away is not "no record"',
    (tester) async {
      final t = setUp();
      t.ws.matchesFor(Mode.quick).value = dataset([
        match('a', 'win'),
        match('b', 'loss'),
      ]);
      await tester.pumpWidget(t.page);
      expect(find.byType(EmptyState), findsNothing);
      expect(find.text('胜'), findsWidgets);
      expect(find.text('负'), findsWidgets);

      t.ws.filtersFor(Mode.quick).outcomes.add(Outcome.draw);
      t.ws.touch();
      await tester.pump();
      expect(find.text('没有符合筛选的对局'), findsOneWidget);
      // The empty state's own button (the scope line above has one too).
      await tester.tap(
        find.descendant(
          of: find.byType(EmptyState),
          matching: find.text('清除筛选'),
        ),
      );
      await tester.pump();
      expect(find.text('没有符合筛选的对局'), findsNothing);
    },
  );
}
