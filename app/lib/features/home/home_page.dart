import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme/apple_motion.dart';
import '../../app/theme/gwd_theme.dart';
import '../../app/widgets/common.dart';
import '../../core/api/socket_client.dart';
import '../../core/models/club_event.dart';
import '../../core/models/club_role.dart';
import '../../core/models/club_task.dart';
import '../../core/models/department.dart';
import '../../core/state/club_store.dart';
import '../alerts/send_alert_sheet.dart';
import '../approvals/approvals_page.dart';
import '../events/create_event_flow.dart';
import '../events/event_workspace_page.dart';
import '../events/events_page.dart' show EventCard;
import '../help/ask_for_help_sheet.dart';
import '../help/help_page.dart';
import '../profile/profile_sheet.dart';
import '../schedule/schedule_editor.dart';
import '../schedule/schedule_page.dart';
import '../tasks/new_task_sheet.dart';
import '../tasks/task_detail_page.dart';

/// Home — the command centre.
///
/// Answers one question, in order of urgency: *what should I be doing?* Today,
/// then what is coming, then your own work, then what is waiting on you, then
/// the club around you.
///
/// It carries a lot — but still exactly **one** primary decision: the "what's
/// next" card. Everything else is a labelled, scannable row. That is the whole
/// trick: more *information* does not have to mean more *decisions*.
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
    final needsYou = store.pendingApprovals.length + openRequests;

    final live = store.eventsOngoing;
    final soon = store.eventsUpcoming.take(3).toList();
    // Other people's open asks. Yours are not "someone needs a hand" — you
    // already know about yours.
    final helpNeeded =
        store.openHelp.where((h) => !h.mine && !h.helping).take(2).toList();

    var step = 0;
    int next() => step++;

    return Scaffold(
      backgroundColor: GwdColors.canvasOf(context),
      body: RefreshIndicator(
        color: GwdColors.primaryRed,
        onRefresh: () => store.loadAll(silent: true),
        child: ListView(
          padding: EdgeInsets.fromLTRB(gutter, 0, gutter, GwdSpace.xxxl),
          children: [
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.only(top: GwdSpace.lg),
                child: AppleStaggerItem(index: next(), child: _Header(store: store)),
              ),
            ),

            // ---------- anything live takes the whole width ----------
            if (live.isNotEmpty) ...[
              const SizedBox(height: GwdSpace.xl),
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
            const SizedBox(height: GwdSpace.xxl),
            AppleStaggerItem(
              index: next(),
              child: SectionHeader(
                title: "What's next",
                subtitle: store.whatsNext.isEmpty
                    ? null
                    : 'The one thing worth your attention right now',
              ),
            ),
            AppleStaggerItem(
              index: next(),
              child: _WhatsNextCard(
                store: store,
                onOpenSchedule: () => _openSchedule(context),
              ),
            ),

            // ---------- today ----------
            if (store.today.isNotEmpty) ...[
              const SizedBox(height: GwdSpace.xxl),
              AppleStaggerItem(
                index: next(),
                child: SectionHeader(
                  title: 'Today',
                  subtitle: '${store.today.length} on the schedule',
                  trailing: _More(onTap: () => _openSchedule(context)),
                ),
              ),
              AppleStaggerItem(
                index: next(),
                child: _TodayStrip(
                  items: store.today,
                  onOpenTask: (id) => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => TaskDetailPage(taskId: id)),
                  ),
                  onOpenSchedule: () => _openSchedule(context),
                ),
              ),
            ],

            // ---------- what the club is putting on ----------
            if (soon.isNotEmpty) ...[
              const SizedBox(height: GwdSpace.xxl),
              AppleStaggerItem(
                index: next(),
                child: SectionHeader(
                  title: 'Coming up',
                  subtitle: 'What the club is putting on',
                  trailing: _More(onTap: () => onNavigate(1)),
                ),
              ),
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

            // ---------- things waiting on you ----------
            if (needsYou > 0) ...[
              const SizedBox(height: GwdSpace.xxl),
              AppleStaggerItem(
                index: next(),
                child: const SectionHeader(
                    title: 'Needs you', subtitle: 'Nobody else can action these'),
              ),
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
                  child: _ActionRow(
                    icon: Icons.pan_tool_alt_outlined,
                    tint: GwdColors.warning,
                    title: '$openRequests task request${openRequests == 1 ? '' : 's'}',
                    subtitle: 'Accept or decline',
                    onTap: () => onNavigate(2),
                  ),
                ),
            ],

            // ---------- somebody is stuck ----------
            if (helpNeeded.isNotEmpty) ...[
              const SizedBox(height: GwdSpace.xxl),
              AppleStaggerItem(
                index: next(),
                child: SectionHeader(
                  title: 'Someone needs a hand',
                  subtitle: 'Five minutes from you might unblock them',
                  trailing: _More(
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => const HelpPage())),
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
            ],

            // ---------- quick actions ----------
            const SizedBox(height: GwdSpace.xxl),
            AppleStaggerItem(
              index: next(),
              child: const SectionHeader(title: 'Quick actions'),
            ),
            AppleStaggerItem(
              index: next(),
              child: _QuickActions(caps: caps, canCreateEvents: store.canCreateEvents),
            ),

            // ---------- your week ----------
            if (caps.earnsPoints) ...[
              const SizedBox(height: GwdSpace.xxl),
              AppleStaggerItem(
                index: next(),
                child: const SectionHeader(
                    title: 'Your week', subtitle: 'Finished against everything on your plate'),
              ),
              AppleStaggerItem(
                index: next(),
                child: _WeekCard(store: store, onOpenTasks: () => onNavigate(2)),
              ),
            ],

            // ---------- departments ----------
            if (store.departments.isNotEmpty) ...[
              const SizedBox(height: GwdSpace.xxl),
              AppleStaggerItem(
                index: next(),
                child: SectionHeader(
                  title: 'Across the club',
                  subtitle: 'How each department is getting on',
                  trailing: _More(
                    label: 'All',
                    onTap: () => onNavigate(3),
                  ),
                ),
              ),
              AppleStaggerItem(
                index: next(),
                child: _DepartmentStrip(store: store, onOpenAll: () => onNavigate(3)),
              ),
            ],

            if (me != null && me.role.isSupervisor) ...[
              const SizedBox(height: GwdSpace.xxl),
              AppleStaggerItem(index: next(), child: _SupervisorNote(role: me.role)),
            ],
          ],
        ),
      ),
    );
  }

  /// The schedule lives under More now, so Home pushes it rather than
  /// switching to a tab that no longer exists.
  void _openSchedule(BuildContext context) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => const SchedulePage()));
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
                    Text('TODAY',
                        style: GwdType.eyebrow.copyWith(color: Colors.white)),
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
                    style: GwdType.footnote
                        .copyWith(color: Colors.white.withValues(alpha: 0.85)),
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
                    style: GwdType.numeric
                        .copyWith(fontSize: 12, color: Colors.white)),
              ),
          ],
        ),
      ),
    );
  }
}

