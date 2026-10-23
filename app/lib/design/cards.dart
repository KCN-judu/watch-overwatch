import 'package:flutter/material.dart';

import '../core/metric_doc.dart';
import '../l10n/strings.dart';
import 'icons.dart';
import 'net_pic.dart';
import 'tokens.dart';
import 'widgets.dart' show FigureText, ProgressLine;

/// The one section heading: a short bar, the title, an optional info tip and an
/// optional control at the right end. The bar is the accent colour unless the section
/// belongs to something with its own colour (a hero, a stat). Put
/// [SectionHeader.below] between it and the section body.
class SectionHeader extends StatelessWidget {
  const SectionHeader(
    this.text, {
    super.key,
    this.accent,
    this.info,
    this.infoDoc,
    this.trailing,
  });
  final String text;
  final Color? accent;
  final String? info;

  /// The metrics-page section [info] is about, when it explains a figure.
  final MetricDoc? infoDoc;
  final Widget? trailing;

  /// Space between a heading and its section; sections are [Sp.betweenSections] apart.
  static const below = Sp.withinGroup;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 4, height: 20, color: accent ?? context.c.accent),
        const SizedBox(width: Sp.withinGroup),
        Flexible(
          child: Semantics(header: true, child: Text(text, style: Ty.section)),
        ),
        if (info != null) InfoTip(info!, doc: infoDoc),
        if (trailing != null) ...[const Spacer(), trailing!],
      ],
    );
  }
}

/// The one bordered container for a block of content: the raised surface, a 1px
/// border, square corners (as cards have). Padding comes in three sizes.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = PanelPadding.normal,
    this.width,
  });
  final Widget child;
  final PanelPadding padding;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      width: width,
      padding: padding.insets,
      decoration: BoxDecoration(
        color: c.raised,
        border: Border.all(color: c.border),
      ),
      child: child,
    );
  }
}

enum PanelPadding {
  /// Charts: tight at the sides so the plot gets the width, room above for labels.
  chart(
    EdgeInsets.fromLTRB(
      Sp.withinGroup,
      Sp.betweenGroups,
      Sp.withinGroup,
      Sp.withinGroup,
    ),
  ),
  normal(EdgeInsets.all(Sp.betweenGroups)),

  /// A panel that is the whole content of the page (an intro, a progress report).
  spacious(EdgeInsets.all(Sp.betweenSections));

  const PanelPadding(this.insets);
  final EdgeInsets insets;
}

/// A titled block that folds away: the title row is a button with a chevron, and the
/// content is not built while it is folded. Starts open.
class FoldSection extends StatefulWidget {
  const FoldSection({
    super.key,
    required this.title,
    required this.accent,
    required this.child,
    this.open = true,
  });
  final String title;
  final Color accent;
  final Widget child;
  final bool open;

  @override
  State<FoldSection> createState() => _FoldSectionState();
}

class _FoldSectionState extends State<FoldSection> {
  late bool _open = widget.open;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          expanded: _open,
          label: widget.title,
          excludeSemantics: true,
          child: InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Sp.withinControl),
              child: Row(
                children: [
                  Icon(
                    _open ? Icons.expand_more : Icons.chevron_right,
                    size: 20,
                    color: c.textSecondary,
                  ),
                  const SizedBox(width: Sp.withinControl),
                  Text(
                    widget.title,
                    style: Ty.bodyStrong.copyWith(
                      color: legibleOn(widget.accent, context.c.window),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_open) widget.child,
      ],
    );
  }
}

/// Cards in equal columns (as many as fit, up to four), every row the same height.
class CardGrid extends StatelessWidget {
  const CardGrid(
    this.children, {
    super.key,
    this.minWidth = 320,
    this.height = 112,
  });
  final List<Widget> children;
  final double minWidth, height;
  static const _gap = 10.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final cols = ((box.maxWidth + _gap) / (minWidth + _gap)).floor().clamp(
          1,
          4,
        );
        final rows = <Widget>[];
        for (var i = 0; i < children.length; i += cols) {
          if (i > 0) rows.add(const SizedBox(height: _gap));
          rows.add(
            SizedBox(
              height: height,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var j = 0; j < cols; j++) ...[
                    if (j > 0) const SizedBox(width: _gap),
                    Expanded(
                      child: i + j < children.length
                          ? children[i + j]
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          );
        }
        return Column(children: rows);
      },
    );
  }
}

