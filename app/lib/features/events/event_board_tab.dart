import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/responsive.dart';
import '../../app/theme/apple_motion.dart';
import '../../app/theme/gwd_theme.dart';
import '../../app/widgets/common.dart';
import '../../core/api/api_client.dart';
import '../../core/models/club_event.dart';
import '../../core/models/club_task.dart';
import '../../core/state/club_store.dart';
import '../tasks/task_detail_page.dart';
import 'add_event_task_sheet.dart';

/// The event board: To do → In progress → Review → Done.
///
/// On a phone it is one column at a time with a lane switcher, because four
/// side-by-side columns on a 390pt screen gives you four unreadable slivers.
/// On a tablet it becomes a real board. Same data, same widgets, one layout
/// decision.
class EventBoardTab extends StatefulWidget {
  const EventBoardTab({super.key, required this.eventId, required this.canManage});

  final String eventId;
  final bool canManage;

  @override
  State<EventBoardTab> createState() => _EventBoardTabState();
}

class _EventBoardTabState extends State<EventBoardTab> {
  int _lane = 0;
  String? _departmentFilter;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.storeOf(context);
    final layout = Layout.of(context);
    final all = store.boardFor(widget.eventId);
    final workspace = store.workspaceFor(widget.eventId);

    if (all == null) {
      return const Padding(
        padding: EdgeInsets.all(GwdSpace.xl),
        child: SkeletonList(count: 4, height: 76),
      );
    }

    final cards = _departmentFilter == null
        ? all
        : all.where((c) => c.departmentId == _departmentFilter).toList();

    final byLane = {
      for (final status in TaskStatus.board)
        status: cards.where((c) => _laneOf(c.status) == status).toList(),
    };

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: widget.canManage && workspace != null
          ? FloatingActionButton.small(
              backgroundColor: GwdColors.primaryRed,
              foregroundColor: Colors.white,
              onPressed: () => showAddEventTaskSheet(
                context,
                eventId: widget.eventId,
                departments: workspace.departments,
              ),
              child: const Icon(Icons.add_rounded),
            )
          : null,
      body: Column(
        children: [
          if (workspace != null && workspace.departments.length > 1)
            _DepartmentFilter(
              departments: workspace.departments,
              selected: _departmentFilter,
              onChanged: (id) => setState(() => _departmentFilter = id),
            ),
          if (layout.isCompact)
            _LaneSwitcher(
              lane: _lane,
              counts: [for (final s in TaskStatus.board) byLane[s]!.length],
              onChanged: (value) => setState(() => _lane = value),
            ),
          Expanded(
            child: layout.isCompact
                ? _Lane(
                    key: ValueKey(_lane),
                    eventId: widget.eventId,
                    status: TaskStatus.board[_lane],
                    cards: byLane[TaskStatus.board[_lane]]!,
                    canManage: widget.canManage,
                  )
                : _WideBoard(
                    eventId: widget.eventId,
                    byLane: byLane,
                    canManage: widget.canManage,
                  ),
          ),
        ],
      ),
    );
  }

  /// Blocked work stays in the lane it stalled in, wearing a badge. Moving it
  /// to a column of its own is how blocked work gets quietly forgotten.
  TaskStatus _laneOf(TaskStatus status) => switch (status) {
        TaskStatus.blocked => TaskStatus.inProgress,
        TaskStatus.cancelled => TaskStatus.completed,
        _ => status,
      };
}

class _WideBoard extends StatelessWidget {
  const _WideBoard({
    required this.eventId,
    required this.byLane,
    required this.canManage,
  });

