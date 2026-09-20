import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/responsive.dart';
import '../../app/theme/apple_motion.dart';
import '../../app/theme/gwd_theme.dart';
import '../../app/widgets/charts.dart';
import '../../app/widgets/common.dart';
import '../../core/api/socket_client.dart';
import '../../core/models/club_event.dart';
import '../../core/models/club_role.dart';
import '../../core/models/club_task.dart';
import '../../core/state/club_store.dart';
import '../alerts/send_alert_sheet.dart';
import '../approvals/approvals_page.dart';
import '../events/create_event_flow.dart';
import '../events/event_workspace_page.dart';
import '../events/events_page.dart' show EventCard;
import '../help/ask_for_help_sheet.dart';
import '../help/help_page.dart';
import '../meetings/meeting_detail_page.dart';
import '../meetings/new_meeting_sheet.dart';
import '../profile/profile_sheet.dart';
import '../schedule/schedule_editor.dart';
import '../schedule/schedule_page.dart';
import '../search/search_page.dart';
import '../tasks/new_task_sheet.dart';
import '../tasks/task_detail_page.dart';

/// Home — the command centre.
///
/// Answers one question, in order of urgency: *what should I be doing?*
///
/// The screen opens on a coloured hero carrying who you are and the three
/// numbers that describe your week, then the one focal decision, then what is
/// waiting on you, then the club around you. Everything below the hero shares a
/// single left edge and a single card shape, and every block is introduced by
/// the same small-caps label.
///
/// That uniformity is doing real work. The earlier version stacked nine
/// sections of equal weight, each with its own editorial subtitle, and it read
/// as nine things shouting at the same volume — the reported complaint was that
/// Home was confusing before you had read a word of it. A reader can only find
/// the important thing on a screen if the unimportant things agree to look
/// alike.
///
/// It still carries a lot, and still offers exactly **one** primary decision:
/// the "what's next" card. More *information* does not have to mean more
/// *decisions*.
class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.onNavigate});

  /// Switches the shell's tab, so quick links feel instant rather than pushing
  /// a duplicate route on top.
  /// 0 Home · 1 Events · 2 Work · 3 Departments · 4 More
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.storeOf(context);
    final session = AppScope.sessionOf(context);
    final me = session.me;
    final caps = store.capabilities;
    final gutter = GwdSpace.gutter(MediaQuery.sizeOf(context).width);

    final openRequests = store.incomingRequests.where((r) => r.isPending).length;
    final live = store.eventsOngoing;
    final soon = store.eventsUpcoming.take(2).toList();
    // Other people's open asks. Yours are not "someone needs a hand" — you
    // already know about yours.
    final helpNeeded = store.openHelp.where((h) => !h.mine && !h.helping).take(2).toList();
    final needsYou =
        store.pendingApprovals.isNotEmpty || openRequests > 0 || helpNeeded.isNotEmpty;

    var step = 0;
    int next() => step++;

    // Every block introduces itself the same way, and everything below the hero
    // lines up on one left edge. Alignment is most of what separates a screen
    // you can skim from one you have to read.
    Widget band(String title, {String? subtitle, Widget? trailing}) => AppleStaggerItem(
          index: next(),
          child: Padding(
            padding: const EdgeInsets.only(top: GwdSpace.xxl),
            child: SectionHeader(title: title, subtitle: subtitle, trailing: trailing),
          ),
        );

    return Scaffold(
      // Transparent so the shell's wash shows through; see ClubShell.
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        color: GwdColors.primaryRed,
        onRefresh: () => store.loadAll(silent: true),
        // Capped on a wide window like every other screen. Without this, Home
        // — the one people open most, and the one the web build lands on —
        // stretched its rows the full width of a desktop browser while the
        // Schedule and Meetings beside it stayed readable.
        child: ContentWidth(
          child: ListView(
            padding: const EdgeInsets.only(bottom: GwdSpace.xxxl),
            children: [
              _HomeHero(store: store, gutter: gutter, onNavigate: onNavigate),

              Padding(
                padding: EdgeInsets.symmetric(horizontal: gutter),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ---------- happening right now ----------
                    if (live.isNotEmpty) ...[
                      band('Happening now'),
                      for (final event in live)
                        AppleStaggerItem(
                          index: next(),
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: GwdSpace.sm),
                            child: _LiveEventBanner(
                              event: event,
                              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => EventWorkspacePage(eventId: event.id),
                              )),
                            ),
                          ),
                        ),
                    ],

                    // ---------- the one focal decision ----------
                    band("What's next"),
                    AppleStaggerItem(
                      index: next(),
                      child: _WhatsNextCard(
                        store: store,
                        onOpenSchedule: () => _openSchedule(context),
                      ),
                    ),

                    // ---------- things only you can clear ----------
                    //
                    // Approvals, task requests and other people's asks used to
                    // be three sections with three headings. They are one
                    // question — what is sitting in my court — and reading as
                    // one list is what makes it answerable.
                    if (needsYou) ...[
                      band('Needs you', subtitle: 'Nobody else can action these'),
                      if (store.pendingApprovals.isNotEmpty)
                        AppleStaggerItem(
                          index: next(),
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: GwdSpace.sm),
                            child: _ActionRow(
                              icon: Icons.how_to_reg_outlined,
                              tint: GwdColors.primaryRed,
                              title: '${store.pendingApprovals.length} waiting to join',
                              subtitle: 'Approve or decline',
                              onTap: () => Navigator.of(context)
                                  .push(MaterialPageRoute(builder: (_) => const ApprovalsPage())),
                            ),
                          ),
                        ),
                      if (openRequests > 0)
                        AppleStaggerItem(
                          index: next(),
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: GwdSpace.sm),
                            child: _ActionRow(
                              icon: Icons.pan_tool_alt_outlined,
                              tint: GwdColors.warning,
                              title: '$openRequests task request${openRequests == 1 ? '' : 's'}',
                              subtitle: 'Accept or decline',
                              onTap: () => onNavigate(2),
                            ),
                          ),
                        ),
                      for (final request in helpNeeded)
                        AppleStaggerItem(
                          index: next(),
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: GwdSpace.sm),
                            child: HelpCard(request: request),
                          ),
                        ),
                      if (helpNeeded.isNotEmpty)
                        AppleStaggerItem(
                          index: next(),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: _More(
                              label: 'Everyone asking',
                              onTap: () => Navigator.of(context)
                                  .push(MaterialPageRoute(builder: (_) => const HelpPage())),
                            ),
                          ),
                        ),
                    ],

                    // ---------- today ----------
                    if (store.today.isNotEmpty) ...[
                      band(
                        'Today',
                        subtitle: '${store.today.length} on the schedule',
                        trailing: _More(onTap: () => _openSchedule(context)),
                      ),
                      AppleStaggerItem(
                        index: next(),
                        child: _TodayStrip(
                          items: store.today,
                          onOpenTask: (id) => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => TaskDetailPage(taskId: id)),
                          ),
                          onOpenMeeting: (id) => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => MeetingDetailPage(meetingId: id)),
                          ),
                          onOpenSchedule: () => _openSchedule(context),
                        ),
                      ),
                    ],

                    // ---------- what the club is putting on ----------
                    if (soon.isNotEmpty) ...[
                      band('Coming up', trailing: _More(onTap: () => onNavigate(1))),
                      for (final event in soon)
                        AppleStaggerItem(
                          index: next(),
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: GwdSpace.sm),
                            child: EventCard(
                              event: event,
                              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => EventWorkspacePage(eventId: event.id),
                              )),
                            ),
                          ),
                        ),
                    ],

                    // ---------- your own week, drawn ----------
                    if (caps.earnsPoints) ...[
                      band('Your work', trailing: _More(label: 'Open', onTap: () => onNavigate(2))),
                      AppleStaggerItem(
                        index: next(),
                        child: _YourWorkCard(store: store, onOpenTasks: () => onNavigate(2)),
                      ),
                    ],

                    // ---------- departments ----------
                    if (store.departments.isNotEmpty) ...[
                      band(
                        'Across the club',
                        subtitle: 'How each department is getting on',
                        trailing: _More(label: 'All', onTap: () => onNavigate(3)),
                      ),
                      AppleStaggerItem(
                        index: next(),
                        child: _DepartmentStrip(store: store, onOpenAll: () => onNavigate(3)),
                      ),
                    ],

                    // ---------- start something ----------
                    band('Start something'),
                    AppleStaggerItem(
                      index: next(),
                      child: _QuickActions(
                        caps: caps,
                        canCreateEvents: store.canCreateEvents,
                        canScheduleMeetings: store.canScheduleMeetings,
                        onOpenSchedule: () => _openSchedule(context),
                      ),
                    ),

                    if (me != null && me.role.isSupervisor) ...[
                      const SizedBox(height: GwdSpace.xxl),
                      AppleStaggerItem(index: next(), child: _SupervisorNote(role: me.role)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The schedule lives under More now, so Home pushes it rather than
  /// switching to a tab that no longer exists.
  void _openSchedule(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SchedulePage()));
}

