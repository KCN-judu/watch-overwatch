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
      '比较己方与对方的平均段位。重装、输出、支援只平均打这个职责的玩家，综合是全部。'
      '${quick ? '快速比赛没有段位，用每名玩家本赛季的竞技段位代替（没有取上赛季），职责按他这局所打的。' : '使用每名参与者在这一局里的段位。'}';

  String get strengthFailed => '无法完成对局强度分析';
  String get scope => '范围';
  String get scopeSemantic => '分析哪个职责';
  String get busyDisabled => '分析进行中，完成或取消后才能更改';
  String get all => '全部';
  String get scopeAllHint => '三个职责各取最近 N 场';

  /// Hint on a role segment of the scope control.
  String scopeRoleHint(String role) => '只分析该玩家打$role的对局';

  /// Before the match-count control: one role, or each of them.
  String recentPrefix({required bool eachRole}) => eachRole ? '各取最近' : '取最近';
  String get countSemantic => '取的场数';
  String get startAnalysis => '开始分析';
  String get reanalyse => '重新分析';
  String get reanalyseTip => '读取新的对局，已读过的直接用缓存';
  String get requeryRanks => '重新查询段位';
  String get requeryRanksTip => '重新查询玩家的当前段位；对局详情仍用缓存';
  String get valueDisplay => '数值显示';
  String get tierSegment => '段位';
  String get tierSegmentHint => '如 白金 2';
  String get ratingSegment => '段位分';
  String get ratingSegmentHint => '500–5000';

  // ---- strength page: result summary ----

  String get noRatedMatches => '没有可计算强度的对局';

  /// Nothing was read for this mode.
  String noMatchesRead(String mode) => '该玩家在$mode没有读取到对局。';

  String noRatedPlayers(int read, int requested) =>
      '读取了 $read / $requested 场详情，但没有玩家能确定段位。快速比赛要求玩家有竞技段位，竞技要求对局里带段位。';

  String unratedMatchesTip(int n) => '这 $n 场里没有任何已定级的参与者，图里和明细里留空，不计入场数和平均。';
  String unratedMatches(int n) => '另有 $n 场没有已定级玩家';

  /// Per-role coverage: the target count was reached.
  String roleCoverageFull(String role, int n) => '$role：取了最近 $n 场';

  /// Per-role coverage: fewer usable matches than the target.
  String roleCoverageShort(String role, int have, int n) =>
      '$role：只有 $have 场可用，不足 $n 场，已取全部';
  String roleCount(String role, int n) => '$role $n 场';

  String cacheHitsTip(int n) => '这次分析里有 $n 项直接取自本机缓存，没有向上游请求';
  String cacheHits(int n) => '缓存 $n';
  String get ratedOfAllTip => '已定级的参与者 / 全部参与者';

  String unratedNote({required bool hasUnratedMatches}) =>
      '未定级或资料不可见的玩家不计入平均，也不会当作 0。'
      '${hasUnratedMatches ? '双方都没有已定级玩家的对局会留空，不计入场数和平均。' : ''}';

  // ---- strength page: by-role table ----

  String get byRoleTitle => '按该玩家所打的职责';
  String get byRoleInfo => '同职责 = 该玩家打的职责。差 = 己方 − 对方，正数表示己方更强。';
  String get byRoleTable => '按该玩家所打职责汇总的对局强度';

  /// Tooltip on an average: points, then the tier.
  String ratingTip(String points, String tier) => '$points 分 · $tier';
  String sideMeanTip(String side) => '$side · 同职责平均';
  String get playedRole => '该玩家打的职责';
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
  String get perMatchInfo => '点击一行打开这场对局。加粗的列是该玩家所打的职责。';
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
      '$when，$map，$outcome，该玩家打$role，综合 己方$allyAll 对方$enemyAll，'
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
      '从对局页已读取的对局里，${role ?? '每个职责'}取最近 $n 场（不够会自动多读）。'
      '第一次最多约 $requests 次请求${quick ? '，约 1–2 分钟' : ''}，之后大多取自缓存；可随时取消。';

  String selectedMatches(int n) => '已选 $n 场';
  String get queryNotNeeded => '无需查询（该模式对局里已有段位）';
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
  String stepSelectHint(int n) => '从已读取的对局里，每个职责取最近 $n 场';
  String get stepDetails => '读取对局详情';
  String get stepDetailsHint => '每场读一次，取得双方全部玩家；读过的用缓存';
  String get stepRanks => '查询参与者段位';
  String stepRanksHint({required bool quick}) =>
      quick ? '快速比赛没有段位，逐个查询每名玩家的竞技段位' : '该模式对局里已有段位，不需要查询';
  String get stepCombine => '整合计算';
  String get stepCombineHint => '合并每场强度并按职责汇总';
  String requestsSent(int requests, int cached) =>
      '已发出 $requests 次请求${cached > 0 ? '，$cached 项取自缓存' : ''}';
  String failures(int n) => '$n 次失败，不计入平均';

  // ---- strength page: chart ----

  String get chartAllRoles => '全部职责';
  String chartRole(String role) => '该玩家打$role';
  String chartNoData(String name) => '$name：这些对局里没有已定级的玩家，无法绘制。';

  /// A null mean has no data.
  String chartSummary(
    String name,
    int n,
    String? allyMean,
    String? enemyMean,
  ) => '$name，$n 场：己方平均 ${allyMean ?? '无数据'}，对方平均 ${enemyMean ?? '无数据'}。';
  String get chartTitle => '逐场走势';
  String get chartRoleSemantic => '该玩家所打的职责';
  String get chartInfo =>
      '按该玩家打的职责筛选对局。竖条是该队已定级玩家的最低到最高段位，圆点是平均，悬停看段位分；斜线阴影是没有已定级玩家的对局。';
  String points(String v) => '$v 分';
  String ratedCount(int n) => '已定级 $n 人';
  String rangeMeaning({required bool tiers}) =>
      '竖条：该队已定级玩家的最低到最高${tiers ? '段位' : '段位分'}，圆点是平均。斜线阴影：这些场没有已定级的玩家。';

  /// The readout line about one match.
  String chartPointNote(String outcome, String role) => '$outcome · 该玩家打$role';
  String get chartAsTable => '以表格查看图中的数值';
  String chartTableRow(String when, String ally, String enemy, String diff) =>
      '$when  己方 $ally  对方 $enemy  差 $diff';
  String otherRoleNote(int n) => '其中 $n 人没有这个职责的段位，按其他职责的最高段位计';

  // ---- growth page ----

  String get lifeTitle => '存活时长（保活能力）';
  String get lifeInfo =>
      '每次阵亡之间平均隔多久 = 对局时长 ÷ 阵亡次数。上游只给阵亡次数、不给每次阵亡的时间点，所以只能这样平均着算。'
      '没有死亡的对局取整局时长（实际只会更长），用盾牌标出，背后的底色填满这一局；含重生等待。';
  String lifeNoteDeathless(String duration) => '对局时长 $duration · 没有死亡';
  String lifeNote(String duration, String deaths) =>
      '对局时长 $duration · 阵亡 $deaths 次';
  String get lifeCard => '保活能力';
  String seconds(String signed) => '$signed 秒';
  String get lifeShield => '盾牌：这一局没有死亡，数值是整局时长，实际更长。';
  String get fletaTitle => 'Fleta 指数';
  String get fletaInfo =>
      '最后一击 ÷（本队最后一击合计 × 0.5）× 100%。100% 表示拿下了本队一半的最后一击。'
      '只和本队比、不分职责，辅助和重装通常偏低，输出偏高，所以按职责看更有意义。';
  String get fletaCard => 'Fleta 指数';
  String percentagePoints(String signed) => '$signed 个百分点';
  String get kdaInfo => '（消灭 + 助攻）÷ 阵亡。没有死亡的对局按 1 次阵亡算，用盾牌标出。';
  String get deathless => '没有死亡';
  String deaths(String n) => '阵亡 $n 次';
  String get kdaShield => '盾牌：这一局没有死亡，按 1 次阵亡算。';
  String get healingTitle => '治疗量';
  String get healingInfo =>
      '每 10 分钟的治疗量（含自我治疗）。只算该玩家打辅助的对局：别的职责的治疗是副产品，混进来会把数字拉低。';
  String per10Min(String v) => '$v / 10 分钟';
  String get mitigationTitle => '阻挡量';
  String get mitigationInfo =>
      '每 10 分钟阻挡或减免的伤害。只算该玩家打重装的对局：别的职责的阻挡量很少，混进来没有意义。';

  String get growthFailed => '无法读取成长数据';
  String get growthLoading => '正在读取成长数据…';
  String noGrowthMatches(String mode) => '还没有可分析的$mode对局';
  String get readMatchListFirst => '先在“对局”页读取对局列表。';
  String detailsNotStored(int listed) =>
      '已读取 $listed 场，但它们的详情还没存到本机（需要对局时长和阵亡数）。'
      '打开几场对局，或等后台准备完成后再来。';
  String growthTitle(String mode) => '$mode · 成长';
  String get roleSemantic => '职责';
  String get growthInfo =>
      '每个指标一张图：一个点是一局，粗线是最近 10 场的平均；空心点是败局。'
      '图上面一行是走势：把对局分成较早一半和较新一半比平均值，并做趋势检验。'
      '不同职责的数值本来就不一样，换职责会让“全部”变化，所以以分职责的结果为准。';

  /// Coverage line under the header; the clauses that apply, joined.
  String growthCoverage({
    required int analysed,
    required int listed,
    required int notStored,
    required int skipped,
  }) => [
    '已分析 $analysed 场（对局列表共 $listed 场）',
    if (notStored > 0) '其余 $notStored 场的详情还没存到本机，后台准备好后会算进来',
    if (skipped > 0) '$skipped 场太短或没有阵亡数，没有计入',
  ].join('；');
  String get pValueNote =>
      'p 值：Mann-Kendall 趋势检验的双侧 p 值，即原假设（序列没有单调趋势）成立时，出现当前或更极端的检验统计量的概率；p < 0.1 时拒绝原假设，判定存在趋势；样本不足 8 场不检验。';
  String trendTooFew(String card) => '$card：场次不足';
  String trendUp(String card) => '$card呈现上升趋势';
  String trendDown(String card) => '$card呈现下降趋势';
  String trendFlat(String card) => '$card没有明显趋势';
  String get trendNeedsEight => '不到 8 场，看不出走势';
  String get baselineMeaning =>
      '灰色底带是该玩家之前 20 场的中间一半（第 1 到第 3 四分位），落在带外的一局才算反常；不足 8 场时没有底带。';
  String get confidenceFirm => '较可信';
  String get confidenceHint => '有迹象';
  String get confidenceNone => '看不出变化';
  String get confidenceTooFew => '样本不足';

  /// The trend card's second line: how big the change is, and how sure.
  String trendEffect(String changePct, String confidence) =>
      '较新一半比较早一半 $changePct% · $confidence';

  /// Under the trend cards: what the wording means (the p value is in each card's tip).
  String get confidenceMeaning =>
      '“较可信”：Mann-Kendall 趋势检验 p < 0.05；“有迹象”：p < 0.1；否则看不出变化。不足 8 场不检验。具体 p 值和前后两半的均值在悬停提示里。';
  String pValue(String p) => 'p $p';
  String trendTip({
    required String older,
    required String newer,
    required String change,
    required String changePct,
    required int matches,
    required String p,
  }) =>
      '较早一半 $older → 较新一半 $newer（$change，$changePct%），共 $matches 场；Mann-Kendall 检验 $p';
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
  String noPastSeasonsBody(String mode) => '最近 6 个赛季没有$mode的职责数据，可能没打过或资料为私密。';

  /// Header: mode and the season span, short form (S5–S10).
  String trendTitle(String mode, int first, int last) =>
      '$mode · S$first–S$last';
  String get metricSemantic => '指标';
  String noRanksIn(String mode) => '$mode没有段位';
  String get rankInfo => '三张图纵轴相同，可直接比较。实线是赛季末段位，虚线是该赛季最高段位。';
  String noRankInfo(String mode) => '$mode不提供段位，请切换到胜率。';
  String get winRateInfo => '胜率 = 胜 ÷ （胜 + 负），纵轴 0–100%。没有数据的赛季线会断开。';
  String onlyOneSeason(int season) => '只读到第 $season 赛季这一个赛季，不画折线。';
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
  String roleNoData(String role) => '$role：这些赛季没有可用数据。';
  String roleSummary(String role, int first, int last, String latest) =>
      '$role：第 $first 赛季到第 $last 赛季，最近一个有数据的赛季为 $latest。';
  String percent(String v) => '$v%';
  String get seasonEnd => '赛季末';
  String get peak => '最高';
  String get noData => '没有数据';
  String seasonPointNote(String matches, String rank) => '$matches 场 · $rank';

  // Rank tracks (season trend page).
  String get tracksTitle => '段位轨迹';
  String get tracksTip =>
      '每个职责一条线：每场对局结束时该玩家这个职责的段位分，阶梯表示段位保持到下一场。空心点是输掉的对局。虚线是赛季分界：对局列表不带赛季，分界按各赛季生涯场次从最新一场往回数出来，所以是推算的。点一场（鼠标点已指着的那一场，或按 Enter）打开这场对局。';
  String get tracksNone => '本机存的对局里还没有带段位分的对局。竞技比赛的对局才带段位。';
  String seasonMark(int s) => 'S$s';
  String trackSummary(String role, String from, String to, int n) =>
      '$role：$n 场，从 $from 到 $to';
  String get trackOpenHint => '点已指着的一场或按 Enter 打开这场对局';
  String get dropsTitle => '掉分时对面强不强';
  String get dropsTip =>
      '一段连续掉了 100 分（一个小段）以上的对局：对面平均段位分比我方高多少，来自打开过详情、算过对局强度的对局。';
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
  String get edgeEven => '与我方持平';
  String get dropNoEdge => '这几场还没有对局强度。打开它们的详情，或在对局强度页分析后再看。';
  String get openDropMatch => '打开最后一场';
}
