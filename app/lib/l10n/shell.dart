/// Shell, navigator, player header, overlays, settings and shared design widgets. See strings.dart for the rules.
class ShellStrings {
  const ShellStrings();

  // ---- ui/shell.dart ----

  String get undo => '撤销';
  String get playerLibrary => '玩家库';
  String get workArea => '工作区';
  String get commandPalette => '命令面板';
  String get backendStartingTitle => '正在启动本地服务…';
  String get backendStartingBody => '首次启动通常不到 3 秒。';
  String get backendNotRunning => '本地服务未运行';

  /// Raw detail for the offline panel when the launcher gave no reason (only in 复制详情).
  String get backendUnreachable => '无法连接本地服务。';
  String get backendDataSafe => '已保存的玩家与账号不受影响。';
  String get noAccountTitle => '还没有大神账号';
  String get noAccountDetail => '查找玩家和读取对局都需要一个大神账号。凭据只保存在本机。';
  String get addAccount => '添加账号';
  String get noReadyAccountTitle => '没有可用的大神账号';
  String get noReadyAccountDetail => '账号可能已过期或正在冷却。请在设置中更新 token，或稍后重试。';
  String get findFirstPlayer => '查找第一名玩家';
  String get choosePlayer => '选择一名玩家';
  String get findFirstPlayerBody => '输入完整的战网昵称（例如 Player#12345）。';
  String get choosePlayerBody => '从左侧玩家库选择，或输入新的战网昵称。';
  String get findPlayer => '查找玩家';
  String get metricDocHint => '点击查看口径说明';
  String get searchFailed => '查找失败';

  // First run: three steps, or the sample player.
  String get welcomeTitle => '欢迎使用 Watch Overwatch';
  String get welcomeBody => '三步查看战绩，也可先用示例数据体验。';
  String get welcomeBodyPlain => '三步查看战绩。';
  String get stepAccount => '添加大神账号';
  String get stepAccountBody =>
      '在设置里粘贴大神 App 的 role_id 和 token（获取方法见使用指引的“凭据”一节），点“测试连接”确认可用。凭据只保存在本机。';
  String get stepAccountDone => '已添加账号';
  String get stepFind => '输入战网昵称';
  String get stepFindBody => '在左上角的搜索框输入完整的战网昵称，例如 Player#12345。';
  String get stepRead => '读取对局';
  String get stepReadBody => '首次从最新一场往回读取对局，之后只补新对局。';
  String get trySample => '先看示例数据';
  String get trySampleBody => '示例玩家为生成数据，无需账号，不会请求大神。';
  String get openSample => '打开示例玩家';

  /// The made-up player the service answers itself (`watch_core::demo::DEMO_NAME`).
  String get sampleName => '示例玩家#0000';
  String get backendConnected => '本地服务已连接';
  String get backendStarting => '正在启动本地服务';
  String get backendDisconnected => '本地服务未连接';

  /// Status bar: N/M 账号可用.
  String accountsReady(int ready, int total) => '账号 $ready/$total 可用';
  String get exporting => '正在导出数据集…';
  String get cancelExport => '取消导出';
  String lastExport(String path) => '最近导出：$path';

  // ---- ui/navigator_pane.dart ----

  String get battleTag => '战网昵称';
  String get battleTagHint => '战网昵称，如 Player#12345';
  String get playerNotFound => '没有找到这名玩家';
  String get searchHint => '输入完整昵称后按 Enter。';

  /// Header of the saved-player list: 玩家库（N）.
  String playerLibraryCount(int n) => '玩家库（$n）';
  String get playerLibraryEmpty => '暂无玩家。查找过的玩家会保存在这里。';
  String get settings => '设置';
  String get collapseLibrary => '折叠玩家库';
  String get expandLibrary => '展开玩家库';

  /// Screen-reader label of a saved player.
  String playerItem(String name) => '玩家 $name';

  /// Screen-reader label of the saved player that is open.
  String playerItemCurrent(String name) => '玩家 $name，当前';
  String removeFromLibrary(String name) => '从玩家库移除 $name';

  // ---- ui/player_view.dart ----

  String get endorsementLevel => '荣誉等级';
  String playTimeHours(String hours) => '$hours 小时';
  String get playTime => '游戏时长';
  String get totalMatches => '总场次';

