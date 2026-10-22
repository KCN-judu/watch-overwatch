/// Heroes list, hero detail and profile pages. See strings.dart for the rules.
class HeroStrings {
  const HeroStrings();

  // ---- shared by these pages ----

  String get matchesLabel => '场次';
  String get winRateLabel => '胜率';
  String get playTimeLabel => '使用时长';
  String get proficiency => '熟练度';
  String get avgKills => '场均消灭';
  String get avgDeaths => '场均阵亡';
  String get avgAssists => '场均助攻';
  String get avgDamage => '场均伤害';
  String get avgHealing => '场均治疗';
  String get avgMitigation => '场均阻挡';

  /// N 胜 M 负.
  String winLoss(int wins, int losses) => '$wins 胜 $losses 负';

  /// The provider's season record for a hero: wins out of all matches. It gives no
  /// losses, and its win rate counts draws in the matches, so losses cannot be worked out.
  String winsOfMatches(int wins, int matches) => '$wins 胜 / $matches 场';

  /// N 小时 (one decimal, already formatted).
  String hours(String h) => '$h 小时';

  // ---- heroes page ----

  String get sortTime => '时长';
  String get sortKills => '消灭';
  String get sortDamage => '伤害';
  String get sortHealing => '治疗';
  String get sortMitigation => '阻挡';

  String loadFailed(String mode) => '无法读取$mode的英雄统计';
  String get searchHint => '搜索英雄';

  /// N 个英雄.
  String heroCount(int n) => '$n 个英雄';

  /// N / M 个英雄, while a search narrows the list.
  String heroCountFiltered(int shown, int total) => '$shown / $total 个英雄';
  String get clearSearch => '清除搜索';

  /// 第 N 赛季累计.
  String seasonTotal(int? season) =>
      season == null ? '本赛季累计' : '第 $season 赛季累计';
  String get listInfo =>
      '整个赛季的累计，来自大神，不是“对局”页读取的最近对局。点一个英雄看详情。消灭、伤害、治疗、阻挡为每 10 分钟；— 表示这个英雄无法产出。';
  String get sortBy => '排序';
  String get sortBasis => '排序依据';

  /// Hint on a per-10-minute sort option: 消灭，每 10 分钟.
  String per10Hint(String label) => '$label，每 10 分钟';
  String sortAscending(String label) => '$label 从低到高';
  String sortDescending(String label) => '$label 从高到低';
  String listLabel(String mode) => '$mode英雄使用统计';

  /// Screen-reader line for one hero row.
  String heroRowLabel(
    String hero,
    String role,
    String matches,
    String winRate,
    String playTime,
  ) => '$hero，$role，$matches 场，胜率$winRate，使用$playTime';
  String noHeroesTitle(int? season, String mode) =>
      season == null ? '本赛季没有$mode的英雄记录' : '第 $season 赛季没有$mode的英雄记录';
  String get noHeroesBody => '该赛季没有打过这个模式，或资料为私密。可换个模式，或到“赛季走势”看往期。';
  String switchTo(String mode) => '切换到$mode';
  String noSearchMatchTitle(String query) => '没有名称包含“$query”的英雄';
  String noSearchMatchBody(int n) => '已有 $n 个英雄记录。';
  String minutes(int n) => '$n 分钟';

  /// Win rate tooltip when the sample is too small.
  String smallSample(int n) => '只有 $n 场，样本太少，仅供参考';

  /// Label of the per-10-minute figure the list is sorted by: 消灭 /10分.
  String per10Metric(String label) => '$label /10分';
  String get cannotProduce => '这个英雄无法产出这项数据';

  // ---- hero detail page ----

  String get heroList => '英雄列表';
  String get backShortcut => 'Esc 或 Alt+←';

  /// 第 N / M 位.
  String position(int n, int total) => '第 $n / $total 位';
  String get previousHero => '上一位英雄';
  String get nextHero => '下一位英雄';

  /// 场均 12:34.
  String avgMatchTime(String clock) => '场均 $clock';
  String get notProvided => '上游没有提供';
  String get recentMatchesNote => '近期对局';

  String get groupCombat => '战斗';
  String get groupDamage => '伤害与命中';
  String get groupHealing => '治疗与支援';
  String get groupDefense => '防护';
  String get groupHero => '英雄特色';

  String get sourceDerived => '上游没给这一项，由每场平均 × 600 ÷ 场均时长推算';
  String get sourceRecent => '上游没给这一项，取自已读取的近期对局';
  String get sourceZero => '这个英雄能产出这项数据，但上游没有记录，按 0 计';

