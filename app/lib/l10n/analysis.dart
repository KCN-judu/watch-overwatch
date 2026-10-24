/// Lobby strength, growth and season trend pages. See strings.dart for the rules.
class AnalysisStrings {
  const AnalysisStrings();

  // ---- shared by the charts ----

  String get hollowMeaning => '实心点：胜或平；空心点：负。';

  // ---- strength page: header and controls ----

  String get overallSlot => '综合';
  String get strengthTitle => '对局强度';

  /// The page's InfoTip; quick play borrows competitive ranks.
  String strengthInfo({required bool quick}) =>
      '己方与对方的平均段位。重装、输出、支援只算该职责的玩家，综合算全部。'
      '${quick ? '快速比赛无段位，用读取本局时记录的本赛季竞技段位，职责按本局所打。' : '使用本局段位。'}';

  String get strengthFailed => '无法完成对局强度分析';
  String get scope => '范围';
  String get scopeSemantic => '分析哪个职责';
  String get busyDisabled => '分析中，完成或取消后可更改';
  String get all => '全部';
  String get scopeAllHint => '三个职责各取最近 N 场';

  /// Hint on a role segment of the scope control.
  String scopeRoleHint(String role) => '只看本人打$role的对局';

  /// Before the match-count control: one role, or each of them.
  String recentPrefix({required bool eachRole}) => eachRole ? '各取最近' : '取最近';
  String get countSemantic => '取的场数';
  String get startAnalysis => '开始分析';
  String get reanalyse => '重新分析';
  String get reanalyseTip => '读取新对局，已读的走缓存';
  String get requeryRanks => '重新查询段位';
  String get requeryRanksTip => '重新查询玩家当前段位，对局详情仍走缓存';
  String get valueDisplay => '数值显示';
  String get tierSegment => '段位';
  String get tierSegmentHint => '如 白金 2';
  String get ratingSegment => '段位分';
  String get ratingSegmentHint => '500–5000';

  // ---- strength page: result summary ----

  String get noRatedMatches => '没有可计算强度的对局';

  /// Nothing was read for this mode.
  String noMatchesRead(String mode) => '$mode还没有读取对局。';

  String noRatedPlayers(int read, int requested) =>
      '已读 $read / $requested 场详情，没有可定段位的玩家。快速比赛需玩家有竞技段位，竞技需对局自带段位。';

  String unratedMatchesTip(int n) => '这 $n 场无已定级玩家，图表与明细留空，不计入场数和平均。';
  String unratedMatches(int n) => '另有 $n 场没有已定级玩家';

  /// Per-role coverage: the target count was reached.
  String roleCoverageFull(String role, int n) => '$role：取了最近 $n 场';

  /// Per-role coverage: fewer usable matches than the target.
  String roleCoverageShort(String role, int have, int n) =>
      '$role：仅 $have 场可用（目标 $n 场）';
  String roleCount(String role, int n) => '$role $n 场';

  String cacheHitsTip(int n) => '本次有 $n 项命中本机缓存';
  String cacheHits(int n) => '缓存 $n';
  String get ratedOfAllTip => '已定级的参与者 / 全部参与者';

  String unratedNote({required bool hasUnratedMatches}) =>
      '未定级或资料不可见的玩家不计入平均（不按 0 算）。'
      '${hasUnratedMatches ? '双方都无已定级玩家的对局留空。' : ''}';

  // ---- strength page: by-role table ----

  String get byRoleTitle => '按本人职责';
  String get byRoleInfo => '同职责 = 本人所打职责。差 = 己方 − 对方，正数为己方更强。';
  String get byRoleTable => '按本人职责汇总的对局强度';

  /// Tooltip on an average: points, then the tier.
  String ratingTip(String points, String tier) => '$points 分 · $tier';
  String sideMeanTip(String side) => '$side · 同职责平均';
  String get playedRole => '本人职责';
  String get matchesColumn => '场次';
  String get winRate => '胜率';
  String get winRateTip => '胜 ÷ （胜 + 负）';
  String get diff => '差';
  String get diffTip => '己方同职责平均 − 对方同职责平均，单位：段位分';
  String get lobby => '全场';
  String get lobbyTip => '双方合计的同职责平均';
  String get overallDiff => '综合差';
  String get overallDiffTip => '所有已定级玩家的平均差（己方 − 对方）';

