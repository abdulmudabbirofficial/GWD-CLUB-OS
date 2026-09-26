
import 'package:flutter/material.dart';

import '../../core/models/app_notification.dart';
import '../../features/alerts/alerts_page.dart';
import '../../features/approvals/approvals_page.dart';
import '../../features/auth/change_password_sheet.dart';
import '../../features/auth/set_name_sheet.dart';
import '../../features/club/more_page.dart';
import '../../features/departments/departments_hub_page.dart';
import '../../features/directory/directory_page.dart';
import '../../features/events/event_workspace_page.dart';
import '../../features/events/events_page.dart';
import '../../features/help/help_page.dart';
import '../../features/home/home_page.dart';
import '../../features/leaderboard/leaderboard_page.dart';
import '../../features/meetings/meeting_detail_page.dart';
import '../../features/meetings/meetings_page.dart';
import '../../features/profile/profile_sheet.dart';
import '../../features/tasks/task_detail_page.dart';
import '../../features/tasks/tasks_page.dart';
import '../app_scope.dart';
import '../responsive.dart';
import '../theme/apple_motion.dart';
import '../theme/gwd_theme.dart';
import '../widgets/brand.dart';
import '../widgets/live_toast.dart';

/// The five-tab shell.
///
/// One tab per question a member actually has:
///   Home         what should I do now?
///   Events       what is the club putting on?
///   Work         what am I responsible for?
///   Departments  how is each part of the club getting on?
///   More         everything else — schedule, announcements, people, admin
///
/// Events earns a tab because it is the unit a club organises around: tasks,
/// paperwork and who-does-what all hang off one. The schedule and announcements
/// moved into More, and Home surfaces what is happening today instead, because
/// a tab you open once a week is a tab wasted.
///
/// On a phone that is a bottom bar. On anything wider it becomes a side rail:
/// a bottom bar on a tablet wastes the whole width and puts the controls miles
/// from the user's hands.
/// Private so the state type never leaks into the public API; reached only
/// through [ClubShell.handleBack].
final GlobalKey<_ClubShellState> _shellKey = GlobalKey<_ClubShellState>();

class ClubShell extends StatefulWidget {
  const ClubShell({super.key});

  /// The shell owns back-button behaviour, but the `PopScope` that intercepts
  /// it has to sit directly under the home route — nested any deeper (behind
  /// this widget's own `Navigator`) it never gets consulted, and Android back
  /// closes the app from anywhere. So the root holds the PopScope and calls
  /// through to here.
  static Key get shellKey => _shellKey;

  /// Returns true when the shell consumed the press, false when there is
  /// nothing left to unwind and the app may close.
  static Future<bool> handleBack() async {
    final state = _shellKey.currentState;
    if (state == null) return false;
    return state._back();
  }

  /// Follow a notification to whatever it is about.
  ///
  /// It lives on the shell rather than in the alerts page because most
  /// destinations are **tabs**, and `Navigator.of(context)` inside a page can
  /// only push — it cannot change which tab is showing. Doing it here means one
  /// implementation serves the notification list, a live toast and an FCM tap
  /// alike, instead of three that drift.
  ///
  /// Returns false when there was nowhere to go, so the caller can leave the
  /// row alone rather than animating a navigation that never happened.
  static bool open(NotificationTarget target) {
    final state = _shellKey.currentState;
    if (state == null) return false;
    return state._open(target);
  }

  @override
  State<ClubShell> createState() => _ClubShellState();
}

