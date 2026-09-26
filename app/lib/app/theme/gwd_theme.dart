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

  // ---------------------------------------------------------------- light --
  //
  // Warm, not neutral. Every grey here carries a trace of the brand red, so a
  // crimson button sits *in* the page rather than on top of it. The difference
  // is a couple of points of hue and it is most of what separates a palette
  // that was designed from one that was picked.
  static const canvas = Color(0xFFFAF7F7);
  static const canvasLight = canvas; // legacy alias
  static const surface = Color(0xFFFFFFFF);
  static const surfaceWhite = surface; // legacy alias
  static const cardWhite = surface; // legacy alias
  static const canvasWhite = surface; // legacy alias
  static const surfaceSunken = Color(0xFFF4EEEF);
  static const hairline = Color(0xFFEAE0E1);
  static const hairlineSoft = Color(0xFFF4EEEF);
  static const line = hairline; // legacy alias
  static const lineSubtle = hairlineSoft; // legacy alias

  static const ink = Color(0xFF16090C);
  static const inkSecondary = Color(0xFF6A585C);
  static const inkTertiary = Color(0xFFA39195);

  // ----------------------------------------------------------------- dark --
  //
  // Near-black, deliberately *not* black. Pure #000 is where a dark theme goes
  // to look cheap: it flattens every surface into the same void, kills the
  // sense of depth that raised cards depend on, and smears on OLED as you
  // scroll. These carry the same red cast as the light side, so the two themes
  // read as one product rather than two.
  static const canvasDark = Color(0xFF0D0709);
  static const surfaceDark = Color(0xFF181013);
  static const surfaceDarkRaised = Color(0xFF211619);
  static const sunkenDark = Color(0xFF120B0D);
  static const hairlineDark = Color(0xFF2F2126);

  static const obsidian = Color(0xFF0D0709);
  static const jetBlack = Color(0xFF000000);
  static const charcoal = Color(0xFF1B1215);

  // ---------------------------------------------------------------- brand --
  //
  // Taken from the logo rather than from a palette generator: the mark is a
  // deep crimson, so the app is a deep crimson. [primaryRed] is the one that
  // gets spent on the single thing per screen that needs attention.
  static const primaryRed = Color(0xFFC81E2A);
  static const crimson = primaryRed;
  static const crimsonDeep = Color(0xFF8E1219);
  static const crimsonBright = Color(0xFFE8434F);
  static const rubyDark = crimsonDeep;
  static const rubyLight = Color(0xFFFCE9EA);
  static const accentCoral = crimsonBright;
  static const redGlow = Color(0x1FC81E2A);
  static const borderRed = Color(0x33C81E2A);

  // ------------------------------------------------------------- semantic --
  //
  // Pulled fractionally warm so they belong to the same family as the brand.
  // A stock material green next to this crimson looks borrowed.
  static const success = Color(0xFF1E9E5A);
  static const warning = Color(0xFFD98324);
  static const critical = Color(0xFFD93544);
  static const info = Color(0xFF3B6FD4);

  /// The brand ramp: a crimson shoulder at the top, gone by the first third.
  ///
  /// The one place the app uses a large area of colour, so that the screens
  /// that should feel like an *arrival* — signing in, the top of Home — are not
  /// a flat dark rectangle.
  ///
  /// ## The backdrop
  ///
  /// One field behind the entire app: near-black at the top, warming as it
  /// falls, with a deep oxblood bloom rising off the bottom edge. It does not
  /// scroll and it does not belong to any screen — it is the room the app is
  /// standing in.
  ///
  /// Two layers rather than one ramp, and that is the whole difference between
  /// this and the version it replaces. A single linear gradient from red to
  /// black bands visibly on an OLED panel, and reads as a gradient — as an
  /// effect somebody applied. A dark base with a radial bloom centred *below*
  /// the screen reads as light coming from somewhere, which is what every
  /// expensive dark interface is actually doing.
  ///
  /// The colour is also deliberately held down. A large field of saturated red
  /// is the single most reliable way to make an interface look cheap: it
  /// fights every piece of text on top of it and leaves nothing for the
  /// accent to say. The bloom is oxblood, most of the screen is nearly black,
  /// and the bright crimson is spent only on the one control that matters.
  static LinearGradient backdropBase(bool dark) => dark
      ? const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF07060A), Color(0xFF0A0709), Color(0xFF150B0F)],
          stops: [0.0, 0.55, 1.0],
        )
      : const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFFFFF), Color(0xFFFDFAFA), Color(0xFFFAF2F3)],
          stops: [0.0, 0.55, 1.0],
        );

  /// The glow, rising off the bottom edge.
  ///
  /// Vertical, and measured from the bottom up, because that is how the thing
  /// is described: red at the floor, gone by the ceiling.
  ///
  /// It was a radial bloom first, which was worse. A radial gradient large
  /// enough to matter puts its own circumference on screen, and a faint circle
  /// drawn across the bottom of every page is the most obvious tell there is
  /// that somebody applied an effect. Seven stops on a straight rise instead:
  /// enough that an OLED panel cannot band it, and no shape of its own.
  ///
  /// The alpha curve does the work. Even spacing looks like a ramp; front-
  /// loading it so the colour holds through the bottom fifth and then decays
  /// slowly looks like light falling off, which is the difference.
  static LinearGradient backdropBloom(bool dark) => dark
      ? const LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Color(0xF0901527),
            Color(0xD17D1322),
            Color(0x9C5F0F1B),
            Color(0x633F0A13),
            Color(0x3326070D),
            Color(0x14120407),
            Color(0x0007060A),
          ],
          stops: [0.0, 0.07, 0.17, 0.29, 0.43, 0.60, 0.84],
        )
      : const LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Color(0x2EC81E2A),
            Color(0x24C81E2A),
            Color(0x1AC81E2A),
            Color(0x11C81E2A),
            Color(0x09C81E2A),
            Color(0x04C81E2A),
            Color(0x00C81E2A),
          ],
          stops: [0.0, 0.07, 0.17, 0.29, 0.43, 0.60, 0.84],
        );

  /// Colours that tell one department, event or member from another.
  ///
  /// All of them warm, and all of them inside the same band as the brand:
  /// hues run from wine at 343 degrees round through crimson to ember at 22,
  /// and nothing goes further. A colour past that starts reading gold, and a
  /// gold header on an oxblood app looks like two products stitched together —
  /// which is exactly what the drone event looked like.
  ///
  /// They separate by *tone* as much as by hue, because eight colours cannot be
  /// told apart inside a forty-degree band on hue alone. Relative luminance
  /// runs 0.05 to 0.28 across the set, so plum and rose are obviously different
  /// things even though they are nearly the same colour.
  ///
  /// Anything stored before this still comes back from the server, so nothing
  /// here is load-bearing on its own — [readableOn] is.
  static const accents = <Color>[
    Color(0xFFC81E2A), // crimson — the brand, first so it is the most common
    Color(0xFFE2607A), // rose — the light end
    Color(0xFF8E1538), // wine
    Color(0xFFB33A22), // rust
    Color(0xFFD9773F), // ember — the warmest, and still short of gold
    Color(0xFF6E2439), // plum — the deep end
    Color(0xFFA85C4E), // terracotta — the muted one
    Color(0xFFC43C55), // raspberry
  ];

  /// The same colour, guaranteed to be readable on the current theme.
  ///
  /// Accent colours arrive from the database — a member's avatar colour, a
  /// category an admin picked from a colour well — so the app cannot assume
  /// any of them suits the theme it is painting. A deep tint vanishes on the
  /// dark canvas and a pale one vanishes on white, and the avatar tile uses the
  /// tint for its text, where vanishing means unreadable rather than merely
  /// dull.
  ///
  /// Only lightness moves, so the colour stays recognisably itself and two
  /// departments that were distinguishable stay distinguishable.
  static Color readableOn(BuildContext context, Color tint) {
    final dark = _isDark(context);
    final hsl = HSLColor.fromColor(tint);
    final lightness = hsl.lightness.clamp(dark ? 0.56 : 0.26, dark ? 0.80 : 0.46);
    return hsl.withLightness(lightness).toColor();
  }

  /// Text that sits on the darkest part of the backdrop.
  ///
  /// Kept because a few surfaces genuinely sit on colour — the sign-in mark,
  /// the nav bar's selected rule — and reaching for `inkOf` there would put
  /// near-black text on a red field in the light theme.
  static const onHero = Color(0xFFFFFFFF);
  static const onHeroSoft = Color(0xB3FFFFFF);
  static const onHeroFaint = Color(0x24FFFFFF);
  static const onHeroLine = Color(0x38FFFFFF);

  /// The same ramp turned on its side, for a card that wants brand weight
  /// without becoming a billboard.
  static const accent = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryRed, crimsonDeep],
  );

  /// A semantic colour as a **background**, correct in either theme.
  ///
  /// The pale `successSoft` / `criticalSoft` constants this replaces were
  /// light-mode hexes with no dark counterpart, so `ErrorNote` — the error
  /// component every screen uses — painted a near-white pink block on the
  /// obsidian canvas. A tint has to be derived from the theme, not frozen at
  /// one brightness: the same hue washed over the surface, faint on white and
  /// a touch stronger on black where a low alpha would otherwise vanish.
  static Color tintOf(BuildContext context, Color tint) =>
      tint.withValues(alpha: _isDark(context) ? 0.16 : 0.10);

  /// The hairline that goes with [tintOf], for a bordered panel.
  static Color tintBorderOf(BuildContext context, Color tint) =>
      tint.withValues(alpha: _isDark(context) ? 0.34 : 0.25);

  /// Resolves a token to its light or dark counterpart.
  static Color surfaceOf(BuildContext context) => _isDark(context) ? surfaceDark : surface;

  static Color raisedOf(BuildContext context) => _isDark(context) ? surfaceDarkRaised : surface;

  static Color canvasOf(BuildContext context) => _isDark(context) ? canvasDark : canvas;

  static Color sunkenOf(BuildContext context) => _isDark(context) ? sunkenDark : surfaceSunken;

  static Color hairlineOf(BuildContext context) => _isDark(context) ? hairlineDark : hairline;

  static Color inkOf(BuildContext context) => _isDark(context) ? const Color(0xFFF7F2F3) : ink;

  static Color inkSecondaryOf(BuildContext context) =>
      _isDark(context) ? const Color(0xFFA79599) : inkSecondary;

  static Color inkTertiaryOf(BuildContext context) =>
      _isDark(context) ? const Color(0xFF756368) : inkTertiary;

  static bool _isDark(BuildContext context) => Theme.of(context).brightness == Brightness.dark;
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