  String byRoleRow({
    required String role,
    required int matches,
    required String winRate,
    required String ally,
    required String enemy,
    required String diff,
  }) => '$role，$matches 场，胜率$winRate，己方同职责$ally，对方同职责$enemy，差$diff';

  // ---- strength page: per-match table ----

  String get perMatchTitle => '逐场明细';
  String get perMatchInfo => '点击查看对局。加粗列为本人所打职责。';
  String get perMatchTable => '逐场对局强度';
  String get matchColumn => '对局';
  String get outcomeColumn => '结果';
  String get roleColumn => '职责';
  String slotAlly(String slot) => '$slot 己方';
  String slotEnemy(String slot) => '$slot 对方';

  /// Column header beside the role glyph: 己 / 对.
  String get allyShort => '己';
  String get enemyShort => '对';
  String slotAllyMeanTip(String slot, {required bool overall}) =>
      '$slot · 己方平均${overall ? '（所有已定级玩家）' : ''}';
  String slotEnemyMeanTip(String slot, {required bool overall}) =>
      '$slot · 对方平均${overall ? '（所有已定级玩家）' : ''}';
  String get ratedColumn => '已定级';
  String get ratedColumnTip => '已定级人数 / 总人数（己方 + 对方）';

  String perMatchRow({
    required String when,
    required String map,
    required String outcome,
    required String role,
    required String allyAll,
    required String enemyAll,
    required String allyTank,
    required String enemyTank,
    required String allyDamage,
    required String enemyDamage,
    required String allySupport,
    required String enemySupport,
  }) =>
      '$when，$map，$outcome，本人打$role，综合 己方$allyAll 对方$enemyAll，'
      '重装 己方$allyTank 对方$enemyTank，输出 己方$allyDamage 对方$enemyDamage，支援 己方$allySupport 对方$enemySupport';

  // ---- strength page: before and during the analysis ----

  String notAnalysed(String mode) => '还没有分析$mode';

  /// [role] is null when every role is analysed.
  String introBody({
    String? role,
    required int n,
    required int requests,
    required bool quick,
  }) =>
      '从已读取的对局中${role ?? '每个职责'}取最近 $n 场（不足会自动多读）。'
      '首次最多约 $requests 次请求${quick ? '，约 1–2 分钟' : ''}，之后大多走缓存，可随时取消。';

  String selectedMatches(int n) => '已选 $n 场';
  String get queryNotNeeded => '无需查询（对局自带段位）';
  String remaining(String clock) => '约剩 $clock';
  String readingNow(String what) => '正在读取：$what';
  String queryingNow(String who) => '正在查询：$who';
  String runningSemantic(int n) => '正在分析，每个职责最近 $n 场';
  String runningStepSemantic(int step, int done, int total) =>
      '正在分析，第 $step 步，已完成 $done / $total';
  String get analysing => '正在分析';
  String eachRoleRecent(int n) => '每个职责最近 $n 场';
  String elapsed(String clock) => '已用 $clock';
  String get stepSelect => '选取对局';
  String stepSelectHint(int n) => '每个职责取最近 $n 场';
  String get stepDetails => '读取对局详情';
  String get stepDetailsHint => '每场读一次，获取双方阵容；已读走缓存';
  String get stepRanks => '查询参与者段位';
  String stepRanksHint({required bool quick}) =>
      quick ? '快速比赛无段位，逐个查询玩家竞技段位' : '对局自带段位，无需查询';
  String get stepCombine => '汇总计算';
  String get stepCombineHint => '按职责汇总每场强度';
  String requestsSent(int requests, int cached) =>
      '已发出 $requests 次请求${cached > 0 ? '，$cached 项取自缓存' : ''}';
  String failures(int n) => '$n 次失败，不计入平均';

  // ---- strength page: chart ----

  String get chartAllRoles => '全部职责';
  String chartRole(String role) => '本人打$role';
  String chartNoData(String name) => '$name：无已定级玩家。';

  /// A null mean has no data.
  String chartSummary(
    String name,
    int n,
    String? allyMean,
    String? enemyMean,
  ) => '$name，$n 场：己方平均 ${allyMean ?? '无数据'}，对方平均 ${enemyMean ?? '无数据'}。';
  String get chartTitle => '逐场走势';
  String get chartRoleSemantic => '本人职责';
  String get chartInfo =>
      '按本人所打职责筛选。竖条：该队已定级玩家最低至最高段位，圆点为平均，悬停看段位分；斜线阴影：无已定级玩家的对局。';
  String points(String v) => '$v 分';
  String ratedCount(int n) => '已定级 $n 人';
  String rangeMeaning({required bool tiers}) =>
      '竖条：该队已定级玩家最低至最高${tiers ? '段位' : '段位分'}，圆点为平均。斜线阴影：无已定级玩家。';

