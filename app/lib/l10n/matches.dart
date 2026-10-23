/// Match list, match detail, team tables and the player card. See strings.dart for the rules.
class MatchStrings {
  const MatchStrings();

  // ---- matches_page: list and empty states ----

  /// Error panel headline when a mode's matches could not be read.
  String cannotReadMatches(String mode) => '无法读取$mode的对局';

  /// Semantics label of the match list.
  String listLabel(String mode) => '$mode对局列表';

  String noRecord(String name, String mode) => '$name 在$mode没有对局记录';
  String get noRecordBody => '该模式没有打过，或资料为私密。可换个模式。';
  String switchToMode(String mode) => '切换到$mode';

  String get noMatchingMatches => '没有符合筛选的对局';

  /// [conditions] is the filter descriptions joined with [conditions].
  String noMatchingBody(int read, String conditions) =>
      '已读取的 $read 场对局中，没有满足：$conditions。';

  /// Joins filter descriptions inside [noMatchingBody]: 结果：胜，职责：输出.
  String conditions(Iterable<String> parts) => parts.join('，');

  /// Semantics label of one match row.
  String rowLabel(
    String outcome,
    String score,
    String map,
    String hero,
    String time,
  ) => '$outcome，比分$score，$map，$hero，$time';

  // ---- matches_page: filters ----

  /// [outcomes] is one outcome or several joined with `tr.common.list`.
  String filterOutcome(String outcomes) => '结果：$outcomes';
  String filterRole(String role) => '职责：$role';
  String get filterHero => '英雄';
  String get filterMap => '地图';

  /// The search text as a condition in [noMatchingBody].
  String filterSearchQuoted(String query) => '搜索“$query”';

  /// The search text as a filter tag.
  String filterSearch(String query) => '搜索：$query';

  String get searchLabel => '搜索对局，匹配英雄、地图、职责与结果';
  String get searchHint => '搜索英雄、地图  Ctrl+F';
  String get clearSearch => '清除搜索';

  /// Semantics label of a filter chip: 胜，12 场.
  String chipLabel(String name, int count) => '$name，$count 场';

  /// First item of a facet menu: 全部英雄.
  String facetAll(String facet) => '全部$facet';
  String get facetOptionEmpty => '在其他筛选条件下没有对局';

  // ---- matches_page: scope line ----

  /// Count when filters hide some matches: 12 / 40 场.
  String shownOfTotal(int shown, int total) => '$shown / $total 场';

  /// One outcome's count: 胜 12 场.
  String recordCount(String outcome, int n) => '$outcome $n 场';
  String winRateTip(int decided) => '胜 ÷ （胜 + 负），共 $decided 场；平局、未知不计。';
  String winRate(String value) => '胜率 $value';
  String allSavedTip(int total) => '本地已保存全部对局（$total 场）。每次打开只读取比已保存的最新一场更新的对局。';
  String get allRead => '已读完';
  String allReadWithNew(int n) => '已读完，新增 $n 场';
  String readingOlder(int n) => n == 0 ? '正在读取对局列表…' : '正在读取更早的对局…已读 $n 场';
  String get olderUnreadTip => '还有更早的对局没有读取';
  String get notAllRead => '未读完';
  String get continueReading => '继续读取';
  String get continueReadingTip => '读取全部更早的对局';
  String get preparingTip => '正在后台给对局里的玩家取段位快照，存进对局信息；打开别的页面时会先让路，之后自动继续。';
  String preparing(int remaining) => '正在后台读取段位，还剩 $remaining 场…';
  String preparingRetry(int seconds, int remaining) =>
      '部分段位没查到，$seconds 秒后重试（还剩 $remaining 场）';
  String preparingPaused(int remaining) =>
      '段位读取已暂停，等其他查询完成后继续（还剩 $remaining 场）';
  String get sortOldestFirst => '时间顺序：最早在前，点击改为最新在前';
  String get sortNewestFirst => '时间顺序：最新在前，点击改为最早在前';
  String get listInfo => '筛选与排序只作用于已读取的对局。点击一行（或按 Enter）打开这一局的详细数据。';

  // ---- match_detail_page ----

  String get matchList => '对局列表';
  String get backShortcut => 'Esc 或 Alt+←';
  String get backToMatchTip => '回到整场对局（Esc 或 Alt+←）';
  String playerPosition(int i, int n) => '第 $i / $n 位';
  String matchPosition(int i, int n) => '第 $i / $n 场';
  String get previousPlayer => '上一位';
  String get nextPlayer => '下一位';
  String get previousMatch => '上一场';
  String get nextMatch => '下一场';
  String get cannotReadDetail => '无法读取这场对局的详情';
  String get backToList => '返回列表';
  String get readingDetail => '正在读取对局详情';
  String duration(String clock) => '用时 $clock';
  String get outcomeFromScoreTip => '角斗领域详情没有提供胜负字段，结果按最终比分判断。';
  String get outcomeFromScore => '结果按比分判断';
  String get openPlayerHint =>
      '点一名玩家（或用方向键选中后按 Enter）打开他的详情页：威能、Fleta 指数、组队和点赞。';
  String get bans => '禁用';
  String get subjectHeroes => '该玩家在本场使用的英雄';
  String heroPlayTime(String clock) => '使用 $clock';
  String heroPlayTimeShare(String clock, String pct) => '使用 $clock（占本场 $pct）';
  String statsAllUnnamed(int n) => '本场 $n 项统计，目录里还没有它们的名称。';
  String statsSomeUnnamed(int n) => '另有 $n 项统计目录里没有名称，未显示。';
  String get rounds => '回合';
  String get timelineTip => '每回合左侧是该回合的胜负，右侧是该玩家这一回合新选的异能和物品。';
  String round(int i, String score, String clock) => '第 $i 回合  $score  $clock';

