import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/responsive.dart';
import '../../app/theme/apple_motion.dart';
import '../../app/theme/gwd_theme.dart';
import '../../app/widgets/brand.dart';
import '../../app/widgets/common.dart';
import '../../core/models/schedule_category.dart';

/// Manage what kinds of thing can go on the schedule.
///
/// The same idea as departments: a club's calendar holds whatever that club
/// does — rehearsals, shoots, sponsor visits, exam weeks — so the list is data,
/// not an enum, and the President can change it without a release.
class CategoryAdminPage extends StatelessWidget {
  const CategoryAdminPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.storeOf(context);
    final layout = Layout.of(context);
    final categories = store.categories;

    return Scaffold(
      backgroundColor: GwdColors.canvasOf(context),
      appBar: AppBar(
        title: Text('Schedule categories',
            style: GwdType.title3.copyWith(color: GwdColors.inkOf(context))),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditor(context),
        backgroundColor: GwdColors.primaryRed,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded, size: 20),
        label: Text('New', style: GwdType.headline.copyWith(color: Colors.white)),
      ),
      body: ContentWidth(
        child: ListView(
          padding: EdgeInsets.fromLTRB(layout.gutter, GwdSpace.lg, layout.gutter, 110),
          children: [
            Container(
              padding: const EdgeInsets.all(GwdSpace.md),
              decoration: BoxDecoration(
                color: GwdColors.sunkenOf(context),
                borderRadius: BorderRadius.circular(GwdRadius.md),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 15, color: GwdColors.inkTertiaryOf(context)),
                  const SizedBox(width: GwdSpace.md),
                  Expanded(
                    child: Text(
                      'Categories appear on the schedule filter and when anyone adds '
                      'an entry. Task deadlines are generated automatically and are '
                      'not listed here.',
                      style: GwdType.footnote
                          .copyWith(color: GwdColors.inkTertiaryOf(context)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: GwdSpace.xl),
            if (categories.isEmpty)
              const EmptyState(
                icon: Icons.category_outlined,
                title: 'No categories yet',
                message: 'Add the first one and it becomes available everywhere.',
              )
            else
              for (var i = 0; i < categories.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: GwdSpace.sm),
                  child: AppleStaggerItem(
                    index: i,
                    child: _CategoryRow(
                      key: ValueKey(categories[i].id),
                      category: categories[i],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({super.key, required this.category});
  final ScheduleCategory category;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: category.active ? 1 : 0.5,
      child: SurfaceCard(
        onTap: () => _showEditor(context, existing: category),
        padding: const EdgeInsets.all(GwdSpace.md),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: category.tint.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(GwdRadius.md),
              ),
              child: Icon(category.iconData, size: 19, color: category.tint),
            ),
            const SizedBox(width: GwdSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(category.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GwdType.headline
                                .copyWith(color: GwdColors.inkOf(context))),
                      ),
                      if (!category.active) ...[
                        const SizedBox(width: GwdSpace.sm),
                        GwdChip(
                            label: 'HIDDEN',
                            color: GwdColors.inkTertiaryOf(context),
                            dense: true),
                      ],
                    ],
                  ),
                  const SizedBox(height: 1),
                  Text(
                    category.count > 0
                        ? '${category.count} upcoming'
                        : (category.blurb.isEmpty ? 'No entries yet' : category.blurb),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GwdType.footnote
                        .copyWith(color: GwdColors.inkTertiaryOf(context)),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 18, color: GwdColors.inkTertiaryOf(context)),
          ],
        ),
      ),
    );
  }
}

Future<void> _showEditor(BuildContext context, {ScheduleCategory? existing}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CategoryEditor(existing: existing),
  );
}

class _CategoryEditor extends StatefulWidget {
  const _CategoryEditor({this.existing});
  final ScheduleCategory? existing;