/// The type system.
///
/// Two faces, and the split is the whole idea:
///
///   **Inter** carries the interface. It is drawn for screens at exactly the
///   sizes this app lives at — a 9.5pt label, a 13.5pt row of names — where
///   the stock system face turns to mud. Everything a person *reads* is Inter.
///
///   **Space Grotesk** carries titles and figures. Geometric and faintly
///   technical, which is the same language the bracket in the logo speaks. Its
///   digits have flat sides and open counters, so a column of points or a
///   percentage reads as *set* rather than typed.
///
/// Before this, the app had no typeface at all: Roboto on Android, San
/// Francisco on iOS, and something else again on the web. Three different apps
/// wearing the same layout, none of them looking like a decision.
///
/// Both are variable fonts, declared per weight in `pubspec.yaml`, so plain
/// [FontWeight] drives the real `wght` axis — no synthetic bold, and the fifty
/// call sites that override a weight go on working rather than silently doing
/// nothing.
class GwdType {
  const GwdType._();

  /// The interface face.
  static const ui = 'Inter';

  /// The display face, for titles and anything numeric.
  static const display = 'SpaceGrotesk';

  // --- display: titles, and only titles -------------------------------------
  //
  // Tracking goes negative as the size goes up. Large text sets itself too
  // loose by default, and pulling it in is most of what separates a heading
  // that looks designed from one that looks like a bigger paragraph.