class _ClubShellState extends State<ClubShell> {
  int _index = 0;
  final _navigatorKey = GlobalKey<NavigatorState>();
  bool _ranFirstRun = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _firstRun());
  }

  /// The two things an account created *for* somebody arrives without: their
  /// name, and a password only they know.
  ///
  /// Name first. It is the thing every other person in the club reads — on
  /// tasks, approvals and boards — and asking "who are you?" before "pick a
  /// password" is the order that reads like being welcomed rather than
  /// processed. Both are forced, and both run once per session.
  Future<void> _firstRun() async {
    if (_ranFirstRun || !mounted) return;
    _ranFirstRun = true;

    final me = AppScope.readSession(context).me;
    if (me == null) return;

    if (me.mustSetName) {
      await showSetNameSheet(context, forced: true);
      if (!mounted) return;
    }
    // Re-read: setting the name refreshed the session, so the instance captured
    // above is stale by now.
    if (AppScope.readSession(context).me?.mustChangePassword == true) {
      await showChangePasswordSheet(context, forced: true);
    }
  }

  /// Tab indices, named. `pages` below must stay in this order.
  static const _home = 0;
  static const _events = 1;
  static const _work = 2;
  static const _departments = 3;
  static const _more = 4;

  /// Push a detail page onto the inner navigator, landing on a sensible tab
  /// first so backing out of it leaves somebody somewhere coherent.
  void _push(int tab, Widget page) {
    _selectTab(tab);
    _navigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => page));
  }

  bool _open(NotificationTarget target) {
    switch (target.kind) {
      case NotificationTargetKind.none:
        return false;

      // --- specific things, by id ------------------------------------------
      case NotificationTargetKind.task:
        // Deliberately not gated on the task already being in the store, unlike
        // `_openTask` above: a notification frequently arrives for work this
        // client has not loaded yet, and the detail page fetches by id anyway.
        // Silently doing nothing is the worst possible answer to a tap.
        _push(_work, TaskDetailPage(taskId: target.id!));
        return true;
      case NotificationTargetKind.meeting:
        _push(_more, MeetingDetailPage(meetingId: target.id!));
        return true;
      case NotificationTargetKind.event:
        _push(_events, EventWorkspacePage(eventId: target.id!));
        return true;
      case NotificationTargetKind.help:
        _push(_more, const HelpPage());
        return true;

      // --- the screen that lists its kind ----------------------------------
      case NotificationTargetKind.approvals:
        _push(_more, const ApprovalsPage());
        return true;
      case NotificationTargetKind.directory:
        _push(_more, const DirectoryPage());
        return true;
      case NotificationTargetKind.helpBoard:
        _push(_more, const HelpPage());
        return true;
      case NotificationTargetKind.meetings:
        _push(_more, const MeetingsPage());
        return true;
      case NotificationTargetKind.recognition:
        _push(_more, const LeaderboardPage());
        return true;
      case NotificationTargetKind.departments:
        _selectTab(_departments);
        return true;
      case NotificationTargetKind.profile:
        _selectTab(_more);
        showProfileSheet(context);
        return true;

      // --- tabs -------------------------------------------------------------
      case NotificationTargetKind.myWork:
      case NotificationTargetKind.incoming:
      case NotificationTargetKind.requests:
        // All three live on the Work tab, which owns its own scopes. Landing
        // on the tab is the honest answer: deep-linking to a filter somebody
        // then cannot get out of is worse than showing them the list.
        _selectTab(_work);
        return true;
      case NotificationTargetKind.broadcasts:
        _push(_more, const AlertsPage());
        return true;
    }
  }

  /// Detail pages live on the inner navigator so the tab bar never disappears.
  /// Switching tabs therefore has to unwind that stack first, or the index
  /// changes underneath an open detail page and the tap looks broken.
  void _selectTab(int next) {
    final navigator = _navigatorKey.currentState;
    if (navigator != null && navigator.canPop()) {
      navigator.popUntil((route) => route.isFirst);
    }
    if (next != _index) setState(() => _index = next);
  }

  /// Android back, unwound in the order people expect:
  ///   1. close an open detail page
  ///   2. return to Home from any other tab
  ///   3. only then let the app close
  ///
  /// Returns true if the press was consumed.
  Future<bool> _back() async {
    final navigator = _navigatorKey.currentState;
    if (navigator != null && navigator.canPop()) {
      navigator.pop();
      return true;
    }
    if (_index != _home) {
      setState(() => _index = _home);
      return true;
    }
    return false; // on Home with nothing stacked — let it close
  }

  @override
  Widget build(BuildContext context) {
    // `readStore`, not `storeOf`: the shell wraps every screen in the app, and
    // subscribing it to the whole store meant one socket event about somebody
    // else's task rebuilt the shell, which rebuilt the current tab, which is a
    // fifty-kilobyte widget tree. The only thing the shell itself displays from
    // the store is three badge numbers, and those watch themselves below.
    final store = AppScope.readStore(context);
    final layout = Layout.of(context);

    final builders = <WidgetBuilder>[
      (_) => HomePage(onNavigate: _selectTab),
      (_) => const EventsPage(),
      (_) => const TasksPage(),
      (_) => const DepartmentsHubPage(),
      (_) => const MorePage(),
    ];

    // Tell everything inside the shell how tall the bar over it is.
    //
    // `extendBody` lets the content scroll under the frosted bar, which is
    // what gives the blur something to blur — but it also means the inner
    // pages' own Scaffolds no longer have that space reserved for them, so
    // their floating action buttons floated *underneath* it. Folding the bar's
    // height into the inherited bottom padding fixes every one of them at
    // once: a Scaffold sizes its FAB against exactly this, and `SafeArea`
    // reads it too, so nothing has to know the shell exists.
    //
    // The `Builder` is load-bearing, and was the bug.
    //
    // Read from the shell's own build context, `MediaQuery.of` returns the data
    // from *outside* this Scaffold — which still carries the keyboard inset
    // that the Scaffold has just finished removing from its body. Re-publishing
    // it put the inset back, and the pushed page's own Scaffold then subtracted
    // it a second time. Measured with a text field focused: the shell handed
    // the Navigator 361.5 points and the page's body came out at **zero**,
    // which paints as a blank screen under the app bar with no error anywhere.
    // Search was unusable the moment anybody typed, which is all that screen
    // does.
    //
    // Inside the body, `MediaQuery.of` is the Scaffold's already-adjusted copy:
    // the inset is gone because the space has been taken, and adding the bar
    // height back is the only correction left to make.
    //
    // Since V8.1 the bar is solid and the body stops above it, so there is no
    // bar height to fold in any more: the Scaffold has already taken it.
    Widget shellBody(BuildContext context) {
      final media = MediaQuery.of(context);
      return MediaQuery(
        data: media,
        child: Navigator(
          key: _navigatorKey,
          onGenerateRoute: (_) => MaterialPageRoute(
            builder: (_) => _TabStack(index: _index, builders: builders),
          ),
        ),
      );
    }

    // No PopScope here — it must sit directly under the home route to be
    // consulted, so main.dart owns it and calls ClubShell.handleBack().
    return LiveToastHost(
      store: store,
      onOpen: _open,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        // The content stops *above* the bar. It used to run underneath a
        // frosted one, and pages ended their lists with a fixed gap shorter
        // than the bar — so the last actions on Home and the last rows of the
        // directory sat behind it, and you had to scroll to the very end to
        // reach "Call a meeting". The blur behind it was also recomputed on
        // every scroll frame, which is the stutter at the bottom of long lists.
        extendBody: false,
        body: layout.usesRail
            ? Row(
                children: [
                  _Badges(
                    builder: (context, items) => _ClubNavRail(
                      index: _index,
                      items: items,
                      onChanged: _selectTab,
                      extended: layout.twoColumn,
                    ),
                  ),
                  Expanded(child: Builder(builder: shellBody)),
                ],
              )
            : Builder(builder: shellBody),
        bottomNavigationBar: layout.usesRail
            ? null
            : _Badges(
                builder: (context, items) =>
                    _ClubNavBar(index: _index, items: items, onChanged: _selectTab),
              ),
      ),
    );
  }
}