/// An event happening today, on Home.
///
/// Deliberately unlike every other card here: on the day, this should be the
/// only thing your eye lands on.
class _LiveEventBanner extends StatelessWidget {
  const _LiveEventBanner({required this.event, required this.onTap});
  final ClubEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tint = event.bannerColor;
    return PressableScale(
      onTap: onTap,
      haptic: HapticStrength.light,
      child: Container(
        padding: const EdgeInsets.all(GwdSpace.lg),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(GwdRadius.xl),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [tint, Color.lerp(tint, Colors.black, 0.34)!],
          ),
          boxShadow: GwdShadow.accent(tint),
        ),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const BreathingDot(color: Colors.white, size: 6),
                    const SizedBox(width: 6),
                    Text('TODAY', style: GwdType.eyebrow.copyWith(color: Colors.white)),
                  ],
                ),
                const SizedBox(height: 5),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: Text(
                    event.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GwdType.title3.copyWith(color: Colors.white),
                  ),
                ),
                if (event.venue.isNotEmpty || event.timeLabel.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    [
                      if (event.timeLabel.isNotEmpty) event.timeLabel,
                      if (event.venue.isNotEmpty) event.venue,
                    ].join('  ·  '),
                    style: GwdType.footnote.copyWith(color: Colors.white.withValues(alpha: 0.85)),
                  ),
                ],
              ],
            ),
            const Spacer(),
            if (event.taskCount > 0)
              ProgressArc(
                progress: event.progress / 100,
                size: 50,
                strokeWidth: 4,
                color: Colors.white,
                trackColor: Colors.white.withValues(alpha: 0.26),
                child: Text('${event.progress}%',
                    style: GwdType.numeric.copyWith(fontSize: 12, color: Colors.white)),
              ),
          ],
        ),
      ),
    );
  }
}

