import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/metric_doc.dart';
import '../core/models.dart';
import '../core/support.dart';
import '../l10n/strings.dart';
import 'interaction.dart';
import 'tokens.dart';
import 'widgets.dart' show NetImage;
import 'net_pic.dart';

/// The Overwatch role glyph (shield / bullets / cross), tinted by the theme.
/// Icon-only wherever space is tight; the label lives in the tooltip and the
/// accessibility tree, and the role column header carries a legend.
class RoleIcon extends StatelessWidget {
  const RoleIcon(
    this.role, {
    super.key,
    this.size = 16,
    this.color,
    this.showLabel = false,
    this.tooltip = true,
  });
  final Role role;
  final double size;
  final Color? color;

  /// First-class surfaces (header, summary rows) show the name beside the glyph.
  final bool showLabel;
  final bool tooltip;

  static const playableAssets = {
    Role.tank: 'assets/roles/tank.svg',
    Role.damage: 'assets/roles/damage.svg',
    Role.support: 'assets/roles/support.svg',
  };

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final asset = playableAssets[role];
    final tint = color ?? c.textPrimary;
    final glyph = asset == null
        ? Icon(Icons.remove, size: size, color: c.textSecondary)
        : _svg(asset, size, tint);
    final label = role.label.isEmpty ? tr.shell.unknownRole : role.label;
    final body = showLabel
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              glyph,
              const SizedBox(width: 6),
              Text(label, style: Ty.body.copyWith(color: tint)),
            ],
          )
        : glyph;
    final named = Semantics(
      label: label,
      image: true,
      excludeSemantics: true,
      child: body,
    );
    return tooltip && !showLabel
        ? Tooltip(message: label, child: named)
        : named;
  }
}

/// Legend for the three role glyphs, used as the tooltip of every role column header.
String get roleLegend => tr.shell.roleLegend;

/// Map picture as a recognition aid next to the map name. Never replaces the name.
class MapThumb extends StatelessWidget {
  const MapThumb(
    this.url, {
    super.key,
    this.width = 44,
    this.height = 26,
    this.radius = 4,
  });
  final String? url;
  final double width, height, radius;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final placeholder = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: c.header,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(
        Icons.map_outlined,
        size: height * 0.6,
        color: c.textSecondary,
      ),
    );
    if (url == null) return ExcludeSemantics(child: placeholder);
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: NetPic(
          url!,
          width: width,
          height: height,
          fit: BoxFit.cover,
          radius: radius,
          error: placeholder,
        ),
      ),
    );
  }
}

/// Rank as the provider's tier emblem plus the division number. Falls back to
/// text when the emblem is not available (offline, unknown tier, no catalog).
class RankBadge extends StatelessWidget {
  const RankBadge(
    this.rank, {
    super.key,
    required this.catalog,
    this.stadium = false,
    this.size = 20,
    this.showText = false,
    this.current = false,
    this.otherRoles = false,
  });
  final Rank? rank;

  /// The rank is the highest of the player's ranks in other roles (none for the role played).
  final bool otherRoles;

  /// The rank is the player's competitive rank now, not the one at the time of the match.
  final bool current;
  final Catalog catalog;
  final bool stadium;
  final double size;