  @override
  State<_CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends State<_CategoryEditor> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _blurb = TextEditingController(text: widget.existing?.blurb ?? '');
  late String _icon = widget.existing?.icon ?? 'flag';
  late String _color = widget.existing?.colorHex ?? schedulePalette.first;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _blurb.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().length < 2) return;
    setState(() { _busy = true; _error = null; });
    try {
      await AppScope.readStore(context).saveCategory(
        id: widget.existing?.id,
        name: _name.text.trim(),
        icon: _icon,
        color: _color,
        blurb: _blurb.text.trim(),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    final existing = widget.existing;
    if (existing == null) return;
    setState(() => _busy = true);
    try {
      final store = AppScope.readStore(context);
      final navigator = Navigator.of(context);
      final messenger = ScaffoldMessenger.of(context);
      final message = await store.removeCategory(existing.id);
      navigator.pop();
      // The server hides rather than deletes when entries still reference it —
      // say so, instead of letting the button quietly do something else.
      if (message != null) {
        messenger.showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (error) {
      if (mounted) setState(() { _error = '$error'; _busy = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final existing = widget.existing;
    final tint = hexToColor(_color);

    return DraggableScrollableSheet(
      initialChildSize: 0.86,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, controller) => Container(
        decoration: BoxDecoration(
          color: GwdColors.canvasOf(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(GwdRadius.xxl)),
        ),
        child: Column(
          children: [
            SheetHeader(
              title: existing == null ? 'New category' : 'Edit category',
              accent: tint,
            ),
            Expanded(
              child: ListView(
                controller: controller,
                padding: EdgeInsets.fromLTRB(
                    GwdSpace.xl, 0, GwdSpace.xl, GwdSpace.xl + inset),
                children: [
                  // Live preview, so the choices below have an obvious effect.
                  Center(
                    child: BracketFrame(
                      color: tint.withValues(alpha: 0.4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: GwdSpace.xl, vertical: GwdSpace.md),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(iconFor(_icon), size: 18, color: tint),
                          const SizedBox(width: GwdSpace.sm),
                          Text(
                            _name.text.trim().isEmpty ? 'Category' : _name.text.trim(),
                            style: GwdType.title3.copyWith(color: tint),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: GwdSpace.xl),
                  GwdField(
                    label: 'Name',
                    controller: _name,
                    hint: 'Rehearsal',
                    autofocus: existing == null,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: GwdSpace.lg),
                  GwdField(
                    label: 'What it is for',
                    controller: _blurb,
                    hint: 'Run-throughs before the real thing. Optional.',
                  ),

                  const SizedBox(height: GwdSpace.xl),
                  Text('COLOUR',
                      style: GwdType.eyebrow
                          .copyWith(color: GwdColors.inkTertiaryOf(context))),
                  const SizedBox(height: GwdSpace.sm),
                  Wrap(
                    spacing: GwdSpace.sm,
                    runSpacing: GwdSpace.sm,
                    children: [
                      for (final hex in schedulePalette)
                        PressableScale(
                          haptic: HapticStrength.selection,
                          onTap: () => setState(() => _color = hex),
                          child: AnimatedContainer(
                            duration: AppleDuration.fast,
                            curve: AppleCurves.overshoot,
                            width: 36,
                            height: 36,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: hexToColor(hex),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _color == hex
                                    ? GwdColors.inkOf(context)
                                    : Colors.transparent,
                                width: 2.5,
                              ),
                            ),
                            child: _color == hex
                                ? const Icon(Icons.check_rounded,
                                    size: 16, color: Colors.white)
                                : null,
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: GwdSpace.xl),
                  Text('ICON',
                      style: GwdType.eyebrow
                          .copyWith(color: GwdColors.inkTertiaryOf(context))),
                  const SizedBox(height: GwdSpace.sm),
                  Wrap(
                    spacing: GwdSpace.sm,
                    runSpacing: GwdSpace.sm,
                    children: [
                      for (final entry in scheduleIconChoices.entries)
                        PressableScale(
                          haptic: HapticStrength.selection,
                          onTap: () => setState(() => _icon = entry.key),
                          child: AnimatedContainer(
                            duration: AppleDuration.fast,
                            width: 44,
                            height: 44,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _icon == entry.key
                                  ? tint
                                  : GwdColors.surfaceOf(context),
                              borderRadius: BorderRadius.circular(GwdRadius.md),
                              border: Border.all(
                                color: _icon == entry.key
                                    ? tint
                                    : GwdColors.hairlineOf(context),
                              ),
                            ),
                            child: Icon(
                              iconFor(entry.key),
                              size: 19,
                              color: _icon == entry.key
                                  ? Colors.white
                                  : GwdColors.inkSecondaryOf(context),
                            ),
                          ),
                        ),
                    ],
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: GwdSpace.lg),
                    ErrorNote(message: _error!),
                  ],

                  const SizedBox(height: GwdSpace.xxl),
                  PrimaryButton(
                    label: existing == null ? 'Create category' : 'Save changes',
                    busy: _busy,
                    tone: tint,
                    onPressed: _name.text.trim().length >= 2 ? _save : null,
                  ),
                  if (existing != null) ...[
                    const SizedBox(height: GwdSpace.md),
                    SecondaryButton(
                      label: existing.count > 0 ? 'Hide from new entries' : 'Delete category',
                      icon: existing.count > 0
                          ? Icons.visibility_off_outlined
                          : Icons.delete_outline_rounded,
                      expand: true,
                      destructive: true,
                      onPressed: _busy ? null : _remove,
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
