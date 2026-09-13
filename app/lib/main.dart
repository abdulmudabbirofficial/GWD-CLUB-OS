import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/app_scope.dart';
import 'app/shell/club_shell.dart';
import 'app/theme/gwd_theme.dart';
import 'app/widgets/brand.dart';
import 'core/state/club_store.dart';
import 'core/state/session.dart';
import 'features/auth/pending_page.dart';
import 'features/auth/sign_in_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Restore the saved session before the first frame so an already-signed-in
  // member never sees sign-in flash past.
  final session = Session();
  await session.restore();

  runApp(GwdClubApp(session: session));
}

class GwdClubApp extends StatefulWidget {
  const GwdClubApp({super.key, required this.session});

  final Session session;

  @override
  State<GwdClubApp> createState() => _GwdClubAppState();
}

class _GwdClubAppState extends State<GwdClubApp> {
  late final ClubStore _store = ClubStore(session: widget.session);
  SessionState? _lastState;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_onSessionChanged);
    _lastState = widget.session.state;
    if (widget.session.state == SessionState.active) _store.start();
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSessionChanged);
    _store.dispose();
    super.dispose();
  }

  /// Connect the socket only once the account is actually approved — a pending
  /// member has nothing to receive, and the server would reject the handshake.
  void _onSessionChanged() {
    final next = widget.session.state;
    if (next == _lastState) return;
    final previous = _lastState;
    _lastState = next;

    if (next == SessionState.active && previous != SessionState.active) {
      _store.start();
    } else if (next != SessionState.active && previous == SessionState.active) {
      _store.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      session: widget.session,
      store: _store,
      child: MaterialApp(
        title: 'GWD Club',
        debugShowCheckedModeBanner: false,
        theme: GwdTheme.light(),
        darkTheme: GwdTheme.dark(),
        // Dark mode from day one (Section 2). v1 pinned this to light.
        themeMode: ThemeMode.system,
        scrollBehavior: const _FluidScrollBehavior(),
        builder: (context, child) {
          final media = MediaQuery.of(context);
          // Honour the user's text-size preference, but cap the extremes so
          // dense rows stay readable rather than collapsing.
          return MediaQuery(
            data: media.copyWith(
              textScaler: media.textScaler.clamp(
                minScaleFactor: 0.85,
                maxScaleFactor: 1.4,
              ),
            ),
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: const _Root(),
      ),
    );
  }
}

/// Decides which of the three top-level surfaces to show.
class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final session = AppScope.sessionOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Keep the system bars in step with the theme.
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: isDark ? GwdColors.canvasDark : GwdColors.canvas,
      systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
    ));

    final inShell = session.state == SessionState.active;

    final screen = switch (session.state) {
      SessionState.restoring => const _Splash(),
      SessionState.signedOut => const SignInPage(),
      SessionState.pendingApproval => const PendingApprovalPage(),
      SessionState.active => ClubShell(key: ClubShell.shellKey),
    };

    // Android back.
    //
    // This has to live here, directly under the home route. Inside ClubShell it
    // sat behind that widget's own Navigator and was never consulted, so back
    // closed the app from anywhere — open a task, press back, app gone.
    //
    // It unwinds in the order people expect:
    //   1. close a full-screen flow (the event wizard), which lives on the root
    //      navigator so it covers the tab bar
    //   2. close a detail page on the shell's inner navigator
    //   3. return to Home from any other tab
    //   4. only from Home does back actually leave the app
    return PopScope(
      canPop: !inShell,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final root = Navigator.of(context, rootNavigator: true);
        if (root.canPop()) {
          root.pop();
          return;
        }
        final consumed = await ClubShell.handleBack();
        if (!consumed) await SystemNavigator.pop();
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 420),
        switchInCurve: Curves.easeOutCubic,
        child: KeyedSubtree(key: ValueKey(session.state), child: screen),
      ),
    );
  }
}

/// Shown only for the instant it takes to read the saved token. Deliberately
/// the brand mark rather than a spinner.
class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GwdColors.canvasOf(context),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The brackets draw themselves in — the app's first frame is the
            // club's own mark being built, not a spinner.
            const AnimatedGwdMark(size: 76),
            const SizedBox(height: GwdSpace.lg),
            Text(
              'GET WORK DONE',
              style: GwdType.eyebrow.copyWith(
                color: GwdColors.inkTertiaryOf(context),
                letterSpacing: 2.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Drag-scroll with a mouse so the web build feels right, plus iOS bouncing
/// physics everywhere for one consistent feel across platforms.
class _FluidScrollBehavior extends MaterialScrollBehavior {
  const _FluidScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());

  @override
  Widget buildOverscrollIndicator(
          BuildContext context, Widget child, ScrollableDetails details) =>
      child;
}