/// The five tabs, each built once and then kept.
///
/// The shell used to hand `AnimatedSwitcher` a child keyed on the tab index,
/// which meant every switch **destroyed the outgoing page**: scroll position
/// gone, entrance animations replayed, and any `initState` fetch run again. A
/// tab you flick to and back from should be where you left it, and should not
/// cost a round trip to find that out.
///
/// Lazy, so an account that never opens Departments never builds it. Alive
/// after that, so it never builds twice. And `TickerMode` is switched off for
/// every hidden tab, because an `IndexedStack` keeps its children in the tree
/// and their animation controllers would otherwise keep ticking on a page
/// nobody is looking at.
class _TabStack extends StatefulWidget {
  const _TabStack({required this.index, required this.builders});

  final int index;
  final List<WidgetBuilder> builders;

  @override
  State<_TabStack> createState() => _TabStackState();
}

class _TabStackState extends State<_TabStack> with SingleTickerProviderStateMixin {
  final Set<int> _built = {};

  // One short fade-and-lift for the whole stack on each switch, rather than a
  // transition per page. A tab change should read as a change without costing
  // a composited layer per row of whatever is on screen.
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: AppleDuration.standard,
    value: 1,
  );

  @override
  void didUpdateWidget(_TabStack old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index && !prefersReducedMotion(context)) {
      _enter.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _built.add(widget.index);

    final stack = IndexedStack(
      index: widget.index,
      sizing: StackFit.expand,
      children: [
        for (var i = 0; i < widget.builders.length; i++)
          if (_built.contains(i))
            TickerMode(enabled: i == widget.index, child: widget.builders[i](context))
          else
            const SizedBox.shrink(),
      ],
    );

    if (prefersReducedMotion(context)) return stack;

    final eased = CurvedAnimation(parent: _enter, curve: AppleCurves.enter);
    return FadeTransition(
      opacity: eased,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.012), end: Offset.zero).animate(eased),
        child: stack,
      ),
    );
  }
}

