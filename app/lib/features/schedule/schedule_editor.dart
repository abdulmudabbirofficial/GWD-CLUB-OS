import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme/apple_motion.dart';
import '../../app/theme/gwd_theme.dart';
import '../../app/widgets/common.dart';
import '../../core/models/schedule_category.dart';
import '../../core/models/schedule_entry.dart';
import 'category_admin_page.dart';

Future<void> showScheduleEditor(
  BuildContext context, {
  String? categoryId,
  ScheduleEntry? existing,
  DateTime? initialDate,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ScheduleEditor(
      categoryId: existing?.categoryId ?? categoryId,
      existing: existing,
      initialDate: initialDate,
    ),
  );
}

/// Add or edit one schedule entry.
///
/// The form grows with what you are actually describing rather than showing
/// every field to everyone: a venue and a link for something people attend,
/// content details when a post is going out. Showing all of it at once is how a
/// simple form starts feeling like paperwork.
class _ScheduleEditor extends StatefulWidget {
  const _ScheduleEditor({this.categoryId, this.existing, this.initialDate});

  final String? categoryId;
  final ScheduleEntry? existing;
  final DateTime? initialDate;

  @override
  State<_ScheduleEditor> createState() => _ScheduleEditorState();
}

class _ScheduleEditorState extends State<_ScheduleEditor> {
  late final _title = TextEditingController(text: widget.existing?.title ?? '');
  late final _description = TextEditingController(text: widget.existing?.description ?? '');
  late final _location = TextEditingController(text: widget.existing?.location ?? '');
  late final _meetingUrl = TextEditingController(text: widget.existing?.meetingUrl ?? '');

  String? _categoryId;
  late DateTime _date = widget.existing?.date ?? widget.initialDate ?? _defaultTime();
  late MarketingPlatform _platform = widget.existing?.platform ?? MarketingPlatform.instagram;
  late MarketingFormat _format = widget.existing?.format ?? MarketingFormat.post;
  late MarketingStage _stage = widget.existing?.stage ?? MarketingStage.planned;
  late bool _showContent = widget.existing?.hasContentFields ?? false;

  bool _busy = false;
  String? _error;

  static DateTime _defaultTime() {
    // The next round hour — nobody schedules things at 14:37.
    final now = DateTime.now().add(const Duration(hours: 1));
    return DateTime(now.year, now.month, now.day, now.hour);
  }

  @override
  void initState() {
    super.initState();
    _categoryId = widget.categoryId;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _location.dispose();
    _meetingUrl.dispose();
    super.dispose();
  }

