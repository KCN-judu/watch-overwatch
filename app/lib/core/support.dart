import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart';

import '../l10n/strings.dart';
import 'models.dart';

// ---- Catalog: images only. Names always come from the IR. ------------------

class Catalog {
  Catalog(Json? raw)
    : _heroes = (raw?['heroes'] as Map?)?.cast<String, dynamic>() ?? const {},
      _maps = (raw?['maps'] as Map?)?.cast<String, dynamic>() ?? const {},
      _icons = (raw?['icons'] as Map?)?.cast<String, dynamic>() ?? const {} {
    for (final s in (raw?['statistics'] as List? ?? const [])) {
      if (s is! Map) continue;
      final hero = '${s['heroGuid']}', guid = '${s['valueGuid']}';
      final name = s['valueText'];
      if (name is String && name.isNotEmpty) {
        (_expected[hero] ??= []).add((guid: guid, name: name));
      }
    }
  }
  final Map<String, List<({String guid, String name})>> _expected = {};
  final Map<String, dynamic> _heroes;
  final Map<String, dynamic> _maps;
  final Map<String, dynamic> _icons;
  bool get isEmpty => _heroes.isEmpty && _maps.isEmpty;

  String? _https(Object? v) =>
      v is String && v.startsWith('https://') ? v : null;

  /// Small square icon, falling back to the portrait.
  String? heroIcon(EntityRef? hero) {
    final h = hero == null ? null : _heroes[hero.guid];
    return _https(h?['small_icon']) ??
        _https(h?['icon']) ??
        _https(h?['portrait']);
  }

  /// Full portrait art; the provider's cover art stands in when no portrait is catalogued.
  String? heroPortrait(EntityRef? hero) {
    final h = hero == null ? null : _heroes[hero.guid];
    return _https(h?['portrait']) ??
        _https(h?['cover']) ??
        _https(h?['icon']) ??
        _https(h?['small_icon']);
  }

  /// Full-body standing art (transparent background) for hero pages.
  String? heroArt(EntityRef? hero) {
    final h = hero == null ? null : _heroes[hero.guid];
    return _https(h?['art']) ??
        _https(h?['cover']) ??
        _https(h?['portrait']) ??
        _https(h?['icon']);
  }

  /// The stats the game defines for a hero: what it can produce. A stat outside this
  /// list is one the hero has no way to record.
  List<({String guid, String name})> expectedStats(EntityRef? hero) =>
      hero == null ? const [] : (_expected[hero.guid] ?? const []);

  /// Wide banner art for the hero (provider's `destinyHeroBanner`).
  String? heroBanner(EntityRef? hero) {
    final h = hero == null ? null : _heroes[hero.guid];
    return _https(h?['banner']);
  }

  /// Role a hero is played in, from the catalog (list rows without a role use this).
  Role heroRole(EntityRef? hero) {
    final r = hero == null ? null : _heroes[hero.guid]?['role'];
    return switch (r) {
      'tank' => Role.tank,
      'dps' || 'damage' || 'offense' => Role.damage,
      'healer' || 'support' => Role.support,
      _ => Role.unknown,
    };
  }

  String? mapImage(EntityRef? map) {
    final m = map == null ? null : _maps[map.guid];
    return _https(m?['icon']);
  }

  String? mapMode(EntityRef? map) =>
      map == null ? null : (_maps[map.guid]?['mode'] as String?);

  /// Rank tier emblem (`Platinum` → image). Stadium has its own ladder.
  String? rankIcon(String? tier, {bool stadium = false}) {
    if (tier == null) return null;
    final table = _icons[stadium ? 'ranks_stadium' : 'ranks'];
    return table is Map ? _https(table[tier]) : null;
  }

  /// Pictures the first screens need: hero icons and portraits, rank and honour badges.
  List<String> preloadUrls() {
    final out = <String>[];
    for (final h in _heroes.values) {
      for (final k in const ['small_icon', 'icon', 'portrait']) {
        final u = _https(h is Map ? h[k] : null);
        if (u != null) out.add(u);
      }
    }
    for (final table in _icons.values) {
      if (table is Map) {
        for (final v in table.values) {
          final u = _https(v);
          if (u != null) out.add(u);
        }
      }
    }
    return out;
  }