  /// Also print the tier name (first-class surfaces).
  final bool showText;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final r = rank;
    if (r == null) {
      return Text(missing, style: Ty.cell.copyWith(color: c.textSecondary));
    }
    final url = catalog.rankIcon(r.tierKey(stadium: stadium), stadium: stadium);
    final text = r.labelOn(stadium: stadium);
    // A Stadium rank known only by its rating already reads “段位分 N”.
    final base = r.skillRating == null || (stadium && r.tier == null)
        ? text
        : tr.shell.rankWithRating(text, fmtInt(r.skillRating));
    final detail = otherRoles
        ? tr.shell.rankFromOtherRole(base)
        : current
        ? tr.shell.currentRankNotThen(base)
        : base;
    if (url == null) {
      return Tooltip(
        message: detail,
        child: Text(text, style: Ty.cell),
      );
    }
    return Tooltip(
      message: detail,
      child: Semantics(
        label: detail,
        excludeSemantics: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            NetPic(
              url,
              width: size,
              height: size,
              error: Text(text, style: Ty.cell),
            ),
            const SizedBox(width: 3),
            // The division is the number inside the tier; showing it keeps ranks comparable at a glance.
            Text(
              showText
                  ? text
                  : (r.divisionOrRating(stadium: stadium)?.toString() ?? ''),
              style: Ty.num(Ty.cell).copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

/// Hero head-and-shoulders for the right end of a row. The source is a square bust
/// with the face filling the frame, so it is drawn as a square the height of the row,
/// flush with the right edge: the whole face shows and the picture's right edge is the
/// row's edge. No fade. Pure decoration: hidden from the accessibility tree.
class PortraitCell extends StatelessWidget {
  const PortraitCell(this.url, {super.key});
  final String? url;
  @override
  Widget build(BuildContext context) {
    if (url == null) return const SizedBox.expand();
    return ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, box) {
          final side = box.maxHeight.isFinite ? box.maxHeight : box.maxWidth;
          return Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: side,
              height: side,
              child: NetPic(
                url!,
                width: side,
                height: side,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                radius: 0,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Full-body standing art (transparent background) for the hero statistics panel.
class HeroPortrait extends StatelessWidget {
  const HeroPortrait(
    this.url, {
    super.key,
    this.width = 150,
    this.height = 190,
    required this.name,
  });
  final String? url;
  final double width, height;
  final String name;
  @override
  Widget build(BuildContext context) {
    if (url == null) {
      return NetImage(null, size: width, fallback: name, radius: 8);
    }
    return Semantics(
      label: tr.shell.heroPortrait(name),
      image: true,
      excludeSemantics: true,
      child: SizedBox(
        width: width,
        height: height,
        child: NetPic(
          url!,
          width: width,
          height: height,
          fit: BoxFit.contain,
          alignment: Alignment.bottomCenter,
          radius: 12,
          error: NetImage(null, size: width, fallback: name, radius: 8),
        ),
      ),
    );
  }
}

/// Small “i” that holds the explanatory sentence a screen used to print inline.
///
/// It is a tab stop: focusing it with the keyboard shows the sentence, as hovering
/// does, so the explanation is never pointer-only. The hit area is 28px square.
///
/// About a figure, it names its section of the metrics page ([doc]): a click (or Enter)
/// opens that section, and the sentence says so.
class InfoTip extends StatefulWidget {
  const InfoTip(this.message, {super.key, this.doc});
  final String message;
  final MetricDoc? doc;

  @override
  State<InfoTip> createState() => _InfoTipState();
}

class _InfoTipState extends State<InfoTip> {
  final _tip = GlobalKey<TooltipState>();
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final ring = _focused && keyboardModality;
    final doc = widget.doc;
    final message = doc == null
        ? widget.message
        : [widget.message, tr.shell.metricDocHint].join('\n');
    return Focus(
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (f && keyboardModality) _tip.currentState?.ensureTooltipVisible();
      },
      onKeyEvent: (_, e) {
        if (doc != null &&
            e is KeyDownEvent &&
            e.logicalKey == LogicalKeyboardKey.enter) {
          doc.open();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Tooltip(
        key: _tip,
        message: message,
        triggerMode: doc == null
            ? TooltipTriggerMode.tap
            : TooltipTriggerMode.longPress,
        showDuration: const Duration(seconds: 8),
        child: Semantics(
          label: message,
          button: doc != null,
          child: GestureDetector(
            onTap: doc?.open,
            child: MouseRegion(
              cursor: doc == null
                  ? MouseCursor.defer
                  : SystemMouseCursors.click,
              child: Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Radii.control),
                  border: c.itemOutline(focused: ring),
                ),
                child: Icon(
                  Icons.info_outline,
                  size: 14,
                  color: c.textSecondary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

extension ModeIcon on Mode {
  /// Backs up the mode's name; the name is always shown or in the tooltip.
  IconData get icon => switch (this) {
    Mode.competitive => Icons.emoji_events_outlined,
    Mode.quick => Icons.bolt,
    Mode.stadium => Icons.stadium_outlined,
  };
}

SvgPicture _svg(String asset, double size, Color tint) => SvgPicture.asset(
  asset,
  width: size,
  height: size,
  colorFilter: ColorFilter.mode(tint, BlendMode.srcIn),
  excludeFromSemantics: true,
);

/// Map game-mode glyph (control point, payload, push …). Shows nothing for modes
/// without an Overwatch icon, so the caller keeps the name as text in that case.
class ModeGlyph extends StatelessWidget {
  const ModeGlyph(this.mode, {super.key, this.size = 18, this.color});
  final String? mode;
  final double size;
  final Color? color;

  static bool has(String? mode) => modeIconKeys.containsKey(mode);

  @override
  Widget build(BuildContext context) {
    final key = modeIconKeys[mode];
    if (key == null) return SizedBox(width: size, height: size);
    return Tooltip(
      message: mode!,
      child: Semantics(
        label: mode,
        child: _svg(
          'assets/gamemodes/$key.svg',
          size,
          color ?? context.c.textSecondary,
        ),
      ),
    );
  }
}

/// Hero subrole glyph (the official one); empty for heroes not in the table.
class SubroleIcon extends StatelessWidget {
  const SubroleIcon(this.heroName, {super.key, this.size = 18, this.color});
  final String? heroName;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final key = heroSubroles[heroName];
    if (key == null) return SizedBox(width: size, height: size);
    return Tooltip(
      message: '${subroleNames[key]}\n${subrolePassives[key]}',
      child: Semantics(
        label: subroleNames[key],
        child: _svg(
          'assets/subroles/${key[0].toUpperCase()}${key.substring(1)}.svg',
          size,
          color ?? context.c.textSecondary,
        ),
      ),
    );
  }
}

/// Proficiency badge (grey → green → blue → purple → orange) with the level beside it.
class LevelBadge extends StatelessWidget {
  const LevelBadge(this.level, {super.key, this.size = 22});
  final int? level;
  final double size;

  @override
  Widget build(BuildContext context) {
    final v = level;
    if (v == null) return const Text(missing);
    return Tooltip(
      message: tr.shell.masteryLevel(v),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/levels/tier${levelTier(v)}.png',
            width: size,
            height: size,
            filterQuality: FilterQuality.medium,
            excludeFromSemantics: true,
          ),
          const SizedBox(width: 6),
          Text('$v', style: Ty.num(Ty.body)),
        ],
      ),
    );
  }
}

/// A perk: its silhouette (tinted by the theme) with the name beside it.
class PerkChip extends StatelessWidget {
  const PerkChip(this.perk, {super.key, required this.catalog, this.size = 24});
  final EntityRef perk;
  final Catalog catalog;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final url = catalog.perkIcon(perk);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (url != null) ...[
          ExcludeSemantics(
            child: NetPic(
              url,
              width: size,
              height: size,
              color: c.textPrimary,
              blend: BlendMode.srcIn,
              error: SizedBox(width: size, height: size),
            ),
          ),
          const SizedBox(width: 6),
        ],
        Flexible(child: Text(perk.label, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}