  /// N 场, with N already formatted (1,234).
  String matchCountFormatted(String n) => '$n 场';
  String get loadingProfile => '正在读取玩家资料…';
  String get accountSuspended => '账号处于暂停状态';
  String accountSuspendedUntil(String until) => '账号处于暂停状态，到期 $until';
  String get mode => '模式';
  String get refreshData => '刷新数据';
  String get exportDataset => '导出数据集';
  String get noAvatar => '未设置头像';
  String noAvatarShowingHero(String hero) => '未设置头像，显示最常用英雄：$hero';
  String rankUnavailable(String message) => '竞技段位暂时无法读取：$message';
  String get rankMissing => '竞技段位  —';
  String get competitiveRank => '竞技段位';
  String get competitive => '竞技';
  String noRoleRankThisSeason(String role) => '本赛季没有$role的竞技记录';

  /// Tooltip of one role's rank in the player header.
  String roleRank(
    String role,
    String current,
    String skillRating,
    String peak,
    String matches,
  ) => '$role：当前 $current（$skillRating 分），最高 $peak，$matches 场';
  String get playerViews => '玩家视图';
  String updatedAt(String time) => '更新于 $time';
  String updatedAtStaleTip(String time) => '更新于 $time（超过 5 分钟）';
  String updatedAtStale(String time) => '更新于 $time（已超过 5 分钟）';
  String refreshFailedShowingOld(String error) => '刷新失败，当前为旧数据：$error';

  // ---- ui/overlays.dart ----

  String get paletteGroupCommands => '命令';
  String get paletteGroupPlayers => '玩家';
  String openPlayer(String player) => '打开玩家  $player';
  String get closePalette => '关闭命令面板';
  String get paletteHint => '输入命令或玩家名，例如“导出”“快速”';
  String paletteNoMatch(String query) => '没有匹配“$query”的命令或玩家。';
  String paletteShowing(int shown, int total) => '显示 $shown / $total 项';
  String paletteTotal(int total) => '共 $total 项';
  String get paletteSelect => '选择';
  String get paletteRun => '执行';

  /// Screen-reader label of a palette row: the label, then its menu and why it is off.
  String paletteEntry(String label, {String? category, String? unavailable}) =>
      [label, ?category, if (unavailable != null) '不可用：$unavailable'].join('，');
  String get shortcutsTitle => '快捷键参考';
  String get shortcutsNote => '所有命令也在菜单和命令面板（Ctrl+K）里。输入文字时，单键快捷键不起作用。';
  String exportTitle(String player) => '导出 $player 的数据集';
  String get exportIntro => '导出为 JSON，含每场双方玩家数据，不含凭据。';
  String get exportModes => '包含的模式';
  String get exportAllModes => '全部模式';
  String get exportCount => '对局数量（每个模式取最近的）';
  String get exportCountLabel => '导出的对局数量';
  String get exportCountAll => '全部';
  String get exportCountCustom => '自定义';
  String get exportCountField => '场数（1–5000）';
  String get exportRanks => '同时导出玩家段位';
  String get exportRanksNote => '用于对局强度。首次需逐个查询，每场约多 7 秒；查过的直接复用。';
  String get exportReadNote => '本机已有的对局直接使用，缺的约每场 1 秒读取，后台进行，可随时取消。';
  String get startExport => '开始导出';
  String get exportNeedMode => '至少选择一个模式。';
  String get exportNeedCount => '请输入场数。';

  // ---- ui/pages/settings_page.dart ----

  String get accountNameRequired => '填写一个账号名称，用来在列表里区分。';
  String get roleIdInvalid => 'role_id 是一串数字。';
  String get tokenRequired => '粘贴 token。';
  String accountSaved(String name) => '已保存账号 $name';
  String get tokenScriptCopied => '已复制获取脚本。到 ds.163.com 的控制台粘贴运行。';
  String get tokenScriptCopyFailed => '无法复制脚本，请看 docs/credentials.md。';
  String removeAccountTitle(String name) => '移除账号“$name”？';
  String get removeAccountBody =>
      '这会删除本机保存的该账号的 role_id 和 token。token 不会再显示，需要重新添加时必须再次粘贴。';
  String get keepAccount => '保留账号';
  String get removeAccount => '移除账号';
  String accountRemoved(String name) => '已移除账号 $name';
  String removeAccountFailed(String message) => '无法移除账号：$message';
  String get dashenAccounts => '大神账号';
  String get dashenAccountsNote => '查询需要至少一个大神账号。凭据只存在本机，多个账号轮流使用。';
  String get columnName => '名称';
  String get columnStatus => '状态';
  String get columnActions => '操作';

