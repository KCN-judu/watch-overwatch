/// The overview page. See strings.dart for the rules.
class OverviewStrings {
  const OverviewStrings();

  String get winRateRecent => '近 20 场胜率';
  String get recordRecent => '近 20 场战绩';
  String get kdaRecent => '近 20 场 KDA';
  String get today => '今天';
  String record(int w, int l, int d) => d > 0 ? '$w 胜 $l 负 $d 平' : '$w 胜 $l 负';
  String get noMatchesToday => '今天还没有对局';
  String versusBefore(String delta) => '比之前 20 场 $delta';
  String get notEnoughBefore => '之前不足 20 场，暂无对比';
  String get rollingLabel => '每 10 场的胜率';
  String coverage(int n, String mode) => '$mode · 本机已读取的 $n 场对局';
  String get coverageTip => '概览只用本机已读取的对局计算，不向上游请求；对局页读到更多对局后会自动更新。胜率不计平局。';

  String get formTitle => '最近 20 场';
  String formTip(String result, String map, String hero, String time) =>
      '$result · $map · $hero · $time';
  String get formHint => '点一场打开详情';

  String get insightsTitle => '值得注意';
  String streakWin(int n) => '已经连胜 $n 场';
  String streakLoss(int n) => '已经连败 $n 场，可以考虑休息一下';
  String recentUp(String now, String then) =>
      '近 20 场胜率 $now，比之前 20 场的 $then 明显更高';
  String recentDown(String now, String then) =>
      '近 20 场胜率 $now，比之前 20 场的 $then 明显更低';
  String mapUp(String map, String rate, int n, String overall) =>
      '$map 是该玩家的强图：$n 场胜率 $rate，整个区间都高于总胜率 $overall';
  String mapDown(String map, String rate, int n, String overall) =>
      '$map 打得明显吃力：$n 场胜率 $rate，整个区间都低于总胜率 $overall';
  String heroUp(String hero, String rate, int n, String overall) =>
      '$hero 是该玩家的拿手英雄：$n 场胜率 $rate，整个区间都高于总胜率 $overall';
  String heroDown(String hero, String rate, int n, String overall) =>
      '用 $hero 时明显吃力：$n 场胜率 $rate，整个区间都低于总胜率 $overall';
  String get insightsNone => '目前没有足够明确的发现：数据再多一些，或差别再大一些，这里才会出现结论。';
  String get insightsTip =>
      '只有证据足够时才出现：地图、英雄要求胜率的整个可能范围都在总胜率的同一侧；近期对比要求前后各至少 10 场且相差 15 个百分点以上；连胜连败从 3 场起。';

  String get heroesTitle => '常用英雄';
  String get mapsTitle => '地图';
  String get rolesTitle => '职责';
  String overallRate(String rate) => '该玩家的总胜率 $rate';
  String get groupTip => '横条是胜率（不计平局），细线是可能的范围；点一行到对局页只看它。少于 5 场的变灰，只列出不比较。';

  String get heatTitle => '什么时候打得好';
  String get heatMetric => '胜率';

  String get emptyTitle => '还没有可概览的对局';
  String emptyBody(String mode) => '该玩家在$mode还没有读取到对局。先到对局页读取，概览会随之生成。';
  String get openMatches => '打开对局页';

  String streakStrength(int stronger, int n) =>
      '这 $n 场连败里有 $stronger 场，对方平均段位分比己方高 200 以上：输得不全在该玩家';
  String driversUp(String items) => '状态回升主要来自 $items';
  String driversDown(String items) => '状态下滑主要来自 $items';
  String driverItem(String label, String delta) => '$label（净胜 $delta）';
  String fatigue(String late, String early) =>
      '一次连续打到第 4 场以后，胜率 $late，明显低于前 3 场的 $early：可以考虑每次少打几场';
  String heroMetricDown(String hero, String metric, int p) =>
      '$hero 的$metric在同侪中排第 $p 百分位，明显偏低';
  String heroMetricUp(String hero, String metric, int p) =>
      '$hero 的$metric在同侪中排第 $p 百分位，明显偏高';
  String get mute => '不再提示这类';
  String muted(int n) => '已隐藏 $n 类提示';
  String get unmute => '全部恢复';
}
