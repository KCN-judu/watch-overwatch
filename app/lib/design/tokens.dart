import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/strings.dart';

/// Spacing scale. Names say where the space goes, not how big it is.
class Sp {
  static const double touching = 0;
  static const double withinControl = 4;
  static const double withinGroup = 8;
  static const double betweenGroups = 16;
  static const double betweenSections = 24;
  static const double page = 32;
}

class Radii {
  static const double control = 6;
  static const double container = 8;
}

/// Motion durations. Reduced-motion preference collapses all of them to zero.
class Dur {
  // Tiers (docs/ui-design.md §7 and the motion spec): exits are shorter than entries,
  // frequent actions get the short ones, nothing runs past 300 ms.

  /// Hover, press, a check appearing.
  static const fast = Duration(milliseconds: 100);

  /// A control changing state, a tooltip, a value changing in place.
  static const short = Duration(milliseconds: 160);

  /// A page or tab replacing another (entry; the exit runs [fast]).
  static const normal = Duration(milliseconds: 200);

  /// A chart drawing itself, rows arriving: the longest anything moves.
  static const long = Duration(milliseconds: 300);

  /// How long a wait may last before anything says it is loading (not motion: it
  /// is not shortened by the reduced-motion setting).
  static const loadingHint = Duration(seconds: 1);
  static Duration of(BuildContext c, Duration d) =>
      MediaQuery.maybeDisableAnimationsOf(c) ?? false ? Duration.zero : d;
}

enum DensityMode {
  compact('compact', 34, 4),
  standard('standard', 44, 8),
  comfortable('comfortable', 52, 12);

  const DensityMode(this.id, this.rowHeight, this.padV);
  final String id;
  String get label => switch (this) {
    DensityMode.compact => tr.shell.densityCompact,
    DensityMode.standard => tr.shell.densityStandard,
    DensityMode.comfortable => tr.shell.densityComfortable,
  };
  final double rowHeight;
  final double padV;
  static DensityMode parse(String v) => DensityMode.values.firstWhere(
    (d) => d.id == v,
    orElse: () => DensityMode.standard,
  );
}