  /// The readout line about one match.
  String chartPointNote(String outcome, String role) => '$outcome · 本人打$role';
  String get chartAsTable => '以表格查看图中的数值';
  String chartTableRow(String when, String ally, String enemy, String diff) =>
      '$when  己方 $ally  对方 $enemy  差 $diff';
  String otherRoleNote(int n) => '其中 $n 人无该职责段位，按其他职责最高段位计';

  // ---- growth page ----

  String get lifeTitle => '平均存活时长';
  String get lifeInfo =>
      '对局时长 ÷ 阵亡次数（大神不提供每次阵亡的时间点），含复活等待。'
      '零阵亡的对局取整局时长（实际更长），用盾牌标出。';
  String lifeNoteDeathless(String duration) => '对局时长 $duration · 零阵亡';
  String lifeNote(String duration, String deaths) =>
      '对局时长 $duration · 阵亡 $deaths 次';
  String get lifeCard => '存活时长';
  String seconds(String signed) => '$signed 秒';
  String get lifeShield => '盾牌：零阵亡，取整局时长。';
  String get fletaTitle => 'Fleta 指数';
  String get fletaInfo =>
      '最后一击 ÷（本队最后一击 × 0.5）× 100%。'
      '只与本队比、不分职责：输出通常偏高，重装、支援偏低，建议分职责看。';
  String get fletaCard => 'Fleta 指数';
  String percentagePoints(String signed) => '$signed 个百分点';
  String get kdaInfo => '（消灭 + 助攻）÷ 阵亡。零阵亡按 1 次计，用盾牌标出。';
  String get deathless => '零阵亡';
  String deaths(String n) => '阵亡 $n 次';
  String get kdaShield => '盾牌：零阵亡，按 1 次计。';
  String get healingTitle => '治疗量';
  String get healingInfo => '每 10 分钟治疗量（含自我治疗），只算支援对局。';
  String per10Min(String v) => '$v / 10 分钟';
  String get mitigationTitle => '阻挡量';
  String get mitigationInfo => '每 10 分钟阻挡 / 减免的伤害，只算重装对局。';

  String get growthFailed => '无法读取成长数据';
  String get growthLoading => '正在读取成长数据…';
  String noGrowthMatches(String mode) => '暂无可分析的$mode对局';
  String get readMatchListFirst => '请先在对局页读取对局。';
  String detailsNotStored(int listed) =>
      '已读 $listed 场，详情尚未存到本机（需要对局时长和阵亡数）。'
      '打开几场对局，或等待后台同步完成。';
  String growthTitle(String mode) => '$mode · 成长';
  String get roleSemantic => '职责';
  String get growthInfo =>
      '每项一张图：一个点一局，粗线为最近 10 场平均，空心点为败局。'
      '上方是走势：前后两半对比并做趋势检验。各职责数值差异大，以分职责结果为准。';

  /// Coverage line under the header; the clauses that apply, joined.
  String growthCoverage({
    required int analysed,
    required int listed,
    required int notStored,
    required int skipped,
  }) => [
    '已分析 $analysed 场（对局列表共 $listed 场）',
    if (notStored > 0) '$notStored 场详情待同步',
    if (skipped > 0) '$skipped 场过短或缺阵亡数，未计入',
  ].join('；');
  String get pValueNote => 'p 值：Mann-Kendall 趋势检验（双侧），p < 0.1 判定有趋势；不足 8 场不检验。';
  String trendTooFew(String card) => '$card：场次不足';
  String trendUp(String card) => '$card 上升';
  String trendDown(String card) => '$card 下降';
  String trendFlat(String card) => '$card 无明显趋势';
  String get trendNeedsEight => '不足 8 场，无法判断';
  String get baselineMeaning => '灰色底带：前 20 场的四分位区间（P25–P75），带外为异常局；不足 8 场不显示。';
  String get confidenceFirm => '显著';
  String get confidenceHint => '弱趋势';
  String get confidenceNone => '无变化';
  String get confidenceTooFew => '样本不足';

  /// The trend card's second line: how big the change is, and how sure.
  String trendEffect(String changePct, String confidence) =>
      '后半段 vs 前半段 $changePct% · $confidence';