  static const largeTitle = TextStyle(
      fontFamily: display,
      fontSize: 32,
      height: 1.08,
      fontWeight: FontWeight.w700,
      letterSpacing: -1.1);
  static const title1 = TextStyle(
      fontFamily: display,
      fontSize: 26,
      height: 1.12,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.85);
  static const title2 = TextStyle(
      fontFamily: display,
      fontSize: 21,
      height: 1.18,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.6);
  static const title3 = TextStyle(
      fontFamily: display,
      fontSize: 17,
      height: 1.24,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.4);

  // --- interface: everything a person actually reads ------------------------

  static const headline = TextStyle(
      fontFamily: ui, fontSize: 15, height: 1.3, fontWeight: FontWeight.w600, letterSpacing: -0.2);
  static const body = TextStyle(
      fontFamily: ui,
      fontSize: 14.5,
      height: 1.46,
      fontWeight: FontWeight.w400,
      letterSpacing: -0.08);
  static const callout = TextStyle(
      fontFamily: ui,
      fontSize: 13.5,
      height: 1.36,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.08);
  static const subhead = TextStyle(
    fontFamily: ui,
    fontSize: 12.5,
    height: 1.36,
    fontWeight: FontWeight.w500,
  );
  static const footnote = TextStyle(
    fontFamily: ui,
    fontSize: 11.5,
    height: 1.32,
    fontWeight: FontWeight.w500,
  );
  static const caption = TextStyle(
    fontFamily: ui,
    fontSize: 11,
    height: 1.26,
    fontWeight: FontWeight.w600,
  );

