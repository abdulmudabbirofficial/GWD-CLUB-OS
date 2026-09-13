import 'package:flutter/material.dart';
import 'apple_motion.dart';

/// ---------------------------------------------------------------------------
/// GWD CLUB OS — DESIGN SYSTEM
///
/// A neutral-first, Apple-grade surface language. The rule that keeps the UI
/// calm: the canvas and cards stay quiet, and crimson is spent only on the one
/// thing on screen that actually needs the user's attention.
/// ---------------------------------------------------------------------------

class GwdColors {
  const GwdColors._();

  // --- Light: paper & ink -------------------------------------------------
  static const canvas = Color(0xFFF6F6F8);
  static const canvasLight = canvas; // legacy alias
  static const surface = Color(0xFFFFFFFF);
  static const surfaceWhite = surface; // legacy alias
  static const cardWhite = surface; // legacy alias
  static const canvasWhite = surface; // legacy alias
  static const surfaceSunken = Color(0xFFF0F0F3);
  static const hairline = Color(0xFFE6E6EA);
  static const hairlineSoft = Color(0xFFF0F0F3);
  static const line = hairline; // legacy alias
  static const lineSubtle = hairlineSoft; // legacy alias

  static const ink = Color(0xFF0B0B0F);
  static const inkSecondary = Color(0xFF5C5C66);
  static const inkTertiary = Color(0xFF9A9AA4);
  static const textPrimary = ink; // legacy alias
  static const textSecondary = inkSecondary; // legacy alias
  static const textMuted = inkTertiary; // legacy alias

  // --- Dark: obsidian -----------------------------------------------------
  static const canvasDark = Color(0xFF08080A);
  static const surfaceDark = Color(0xFF141417);
  static const surfaceDarkRaised = Color(0xFF1C1C20);
  static const cardDark = surfaceDark; // legacy alias
  static const hairlineDark = Color(0xFF2A2A30);

  static const obsidian = Color(0xFF0B0B0F);
  static const jetBlack = Color(0xFF000000);
  static const charcoal = Color(0xFF18181B);

  // --- Brand accent (spend sparingly) -------------------------------------
  static const primaryRed = Color(0xFFDC2626);
  static const rubyDark = Color(0xFF9F1239);
  static const rubyLight = Color(0xFFFFE9E9);
  static const accentCoral = Color(0xFFEF4444);
  static const redGlow = Color(0x1FDC2626);
  static const borderRed = Color(0x33DC2626);

  // --- Semantic -----------------------------------------------------------
  static const success = Color(0xFF16A34A);
  static const successSoft = Color(0xFFE7F6EC);
  static const warning = Color(0xFFD97706);
  static const warningSoft = Color(0xFFFDF1E1);
  static const critical = Color(0xFFDC2626);
  static const criticalSoft = Color(0xFFFFE9E9);
  static const info = Color(0xFF2563EB);
  static const infoSoft = Color(0xFFE8EFFE);

  // Legacy semantic aliases still referenced by feature pages.
  static const emerald = success;
  static const amber = warning;
  static const coral = critical;
  static const primaryIndigo = primaryRed;
  static const electricViolet = rubyDark;
  static const purple = primaryRed;
  static const neonPink = accentCoral;
  static const neonCyan = ink;
  static const glassSurface = Color(0xE6FFFFFF);
  static const glassBorder = hairline;
  static const glassBorderActive = primaryRed;

  /// Resolves a token to its light or dark counterpart.
  static Color surfaceOf(BuildContext context) =>
      _isDark(context) ? surfaceDark : surface;

  static Color raisedOf(BuildContext context) =>
      _isDark(context) ? surfaceDarkRaised : surface;

  static Color canvasOf(BuildContext context) =>
      _isDark(context) ? canvasDark : canvas;

  static Color sunkenOf(BuildContext context) =>
      _isDark(context) ? const Color(0xFF0F0F12) : surfaceSunken;

  static Color hairlineOf(BuildContext context) =>
      _isDark(context) ? hairlineDark : hairline;

  static Color inkOf(BuildContext context) =>
      _isDark(context) ? const Color(0xFFF5F5F7) : ink;

  static Color inkSecondaryOf(BuildContext context) =>
      _isDark(context) ? const Color(0xFF9E9EA8) : inkSecondary;

  static Color inkTertiaryOf(BuildContext context) =>
      _isDark(context) ? const Color(0xFF6B6B75) : inkTertiary;

  static bool _isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;
}

/// 4pt spacing scale. Named steps keep the vertical rhythm consistent.
class GwdSpace {
  const GwdSpace._();
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 28.0;
  static const xxxl = 40.0;

  /// Horizontal page gutter, widened on larger canvases.
  static double gutter(double width) {
    if (width >= 1200) return 32;
    if (width >= 840) return 28;
    if (width >= 480) return 22;
    return 18;
  }
}

class GwdRadius {
  const GwdRadius._();
  static const sm = 10.0;
  static const md = 14.0;
  static const lg = 18.0;
  static const xl = 24.0;
  static const xxl = 30.0;
  static const pill = 999.0;
}

