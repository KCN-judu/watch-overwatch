/// Comparisons: two heroes, two stretches of time, two players. See strings.dart.
class CompareStrings {
  const CompareStrings();

  // Two heroes.
  String get compareHero => '对比';
  String get compareHeroTip => '和另一个英雄并排比较';
  String get pickHero => '选择对比英雄';
  String get pickHeroTip => '同职责英雄在前。灰色为本赛季未使用，不可选。';
  String get current => '当前';
  String noMatchesTip(String hero) => '$hero：本赛季未使用';
  String get change => '换一个';
  String get close => '关闭对比';
  String heroesTitle(String a, String b) => '$a 对比 $b';
  String get differentRoles => '职责不同，同项数据含义不同，差值仅供参考。';
  String tooFew(String hero, int n) => '$hero 仅 $n 场，样本不足。';
  String get statColumn => '数据';
  String get diffColumn => '差值';
  String get per10Note => '每 10 分钟；比率、时长按每场。差值 = 左 − 右，括号内为相对右侧的百分比。';
  String get winRate => '胜率';
  String get matches => '场次';
  String get kda => 'KDA';
  String get playTime => '游戏时间';
  String rateNote(int n, String low, String high) => '$n 场，$low–$high';
  String get onlyOne => '—';

  // Two stretches of time (growth page).
  String get compareTime => '对比前一段';
  String get compareTimeTip => '最近一段与之前等长一段逐场对齐，横轴为段内第几场。';
  String recentStretch(int n) => '最近 $n 场';
  String earlierStretch(int n) => '之前 $n 场';
  String timeDiff(String now, String before, String diff, int n, int m) =>
      '最近 $n 场平均 $now，之前 $m 场平均 $before，$diff';
  String get timeTooFew => '至少需要 10 场（两段各 5 场）。';
  String nth(int i) => '第 $i 场';
  String get higher => '高';
  String get lower => '低';
  String diffWord(String word, String amount) => '$word $amount';
  String get same => '持平';

  // Two players (overview page).
  String get playersTitle => '与其他玩家对比';
  String get playersTip => '与本次打开过的其他玩家对比：同模式、同口径（本机已读取的对局），场次不同会标出。';
  String get playersNone => '再查找一名玩家即可对比。';
  String get playersPick => '选一名玩家';
  String samples(String a, int n, String b, int m) => '$a $n 场，$b $m 场';
  String get samplesDiffer => '双方场次差距较大，场次少的一方波动更大。';
  String get rowRecentRate => '近 20 场胜率';
  String get rowOverallRate => '总胜率';
  String get rowKda => 'KDA';
  String get rowKills => '场均消灭';
  String get rowDeaths => '场均阵亡';
  String get rowDamage => '场均伤害';
  String get rowHealing => '场均治疗';
  String get loadingOther => '正在计算对方数据…';
}