  // ---- team_table ----

  String partialTotalTip(int have, int total) =>
      '只有 $have / $total 人有这项数据，合计不含其余的人';
  String get player => '玩家';
  String teamTotal(String team) => '$team合计';

  /// Badge next to the player being looked at.
  String get subject => '该玩家';
  String get suspendedTip => '该玩家账号处于暂停状态';
  String get kdaTip => 'Kills / Assists / Deaths：消灭 / 助攻 / 阵亡';
  String get damageTip => '对英雄伤害。条形长度按全场 10 人的最大值';
  String get healingTip => '治疗量。条形长度按全场 10 人的最大值';
  String get mitigationTip => '阻挡或减免的伤害量，不是次数。条形长度按全场 10 人的最大值';
  String get rank => '段位';
  String get rankTip => '竞技、角斗显示该场的段位；快速比赛显示读取这场时取的竞技段位快照，之后不再变。查不到的显示 —';
  String get rankLookupTip => '正在查询这名玩家的竞技段位';
  String get rankLookup => '查询中';
  String get unranked => '未定级';
  String get unrankedTip => '这名玩家没有竞技段位，或查不到';
  String roleRank(String role, String rank) => '$role $rank';
  String roleRanks(List<String> roles) => '读取这场时的竞技段位：${roles.join(' · ')}';
  String get portrait => '英雄立绘';
  String playerCount(int n) => '$n 人';
  String teamTableLabel(String team) => '$team队伍';
  String totalRowLabel(
    String team,
    String damage,
    String healing,
    String mitigation,
  ) => '$team合计，伤害$damage，治疗$healing，阻挡$mitigation';
  String playerRowLabel(
    String name,
    String hero,
    String role,
    String kills,
    String assists,
    String deaths,
    String damage,
    String healing,
    String mitigation,
  ) =>
      '$name，$hero，$role，消灭$kills助攻$assists阵亡$deaths，'
      '伤害$damage，治疗$healing，阻挡$mitigation';

  /// [playerRowLabel] for the player being looked at.
  String subjectRowLabel(
    String name,
    String hero,
    String role,
    String kills,
    String assists,
    String deaths,
    String damage,
    String healing,
    String mitigation,
  ) =>
      '$name，该玩家，$hero，$role，消灭$kills助攻$assists阵亡$deaths，'
      '伤害$damage，治疗$healing，阻挡$mitigation';
  String get noParticipants => '没有参与者数据';
  String get noParticipantsBody => '上游没有返回这一方的名单。';

  // ---- stat names (team_table, player_detail_page) ----

  String get kills => '消灭';
  String get assists => '助攻';
  String get deaths => '阵亡';
  String get damage => '伤害';
  String get healing => '治疗';
  String get mitigation => '阻挡';
  String get finalBlows => '最后一击';
  String get soloKills => '单独消灭';
  String get damageTaken => '承受伤害';
  String get healingTaken => '承受治疗';
  String get objectiveTime => '目标争夺';
  String get kdaFormula => '（消灭 + 助攻）÷ 阵亡';

  // ---- player_detail_page ----

  String shareOfTeam(String pct) => '占本队 $pct';
  String get rankLookupLong => '段位查询中';
  String get restrictedTip => '这个账号正处于处罚或风险状态。';
  String get restricted => '账号受限';
  String peopleNotInMatch(int n) => '另有 $n 名不在这场对局里';

  /// Joins the named players and [peopleNotInMatch].
  String peopleParts(Iterable<String> parts) => parts.join('；');
  String get matchStats => '本场数据';
  String get matchStatsInfo => '占本队的比例按本队 5 人的合计算；— 表示上游没有提供，不等于 0。';
  String get fleta => 'Fleta 指数';
  String get fletaInfo =>
      '最后一击 ÷（本队最后一击合计 × 0.5）× 100%。100% 表示拿下了本队一半的最后一击；'
      '越高，说明这支队伍的击杀越多是由他收尾的。只看这一场、只和本队比，不分职责，'
      '辅助和重装通常偏低，输出偏高。';
  String get fletaNoData => '没有最后一击数据，或本队没有最后一击';
  String fletaFormula(String finalBlows, String teamFinalBlows) =>
      '最后一击 $finalBlows ÷（本队 $teamFinalBlows × 0.5）';
  String get perks => '威能';
  String get partyAndEndorsements => '组队与点赞';
  String get party => '组队';
  String get noParty => '没有组队信息';
  String partyWith(int n, String names) => '与 $n 名玩家组队：$names';
  String get endorsements => '获得点赞';
  String get noEndorsements => '没有收到点赞';
  String endorsedBy(int n, String names) => '$n 人：$names';
  String get stadiumBuild => '角斗构筑';
  String get stadiumCash => '局内货币';
  String get power => '异能';
  String get item => '装备';

  /// The tag on a Stadium power or item card: its kind (异能, or the item's 武器 / 技能 /
  /// 生存 category) and rarity when known: 武器 · 史诗.
  String upgradeTag(String kind, String? rarity) =>
      rarity == null ? kind : '$kind · $rarity';
}