  /// Under the trend cards: what the wording means (the p value is in each card's tip).
  String get confidenceMeaning =>
      '显著：p < 0.05；弱趋势：p < 0.1（Mann-Kendall 检验）。不足 8 场不检验，悬停查看 p 值与前后均值。';
  String pValue(String p) => 'p $p';
  String trendTip({
    required String older,
    required String newer,
    required String change,
    required String changePct,
    required int matches,
    required String p,
  }) =>
      '前半段 $older → 后半段 $newer（$change，$changePct%）· $matches 场 · Mann-Kendall $p';
  String movingAverage(int n) => '$n 场平均';
  String chartEmpty(String title) => '$title：没有数据。';
  String growthChartSummary({
    required String title,
    required int n,
    required String last,
    required int window,
    required String average,
  }) => '$title：$n 场，最近一局 $last，最近 $window 场平均 $average。';

  // ---- trend page ----

  String get trendFailed => '无法读取往期赛季';
  String get trendLoading => '正在读取往期赛季…';
  String noPastSeasons(String mode) => '没有往期$mode记录';
  String noPastSeasonsBody(String mode) => '近 6 个赛季无$mode职责数据（未玩过或资料未公开）。';

  /// Header: mode and the season span, short form (S5–S10).
  String trendTitle(String mode, int first, int last) =>
      '$mode · S$first–S$last';
  String get metricSemantic => '指标';
  String noRanksIn(String mode) => '$mode没有段位';
  String get rankInfo => '三图纵轴一致。实线：赛季末段位；虚线：赛季最高段位。';
  String noRankInfo(String mode) => '$mode无段位，请切换到胜率。';
  String get winRateInfo => '胜率 = 胜 ÷（胜 + 负），纵轴 0–100%，无数据的赛季断开。';
  String onlyOneSeason(int season) => '仅有第 $season 赛季数据，不绘制折线。';
  String get seasonsTitle => '各赛季数据';
  String get seasonsTable => '各赛季各职责数据';
  String get seasonColumn => '赛季';

  /// Short season label for axes, cells and cards: S5.
  String seasonShort(int? season) => season == null ? '—' : 'S$season';
  String get seasonEndRank => '赛季末段位';
  String get peakRank => '最高段位';
  String seasonRow({
    required String season,
    required String role,
    required String matches,
    required String winRate,
    required String current,
    required String peak,
  }) => '$season，$role，$matches 场，胜率$winRate，赛季末$current，最高$peak';
  String roleNoData(String role) => '$role：无数据。';
  String roleSummary(String role, int first, int last, String latest) =>
      '$role：S$first–S$last，最近有数据的赛季为 $latest。';
  String percent(String v) => '$v%';
  String get seasonEnd => '赛季末';
  String get peak => '最高';
  String get noData => '没有数据';
  String seasonPointNote(String matches, String rank) => '$matches 场 · $rank';

  // Rank tracks (season trend page).
  String get tracksTitle => '段位轨迹';
  String get tracksTip =>
      '每职责一条线：每场结束时的段位分，阶梯表示保持到下一场；空心点为败局。虚线为赛季分界（按各赛季生涯场次倒推，为估算）。点击或按 Enter 查看对局。';
  String get tracksNone => '暂无带段位分的对局（仅竞技对局有）。';
  String seasonMark(int s) => 'S$s';
  String trackSummary(String role, String from, String to, int n) =>
      '$role：$n 场，从 $from 到 $to';
  String get trackOpenHint => '点已指着的一场或按 Enter 打开这场对局';
  String get dropsTitle => '掉分局对手强度';
  String get dropsTip => '连续掉分 ≥ 100（一个小段）的区间里，对方均分比己方高多少，来自已算过对局强度的对局。';
  String drop(
    String role,
    String from,
    String to,
    int lost,
    int n,
    int w,
    int l,
  ) => '$role $from – $to 掉了 $lost 分（$n 场，$w 胜 $l 负）';
  String dropEdge(int rated, String edge) => '其中 $rated 场有对局强度：对面平均$edge';
  String edgeHigher(int v) => '高 $v 分';
  String edgeLower(int v) => '低 $v 分';
  String get edgeEven => '与己方持平';
  String get dropNoEdge => '这几场暂无对局强度，可在对局强度页分析。';
  String get openDropMatch => '打开最后一场';
}