  final String eventId;
  final Map<TaskStatus, List<EventTaskCard>> byLane;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final status in TaskStatus.board)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      GwdSpace.md, GwdSpace.lg, GwdSpace.md, GwdSpace.sm),
                  child: Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                            color: status.tint, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: GwdSpace.sm),
                      Text(status.boardLabel.toUpperCase(),
                          style: GwdType.eyebrow
                              .copyWith(color: GwdColors.inkOf(context))),
                      const Spacer(),
                      Text('${byLane[status]!.length}',
                          style: GwdType.caption.copyWith(
                              color: GwdColors.inkTertiaryOf(context))),
                    ],
                  ),
                ),
                Expanded(
                  child: _Lane(
                    eventId: eventId,
                    status: status,
                    cards: byLane[status]!,
                    canManage: canManage,
                    showHeader: false,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Lane extends StatelessWidget {
  const _Lane({
    super.key,
    required this.eventId,
    required this.status,
    required this.cards,
    required this.canManage,
    this.showHeader = true,
  });

  final String eventId;
  final TaskStatus status;
  final List<EventTaskCard> cards;
  final bool canManage;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final gutter = Layout.of(context).gutter;

    if (cards.isEmpty) {
      return EmptyState(
        compact: true,
        icon: status.icon,
        title: switch (status) {
          TaskStatus.pending => 'Nothing waiting',
          TaskStatus.inProgress => 'Nothing being worked on',
          TaskStatus.review => 'Nothing to review',
          _ => 'Nothing finished yet',
        },
        message: switch (status) {
          TaskStatus.pending => 'Every task here has been picked up.',
          TaskStatus.inProgress => 'Pick something up from To do to get going.',
          TaskStatus.review => 'Work sent for a second pair of eyes lands here.',
          _ => 'Finished work collects here.',
        },
      );
    }

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
          showHeader ? gutter : GwdSpace.md,
          GwdSpace.md,
          showHeader ? gutter : GwdSpace.md,
          GwdSpace.xxxl + 40),
      itemCount: cards.length,
      itemBuilder: (context, i) => Padding(
        padding: const EdgeInsets.only(bottom: GwdSpace.sm),
        child: AppleStaggerItem(
          index: i,
          child: _BoardCard(
            eventId: eventId,
            card: cards[i],
            canManage: canManage,
          ),
        ),
      ),
    );
  }
}

class _BoardCard extends StatelessWidget {
  const _BoardCard({
    required this.eventId,
    required this.card,
    required this.canManage,
  });

  final String eventId;
  final EventTaskCard card;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.storeOf(context);
    final meId = AppScope.sessionOf(context).me?.id;
    final mine = card.assignedTo != null && card.assignedTo == meId;
    final unclaimed = card.assignedTo == null;

    return SurfaceCard(
      padding: const EdgeInsets.all(GwdSpace.md),
      onTap: () => _showCardSheet(context, eventId, card, canManage),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (card.priority == 'high') ...[
                const Padding(
                  padding: EdgeInsets.only(top: 2, right: 6),
                  child: Icon(Icons.priority_high_rounded,
                      size: 13, color: GwdColors.critical),
                ),
              ],
              Expanded(
                child: Text(
                  card.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: GwdType.callout.copyWith(
                    color: GwdColors.inkOf(context),
                    fontWeight: FontWeight.w600,
                    decoration: card.status == TaskStatus.completed
                        ? TextDecoration.lineThrough
                        : null,
                    decorationColor: GwdColors.inkTertiaryOf(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: GwdSpace.sm),
          Row(
            children: [
              if (card.departmentName != null) ...[
                GwdChip(
                  label: card.departmentName!,
                  color: GwdColors.inkTertiaryOf(context),
                  dense: true,
                ),
                const SizedBox(width: 5),
              ],
              if (card.status == TaskStatus.blocked)
                const GwdChip(
                  label: 'Blocked',
                  color: GwdColors.warning,
                  icon: Icons.report_problem_outlined,
                  dense: true,
                ),
              const Spacer(),
              if (card.dueDate != null)
                Text(
                  '${card.dueDate!.day}/${card.dueDate!.month}',
                  style: GwdType.caption.copyWith(
                    fontSize: 9.5,
                    letterSpacing: 0,
                    color: card.isOverdue
                        ? GwdColors.critical
                        : GwdColors.inkTertiaryOf(context),
                  ),
                ),
              const SizedBox(width: GwdSpace.sm),
              if (unclaimed)
                PressableScale(
                  onTap: () => _claim(context, store, eventId, card),
                  haptic: HapticStrength.light,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: GwdColors.primaryRed.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(GwdRadius.sm),
                    ),
                    child: Text('I’ll take it',
                        style: GwdType.caption.copyWith(
                            fontSize: 9.5,
                            letterSpacing: 0,
                            color: GwdColors.primaryRed)),
                  ),
                )
              else
                Avatar(
                  initials: _initials(card.assigneeName ?? '?'),
                  tint: card.accent,
                  size: 22,
                  selected: mine,
                ),
            ],
          ),
        ],
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

Future<void> _claim(
    BuildContext context, ClubStore store, String eventId, EventTaskCard card) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await store.claimEventTask(eventId, card.id);
    messenger.showSnackBar(SnackBar(content: Text('“${card.title}” is yours.')));
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  }
}