/// Greeting, identity, points.
class _Header extends StatelessWidget {
  const _Header({required this.store});
  final ClubStore store;

  @override
  Widget build(BuildContext context) {
    final session = AppScope.sessionOf(context);
    final me = session.me;
    final role = me?.role ?? ClubRole.clubMember;

    // "Good morning, President" — the office, not an honorific. Guessing
    // someone's title from their name or gender and getting it wrong every
    // single morning is worse than the formality it would buy.
    final greeting = role.hasAddress
        ? '${_timeGreeting()}, ${role.address}'
        : _timeGreeting();

    return Row(
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
                      greeting,
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
              // "Marketing Lead". The badge and the department name used to sit
              // side by side underneath, which made the reader assemble the
              // sentence themselves and read as "Lead" plus an unrelated word.
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
                  style: GwdType.footnote
                      .copyWith(color: GwdColors.inkTertiaryOf(context)),
                ),
            ],
          ),
        ),
        const SizedBox(width: GwdSpace.md),
        // Supervisors do not collect points, so they are not shown a score.
        if (store.capabilities.earnsPoints) ...[
          _PointsPill(points: me?.points ?? 0),
          const SizedBox(width: GwdSpace.sm),
        ],
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
    );
  }

  static String _timeGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }
}

class _PointsPill extends StatelessWidget {
  const _PointsPill({required this.points});
  final int points;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$points points',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: GwdSpace.md, vertical: 8),
        decoration: BoxDecoration(
          color: GwdColors.sunkenOf(context),
          borderRadius: BorderRadius.circular(GwdRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome_outlined,
                size: 12, color: GwdColors.inkTertiaryOf(context)),
            const SizedBox(width: 5),
            AnimatedCounter(
              value: points,
              style: GwdType.callout.copyWith(
                color: GwdColors.inkOf(context),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
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
      return SurfaceCard(
        padding: const EdgeInsets.symmetric(
            horizontal: GwdSpace.lg, vertical: GwdSpace.xxl),
        child: EmptyState(
          compact: true,
          icon: Icons.check_circle_outline,
          title: "You're all clear",
          message: store.loadError ??
              'Nothing is waiting on you. New work shows up here the moment it lands.',
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
              GwdChip(
                  label: entry.categoryName.toUpperCase(),
                  color: entry.tint,
                  icon: entry.icon),
              const Spacer(),
              Text(entry.relativeLabel,
                  style: GwdType.caption
                      .copyWith(color: GwdColors.inkTertiaryOf(context))),
            ],
          ),
          const SizedBox(height: GwdSpace.md),
          Text(entry.title,
              style: GwdType.title2.copyWith(color: GwdColors.inkOf(context))),
          if (entry.location.isNotEmpty) ...[
            const SizedBox(height: GwdSpace.xs),
            Row(
              children: [
                Icon(Icons.place_outlined,
                    size: 13, color: GwdColors.inkTertiaryOf(context)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(entry.location,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GwdType.footnote
                          .copyWith(color: GwdColors.inkSecondaryOf(context))),
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
                style: GwdType.callout
                    .copyWith(color: GwdColors.inkSecondaryOf(context))),
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
    required this.onOpenSchedule,
  });

  final List<TodayItem> items;
  final void Function(String taskId) onOpenTask;
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
              onTap: () => item.taskId != null
                  ? onOpenTask(item.taskId!)
                  : onOpenSchedule(),
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
class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.caps, required this.canCreateEvents});
  final Capabilities caps;
  final bool canCreateEvents;

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
      if (caps.canEditSchedule)
        _Action(
          icon: Icons.event_available_outlined,
          label: 'Schedule',
          tint: GwdColors.info,
          onTap: () => showScheduleEditor(context),
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
                      child: i < rows[r].length
                          ? rows[r][i]
                          : const SizedBox.shrink(),
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

class _WeekCard extends StatelessWidget {
  const _WeekCard({required this.store, required this.onOpenTasks});
  final ClubStore store;
  final VoidCallback onOpenTasks;

  @override
  Widget build(BuildContext context) {
    final p = store.progress;
    return SurfaceCard(
      onTap: onOpenTasks,
      child: Row(
        children: [
          ProgressArc(
            progress: p.ratio.clamp(0.0, 1.0),
            color: GwdColors.success,
            size: 58,
            child: Text(
              '${(p.ratio * 100).round()}%',
              style: GwdType.caption.merge(GwdType.numeric).copyWith(
                    fontSize: 13,
                    color: GwdColors.inkOf(context),
                  ),
            ),
          ),
          const SizedBox(width: GwdSpace.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  p.total == 0
                      ? 'Nothing on your plate'
                      : '${p.done} of ${p.total} done',
                  style: GwdType.title3.copyWith(color: GwdColors.inkOf(context)),
                ),
                const SizedBox(height: 3),
                Text(
                  p.total == 0
                      ? 'Work assigned to you this week appears here.'
                      : '${store.pendingCount} pending · ${store.inProgressCount} in progress',
                  style: GwdType.footnote
                      .copyWith(color: GwdColors.inkTertiaryOf(context)),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded,
              size: 20, color: GwdColors.inkTertiaryOf(context)),
        ],
      ),
    );
  }
}

/// Department progress, on Home.
///
/// A horizontal row of coloured initials looked like decoration and said
/// nothing. Department progress is open to every member by design, so this
/// shows the number that actually matters — how much of each department's work
/// has landed — and links into the full structure.
class _DepartmentStrip extends StatelessWidget {
  const _DepartmentStrip({required this.store, required this.onOpenAll});
  final ClubStore store;
  final VoidCallback onOpenAll;

  @override
  Widget build(BuildContext context) {
    // Alphabetical, never by how well anyone is doing. Sorting departments by
    // completion turns a progress panel into a league table, which Section 31
    // is explicit about not building.
    final departments = store.departments.where((d) => d.active).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final shown = departments.take(4).toList();

    return SurfaceCard(
      onTap: onOpenAll,
      child: Column(
        children: [
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) const SizedBox(height: GwdSpace.md),
            _DepartmentRow(department: shown[i]),
          ],
          if (departments.length > shown.length) ...[
            const SizedBox(height: GwdSpace.md),
            Row(
              children: [
                Text(
                  '+${departments.length - shown.length} more',
                  style: GwdType.footnote
                      .copyWith(color: GwdColors.inkTertiaryOf(context)),
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

class _DepartmentRow extends StatelessWidget {
  const _DepartmentRow({required this.department});
  final Department department;

  @override
  Widget build(BuildContext context) {
    final rate = department.completionRate;
    final tint = rate >= 80
        ? GwdColors.success
        : rate >= 50
            ? GwdColors.info
            : rate > 0
                ? GwdColors.warning
                : GwdColors.inkTertiaryOf(context);

    return Row(
      children: [
        SizedBox(
          width: 104,
          child: Text(
            department.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GwdType.callout.copyWith(color: GwdColors.inkOf(context)),
          ),
        ),
        const SizedBox(width: GwdSpace.sm),
        Expanded(
          child: TweenAnimationBuilder<double>(
            duration: AppleDuration.deliberate,
            curve: AppleCurves.standard,
            tween: Tween(
                begin: 0,
                end: department.assigned == 0
                    ? 0
                    : department.completed / department.assigned),
            builder: (context, t, _) => Container(
              height: 7,
              decoration: BoxDecoration(
                color: GwdColors.sunkenOf(context),
                borderRadius: BorderRadius.circular(GwdRadius.pill),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: t.clamp(0.0, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: tint,
                    borderRadius: BorderRadius.circular(GwdRadius.pill),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: GwdSpace.md),
        SizedBox(
          width: 58,
          child: Text(
            department.assigned == 0
                ? 'no work'
                : '${department.completed}/${department.assigned}',
            textAlign: TextAlign.right,
            style: GwdType.footnote.merge(GwdType.numeric).copyWith(
                  color: GwdColors.inkTertiaryOf(context),
                ),
          ),
        ),
      ],
    );
  }
}

/// points area just looks like a bug.
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

              style: GwdType.footnote
                  .copyWith(color: GwdColors.inkTertiaryOf(context)),
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
                Text(title,
                    style: GwdType.headline.copyWith(color: GwdColors.inkOf(context))),
                Text(subtitle,
                    style: GwdType.footnote
                        .copyWith(color: GwdColors.inkTertiaryOf(context))),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded,
              size: 20, color: GwdColors.inkTertiaryOf(context)),
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
      child: Text(label,
          style: GwdType.footnote.copyWith(color: GwdColors.primaryRed)),
    );
  }
}
