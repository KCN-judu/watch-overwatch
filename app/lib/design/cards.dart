import 'package:flutter/material.dart';

import 'icons.dart';
import 'net_pic.dart';
import 'tokens.dart';

/// Section heading with an accent colour as a bar, optionally followed by an info tip.
class AccentTitle extends StatelessWidget {
  const AccentTitle(this.text, {super.key, required this.accent, this.info});
  final String text;
  final Color accent;
  final String? info;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 4, height: 20, color: accent),
        const SizedBox(width: 10),
        Semantics(header: true, child: Text(text, style: Ty.section)),
        if (info != null) InfoTip(info!),
      ],
    );
  }
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
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    _open ? Icons.expand_more : Icons.chevron_right,
                    size: 20,
                    color: c.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    widget.title,
                    style: Ty.bodyStrong.copyWith(color: widget.accent),
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
            Container(width: 3, color: accent),
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
  });
  final String name;
  final String description;
  final String? tag;
  final String? asset;
  final String? iconUrl;

  /// A built-in glyph, for things that have no picture of their own.
  final IconData? glyph;

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
                color: c.textPrimary,
                blend: BlendMode.srcIn,
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
          const SizedBox(width: 12),
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
                      const SizedBox(width: 8),
                      Text(
                        tag!,
                        style: Ty.meta.copyWith(color: c.textSecondary),
                      ),
                    ],
                  ],
                ),
                if (text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
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
      1 => '一级威能',
      2 => '二级威能',
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
          const SizedBox(height: 2),
          Text(value, style: Ty.num(Ty.figure)),
          if (share != null) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: share!.clamp(0.0, 1.0),
                minHeight: 4,
                color: accent,
                backgroundColor: c.border,
              ),
            ),
          ],
          if (caption != null) ...[
            const SizedBox(height: 4),
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
