/// The recap (overview → 回顾) and share pictures. See strings.dart for the rules.
class RecapStrings {
  const RecapStrings();

  String get open => '回顾';
  String get openTip => '总场次、最常用英雄、强势图、提升最大的数据、最佳一局，可导出长图。';
  String get title => '回顾';
  String caption(String name, String mode, int n) =>
      '$name · $mode · 本机已读取的 $n 场对局';
  String get fileName => '回顾';
  String get stepMatches => '总场次';
  String matchesNote(String rate, int w, int l, String? week) =>
      week == null ? '胜率 $rate（$w 胜 $l 负）' : '胜率 $rate（$w 胜 $l 负）。本周 $week。';
  String get stepHero => '最常用英雄';
  String heroNote(int n, String rate) => '$n 场，胜率 $rate';
  String get stepMap => '强势图';
  String get guessPrompt => '猜一猜：哪张是强势图';
  String mapNote(int n, String rate, String? verdict) =>
      verdict == null ? '$n 场，胜率 $rate' : '$verdict $n 场，胜率 $rate';
  String get guessRight => '猜中了';
  String get guessWrong => '不是这张';
  String get stepImproved => '提升最大';
  String improvedNote(String pct, int n) => '后半段比前半段高 $pct（$n 场）';
  String get stepBest => '最佳一局';
  String bestNote(String hero, String map, String when) =>
      '$hero · $map · $when';
  String get openBest => '查看本局';
  String get previous => '上一步';
  String get next => '下一步';
  String get showAll => '全部显示';
  String get stepByStep => '一步一步看';
  String position(int i, int n) => '$i / $n';

  // Share pictures.
  String get shareCopy => '复制为图片';
  String get shareSave => '保存为 PNG';
  String get shareCopied => '已复制图片';
  String get shareCopyFailed => '复制失败，请改用保存为 PNG';
  String shareSaved(String path) => '已保存到 $path';
  String shareSaveFailed(String why) => '保存失败：$why';
  String shareFooter(String caption) => '$caption · Watch Overwatch';
  String get maskNames => '图片里隐藏玩家昵称';
  String get maskNamesTip => '分享图里的昵称显示为“玩家”。';
  String get masked => '玩家';
  String get namesShown => '显示';
  String get namesHidden => '隐藏';
}