/// Semantic colour roles. Widgets read these, never raw hex.
///
/// Intent notes (what each must NOT be used for):
///  - accent: interactive focus, selection and primary actions only.
///  - win/loss/draw: match outcome marks only.
///  - ally/enemy: team identity and the strength chart only.
///  - warning/error: status banners and messages only.
///  - success: a step or check that worked (never a match result).
///  - positive/negative: a change for the better / worse (trends, deltas).
///  - ally/enemy: never reused for other pairs; a chart with two series of one
///    thing uses accent (main) and textSecondary (reference, dashed).
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.window,
    required this.nav,
    required this.raised,
    required this.header,
    required this.hover,
    required this.selected,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.accent,
    required this.onAccent,
    required this.win,
    required this.loss,
    required this.draw,
    required this.ally,
    required this.enemy,
    required this.warning,
    required this.error,
    required this.success,
    required this.positive,
    required this.negative,
    required this.grid,
    required this.statDamage,
    required this.statHealing,
    required this.statMitigation,
    required this.barAlpha,
  });

  final Color window,
      nav,
      raised,
      header,
      hover,
      selected,
      border,
      textPrimary,
      textSecondary,
      accent,
      onAccent,
      win,
      loss,
      draw,
      ally,
      enemy,
      warning,
      error,
      success,
      positive,
      negative,
      grid,
      statDamage,
      statHealing,
      statMitigation;

  /// Opacity of a stat colour when used as a bar fill behind its number.
  final double barAlpha;

  static const dark = AppColors(
    window: Color(0xFF12141A),
    nav: Color(0xFF171A21),
    raised: Color(0xFF1D212A),
    header: Color(0xFF232834),
    hover: Color(0x0DFFFFFF),
    selected: Color(0x298E96FF),
    border: Color(0x1FFFFFFF),
    textPrimary: Color(0xFFE8EAEF),
    textSecondary: Color(0xFFA9AFBD),
    accent: Color(0xFF8E96FF),
    onAccent: Color(0xFF11131A),
    win: Color(0xFF5FD19A),
    loss: Color(0xFFFF7A70),
    draw: Color(0xFFA9AFBD),
    ally: Color(0xFF4FB0F0),
    enemy: Color(0xFFF2994A),
    warning: Color(0xFFE9B84A),
    error: Color(0xFFFF7A70),
    success: Color(0xFF5FD19A),
    positive: Color(0xFF5FD19A),
    negative: Color(0xFFFF7A70),
    grid: Color(0x1FFFFFFF),
    statDamage: Color(0xFFF0605A),
    statHealing: Color(0xFF3FC47E),
    statMitigation: Color(0xFF4E9CF0),
    barAlpha: 0.46,
  );

  static const light = AppColors(
    window: Color(0xFFF4F5F7),
    nav: Color(0xFFECEEF2),
    raised: Color(0xFFFFFFFF),
    header: Color(0xFFF0F2F5),
    hover: Color(0x0A000000),
    selected: Color(0x243B42C4),
    border: Color(0x1F000000),
    textPrimary: Color(0xFF1A1D24),
    textSecondary: Color(0xFF525866),
    accent: Color(0xFF3B42C4),
    onAccent: Color(0xFFFFFFFF),
    win: Color(0xFF166A42),
    loss: Color(0xFFAD2B24),
    draw: Color(0xFF525866),
    ally: Color(0xFF11608F),
    enemy: Color(0xFF8A4A07),
    warning: Color(0xFF6F4D00),
    error: Color(0xFFAD2B24),
    success: Color(0xFF166A42),
    positive: Color(0xFF166A42),
    negative: Color(0xFFAD2B24),
    grid: Color(0x1F000000),
    statDamage: Color(0xFFD0453E),
    statHealing: Color(0xFF1E9A5C),
    statMitigation: Color(0xFF2C7BD4),
    barAlpha: 0.32,
  );

  /// Alpha mask that fades a row's picture out toward the right (only the alpha counts).
  static const artFade = [
    Color(0xFF000000),
    Color(0xB3000000),
    Color(0x00000000),
  ];

  /// Opacity of the `raised` scrim over a row's picture, left / middle / right: dense
  /// behind the text, thin where the picture shows.
  static List<double> artScrim(bool light) =>
      light ? const [0.88, 0.50, 0.08] : const [0.94, 0.70, 0.25];

  /// Dims the page behind a dialog or the command palette.
  static const barrier = Color(0x47000000);

  /// Shadow under floating panels (the command palette).
  static const shadow = Color(0x55000000);

  /// Bar fill: the stat colour, softened so the number on top stays readable.
  Color barFill(Color stat) => stat.withValues(alpha: barAlpha);

  Color outcome(String id) => switch (id) {
    'win' => win,
    'loss' => loss,
    'draw' => draw,
    _ => textSecondary,
  };

  /// Every text token paired with every surface it may sit on; checked by a unit test.
  List<(String, Color, Color)> textPairs() {
    final base = [
      ('window', window),
      ('nav', nav),
      ('raised', raised),
      ('header', header),
    ];
    final over = [
      ('raised+hover', Color.alphaBlend(hover, raised)),
      ('raised+selected', Color.alphaBlend(selected, raised)),
    ];
    final text = [
      ('textPrimary', textPrimary),
      ('textSecondary', textSecondary),
      ('accent', accent),
      ('win', win),
      ('loss', loss),
      ('draw', draw),
      ('ally', ally),
      ('enemy', enemy),
      ('warning', warning),
      ('error', error),
      ('success', success),
      ('positive', positive),
      ('negative', negative),
    ];
    return [
      // The number sits on top of its bar, so text must read over every bar tint.
      for (final stat in [statDamage, statHealing, statMitigation])
        (
          'textPrimary on bar',
          textPrimary,
          Color.alphaBlend(barFill(stat), raised),
        ),
      for (final s in [...base, ...over])
        for (final t in text) ('${t.$1} on ${s.$1}', t.$2, s.$2),
    ];
  }

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      window: l(window, other.window),
      nav: l(nav, other.nav),
      raised: l(raised, other.raised),
      header: l(header, other.header),
      hover: l(hover, other.hover),
      selected: l(selected, other.selected),
      border: l(border, other.border),
      textPrimary: l(textPrimary, other.textPrimary),
      textSecondary: l(textSecondary, other.textSecondary),
      accent: l(accent, other.accent),
      onAccent: l(onAccent, other.onAccent),
      win: l(win, other.win),
      loss: l(loss, other.loss),
      draw: l(draw, other.draw),
      ally: l(ally, other.ally),
      enemy: l(enemy, other.enemy),
      warning: l(warning, other.warning),
      error: l(error, other.error),
      success: l(success, other.success),
      positive: l(positive, other.positive),
      negative: l(negative, other.negative),
      grid: l(grid, other.grid),
      statDamage: l(statDamage, other.statDamage),
      statHealing: l(statHealing, other.statHealing),
      statMitigation: l(statMitigation, other.statMitigation),
      barAlpha: barAlpha + (other.barAlpha - barAlpha) * t,
    );
  }
}

