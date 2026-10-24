/// The string table: every sentence, label and message the app shows the user.
///
/// Pages read their wording from here (`tr.matches.noRecord(name, mode)`), never from
/// literals in widgets (docs/ui-design.md §8). Only `zh_CN` exists today; another
/// language means making these classes abstract and adding an implementation.
///
/// Rules for every entry:
///  - A whole sentence is one entry. Values go in as parameters (`noRecord(name, mode)`),
///    never by gluing fragments together, so a translation can reorder them.
///  - Words follow the glossary in docs/ui-design.md §2 (段位 / 段位分, 已定级 / 未定级,
///    对局 / 场, 读取 / 加载 / 查询, 刷新 / 重新分析 / 重新查询段位 / 重试, 搜索 / 筛选,
///    移除 / 清除, 己方 / 对方, 第 N 赛季, 该玩家 …).
///  - The voice is a game stats tool's (docs/ui-design.md §8 措辞): labels in players'
///    words (强势图 / 苦手图, 绝活, 连胜中, 零阵亡, 同分段, 段位同步, 高光时刻); facts and
///    figures, never advice, comfort or judgement of a player; a tip is one or two short
///    clauses, the rule first; one fact per clause, joined with ，(tr.common.sep), never an
///    infix dot ·; no “只有……才会出现” or
///    “会随之生成” narrating the app itself; the provider is “大神”, never “上游”.
///  - The player being looked at needs no subject in most lines; where it must be told
///    apart from others it is “本人”, never “你” (the user may be looking at someone
///    else).
///  - Not here: data from the game or the provider (hero, map and stat names, map
///    modes, rank tiers as keys), which are matched against upstream values.
library;

import 'analysis.dart';
import 'common.dart';
import 'compare.dart';
import 'core.dart';
import 'daily.dart';
import 'heroes.dart';
import 'maps.dart';
import 'matches.dart';
import 'overview.dart';
import 'people.dart';
import 'recap.dart';
import 'shell.dart';
import 'update.dart';

export 'analysis.dart';
export 'common.dart';
export 'compare.dart';
export 'core.dart';
export 'daily.dart';
export 'heroes.dart';
export 'maps.dart';
export 'matches.dart';
export 'overview.dart';
export 'people.dart';
export 'recap.dart';
export 'shell.dart';
export 'update.dart';

class Strings {
  const Strings();

  /// Words and actions used on many pages.
  CommonStrings get common => const CommonStrings();

  /// Model labels, formatting, commands and app-state messages (core/, state/).
  CoreStrings get core => const CoreStrings();

  /// Lobby strength, growth and season trend pages.
  AnalysisStrings get analysis => const AnalysisStrings();

  /// Shell, navigator, player header, overlays, settings and shared design widgets.
  ShellStrings get shell => const ShellStrings();

  /// Heroes list, hero detail and profile pages.
  HeroStrings get heroes => const HeroStrings();

  /// Comparisons of two heroes, two stretches of time, two players.
  CompareStrings get compare => const CompareStrings();

  /// The recap and share pictures.
  RecapStrings get recap => const RecapStrings();

  /// The daily summary.
  DailyStrings get daily => const DailyStrings();

  /// The frequent players page.
  PeopleStrings get people => const PeopleStrings();

  /// The maps page.
  MapStrings get maps => const MapStrings();

  /// Checking for and installing a new version.
  UpdateStrings get update => const UpdateStrings();

  /// The overview page.
  OverviewStrings get overview => const OverviewStrings();

  /// Match list, match detail, team tables and the player card.
  MatchStrings get matches => const MatchStrings();
}

/// The app's strings, for code with or without a `BuildContext`.
const tr = Strings();
