import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_scope.dart';
import '../../app/theme/apple_motion.dart';
import '../../app/theme/gwd_theme.dart';
import '../../app/widgets/common.dart';
import '../../core/models/club_task.dart';

/// Task detail.
///
/// One primary decision on the screen: the single next step this person can
/// take. Editing, deleting and the comment thread are all secondary, which is
/// what stops this becoming another control panel.
class TaskDetailPage extends StatefulWidget {
  const TaskDetailPage({super.key, required this.taskId});

  final String taskId;

  @override
  State<TaskDetailPage> createState() => _TaskDetailPageState();
}

class _TaskDetailPageState extends State<TaskDetailPage> {
  bool _busy = false;
  bool _loadingComments = true;
  List<TaskComment> _comments = const [];
  final _comment = TextEditingController();

  /// Set only when the task is not in the store's list — event work, which is
  /// deliberately kept off it.
  ClubTask? _fetched;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final detail = await AppScope.readStore(context).taskDetail(widget.taskId);
      if (mounted) {
        setState(() {
          _comments = detail.comments;
          _fetched = detail.task;
          _loadingComments = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingComments = false);
    }
  }

  Future<void> _advance(ClubTask task) async {
    final next = task.status.nextForOwner;
    if (next == null) return;
    setState(() => _busy = true);
    try {
      await AppScope.readStore(context).setTaskStatus(task, next);
      // Section 2 — haptic on task completion.
      if (next == TaskStatus.completed) await HapticFeedback.mediumImpact();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitComment() async {
    final body = _comment.text.trim();
    if (body.isEmpty) return;
    _comment.clear();
    try {
      final comment = await AppScope.readStore(context).addComment(widget.taskId, body);
      if (comment != null && mounted) setState(() => _comments = [..._comments, comment]);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.storeOf(context);
    final session = AppScope.sessionOf(context);
    // The store first, so a live update reaches this screen; the directly
    // fetched copy only covers work the list does not carry.
    final task = store.tasks.where((t) => t.id == widget.taskId).firstOrNull ?? _fetched;

    if (task == null) {
      return Scaffold(
        backgroundColor: GwdColors.canvasOf(context),
        appBar: AppBar(),
        body: _loadingComments
            ? const Padding(
                padding: EdgeInsets.all(GwdSpace.xl),
                child: SkeletonList(count: 3, height: 88),
              )
            : const EmptyState(
                icon: Icons.search_off_rounded,
                title: 'Task not found',
                message:
                    'It may have been removed, or you no longer have access to it.',
              ),
      );
    }

    final isOwner = task.assignedTo == session.me?.id;
    final isAssigner = task.assignedBy == session.me?.id;
    final gutter = GwdSpace.gutter(MediaQuery.sizeOf(context).width);

    return Scaffold(
      backgroundColor: GwdColors.canvasOf(context),
      appBar: AppBar(
        title: Text('Task', style: GwdType.title3.copyWith(color: GwdColors.inkOf(context))),
        actions: [
          if (isAssigner)
            IconButton(
              tooltip: 'Delete task',
              icon: const Icon(Icons.delete_outline_rounded, size: 20),
              onPressed: () => _confirmDelete(task),
            ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(gutter, 0, gutter, GwdSpace.xxxl),
        children: [
          FluidReveal(
            child: Text(task.title,
                style: GwdType.largeTitle.copyWith(color: GwdColors.inkOf(context))),
          ),
          const SizedBox(height: GwdSpace.md),

          FluidReveal(
            index: 1,
            child: Wrap(
              spacing: GwdSpace.sm,
              runSpacing: GwdSpace.sm,
              children: [
                GwdChip(
                    label: task.status.label.toUpperCase(),
                    color: task.status.tint,
                    icon: task.status.icon),
                if (task.dueLabel != null)
                  GwdChip(
                    label: task.dueLabel!.toUpperCase(),
                    color: task.isOverdue
                        ? GwdColors.critical
                        : GwdColors.inkSecondaryOf(context),
                    icon: Icons.schedule_rounded,
                  ),
                if (task.points > 0)
                  GwdChip(
                      label: '+${task.points} PTS',
                      color: GwdColors.inkTertiaryOf(context),
                      icon: Icons.auto_awesome_outlined),
                if (task.priority == TaskPriority.high)
                  const GwdChip(
                      label: 'HIGH PRIORITY',
                      color: GwdColors.warning,
                      icon: Icons.priority_high_rounded),
              ],
            ),
          ),

          const SizedBox(height: GwdSpace.xl),

          // ---------- the animated three-step track ----------
          FluidReveal(index: 2, child: _StatusTrack(status: task.status)),

          const SizedBox(height: GwdSpace.xl),

          if (task.description.isNotEmpty) ...[
            FluidReveal(
              index: 3,
              child: SurfaceCard(
                child: Text(
                  task.description,
                  style: GwdType.body.copyWith(color: GwdColors.inkSecondaryOf(context)),
                ),
              ),
            ),
            const SizedBox(height: GwdSpace.lg),
          ],

          FluidReveal(
            index: 4,
            child: SurfaceCard(
              child: Column(
                children: [
                  _PersonRow(
                    label: 'Assigned to',
                    name: store.memberName(task.assignedTo),
                    you: isOwner,
                  ),
                  Divider(height: GwdSpace.xl, color: GwdColors.hairlineOf(context)),
                  _PersonRow(
                    label: 'Assigned by',
                    name: store.memberName(task.assignedBy),
                    you: isAssigner,
                  ),
                  if (store.departmentById(task.departmentId) != null) ...[
                    Divider(height: GwdSpace.xl, color: GwdColors.hairlineOf(context)),
                    _PersonRow(
                      label: 'Department',
                      name: store.departmentById(task.departmentId)!.name,
                    ),
                  ],
                ],
              ),
            ),
          ),

          // ---------- the one primary action ----------
          if (isOwner && task.status.nextForOwner != null) ...[
            const SizedBox(height: GwdSpace.xl),
            PrimaryButton(
              label: task.status.advanceVerb,
              busy: _busy,
              icon: task.status == TaskStatus.inProgress
                  ? Icons.check_rounded
                  : Icons.play_arrow_rounded,
              onPressed: () => _advance(task),
            ),
          ],

          if (isOwner && task.status.isOpen && task.status != TaskStatus.blocked) ...[
            const SizedBox(height: GwdSpace.md),
            SecondaryButton(
              label: 'I\'m blocked on this',
              icon: Icons.report_problem_outlined,
              expand: true,
              onPressed: () => _markBlocked(task),
            ),
          ],

          const SizedBox(height: GwdSpace.xxl),

          // ---------- comments ----------
          const SectionHeader(
              title: 'Discussion', subtitle: 'Keep the context attached to the work'),
          if (_loadingComments)
            const SkeletonList(count: 2, height: 56)
          else if (_comments.isEmpty)
            Text('No comments yet.',
                style: GwdType.footnote.copyWith(color: GwdColors.inkTertiaryOf(context)))
          else
            for (final comment in _comments)
              Padding(
                padding: const EdgeInsets.only(bottom: GwdSpace.md),
                child: _CommentRow(comment: comment, isMe: comment.authorId == session.me?.id),
              ),

          const SizedBox(height: GwdSpace.md),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _comment,
                  style: GwdType.callout.copyWith(color: GwdColors.inkOf(context)),
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _submitComment(),
                  decoration: InputDecoration(
                    hintText: 'Add a comment…',
                    hintStyle:
                        GwdType.callout.copyWith(color: GwdColors.inkTertiaryOf(context)),
                    filled: true,
                    fillColor: GwdColors.sunkenOf(context),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: GwdSpace.lg, vertical: GwdSpace.md),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(GwdRadius.pill),
                      borderSide: BorderSide(color: GwdColors.hairlineOf(context)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(GwdRadius.pill),
                      borderSide: BorderSide(color: GwdColors.hairlineOf(context)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: GwdSpace.sm),
              PressableScale(
                onTap: _submitComment,
                child: Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                      color: GwdColors.primaryRed, shape: BoxShape.circle),
                  child: const Icon(Icons.arrow_upward_rounded,
                      size: 19, color: Colors.white),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _markBlocked(ClubTask task) async {
    final store = AppScope.readStore(context);
    setState(() => _busy = true);
    try {
      await store.setTaskStatus(task, TaskStatus.blocked);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmDelete(ClubTask task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: GwdColors.surfaceOf(context),
        title: Text('Delete this task?',
            style: GwdType.title3.copyWith(color: GwdColors.inkOf(context))),
        content: Text(
          'This removes it for ${AppScope.readStore(context).memberName(task.assignedTo)} too. It cannot be undone.',
          style: GwdType.callout.copyWith(color: GwdColors.inkSecondaryOf(context)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: GwdColors.critical)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await AppScope.readStore(context).deleteTask(task.id);
    if (mounted) Navigator.of(context).pop();
  }
}

/// The three-step rail. A status change physically travels along it rather than
/// swapping a label — this is the "task moving Pending → In Progress →
/// Completed should physically transition" requirement.
class _StatusTrack extends StatelessWidget {
  const _StatusTrack({required this.status});
  final TaskStatus status;

  @override
  Widget build(BuildContext context) {
    const steps = [TaskStatus.pending, TaskStatus.inProgress, TaskStatus.completed];
    final active = status.trackIndex;
    final blocked = status == TaskStatus.blocked;

    return Row(
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          Expanded(
            child: Column(
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedContainer(
                      duration: AppleDuration.slow,
                      curve: AppleCurves.overshoot,
                      width: i == active ? 30 : 22,
                      height: i == active ? 30 : 22,
                      decoration: BoxDecoration(
                        color: i <= active
                            ? (blocked && i == active
                                ? GwdColors.warning
                                : steps[i].tint)
                            : GwdColors.sunkenOf(context),
                        shape: BoxShape.circle,
                      ),
                    ),
                    if (i <= active)
                      Icon(
                        blocked && i == active
                            ? Icons.priority_high_rounded
                            : (i < active ? Icons.check_rounded : steps[i].icon),
                        size: i == active ? 15 : 12,
                        color: Colors.white,
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                AnimatedDefaultTextStyle(
                  duration: AppleDuration.standard,
                  style: GwdType.caption.copyWith(
                    fontSize: 9.5,
                    letterSpacing: 0.3,
                    color: i <= active
                        ? GwdColors.inkOf(context)
                        : GwdColors.inkTertiaryOf(context),
                  ),
                  child: Text(
                    blocked && i == active ? 'BLOCKED' : steps[i].label.toUpperCase(),
                  ),
                ),
              ],
            ),
          ),
          if (i < steps.length - 1)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: TweenAnimationBuilder<double>(
                  duration: AppleDuration.slow,
                  curve: AppleCurves.standard,
                  tween: Tween(begin: 0, end: i < active ? 1.0 : 0.0),
                  builder: (context, t, _) => Stack(
                    children: [
                      Container(height: 2, color: GwdColors.sunkenOf(context)),
                      FractionallySizedBox(
                        widthFactor: t,
                        child: Container(height: 2, color: steps[i + 1].tint),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.label, required this.name, this.you = false});
  final String label;
  final String name;
  final bool you;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label,
            style: GwdType.callout.copyWith(color: GwdColors.inkTertiaryOf(context))),
        const Spacer(),
        Text(you ? 'You' : name,
            style: GwdType.headline.copyWith(color: GwdColors.inkOf(context))),
      ],
    );
  }
}

class _CommentRow extends StatelessWidget {
  const _CommentRow({required this.comment, required this.isMe});
  final TaskComment comment;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(GwdSpace.md),
      decoration: BoxDecoration(
        color: isMe ? GwdColors.sunkenOf(context) : GwdColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(GwdRadius.lg),
        border: Border.all(color: GwdColors.hairlineOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(isMe ? 'You' : comment.authorName,
                  style: GwdType.caption.copyWith(color: GwdColors.inkOf(context))),
              const Spacer(),
              Text(
                '${comment.createdAt.day}/${comment.createdAt.month}',
                style: GwdType.caption
                    .copyWith(color: GwdColors.inkTertiaryOf(context), letterSpacing: 0),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(comment.body,
              style: GwdType.callout.copyWith(color: GwdColors.inkSecondaryOf(context))),
        ],
      ),
    );
  }
}
