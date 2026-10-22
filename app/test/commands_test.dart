import 'package:flutter_test/flutter_test.dart';
import 'package:watch_overwatch/state/app_state.dart';
import 'package:watch_overwatch/state/commands.dart';

void main() {
  test('every tab has its own Ctrl+digit shortcut', () {
    final cmds = buildCommands();
    final tabs = [
      for (final id in tabIds) cmds.firstWhere((c) => c.id == 'view.tab.$id'),
    ];
    expect(tabs.length, tabIds.length);
    expect({for (final c in tabs) c.shortcutLabel}.length, tabIds.length);
    expect(tabIds.length, lessThanOrEqualTo(9));
  });
}
