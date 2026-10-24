/// The daily summary. See strings.dart for the rules.
class DailyStrings {
  const DailyStrings();

  String get daysTitle => '有对局的日子';
  String get daysTip => '按日分组（北京时间），点击查看当天战报。';
  String title(String date, String weekday) => '每日总结 $date $weekday';
  String get previousDay => '前一天';
  String get nextDay => '后一天';
  String caption(String name, String mode, String date, int n) =>
      '$name，$mode，$date，$n 场对局';
  String get fileName => '每日总结';
  String get emptyTitle => '暂无对局数据';
  String emptyBody(String mode) => '$mode还没有读取对局。';
  String get openMatchList => '去对局页读取';

  String get record => '战绩';
  String get winRate => '胜率';
  String get matches => '场次';
  String matchCount(int n) => '$n 场';
  String rateRange(String low, String high) => '区间 $low – $high';
  String sittings(int n) => '分 $n 段';
  String get playTime => '游戏时长';
  String playNote(int n, int all) => n == all ? '$n 场合计' : '有详情的 $n / $all 场';
  String get noPlayTime => '需要对局详情';
  String get kda => 'KDA';
  String timeSpan(String from, String to) => '$from – $to';
  String get rankTitle => '段位变化';
  String get rankSame => '无变化';
  String rankFrom(String from, String sign, int v) => '原 $from，$sign$v 分';

  String get highlightsTitle => '高光时刻';
  String get highlightsTip => '全场最高、单场最佳、本机纪录、连胜、零阵亡、最佳一局。点击查看对应对局。';
  String get noHighlights => '当天没有突出数据。';
  String lobbyTop(String stat) => '全场最高$stat';
  String get lobbyTopTitle => '全场最高';
  String lobbyTopNote(int n) => '$n 场全场第一';
  String dayBest(String stat) => '单场最高$stat';
  String newRecord(String stat) => '刷新纪录：$stat';
  String recordNote(String prev) => '之前本机最高 $prev';
  String streak(int n) => '$n 连胜';
  String get streakNote => '当天最长连胜';
  String deathless(int n) => '$n 场零阵亡';
  String get deathlessNote => '全场 0 阵亡';
  String get bestMatch => '最佳一局';
  String get bestMatchNote => '胜局中 KDA 最高';
  String get bestFleta => '最高 Fleta';
  String get bestFletaNote => '最后一击 / 本队一半';
  String where(String hero, String map) => '$hero，$map';

  String get statKills => '消灭';
  String get statDamage => '伤害';
  String get statHealing => '治疗';
  String get statMitigation => '阻挡';
  String get statDeaths => '阵亡';
  String get statKda => 'KDA';

  String versusTitle(String role) => '对比近 30 天（$role）';
  String get versusTip => '当天该职责场均 vs 前 30 天同职责场均。阵亡越少越好。';
  String get versusStat => '数据';
  String get versusToday => '当天';
  String get versusUsual => '近 30 天';
  String get versusDiff => '差';
  String versusNote(int n, int m) => '当天 $n 场，近 30 天 $m 场';

  String get heroesTitle => '使用英雄';
  String get mapsTitle => '地图';
  String get matchesTitle => '当天对局';
  String groupRow(int w, int l) => '$w 胜 $l 负';

  List<String> get weekdays => const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
}