/// WCAG relative-luminance contrast of `fg` over an opaque `bg`.
double contrastRatio(Color fg, Color bg) {
  double lum(Color c) {
    double ch(double v) => v <= 0.03928
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
  }

  final a = lum(Color.alphaBlend(fg, bg));
  final b = lum(bg);
  final hi = a > b ? a : b;
  final lo = a > b ? b : a;
  return (hi + 0.05) / (lo + 0.05);
}

extension AppTheme on BuildContext {
  AppColors get c => Theme.of(this).extension<AppColors>()!;
  DensityMode get density => _DensityScope.of(this);
}

class _DensityScope extends InheritedWidget {
  const _DensityScope({required this.density, required super.child});
  final DensityMode density;
  static DensityMode of(BuildContext c) =>
      c.dependOnInheritedWidgetOfExactType<_DensityScope>()?.density ??
      DensityMode.standard;
  @override
  bool updateShouldNotify(_DensityScope old) => old.density != density;
}

class DensityScope extends StatelessWidget {
  const DensityScope({super.key, required this.density, required this.child});
  final DensityMode density;
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      _DensityScope(density: density, child: child);
}

/// Four sizes, two weights. Chinese body text uses a 1.5 line height; table
/// cells use fixed row heights so their line height only needs to avoid clipping.
///
/// One primary face (Microsoft YaHei UI) covers Chinese, Latin and digits, so every
/// line has the same ascent and descent. Mixing a Latin face with a CJK fallback
/// makes lines containing digits sit at a different height from lines containing only
/// Chinese, which shows up as text and icons that do not line up across cells.
/// `leadingDistribution: even` splits the extra line height evenly above and below,
/// so a glyph is centred in its line box rather than pushed to the bottom.
class Ty {
  static const family = 'Microsoft YaHei UI';
  static const fallback = ['Microsoft YaHei', 'Segoe UI'];
  static const _tab = [FontFeature.tabularFigures()];
  static const _even = TextLeadingDistribution.even;
  static const meta = TextStyle(
    fontSize: 12,
    height: 1.5,
    fontWeight: FontWeight.w400,
    leadingDistribution: _even,
  );
  static const body = TextStyle(
    fontSize: 13,
    height: 1.5,
    fontWeight: FontWeight.w400,
    leadingDistribution: _even,
  );
  static const bodyStrong = TextStyle(
    fontSize: 13,
    height: 1.5,
    fontWeight: FontWeight.w600,
    leadingDistribution: _even,
  );
  static const section = TextStyle(
    fontSize: 15,
    height: 1.5,
    fontWeight: FontWeight.w600,
    leadingDistribution: _even,
  );
  static const page = TextStyle(
    fontSize: 20,
    height: 1.4,
    fontWeight: FontWeight.w600,
    leadingDistribution: _even,
  );
  static const cell = TextStyle(
    fontSize: 13,
    height: 1.3,
    fontWeight: FontWeight.w400,
    leadingDistribution: _even,
  );

