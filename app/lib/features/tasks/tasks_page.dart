import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme/apple_motion.dart';
import '../../app/theme/gwd_theme.dart';
import '../../app/widgets/common.dart';
import '../../core/models/club_task.dart';
import '../../core/models/task_request.dart';
import '../../core/state/club_store.dart';
import 'hand_out_sheet.dart';
import 'new_task_sheet.dart';
import 'task_card.dart';
import 'task_detail_page.dart';

/// Section 6.2 — one page, two tabs.
///
/// *Assigned Task* only exists for roles that can assign; a Member never sees
/// a tab they can do nothing with. The task-request action sits in the compose
/// sheet as a mode, not as a third tab.
class TasksPage extends StatefulWidget {
  const TasksPage({super.key});

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  int _tab = 0;
  TaskStatus? _filter;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.storeOf(context);
    final canAssign = store.capabilities.canAssign;
    final gutter = GwdSpace.gutter(MediaQuery.sizeOf(context).width);

    final tasks = _tab == 0 ? store.myTasks : store.assignedByMe;
    final visible =
        _filter == null ? tasks : tasks.where((t) => t.status == _filter).toList();

    final pendingRequests = store.incomingRequests.where((r) => r.isPending).toList();

    return Scaffold(
      backgroundColor: GwdColors.canvasOf(context),
      floatingActionButton: canAssign
          ? FloatingActionButton.extended(
              onPressed: () => showNewTaskSheet(context),
              backgroundColor: GwdColors.primaryRed,
              foregroundColor: Colors.white,
              elevation: 2,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: Text('New task', style: GwdType.headline.copyWith(color: Colors.white)),
            )
          : null,
      body: RefreshIndicator(
        color: GwdColors.primaryRed,
        onRefresh: () => store.loadAll(silent: true),
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(gutter, GwdSpace.lg, gutter, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Work',
                          style: GwdType.largeTitle
                              .copyWith(color: GwdColors.inkOf(context))),
                      const SizedBox(height: GwdSpace.lg),
                      if (canAssign)
                        _TabBar(
                          index: _tab,
                          mine: store.myTasks.where((t) => t.status.isOpen).length,
                          assigned:
                              store.assignedByMe.where((t) => t.status.isOpen).length,
                          onChanged: (i) => setState(() {
                            _tab = i;
                            _filter = null;
                          }),
                        ),
                      if (canAssign) const SizedBox(height: GwdSpace.lg),
                      _StatusFilter(
                        value: _filter,
                        counts: _countsFor(tasks),
                        onChanged: (s) => setState(() => _filter = s),
                      ),
                      const SizedBox(height: GwdSpace.lg),
                    ],
                  ),
                ),
              ),
            ),

            // Work the leadership sent to this Lead's department that nobody
            // has been given yet. Top of the screen because it is blocking
            // somebody else, and it only exists while there is something in it.
            if (_tab == 0 && store.incoming.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: gutter),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SectionHeader(
                        title: 'Sent to your department',
                        subtitle: store.incoming.length == 1
                            ? 'Decide who takes it on'
                            : 'Decide who takes these on',
                      ),
                      for (final task in store.incoming)
                        Padding(
                          padding: const EdgeInsets.only(bottom: GwdSpace.md),
                          child: _IncomingCard(task: task),
                        ),
                      const SizedBox(height: GwdSpace.lg),
                    ],
                  ),
                ),
              ),

            // Incoming task requests — a distinct action, shown above the list
            // only when there are some, so it never becomes permanent furniture.
            if (_tab == 0 && pendingRequests.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: gutter),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionHeader(title: 'Requests for you'),
                      for (final request in pendingRequests)
                        Padding(
                          padding: const EdgeInsets.only(bottom: GwdSpace.md),
                          child: _RequestCard(request: request, store: store),
                        ),
                      const SizedBox(height: GwdSpace.lg),
                    ],
                  ),
                ),
              ),

            if (store.loading && !store.hasLoadedOnce)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: gutter),
                  child: const SkeletonList(),
                ),
              )
            else if (visible.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: _tab == 0 ? Icons.inbox_outlined : Icons.outbox_outlined,
                  title: _tab == 0 ? 'No tasks for you' : 'You haven\'t assigned anything',
                  message: _filter != null
                      ? 'Nothing is ${_filter!.label.toLowerCase()} right now.'
                      : _tab == 0
                          ? 'When someone assigns you work, it appears here straight away.'
                          : 'Work you hand to other people shows up here so you can track it.',
                  action: _filter != null
                      ? SecondaryButton(
                          label: 'Clear filter',
                          onPressed: () => setState(() => _filter = null),
                        )
                      : null,
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 96),
                sliver: SliverList.builder(
                  itemCount: visible.length,
                  itemBuilder: (context, i) {
                    final task = visible[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: GwdSpace.md),
                      child: AppleStaggerItem(
                        index: i,
                        // Keyed by id so a live update animates in place rather
                        // than the whole list rebuilding underneath the user.
                        child: TaskCard(
                          key: ValueKey(task.id),
                          task: task,
                          subtitle: _tab == 0
                              ? 'From ${store.memberName(task.assignedBy)}'
                              : 'To ${store.memberName(task.assignedTo)}',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => TaskDetailPage(taskId: task.id)),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Map<TaskStatus, int> _countsFor(List<ClubTask> tasks) {
    final counts = <TaskStatus, int>{};
    for (final task in tasks) {
      counts[task.status] = (counts[task.status] ?? 0) + 1;
    }
    return counts;
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({
    required this.index,
    required this.onChanged,
    required this.mine,
    required this.assigned,
  });

  final int index;
  final ValueChanged<int> onChanged;
  final int mine;
  final int assigned;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: GwdColors.sunkenOf(context),
        borderRadius: BorderRadius.circular(GwdRadius.md),
      ),
      child: Row(
        children: [
          _tab(context, 0, 'My Task', mine),
          _tab(context, 1, 'Assigned Task', assigned),
        ],
      ),
    );
  }

  Widget _tab(BuildContext context, int i, String label, int count) {
    final selected = i == index;
    return Expanded(
      child: PressableScale(
        haptic: HapticStrength.selection,
        pressedScale: 0.98,
        onTap: () => onChanged(i),
        child: AnimatedContainer(
          duration: AppleDuration.standard,
          curve: AppleCurves.standard,
          padding: const EdgeInsets.symmetric(vertical: GwdSpace.sm + 2),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? GwdColors.surfaceOf(context) : Colors.transparent,
            borderRadius: BorderRadius.circular(GwdRadius.sm),
            boxShadow: selected ? GwdShadow.resting(
                Theme.of(context).brightness == Brightness.dark) : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: GwdType.callout.copyWith(
                  color: selected
                      ? GwdColors.inkOf(context)
                      : GwdColors.inkTertiaryOf(context),
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 5),
                Text('$count',
                    style: GwdType.caption.copyWith(
                      color: selected
                          ? GwdColors.primaryRed
                          : GwdColors.inkTertiaryOf(context),
                    )),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusFilter extends StatelessWidget {
  const _StatusFilter({
    required this.value,
    required this.counts,
    required this.onChanged,
  });

  final TaskStatus? value;
  final Map<TaskStatus, int> counts;
  final ValueChanged<TaskStatus?> onChanged;

  @override
  Widget build(BuildContext context) {
    const shown = [TaskStatus.pending, TaskStatus.inProgress, TaskStatus.completed];
    return SizedBox(
      height: 32,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _chip(context, null, 'All', counts.values.fold(0, (a, b) => a + b)),
          for (final status in shown)
            if ((counts[status] ?? 0) > 0 || value == status)
              _chip(context, status, status.label, counts[status] ?? 0),
          if ((counts[TaskStatus.blocked] ?? 0) > 0)
            _chip(context, TaskStatus.blocked, 'Blocked', counts[TaskStatus.blocked]!),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, TaskStatus? status, String label, int count) {
    final selected = value == status;
    return Padding(
      padding: const EdgeInsets.only(right: GwdSpace.sm),
      child: PressableScale(
        haptic: HapticStrength.selection,
        onTap: () => onChanged(status),
        child: AnimatedContainer(
          duration: AppleDuration.fast,
          curve: AppleCurves.standard,
          padding: const EdgeInsets.symmetric(horizontal: GwdSpace.md, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? GwdColors.inkOf(context) : GwdColors.surfaceOf(context),
            borderRadius: BorderRadius.circular(GwdRadius.pill),
            border: Border.all(
              color: selected ? GwdColors.inkOf(context) : GwdColors.hairlineOf(context),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: GwdType.footnote.copyWith(
                  color: selected
                      ? GwdColors.surfaceOf(context)
                      : GwdColors.inkSecondaryOf(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 4),
                Text('$count',
                    style: GwdType.caption.copyWith(
                      color: selected
                          ? GwdColors.surfaceOf(context).withValues(alpha: 0.7)
                          : GwdColors.inkTertiaryOf(context),
                    )),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A department task waiting to be handed out.
///
/// Visually distinct from an ordinary task card because it is not *yours* — it
/// is a decision you owe somebody. The accent border and the single action say
/// that without a paragraph of explanation.
class _IncomingCard extends StatelessWidget {
  const _IncomingCard({required this.task});
  final ClubTask task;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.readStore(context);
    final from = store.memberName(task.assignedBy);

    return SurfaceCard(
      padding: const EdgeInsets.all(GwdSpace.lg),
      emphasis: SurfaceEmphasis.live,
      accent: GwdColors.warning,
      onTap: () => showHandOutSheet(context, task),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.inbox_rounded, size: 15, color: GwdColors.warning),
              const SizedBox(width: 6),
              Text('FROM $from'.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GwdType.eyebrow.copyWith(color: GwdColors.warning)),
              const Spacer(),
              if (task.dueLabel != null)
                Text(task.dueLabel!,
                    style: GwdType.caption.copyWith(
                        fontSize: 9.5,
                        letterSpacing: 0,
                        color: task.isOverdue
                            ? GwdColors.critical
                            : GwdColors.inkTertiaryOf(context))),
            ],
          ),
          const SizedBox(height: GwdSpace.sm),
          Text(task.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GwdType.title3.copyWith(color: GwdColors.inkOf(context))),
          if (task.description.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(task.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GwdType.footnote
                    .copyWith(color: GwdColors.inkSecondaryOf(context))),
          ],
          const SizedBox(height: GwdSpace.lg),
          SecondaryButton(
            label: 'Decide who does it',
            icon: Icons.arrow_forward_rounded,
            expand: true,
            onPressed: () => showHandOutSheet(context, task),
          ),
        ],
      ),
    );
  }
}

class _RequestCard extends StatefulWidget {
  const _RequestCard({required this.request, required this.store});
  final TaskRequest request;
  final ClubStore store;

  @override
  State<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends State<_RequestCard> {
  bool _busy = false;

  Future<void> _respond(bool accept) async {
    setState(() => _busy = true);
    try {
      await widget.store.respondToRequest(widget.request.id, accept: accept);
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
    final request = widget.request;
    return SurfaceCard(
      emphasis: SurfaceEmphasis.live,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const GwdChip(label: 'REQUEST', color: GwdColors.primaryRed),
              const SizedBox(width: GwdSpace.sm),
              Expanded(
                child: Text(
                  'from ${request.fromName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GwdType.footnote
                      .copyWith(color: GwdColors.inkTertiaryOf(context)),
                ),
              ),
            ],
          ),
          const SizedBox(height: GwdSpace.sm),
          Text(request.title,
              style: GwdType.title3.copyWith(color: GwdColors.inkOf(context))),
          if (request.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(request.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GwdType.footnote
                    .copyWith(color: GwdColors.inkSecondaryOf(context))),
          ],
          const SizedBox(height: GwdSpace.lg),
          Row(
            children: [
              Expanded(
                child: PrimaryButton(
                  label: 'Accept',
                  busy: _busy,
                  onPressed: () => _respond(true),
                ),
              ),
              const SizedBox(width: GwdSpace.md),
              SecondaryButton(
                label: 'Decline',
                onPressed: _busy ? null : () => _respond(false),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