  /// Section eyebrow. Uppercase, wide tracking, never larger than 10.5pt.
  static const eyebrow = TextStyle(
      fontFamily: ui, fontSize: 10.5, height: 1.2, fontWeight: FontWeight.w700, letterSpacing: 0.9);

  // --- the bottom of the ramp ----------------------------------------------
  //
  // These two exist because the app was already full of them without names:
  // 59 call sites shrinking `caption` or `eyebrow` by hand to 8.5, 9, 9.5 or
  // 10pt, each one a guess. That is a ramp step whether it is written down or
  // not, so it is written down — and changing how big the app's smallest text
  // is becomes one edit rather than 59.
  //
  // 9.5pt is the floor and nothing goes under it. Sizes below that existed
  // (one label was 7.5) and, with the old 0.85 text-scale floor, reached the
  // screen at under 7pt.

  /// Dense metadata: the grey line under a name, a count beside a label.
  /// No tracking — it sits directly under normal text and must not look
  /// like a heading.
  static const micro = TextStyle(
      fontFamily: ui, fontSize: 9.5, height: 1.25, fontWeight: FontWeight.w600, letterSpacing: 0);

  /// The smallest tracked label: chips, badges, the month in a date block.
  /// Uppercase in use, so the tracking is doing real work.
  static const microLabel = TextStyle(
      fontFamily: ui, fontSize: 9.5, height: 1.2, fontWeight: FontWeight.w700, letterSpacing: 0.5);

  /// Figures: points, percentages, counts, money, dates.
  ///
  /// Merged onto a ramp step rather than used alone, so it changes the *face*
  /// and the figure style without touching the size the layout chose.
  /// Tabular so an animated counter does not reflow the row while it rolls.
  /// Deliberately *not* slashed: a slashed zero disambiguates a reference
  /// code, but on "0 points" it reads as a figure struck through — which is
  /// the opposite of what the number is saying.
  static const numeric = TextStyle(
    fontFamily: display,
    fontFeatures: [FontFeature.tabularFigures()],
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
  );
}

/// One icon per *state*, so the same fact looks the same everywhere.
///
/// This exists because it did not. "Finished" was drawn five different ways
/// depending on which screen you were on — `check_circle_rounded` on a task,
/// `check_circle_outline_rounded` on a meeting, `task_alt_rounded` in a
/// notification, `verified_rounded` on a paid bill, a bare `check_rounded` on
/// an attendance row. Nobody decided that; it accumulated. The cost is that a
/// member cannot learn the app's vocabulary, because it does not have one.
///
/// The distinctions that remain are the ones that carry meaning:
///
///   [done]      the work is finished
///   [approved]  somebody with authority said yes — a judgement, not a state
///   [settled]   money actually moved
///
/// Finishing a task and having your expense approved are different events and
/// should not share a glyph. Two tasks finishing should.
class GwdIcons {
  const GwdIcons._();

  // --- how something is going ----------------------------------------------
  /// Open and untouched. Hollow on purpose: it reads as an empty checkbox.
  static const notStarted = Icons.radio_button_unchecked;
  static const inProgress = Icons.timelapse_rounded;
  static const inReview = Icons.rate_review_outlined;
  static const done = Icons.check_circle_rounded;
  static const blocked = Icons.report_problem_outlined;
  static const cancelled = Icons.cancel_outlined;

  // --- somebody's decision --------------------------------------------------
  /// Waiting on a person, not on work. Distinct from [notStarted]: nobody can
  /// make this move by doing more.
  static const waiting = Icons.hourglass_empty_rounded;
  static const approved = Icons.verified_rounded;
  static const declined = Icons.block_rounded;
  static const settled = Icons.payments_outlined;

  // --- attendance -----------------------------------------------------------
  /// Deliberately not [done]: a meeting is not a task, and a tick in a
  /// register means "was here", not "finished".
  static const attended = Icons.check_rounded;
  static const absent = Icons.close_rounded;
  static const excused = Icons.info_outline_rounded;
  static const notRecorded = Icons.remove_rounded;

  // --- things ----------------------------------------------------------------
  static const meeting = Icons.groups_2_outlined;
  static const meetingOff = Icons.event_busy_outlined;
  static const event = Icons.celebration_outlined;
  static const task = Icons.assignment_outlined;
  static const department = Icons.workspaces_outline;
  static const help = Icons.pan_tool_alt_outlined;
  static const document = Icons.description_outlined;
  static const money = Icons.receipt_long_outlined;
}

/// Soft, physically plausible shadows: a tight contact shadow plus a wide
/// ambient one. Coloured glows are reserved for genuinely live elements.
class GwdShadow {
  const GwdShadow._();

