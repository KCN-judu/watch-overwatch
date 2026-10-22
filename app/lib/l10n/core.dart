/// Model labels, formatting, commands and app-state messages (core/, state/). See strings.dart for the rules.
class CoreStrings {
  const CoreStrings();

  // ---- core/models.dart ----

  String get modeCompetitive => '竞技比赛';
  String get modeCompetitiveShort => '竞技';
  String get modeQuick => '快速比赛';
  String get modeQuickShort => '快速';
  String get modeStadium => '角斗领域';
  String get modeStadiumShort => '角斗';

  String get roleTank => '重装';
  String get roleDamage => '输出';
  String get roleSupport => '支援';

  /// All roles together.
  String get roleOpen => '综合';

  String get outcomeWin => '胜';
  String get outcomeLoss => '负';
  String get outcomeDraw => '平';

  String get queueRole => '职责队列';
  String get queueOpen => '开放队列';

  /// An entity the provider named only by id: 未知（…a1b2c3）.
  String unknownEntity(String id) => '未知（$id）';

  /// Tier and division: 白金2. [division] may be missing.
  String rank(String tier, int? division) => '$tier${division ?? ''}';

  // ---- core/support.dart ----

  /// Play time under an hour.
  String playTimeMinutes(int minutes) => '$minutes 分钟';

  /// Play time of an hour or more.
  String playTimeHours(int hours, int minutes) => '$hours 小时 $minutes 分钟';

  // ---- core/hero_stats.dart ----

  /// The two parts of healing.
  String get selfHealing => '自我治疗';
  String get healingOthers => '对他人';

  /// Eliminations that are not the player's own final blows.
  String get sharedEliminations => '共同消灭';

  // ---- core/gamedata.dart ----

  String get abilityUltimate => '终极技能';
  String get abilityWeapon => '武器';
  String get abilityBasic => '技能';
  String get abilityPassive => '被动';

  // ---- core/api.dart ----

  String get requestFailed => '请求失败。';
  String get unreadableResponse => '本地服务返回了无法读取的响应。';
  String serviceTimeout(int seconds) => '本地服务超过 $seconds 秒没有响应。';
  String serviceUnreachable(int port) => '无法连接本地服务（端口 $port）。它可能还在启动或已退出。';
  String get serviceNotFound => '找不到 watchd.exe，请放在应用同一目录。';
  String serviceStartFailed(Object error) => '无法启动 watchd：$error';
  String get serviceStartTimeout => 'watchd 已启动，但 10 秒内没有响应。';

  // ---- core/export_file.dart ----

  /// Confirm button of the save dialog.
  String get save => '保存';

  // ---- core/image_store.dart ----

  String imageLoadFailed(String url, Object? reason) => '无法加载图片 $url：$reason';

  // ---- state/app_state.dart ----

  String get tabOverview => '概览';
  String get tabMatches => '对局';
  String get tabHeroes => '英雄';
  String get tabMaps => '地图';
  String get tabPeople => '常遇玩家';
  String get tabStrength => '对局强度';
  String get tabGrowth => '成长';
  String get tabTrend => '赛季走势';
  String get tabProfile => '档案';

  String get strengthReading => '正在读取对局…';

  /// A later round of the lobby-strength analysis, after some matches had no player to rate.
  String strengthRound(int round) => '第 $round 轮：有对局没有可评定的玩家，再多取几场…';
  String get strengthReadingOlder => '对局不够，正在读取更早的对局…';

  String get serviceUnavailable => '无法连接本地服务。';

  String get cacheCleared => '已清除本地缓存';
  String cacheClearFailed(String reason) => '无法清除本地缓存：$reason';

  String playerRemoveFailed(String name, String reason) => '无法移除 $name：$reason';
  String playerRemoved(String name) => '已从玩家库移除 $name';
  String get undo => '撤销';
  String playerRestoreFailed(String name, String reason) =>
      '无法恢复 $name：$reason';

  String get exportPickLocation => '请选择保存位置…';

  /// Suggested file name of an exported dataset; [player] has no '#'.
  String exportFileName(String player) => '$player-数据集.json';
  String get exportAssembling => '正在整理导出内容…';
  String exportSaved(String path) => '数据集已保存：$path';
  String get exportCancelled => '已取消导出，没有写入文件。';
  String get exportWriteFailed => '无法保存到所选位置。请换一个文件夹，并检查权限和剩余空间。';
  String exportFailed(String reason) => '导出失败：$reason';

  /// Reading the match list of [mode] for an export; [seen] matches read so far.
  String exportReadingList(String mode, int seen) =>
      seen > 0 ? '读取$mode对局列表（已读 $seen 场）…' : '读取$mode对局列表…';

  String exportPreparing(String mode, int done, int total) =>
      '准备$mode对局数据 $done/$total…';

  // ---- state/commands.dart ----

  /// Command palette categories (the shell orders them by this text).
  String get categoryFile => '文件';
  String get categoryView => '视图';
  String get categoryMode => '模式';
  String get categoryMatches => '对局';
  String get categoryAppearance => '外观';
  String get categoryHelp => '帮助';

  String get needPlayer => '先在左侧打开一名玩家。';
  String get needOpenItem => '打开一场对局或一个英雄后可用。';
  String get onlyInMatchList => '在对局列表中可用。';
  String get exportBusy => '正在导出，请等待完成或取消。';

  String get cmdFindPlayer => '查找玩家';
  String get cmdExport => '导出数据集';
  String get cmdSettings => '设置';
  String get cmdRefresh => '刷新数据';
  String get cmdSearchList => '搜索当前列表';
  String get cmdPrevItem => '上一项';
  String get cmdNextItem => '下一项';
  String get cmdBackToList => '返回列表';
  String get cmdToggleNav => '折叠或展开玩家库';
  String get cmdNextPane => '切换窗格';
  String get cmdPrevPane => '反向切换窗格';
  String cmdDensity(String density) => '表格密度：$density';
  String get cmdThemeSystem => '外观：跟随系统';
  String get cmdThemeLight => '外观：浅色';
  String get cmdThemeDark => '外观：深色';
  String get cmdResetLayout => '重置界面布局';
  String get cmdPalette => '命令面板';
  String get cmdShortcuts => '快捷键参考';

  /// Extra words the command palette matches against.
  String get settingsKeywords => 'account 账号 token 外观';
  String get densityKeywords => 'density 行高';
  String get themeKeywords => 'theme 主题';

  // ---- rank tiers ----

  /// Provider tier keys to the normal ladder's names. The catalog's names win when it has
  /// them (`Catalog.rankName`); these are the same names for an older service.
  Map<String, String> get tiers => const {
    'Bronze': '青铜',
    'Silver': '白银',
    'Gold': '黄金',
    'Platinum': '白金',
    'Emerald': '翡翠',
    'Diamond': '钻石',
    'Master': '大师',
    'Grandmaster': '宗师',
    'Champion': '英杰',
  };

  /// The Stadium ladder's own tier names (it has no 翡翠 and no 英杰).
  Map<String, String> get tiersStadium => const {
    'Bronze': '菜鸟',
    'Silver': '新秀',
    'Gold': '斗士',
    'Platinum': '精英',
    'Diamond': '专家',
    'Master': '全明星',
    'Grandmaster': '传奇',
  };

  /// A rank known only by its rating (Stadium ratings are not turned into tiers).
  String ratingOnly(String rating) => '段位分 $rating';
}