/// The nav badges, and nothing else, watching the store.
///
/// Three numbers out of a store that notifies from sixty places. Pulled out so
/// the counts stay live without the shell — and therefore the whole current
/// tab — rebuilding underneath them.
class _Badges extends StatelessWidget {
  const _Badges({required this.builder});

  final Widget Function(BuildContext context, List<NavItem> items) builder;

  @override
  Widget build(BuildContext context) {
    return AppScope.select<({int live, int mine, int needsYou})>(
      context,
      (store) => (
        live: store.eventsOngoing.length,
        mine: store.myTasks.where((t) => t.status.isOpen).length,
        needsYou: store.unreadNotifications + store.pendingApprovals.length,
      ),
      (context, counts) => builder(context, [
        const NavItem(Icons.home_outlined, Icons.home_rounded, 'Home'),
        NavItem(Icons.event_outlined, Icons.event_rounded, 'Events',
            badge: counts.live, accentBadge: true),
        NavItem(Icons.check_circle_outline, Icons.check_circle_rounded, 'Work',
            badge: counts.mine),
        const NavItem(Icons.workspaces_outline, Icons.workspaces_rounded, 'Departments'),
        NavItem(Icons.more_horiz_rounded, Icons.more_horiz_rounded, 'More',
            badge: counts.needsYou, accentBadge: true),
      ]),
    );
  }
}

class NavItem {
  const NavItem(this.icon, this.activeIcon, this.label, {this.badge = 0, this.accentBadge = false});
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final int badge;
  final bool accentBadge;
}

/// Side navigation for tablets and desktop. Carries the wordmark, which a
/// bottom bar has no room for.
class _ClubNavRail extends StatelessWidget {
  const _ClubNavRail({
    required this.index,
    required this.items,
    required this.onChanged,
    required this.extended,
  });

  final int index;
  final List<NavItem> items;
  final ValueChanged<int> onChanged;
  final bool extended;

