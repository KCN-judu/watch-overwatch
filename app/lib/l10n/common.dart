/// Words and actions used on many pages. See strings.dart for the rules.
class CommonStrings {
  const CommonStrings();

  /// A value the provider did not supply (never shown as 0).
  String get missing => '—';

  /// Joins items of a list inside a sentence: 胜、负.
  String list(Iterable<String> items) => items.join('、');

  /// Separates facts on one line: 10-21 16:33 · 运载目标.
  String get dot => ' · ';

  String get retry => '重试';
  String get cancel => '取消';
  String get close => '关闭';
  String get back => '返回';
  String get refresh => '刷新';
  String get openSettings => '打开设置';
  String get clearFilters => '清除筛选';
  String get copyDetails => '复制详情';
  String get detailsCopied => '详情已复制';
  String get loading => '正在读取';
  String get refreshing => '正在刷新…';
  String get ally => '己方';
  String get enemy => '对方';
  String get unknownMap => '未知地图';
  String get unknownHero => '未知英雄';
  String get unknownPlayer => '未知玩家';
  String get unranked => '未定级';

  /// N 场.
  String matchCount(int n) => '$n 场';

  /// 第 N 赛季.
  String season(int n) => '第 $n 赛季';
}