  /// Hero name on a match row: one step above body text so it reads at a glance.
  static const title = TextStyle(
    fontSize: 16,
    height: 1.3,
    fontWeight: FontWeight.w600,
    leadingDistribution: _even,
  );

  /// The overview's headline figures: the page's largest type, for a handful of numbers
  /// only (docs/ui-design.md §7, the reference's “数字是主角”).
  static const display = TextStyle(
    fontSize: 40,
    height: 1.1,
    fontWeight: FontWeight.w600,
    leadingDistribution: _even,
  );

  /// Large figures (scores) in list rows.
  static const figure = TextStyle(
    fontSize: 24,
    height: 1.2,
    fontWeight: FontWeight.w600,
    leadingDistribution: _even,
  );
  static TextStyle num(TextStyle s) => s.copyWith(fontFeatures: _tab);
}

ThemeData buildTheme(Brightness b) {
  final c = b == Brightness.dark ? AppColors.dark : AppColors.light;
  final scheme = ColorScheme(
    brightness: b,
    primary: c.accent,
    onPrimary: c.onAccent,
    secondary: c.accent,
    onSecondary: c.onAccent,
    error: c.error,
    onError: c.window,
    surface: c.raised,
    onSurface: c.textPrimary,
    onSurfaceVariant: c.textSecondary,
    outline: c.border,
    outlineVariant: c.border,
    surfaceContainerHighest: c.header,
    surfaceContainerHigh: c.raised,
    surfaceContainer: c.raised,
    surfaceContainerLow: c.nav,
    surfaceContainerLowest: c.window,
  );
  TextStyle f(TextStyle s) => s.copyWith(
    fontFamily: Ty.family,
    fontFamilyFallback: Ty.fallback,
    color: c.textPrimary,
    letterSpacing: 0,
  );
  final text = TextTheme(
    bodyLarge: f(Ty.body),
    bodyMedium: f(Ty.body),
    bodySmall: f(Ty.meta).copyWith(color: c.textSecondary),
    labelLarge: f(Ty.bodyStrong),
    labelMedium: f(Ty.meta),
    labelSmall: f(Ty.meta),
    titleLarge: f(Ty.page),
    titleMedium: f(Ty.section),
    titleSmall: f(Ty.bodyStrong),
    headlineSmall: f(Ty.page),
  );
  return ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.window,
    canvasColor: c.window,
    fontFamily: Ty.family,
    fontFamilyFallback: Ty.fallback,
    textTheme: text,
    extensions: [c],
    dividerColor: c.border,
    focusColor: c.accent.withValues(alpha: 0.35),
    hoverColor: c.hover,
    splashFactory: NoSplash.splashFactory,
    visualDensity: VisualDensity.compact,
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 500),
      textStyle: f(Ty.meta).copyWith(color: c.textPrimary),
      decoration: BoxDecoration(
        color: c.header,
        borderRadius: BorderRadius.circular(Radii.control),
        border: Border.all(color: c.border),
      ),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(c.raised),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        side: WidgetStatePropertyAll(BorderSide(color: c.border)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 4),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.container),
          ),
        ),
      ),
    ),
    menuButtonTheme: MenuButtonThemeData(
      style: ButtonStyle(
        textStyle: WidgetStatePropertyAll(f(Ty.body)),
        foregroundColor: WidgetStatePropertyAll(c.textPrimary),
        overlayColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.focused)
              ? c.selected
              : s.contains(WidgetState.hovered)
              ? c.hover
              : null,
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.raised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.container),
        side: BorderSide(color: c.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: c.window,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      hintStyle: f(Ty.body).copyWith(color: c.textSecondary),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.control),
        borderSide: BorderSide(color: c.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.control),
        borderSide: BorderSide(color: c.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.control),
        borderSide: BorderSide(color: c.accent, width: 2),
      ),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: c.accent,
      selectionColor: c.accent.withValues(alpha: 0.35),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(
        c.textSecondary.withValues(alpha: 0.45),
      ),
      thickness: const WidgetStatePropertyAll(8),
      radius: const Radius.circular(4),
      thumbVisibility: const WidgetStatePropertyAll(true),
    ),
  );
}
