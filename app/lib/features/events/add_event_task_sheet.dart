import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme/apple_motion.dart';
import '../../app/theme/gwd_theme.dart';
import '../../app/widgets/common.dart';
import '../../core/api/api_client.dart';
import '../../core/models/club_event.dart';
import '../../core/models/club_task.dart';

/// Add one piece of work to an event.
///
/// Assignee is deliberately optional: the useful thing at planning time is
/// writing down *what* needs doing. Who does it is a separate decision, often
/// made days later by somebody else, and blocking on it means the task never
/// gets written down at all.
Future<void> showAddEventTaskSheet(
  BuildContext context, {
  required String eventId,
  required List<EventDepartment> departments,
  String? initialDepartmentId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _AddEventTaskSheet(
      eventId: eventId,
      departments: departments,
      initialDepartmentId: initialDepartmentId,
    ),
  );
}

class _AddEventTaskSheet extends StatefulWidget {
  const _AddEventTaskSheet({
    required this.eventId,
    required this.departments,
    this.initialDepartmentId,
  });

  final String eventId;
  final List<EventDepartment> departments;
  final String? initialDepartmentId;

  @override
  State<_AddEventTaskSheet> createState() => _AddEventTaskSheetState();
}

class _AddEventTaskSheetState extends State<_AddEventTaskSheet> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  String? _departmentId;
  String? _assignee;
  DateTime? _due;
  TaskPriority _priority = TaskPriority.normal;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _departmentId = widget.initialDepartmentId ??
        (widget.departments.isEmpty ? null : widget.departments.first.departmentId);
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final store = AppScope.readStore(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await store.addEventTask(
        eventId: widget.eventId,
        departmentId: _departmentId!,
        title: _title.text.trim(),
        description: _description.text.trim(),
        assignedTo: _assignee,
        dueDate: _due,
        priority: _priority,
      );
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.storeOf(context);
    final valid = _title.text.trim().length >= 2 && _departmentId != null;

    // Only people in the chosen department, because that is who the server will
    // actually accept — offering the whole club here just produces a refusal.
    final candidates =
        store.members.where((m) => m.departmentId == _departmentId).toList();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color: GwdColors.surfaceOf(context),
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(GwdRadius.xxl)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SheetHeader(
                  title: 'Add to the board',
                  subtitle: 'Leave it unassigned and somebody can pick it up.',
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      GwdSpace.xl, 0, GwdSpace.xl, GwdSpace.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      GwdField(
                        label: 'What needs doing',
                        controller: _title,
                        autofocus: true,
                        hint: 'Print the banners',
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: GwdSpace.lg),

                      Text('DEPARTMENT',
                          style: GwdType.eyebrow
                              .copyWith(color: GwdColors.inkTertiaryOf(context))),
                      const SizedBox(height: GwdSpace.sm),
                      Wrap(
                        spacing: GwdSpace.sm,
                        runSpacing: GwdSpace.sm,
                        children: [
                          for (final d in widget.departments)
                            _Tag(
                              label: d.name,
                              selected: _departmentId == d.departmentId,
                              onTap: () => setState(() {
                                _departmentId = d.departmentId;
                                _assignee = null;
                              }),
                            ),
                        ],
                      ),
                      const SizedBox(height: GwdSpace.lg),

                      Text('WHO (OPTIONAL)',
                          style: GwdType.eyebrow
                              .copyWith(color: GwdColors.inkTertiaryOf(context))),
                      const SizedBox(height: GwdSpace.sm),
                      if (candidates.isEmpty)
                        Text('Nobody in that department yet.',
                            style: GwdType.footnote.copyWith(
                                color: GwdColors.inkTertiaryOf(context)))
                      else
                        Wrap(
                          spacing: GwdSpace.sm,
                          runSpacing: GwdSpace.sm,
                          children: [
                            for (final m in candidates)
                              _Tag(
                                label: m.firstName,
                                selected: _assignee == m.id,
                                onTap: () => setState(() =>
                                    _assignee = _assignee == m.id ? null : m.id),
                              ),
                          ],
                        ),
                      const SizedBox(height: GwdSpace.lg),

                      Row(
                        children: [
                          Expanded(
                            child: _MiniPicker(
                              label: 'Due',
                              value: _due == null
                                  ? 'No date'
                                  : '${_due!.day}/${_due!.month}',
                              icon: Icons.event_rounded,
                              muted: _due == null,
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: _due ?? DateTime.now(),
                                  firstDate: DateTime.now()
                                      .subtract(const Duration(days: 30)),
                                  lastDate: DateTime.now()
                                      .add(const Duration(days: 365)),
                                );
                                if (picked != null) setState(() => _due = picked);
                              },
                            ),
                          ),
                          const SizedBox(width: GwdSpace.sm),
                          Expanded(
                            child: _MiniPicker(
                              label: 'Priority',
                              value: _priority.label,
                              icon: Icons.flag_outlined,
                              muted: _priority == TaskPriority.normal,
                              onTap: () => setState(() {
                                _priority = switch (_priority) {
                                  TaskPriority.low => TaskPriority.normal,
                                  TaskPriority.normal => TaskPriority.high,
                                  TaskPriority.high => TaskPriority.low,
                                };
                              }),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: GwdSpace.lg),

                      GwdField(
                        label: 'Notes',
                        controller: _description,
                        maxLines: 3,
                        hint: 'Anything the person picking this up should know.',
                      ),

                      if (_error != null) ...[
                        const SizedBox(height: GwdSpace.lg),
                        ErrorNote(message: _error!),
                      ],
                      const SizedBox(height: GwdSpace.xl),
                      PrimaryButton(
                        label: 'Add to board',
                        busy: _saving,
                        onPressed: valid ? _save : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.selected, required this.onTap});
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
        padding: const EdgeInsets.symmetric(
            horizontal: GwdSpace.md, vertical: GwdSpace.sm),
        decoration: BoxDecoration(
          color: selected ? GwdColors.primaryRed : GwdColors.sunkenOf(context),
          borderRadius: BorderRadius.circular(GwdRadius.sm),
        ),
        child: Text(
          label,
          style: GwdType.footnote.copyWith(
            color: selected ? Colors.white : GwdColors.inkSecondaryOf(context),
          ),
        ),
      ),
    );
  }
}

class _MiniPicker extends StatelessWidget {
  const _MiniPicker({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
    this.muted = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      pressedScale: 0.97,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: GwdSpace.md, vertical: GwdSpace.md),
        decoration: BoxDecoration(
          color: GwdColors.sunkenOf(context),
          borderRadius: BorderRadius.circular(GwdRadius.md),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: GwdColors.inkTertiaryOf(context)),
            const SizedBox(width: GwdSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label.toUpperCase(),
                      style: GwdType.eyebrow.copyWith(
                          fontSize: 8.5,
                          color: GwdColors.inkTertiaryOf(context))),
                  Text(value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GwdType.footnote.copyWith(
                        color: muted
                            ? GwdColors.inkTertiaryOf(context)
                            : GwdColors.inkOf(context),
                      )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