  /// Screen-reader label of an account row.
  String accountRow(String name, String status) => '账号 $name，$status';
  String get noAccounts => '暂无账号，请在下方添加。';
  String get addOrUpdateAccount => '添加或更新账号';
  String get addOrUpdateNote => '名称相同会更新已有账号。token 留空不会保留旧值，请重新粘贴。';
  String get copyTokenScript => '复制获取脚本';
  String get copyTokenScriptNote =>
      '登录 ds.163.com，按 F12 打开控制台，粘贴运行；token 会自动复制到剪贴板。';
  String get saving => '正在保存…';
  String get saveAccount => '保存账号';
  String saveFailed(String message) => '无法保存：$message';
  String get appearance => '外观';
  String get theme => '主题';
  String get themeSystem => '跟随系统';
  String get themeLight => '浅色';
  String get themeDark => '深色';
  String get rowHeight => '表格行高';
  String get layout => '界面布局';
  String get resetLayout => '重置界面布局';
  String get dataAndBackend => '数据与本地服务';
  String get credentialsPath => '账号凭据位置';
  String get lastExportLabel => '最近导出';
  String get noExportYet => '还没有导出';
  String get backend => '本地服务';
  String get shortcuts => '快捷键参考';
  String get requestLog => '请求记录';
  String requestLogNote(int n) => '最近 $n 次对大神的请求。不含 token 或参数。';
  String get columnTime => '时间';
  String get columnEndpoint => '接口';
  String get columnResult => '结果';
  String get columnStatusCode => '状态码';
  String get columnQueueMs => '排队 ms';
  String get columnDurationMs => '耗时 ms';
  String get columnAttempts => '尝试';

  /// Screen-reader label of a request-log row.
  String requestRow(String endpoint, String status, String durationMs) =>
      '$endpoint，$status，耗时 $durationMs 毫秒';
  String get noRequests => '还没有请求。';
  String get unavailable => '不可用';

  /// What the local cache holds; [size] is already formatted (12.3 MB).
  String cacheStats(
    Object listed,
    Object matches,
    Object participants,
    String size,
  ) => '$listed 场对局记录、$matches 场详情（含段位快照）、$participants 名队友与对手，$size';
  String get localCache => '本地缓存';
  String get clearCache => '清除缓存';
  String get accountReady => '可用';
  String accountCooldown(int seconds) => '冷却中，约 $seconds 秒后恢复';
  String get accountExpired => 'token 已失效，需要更新';
  String get accountUnknown => '未知';
  String get requestOk => '成功';

  // ---- design/widgets.dart ----

  String get severityInfo => '提示';
  String get severityWarning => '警告';
  String get severityError => '错误';

  /// Screen-reader label of a status banner: 警告：title。detail.
  String banner(String severity, String title, String? detail) =>
      detail == null ? '$severity：$title' : '$severity：$title。$detail';
  String get nothingChanged => '没有保存或修改任何数据。';
  String removeFilterLabel(String filter) => '移除筛选条件“$filter”';
  String get removeFilter => '移除此筛选';

  /// What went wrong and what to do, by `ApiError.kind`. The raw message stays in 复制详情.
  String errorSentence(String kind) => switch (kind) {
    'offline' => errorOffline,
    'timeout' => errorTimeout,
    'auth' => errorAuth,
    'no_account' => errorNoAccount,
    'validation' => errorValidation,
    'busy' => errorBusy,
    'rate_limited' => errorRateLimited,
    'network' => errorNetwork,
    'response' => errorResponse,
    'business' => errorBusiness,
    'upstream' => errorUpstream,
    'shutdown' => errorShutdown,
    _ => errorUnknown,
  };
  String get errorOffline => '连不上本地服务。请确认 watchd.exe 在同一目录，然后重试。';
  String get errorTimeout => '请求超时。请稍后重试，或缩小查询范围。';
  String get errorAuth => '大神账号的凭据已失效。请在设置中更新 token，然后重试。';
  String get errorNoAccount => '还没有可用的大神账号。请先在设置中添加一个账号。';
  String get errorValidation => '这次请求的内容无效。请检查输入或重新选择后再试。';
  String get errorBusy => '本地服务繁忙，请稍后重试。';
  String get errorRateLimited => '请求过于频繁，大神已限流，请稍后重试。';
  String get errorNetwork => '连不上大神服务。请检查网络和代理设置，然后重试。';
  String get errorResponse => '大神返回的数据无法解析。请稍后重试，持续出现请复制详情反馈。';
  String get errorBusiness => '大神未返回有效数据：玩家不存在、资料未公开，或账号授权失效。';
  String get errorUpstream => '大神服务暂时不可用。请稍后重试。';
  String get errorShutdown => '本地服务正在关闭。请重新启动应用。';
  String get errorUnknown => '未知错误。请重试，持续出现请复制详情反馈。';