  @override
  Widget build(BuildContext context) {
    // Fixed width, so the same cap on text scaling as the bottom bar.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.15,
      child: _rail(context),
    );
  }

  Widget _rail(BuildContext context) {
    return Container(
      width: extended ? 208 : 88,
      decoration: BoxDecoration(
        color: GwdColors.surfaceOf(context),
        border: Border(right: BorderSide(color: GwdColors.hairlineOf(context))),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(extended ? GwdSpace.lg : GwdSpace.md, GwdSpace.xl,
                  extended ? GwdSpace.lg : GwdSpace.md, GwdSpace.xl),
              child: extended
                  ? const GwdWordmark(compact: true)
                  : const Center(child: GwdMark(size: 40)),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.symmetric(horizontal: extended ? GwdSpace.md : GwdSpace.sm),
                children: [
                  for (var i = 0; i < items.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: GwdSpace.xs),
                      child: _RailButton(
                        item: items[i],
                        selected: i == index,
                        extended: extended,
                        onTap: () => onChanged(i),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.item,
    required this.selected,
    required this.extended,
    required this.onTap,
  });

  final NavItem item;
  final bool selected;
  final bool extended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.white : GwdColors.inkSecondaryOf(context);

    return Semantics(
      button: true,
      selected: selected,
      label: item.badge > 0 ? '${item.label}, ${item.badge} pending' : item.label,
      child: PressableScale(
        onTap: onTap,
        pressedScale: 0.97,
        haptic: HapticStrength.selection,
        child: AnimatedContainer(
          duration: AppleDuration.standard,
          curve: AppleCurves.standard,
          padding: EdgeInsets.symmetric(
              horizontal: extended ? GwdSpace.md : GwdSpace.sm, vertical: GwdSpace.md),
          decoration: BoxDecoration(
            color: selected ? GwdColors.primaryRed : Colors.transparent,
            borderRadius: BorderRadius.circular(GwdRadius.md),
          ),
          child: Row(
            mainAxisAlignment: extended ? MainAxisAlignment.start : MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(selected ? item.activeIcon : item.icon, size: 21, color: color),
                  if (item.badge > 0)
                    Positioned(
                      top: -7,
                      right: -11,
                      child: _Badge(item: item, selected: selected),
                    ),
                ],
              ),
              if (extended) ...[
                const SizedBox(width: GwdSpace.md),
                Expanded(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GwdType.callout.copyWith(
                      color: color,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ClubNavBar extends StatelessWidget {
  const _ClubNavBar({required this.index, required this.items, required this.onChanged});

  /// The bar's own height, excluding the system inset it sits on.
  ///
  /// Public to the library so the shell can reserve exactly this much bottom
  /// padding for the pages underneath — two places agreeing on one number
  /// rather than a literal copied into both and drifting.
  static const height = 60.0;

  final int index;
  final List<NavItem> items;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Solid. It was frosted glass over the content: a 24-sigma blur of
    // whatever scrolled beneath it, recomputed on every frame of every scroll,
    // on every screen — the single most expensive thing in the app, spent on
    // a bar. And it only worked by letting content run underneath the bar,
    // which is how the last rows of every list ended up hidden behind it.
    //
    // Its labels scale with the system text size only so far: the bar is a
    // fixed 60 high, and at 1.5x or 2x text the icon, label and bracket rule
    // no longer fit in it. Tab bars everywhere cap this the same way.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.15,
      child: ClipRect(
        child: RepaintBoundary(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0E0B0C) : GwdColors.surfaceOf(context),
              border: Border(
                top: BorderSide(color: GwdColors.hairlineOf(context).withValues(alpha: 0.9)),
              ),
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: height,
                child: Row(
                  children: [
                    for (var i = 0; i < items.length; i++)
                      Expanded(
                        child: _NavButton(
                          item: items[i],
                          selected: i == index,
                          onTap: () => onChanged(i),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.item, required this.selected, required this.onTap});

  final NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? GwdColors.inkOf(context) : GwdColors.inkTertiaryOf(context);

    return Semantics(
      button: true,
      selected: selected,
      label: item.badge > 0 ? '${item.label}, ${item.badge} pending' : item.label,
      child: PressableScale(
        onTap: onTap,
        pressedScale: 0.94,
        haptic: HapticStrength.selection,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedSwitcher(
                  duration: AppleDuration.fast,
                  child: Icon(
                    selected ? item.activeIcon : item.icon,
                    key: ValueKey(selected),
                    size: 21,
                    color: color,
                  ),
                ),
                if (item.badge > 0)
                  Positioned(
                    top: -7,
                    right: -11,
                    child: _Badge(item: item, selected: false),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: AppleDuration.fast,
              style: GwdType.micro.copyWith(
                color: color,
                letterSpacing: 0.1,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
              child: Text(item.label),
            ),
            // The selected tab gets a short bracket rule rather than a generic
            // pill — a small piece of the logo, doing real work.
            //
            // Clamped: the overshoot that makes it spring open also carried it
            // past zero on the way closed, a negative width that is an error in
            // a debug build and a flicker in a release one.
            TweenAnimationBuilder<double>(
              tween: Tween(end: selected ? 16 : 0),
              duration: AppleDuration.standard,
              curve: AppleCurves.overshoot,
              builder: (context, width, _) => Container(
                margin: const EdgeInsets.only(top: 3),
                height: 2,
                width: width.clamp(0.0, 24.0),
                decoration: BoxDecoration(
                  color: GwdColors.primaryRed,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.item, required this.selected});
  final NavItem item;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    // No ring around it any more.
    //
    // The ring was `surfaceOf` — an opaque colour, drawn to separate the badge
    // from the glyph behind it. That worked while the bar was opaque. The bar
    // is frosted over the backdrop now, so the ring painted a solid grey collar
    // that matched nothing, and with the badge sitting on the icon the whole
    // thing read as a clipping artifact. Clearing the glyph does the separating
    // instead, which needs no colour at all.
    final fill = selected
        ? Colors.white
        : (item.accentBadge ? GwdColors.primaryRed : GwdColors.inkOf(context));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      constraints: const BoxConstraints(minWidth: 16),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(GwdRadius.pill),
      ),
      child: Text(
        item.badge > 99 ? '99+' : '${item.badge}',
        textAlign: TextAlign.center,
        style: GwdType.micro.copyWith(
          color: selected
              ? GwdColors.primaryRed
              : (item.accentBadge ? Colors.white : GwdColors.canvasOf(context)),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
