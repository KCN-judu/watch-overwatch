/// The recap (overview → 回顾) and share pictures. See strings.dart for the rules.
class RecapStrings {
  const RecapStrings();

  String get open => '回顾';
  String get openTip => '一步一步看这段时间：打了多少、最常玩、最强的图、进步最大的一项、最好的一局；可以存成一张长图。';
  String get title => '回顾';
  String caption(String name, String mode, int n) =>
      '$name · $mode · 本机已读取的 $n 场对局';
  String get fileName => '回顾';
  String get stepMatches => '这段时间打了';
  String matchesNote(String rate, int w, int l, String? week) =>
      week == null ? '胜率 $rate（$w 胜 $l 负）' : '胜率 $rate（$w 胜 $l 负）。本周 $week。';
  String get stepHero => '最常玩的英雄';
  String heroNote(int n, String rate) => '$n 场，胜率 $rate';
  String get stepMap => '最强的地图';
  String get guessPrompt => '先猜一猜：下面哪张图胜率最有把握地高？';
  String mapNote(int n, String rate, String? verdict) =>
      verdict == null ? '$n 场，胜率 $rate' : '$verdict $n 场，胜率 $rate';
  String get guessRight => '猜对了！';
  String get guessWrong => '不是它。';
  String get stepImproved => '进步最大的一项';
  String improvedNote(String pct, int n) =>
      '较新的一半对局比较早的一半高 $pct（$n 场，成长页的趋势检验）';
  String get stepBest => '最好的一局';
  String bestNote(String hero, String map, String when) =>
      '$hero · $map · $when 赢下';
  String get openBest => '打开这一局';
  String get previous => '上一步';
  String get next => '下一步';
  String get showAll => '全部显示';
  String get stepByStep => '一步一步看';
  String position(int i, int n) => '$i / $n';

  // Share pictures.
  String get shareCopy => '复制为图片';
  String get shareSave => '保存为 PNG';
  String get shareCopied => '已复制图片';
  String get shareCopyFailed => '复制图片失败，可以改用保存为 PNG';
  String shareSaved(String path) => '已保存到 $path';
  String shareSaveFailed(String why) => '保存失败：$why';
  String shareFooter(String caption) => '$caption · Watch Overwatch';
  String get maskNames => '图片里隐藏玩家昵称';
  String get maskNamesTip => '开启后，分享的图片里玩家昵称显示为“玩家”。';
  String get masked => '玩家';
  String get namesShown => '显示';
  String get namesHidden => '隐藏';
}
