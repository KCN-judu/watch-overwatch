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
      '本赛季累计（来自大神），非对局页的近期对局。消灭、伤害、治疗、阻挡为每 10 分钟；— 为该英雄不产出此项。点击查看详情。';
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
  String get noHeroesBody => '本赛季未玩过该模式或资料未公开，往期见赛季走势。';
  String switchTo(String mode) => '切换到$mode';
  String noSearchMatchTitle(String query) => '没有名称包含“$query”的英雄';
  String noSearchMatchBody(int n) => '共 $n 个英雄。';
  String minutes(int n) => '$n 分钟';

  /// Win rate tooltip when the sample is too small.
  String smallSample(int n) => '仅 $n 场，样本不足';

  /// Label of the per-10-minute figure the list is sorted by: 消灭 /10分.
  String per10Metric(String label) => '$label /10分';
  String get cannotProduce => '该英雄不产出此项';

  // ---- hero detail page ----

  String get heroList => '英雄列表';
  String get backShortcut => 'Esc 或 Alt+←';

  /// 第 N / M 位.
  String position(int n, int total) => '第 $n / $total 位';
  String get previousHero => '上一位英雄';
  String get nextHero => '下一位英雄';

  /// 场均 12:34.
  String avgMatchTime(String clock) => '场均 $clock';
  String get notProvided => '大神未提供';
  String get recentMatchesNote => '近期对局';

  String get groupCombat => '战斗';
  String get groupDamage => '伤害与命中';
  String get groupHealing => '治疗与支援';
  String get groupDefense => '防护';
  String get groupHero => '英雄特色';

  String get sourceDerived => '大神未提供，按场均 × 600 ÷ 场均时长推算';
  String get sourceRecent => '大神未提供，取自已读取的近期对局';
  String get sourceZero => '大神无记录，按 0 计';

  String get seasonStats => '赛季数据';
  String get seasonStatsInfo =>
      '本赛季累计（来自大神）。缺项按英雄补全：≈ 为推算或取自近期对局，灰色 0 为大神无记录。消灭 = 最后一击 + 共同消灭，治疗量 = 自我治疗 + 对他人，条内为前者占比。';
  String get noStats => '暂无该英雄数据。';
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
      '已读取 $total 场中使用$hero的对局，平均值仅来自这些对局。';
  String recentEmpty(int total, String hero) =>
      '已读取的 $total 场中没有使用$hero。';
  String moreMatches(int n) => '另有 $n 场，可在对局页筛选查看。';

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
  String noCareer(String mode) => '$mode本赛季无职责数据。';
  String noRanksInMode(String mode) => '$mode无段位。';

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
      '基于对局页已读取的对局。胜率 = 胜 ÷（胜 + 负）；平均值只计提供了该项的对局，不足时标注 n。';
  String get noMatchesRead => '暂无已读取的对局。';
  String get record => '战绩';

  /// N 平, with · M 未知 when some outcomes are unknown.
  String drawsNote(int draws, int unknown) =>
      unknown > 0 ? '$draws 平 · $unknown 未知' : '$draws 平';

  /// The range a win rate plausibly lies in, and the record behind it.
  String winRateRange(String low, String high, int wins, int matches) =>
      '区间 $low–$high（$wins 胜 / $matches 场），按胜率排序取区间下限。';

  // ---- ui/pages/peer_bench.dart ----

  String get peerTitle => '同分段对比';
  String get peerInfo =>
      '本人该英雄的中位数（每 10 分钟）在其他玩家同英雄对局中的百分位，第 50 即中游；阵亡已反向计算。优先同段位，样本不足时放宽到相邻段位，再不足则不限段位。';
  String get peerLoading => '正在计算同分段基准…';
  String get peerNone =>
      '样本不足：本人该英雄需 ≥ 3 场，其他玩家需 ≥ 30 场。';
  String get peerStadium => '角斗领域的数据与段位独立，暂不支持同分段对比。';
  String get metricDamage => '伤害';
  String get metricHealing => '治疗';
  String get metricMitigation => '阻挡';
  String get metricEliminations => '消灭';
  String get metricFinalBlows => '最后一击';
  String get metricDeaths => '阵亡';
  String perTen(String v) => '$v /10分';
  String percentile(int p) => '第 $p 百分位';
  String get bandPoor => '后 10%';
  String get bandSubpar => '偏低';
  String get bandAverage => '中游';
  String get bandGood => '偏高';
  String get bandGreat => '前 10%';
  String peerRow(
    String metric,
    String value,
    int p,
    String band,
    String median,
  ) => '$metric：$value，第 $p 百分位（$band），同分段中位数 $median';
  String peerMedian(String v) => '同分段中位数 $v';
  String get anyRank => '不限段位';
  String tierRange(String low, String high) => low == high ? low : '$low–$high';
  String peerSource(String band, String hero, int peers, int stored) =>
      '基准：$band的$hero，$peers 场（本机已存 $stored 场）。仅含查询过的玩家所在对局，不代表全服。';

  /// Under a per-match average: the provider's server-wide figure.
  String serverAverage(String v) => '全服平均 $v';

  // Hero boards (hero detail).
  String heroBoard(String province, int rank) => '英雄榜：$province第 $rank 名';
  String heroBoardTip(int n, String rate) => '依据 $n 场 · 胜率 $rate（大神英雄榜）';

  // Stadium builds (hero detail, Stadium mode).
  String get buildsTitle => '构筑';
  String get buildsTip =>
      '本机已存角斗领域对局中，各异能、物品的选取次数与胜率。横条：胜率；细线：置信区间；不足 5 场置灰。点击列出本人使用它的对局。';
  String get scopeOwn => '本人';
  String get scopeEveryone => '本机所有玩家';
  String buildsSource(int n, int own, int stored) => own == n
      ? '$n 场本人对局（本机已存 $stored 场角斗领域对局）'
      : '$n 场对局，本人 $own 场（本机已存 $stored 场角斗领域对局）。仅含查询过的玩家所在对局，不代表全服。';
  String get buildsNone => '暂无该英雄的角斗领域对局详情。';
  String get buildsPowers => '异能';
  String get buildsItems => '物品';
  String get buildsSets => '常用异能组合';
  String roundTag(int r) => '第 $r 回合';
  String pickRate(String rate) => '选取率 $rate';
  String get noOwnMatches => '本人没有使用它的已存对局。';
  String ownMatches(int n) => '本人使用它的 $n 场对局';
  String get hideMatches => '收起';
}
