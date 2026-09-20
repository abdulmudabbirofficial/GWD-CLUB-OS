import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme/apple_motion.dart';
import '../../app/theme/gwd_theme.dart';
import '../../app/widgets/common.dart';
import '../../core/api/api_client.dart';
import '../../core/state/club_store.dart';

/// Turning something agreed in the room into work somebody actually has.
///
/// The failure this closes is specific: a decision gets made, somebody writes
/// it in a notes app, and it is next read when the same thing goes wrong at the
/// following meeting. So what this creates is not an entry on a meeting's
/// private checklist — it is a **real task**, which lands on the Work tab,
/// sends the same notification, counts for the same points, and is ticked off
/// in one place however you reach it.
///
/// Who it can go to is the server's answer, not a guess: `/api/users/assignable`
/// returns departments *or* people depending on the asker's role, so the sheet
/// never offers a target that would be refused.
Future<bool> showMeetingActionSheet(BuildContext context, String meetingId) async {
  final added = await showGwdSheet<bool>(
    context: context,
    builder: (_) => _MeetingActionSheet(meetingId: meetingId),
  );
  return added == true;
}

class _MeetingActionSheet extends StatefulWidget {
  const _MeetingActionSheet({required this.meetingId});

  final String meetingId;

  @override
  State<_MeetingActionSheet> createState() => _MeetingActionSheetState();
}

class _MeetingActionSheetState extends State<_MeetingActionSheet> {
  final _title = TextEditingController();
  AssignmentTargets _targets = AssignmentTargets.empty;
  bool _loadingTargets = true;
  String? _person;
  String? _department;
  DateTime? _due;
  int _points = 1;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTargets();
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _loadTargets() async {
    try {
      final targets = await AppScope.readStore(context).assignableTargets();
      if (!mounted) return;
      setState(() {
        _targets = targets;
        _loadingTargets = false;
        // Whichever kind this person actually has. The executive addresses
        // departments; a Lead names one of their own. Nobody is shown a switch
        // between two options when they only have one.
        if (targets.assignable.isEmpty && targets.departments.length == 1) {
          _department = targets.departments.first.id;
        }
      });
    } catch (e) {
      if (mounted) setState(() { _loadingTargets = false; _error = '$e'; });
    }
  }

  bool get _canSubmit =>
      _title.text.trim().length >= 3 && (_person != null || _department != null);

