/// Comparisons: two heroes, two stretches of time, two players. See strings.dart.
class CompareStrings {
  const CompareStrings();

  // Two heroes.
  String get compareHero => '对比';
  String get compareHeroTip => '和另一个英雄并排比较';
  String get pickHero => '选一个英雄来对比';
  String get pickHeroTip => '同职责的英雄排在前面。只列出本赛季玩过的英雄。';
  String get change => '换一个';
  String get close => '关闭对比';
  String heroesTitle(String a, String b) => '$a 对比 $b';
  String get differentRoles => '两个英雄职责不同：同一项数据的意义不一样（比如治疗之于重装和支援），差值只作参考。';
  String tooFew(String hero, int n) => '$hero 只有 $n 场，数字很不稳定。';
  String get statColumn => '数据';
  String get diffColumn => '差值';
  String get per10Note => '每 10 分钟；没有每 10 分钟意义的项（比率、时长）用每场。差值是左减右，后面是相对右边的百分比。';
  String get winRate => '胜率';
  String get matches => '场次';
  String get kda => 'KDA';
  String get playTime => '游戏时间';
  String rateNote(int n, String low, String high) => '$n 场 · 可能 $low – $high';
  String get onlyOne => '—';

  // Two stretches of time (growth page).
  String get compareTime => '对比前一段';
  String get compareTimeTip => '把最近一段和它之前同样长的一段逐场对齐来比：横轴是这一段里的第几场。';
  String recentStretch(int n) => '最近 $n 场';
  String earlierStretch(int n) => '之前 $n 场';
  String timeDiff(String now, String before, String diff, int n, int m) =>
      '最近 $n 场平均 $now，之前 $m 场平均 $before，$diff';
  String get timeTooFew => '对比需要至少 10 场：两段各 5 场。';
  String nth(int i) => '第 $i 场';
  String get higher => '高';
  String get lower => '低';
  String diffWord(String word, String amount) => '$word $amount';
  String get same => '持平';

  // Two players (overview page).
  String get playersTitle => '与其他玩家对比';
  String get playersTip => '和这次打开过的另一名玩家比较，同一模式、同一口径：都只用本机已读取的对局。双方场次不同时会写明。';
  String get playersNone => '再查找一名玩家，就能在这里和该玩家对比。';
  String get playersPick => '选一名玩家';
  String samples(String a, int n, String b, int m) => '$a 用了 $n 场，$b 用了 $m 场。';
  String get samplesDiffer => '双方场次相差较大，样本少的一方数字更不稳定。';
  String get rowRecentRate => '近 20 场胜率';
  String get rowOverallRate => '总胜率';
  String get rowKda => 'KDA';
  String get rowKills => '场均消灭';
  String get rowDeaths => '场均阵亡';
  String get rowDamage => '场均伤害';
  String get rowHealing => '场均治疗';
  String get loadingOther => '正在计算对方的概览…';
}
