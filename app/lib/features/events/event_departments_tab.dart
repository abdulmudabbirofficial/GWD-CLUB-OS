import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/responsive.dart';
import '../../app/theme/apple_motion.dart';
import '../../app/theme/gwd_theme.dart';
import '../../app/widgets/common.dart';
import '../../core/api/api_client.dart';
import '../../core/models/club_event.dart';
import '../../core/models/club_task.dart';
import 'add_event_task_sheet.dart';

/// Who is carrying which part of this event.
///
/// Section 31: this is *Department Progress*, not a ranking. Departments are
/// listed in the order they were brought in, never sorted by how well they are
/// doing, and the copy never compares one to another. A club runs on people
/// covering for each other, and a league table of departments quietly stops
/// that happening.
class EventDepartmentsTab extends StatelessWidget {
  const EventDepartmentsTab({
    super.key,
    required this.eventId,
    required this.workspace,
  });

  final String eventId;
  final EventWorkspace workspace;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.storeOf(context);
    final gutter = Layout.of(context).gutter;
    final board = store.boardFor(eventId) ?? const [];

    if (workspace.departments.isEmpty) {
      return EmptyState(
        icon: Icons.workspaces_outline,
        title: 'No departments on this yet',
        message: workspace.canManage
            ? 'Bring a department in and give them something to own.'
            : 'Nobody has been given a share of this event yet.',
        action: workspace.canManage
            ? SecondaryButton(
                label: 'Bring a department in',
                icon: Icons.add_rounded,
                onPressed: () => _addDepartment(context, store, eventId, workspace),
              )
            : null,
      );
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(gutter, GwdSpace.lg, gutter, GwdSpace.xxxl),
      children: [
        for (var i = 0; i < workspace.departments.length; i++)
          AppleStaggerItem(
            index: i,
            child: Padding(
              padding: const EdgeInsets.only(bottom: GwdSpace.md),
              child: _DepartmentCard(
                eventId: eventId,
                department: workspace.departments[i],
                tasks: board
                    .where((c) => c.departmentId == workspace.departments[i].departmentId)
                    .toList(),
                canManage: workspace.canManage,
                allDepartments: workspace.departments,
              ),
            ),
          ),
        if (workspace.canManage) ...[
          const SizedBox(height: GwdSpace.sm),
          SecondaryButton(
            label: 'Bring another department in',
            icon: Icons.add_rounded,
            expand: true,
            onPressed: () => _addDepartment(context, store, eventId, workspace),
          ),
        ],
      ],
    );
  }
}

Future<void> _addDepartment(
  BuildContext context,
  dynamic store,
  String eventId,
  EventWorkspace workspace,
) async {
  final used = workspace.departments.map((d) => d.departmentId).toSet();
  final available =
      store.departments.where((d) => d.active && !used.contains(d.id)).toList();
  final messenger = ScaffoldMessenger.of(context);

  if (available.isEmpty) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Every department is already involved.')),
    );
    return;
  }

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
            const SheetHeader(
              title: 'Bring a department in',
              subtitle: 'Their Lead can then add and hand out the work.',
            ),
            for (final d in available)
              ListTile(
                leading: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                      color: d.tint, borderRadius: BorderRadius.circular(3)),
                ),
                title: Text(d.name,
                    style: GwdType.body.copyWith(color: GwdColors.inkOf(sheetContext))),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  try {
                    await store.addEventDepartment(eventId, d.id);
                  } on ApiException catch (e) {
                    messenger.showSnackBar(SnackBar(content: Text(e.message)));
                  }
                },
              ),
            const SizedBox(height: GwdSpace.md),
          ],
        ),
      ),
    ),
  );
}

class _DepartmentCard extends StatefulWidget {
  const _DepartmentCard({
    required this.eventId,
    required this.department,
    required this.tasks,
    required this.canManage,
    required this.allDepartments,
  });

  final String eventId;
  final EventDepartment department;
  final List<EventTaskCard> tasks;
  final bool canManage;
  final List<EventDepartment> allDepartments;

  @override
  State<_DepartmentCard> createState() => _DepartmentCardState();
}