  @override
  Widget build(BuildContext context) {
    final points = _targets.pointValues.isEmpty ? const [1, 3, 5] : _targets.pointValues;

    return Container(
      decoration: BoxDecoration(
        color: GwdColors.canvasOf(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(GwdRadius.xxl)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetHeader(
              title: 'Somebody agreed to do this',
              subtitle: 'It becomes a real task on their Work tab, not a note '
                  'on this page that nobody sees again.',
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                    GwdSpace.xl, 0, GwdSpace.xl, GwdSpace.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GwdField(
                      label: 'What needs doing',
                      controller: _title,
                      hint: 'Send the venue confirmation to the office',
                      autofocus: true,
                      textCapitalization: TextCapitalization.sentences,
                      // onChanged, never onSubmitted: the Done key is something
                      // people reasonably never press, and a Save that sits
                      // dead while somebody types has shipped here twice.
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: GwdSpace.lg),

                    if (_loadingTargets)
                      const SkeletonList(count: 2, height: 40)
                    else ...[
                      Text('WHO HAS IT',
                          style: GwdType.eyebrow
                              .copyWith(color: GwdColors.inkTertiaryOf(context))),
                      const SizedBox(height: GwdSpace.sm),
                      if (_targets.assignable.isEmpty && _targets.departments.isEmpty)
                        Text(
                          'Your role cannot hand work out, so an action from this '
                          'meeting has to go through a Lead.',
                          style: GwdType.footnote
                              .copyWith(color: GwdColors.inkTertiaryOf(context)),
                        ),
                      Wrap(
                        spacing: GwdSpace.sm,
                        runSpacing: GwdSpace.sm,
                        children: [
                          for (final d in _targets.departments)
                            _Pick(
                              label: d.name,
                              // A department with no Lead has nobody to receive
                              // the work, and saying so beforehand beats the
                              // task quietly sitting unseen.
                              sublabel: d.leadName ?? 'No Lead yet',
                              icon: Icons.workspaces_outline,
                              selected: _department == d.id,
                              onTap: () => setState(() {
                                _department = d.id;
                                _person = null;
                              }),
                            ),
                          for (final m in _targets.assignable)
                            _Pick(
                              label: m.displayName,
                              sublabel: m.positionLine(null),
                              icon: Icons.person_outline,
                              selected: _person == m.id,
                              onTap: () => setState(() {
                                _person = m.id;
                                _department = null;
                              }),
                            ),
                        ],
                      ),
                      const SizedBox(height: GwdSpace.lg),

                      Text('WORTH',
                          style: GwdType.eyebrow
                              .copyWith(color: GwdColors.inkTertiaryOf(context))),
                      const SizedBox(height: GwdSpace.sm),
                      Wrap(
                        spacing: GwdSpace.sm,
                        children: [
                          // Three values, never a free number: a spectrum
                          // invites haggling, and the difference between six
                          // and seven points is not a conversation any club
                          // should be having.
                          for (final value in points)
                            _Pick(
                              label: '$value',
                              selected: _points == value,
                              onTap: () => setState(() => _points = value),
                            ),
                        ],
                      ),
                      const SizedBox(height: GwdSpace.lg),

                      SecondaryButton(
                        label: _due == null
                            ? 'By when? (optional)'
                            : 'By ${_due!.day}/${_due!.month}/${_due!.year}',
                        icon: Icons.event_rounded,
                        onPressed: _pickDate,
                      ),
                    ],

                    if (_error != null) ...[
                      const SizedBox(height: GwdSpace.lg),
                      ErrorNote(message: _error!),
                    ],
                    const SizedBox(height: GwdSpace.xl),
                    PrimaryButton(
                      label: 'Make it a task',
                      icon: Icons.arrow_forward_rounded,
                      busy: _busy,
                      onPressed: _canSubmit ? _submit : null,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _due ?? now.add(const Duration(days: 3)),
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null && mounted) setState(() => _due = picked);
  }

  Future<void> _submit() async {
    setState(() { _busy = true; _error = null; });
    final store = AppScope.readStore(context);
    final navigator = Navigator.of(context);
    try {
      await store.addMeetingAction(
        widget.meetingId,
        title: _title.text.trim(),
        assignedTo: _person,
        departmentId: _department,
        dueDate: _due,
        points: _points,
      );
      navigator.pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() { _busy = false; _error = e.message; });
    } catch (e) {
      if (mounted) setState(() { _busy = false; _error = '$e'; });
    }
  }
}

class _Pick extends StatelessWidget {
  const _Pick({
    required this.label,
    required this.selected,
    required this.onTap,
    this.sublabel,
    this.icon,
  });

  final String label;
  final String? sublabel;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      haptic: HapticStrength.selection,
      child: AnimatedContainer(
        duration: AppleDuration.fast,
        curve: AppleCurves.standard,
        padding: const EdgeInsets.symmetric(
            horizontal: GwdSpace.md, vertical: GwdSpace.sm),
        decoration: BoxDecoration(
          color: selected
              ? GwdColors.primaryRed.withValues(alpha: 0.14)
              : GwdColors.sunkenOf(context),
          borderRadius: BorderRadius.circular(GwdRadius.md),
          border: Border.all(
            color: selected
                ? GwdColors.primaryRed.withValues(alpha: 0.55)
                : GwdColors.hairlineOf(context),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon,
                  size: 15,
                  color: selected
                      ? GwdColors.primaryRed
                      : GwdColors.inkTertiaryOf(context)),
              const SizedBox(width: GwdSpace.sm),
            ],
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    style: GwdType.footnote.copyWith(
                      color: selected
                          ? GwdColors.primaryRed
                          : GwdColors.inkOf(context),
                    )),
                if (sublabel != null)
                  Text(sublabel!,
                      style: GwdType.caption
                          .copyWith(color: GwdColors.inkTertiaryOf(context))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
