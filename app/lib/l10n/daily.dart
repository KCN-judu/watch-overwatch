/// The daily summary. See strings.dart for the rules.
class DailyStrings {
  const DailyStrings();

  String get daysTitle => '有对局的日子';
  String get daysTip => '按天列出本机已读取的对局（北京时间的自然日）。点一天看它的总结。';
  String title(String date, String weekday) => '每日总结 · $date $weekday';
  String get previousDay => '前一天';
  String get nextDay => '后一天';
  String caption(String name, String mode, String date, int n) =>
      '$name · $mode · $date · $n 场对局';
  String get fileName => '每日总结';
  String get emptyTitle => '还没有可总结的日子';
  String emptyBody(String mode) => '该玩家在$mode还没有读取到对局。先到对局页读取，每日总结会随之生成。';
  String get openMatchList => '打开对局页';

  String get record => '战绩';
  String get winRate => '胜率';
  String get matches => '场次';
  String sittings(int n) => '$n 次连着打';
  String get playTime => '游戏时长';
  String playNote(int n, int all) => n == all ? '$n 场合计' : '有详情的 $n / $all 场';
  String get noPlayTime => '打开过详情的对局才有时长';
  String get kda => 'KDA';
  String timeSpan(String from, String to) => '$from – $to';
  String get rankTitle => '段位变化';
  String get rankSame => '这一天没有变化';
  String rankFrom(String from, String sign, int v) => '原 $from，$sign$v 分';

  String get highlightsTitle => '高光';
  String get highlightsTip =>
      '这一天最亮眼的地方：全场最高、单场最佳、刷新本机纪录的单场、连胜、无阵亡、最好的一局。点一条打开对应对局。';
  String get noHighlights => '这一天没有特别突出的数据。';
  String lobbyTop(String stat) => '全场最高$stat';
  String lobbyTopNote(int n) =>
      n == 1 ? '有 1 场是全场 10 人里最高' : '有 $n 场是全场 10 人里最高';
  String dayBest(String stat) => '单场最高$stat';
  String newRecord(String stat) => '刷新纪录：$stat';
  String recordNote(String prev) => '之前本机最高 $prev';
  String streak(int n) => '$n 连胜';
  String get streakNote => '这一天最长的连胜';
  String deathless(int n) => '$n 场无阵亡';
  String get deathlessNote => '整场一次都没有阵亡';
  String get bestMatch => '最好的一局';
  String get bestMatchNote => '赢下的对局里 KDA 最高';
  String get bestFleta => '最高 Fleta';
  String get bestFletaNote => '最后一击占本队一半的比例';
  String where(String hero, String map) => '$hero · $map';

  String get statKills => '消灭';
  String get statDamage => '伤害';
  String get statHealing => '治疗';
  String get statMitigation => '阻挡';
  String get statDeaths => '阵亡';
  String get statKda => 'KDA';

  String versusTitle(String role) => '和平时比（$role）';
  String get versusTip => '这一天打这个职责的场均，和之前 30 天同职责的场均比。阵亡越少越好。';
  String get versusStat => '数据';
  String get versusToday => '这一天';
  String get versusUsual => '平时';
  String get versusDiff => '差';
  String versusNote(int n, int m) => '这一天 $n 场，平时 $m 场';

  String get heroesTitle => '用过的英雄';
  String get mapsTitle => '打过的地图';
  String get matchesTitle => '这一天的对局';
  String groupRow(int w, int l) => '$w 胜 $l 负';

  List<String> get weekdays => const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
}