/// The top of Home: who you are, and the three numbers that describe your week.
///
/// No background of its own. The app's backdrop is near-black up here and warms
/// as it falls, so the hero is the quiet end of the screen and the colour is
/// somewhere below — which is the right way round. A coloured panel at the top
/// of the one screen people open forty times a day is a thing you get tired of.
///
/// The three figures are the dashboard the app was missing. Opening a club app
/// and having to visit three tabs to find out whether you are behind is the
/// difference between a tool and a filing cabinet.
class _HomeHero extends StatelessWidget {
  const _HomeHero({required this.store, required this.gutter, required this.onNavigate});

  final ClubStore store;
  final double gutter;
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    final session = AppScope.sessionOf(context);
    final me = session.me;
    final caps = store.capabilities;

    final open = store.myTasks.where((t) => t.status.isOpen).toList();
    final horizon = DateTime.now().add(const Duration(days: 7));
    // Overdue counts as due. Work that slipped past its date is the most due
    // thing you own, and dropping it out of the figure is how it gets forgotten.
    final due = open.where((t) => t.dueDate != null && t.dueDate!.isBefore(horizon)).length;

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(gutter, GwdSpace.lg, gutter, GwdSpace.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              _timeGreeting(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GwdType.callout
                                  .copyWith(color: GwdColors.inkSecondaryOf(context)),
                            ),
                          ),
                          const SizedBox(width: GwdSpace.sm),
                          LiveDot(connected: store.liveStatus == LiveStatus.connected),
                        ],
                      ),
                      const SizedBox(height: 2),
                      // The name, then what they are and where — "Abdul" over
                      // "Marketing Lead". A role badge beside a department name
                      // makes the reader assemble the sentence, and reads as
                      // "Lead" plus an unrelated word.
                      Text(
                        me?.displayName ?? 'There',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GwdType.largeTitle.copyWith(
                          color: me?.isUnnamed == true
                              ? GwdColors.inkTertiaryOf(context)
                              : GwdColors.inkOf(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (me != null)
                        Text(
                          me.positionLine(session.department?.name),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              GwdType.footnote.copyWith(color: GwdColors.inkTertiaryOf(context)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: GwdSpace.sm),
                // Search sits next to the avatar because this is the screen
                // everybody lands on, and "where is that person / event / task"
                // is a question the app had no answer to at all.
                PressableScale(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SearchPage()),
                  ),
                  child: Semantics(
                    button: true,
                    label: 'Search the club',
                    child: Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: GwdColors.sunkenOf(context),
                        shape: BoxShape.circle,
                        border: Border.all(color: GwdColors.hairlineOf(context)),
                      ),
                      child: Icon(Icons.search_rounded,
                          size: 20, color: GwdColors.inkSecondaryOf(context)),
                    ),
                  ),
                ),
                const SizedBox(width: GwdSpace.sm),
                PressableScale(
                  onTap: () => showProfileSheet(context),
                  child: Semantics(
                    button: true,
                    label: 'Profile and settings',
                    child: Avatar(
                      initials: me?.initials ?? '?',
                      tint: me?.tint ?? GwdColors.inkTertiary,
                      size: 44,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: GwdSpace.xl),
            Row(
              children: [
                Expanded(
                  child: _HeroStat(
                    value: open.length,
                    label: open.length == 1 ? 'task open' : 'tasks open',
                    onTap: () => onNavigate(2),
                  ),
                ),
                const SizedBox(width: GwdSpace.sm),
                Expanded(
                  child: _HeroStat(
                    value: due,
                    label: 'due this week',
                    tint: due > 0 ? GwdColors.warning : null,
                    onTap: () => onNavigate(2),
                  ),
                ),
                const SizedBox(width: GwdSpace.sm),
                Expanded(
                  // Supervisors do not collect points, so they are not shown a
                  // score they can never move.
                  child: caps.earnsPoints
                      ? _HeroStat(value: me?.points ?? 0, label: 'points earned')
                      : _HeroStat(
                          value: store.members.length,
                          label: 'in the club',
                          onTap: () => onNavigate(3),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _timeGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }
}

/// One figure in the hero.
///
/// The number is set in the display face at tabular width, so three tiles side
/// by side keep their digits on one baseline grid however the values change.
/// Counters that reflow as they tick read as unstable.
class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.value, required this.label, this.tint, this.onTap});

  final int value;
  final String label;
  final Color? tint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: GwdSpace.md, vertical: GwdSpace.md),
      borderRadius: GwdRadius.lg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedCounter(
            value: value,
            style: GwdType.title1.merge(GwdType.numeric).copyWith(
                  color: tint ?? GwdColors.inkOf(context),
                  height: 1.0,
                ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GwdType.micro.copyWith(color: GwdColors.inkTertiaryOf(context)),
          ),
        ],
      ),
    );

    if (onTap == null) return Semantics(label: '$value $label', child: card);
    return Semantics(
      button: true,
      label: '$value $label',
      child: PressableScale(onTap: onTap, child: card),
    );
  }
}