class _DepartmentCardState extends State<_DepartmentCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.department;
    final store = AppScope.readStore(context);
    final department = store.departmentById(d.departmentId);
    final tint = department?.tint ?? GwdColors.inkSecondaryOf(context);

    // Encouraging, never comparative. "3 left" is a fact somebody can act on;
    // "72% — 3rd of 5" is a scoreboard nobody asked for.
    final remaining = d.total - d.done;
    final line = switch ((d.total, remaining)) {
      (0, _) => 'Nothing added yet',
      (_, 0) => 'All done',
      (_, 1) => 'One left',
      _ => '$remaining left of ${d.total}',
    };

    return SurfaceCard(
      padding: const EdgeInsets.all(GwdSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PressableScale(
            onTap: () => setState(() => _open = !_open),
            pressedScale: 0.99,
            child: Row(
              children: [
                ProgressArc(
                  progress: d.total == 0 ? 0 : d.done / d.total,
                  size: 44,
                  strokeWidth: 4,
                  color: tint,
                  child: Text(
                    d.total == 0 ? '–' : '${d.progress}',
                    style: GwdType.numeric.copyWith(
                        fontSize: 12, color: GwdColors.inkOf(context)),
                  ),
                ),
                const SizedBox(width: GwdSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(d.name,
                          style: GwdType.headline
                              .copyWith(color: GwdColors.inkOf(context))),
                      const SizedBox(height: 1),
                      Text(line,
                          style: GwdType.footnote.copyWith(
                              color: remaining == 0 && d.total > 0
                                  ? GwdColors.success
                                  : GwdColors.inkTertiaryOf(context))),
                    ],
                  ),
                ),
                AnimatedRotation(
                  turns: _open ? 0.5 : 0,
                  duration: AppleDuration.standard,
                  curve: AppleCurves.standard,
                  child: Icon(Icons.expand_more_rounded,
                      size: 20, color: GwdColors.inkTertiaryOf(context)),
                ),
              ],
            ),
          ),

          if (d.notes.isNotEmpty) ...[
            const SizedBox(height: GwdSpace.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(GwdSpace.md),
              decoration: BoxDecoration(
                color: GwdColors.sunkenOf(context),
                borderRadius: BorderRadius.circular(GwdRadius.md),
              ),
              child: Text(d.notes,
                  style: GwdType.callout
                      .copyWith(color: GwdColors.inkSecondaryOf(context))),
            ),
          ],

          AnimatedSize(
            duration: AppleDuration.standard,
            curve: AppleCurves.standard,
            alignment: Alignment.topCenter,
            child: _open
                ? Padding(
                    padding: const EdgeInsets.only(top: GwdSpace.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.tasks.isEmpty)
                          Text('No work listed for them yet.',
                              style: GwdType.footnote.copyWith(
                                  color: GwdColors.inkTertiaryOf(context)))
                        else
                          for (final task in widget.tasks)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 7),
                              child: Row(
                                children: [
                                  Icon(task.status.icon,
                                      size: 14, color: task.status.tint),
                                  const SizedBox(width: GwdSpace.sm),
                                  Expanded(
                                    child: Text(
                                      task.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GwdType.callout.copyWith(
                                        color: task.status == TaskStatus.completed
                                            ? GwdColors.inkTertiaryOf(context)
                                            : GwdColors.inkOf(context),
                                        decoration:
                                            task.status == TaskStatus.completed
                                                ? TextDecoration.lineThrough
                                                : null,
                                        decorationColor:
                                            GwdColors.inkTertiaryOf(context),
                                      ),
                                    ),
                                  ),
                                  if (task.assigneeName != null)
                                    Text(task.assigneeName!.split(' ').first,
                                        style: GwdType.caption.copyWith(
                                            fontSize: 9.5,
                                            letterSpacing: 0,
                                            color: GwdColors.inkTertiaryOf(context)))
                                  else
                                    Text('unclaimed',
                                        style: GwdType.caption.copyWith(
                                            fontSize: 9.5,
                                            letterSpacing: 0,
                                            color: GwdColors.warning)),
                                ],
                              ),
                            ),
                        if (widget.canManage) ...[
                          const SizedBox(height: GwdSpace.md),
                          SecondaryButton(
                            label: 'Add work for ${d.name}',
                            icon: Icons.add_rounded,
                            expand: true,
                            onPressed: () => showAddEventTaskSheet(
                              context,
                              eventId: widget.eventId,
                              departments: widget.allDepartments,
                              initialDepartmentId: d.departmentId,
                            ),
                          ),
                        ],
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}