/// Tapping a card opens what you can actually do with it, which depends on
/// whether it is yours and where it is on the board.
Future<void> _showCardSheet(
  BuildContext context,
  String eventId,
  EventTaskCard card,
  bool canManage,
) async {
  final store = AppScope.readStore(context);
  final meId = AppScope.readSession(context).me?.id;
  final messenger = ScaffoldMessenger.of(context);
  final mine = card.assignedTo != null && card.assignedTo == meId;

  // What this person can move it to. The server decides for real; this only
  // avoids offering something that will be refused.
  final moves = <TaskStatus>{
    if (mine)
      ...switch (card.status) {
        TaskStatus.pending => [TaskStatus.inProgress, TaskStatus.blocked],
        TaskStatus.inProgress => [
            TaskStatus.review,
            TaskStatus.completed,
            TaskStatus.blocked
          ],
        TaskStatus.review => [TaskStatus.inProgress],
        TaskStatus.blocked => [TaskStatus.inProgress],
        _ => <TaskStatus>[],
      },
    if (canManage && card.status == TaskStatus.review) ...[
      TaskStatus.completed,
      TaskStatus.inProgress,
    ],
  }.toList();

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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHeader(
              title: card.title,
              subtitle: [
                if (card.departmentName != null) card.departmentName!,
                card.assigneeName ?? 'Nobody has picked this up',
              ].join('  ·  '),
            ),
            if (card.description.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    GwdSpace.xl, 0, GwdSpace.xl, GwdSpace.md),
                child: Text(card.description,
                    style: GwdType.body
                        .copyWith(color: GwdColors.inkSecondaryOf(sheetContext))),
              ),
            if (card.assignedTo == null)
              ListTile(
                leading: const Icon(Icons.pan_tool_alt_outlined,
                    size: 20, color: GwdColors.primaryRed),
                title: Text('I’ll take this on',
                    style: GwdType.body.copyWith(color: GwdColors.primaryRed)),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _claim(context, store, eventId, card);
                },
              ),
            for (final status in moves)
              ListTile(
                leading: Icon(status.icon, size: 20, color: status.tint),
                title: Text(
                  switch (status) {
                    TaskStatus.inProgress =>
                      card.status == TaskStatus.review ? 'Send it back' : 'Start it',
                    TaskStatus.review => 'Send for review',
                    TaskStatus.completed =>
                      card.status == TaskStatus.review ? 'Accept it' : 'Mark it done',
                    TaskStatus.blocked => 'I’m stuck on this',
                    _ => status.label,
                  },
                  style: GwdType.body.copyWith(color: GwdColors.inkOf(sheetContext)),
                ),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  try {
                    await store.setEventTaskStatus(eventId, card, status);
                  } on ApiException catch (e) {
                    messenger.showSnackBar(SnackBar(content: Text(e.message)));
                  }
                },
              ),
            if (moves.isEmpty && card.assignedTo != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    GwdSpace.xl, GwdSpace.sm, GwdSpace.xl, GwdSpace.lg),
                child: Text(
                  card.status == TaskStatus.completed
                      ? 'This one is finished.'
                      : '${card.assigneeName ?? 'Someone'} is on this. '
                          'They move it along from here.',
                  style: GwdType.callout
                      .copyWith(color: GwdColors.inkTertiaryOf(sheetContext)),
                ),
              ),

            // Section 19: context belongs attached to the work. This opens the
            // task's own thread rather than inventing a second comment system.
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.forum_outlined,
                  size: 20, color: GwdColors.inkSecondaryOf(sheetContext)),
              title: Text(
                card.commentCount == 0
                    ? 'Discuss this'
                    : card.commentCount == 1
                        ? '1 comment'
                        : '${card.commentCount} comments',
                style: GwdType.body.copyWith(color: GwdColors.inkOf(sheetContext)),
              ),
              trailing: Icon(Icons.chevron_right_rounded,
                  size: 18, color: GwdColors.inkTertiaryOf(sheetContext)),
              onTap: () {
                Navigator.of(sheetContext).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => TaskDetailPage(taskId: card.id)),
                );
              },
            ),
            const SizedBox(height: GwdSpace.md),
          ],
        ),
      ),
    ),
  );
}

