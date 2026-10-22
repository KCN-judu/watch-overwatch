/// The maps page. See strings.dart for the rules.
class MapStrings {
  const MapStrings();

  String coverage(int n, String mode) => '$mode · 本机已读取的 $n 场对局';
  String get coverageTip =>
      '按地图类型分组，只用本机已读取的对局计算，不向上游请求。胜率不计平局。对局列表不区分进攻和防守，所以地图不按攻防拆开。';
  String get otherMode => '其他';
  String modeSummary(int n, String rate) => '$n 场 · 胜率 $rate';
  String get modeTip =>
      '横条是胜率，细线是可能的范围，竖线是这一类地图的总胜率。少于 5 场的地图变灰，排在后面，不参与比较。点一张图看详情。';
  String typeRate(String rate) => '这类地图的总胜率 $rate';
  String get winRate => '胜率';
  String range(String low, String high) => '可能在 $low – $high';
  String get record => '战绩';
  String get duration => '平均时长';
  String durationNote(int n) => '有详情的 $n 场';
  String get noDuration => '打开过详情的对局才有时长';
  String get kda => 'KDA';
  String get kills => '场均消灭';
  String get damage => '场均伤害';
  String get healing => '场均治疗';
  String get heroesTitle => '在这张图上玩什么';
  String get heroesTip => '这张图上最常用的英雄。竖线是这张图的总胜率；点一行到对局页只看这张图上的这个英雄。';
  String mapRate(String rate) => '这张图的胜率 $rate';
  String get openMatches => '查看这张图的对局';
  String get notRanked => '场次不足，不参与比较';
  String get emptyTitle => '还没有可统计的地图';
  String emptyBody(String mode) => '该玩家在$mode还没有读取到对局。先到对局页读取，地图统计会随之生成。';
  String get openMatchList => '打开对局页';
  String get pick => '选一张地图看详情';
}
