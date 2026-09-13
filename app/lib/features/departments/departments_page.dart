import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme/apple_motion.dart';
import '../../app/theme/gwd_theme.dart';
import '../../app/widgets/common.dart';
import '../../core/models/club_role.dart';
import '../../core/models/department.dart';

/// Section 6.6 — Department Management.
///
/// President and Club Directors only, and deliberately reached from the profile
/// sheet rather than the main nav so it adds zero visual weight to the app
/// everyone else uses.
///
/// This screen is the whole reason departments stopped being a Dart enum.
class DepartmentsPage extends StatelessWidget {
  const DepartmentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.storeOf(context);
    final gutter = GwdSpace.gutter(MediaQuery.sizeOf(context).width);
    final departments = store.departments;

    return Scaffold(
      backgroundColor: GwdColors.canvasOf(context),
      appBar: AppBar(
        title: Text('Departments',
            style: GwdType.title3.copyWith(color: GwdColors.inkOf(context))),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditor(context),
        backgroundColor: GwdColors.primaryRed,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded, size: 20),
        label: Text('New', style: GwdType.headline.copyWith(color: Colors.white)),
      ),
      body: departments.isEmpty
          ? const EmptyState(
              icon: Icons.workspaces_outline,
              title: 'No departments yet',
              message:
                  'Create the first one and members will be able to pick it when they sign up.',
            )
          : ListView.builder(
              padding: EdgeInsets.fromLTRB(gutter, GwdSpace.lg, gutter, 96),
              itemCount: departments.length,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.only(bottom: GwdSpace.md),
                child: AppleStaggerItem(
                  index: i,
                  child: _DepartmentCard(
                    key: ValueKey(departments[i].id),
                    department: departments[i],
                  ),
                ),
              ),
            ),
    );
  }
}

class _DepartmentCard extends StatelessWidget {
  const _DepartmentCard({super.key, required this.department});
  final Department department;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.storeOf(context);
    final inactive = !department.active;