class _WhatsNextCard extends StatelessWidget {
  const _WhatsNextCard({required this.store, required this.onOpenSchedule});

  final ClubStore store;
  final VoidCallback onOpenSchedule;

  @override
  Widget build(BuildContext context) {
    if (store.loading && !store.hasLoadedOnce) {
      return const SkeletonList(count: 1, height: 150);
    }

    final next = store.whatsNext;
    if (next.isEmpty) {
      final failed = store.loadError != null;
      // Quiet, and one row tall.
      //
      // This was the full centred EmptyState inside a card that added its own
      // padding on top — a 570pt billboard announcing that nothing is wrong.
      // An empty focal slot is *good news*, and good news does not get to be
      // the largest thing on the screen; it should read as a clear desk, not
      // as a hole where the content failed to load.
      return SurfaceCard(
        padding: const EdgeInsets.all(GwdSpace.md + 2),
        borderColor: failed ? GwdColors.tintBorderOf(context, GwdColors.critical) : null,
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: GwdColors.tintOf(context, failed ? GwdColors.critical : GwdColors.success),
                shape: BoxShape.circle,
              ),
              child: Icon(failed ? Icons.wifi_off_rounded : GwdIcons.done,
                  size: 19, color: failed ? GwdColors.critical : GwdColors.success),
            ),
            const SizedBox(width: GwdSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(failed ? 'Cannot reach the server' : "You're all clear",
                      style: GwdType.headline.copyWith(color: GwdColors.inkOf(context))),
                  const SizedBox(height: 1),
                  Text(
                    store.loadError ?? 'Nothing is waiting on you right now.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GwdType.footnote.copyWith(color: GwdColors.inkTertiaryOf(context)),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final task = next.task;
    if (task != null) return _NextTaskCard(task: task, store: store);

    final entry = next.entry!;
    return SurfaceCard(
      emphasis: SurfaceEmphasis.raised,
      onTap: onOpenSchedule,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GwdChip(label: entry.categoryName.toUpperCase(), color: entry.tint, icon: entry.icon),
              const Spacer(),
              Text(entry.relativeLabel,
                  style: GwdType.caption.copyWith(color: GwdColors.inkTertiaryOf(context))),
            ],
          ),
          const SizedBox(height: GwdSpace.md),
          Text(entry.title, style: GwdType.title2.copyWith(color: GwdColors.inkOf(context))),
          if (entry.location.isNotEmpty) ...[
            const SizedBox(height: GwdSpace.xs),
            Row(
              children: [
                Icon(Icons.place_outlined, size: 13, color: GwdColors.inkTertiaryOf(context)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(entry.location,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GwdType.footnote.copyWith(color: GwdColors.inkSecondaryOf(context))),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _NextTaskCard extends StatefulWidget {
  const _NextTaskCard({required this.task, required this.store});
  final ClubTask task;
  final ClubStore store;

  @override
  State<_NextTaskCard> createState() => _NextTaskCardState();
}

class _NextTaskCardState extends State<_NextTaskCard> {
  bool _busy = false;

  Future<void> _advance() async {
    final next = widget.task.status.nextForOwner;
    if (next == null) return;
    setState(() => _busy = true);
    try {
      await widget.store.setTaskStatus(widget.task, next);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final overdue = task.isOverdue;

    return SurfaceCard(
      emphasis: overdue ? SurfaceEmphasis.live : SurfaceEmphasis.raised,
      accent: overdue ? GwdColors.critical : null,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => TaskDetailPage(taskId: task.id)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GwdChip(
                  label: task.status.label.toUpperCase(),
                  color: task.status.tint,
                  icon: task.status.icon),
              const Spacer(),
              if (task.dueLabel != null)
                Text(
                  task.dueLabel!,
                  style: GwdType.caption.copyWith(
                    color: overdue ? GwdColors.critical : GwdColors.inkTertiaryOf(context),
                  ),
                ),
            ],
          ),
          const SizedBox(height: GwdSpace.md),
          Text(task.title,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: GwdType.title2.copyWith(color: GwdColors.inkOf(context))),
          if (task.description.isNotEmpty) ...[
            const SizedBox(height: GwdSpace.xs),
            Text(task.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GwdType.callout.copyWith(color: GwdColors.inkSecondaryOf(context))),
          ],
          if (task.status.nextForOwner != null) ...[
            const SizedBox(height: GwdSpace.xl),
            PrimaryButton(
              label: task.status.advanceVerb,
              busy: _busy,
              icon: task.status == TaskStatus.inProgress
                  ? Icons.check_rounded
                  : Icons.play_arrow_rounded,
              onPressed: _advance,
            ),
          ],
        ],
      ),
    );
  }
}

class _TodayStrip extends StatelessWidget {
  const _TodayStrip({
    required this.items,
    required this.onOpenTask,
    required this.onOpenMeeting,
    required this.onOpenSchedule,
  });

  final List<TodayItem> items;
  final void Function(String taskId) onOpenTask;
  final void Function(String meetingId) onOpenMeeting;
  final VoidCallback onOpenSchedule;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final item in items.take(4))
          Padding(
            padding: const EdgeInsets.only(bottom: GwdSpace.sm),
            child: SurfaceCard(
              padding: const EdgeInsets.all(GwdSpace.md),
              // A deadline row and a meeting row are the real thing shown on
              // the schedule, so tapping opens the real thing. Only a genuine
              // schedule entry falls through to the calendar.
              onTap: () {
                if (item.taskId != null) return onOpenTask(item.taskId!);
                if (item.meetingId != null) return onOpenMeeting(item.meetingId!);
                onOpenSchedule();
              },
              child: Row(
                children: [
                  SizedBox(
                    width: 42,
                    child: Text(
                      item.timeLabel,
                      style: GwdType.callout.merge(GwdType.numeric).copyWith(
                            color: GwdColors.inkOf(context),
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  Container(
                    width: 3,
                    height: 26,
                    margin: const EdgeInsets.only(right: GwdSpace.md),
                    decoration: BoxDecoration(
                      color: item.tint,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GwdType.headline.copyWith(color: GwdColors.inkOf(context)),
                    ),
                  ),
                  Icon(item.icon, size: 14, color: item.tint),
                ],
              ),
            ),
          ),
        if (items.length > 4)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: PressableScale(
              haptic: HapticStrength.selection,
              onTap: onOpenSchedule,
              child: Text('${items.length - 4} more today',
                  style: GwdType.footnote.copyWith(color: GwdColors.primaryRed)),
            ),
          ),
      ],
    );
  }
}

/// The short list of things somebody starts from Home.
///
/// "I need help" is here for everyone, deliberately first for a plain Member:
/// it is the one action in the app that anybody can take, and burying it is how
/// the feature dies.
/// One option in a "which of these did you mean?" sheet.
class _SheetChoice extends StatelessWidget {
  const _SheetChoice({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      haptic: HapticStrength.light,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: GwdSpace.xl, vertical: GwdSpace.md),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: GwdColors.sunkenOf(context),
                borderRadius: BorderRadius.circular(GwdRadius.md),
              ),
              child: Icon(icon, size: 19, color: GwdColors.inkOf(context)),
            ),
            const SizedBox(width: GwdSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: GwdType.headline.copyWith(color: GwdColors.inkOf(context))),
                  Text(subtitle,
                      style: GwdType.footnote.copyWith(color: GwdColors.inkTertiaryOf(context))),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: GwdColors.inkTertiaryOf(context)),
          ],
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.caps,
    required this.canCreateEvents,
    required this.canScheduleMeetings,
    required this.onOpenSchedule,
  });
  final Capabilities caps;
  final bool canCreateEvents;
  final bool canScheduleMeetings;
  final VoidCallback onOpenSchedule;

  /// Add something, or go and look at what is already there.
  ///
  /// A sheet rather than opening one and hoping: both are reasonable things to
  /// want from a tile labelled "Schedule", and guessing wrong sends somebody
  /// into a form they have to back out of.
  Future<void> _chooseScheduleAction(BuildContext context) async {
    final choice = await showGwdSheet<String>(
      context: context,
      builder: (sheetContext) => Container(
        decoration: BoxDecoration(
          color: GwdColors.surfaceOf(sheetContext),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(GwdRadius.xxl)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SheetHeader(title: 'Schedule'),
              _SheetChoice(
                icon: Icons.calendar_month_rounded,
                title: 'View the schedule',
                subtitle: 'Everything the club has coming up',
                onTap: () => Navigator.of(sheetContext).pop('view'),
              ),
              _SheetChoice(
                icon: Icons.add_rounded,
                title: 'Add to the schedule',
                subtitle: 'A meeting, a shoot, a rehearsal',
                onTap: () => Navigator.of(sheetContext).pop('add'),
              ),
              const SizedBox(height: GwdSpace.lg),
            ],
          ),
        ),
      ),
    );

    if (!context.mounted || choice == null) return;
    if (choice == 'view') {
      onOpenSchedule();
    } else {
      await showScheduleEditor(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[
      if (canCreateEvents)
        _Action(
          icon: Icons.event_rounded,
          label: 'Plan event',
          tint: GwdColors.primaryRed,
          onTap: () => CreateEventFlow.open(context),
        ),
      if (caps.canAssign)
        _Action(
          icon: Icons.add_task_rounded,
          label: 'Assign task',
          tint: GwdColors.rubyDark,
          onTap: () => showNewTaskSheet(context),
        ),
      _Action(
        icon: Icons.pan_tool_alt_outlined,
        label: 'Need help',
        tint: GwdColors.success,
        onTap: () => showAskForHelpSheet(context),
      ),
      // Shown to everybody. Reading the schedule is the commonest thing anyone
      // wants from it, and gating the whole tile behind `canEditSchedule` meant
      // a member had no way in at all — while for somebody who *can* edit, the
      // tile did only the rarer of the two jobs.
      _Action(
        icon: Icons.event_available_outlined,
        label: 'Schedule',
        tint: GwdColors.info,
        onTap: () {
          if (!caps.canEditSchedule) {
            onOpenSchedule();
            return;
          }
          _chooseScheduleAction(context);
        },
      ),
      // Only for the people who call meetings. For everybody else the meeting
      // they are expected at is already on the Today strip, and the list lives
      // in More — a tile that only ever means "go and look" does not earn a
      // place among four actions.
      if (canScheduleMeetings)
        _Action(
          icon: Icons.groups_2_outlined,
          label: 'Call meeting',
          tint: GwdColors.info,
          onTap: () => showNewMeetingSheet(context),
        ),
      if (caps.canBroadcast)
        _Action(
          icon: Icons.campaign_outlined,
          label: 'Send alert',
          tint: GwdColors.warning,
          onTap: () => showSendAlertSheet(context),
        ),
    ];

    // Four across is already tight on a small phone, so overflow wraps to a
    // second row rather than shrinking every tile until the labels clip.
    return LayoutBuilder(
      builder: (context, constraints) {
        final perRow = constraints.maxWidth >= 520 ? 5 : 3;
        final rows = <List<Widget>>[];
        for (var i = 0; i < actions.length; i += perRow) {
          rows.add(actions.sublist(i, (i + perRow).clamp(0, actions.length)));
        }
        return Column(
          children: [
            for (var r = 0; r < rows.length; r++) ...[
              if (r > 0) const SizedBox(height: GwdSpace.md),
              Row(
                children: [
                  for (var i = 0; i < perRow; i++) ...[
                    if (i > 0) const SizedBox(width: GwdSpace.md),
                    Expanded(
                      child: i < rows[r].length ? rows[r][i] : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.tint,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(vertical: GwdSpace.lg, horizontal: GwdSpace.sm),
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: tint),
          ),
          const SizedBox(height: GwdSpace.sm),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GwdType.footnote.copyWith(
              color: GwdColors.inkOf(context),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Your own work, drawn rather than described.
///
/// Two readings, because they answer different questions. The donut is *what
/// state is my work in* — the shape tells you at a glance whether you are
/// sitting on a pile of untouched tasks or a pile of nearly-finished ones,
/// which a single "62%" cannot. The columns are *when is it due*, which is the
/// question that actually decides what you do this afternoon.
///
/// Neither is a ranking and neither compares you to anybody. Same rule as every
/// other progress surface in the app.
class _YourWorkCard extends StatelessWidget {
  const _YourWorkCard({required this.store, required this.onOpenTasks});
  final ClubStore store;
  final VoidCallback onOpenTasks;

  @override
  Widget build(BuildContext context) {
    final mine = store.myTasks;
    final toDo = mine.where((t) => t.status == TaskStatus.pending).length;
    final doing = mine.where((t) => t.status == TaskStatus.inProgress).length;
    final review = mine.where((t) => t.status == TaskStatus.review).length;
    final blocked = mine.where((t) => t.status == TaskStatus.blocked).length;
    final done = mine.where((t) => t.status == TaskStatus.completed).length;
    final open = toDo + doing + review + blocked;

    if (mine.isEmpty) {
      return SurfaceCard(
        onTap: onOpenTasks,
        child: Row(
          children: [
            Icon(Icons.inbox_outlined, size: 22, color: GwdColors.inkTertiaryOf(context)),
            const SizedBox(width: GwdSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Nothing on your plate',
                      style: GwdType.headline.copyWith(color: GwdColors.inkOf(context))),
                  const SizedBox(height: 2),
                  Text('Work assigned to you appears here.',
                      style:
                          GwdType.footnote.copyWith(color: GwdColors.inkTertiaryOf(context))),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return SurfaceCard(
      onTap: onOpenTasks,
      padding: const EdgeInsets.all(GwdSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          DonutChart(
            centreValue: '$open',
            centreLabel: open == 1 ? 'still open' : 'still open',
            slices: [
              ChartSlice(label: 'To do', value: toDo, tint: GwdColors.inkTertiaryOf(context)),
              ChartSlice(label: 'In progress', value: doing, tint: GwdColors.primaryRed),
              ChartSlice(label: 'In review', value: review, tint: GwdColors.info),
              if (blocked > 0)
                ChartSlice(label: 'Blocked', value: blocked, tint: GwdColors.warning),
              ChartSlice(label: 'Done', value: done, tint: GwdColors.success),
            ],
          ),
          const SizedBox(height: GwdSpace.lg),
          Divider(height: 1, color: GwdColors.hairlineOf(context)),
          const SizedBox(height: GwdSpace.lg),
          Text(
            'DUE OVER THE NEXT WEEK',
            style: GwdType.eyebrow.copyWith(color: GwdColors.inkTertiaryOf(context)),
          ),
          const SizedBox(height: GwdSpace.md),
          ColumnChart(columns: _week(mine)),
        ],
      ),
    );
  }

  /// Seven days from today, counting open work by the day it is due.
  ///
  /// Anything already overdue lands on today rather than being dropped: it is
  /// not next week's problem, and a chart that quietly omits late work is
  /// telling its reader the most comforting available lie.
  static List<ChartColumn> _week(List<ClubTask> tasks) {
    const initials = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return List.generate(7, (i) {
      final day = today.add(Duration(days: i));
      final count = tasks.where((t) {
        if (!t.status.isOpen || t.dueDate == null) return false;
        final d = t.dueDate!;
        final due = DateTime(d.year, d.month, d.day);
        if (i == 0) return !due.isAfter(today);
        return due == day;
      }).length;
      return ChartColumn(
        label: initials[(day.weekday - 1) % 7],
        value: count,
        highlight: i == 0,
      );
    });
  }
}

/// Department progress, on Home.
///
/// Open to every member by design: a club where you cannot see what another
/// department is working on duplicates work. Aggregate only — how much of a
/// department's work has landed, never who inside it did what.
///
/// The name sits above its bar rather than in a fixed-width column beside it.
/// A column wide enough for "Cinematography" wastes half the row on "PR", and
/// one sized for "PR" truncates every other department in the club.
class _DepartmentStrip extends StatelessWidget {
  const _DepartmentStrip({required this.store, required this.onOpenAll});
  final ClubStore store;
  final VoidCallback onOpenAll;

  @override
  Widget build(BuildContext context) {
    // Alphabetical, never by how well anyone is doing. Sorting departments by
    // completion turns a progress panel into a league table.
    final departments = store.departments.where((d) => d.active).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final shown = departments.take(4).toList();

    // Every bar is read against the busiest department rather than against its
    // own total, so a department with two tasks finished does not draw the same
    // full bar as one that finished thirty. Percentages hide the size of the
    // job; this is comparing like with like.
    final busiest = shown.fold<int>(1, (m, d) => d.assigned > m ? d.assigned : m);

    return SurfaceCard(
      onTap: onOpenAll,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          BarChart(
            max: busiest,
            bars: [
              for (final d in shown)
                ChartBar(
                  label: d.name,
                  value: d.completed,
                  tint: d.assigned == 0
                      ? GwdColors.inkTertiaryOf(context)
                      : (d.completed >= d.assigned ? GwdColors.success : GwdColors.primaryRed),
                  caption: d.assigned == 0
                      ? 'nothing yet'
                      : '${d.completed} of ${d.assigned} done',
                ),
            ],
          ),
          if (departments.length > shown.length) ...[
            const SizedBox(height: GwdSpace.lg),
            Row(
              children: [
                Text(
                  '+${departments.length - shown.length} more',
                  style: GwdType.footnote.copyWith(color: GwdColors.inkTertiaryOf(context)),
                ),
                const Spacer(),
                Icon(Icons.chevron_right_rounded,
                    size: 16, color: GwdColors.inkTertiaryOf(context)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Why a supervisor has no score.
///
/// Directors and the Faculty Coordinator oversee the club rather than compete
/// in it, so they earn no points and are absent from the leaderboard. Without
/// a line saying so, an empty points area just looks like a bug.
class _SupervisorNote extends StatelessWidget {
  const _SupervisorNote({required this.role});
  final ClubRole role;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(GwdSpace.md),
      decoration: BoxDecoration(
        color: GwdColors.sunkenOf(context),
        borderRadius: BorderRadius.circular(GwdRadius.md),
      ),
      child: Row(
        children: [
          Icon(role.icon, size: 15, color: GwdColors.inkTertiaryOf(context)),
          const SizedBox(width: GwdSpace.md),
          Expanded(
            child: Text(
              'As ${role.title} you have full visibility across the club, and '
              'can award points to anyone.',
              style: GwdType.footnote.copyWith(color: GwdColors.inkTertiaryOf(context)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.tint,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color tint;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      emphasis: SurfaceEmphasis.live,
      accent: tint,
      onTap: onTap,
      padding: const EdgeInsets.all(GwdSpace.md),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: tint),
          ),
          const SizedBox(width: GwdSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: GwdType.headline.copyWith(color: GwdColors.inkOf(context))),
                Text(subtitle,
                    style: GwdType.footnote.copyWith(color: GwdColors.inkTertiaryOf(context))),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, size: 20, color: GwdColors.inkTertiaryOf(context)),
        ],
      ),
    );
  }
}

class _More extends StatelessWidget {
  const _More({required this.onTap, this.label = 'See all'});
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      haptic: HapticStrength.selection,
      onTap: onTap,
      child: Text(label, style: GwdType.footnote.copyWith(color: GwdColors.primaryRed)),
    );
  }
}