/// Type ramp modelled on the SF Pro hierarchy: few sizes, decisive weights,
/// negative tracking on the large end so headings read tight and modern.
class GwdType {
  const GwdType._();

  static const largeTitle = TextStyle(
      fontSize: 32,
      height: 1.12,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.9);
  static const title1 = TextStyle(
      fontSize: 26,
      height: 1.15,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.7);
  static const title2 = TextStyle(
      fontSize: 21,
      height: 1.2,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5);
  static const title3 = TextStyle(
      fontSize: 17,
      height: 1.25,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.35);
  static const headline = TextStyle(
      fontSize: 15,
      height: 1.3,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2);
  static const body = TextStyle(
      fontSize: 14.5,
      height: 1.42,
      fontWeight: FontWeight.w400,
      letterSpacing: -0.1);
  static const callout = TextStyle(
      fontSize: 13.5,
      height: 1.35,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.1);
  static const subhead =
      TextStyle(fontSize: 12.5, height: 1.35, fontWeight: FontWeight.w500);
  static const footnote =
      TextStyle(fontSize: 11.5, height: 1.3, fontWeight: FontWeight.w500);
  static const caption =
      TextStyle(fontSize: 11, height: 1.25, fontWeight: FontWeight.w600);

  /// Section eyebrow. Uppercase, wide tracking, never larger than 10.5pt.
  static const eyebrow = TextStyle(
      fontSize: 10.5,
      height: 1.2,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.9);

  /// Tabular figures so animated counters do not jitter while they roll.
  static const numeric = TextStyle(
    fontFeatures: [FontFeature.tabularFigures()],
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
  );
}

/// Soft, physically plausible shadows: a tight contact shadow plus a wide
/// ambient one. Coloured glows are reserved for genuinely live elements.
class GwdShadow {
  const GwdShadow._();

  static List<BoxShadow> resting(bool isDark) => [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.40 : 0.035),
          blurRadius: 2,
          offset: const Offset(0, 1),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.045),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ];

  static List<BoxShadow> lifted(bool isDark) => [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.50 : 0.06),
          blurRadius: 4,
          offset: const Offset(0, 2),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.40 : 0.08),
          blurRadius: 30,
          offset: const Offset(0, 14),
        ),
      ];

  /// Reserved for elements that are genuinely live (active alert, primary CTA).
  static List<BoxShadow> accent(Color color) => [
        BoxShadow(
          color: color.withValues(alpha: 0.26),
          blurRadius: 22,
          offset: const Offset(0, 8),
        ),
      ];
}

class GwdTheme {
  const GwdTheme._();

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final ink = isDark ? const Color(0xFFF5F5F7) : GwdColors.ink;
    final secondary = isDark ? const Color(0xFF9E9EA8) : GwdColors.inkSecondary;

    final textTheme = TextTheme(
      displayLarge: GwdType.largeTitle.copyWith(color: ink),
      headlineLarge: GwdType.title1.copyWith(color: ink),
      headlineMedium: GwdType.title2.copyWith(color: ink),
      headlineSmall: GwdType.title3.copyWith(color: ink),
      titleMedium: GwdType.headline.copyWith(color: ink),
      bodyLarge: GwdType.body.copyWith(color: ink),
      bodyMedium: GwdType.callout.copyWith(color: secondary),
      bodySmall: GwdType.footnote.copyWith(color: secondary),
      labelLarge: GwdType.headline.copyWith(color: ink),
      labelMedium: GwdType.caption.copyWith(color: secondary),
      labelSmall: GwdType.eyebrow.copyWith(color: secondary),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: isDark ? GwdColors.canvasDark : GwdColors.canvas,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: GwdColors.primaryRed,
        onPrimary: Colors.white,
        secondary: isDark ? Colors.white : GwdColors.ink,
        onSecondary: isDark ? GwdColors.ink : Colors.white,
        surface: isDark ? GwdColors.surfaceDark : GwdColors.surface,
        onSurface: ink,
        surfaceContainerHighest:
            isDark ? GwdColors.surfaceDarkRaised : GwdColors.surfaceSunken,
        error: GwdColors.critical,
        onError: Colors.white,
        outline: isDark ? GwdColors.hairlineDark : GwdColors.hairline,
      ),
      textTheme: textTheme,
      cardColor: isDark ? GwdColors.surfaceDark : GwdColors.surface,
      dividerColor: isDark ? GwdColors.hairlineDark : GwdColors.hairline,
      dividerTheme: DividerThemeData(
        color: isDark ? GwdColors.hairlineDark : GwdColors.hairline,
        thickness: 1,
        space: 1,
      ),
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      splashColor: Colors.transparent,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: ink,
        titleTextStyle: GwdType.title3.copyWith(color: ink),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: Colors.transparent,
        elevation: 0,
        modalBarrierColor: Colors.black.withValues(alpha: isDark ? 0.62 : 0.34),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? GwdColors.surfaceDarkRaised : GwdColors.ink,
        contentTextStyle: GwdType.callout.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GwdRadius.md),
        ),
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
        elevation: 6,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? GwdColors.surfaceDarkRaised : GwdColors.ink,
          borderRadius: BorderRadius.circular(GwdRadius.sm),
        ),
        textStyle: GwdType.footnote.copyWith(color: Colors.white),
        waitDuration: const Duration(milliseconds: 500),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: GwdColors.primaryRed,
        linearMinHeight: 6,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FluidPageTransitionsBuilder(),
          TargetPlatform.iOS: FluidPageTransitionsBuilder(),
          TargetPlatform.macOS: FluidPageTransitionsBuilder(),
          TargetPlatform.windows: FluidPageTransitionsBuilder(),
          TargetPlatform.linux: FluidPageTransitionsBuilder(),
        },
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// SURFACES
/// ---------------------------------------------------------------------------

