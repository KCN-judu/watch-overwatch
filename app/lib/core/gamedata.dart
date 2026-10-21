import 'dart:convert';

import 'package:flutter/material.dart' show Color;
import 'package:flutter/services.dart' show rootBundle;

import '../l10n/strings.dart';

/// Hero reference data read from the installed game (see `docs/game-data.md`):
/// abilities, perks and the subrole passive, in the CN client's wording.
class GameAbility {
  GameAbility(Map<String, dynamic> j)
    : name = '${j['name']}',
      category = '${j['category']}',
      description = (j['description'] as String?) ?? '',
      icon = j['icon'] as String?;
  final String name, category, description;
  final String? icon;

  /// How the game groups it; drives the order and the label.
  String get categoryLabel => switch (category) {
    'UltimateAbility' => tr.core.abilityUltimate,
    'Weapon' => tr.core.abilityWeapon,
    'Ability' => tr.core.abilityBasic,
    'PassiveAbility' => tr.core.abilityPassive,
    _ => '',
  };
  int get order => switch (category) {
    'Weapon' => 0,
    'Ability' => 1,
    'UltimateAbility' => 2,
    'PassiveAbility' => 3,
    _ => 4,
  };
  String? get asset => icon == null ? null : 'assets/game/$icon';
}

class GamePerk {
  GamePerk(Map<String, dynamic> j)
    : name = '${j['name']}',
      description = (j['description'] as String?) ?? '',
      icon = j['icon'] as String?;
  final String name, description;
  final String? icon;
  String? get asset => icon == null ? null : 'assets/game/$icon';
}

class GameHero {
  GameHero(Map<String, dynamic> j)
    : name = '${j['name']}',
      description = (j['description'] as String?) ?? '',
      color = _hex(j['color'] as String?),
      subrole = (j['subrole'] as Map?)?['name'] as String?,
      subrolePassive = (j['subrole'] as Map?)?['passive'] as String?,
      abilities = [
        for (final a in (j['abilities'] as List? ?? const []))
          GameAbility((a as Map).cast<String, dynamic>()),
      ],
      perks = [
        for (final p in (j['perks'] as List? ?? const []))
          GamePerk((p as Map).cast<String, dynamic>()),
      ];
  final String name, description;
  final String? subrole, subrolePassive;

  /// The hero's signature colour in the game's UI.
  final Color? color;
  final List<GameAbility> abilities;

  /// Four perks: the first two are the minor (level 1) pair, the last two the major pair.
  final List<GamePerk> perks;

  /// Abilities without the role and subrole passives, which the header already shows.
  List<GameAbility> get kit => [
    for (final a in abilities)
      if (a.order < 4 && !a.name.startsWith('职责：')) a,
  ]..sort((a, b) => a.order.compareTo(b.order));
}

/// `#RRGGBBAA` → colour.
Color? _hex(String? s) {
  if (s == null || !RegExp(r'^#[0-9A-Fa-f]{6,8}$').hasMatch(s)) return null;
  final rgb = int.parse(s.substring(1, 7), radix: 16);
  return Color(0xFF000000 | rgb);
}

class GameData {
  GameData._(this._heroes);
  final Map<String, GameHero> _heroes;
  GameHero? hero(String? name) => _heroes[name];

  static Future<GameData>? _loading;

  /// The data once [load] has finished, for `initialData`: a page opened after that
  /// draws in the hero's colours from its first frame instead of flashing the accent.
  static GameData? loaded;

  /// Loaded once; the file is a few hundred KB.
  static Future<GameData> load() => _loading ??= () async {
    final raw = await rootBundle.loadString('assets/game/heroes.json');
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return loaded = GameData._({
      for (final j in list) '${j['name']}': GameHero(j),
    });
  }();
}