  /// Perk icon (a white silhouette), looked up by the perk's `0x…` id.
  String? perkIcon(EntityRef? perk) {
    final table = _icons['perks'];
    final id = perk?.officialId;
    return id == null || table is! Map ? null : _https(table[id]);
  }

  String? endorsementIcon(int? level) {
    final table = _icons['endorsement'];
    return level == null || table is! Map ? null : _https(table['$level']);
  }
}

// ---- Formatting ------------------------------------------------------------

const missing = '—';
final _int = NumberFormat.decimalPattern('zh_CN');
final _one = NumberFormat('#,##0.0', 'zh_CN');
final _two = NumberFormat('#,##0.00', 'zh_CN');

String fmtInt(num? v) => v == null ? missing : _int.format(v.round());
String fmtOne(num? v) => v == null ? missing : _one.format(v);
String fmtTwo(num? v) => v == null ? missing : _two.format(v);
String fmtPct(num? v, {int digits = 1}) => v == null
    ? missing
    : '${(digits == 0 ? _int.format(v.round()) : _one.format(v))}%';

String two(int n) => n.toString().padLeft(2, '0');

String fmtDateTime(int? ms) {
  if (ms == null) return missing;
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}

String fmtTime(DateTime d) => '${two(d.hour)}:${two(d.minute)}';

String fmtClock(double? seconds) {
  if (seconds == null) return missing;
  final s = seconds.round();
  return '${s ~/ 60}:${two(s % 60)}';
}

String fmtPlayTime(double? seconds) {
  if (seconds == null) return missing;
  final minutes = (seconds / 60).round();
  if (minutes < 60) return tr.core.playTimeMinutes(minutes);
  return tr.core.playTimeHours(minutes ~/ 60, minutes % 60);
}

/// `Name#1234` → (`Name`, `#1234`).
(String, String) splitTag(String tag) {
  final i = tag.indexOf('#');
  return i < 0 ? (tag, '') : (tag.substring(0, i), tag.substring(i));
}

String fmtScore(int? a, int? b) => a == null || b == null ? missing : '$a:$b';

String fmtKda(StatLine s) =>
    s.kills == null && s.assists == null && s.deaths == null
    ? missing
    : '${fmtInt(s.kills)}/${fmtInt(s.assists)}/${fmtInt(s.deaths)}';

/// Chinese substring match: case-insensitive, no word-boundary assumptions.
bool matchesQuery(String haystack, String query) =>
    query.trim().isEmpty ||
    haystack.toLowerCase().contains(query.trim().toLowerCase());

// ---- Persisted interface state ---------------------------------------------

class UiState {
  static const version = 1;
  String theme = 'system';
  String density = 'standard';
  double navWidth = 248;
  bool navCollapsed = false;
  String? lastPlayer;
  String tab = 'matches';
  String mode = 'competitive';

  static File _file() {
    final base =
        Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path;
    return File(
      '$base${Platform.pathSeparator}Watch Overwatch${Platform.pathSeparator}ui-state.json',
    );
  }

  static UiState load() {
    final s = UiState();
    try {
      final j = jsonDecode(_file().readAsStringSync());
      // A different layout version is discarded rather than half-applied.
      if (j is Map && j['version'] == version) {
        s.theme = {'system', 'light', 'dark'}.contains(j['theme'])
            ? j['theme']
            : s.theme;
        s.density =
            {'compact', 'standard', 'comfortable'}.contains(j['density'])
            ? j['density']
            : s.density;
        s.navWidth = ((j['navWidth'] as num?)?.toDouble() ?? s.navWidth).clamp(
          180.0,
          360.0,
        );
        s.navCollapsed = j['navCollapsed'] == true;
        s.lastPlayer = j['lastPlayer'] is String ? j['lastPlayer'] : null;
        s.tab = j['tab'] is String ? j['tab'] : s.tab;
        s.mode = j['mode'] is String ? j['mode'] : s.mode;
      }
    } catch (_) {}
    return s;
  }

  void save() {
    try {
      final f = _file();
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(
        jsonEncode({
          'version': version,
          'theme': theme,
          'density': density,
          'navWidth': navWidth,
          'navCollapsed': navCollapsed,
          'lastPlayer': lastPlayer,
          'tab': tab,
          'mode': mode,
        }),
      );
    } catch (_) {
      // Layout is a convenience; failing to save it must never interrupt work.
    }
  }
}

// ---- Fixed-meaning icon keys -----------------------------------------------

