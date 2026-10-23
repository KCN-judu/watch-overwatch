import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../core/support.dart';
import '../l10n/strings.dart';
import 'tokens.dart';

/// Release notes (the CHANGELOG section of a version, in Markdown) set for reading:
/// each section (新增 / 修复 / 变更) under a heading with its colour bar and count,
/// each entry led by its name in bold with the issue beside it as a tag and the
/// description under it in the secondary colour, sub-points indented. Bold, code and
/// links keep their meaning inline; links open in the browser. The text can be selected.
class ReleaseNotes extends StatefulWidget {
  const ReleaseNotes(this.markdown, {super.key});
  final String markdown;

  @override
  State<ReleaseNotes> createState() => _ReleaseNotesState();
}

/// One parsed block of the notes.
sealed class _Block {}

class _Heading extends _Block {
  _Heading(this.text);
  final String text;

  /// Entries under it, counted as they are read.
  int count = 0;
}

class _Entry extends _Block {
  _Entry(this.lead, this.issues, this.body, this.subs);
  final String? lead;
  final List<String> issues;
  final String body;
  final List<String> subs;
}

class _Paragraph extends _Block {
  _Paragraph(this.text);
  final String text;
}

class _ReleaseNotesState extends State<ReleaseNotes> {
  final _taps = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final t in _taps) {
      t.dispose();
    }
    super.dispose();
  }

  static final _heading = RegExp(r'^(#{1,6})\s+(.*)$');
  static final _item = RegExp(r'^(\s*)[-*]\s+(.*)$');

  /// `**名字**（issue #40）：说明` → the name, the issues and the rest.
  static final _lead = RegExp(
    r'^\*\*(.+?)\*\*\s*(?:[（(]([^）)]*#\d+[^）)]*)[）)])?\s*[：:]?\s*',
  );

  static List<_Block> parse(String markdown) {
    final out = <_Block>[];
    _Entry? entry;
    _Heading? heading;
    final lines = markdown.replaceAll('\r', '').split('\n');
    for (final (i, raw) in lines.indexed) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) continue;
      final h = _heading.firstMatch(line);
      if (h != null) {
        // The `# Watch Overwatch 1.3.0` title repeats the dialog's own heading.
        if (h[1]!.length == 1 &&
            i == lines.indexWhere((l) => l.trim().isNotEmpty)) {
          continue;
        }
        heading = _Heading(h[2]!.trim());
        out.add(heading);
        entry = null;
        continue;
      }
      final it = _item.firstMatch(line);
      if (it != null) {
        final text = it[2]!.trim();
        if (it[1]!.length >= 2 && entry != null) {
          entry.subs.add(text);
          continue;
        }
        final lead = _lead.firstMatch(text);
        final issues = [
          for (final m in RegExp(r'#\d+').allMatches(lead?[2] ?? '')) m[0]!,
        ];
        entry = _Entry(
          lead?[1],
          issues,
          lead == null ? text : text.substring(lead.end),
          [],
        );
        out.add(entry);
        heading?.count++;
        continue;
      }
      // A continuation of the entry above (a wrapped line) or a paragraph.
      if (entry != null && raw.startsWith('  ')) {
        if (entry.subs.isEmpty) {
          final joined = '${entry.body} ${line.trim()}';
          out[out.length - 1] = entry = _Entry(
            entry.lead,
            entry.issues,
            joined,
            entry.subs,
          );
        } else {
          entry.subs[entry.subs.length - 1] += ' ${line.trim()}';
        }
        continue;
      }
      entry = null;
      out.add(_Paragraph(line.trim()));
    }
    return out;
  }

  static final _inline = RegExp(
    r'\*\*(.+?)\*\*|`([^`]+)`|\[([^\]]+)\]\(([^)]+)\)|<(https?://[^>]+)>|(#\d+)',
  );

  /// Inline Markdown as spans: bold, code, links (clickable), issue numbers muted.
  List<InlineSpan> _spans(String text, TextStyle base) {
    final c = context.c;
    final spans = <InlineSpan>[];
    var at = 0;
    TextSpan link(String label, String url) {
      final tap = TapGestureRecognizer()..onTap = () => openUrl(url);
      _taps.add(tap);
      return TextSpan(
        text: label,
        style: base.copyWith(
          color: c.accent,
          decoration: TextDecoration.underline,
          decorationColor: c.accent.withValues(alpha: Alpha.muted),
        ),
        recognizer: tap,
        mouseCursor: SystemMouseCursors.click,
      );
    }

    for (final m in _inline.allMatches(text)) {
      if (m.start > at) {
        spans.add(TextSpan(text: text.substring(at, m.start), style: base));
      }
      if (m[1] != null) {
        spans.add(
          TextSpan(
            text: m[1],
            style: base.copyWith(
              fontWeight: FontWeight.w600,
              color: c.textPrimary,
            ),
          ),
        );
      } else if (m[2] != null) {
        spans.add(
          TextSpan(
            text: m[2],
            style: Ty.code.copyWith(
              color: c.textPrimary,
              backgroundColor: c.hover,
            ),
          ),
        );
      } else if (m[3] != null) {
        spans.add(link(m[3]!, m[4]!));
      } else if (m[5] != null) {
        spans.add(link(m[5]!, m[5]!));
      } else {
        spans.add(
          TextSpan(
            text: m[6],
            style: Ty.num(base).copyWith(color: c.textSecondary),
          ),
        );
      }
      at = m.end;
    }
    if (at < text.length) {
      spans.add(TextSpan(text: text.substring(at), style: base));
    }
    return spans;
  }

  Color _sectionColor(String title) {
    final c = context.c;
    if (title.contains(tr.update.sectionAdded)) return c.positive;
    if (title.contains(tr.update.sectionFixed)) return c.warning;
    if (tr.update.sectionChanged.any(title.contains)) return c.accent;
    return c.textSecondary;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    for (final t in _taps) {
      t.dispose();
    }
    _taps.clear();
    final blocks = parse(widget.markdown);
    if (blocks.isEmpty) {
      return Text(
        tr.update.noNotes,
        style: Ty.body.copyWith(color: c.textSecondary),
      );
    }
    final secondary = Ty.prose.copyWith(color: c.textSecondary);
    final children = <Widget>[];
    for (final (i, b) in blocks.indexed) {
      switch (b) {
        case _Heading(:final text, :final count):
          children.add(
            Padding(
              padding: EdgeInsets.only(
                top: i == 0 ? 0 : Sp.betweenSections,
                bottom: Sp.betweenItems,
              ),
              child: Row(
                children: [
                  Container(
                    width: accentBar,
                    height: 14,
                    color: _sectionColor(text),
                  ),
                  const SizedBox(width: Sp.withinGroup),
                  Text(text, style: Ty.section),
                  if (count > 0) ...[
                    const SizedBox(width: Sp.withinGroup),
                    Text(
                      tr.update.entries(count),
                      style: Ty.num(Ty.meta).copyWith(color: c.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
          );
        case _Entry(:final lead, :final issues, :final body, :final subs):
          children.add(
            Padding(
              padding: const EdgeInsets.only(
                left: Sp.betweenItems,
                bottom: Sp.betweenGroups,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (lead != null)
                    Wrap(
                      spacing: Sp.withinGroup,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text.rich(
                          TextSpan(children: _spans(lead, Ty.bodyStrong)),
                        ),
                        for (final n in issues) _IssueTag(n),
                      ],
                    ),
                  if (body.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.only(
                        top: lead == null ? 0 : Sp.hairline,
                      ),
                      child: lead == null
                          ? _Bulleted(
                              child: Text.rich(
                                TextSpan(
                                  children: _spans(
                                    body,
                                    Ty.prose.copyWith(color: c.textPrimary),
                                  ),
                                ),
                              ),
                            )
                          : Text.rich(
                              TextSpan(children: _spans(body, secondary)),
                            ),
                    ),
                  for (final s in subs)
                    Padding(
                      padding: const EdgeInsets.only(
                        left: Sp.betweenGroups,
                        top: Sp.withinControl,
                      ),
                      child: _Bulleted(
                        dash: true,
                        child: Text.rich(
                          TextSpan(children: _spans(s, secondary)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        case _Paragraph(:final text):
          children.add(
            Padding(
              padding: const EdgeInsets.only(bottom: Sp.betweenItems),
              child: Text.rich(
                TextSpan(
                  children: _spans(
                    text,
                    Ty.prose.copyWith(color: c.textPrimary),
                  ),
                ),
              ),
            ),
          );
      }
    }
    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

/// A small outlined tag for an issue number beside an entry's name.
class _IssueTag extends StatelessWidget {
  const _IssueTag(this.number);
  final String number;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.iconGap),
      decoration: BoxDecoration(
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(Sp.withinControl),
      ),
      child: Text(
        number,
        style: Ty.num(Ty.micro).copyWith(color: c.textSecondary),
      ),
    );
  }
}

/// A list item's marker (a dot, or a dash for a sub-point) set on the first line.
class _Bulleted extends StatelessWidget {
  const _Bulleted({required this.child, this.dash = false});
  final Widget child;
  final bool dash;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: Sp.betweenItems,
          height: 22,
          child: Center(
            child: Container(
              width: dash ? Sp.iconGap : Sp.withinControl,
              height: dash ? 1 : Sp.withinControl,
              decoration: BoxDecoration(
                color: c.textSecondary,
                shape: dash ? BoxShape.rectangle : BoxShape.circle,
              ),
            ),
          ),
        ),
        const SizedBox(width: Sp.iconGap),
        Expanded(child: child),
      ],
    );
  }
}
