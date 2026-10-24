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
  String get notEnoughBefore => '前 20 场不足，无对比';
  String get rollingLabel => '每 10 场的胜率';
  String coverage(int n, String mode) => '$mode，已读取 $n 场';
  String get coverageTip => '基于本机已读取的对局，对局页读到新对局后自动更新。胜率不计平局。';

  String get formTitle => '最近 20 场';
  String formTip(String result, String map, String hero, String time) =>
      '$result，$map，$hero，$time';
  String get formHint => '点头像查看本局';

  String get insightsTitle => '近期动态';
  String streakWin(int n) => '$n 连胜中';
  String streakLoss(int n) => '$n 连败中';
  String recentUp(String now, String then) => '状态回升：近 20 场胜率 $now，前 20 场 $then';
  String recentDown(String now, String then) =>
      '状态下滑：近 20 场胜率 $now，前 20 场 $then';
  String mapUp(String map, String rate, int n, String overall) =>
      '强势图 $map：$n 场，胜率 $rate（总胜率 $overall）';
  String mapDown(String map, String rate, int n, String overall) =>
      '苦手图 $map：$n 场，胜率 $rate（总胜率 $overall）';
  String heroUp(String hero, String rate, int n, String overall) =>
      '绝活 $hero：$n 场，胜率 $rate（总胜率 $overall）';
  String heroDown(String hero, String rate, int n, String overall) =>
      '短板英雄 $hero：$n 场，胜率 $rate（总胜率 $overall）';
  String get insightsNone => '暂无显著动态。';
  String get insightsTip =>
      '判定标准：地图、英雄的胜率区间整体高于或低于总胜率；近期对比前后各 ≥ 10 场且相差 ≥ 15 个百分点；连胜、连败从 3 场起。';

  String get heroesTitle => '常用英雄';
  String get mapsTitle => '地图';
  String get rolesTitle => '职责';
  String overallRate(String rate) => '总胜率 $rate';
  String get groupTip => '横条：胜率（不计平局）；细线：置信区间；不足 5 场置灰，不参与比较。点击筛选对局。';

  String get heatTitle => '时段胜率';
  String get heatMetric => '胜率';

  String get emptyTitle => '暂无对局数据';
  String emptyBody(String mode) => '$mode还没有读取对局。';
  String get openMatches => '去对局页读取';

  String streakStrength(int stronger, int n) =>
      '连败 $n 场中，$stronger 场对方均分高出 200 以上';
  String driversUp(String items) => '回升来源：$items';
  String driversDown(String items) => '下滑来源：$items';
  String driverItem(String label, String delta) => '$label（净胜 $delta）';
  String fatigue(String late, String early) => '连续第 4 场起胜率 $late，前 3 场 $early';
  String heroMetricDown(String hero, String metric, int p) =>
      '$hero $metric：同分段第 $p 百分位，偏低';
  String heroMetricUp(String hero, String metric, int p) =>
      '$hero $metric：同分段第 $p 百分位，偏高';
  String get mute => '屏蔽此类';
  String muted(int n) => '已屏蔽 $n 类';
  String get unmute => '取消屏蔽';
}