  // Cheaper than they were. Every card carried a 16px (resting) or 30px
  // (raised) ambient blur, which on the near-black dark theme is invisible and
  // still costs a blur per card per frame while a list scrolls. Dark keeps the
  // tight contact shadow that actually reads; light keeps a small soft one.
  static List<BoxShadow> resting(bool isDark) => [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.40 : 0.035),
          blurRadius: 2,
          offset: const Offset(0, 1),
        ),
        if (!isDark)
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.045),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
      ];

  static List<BoxShadow> lifted(bool isDark) => [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.50 : 0.06),
          blurRadius: 4,
          offset: const Offset(0, 2),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.07),
          blurRadius: 12,
          offset: const Offset(0, 6),
        ),
      ];

  /// Reserved for elements that are genuinely live (active alert, primary CTA).
  ///
  /// A contact shadow, not a glow. At a wide blur and no offset a coloured
  /// shadow stops reading as light falling off an object and starts reading as
  /// the object emitting light, which on a dark page looks like a bad neon
  /// filter. Kept tight and pushed downwards so it still says "this button is
  /// the raised one" without haloing.
  static List<BoxShadow> accent(Color color) => [
        BoxShadow(
          color: color.withValues(alpha: 0.22),
          blurRadius: 14,
          offset: const Offset(0, 6),
          spreadRadius: -4,
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
      // The interface face, as the app-wide default.
      //
      // The TextTheme below covers everything the design system draws, but
      // Material fills in its own chrome from this — dialog buttons, tooltips,
      // the date picker, the text-selection toolbar. Without it those kept
      // rendering in Roboto while everything around them did not, which reads
      // as a bug even when nobody can name it.
      fontFamily: GwdType.ui,
      fontFamilyFallback: const ['Inter', 'Roboto'],
      // Transparent, because the app paints one backdrop at the root and
      // every screen stands on it. An opaque scaffold anywhere punches a
      // flat rectangle through that field, which is exactly how a dark
      // theme ends up looking like five unrelated black screens.
      scaffoldBackgroundColor: Colors.transparent,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: GwdColors.primaryRed,
        onPrimary: Colors.white,
        secondary: isDark ? Colors.white : GwdColors.ink,
        onSecondary: isDark ? GwdColors.ink : Colors.white,
        surface: isDark ? GwdColors.surfaceDark : GwdColors.surface,
        onSurface: ink,
        surfaceContainerHighest: isDark ? GwdColors.surfaceDarkRaised : GwdColors.surfaceSunken,
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
/// The field the whole app stands on.
///
/// Painted once, at the root, behind every route. Deliberately *not* per-screen:
/// five pages each drawing their own background is how they drift apart, and a
/// backdrop that restarts at every navigation is a backdrop the eye notices.
///
/// It does not scroll with the content either. A glow that slides up the screen
/// as you flick a list reads as a texture printed on the page; one that stays
/// put reads as the light in the room.
class AppBackdrop extends StatelessWidget {
  const AppBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(gradient: GwdColors.backdropBase(dark)),
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: GwdColors.backdropBloom(dark)),
        child: child,
      ),
    );
  }
}

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
    // Translucent in the dark, so the backdrop's glow passes through a card
    // instead of being blocked by it. An opaque near-black panel laid over a
    // lit field is a hole cut in the page; a pane of tinted glass is a surface
    // resting on it, and that difference is most of what separates an
    // expensive-looking dark interface from a cheap one.
    //
    // Light mode keeps a solid surface: white on near-white needs the edge that
    // opacity provides, and there is no glow underneath to reveal.
    final bg = backgroundColor ??
        (isDark ? const Color(0x0DFFFFFF) : GwdColors.surface);

    final border = borderColor ??
        switch (emphasis) {
          // A hairline of light along the top edge, not a grey outline. On a
          // glass pane the border is the edge catching the light.
          SurfaceEmphasis.quiet => isDark ? const Color(0x14FFFFFF) : GwdColors.hairline,
          SurfaceEmphasis.raised => isDark ? const Color(0x1FFFFFFF) : GwdColors.hairline,
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
            ? [BoxShadow(color: shadowColor!, blurRadius: 18, offset: const Offset(0, 6))]
            : shadows,
      ),
      child: Padding(padding: padding, child: child),
    );

    if (onTap == null) return content;
    return PressableScale(onTap: onTap, child: content);
  }
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
                  style: GwdType.eyebrow.copyWith(color: GwdColors.inkTertiaryOf(context)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: GwdType.footnote.copyWith(color: GwdColors.inkSecondaryOf(context)),
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