    return Opacity(
      opacity: inactive ? 0.55 : 1,
      child: SurfaceCard(
        onTap: () => _showEditor(context, existing: department),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Avatar(
                    initials: department.initials, tint: department.tint, size: 42),
                const SizedBox(width: GwdSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(department.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GwdType.headline
                                    .copyWith(color: GwdColors.inkOf(context))),
                          ),
                          if (inactive) ...[
                            const SizedBox(width: GwdSpace.sm),
                            GwdChip(
                                label: 'INACTIVE',
                                color: GwdColors.inkTertiaryOf(context),
                                dense: true),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${department.memberCount} member${department.memberCount == 1 ? '' : 's'}',
                        style: GwdType.footnote
                            .copyWith(color: GwdColors.inkTertiaryOf(context)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: GwdSpace.md),
            Container(
              padding: const EdgeInsets.all(GwdSpace.md),
              decoration: BoxDecoration(
                color: GwdColors.sunkenOf(context),
                borderRadius: BorderRadius.circular(GwdRadius.md),
              ),
              child: Row(
                children: [
                  Icon(Icons.flag_outlined,
                      size: 15, color: GwdColors.inkTertiaryOf(context)),
                  const SizedBox(width: GwdSpace.sm),
                  Expanded(
                    child: Text(
                      department.hasLead
                          ? store.memberName(department.leadUserId)
                          : 'No Lead assigned',
                      style: GwdType.callout.copyWith(
                        color: department.hasLead
                            ? GwdColors.inkOf(context)
                            : GwdColors.inkTertiaryOf(context),
                      ),
                    ),
                  ),
                  PressableScale(
                    haptic: HapticStrength.selection,
                    onTap: () => _pickLead(context, department),
                    child: Text(department.hasLead ? 'Change' : 'Assign',
                        style: GwdType.footnote.copyWith(color: GwdColors.primaryRed)),
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

Future<void> _pickLead(BuildContext context, Department department) async {
  final store = AppScope.readStore(context);
  // Only a Member of this department, or the sitting Lead, can lead it.
  final candidates = store.members
      .where((m) =>
          m.departmentId == department.id &&
          (m.role == ClubRole.clubMember || m.role == ClubRole.clubLead))
      .toList();

  await showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => Container(
      decoration: BoxDecoration(
        color: GwdColors.canvasOf(sheetContext),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(GwdRadius.xxl)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetHeader(title: 'Lead of ${department.name}'),
            if (candidates.isEmpty)
              const Padding(
                padding: EdgeInsets.all(GwdSpace.xl),
                child: EmptyState(
                  compact: true,
                  icon: Icons.person_search_outlined,
                  title: 'Nobody to promote',
                  message: 'This department has no approved members yet.',
                ),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(
                      GwdSpace.xl, 0, GwdSpace.xl, GwdSpace.xl),
                  children: [
                    for (final member in candidates)
                      Padding(
                        padding: const EdgeInsets.only(bottom: GwdSpace.sm),
                        child: PressableScale(
                          onTap: () async {
                            Navigator.pop(sheetContext);
                            await store.setDepartmentLead(department.id, member.id);
                          },
                          child: Container(
                            padding: const EdgeInsets.all(GwdSpace.md),
                            decoration: BoxDecoration(
                              color: GwdColors.surfaceOf(sheetContext),
                              borderRadius: BorderRadius.circular(GwdRadius.lg),
                              border: Border.all(
                                color: member.id == department.leadUserId
                                    ? GwdColors.primaryRed
                                    : GwdColors.hairlineOf(sheetContext),
                              ),
                            ),
                            child: Row(
                              children: [
                                Avatar(
                                    initials: member.initials,
                                    tint: member.tint,
                                    size: 34),
                                const SizedBox(width: GwdSpace.md),
                                Expanded(
                                  child: Text(member.name,
                                      style: GwdType.headline.copyWith(
                                          color: GwdColors.inkOf(sheetContext))),
                                ),
                                if (member.id == department.leadUserId)
                                  const Icon(Icons.check_circle_rounded,
                                      size: 19, color: GwdColors.primaryRed),
                              ],
                            ),
                          ),
                        ),
                      ),
                    if (department.hasLead) ...[
                      const SizedBox(height: GwdSpace.sm),
                      SecondaryButton(
                        label: 'Remove current Lead',
                        expand: true,
                        destructive: true,
                        onPressed: () async {
                          Navigator.pop(sheetContext);
                          await store.setDepartmentLead(department.id, null);
                        },
                      ),
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

Future<void> _showEditor(BuildContext context, {Department? existing}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _DepartmentEditor(existing: existing),
  );
}

class _DepartmentEditor extends StatefulWidget {
  const _DepartmentEditor({this.existing});
  final Department? existing;

  @override
  State<_DepartmentEditor> createState() => _DepartmentEditorState();
}

class _DepartmentEditorState extends State<_DepartmentEditor> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _description =
      TextEditingController(text: widget.existing?.description ?? '');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().length < 2) return;
    setState(() { _busy = true; _error = null; });
    final store = AppScope.readStore(context);
    try {
      if (widget.existing == null) {
        await store.createDepartment(_name.text.trim(),
            description: _description.text.trim());
      } else {
        await store.updateDepartment(widget.existing!.id,
            name: _name.text.trim(), description: _description.text.trim());
      }
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    final inset = MediaQuery.viewInsetsOf(context).bottom;

    return Container(
      decoration: BoxDecoration(
        color: GwdColors.canvasOf(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(GwdRadius.xxl)),
      ),
      padding: EdgeInsets.only(bottom: inset),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetHeader(
              title: existing == null ? 'New department' : 'Edit department',
              subtitle: existing == null
                  ? 'Members can pick it at signup straight away'
                  : null,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  GwdSpace.xl, 0, GwdSpace.xl, GwdSpace.xl),
              child: Column(
                children: [
                  GwdField(
                      label: 'Name',
                      controller: _name,
                      hint: 'Social Media & Marketing',
                      autofocus: true),
                  const SizedBox(height: GwdSpace.lg),
                  GwdField(
                      label: 'What they do',
                      controller: _description,
                      hint: 'Optional',
                      maxLines: 2),
                  if (_error != null) ...[
                    const SizedBox(height: GwdSpace.lg),
                    ErrorNote(message: _error!),
                  ],
                  const SizedBox(height: GwdSpace.xl),
                  PrimaryButton(
                    label: existing == null ? 'Create department' : 'Save changes',
                    busy: _busy,
                    onPressed: _save,
                  ),
                  if (existing != null && existing.active) ...[
                    const SizedBox(height: GwdSpace.md),
                    SecondaryButton(
                      label: 'Deactivate',
                      icon: Icons.archive_outlined,
                      expand: true,
                      destructive: true,
                      // Deactivate, never delete: tasks and history stay
                      // auditable.
                      onPressed: _busy
                          ? null
                          : () async {
                              // Captured before the await so nothing reaches
                              // across the async gap for a BuildContext.
                              final store = AppScope.readStore(context);
                              final navigator = Navigator.of(context);
                              try {
                                await store.deactivateDepartment(existing.id);
                                if (mounted) navigator.pop();
                              } catch (error) {
                                if (mounted) setState(() => _error = '$error');
                              }
                            },
                    ),
                  ],
                  if (existing != null && !existing.active) ...[
                    const SizedBox(height: GwdSpace.md),
                    SecondaryButton(
                      label: 'Reactivate',
                      icon: Icons.unarchive_outlined,
                      expand: true,
                      onPressed: () async {
                        final store = AppScope.readStore(context);
                        final navigator = Navigator.of(context);
                        await store.updateDepartment(existing.id, active: true);
                        if (mounted) navigator.pop();
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
