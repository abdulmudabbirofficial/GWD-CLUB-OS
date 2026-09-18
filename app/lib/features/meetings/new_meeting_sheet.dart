import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme/apple_motion.dart';
import '../../app/theme/gwd_theme.dart';
import '../../app/widgets/common.dart';
import '../../core/api/api_client.dart';
import '../../core/models/club_role.dart';
import '../../core/models/member.dart';

/// Call a meeting.
///
/// The participant picker is the point of this screen. Inviting "the Marketing
/// team" must be one tap, not eleven — making somebody tick every name is how
/// they miss one, and it silently goes wrong the moment the team changes.
///
/// Both kinds combine: a department plus a named person from elsewhere is a
/// perfectly normal meeting, and the server de-duplicates anybody caught twice.
Future<void> showNewMeetingSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _NewMeetingSheet(),
  );
}

class _NewMeetingSheet extends StatefulWidget {
  const _NewMeetingSheet();

  @override
  State<_NewMeetingSheet> createState() => _NewMeetingSheetState();
}

class _NewMeetingSheetState extends State<_NewMeetingSheet> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _venue = TextEditingController();

  DateTime _date = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _start = const TimeOfDay(hour: 17, minute: 0);
  TimeOfDay? _end;

  final Set<String> _departments = {};
  final Set<String> _people = {};

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _venue.dispose();
    super.dispose();
  }

  /// The organiser is always in the room, so one other invitee is the floor —
  /// a meeting with only you in it is a reminder.
  bool get _canSubmit =>
      !_busy && _title.text.trim().length >= 3 && (_departments.isNotEmpty || _people.isNotEmpty);

  String _hhmm(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime({required bool start}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: start ? _start : (_end ?? _start.replacing(hour: _start.hour + 1)),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _start = picked;
      } else {
        _end = picked;
      }
    });
  }

  Future<void> _submit() async {
    final store = AppScope.readStore(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // The date carries the start time, so "what's next" and the schedule
      // order it correctly rather than putting every meeting at midnight.
      final when = DateTime(
        _date.year,
        _date.month,
        _date.day,
        _start.hour,
        _start.minute,
      );
      await store.createMeeting(
        title: _title.text.trim(),
        description: _description.text.trim(),
        date: when,
        startTime: _hhmm(_start),
        endTime: _end == null ? '' : _hhmm(_end!),
        venue: _venue.text.trim(),
        departmentIds: _departments.toList(),
        userIds: _people.toList(),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Meeting called. Everybody invited has been told.')),
      );
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _busy = false;
      });
    } catch (error) {
      setState(() {
        _error = '$error';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.storeOf(context);
    final me = AppScope.sessionOf(context).me;

    // Everybody except the organiser, who is added server-side.
    final people = store.members
        .where((m) => m.id != me?.id && m.role != ClubRole.clubDirector)
        .toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, controller) => Container(
          decoration: BoxDecoration(
            color: GwdColors.surfaceOf(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(GwdRadius.xxl)),
          ),
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.only(bottom: GwdSpace.xxl),
            children: [
              const SheetHeader(
                title: 'Call a meeting',
                subtitle: 'Everybody invited is told straight away.',
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: GwdSpace.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    GwdField(
                      label: 'What is it about',
                      controller: _title,
                      autofocus: true,
                      hint: 'Pre-event sync',
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: GwdSpace.lg),

                    // ---------- when ----------
                    Row(
                      children: [
                        Expanded(
                          child: _Picker(
                            label: 'Date',
                            value: '${_date.day}/${_date.month}',
                            icon: Icons.event_rounded,
                            onTap: _pickDate,
                          ),
                        ),
                        const SizedBox(width: GwdSpace.sm),
                        Expanded(
                          child: _Picker(
                            label: 'Starts',
                            value: _hhmm(_start),
                            icon: Icons.schedule_rounded,
                            onTap: () => _pickTime(start: true),
                          ),
                        ),
                        const SizedBox(width: GwdSpace.sm),
                        Expanded(
                          child: _Picker(
                            label: 'Ends',
                            value: _end == null ? 'Open' : _hhmm(_end!),
                            icon: Icons.schedule_outlined,
                            muted: _end == null,
                            onTap: () => _pickTime(start: false),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: GwdSpace.lg),
                    GwdField(
                      label: 'Where (optional)',
                      controller: _venue,
                      hint: 'Seminar Hall 1, or a meeting link',
                      onChanged: (_) => setState(() {}),
                    ),

                    // ---------- who: whole teams ----------
                    const SizedBox(height: GwdSpace.xl),
                    Text('INVITE A WHOLE TEAM',
                        style: GwdType.eyebrow.copyWith(color: GwdColors.inkTertiaryOf(context))),
                    const SizedBox(height: 3),
                    Text(
                      'Everyone in the department at this moment, Lead included. '
                      'The list is fixed now, so it will not change if somebody '
                      'moves department later.',
                      style: GwdType.caption
                          .copyWith(letterSpacing: 0, color: GwdColors.inkTertiaryOf(context)),
                    ),
                    const SizedBox(height: GwdSpace.sm),
                    Wrap(
                      spacing: GwdSpace.sm,
                      runSpacing: GwdSpace.sm,
                      children: [
                        for (final d in store.departments.where((d) => d.active))
                          _Tag(
                            label: '${d.name} team',
                            selected: _departments.contains(d.id),
                            onTap: () => setState(() {
                              if (!_departments.remove(d.id)) _departments.add(d.id);
                            }),
                          ),
                      ],
                    ),

                    // ---------- who: named people ----------
                    const SizedBox(height: GwdSpace.lg),
                    Text('OR ADD PEOPLE INDIVIDUALLY',
                        style: GwdType.eyebrow.copyWith(color: GwdColors.inkTertiaryOf(context))),
                    const SizedBox(height: GwdSpace.sm),
                    if (people.isEmpty)
                      Text('Nobody else to invite yet.',
                          style: GwdType.footnote.copyWith(color: GwdColors.inkTertiaryOf(context)))
                    else
                      for (final person in people.take(40))
                        _PersonRow(
                          member: person,
                          departmentName: store.departmentById(person.departmentId)?.name,
                          selected: _people.contains(person.id),
                          onTap: () => setState(() {
                            if (!_people.remove(person.id)) _people.add(person.id);
                          }),
                        ),

                    const SizedBox(height: GwdSpace.lg),
                    GwdField(
                      label: 'Anything to add (optional)',
                      controller: _description,
                      maxLines: 3,
                      hint: 'What to bring, what will be decided.',
                    ),

                    if (_error != null) ...[
                      const SizedBox(height: GwdSpace.lg),
                      ErrorNote(message: _error!),
                    ],
                    const SizedBox(height: GwdSpace.xl),
                    PrimaryButton(
                      label: 'Call the meeting',
                      icon: Icons.groups_2_rounded,
                      busy: _busy,
                      onPressed: _canSubmit ? _submit : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Picker extends StatelessWidget {
  const _Picker({
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
      haptic: HapticStrength.selection,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: GwdSpace.md, vertical: GwdSpace.md),
        decoration: BoxDecoration(
          color: GwdColors.sunkenOf(context),
          borderRadius: BorderRadius.circular(GwdRadius.md),
          border: Border.all(color: GwdColors.hairlineOf(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label.toUpperCase(),
                style: GwdType.micro.copyWith(color: GwdColors.inkTertiaryOf(context))),
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(icon, size: 13, color: GwdColors.inkTertiaryOf(context)),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GwdType.footnote.copyWith(
                        color: muted ? GwdColors.inkTertiaryOf(context) : GwdColors.inkOf(context),
                      )),
                ),
              ],
            ),
          ],
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
        padding: const EdgeInsets.symmetric(horizontal: GwdSpace.md, vertical: GwdSpace.sm),
        decoration: BoxDecoration(
          color: selected ? GwdColors.primaryRed : GwdColors.sunkenOf(context),
          borderRadius: BorderRadius.circular(GwdRadius.sm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(selected ? Icons.groups_rounded : Icons.groups_outlined,
                size: 14, color: selected ? Colors.white : GwdColors.inkTertiaryOf(context)),
            const SizedBox(width: 5),
            Text(label,
                style: GwdType.footnote.copyWith(
                  color: selected ? Colors.white : GwdColors.inkSecondaryOf(context),
                )),
          ],
        ),
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.member,
    required this.selected,
    required this.onTap,
    this.departmentName,
  });

  final Member member;
  final bool selected;
  final VoidCallback onTap;
  final String? departmentName;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      pressedScale: 0.99,
      haptic: HapticStrength.selection,
      child: Container(
        margin: const EdgeInsets.only(bottom: GwdSpace.xs),
        padding: const EdgeInsets.all(GwdSpace.sm),
        decoration: BoxDecoration(
          color: selected ? GwdColors.primaryRed.withValues(alpha: 0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(GwdRadius.md),
        ),
        child: Row(
          children: [
            Avatar(initials: member.initials, tint: member.tint, size: 32),
            const SizedBox(width: GwdSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(member.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GwdType.callout.copyWith(color: GwdColors.inkOf(context))),
                  Text(member.positionLine(departmentName),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GwdType.caption.copyWith(
                          fontSize: 10, letterSpacing: 0, color: GwdColors.inkTertiaryOf(context))),
                ],
              ),
            ),
            Icon(
              selected ? Icons.check_circle_rounded : Icons.circle_outlined,
              size: 20,
              color: selected ? GwdColors.primaryRed : GwdColors.inkTertiaryOf(context),
            ),
          ],
        ),
      ),
    );
  }
}