  // ---- design/cards.dart ----

  String get perkMinor => '一级威能';
  String get perkMajor => '二级威能';

  // ---- design/charts.dart ----

  String get chartNoData => '没有可绘制的数据';
  String axisTruncated(String min, String max) => '纵轴范围 $min–$max，不从 0 开始。';
  String get axisFromZero => '纵轴从 0 开始。';
  String get chartHintPerTeam => '悬停查看该队详情；←/→ 换场，↑/↓ 换队。';
  String get chartHint => '点击或按 ←/→ 查看精确值。';

  /// Shown in a chart tooltip where a series has no value at a point.
  String get chartValueMissing => '无数据';

  /// Chart tooltip line: series label and its value.
  String chartValue(String series, String value) => '$series  $value';
  String playerCount(int n) => '$n 人';
  String chartRankRange(String low, String high) => '段位  $low – $high';
  String chartSkillRatingRange(String low, String high) => '段位分  $low – $high';
  String chartMean(String mean) => '平均  $mean';

  /// Indented detail under a series in the chart tooltip, with the mean.
  String chartMeanAndRange(String mean, String low, String high) =>
      '    平均 $mean，区间 $low–$high';

  /// Indented detail under a series in the chart tooltip, without a mean.
  String chartRange(String low, String high) => '    区间 $low–$high';

  // ---- design/icons.dart ----

  String get unknownRole => '未知职责';

  /// Tooltip of every role column header.
  String get roleLegend => '盾牌 = 重装　子弹 = 输出　十字 = 支援';

  /// A rank with its skill rating: 白金 2（2650 分）.
  String rankWithRating(String rank, String rating) => '$rank（$rating 分）';
  String rankFromOtherRole(String rank) => '无该职责段位，取其他职责最高段位：$rank';
  String rankSnapshot(String rank) => '本局记录的竞技段位：$rank';
  String heroPortrait(String hero) => '$hero 立绘';
  String masteryLevel(int level) => '熟练度 $level';

  // ---- design/net_pic.dart ----

  String loadingImagesLabel(int done, int total) => '正在加载图片 $done / $total';
  String loadingImages(int done, int total) => '加载图片 $done/$total';

  // ---- design/data_table.dart ----

  /// Screen-reader label of a sorted column header.
  String sortedColumn(String column, bool ascending) =>
      ascending ? '$column，按升序排序' : '$column，按降序排序';

  // ---- design/tokens.dart ----

  String get densityCompact => '紧凑';
  String get densityStandard => '标准';
  String get densityComfortable => '宽松';

  // ---- design/chart_kit.dart ----

  /// Monday first, as the calendar in China.
  List<String> get weekdaysShort => const ['一', '二', '三', '四', '五', '六', '日'];
  String hourTick(int h) => '$h';
  String heatCell(String day, int hour, String value, int n) =>
      '周$day $hour 点：$value，$n 场';
  String heatCellTooFew(String day, int hour, int n) =>
      '周$day $hour 点：$n 场，太少不计';
  String get heatLegendLow => '低';
  String get heatLegendHigh => '高';
  String heatMeaning(String metric, int minN) =>
      '颜色越深，$metric偏离中线越多；不足 $minN 场不着色。';
  String intervalRow(String label, String value, String range, int n) =>
      '$label：$value（区间 $range），$n 场';
  String intervalRowTooFew(String label, String value, int n) =>
      '$label：$value，只有 $n 场，样本太少';
  String intervalMeaning(String reference) =>
      '横条：数值；细线：置信区间；竖线：$reference。灰色为场次不足，不参与比较。';
  String sparkline(String label, String first, String last) =>
      '$label：从 $first 到 $last';
}
