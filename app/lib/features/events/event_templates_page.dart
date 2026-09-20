import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/responsive.dart';
import '../../app/theme/apple_motion.dart';
import '../../app/theme/gwd_theme.dart';
import '../../app/widgets/common.dart';
import '../../core/api/api_client.dart';
import '../../core/models/department.dart';
import '../../core/models/event_template.dart';
import '../../core/plural.dart';

/// The shapes the club runs again.
///
/// Templates are made from real events — finish a workshop, save it, start the
/// next one from it — so this page is a place to *read and tidy* them rather
/// than a builder. Nobody sits down to write an abstract plan, and a screen
/// that asked them to would stay empty.
///
/// Readable by everyone. Seeing that the club has a "Guest Lecture" plan is
/// useful to the member being asked to help run one, and there is nothing
/// private in it.
class EventTemplatesPage extends StatefulWidget {
  const EventTemplatesPage({super.key});

  @override
  State<EventTemplatesPage> createState() => _EventTemplatesPageState();
}

class _EventTemplatesPageState extends State<EventTemplatesPage> {
  @override
  Widget build(BuildContext context) {
    final store = AppScope.storeOf(context);
    final templates = store.eventTemplates;
    final gutter = GwdSpace.gutter(MediaQuery.sizeOf(context).width);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Event templates')),
      body: ContentWidth(
        child: RefreshIndicator(
          onRefresh: store.loadEventTemplates,
          child: templates.isEmpty
              ? ListView(
                  children: const [
                    SizedBox(height: GwdSpace.xxxl),
                    EmptyState(
                      icon: Icons.bookmarks_outlined,
                      title: 'No templates yet',
                      // Told where they come from, because there is deliberately
                      // no "new template" button here — one made from nothing
                      // would be a guess at what the club does.
                      message: 'Open an event that went well and choose '
                          '"Save as a template". The next one of its kind then '
                          'starts with its departments and tasks already in.',
                    ),
                  ],
                )
              : ListView.builder(
                  padding: EdgeInsets.fromLTRB(
                      gutter, GwdSpace.md, gutter, GwdSpace.xxxl),
                  itemCount: templates.length,
                  itemBuilder: (context, i) => AppleStaggerItem(
                    index: i,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: GwdSpace.sm),
                      child: _TemplateCard(
                        template: templates[i],
                        departments: store.departments,
                        onChanged: () => setState(() {}),
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.template,
    required this.departments,
    required this.onChanged,
  });

  final EventTemplate template;
  final List<Department> departments;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final me = AppScope.sessionOf(context).me;
    final caps = AppScope.storeOf(context).capabilities;
    // Whoever saved it, or the executive tier. A template is shared club
    // property once it exists — a Lead who saved "Workshop" and then left
    // should not take the club's workshop plan with them — but letting anybody
    // edit one means the plan changes under the people using it.
    final mine = me != null && template.createdBy == me.id;
    final canEdit = mine || caps.canManageDepartments;

    return SurfaceCard(
      padding: const EdgeInsets.all(GwdSpace.lg),
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
                    Text(template.name,
                        style: GwdType.headline
                            .copyWith(color: GwdColors.inkOf(context))),
                    const SizedBox(height: 1),
                    Text(
                      [
                        countOf(template.departmentCount, 'department'),
                        countOf(template.taskCount, 'task'),
                        template.usageLabel,
                      ].join(' · '),
                      style: GwdType.caption
                          .copyWith(color: GwdColors.inkTertiaryOf(context)),
                    ),
                  ],
                ),
              ),
              if (canEdit)
                PopupMenuButton<String>(
                  tooltip: 'Change this template',
                  icon: Icon(Icons.more_horiz_rounded,
                      size: 19, color: GwdColors.inkTertiaryOf(context)),
                  onSelected: (value) => value == 'rename'
                      ? _rename(context)
                      : _remove(context),
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'rename', child: Text('Rename it')),
                    PopupMenuItem(value: 'remove', child: Text('Retire it')),
                  ],
                ),
            ],
          ),
          if (template.description.isNotEmpty) ...[
            const SizedBox(height: GwdSpace.sm),
            Text(template.description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: GwdType.footnote
                    .copyWith(color: GwdColors.inkSecondaryOf(context))),
          ],
          if (template.responsibilities.isNotEmpty) ...[
            const SizedBox(height: GwdSpace.md),
            for (final r in template.responsibilities)
              _ResponsibilityLine(
                responsibility: r,
                name: departments
                        .where((d) => d.id == r.departmentId)
                        .map((d) => d.name)
                        .firstOrNull ??
                    'A department that has since been retired',
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _rename(BuildContext context) async {
    final store = AppScope.readStore(context);
    final messenger = ScaffoldMessenger.of(context);
    final controller = TextEditingController(text: template.name);

    final confirmed = await showGwdSheet<bool>(
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
              const SheetHeader(title: 'Rename this template'),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    GwdSpace.xl, 0, GwdSpace.xl, GwdSpace.xl),
                child: Column(
                  children: [
                    GwdField(label: 'Call it', controller: controller, autofocus: true),
                    const SizedBox(height: GwdSpace.xl),
                    PrimaryButton(
                      label: 'Save',
                      onPressed: () => Navigator.of(sheetContext).pop(true),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final name = controller.text.trim();
    controller.dispose();
    if (confirmed != true || name.length < 2) return;
    try {
      await store.updateEventTemplate(template.id, {'name': name});
      onChanged();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _remove(BuildContext context) async {
    final store = AppScope.readStore(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Retire this template?'),
        // Honest about what happens: it is hidden, not erased, because events
        // created from it still point at it in the audit trail.
        content: Text('"${template.name}" stops being offered when anyone creates '
            'an event. Events already made from it are untouched.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Retire it',
                style: TextStyle(color: GwdColors.primaryRed)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await store.deleteEventTemplate(template.id);
      onChanged();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

class _ResponsibilityLine extends StatelessWidget {
  const _ResponsibilityLine({required this.responsibility, required this.name});

  final TemplateResponsibility responsibility;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: GwdSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(name.toUpperCase(),
              style: GwdType.eyebrow
                  .copyWith(color: GwdColors.inkTertiaryOf(context))),
          const SizedBox(height: GwdSpace.xs),
          for (final task in responsibility.tasks)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Container(
                      width: 3,
                      height: 3,
                      decoration: BoxDecoration(
                        color: GwdColors.inkTertiaryOf(context),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: GwdSpace.sm),
                  Expanded(
                    child: Text(task.title,
                        style: GwdType.footnote
                            .copyWith(color: GwdColors.inkSecondaryOf(context))),
                  ),
                  const SizedBox(width: GwdSpace.sm),
                  // The offset, spelled out. "-14" is a number you have to
                  // decode; "14 days before" is the thing itself.
                  Text(task.whenLabel,
                      style: GwdType.caption
                          .copyWith(color: GwdColors.inkTertiaryOf(context))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