class _LaneSwitcher extends StatelessWidget {
  const _LaneSwitcher({
    required this.lane,
    required this.counts,
    required this.onChanged,
  });

  final int lane;
  final List<int> counts;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(
            horizontal: Layout.of(context).gutter, vertical: GwdSpace.sm),
        itemCount: TaskStatus.board.length,
        separatorBuilder: (_, __) => const SizedBox(width: GwdSpace.sm),
        itemBuilder: (context, i) {
          final status = TaskStatus.board[i];
          final selected = i == lane;
          return PressableScale(
            onTap: () => onChanged(i),
            pressedScale: 0.95,
            haptic: HapticStrength.selection,
            child: AnimatedContainer(
              duration: AppleDuration.fast,
              curve: AppleCurves.standard,
              padding: const EdgeInsets.symmetric(horizontal: GwdSpace.md),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? status.tint.withValues(alpha: 0.12)
                    : GwdColors.surfaceOf(context),
                borderRadius: BorderRadius.circular(GwdRadius.md),
                border: Border.all(
                  color: selected
                      ? status.tint.withValues(alpha: 0.4)
                      : GwdColors.hairlineOf(context),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration:
                        BoxDecoration(color: status.tint, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    status.boardLabel,
                    style: GwdType.footnote.copyWith(
                      color: selected
                          ? GwdColors.inkOf(context)
                          : GwdColors.inkSecondaryOf(context),
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '${counts[i]}',
                    style: GwdType.caption.copyWith(
                      fontSize: 9.5,
                      letterSpacing: 0,
                      color: GwdColors.inkTertiaryOf(context),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DepartmentFilter extends StatelessWidget {
  const _DepartmentFilter({
    required this.departments,
    required this.selected,
    required this.onChanged,
  });

  final List<EventDepartment> departments;
  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(
            horizontal: Layout.of(context).gutter, vertical: GwdSpace.sm),
        children: [
          _Pill(
            label: 'Everyone',
            selected: selected == null,
            onTap: () => onChanged(null),
          ),
          for (final d in departments) ...[
            const SizedBox(width: GwdSpace.sm),
            _Pill(
              label: d.name,
              selected: selected == d.departmentId,
              onTap: () => onChanged(d.departmentId),
            ),
          ],
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      pressedScale: 0.95,
      haptic: HapticStrength.selection,
      child: AnimatedContainer(
        duration: AppleDuration.fast,
        padding: const EdgeInsets.symmetric(horizontal: GwdSpace.md),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? GwdColors.inkOf(context) : Colors.transparent,
          borderRadius: BorderRadius.circular(GwdRadius.pill),
          border: Border.all(
            color: selected ? GwdColors.inkOf(context) : GwdColors.hairlineOf(context),
          ),
        ),
        child: Text(
          label,
          style: GwdType.footnote.copyWith(
            color: selected
                ? GwdColors.canvasOf(context)
                : GwdColors.inkSecondaryOf(context),
          ),
        ),
      ),
    );
  }
}
