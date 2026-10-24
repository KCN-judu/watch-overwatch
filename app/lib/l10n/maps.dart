/// The maps page. See strings.dart for the rules.
class MapStrings {
  const MapStrings();

  String coverage(int n, String mode) => '$mode · 已读取 $n 场';
  String get coverageTip => '按地图类型分组，基于本机已读取的对局。胜率不计平局；对局列表不区分攻防。';
  String get otherMode => '其他';
  String modeSummary(int n, String rate) => '$n 场 · 胜率 $rate';
  String get modeTip => '横条：胜率；细线：置信区间；竖线：该类地图总胜率。不足 5 场置灰，不参与比较。点击查看地图详情。';
  String typeRate(String rate) => '该类总胜率 $rate';
  String get winRate => '胜率';
  String range(String low, String high) => '区间 $low – $high';
  String get record => '战绩';
  String get duration => '平均时长';
  String durationNote(int n) => '有详情的 $n 场';
  String get noDuration => '需要对局详情';
  String get kda => 'KDA';
  String get kills => '场均消灭';
  String get damage => '场均伤害';
  String get healing => '场均治疗';
  String get heroesTitle => '本图英雄';
  String get heroesTip => '本图最常用英雄。竖线：本图总胜率。点击筛选本图该英雄的对局。';
  String mapRate(String rate) => '本图胜率 $rate';
  String get openMatches => '查看本图对局';
  String get notRanked => '场次不足，不参与比较';
  String get emptyTitle => '暂无地图数据';
  String emptyBody(String mode) => '$mode还没有读取对局。';
  String get openMatchList => '去对局页读取';
  String get pick => '选择地图查看详情';
}