  String get seasonStats => '赛季数据';
  String get seasonStatsInfo =>
      '整个赛季的累计，来自大神。上游常漏项，缺的按这个英雄能产出的内容补全：≈ 是推算或取自近期对局，灰色 0 是上游没有记录。消灭和治疗量是两部分相加，条里是第一部分占的比例：消灭 = 最后一击 + 共同消灭（造成过伤害、最后一击是队友打的），治疗量 = 自我治疗 + 对他人。';
  String get noStats => '没有这个英雄的统计项。';
  String get per10 => '每 10 分钟';
  String get perMatch => '每场平均';
  String unnamedStats(int n) => '另有 $n 项统计目录里没有名称，未显示。';

  /// Caption under a two-part figure: 最后一击 1,234（60%）· 共同消灭 800.
  String splitCaption(
    String part,
    String partValue,
    String pct,
    String rest,
    String restValue,
  ) => '$part $partValue（$pct）· $rest $restValue';

  String get recentMatches => '近期对局';
  String recentInfo(int total, String hero) =>
      '已读取的 $total 场里该玩家用$hero打的。平均值来自这些对局，不是赛季累计。';
  String recentEmpty(int total, String hero) =>
      '已读取的 $total 场里没有用$hero打的。到“对局”页读取更多。';
  String moreMatches(int n) => '还有 $n 场，在“对局”页筛选这个英雄查看。';

  String get abilities => '技能';
  String get abilitiesInfo => '来自本机安装的游戏资料（国服 2.25），名称和说明与游戏内一致。';
  String get perks => '威能';
  String get minorPerks => '一级威能（二选一）';
  String get majorPerks => '二级威能（二选一）';

  // ---- profile page ----

  String get profileLoadFailed => '无法读取玩家档案';
  String get profileLoading => '正在读取档案…';
  String get identity => '身份';
  String get battleTag => '战网昵称';
  String get playerId => '玩家编号';
  String get title => '称号';
  String get endorsement => '荣誉等级';

  /// N 级.
  String endorsementLevel(int n) => '$n 级';
  String get totalPlayTime => '游戏时长';
  String get totalMatches => '总场次';
  String get accountStatus => '账号状态';
  String get accountSuspended => '暂停';
  String accountSuspendedUntil(String at) => '暂停，到期 $at';
  String get accountNormal => '正常';

  /// 竞技比赛生涯 · 第 N 赛季.
  String careerHeading(String mode, int? season) =>
      season == null ? '$mode生涯' : '$mode生涯 · 第 $season 赛季';
  String careerTableLabel(String mode) => '$mode各职责生涯';
  String get colRole => '职责';
  String get colCurrentRank => '当前段位';
  String get colPeakRank => '最高段位';
  String get colMaxStreak => '最长连胜';

  /// Screen-reader line for one role row.
  String careerRowLabel(
    String role,
    String current,
    String peak,
    String matches,
    String winRate,
  ) => '$role，当前$current，最高$peak，$matches 场，胜率$winRate';
  String noCareer(String mode) => '$mode本赛季没有分职责的生涯数据。';
  String noRanksInMode(String mode) => '$mode不提供段位，段位列为 —。';

  String get behavior => '行为与荣誉';
  String get honorsReceived => '收到的荣誉';
  String get honorsSent => '送出的荣誉';
  String get reports => '被举报次数';
  String get weeklyComment => '本周评语';

  String get provinceRanks => '省榜排名';

  /// Province board label; an empty role is the overall board.
  String provinceRankLabel(String? role, String? province) {
    final r = role == null || role.isEmpty ? '综合' : role;
    return province == null ? r : '$r · $province';
  }

  /// 第 N 名.
  String rankPosition(String n) => '第 $n 名';

  /// 近期表现 · 竞技比赛.
  String recentHeading(String mode) => '近期表现 · $mode';
  String get recentFormInfo =>
      '只统计“对局”页已读取的对局。胜率 = 胜 ÷ （胜 + 负）；平均值只计入提供了该数据的对局，数量不足时标注 n。';
  String get noMatchesRead => '还没有读取到对局。';
  String get record => '战绩';

  /// N 平, with · M 未知 when some outcomes are unknown.
  String drawsNote(int draws, int unknown) =>
      unknown > 0 ? '$draws 平 · $unknown 未知' : '$draws 平';

  /// The range a win rate plausibly lies in, and the record behind it.
  String winRateRange(String low, String high, int wins, int matches) =>
      '可能在 $low–$high 之间（$wins 胜 / $matches 场）。按胜率排序时以区间下限为准。';
}