enum SurfaceEmphasis { quiet, raised, live }

/// The single card primitive for the whole app. Quiet by default; it only picks
/// up an accent border and glow when [emphasis] says the content is live.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(GwdSpace.lg),
    this.borderRadius = GwdRadius.xl,
    this.borderColor,
    this.backgroundColor,
    this.shadowColor,
    this.onTap,
    this.emphasis = SurfaceEmphasis.quiet,
    this.accent,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final Color? borderColor;
  final Color? backgroundColor;
  final Color? shadowColor;
  final VoidCallback? onTap;
  final SurfaceEmphasis emphasis;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = accent ?? GwdColors.primaryRed;
    final bg =
        backgroundColor ?? (isDark ? GwdColors.surfaceDark : GwdColors.surface);

    final border = borderColor ??
        switch (emphasis) {
          SurfaceEmphasis.quiet =>
            isDark ? GwdColors.hairlineDark : GwdColors.hairline,
          SurfaceEmphasis.raised =>
            isDark ? GwdColors.hairlineDark : GwdColors.hairline,
          SurfaceEmphasis.live => accentColor.withValues(alpha: 0.34),
        };

    final shadows = switch (emphasis) {
      SurfaceEmphasis.quiet => GwdShadow.resting(isDark),
      SurfaceEmphasis.raised => GwdShadow.lifted(isDark),
      SurfaceEmphasis.live => [
          ...GwdShadow.resting(isDark),
          ...GwdShadow.accent(accentColor),
        ],
    };

    final content = DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: border, width: 1),
        boxShadow: shadowColor != null
            ? [
                BoxShadow(
                    color: shadowColor!,
                    blurRadius: 18,
                    offset: const Offset(0, 6))
              ]
            : shadows,
      ),
      child: Padding(padding: padding, child: child),
    );

    if (onTap == null) return content;
    return PressableScale(onTap: onTap, child: content);
  }
}

/// Backwards-compatible alias so existing feature pages keep compiling while
/// they inherit the new, calmer surface treatment.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(GwdSpace.lg),
    this.borderRadius = GwdRadius.xl,
    this.borderColor,
    this.backgroundColor,
    this.shadowColor,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final Color? borderColor;
  final Color? backgroundColor;
  final Color? shadowColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SurfaceCard(
        padding: padding,
        borderRadius: borderRadius,
        borderColor: borderColor,
        backgroundColor: backgroundColor,
        shadowColor: shadowColor,
        onTap: onTap,
        child: child,
      );
}

/// Small status/label capsule. One consistent shape for every tag in the app.
class GwdChip extends StatelessWidget {
  const GwdChip({
    super.key,
    required this.label,
    this.color,
    this.icon,
    this.filled = false,
    this.dense = false,
  });

  final String label;
  final Color? color;
  final IconData? icon;
  final bool filled;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = color ?? GwdColors.inkSecondaryOf(context);
    final bg = filled ? c : c.withValues(alpha: isDark ? 0.18 : 0.10);
    final fg = filled ? Colors.white : c;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 7 : 9,
        vertical: dense ? 3 : 4.5,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(GwdRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 10 : 11.5, color: fg),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              style: GwdType.caption.copyWith(
                color: fg,
                fontSize: dense ? 9.5 : 10.5,
                letterSpacing: 0.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Section heading with optional trailing action. Replaces the ad-hoc
/// Row + Text + TextButton clusters that were repeated on every screen.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: GwdSpace.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title.toUpperCase(),
                  style: GwdType.eyebrow
                      .copyWith(color: GwdColors.inkTertiaryOf(context)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: GwdType.footnote
                        .copyWith(color: GwdColors.inkSecondaryOf(context)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: GwdSpace.sm),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// Equalizer bar kept for source compatibility with existing widgets.
class SpectrumFrequencyBar extends StatelessWidget {
  const SpectrumFrequencyBar({
    super.key,
    required this.progress,
    this.barCount = 34,
    this.height = 36,
  });

  final double progress;
  final int barCount;
  final double height;

  @override
  Widget build(BuildContext context) => AppleDynamicEqualizer(
        progress: progress,
        barCount: barCount,
        height: height,
      );
}
