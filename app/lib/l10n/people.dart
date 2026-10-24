/// The frequent players page. See strings.dart for the rules.
class PeopleStrings {
  const PeopleStrings();

  String coverage(int n, String mode) => '$mode，$n 场对局详情';
  String get coverageTip => '统计已存详情的对局（对局列表不含阵容），组排来自对局内的组队信息。';
  String get partyTitle => '组排与单排';
  String get partyTip => '组排：同队至少一人与本人组队；单排：同队全是路人。胜率不计平局，细线为置信区间。';
  String get partyRate => '组排胜率';
  String get soloRate => '单排胜率';
  String matchesNote(int n) => '$n 场';
  String rangeNote(int n, String low, String high) => '$n 场，$low–$high';
  String get matesTitle => '常遇玩家';
  String get matesTip => '已存对局中同场 ≥ 2 次的玩家，按共同场次排序，胜率为本人胜率。点击查看共同对局。';
  String get anonymous => '未知玩家';
  String shared(int n) => '共同 $n 场';
  String allyLine(int n, String rate) => '同队 $n 场，胜率 $rate';
  String enemyLine(int n, String rate) => '对面 $n 场，胜率 $rate';
  String partyLine(int n) => '组排 $n 场';
  String lastSeen(String when) => '最近 $when';
  String get none => '暂无同场 2 次以上的玩家。';
  String get emptyTitle => '暂无对局详情';
  String emptyBody(String mode) => '常遇玩家按对局详情统计，先在对局页打开几场$mode对局。';
  String get openMatchList => '去对局页';
  String get pick => '选择玩家查看共同对局';
  String get withThem => '同队时';
  String get without => '其他对局';
  String get againstThem => '对面时';
  String get sharedTitle => '共同对局';
  String get sharedTip => '左侧本人，右侧对方。点击查看对局。';
  String get sameSide => '同队';
  String get otherSide => '对面';
  String get grouped => '组排';
  String kda(String k, String d, String a) => '$k/$d/$a';
  String partyTag(int n) => '$n 人组排';
}
