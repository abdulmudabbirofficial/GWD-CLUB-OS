import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/responsive.dart';
import '../../app/theme/apple_motion.dart';
import '../../app/theme/gwd_theme.dart';
import '../../app/widgets/common.dart';
import '../../core/api/api_client.dart';
import '../../core/models/club_role.dart';
import '../../core/models/club_event.dart';
import '../../core/state/club_store.dart';
import 'event_board_tab.dart';
import 'event_departments_tab.dart';
import 'event_documents_tab.dart';
import 'event_finance_tab.dart';
import 'event_updates_tab.dart';

/// The event workspace.
///
/// Everything about one event in one place: what it is, the work under it, who
/// is carrying which part, its paperwork, and its history. Five tabs, because
/// each answers a different question and cramming them into one scroll makes
/// the thing unusable on the day.
class EventWorkspacePage extends StatefulWidget {
  const EventWorkspacePage({super.key, required this.eventId});
  final String eventId;

  @override
  State<EventWorkspacePage> createState() => _EventWorkspacePageState();
}

class _EventWorkspacePageState extends State<EventWorkspacePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 6, vsync: this);
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    // The store owns the data; this only asks it to fetch. Everything after
    // this — a socket event, somebody else moving a card — arrives through the
    // store and rebuilds this page for free.
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final store = AppScope.readStore(context);
    try {
      await Future.wait([
        store.loadEventWorkspace(widget.eventId),
        store.loadEventBoard(widget.eventId),
      ]);
    } on ApiException {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.storeOf(context);
    final workspace = store.workspaceFor(widget.eventId);

    if (workspace == null) {
      return Scaffold(
        backgroundColor: GwdColors.canvasOf(context),
        appBar: AppBar(),
        body: _failed
            ? EmptyState(
                icon: Icons.wifi_off_rounded,
                title: 'Could not open this event',
                message: 'Check the connection and try again.',
                action: SecondaryButton(
                  label: 'Retry',
                  icon: Icons.refresh_rounded,
                  onPressed: () {
                    setState(() => _failed = false);
                    _load();
                  },
                ),
              )
            : const Padding(
                padding: EdgeInsets.all(GwdSpace.xl),
                child: SkeletonList(count: 4, height: 92),
              ),
      );
    }

    final event = workspace.event;

    return Scaffold(
      backgroundColor: GwdColors.canvasOf(context),
      body: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          _EventHeader(workspace: workspace, eventId: widget.eventId),
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabBarHeader(
              child: _WorkspaceTabs(
                controller: _tabs,
                pendingApprovals: workspace.approvalsPending,
                owedCount:
                    store.financeFor(widget.eventId)?.awaitingDecision ?? 0,
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabs,
          children: [
            _OverviewTab(workspace: workspace),
            EventBoardTab(eventId: widget.eventId, canManage: workspace.canManage),
            EventDepartmentsTab(eventId: widget.eventId, workspace: workspace),
            EventDocumentsTab(eventId: widget.eventId, eventName: event.name),
            EventFinanceTab(eventId: widget.eventId),
            EventUpdatesTab(eventId: widget.eventId),
          ],
        ),
      ),
    );
  }
}

/// The collapsing header: the event's colour, its name, and one status line.
///
/// Hand-rolled rather than using `FlexibleSpaceBar.title`, which draws its
/// title over the background at every scroll position — so the small pinned
/// name sat on top of the large hero one. Here the two cross-fade: exactly one
/// of them is ever readable.
class _EventHeader extends StatelessWidget {
  const _EventHeader({required this.workspace, required this.eventId});
  final EventWorkspace workspace;
  final String eventId;

  static const _expandedHeight = 210.0;

