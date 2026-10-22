/// The frequent players page. See strings.dart for the rules.
class PeopleStrings {
  const PeopleStrings();

  String coverage(int n, String mode) => '$mode · 本机已存的 $n 场对局详情';
  String get coverageTip =>
      '只统计打开过详情、存在本机的对局（对局列表本身没有阵容）。组排来自对局里的好友组队信息。这里只列出事实，不给任何玩家贴标签。';
  String get partyTitle => '组排与单排';
  String get partyTip => '组排：同队里至少有一人和该玩家组队。单排：同队都是匹配到的玩家。胜率不计平局，细线是可能的范围。';
  String get partyRate => '组排胜率';
  String get soloRate => '单排胜率';
  String matchesNote(int n) => '$n 场';
  String rangeNote(int n, String low, String high) => '$n 场 · $low–$high';
  String get matesTitle => '常遇玩家';
  String get matesTip => '在该玩家已存的对局里出现 2 次及以上的玩家，按共同场次排。胜率是该玩家的胜率。点一位查看共同对局。';
  String get anonymous => '未知玩家';
  String shared(int n) => '共同 $n 场';
  String allyLine(int n, String rate) => '同队 $n 场 · 胜率 $rate';
  String enemyLine(int n, String rate) => '对面 $n 场 · 胜率 $rate';
  String partyLine(int n) => '组排 $n 场';
  String lastSeen(String when) => '最近 $when';
  String get none => '还没有和该玩家同场 2 次以上的玩家。打开更多对局的详情后会出现。';
  String get emptyTitle => '还没有存下的对局详情';
  String emptyBody(String mode) => '常遇玩家来自对局详情。到对局页打开几场$mode对局的详情后，这里就会有统计。';
  String get openMatchList => '打开对局页';
  String get pick => '选一位玩家查看共同对局';
  String get withThem => '同队时';
  String get without => '其他对局';
  String get againstThem => '对面时';
  String get sharedTitle => '共同对局';
  String get sharedTip => '左边是该玩家，右边是对方。点一场打开详情。';
  String get sameSide => '同队';
  String get otherSide => '对面';
  String get grouped => '组排';
  String kda(String k, String d, String a) => '$k/$d/$a';
  String partyTag(int n) => '$n 人组排';
}