  Future<void> _pickWhen() async {
    final day = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_date),
    );
    setState(() => _date = DateTime(
          day.year, day.month, day.day,
          time?.hour ?? _date.hour, time?.minute ?? _date.minute,
        ));
  }

  Future<void> _save() async {
    final categoryId = _categoryId;
    if (categoryId == null || _title.text.trim().length < 2) return;
    setState(() { _busy = true; _error = null; });
    try {
      await AppScope.readStore(context).saveScheduleEntry(
        id: widget.existing?.id,
        categoryId: categoryId,
        title: _title.text.trim(),
        date: _date,
        description: _description.text.trim(),
        location: _location.text.trim(),
        meetingUrl: _meetingUrl.text.trim(),
        platform: _showContent ? _platform : null,
        format: _showContent ? _format : null,
        stage: _showContent ? _stage : null,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.storeOf(context);
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final isNew = widget.existing == null;
    final categories = store.activeCategories;
    final selected = store.categoryById(_categoryId);
    final tint = selected?.tint ?? GwdColors.primaryRed;

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
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
              title: isNew ? 'Add to the schedule' : 'Edit entry',
              subtitle: 'Everyone in the club sees this',
              accent: tint,
            ),
            Expanded(
              child: ListView(
                controller: controller,
                padding: EdgeInsets.fromLTRB(
                    GwdSpace.xl, 0, GwdSpace.xl, GwdSpace.xl + inset),
                children: [
                  Row(
                    children: [
                      Text('WHAT IS IT',
                          style: GwdType.eyebrow
                              .copyWith(color: GwdColors.inkTertiaryOf(context))),
                      const Spacer(),
                      if (store.capabilities.canManageDepartments)
                        PressableScale(
                          haptic: HapticStrength.selection,
                          onTap: () {
                            Navigator.of(context).pop();
                            Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => const CategoryAdminPage()));
                          },
                          child: Text('Manage',
                              style: GwdType.footnote
                                  .copyWith(color: GwdColors.primaryRed)),
                        ),
                    ],
                  ),
                  const SizedBox(height: GwdSpace.sm),
                  if (categories.isEmpty)
                    Text(
                      'No categories yet. The President can add some from Manage.',
                      style: GwdType.footnote
                          .copyWith(color: GwdColors.inkSecondaryOf(context)),
                    )
                  else
                    Wrap(
                      spacing: GwdSpace.sm,
                      runSpacing: GwdSpace.sm,
                      children: [
                        for (final category in categories)
                          _CategoryChip(
                            category: category,
                            selected: category.id == _categoryId,
                            onTap: () => setState(() {
                              _categoryId = category.id;
                              // A marketing-flavoured category opens its content
                              // fields by default; everything else keeps them
                              // available but out of the way.
                              if (category.icon == 'marketing') _showContent = true;
                            }),
                          ),
                      ],
                    ),

                  const SizedBox(height: GwdSpace.xl),
                  GwdField(
                    label: 'Title',
                    controller: _title,
                    hint: 'Core team sync',
                    autofocus: true,
                    onChanged: (_) => setState(() {}),
                  ),

                  const SizedBox(height: GwdSpace.lg),
                  SecondaryButton(
                    label: _whenLabel(),
                    icon: Icons.schedule_rounded,
                    expand: true,
                    onPressed: _pickWhen,
                  ),

                  const SizedBox(height: GwdSpace.lg),
                  GwdField(
                      label: 'Where',
                      controller: _location,
                      hint: 'Auditorium, Block C. Optional.'),

                  const SizedBox(height: GwdSpace.lg),
                  GwdField(
                    label: 'Meeting link',
                    controller: _meetingUrl,
                    hint: 'Zoom or Meet link. Optional.',
                  ),

                  const SizedBox(height: GwdSpace.lg),
                  GwdField(
                    label: 'Details',
                    controller: _description,
                    hint: 'Anything people need to know. Optional.',
                    maxLines: 3,
                  ),

                  // ---------- optional content details ----------
                  const SizedBox(height: GwdSpace.xl),
                  _Disclosure(
                    open: _showContent,
                    label: 'Content details',
                    hint: 'Platform, format and production stage',
                    onToggle: () => setState(() => _showContent = !_showContent),
                  ),
                  AnimatedSize(
                    duration: AppleDuration.standard,
                    curve: AppleCurves.standard,
                    alignment: Alignment.topCenter,
                    child: _showContent
                        ? Padding(
                            padding: const EdgeInsets.only(top: GwdSpace.lg),
                            child: Column(
                              children: [
                                _Picker<MarketingPlatform>(
                                  label: 'Platform',
                                  values: MarketingPlatform.values,
                                  selected: _platform,
                                  labelOf: (p) => p.label,
                                  onChanged: (p) => setState(() => _platform = p),
                                ),
                                const SizedBox(height: GwdSpace.lg),
                                _Picker<MarketingFormat>(
                                  label: 'Format',
                                  values: MarketingFormat.values,
                                  selected: _format,
                                  labelOf: (f) => f.label,
                                  iconOf: (f) => f.icon,
                                  onChanged: (f) => setState(() => _format = f),
                                ),
                                const SizedBox(height: GwdSpace.lg),
                                _Picker<MarketingStage>(
                                  label: 'Stage',
                                  values: MarketingStage.values,
                                  selected: _stage,
                                  labelOf: (s) => s.label,
                                  tintOf: (s) => s.tint,
                                  onChanged: (s) => setState(() => _stage = s),
                                ),
                              ],
                            ),
                          )
                        : const SizedBox(width: double.infinity),
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: GwdSpace.lg),
                    ErrorNote(message: _error!),
                  ],

                  const SizedBox(height: GwdSpace.xxl),
                  PrimaryButton(
                    label: isNew ? 'Add to schedule' : 'Save changes',
                    busy: _busy,
                    tone: tint,
                    onPressed:
                        (_categoryId != null && _title.text.trim().length >= 2) ? _save : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _whenLabel() {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final time =
        '${_date.hour.toString().padLeft(2, '0')}:${_date.minute.toString().padLeft(2, '0')}';
    final now = DateTime.now();
    final isToday = _date.year == now.year && _date.month == now.month && _date.day == now.day;
    if (isToday) return 'Today at $time';
    return '${_date.day} ${months[_date.month - 1]} at $time';
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final ScheduleCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      haptic: HapticStrength.selection,
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppleDuration.fast,
        curve: AppleCurves.standard,
        padding: const EdgeInsets.symmetric(
            horizontal: GwdSpace.md, vertical: GwdSpace.sm + 1),
        decoration: BoxDecoration(
          color: selected ? category.tint : GwdColors.surfaceOf(context),
          borderRadius: BorderRadius.circular(GwdRadius.md),
          border: Border.all(
            color: selected ? category.tint : GwdColors.hairlineOf(context),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(category.iconData,
                size: 14,
                color: selected ? Colors.white : GwdColors.inkSecondaryOf(context)),
            const SizedBox(width: 6),
            Text(
              category.name,
              style: GwdType.callout.copyWith(
                color: selected ? Colors.white : GwdColors.inkOf(context),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Progressive disclosure: an optional block that stays collapsed until asked
/// for, so the common case is a short form.
class _Disclosure extends StatelessWidget {
  const _Disclosure({
    required this.open,
    required this.label,
    required this.hint,
    required this.onToggle,
  });

  final bool open;
  final String label;
  final String hint;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      haptic: HapticStrength.selection,
      onTap: onToggle,
      child: Container(
        padding: const EdgeInsets.all(GwdSpace.md),
        decoration: BoxDecoration(
          color: GwdColors.sunkenOf(context),
          borderRadius: BorderRadius.circular(GwdRadius.md),
        ),
        child: Row(
          children: [
            AnimatedRotation(
              duration: AppleDuration.fast,
              turns: open ? 0.125 : 0,
              child: Icon(Icons.add_rounded,
                  size: 17, color: GwdColors.inkSecondaryOf(context)),
            ),
            const SizedBox(width: GwdSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label,
                      style: GwdType.headline.copyWith(color: GwdColors.inkOf(context))),
                  Text(hint,
                      style: GwdType.footnote
                          .copyWith(color: GwdColors.inkTertiaryOf(context))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Picker<T> extends StatelessWidget {
  const _Picker({
    required this.label,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
    this.iconOf,
    this.tintOf,
  });

  final String label;
  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final IconData Function(T)? iconOf;
  final Color Function(T)? tintOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(),
            style: GwdType.eyebrow.copyWith(color: GwdColors.inkTertiaryOf(context))),
        const SizedBox(height: GwdSpace.sm),
        Wrap(
          spacing: GwdSpace.sm,
          runSpacing: GwdSpace.sm,
          children: [
            for (final value in values)
              PressableScale(
                haptic: HapticStrength.selection,
                onTap: () => onChanged(value),
                child: AnimatedContainer(
                  duration: AppleDuration.fast,
                  padding: const EdgeInsets.symmetric(
                      horizontal: GwdSpace.md, vertical: GwdSpace.sm),
                  decoration: BoxDecoration(
                    color: value == selected
                        ? (tintOf?.call(value) ?? GwdColors.inkOf(context))
                        : GwdColors.surfaceOf(context),
                    borderRadius: BorderRadius.circular(GwdRadius.md),
                    border: Border.all(
                      color: value == selected
                          ? (tintOf?.call(value) ?? GwdColors.inkOf(context))
                          : GwdColors.hairlineOf(context),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (iconOf != null) ...[
                        Icon(iconOf!(value),
                            size: 13,
                            color: value == selected
                                ? Colors.white
                                : GwdColors.inkSecondaryOf(context)),
                        const SizedBox(width: 5),
                      ],
                      Text(
                        labelOf(value),
                        style: GwdType.footnote.copyWith(
                          color: value == selected
                              ? Colors.white
                              : GwdColors.inkOf(context),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