  @override
  Widget build(BuildContext context) {
    final event = workspace.event;
    final tint = event.bannerColor;
    final topInset = MediaQuery.paddingOf(context).top;
    final collapsedHeight = kToolbarHeight + topInset;

    return SliverAppBar(
      pinned: true,
      expandedHeight: _expandedHeight,
      backgroundColor: tint,
      foregroundColor: Colors.white,
      actions: [
        if (workspace.canManage)
          IconButton(
            tooltip: 'Event status',
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => _showStatusSheet(context, event, eventId),
          ),
      ],
      flexibleSpace: LayoutBuilder(
        builder: (context, constraints) {
          // 1 when fully expanded, 0 when collapsed to the toolbar.
          final range = _expandedHeight - collapsedHeight;
          final open = range <= 0
              ? 0.0
              : ((constraints.maxHeight - collapsedHeight) / range).clamp(0.0, 1.0);

          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [tint, Color.lerp(tint, Colors.black, 0.42)!],
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // --- expanded hero ---
                Positioned(
                  left: GwdSpace.lg,
                  right: GwdSpace.lg,
                  bottom: GwdSpace.xl,
                  child: IgnorePointer(
                    child: Opacity(
                      // Fade out well before it reaches the toolbar, so the two
                      // titles are never both legible.
                      opacity: Curves.easeOut.transform(
                          ((open - 0.35) / 0.65).clamp(0.0, 1.0)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              if (event.status == EventStatus.ongoing) ...[
                                const BreathingDot(color: Colors.white, size: 6),
                                const SizedBox(width: 6),
                              ],
                              Text(
                                event.status.label.toUpperCase(),
                                style:
                                    GwdType.eyebrow.copyWith(color: Colors.white),
                              ),
                              Flexible(
                                child: Text(
                                  '  ·  ${event.type.toUpperCase()}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GwdType.eyebrow.copyWith(
                                      color: Colors.white.withValues(alpha: 0.7)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: GwdSpace.sm),
                          Text(
                            event.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GwdType.title1.copyWith(color: Colors.white),
                          ),
                          const SizedBox(height: GwdSpace.xs),
                          Text(
                            [
                              event.fullDateLabel,
                              if (event.timeLabel.isNotEmpty) event.timeLabel,
                              if (event.venue.isNotEmpty) event.venue,
                            ].join('  ·  '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GwdType.footnote.copyWith(
                                color: Colors.white.withValues(alpha: 0.86)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // --- collapsed title, sitting in the toolbar ---
                Positioned(
                  top: topInset,
                  left: 56,
                  right: workspace.canManage ? 56 : GwdSpace.lg,
                  height: kToolbarHeight,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity:
                          Curves.easeIn.transform((1 - (open / 0.35)).clamp(0.0, 1.0)),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          event.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GwdType.headline.copyWith(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

Future<void> _showStatusSheet(
    BuildContext context, ClubEvent event, String eventId) async {
  final store = AppScope.readStore(context);
  final messenger = ScaffoldMessenger.of(context);

  await showModalBottomSheet<void>(
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
            SheetHeader(
              title: 'Where is this up to?',
              subtitle: 'Currently ${event.status.label.toLowerCase()}',
            ),
            for (final status in event.status.nextOptions)
              ListTile(
                leading: Icon(status.icon, color: status.tint, size: 20),
                title: Text(status.label,
                    style: GwdType.body.copyWith(color: GwdColors.inkOf(sheetContext))),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _applyStatus(
                      context, store, messenger, eventId, event, status);
                },
              ),

            // Cancelling throws away work a lot of people did, so it sits
            // apart from the ordinary status moves and is Directors and the
            // President only. The server enforces that; this only decides
            // whether to offer it.
            if (_mayCancel(AppScope.sessionOf(sheetContext).me?.role)) ...[
              Divider(height: GwdSpace.xl, color: GwdColors.hairlineOf(sheetContext)),
              if (event.status != EventStatus.cancelled)
                ListTile(
                  leading: const Icon(Icons.event_busy_outlined,
                      color: GwdColors.critical, size: 20),
                  title: Text('Cancel this event',
                      style: GwdType.body.copyWith(color: GwdColors.critical)),
                  subtitle: Text('The work and paperwork are kept',
                      style: GwdType.footnote
                          .copyWith(color: GwdColors.inkTertiaryOf(sheetContext))),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await _confirmCancel(context, store, messenger, eventId, event);
                  },
                )
              else
                ListTile(
                  leading: const Icon(Icons.delete_forever_outlined,
                      color: GwdColors.critical, size: 20),
                  title: Text('Delete permanently',
                      style: GwdType.body.copyWith(color: GwdColors.critical)),
                  subtitle: Text('Removes its tasks, documents and bills too',
                      style: GwdType.footnote
                          .copyWith(color: GwdColors.inkTertiaryOf(sheetContext))),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await _confirmPurge(context, store, messenger, eventId, event);
                  },
                ),
            ],
            const SizedBox(height: GwdSpace.md),
          ],
        ),
      ),
    ),
  );
}

/// Cancelling is not the event lead's call — it discards work a lot of people
/// did. Mirrors the server, which is the authority.
bool _mayCancel(ClubRole? role) =>
    role == ClubRole.clubDirector
    || role == ClubRole.facultyCoordinator
    || role == ClubRole.president;

Future<void> _confirmCancel(
  BuildContext context,
  ClubStore store,
  ScaffoldMessengerState messenger,
  String eventId,
  ClubEvent event,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: GwdColors.surfaceOf(dialogContext),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GwdRadius.xl)),
      title: Text('Cancel ${event.name}?',
          style: GwdType.title3.copyWith(color: GwdColors.inkOf(dialogContext))),
      content: Text(
        'Everyone on it is told. Its tasks, documents and expenses are kept, so '
        'nothing anybody already did is lost — and you can delete it outright '
        'afterwards if you want it gone.',
        style: GwdType.callout
            .copyWith(color: GwdColors.inkSecondaryOf(dialogContext)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text('Keep it',
              style: GwdType.callout
                  .copyWith(color: GwdColors.inkSecondaryOf(dialogContext))),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text('Cancel the event',
              style: GwdType.callout.copyWith(
                  color: GwdColors.critical, fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  try {
    await store.cancelEvent(eventId);
    messenger.showSnackBar(SnackBar(content: Text('${event.name} was cancelled.')));
  } catch (error) {
    messenger.showSnackBar(SnackBar(content: Text('$error')));
  }
}

/// Only reachable on an already-cancelled event, so removing one is always two
/// deliberate steps.
Future<void> _confirmPurge(
  BuildContext context,
  ClubStore store,
  ScaffoldMessengerState messenger,
  String eventId,
  ClubEvent event,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: GwdColors.surfaceOf(dialogContext),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GwdRadius.xl)),
      title: Text('Delete ${event.name} for good?',
          style: GwdType.title3.copyWith(color: GwdColors.inkOf(dialogContext))),
      content: Text(
        'This also removes its tasks, its documents and its expense records. '
        'It cannot be undone.',
        style: GwdType.callout
            .copyWith(color: GwdColors.inkSecondaryOf(dialogContext)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text('Keep the record',
              style: GwdType.callout
                  .copyWith(color: GwdColors.inkSecondaryOf(dialogContext))),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text('Delete',
              style: GwdType.callout.copyWith(
                  color: GwdColors.critical, fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  try {
    await store.cancelEvent(eventId, purge: true);
    if (context.mounted) Navigator.of(context).pop();
    messenger.showSnackBar(SnackBar(content: Text('${event.name} was deleted.')));
  } catch (error) {
    messenger.showSnackBar(SnackBar(content: Text('$error')));
  }
}

/// Applies a status change, and handles the one case that needs a conversation:
/// closing an event that still has work open.
Future<void> _applyStatus(
  BuildContext context,
  ClubStore store,
  ScaffoldMessengerState messenger,
  String eventId,
  ClubEvent event,
  EventStatus status,
) async {
  try {
    final checklist = await store.setEventStatus(eventId, status);
    if (checklist == null) return;
    if (!context.mounted) return;

    final openTasks = (checklist['openTasks'] as num?)?.toInt() ?? 0;
    final pending = (checklist['pendingApprovals'] as num?)?.toInt() ?? 0;

    final force = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: GwdColors.surfaceOf(dialogContext),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(GwdRadius.xl)),
        title: Text('Not quite finished',
            style: GwdType.title3.copyWith(color: GwdColors.inkOf(dialogContext))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (openTasks > 0)
              _ChecklistLine(
                  label: '$openTasks ${openTasks == 1 ? 'task' : 'tasks'} still open'),
            if (pending > 0)
              _ChecklistLine(
                  label:
                      '$pending ${pending == 1 ? 'approval' : 'approvals'} awaiting sign-off'),
            const SizedBox(height: GwdSpace.md),
            Text(
              'You can close it anyway — the work stays on the record either way.',
              style: GwdType.footnote
                  .copyWith(color: GwdColors.inkSecondaryOf(dialogContext)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Go back',
                style: GwdType.callout
                    .copyWith(color: GwdColors.inkSecondaryOf(dialogContext))),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Close it anyway',
                style: GwdType.callout.copyWith(
                    color: GwdColors.primaryRed, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (force == true) {
      await store.setEventStatus(eventId, status, force: true);
    }
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  }
}

class _ChecklistLine extends StatelessWidget {
  const _ChecklistLine({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Row(
          children: [
            const Icon(Icons.radio_button_unchecked,
                size: 13, color: GwdColors.warning),
            const SizedBox(width: GwdSpace.sm),
            Expanded(
              child: Text(label,
                  style:
                      GwdType.callout.copyWith(color: GwdColors.inkOf(context))),
            ),
          ],
        ),
      );
}

class _WorkspaceTabs extends StatelessWidget {
  const _WorkspaceTabs({
    required this.controller,
    required this.pendingApprovals,
    required this.owedCount,
  });

  final TabController controller;
  final int pendingApprovals;

  /// Expenses still waiting on a decision. Badged because somebody is out of
  /// pocket until it moves.
  final int owedCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: GwdColors.canvasOf(context),
      child: TabBar(
        controller: controller,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        dividerColor: GwdColors.hairlineOf(context),
        indicatorColor: GwdColors.primaryRed,
        indicatorWeight: 2.5,
        indicatorSize: TabBarIndicatorSize.label,
        labelColor: GwdColors.inkOf(context),
        unselectedLabelColor: GwdColors.inkTertiaryOf(context),
        labelStyle: GwdType.callout.copyWith(fontWeight: FontWeight.w700),
        unselectedLabelStyle: GwdType.callout,
        tabs: [
          const Tab(text: 'Overview'),
          const Tab(text: 'Work'),
          const Tab(text: 'Departments'),
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Documents'),
                if (pendingApprovals > 0) ...[
                  const SizedBox(width: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: GwdColors.warning,
                      borderRadius: BorderRadius.circular(GwdRadius.pill),
                    ),
                    child: Text('$pendingApprovals',
                        style: GwdType.caption
                            .copyWith(color: Colors.white, fontSize: 8.5)),
                  ),
                ],
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Finance'),
                if (owedCount > 0) ...[
                  const SizedBox(width: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: GwdColors.warning,
                      borderRadius: BorderRadius.circular(GwdRadius.pill),
                    ),
                    child: Text('$owedCount',
                        style: GwdType.caption
                            .copyWith(color: Colors.white, fontSize: 8.5)),
                  ),
                ],
              ],
            ),
          ),
          const Tab(text: 'Updates'),
        ],
      ),
    );
  }
}

class _TabBarHeader extends SliverPersistentHeaderDelegate {
  _TabBarHeader({required this.child});
  final Widget child;

  @override
  double get minExtent => 48;
  @override
  double get maxExtent => 48;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => child;

  @override
  bool shouldRebuild(_TabBarHeader old) => old.child != child;
}

// ----------------------------------------------------------------- overview

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.workspace});
  final EventWorkspace workspace;

  @override
  Widget build(BuildContext context) {
    final event = workspace.event;
    final gutter = Layout.of(context).gutter;
    var step = 0;
    int next() => step++;

    return ListView(
      padding: EdgeInsets.fromLTRB(gutter, GwdSpace.lg, gutter, GwdSpace.xxxl),
      children: [
        AppleStaggerItem(
          index: next(),
          child: _ProgressCard(workspace: workspace),
        ),

        if (event.description.isNotEmpty) ...[
          const SizedBox(height: GwdSpace.lg),
          AppleStaggerItem(
            index: next(),
            child: SurfaceCard(
              child: Text(
                event.description,
                style: GwdType.body.copyWith(color: GwdColors.inkSecondaryOf(context)),
              ),
            ),
          ),
        ],

        if (workspace.deadlines.isNotEmpty) ...[
          const SizedBox(height: GwdSpace.xl),
          AppleStaggerItem(
            index: next(),
            child: const SectionHeader(
                title: 'Next up', subtitle: 'The closest deadlines on this event'),
          ),
          for (final deadline in workspace.deadlines)
            AppleStaggerItem(
              index: next(),
              child: Padding(
                padding: const EdgeInsets.only(bottom: GwdSpace.sm),
                child: _DeadlineRow(deadline: deadline),
              ),
            ),
        ],

        const SizedBox(height: GwdSpace.xl),
        AppleStaggerItem(
          index: next(),
          child: SectionHeader(
            title: 'Running it',
            subtitle: workspace.team.length == 1
                ? 'One person on the core team'
                : '${workspace.team.length} people on the core team',
          ),
        ),
        AppleStaggerItem(index: next(), child: _TeamStrip(workspace: workspace)),

        if (event.speakerName.isNotEmpty) ...[
          const SizedBox(height: GwdSpace.xl),
          AppleStaggerItem(
            index: next(),
            child: SurfaceCard(
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: event.bannerColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(GwdRadius.md),
                    ),
                    child: Icon(Icons.record_voice_over_outlined,
                        size: 18, color: event.bannerColor),
                  ),
                  const SizedBox(width: GwdSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(event.speakerName,
                            style: GwdType.headline
                                .copyWith(color: GwdColors.inkOf(context))),
                        if (event.externalOrganisation.isNotEmpty)
                          Text(event.externalOrganisation,
                              style: GwdType.footnote.copyWith(
                                  color: GwdColors.inkTertiaryOf(context))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.workspace});
  final EventWorkspace workspace;

  @override
  Widget build(BuildContext context) {
    final event = workspace.event;
    final tint = event.bannerColor;
    final days = event.daysAway;

    return SurfaceCard(
      emphasis: event.status == EventStatus.ongoing
          ? SurfaceEmphasis.live
          : SurfaceEmphasis.quiet,
      accent: tint,
      child: Row(
        children: [
          ProgressArc(
            progress: event.taskCount == 0 ? 0 : event.progress / 100,
            size: 74,
            color: tint,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedCounter(
                  value: event.progress,
                  suffix: '%',
                  style: GwdType.numeric.copyWith(
                      fontSize: 19, color: GwdColors.inkOf(context)),
                ),
                Text('done',
                    style: GwdType.caption.copyWith(
                        fontSize: 8.5,
                        letterSpacing: 0.4,
                        color: GwdColors.inkTertiaryOf(context))),
              ],
            ),
          ),
          const SizedBox(width: GwdSpace.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  event.taskCount == 0
                      ? 'No work added yet'
                      : '${event.taskCompleted} of ${event.taskCount} tasks done',
                  style: GwdType.headline.copyWith(color: GwdColors.inkOf(context)),
                ),
                const SizedBox(height: 3),
                Text(
                  switch (event.status) {
                    EventStatus.completed => 'Wrapped up.',
                    EventStatus.cancelled => 'This one was called off.',
                    EventStatus.ongoing => 'Happening right now.',
                    _ when days < 0 => 'The date has passed.',
                    _ when days == 0 => 'It is today.',
                    _ when days == 1 => 'One day to go.',
                    _ => '$days days to go.',
                  },
                  style: GwdType.footnote
                      .copyWith(color: GwdColors.inkSecondaryOf(context)),
                ),
                if (workspace.approvalsPending > 0) ...[
                  const SizedBox(height: GwdSpace.sm),
                  GwdChip(
                    label:
                        '${workspace.approvalsPending} awaiting sign-off',
                    color: GwdColors.warning,
                    icon: Icons.hourglass_empty_rounded,
                    dense: true,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DeadlineRow extends StatelessWidget {
  const _DeadlineRow({required this.deadline});
  final EventDeadline deadline;

  @override
  Widget build(BuildContext context) {
    final tint = deadline.overdue ? GwdColors.critical : GwdColors.inkTertiaryOf(context);
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(
          horizontal: GwdSpace.md, vertical: GwdSpace.md),
      child: Row(
        children: [
          Icon(
            deadline.overdue
                ? Icons.error_outline_rounded
                : Icons.schedule_rounded,
            size: 16,
            color: tint,
          ),
          const SizedBox(width: GwdSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(deadline.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        GwdType.callout.copyWith(color: GwdColors.inkOf(context))),
                if (deadline.departmentName != null)
                  Text(deadline.departmentName!,
                      style: GwdType.caption.copyWith(
                          fontSize: 9.5,
                          letterSpacing: 0,
                          color: GwdColors.inkTertiaryOf(context))),
              ],
            ),
          ),
          Text(
            '${deadline.dueDate.day}/${deadline.dueDate.month}',
            style: GwdType.footnote.copyWith(color: tint),
          ),
        ],
      ),
    );
  }
}

class _TeamStrip extends StatelessWidget {
  const _TeamStrip({required this.workspace});
  final EventWorkspace workspace;

  @override
  Widget build(BuildContext context) {
    if (workspace.team.isEmpty) {
      return SurfaceCard(
        child: Text('Nobody assigned to the core team yet.',
            style: GwdType.callout.copyWith(color: GwdColors.inkTertiaryOf(context))),
      );
    }

    return SizedBox(
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: workspace.team.length,
        separatorBuilder: (_, __) => const SizedBox(width: GwdSpace.md),
        itemBuilder: (context, i) {
          final person = workspace.team[i];
          final tint = person.avatarColor == null || person.avatarColor!.length < 7
              ? GwdColors.inkSecondaryOf(context)
              : Color(int.parse('FF${person.avatarColor!.substring(1)}', radix: 16));
          return SizedBox(
            width: 62,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  children: [
                    Avatar(
                      initials: _initials(person.name),
                      tint: tint,
                      size: 44,
                      selected: person.isLead,
                    ),
                    if (person.isLead)
                      Positioned(
                        right: -1,
                        bottom: -1,
                        child: Container(
                          padding: const EdgeInsets.all(2.5),
                          decoration: BoxDecoration(
                            color: GwdColors.primaryRed,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: GwdColors.canvasOf(context), width: 1.5),
                          ),
                          child: const Icon(Icons.star_rounded,
                              size: 8, color: Colors.white),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  person.name.split(' ').first,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GwdType.caption.copyWith(
                    fontSize: 9.5,
                    letterSpacing: 0,
                    color: GwdColors.inkSecondaryOf(context),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _initials(String name) {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    if (words.isEmpty) return '?';
    if (words.length == 1) {
      final w = words.first;
      return (w.length >= 2 ? w.substring(0, 2) : w).toUpperCase();
    }
    return '${words.first[0]}${words.last[0]}'.toUpperCase();
  }
}