/// Map game mode (as the provider names it) → bundled icon file. Modes without
/// an Overwatch icon (hero mastery, workshop, practice …) stay text only.
const modeIconKeys = {
  '占领要点': 'control',
  '运载目标': 'escort',
  '攻击/护送': 'hybrid',
  '机动推进': 'push',
  '闪点作战': 'flashpoint',
  '攻防阵线': 'clash',
  '攻防作战': 'assault',
  '死斗': 'deathmatch',
  '决斗先锋': 'elimination',
  '勇夺锦旗': 'capture-the-flag',
};

/// Hero (catalog name) → subrole key, from the official hero pages. Heroes added
/// after the survey are missing and simply show no subrole.
const heroSubroles = {
  '莱因哈特': 'stalwart',
  '西格玛': 'stalwart',
  '渣客女王': 'stalwart',
  '拉玛刹': 'stalwart',
  '温斯顿': 'initiator',
  'D.Va': 'initiator',
  '末日铁拳': 'initiator',
  '骇灾': 'initiator',
  '奥丽莎': 'bruiser',
  '路霸': 'bruiser',
  '查莉娅': 'bruiser',
  '毛加': 'bruiser',
  '猎空': 'flanker',
  '源氏': 'flanker',
  '死神': 'flanker',
  '探奇': 'flanker',
  '索杰恩': 'sharpshooter',
  '黑百合': 'sharpshooter',
  '半藏': 'sharpshooter',
  '艾什': 'sharpshooter',
  '卡西迪': 'sharpshooter',
  '士兵：76': 'specialist',
  '堡垒': 'specialist',
  '美': 'specialist',
  '狂鼠': 'specialist',
  '秩序之光': 'specialist',
  '托比昂': 'specialist',
  '法老之鹰': 'recon',
  '回声': 'recon',
  '弗蕾娅': 'recon',
  '黑影': 'initiator',
  '安娜': 'tactician',
  '卢西奥': 'tactician',
  '巴蒂斯特': 'tactician',
  '禅雅塔': 'tactician',
  '天使': 'medic',
  '雾子': 'medic',
  '莫伊拉': 'medic',
  '生命之梭': 'medic',
  '朱诺': 'survivor',
  '布丽吉塔': 'survivor',
  '伊拉锐': 'survivor',
  // Added after the first survey, from the OverFast hero list (same subroles as
  // the official pages). Names within one subrole are matched by role and count.
  '破坏球': 'initiator',
  '金驭': 'stalwart',
  'D.Mon': 'stalwart',
  '安燃': 'flanker',
  '斩仇': 'flanker',
  '死怨': 'flanker',
  '西拉': 'recon',
  '埃姆雷': 'specialist',
  '无漾': 'survivor',
  '瑞稀': 'survivor',
  '血律': 'survivor',
  '飞天猫': 'tactician',
};

/// Subrole name and passive, as the CN client words them (read from the installed
/// game's text tables, 2.25).
const subroleNames = {
  'bruiser': '斗士 Bruiser',
  'initiator': '先锋 Initiator',
  'stalwart': '铁壁 Stalwart',
  'sharpshooter': '神准 Sharpshooter',
  'flanker': '奇袭 Flanker',
  'specialist': '专业 Specialist',
  'recon': '侦察 Recon',
  'tactician': '战术 Tactician',
  'medic': '医疗 Medic',
  'survivor': '生存 Survivor',
};

const subrolePassives = {
  'bruiser': '获得暴击伤害抗性。生命值低于一半时移动速度加快',
  'initiator': '使用特定位移技能后获得持续治疗',
  'stalwart': '获得击退和减速抗性',
  'sharpshooter': '造成暴击会缩短位移技能的冷却时间',
  'flanker': '提高急救包恢复的生命值',
  'specialist': '消灭敌人后在短时间内加快装弹速度',
  'recon': '对生命值低于一半的敌人造成伤害会显示其位置',
  'tactician': '可过量储存终极技能充能',
  'medic': '使用武器治疗盟友也会治疗自己',
  'survivor': '位移技能会激活被动生命值恢复',
};

/// Hero proficiency tier 1–5 from `hero_level` (<25, <50, <75, <100, ≥100).
int levelTier(int level) => level < 25
    ? 1
    : level < 50
    ? 2
    : level < 75
    ? 3
    : level < 100
    ? 4
    : 5;