/// The surface every card sits on: a raised, bordered rectangle with an accent bar down
/// the left edge. Square corners everywhere, so cards on different pages look the same.
class CardSurface extends StatelessWidget {
  const CardSurface({super.key, required this.accent, required this.child});
  final Color accent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.raised,
        border: Border.all(color: c.border),
      ),
      child: ClipRect(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: accentBar, color: accent),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(Sp.betweenGroups),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A named thing with an icon and a few lines of text: an ability, a perk, a piece of
/// equipment. The icon is a bundled asset or an image address; either may be missing.
class InfoCard extends StatelessWidget {
  const InfoCard({
    super.key,
    required this.name,
    required this.accent,
    this.description = '',
    this.tag,
    this.asset,
    this.iconUrl,
    this.glyph,
    this.tintIcon = true,
  });
  final String name;
  final String description;
  final String? tag;
  final String? asset;
  final String? iconUrl;

  /// A built-in glyph, for things that have no picture of their own.
  final IconData? glyph;

  /// Draw [iconUrl] in the text colour (white silhouettes such as perks); off for
  /// pictures in their own colours (Stadium powers and items).
  final bool tintIcon;

  final Color accent;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final text = description.replaceAll('%%', '%');
    final Widget icon = SizedBox(
      width: 48,
      height: 48,
      child: asset != null
          ? Image.asset(
              asset!,
              fit: BoxFit.contain,
              color: c.textPrimary,
              colorBlendMode: BlendMode.srcIn,
              filterQuality: FilterQuality.medium,
              excludeFromSemantics: true,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            )
          : iconUrl != null
          ? ExcludeSemantics(
              child: NetPic(
                iconUrl!,
                width: 48,
                height: 48,
                color: tintIcon ? c.textPrimary : null,
                blend: tintIcon ? BlendMode.srcIn : null,
                error: const SizedBox(width: 48, height: 48),
              ),
            )
          : glyph != null
          ? Icon(glyph, size: 40, color: c.textPrimary)
          : null,
    );
    return CardSurface(
      accent: accent,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          icon,
          const SizedBox(width: Sp.betweenItems),
          Expanded(
            child: Column(
              // Only as tall as its text, so the Row centres it against the icon.
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        style: Ty.bodyStrong,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (tag != null && tag!.isNotEmpty) ...[
                      const SizedBox(width: Sp.withinGroup),
                      Text(
                        tag!,
                        style: Ty.meta.copyWith(color: c.textSecondary),
                      ),
                    ],
                  ],
                ),
                if (text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: Sp.hairline),
                    child: Tooltip(
                      message: text,
                      waitDuration: const Duration(milliseconds: 400),
                      child: Text(
                        text,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Ty.body.copyWith(color: c.textSecondary),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A hero perk: its name, what it does, and its icon. `level` (1 or 2) adds the tier as the
/// tag; the hero page leaves it out because its rows are already titled by tier. `info` is
/// the game's own entry for the perk, when there is one; `fallbackIconUrl` stands in for
/// its picture when there is not.
class PerkCard extends StatelessWidget {
  const PerkCard({
    super.key,
    required this.name,
    required this.accent,
    this.description = '',
    this.asset,
    this.fallbackIconUrl,
    this.level,
  });
  final String name;
  final String description;
  final String? asset;
  final String? fallbackIconUrl;
  final int? level;
  final Color accent;

  @override
  Widget build(BuildContext context) => InfoCard(
    name: name,
    tag: switch (level) {
      1 => tr.shell.perkMinor,
      2 => tr.shell.perkMajor,
      _ => null,
    },
    description: description,
    asset: asset,
    iconUrl: asset == null ? fallbackIconUrl : null,
    accent: accent,
  );
}

/// One figure with its label, an optional line under it and an optional bar showing a
/// share (0 to 1) of something. A missing value shows the dash, never 0.
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.accent,
    this.caption,
    this.share,
    this.tooltip,
  });
  final String label;
  final String value;
  final Color accent;
  final String? caption;

  /// Fraction of the bar to fill; no bar when null.
  final double? share;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final card = CardSurface(
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: Ty.meta.copyWith(color: c.textSecondary)),
          const SizedBox(height: Sp.hairline),
          FigureText(value, style: Ty.figure),
          if (share != null) ...[
            const SizedBox(height: Sp.iconGap),
            ProgressLine(value: share!.clamp(0.0, 1.0), color: accent),
          ],
          if (caption != null) ...[
            const SizedBox(height: Sp.withinControl),
            Text(
              caption!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Ty.meta.copyWith(color: c.textSecondary),
            ),
          ],
        ],
      ),
    );
    return Semantics(
      container: true,
      label: '$label $value${caption == null ? '' : '，$caption'}',
      excludeSemantics: true,
      child: tooltip == null ? card : Tooltip(message: tooltip!, child: card),
    );
  }
}
