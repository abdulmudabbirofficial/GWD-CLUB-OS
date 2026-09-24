import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme/apple_motion.dart';
import '../../app/theme/gwd_theme.dart';
import '../../app/widgets/common.dart';
import '../../core/api/api_client.dart';
import '../../core/models/club_event.dart';

/// Editing an event after it exists.
///
/// There was no way to. `PATCH /api/events/:id` and `ClubStore.updateEvent`
/// were both written and nothing in the app ever called either, so a wrong
/// date or a venue that changed a week before the event could only be fixed by
/// cancelling and making the whole thing again — which throws away its tasks,
/// its paperwork and its history.
///
/// Only what actually changed is sent. The server notifies the event's team,
/// the Lead of every department working on it and anybody holding open work on
/// it when **where or when** moves; resending untouched fields would make a
/// fixed typo in the description look like news.
Future<bool> showEditEventSheet(BuildContext context, ClubEvent event) async {
  final saved = await showGwdSheet<bool>(
    context: context,
    builder: (_) => _EditEventSheet(event: event),
  );
  return saved == true;
}

class _EditEventSheet extends StatefulWidget {
  const _EditEventSheet({required this.event});

  final ClubEvent event;

  @override
  State<_EditEventSheet> createState() => _EditEventSheetState();
}

class _EditEventSheetState extends State<_EditEventSheet> {
  static const _types = ['Event', 'Workshop', 'Seminar', 'Competition', 'Meetup', 'Drive'];

  late final _name = TextEditingController(text: widget.event.name);
  late final _description = TextEditingController(text: widget.event.description);
  late final _venue = TextEditingController(text: widget.event.venue);
  late final _speaker = TextEditingController(text: widget.event.speakerName);
  late final _organisation = TextEditingController(text: widget.event.externalOrganisation);
  late DateTime _date = widget.event.date;
  late TimeOfDay? _start = _parse(widget.event.startTime);
  late TimeOfDay? _end = _parse(widget.event.endTime);
  late String _type = widget.event.type;
  bool _busy = false;
  String? _error;

  static TimeOfDay? _parse(String value) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value.trim());
    if (match == null) return null;
    final h = int.parse(match.group(1)!);
    final m = int.parse(match.group(2)!);
    if (h > 23 || m > 59) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  static String _wire(TimeOfDay? t) => t == null
      ? ''
      : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _venue.dispose();
    _speaker.dispose();
    _organisation.dispose();
    super.dispose();
  }

  /// Only the fields that differ from what the event already says.
  Map<String, dynamic> get _changes {
    final e = widget.event;
    String t(TextEditingController c) => c.text.trim();
    final day = DateTime(_date.year, _date.month, _date.day);
    final was = DateTime(e.date.year, e.date.month, e.date.day);
    return {
      if (t(_name) != e.name) 'name': t(_name),
      if (_type != e.type) 'type': _type,
      if (day != was) 'date': day.toUtc().toIso8601String(),
      if (_wire(_start) != e.startTime) 'startTime': _wire(_start),
      if (_wire(_end) != e.endTime) 'endTime': _wire(_end),
      if (t(_venue) != e.venue) 'venue': t(_venue),
      if (t(_description) != e.description) 'description': t(_description),
      if (t(_speaker) != e.speakerName) 'speakerName': t(_speaker),
      if (t(_organisation) != e.externalOrganisation) 'externalOrganisation': t(_organisation),
    };
  }

  /// Said before saving, not after a round trip.
  String? get _problem {
    if (_name.text.trim().length < 2) return 'Give the event a name.';
    final start = _start;
    final end = _end;
    if (start != null && end != null &&
        end.hour * 60 + end.minute <= start.hour * 60 + start.minute) {
      return 'It has to end after it starts.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final problem = _problem;
    final changed = _changes.isNotEmpty;
    // Adding a kind nobody listed would otherwise silently re-label the event
    // when the first chip is tapped; keep whatever it already is on the list.
    final types = _types.contains(_type) ? _types : [_type, ..._types];

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
              title: 'Edit the event',
              subtitle: 'If the date, time or venue moves, everybody working on it is told.',
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(GwdSpace.xl, 0, GwdSpace.xl, GwdSpace.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GwdField(
                      label: 'Event name',
                      controller: _name,
                      textCapitalization: TextCapitalization.sentences,
                      // onChanged, never onSubmitted, for anything the Save
                      // button depends on.
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: GwdSpace.lg),
                    Text('KIND',
                        style: GwdType.eyebrow.copyWith(color: GwdColors.inkTertiaryOf(context))),
                    const SizedBox(height: GwdSpace.sm),
                    Wrap(
                      spacing: GwdSpace.sm,
                      runSpacing: GwdSpace.sm,
                      children: [
                        for (final type in types)
                          _Chip(
                            label: type,
                            selected: _type == type,
                            onTap: () => setState(() => _type = type),
                          ),
                      ],
                    ),
                    const SizedBox(height: GwdSpace.lg),
                    SecondaryButton(
                      label: 'On ${_date.day}/${_date.month}/${_date.year}',
                      icon: Icons.event_rounded,
                      expand: true,
                      onPressed: _pickDate,
                    ),
                    const SizedBox(height: GwdSpace.sm),
                    Row(
                      children: [
                        Expanded(
                          child: SecondaryButton(
                            label: _start == null ? 'Starts' : 'From ${_wire(_start)}',
                            icon: Icons.schedule_rounded,
                            expand: true,
                            onPressed: () => _pickTime(start: true),
                          ),
                        ),
                        const SizedBox(width: GwdSpace.sm),
                        Expanded(
                          child: SecondaryButton(
                            label: _end == null ? 'Ends' : 'Until ${_wire(_end)}',
                            icon: Icons.schedule_rounded,
                            expand: true,
                            onPressed: () => _pickTime(start: false),
                          ),
                        ),
                      ],
                    ),
                    if (_start != null || _end != null)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => setState(() {
                            _start = null;
                            _end = null;
                          }),
                          child: Text('Clear the times',
                              style: GwdType.footnote
                                  .copyWith(color: GwdColors.inkTertiaryOf(context))),
                        ),
                      ),
                    const SizedBox(height: GwdSpace.md),
                    GwdField(
                      label: 'Venue',
                      controller: _venue,
                      hint: 'E block auditorium',
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: GwdSpace.lg),
                    GwdField(
                      label: 'What it is',
                      controller: _description,
                      maxLines: 3,
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: GwdSpace.lg),
                    GwdField(
                      label: 'Speaker (optional)',
                      controller: _speaker,
                      textCapitalization: TextCapitalization.words,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: GwdSpace.lg),
                    GwdField(
                      label: 'Outside organisation (optional)',
                      controller: _organisation,
                      textCapitalization: TextCapitalization.words,
                      onChanged: (_) => setState(() {}),
                    ),
                    if (problem != null && changed) ...[
                      const SizedBox(height: GwdSpace.lg),
                      Text(problem,
                          style: GwdType.footnote.copyWith(color: GwdColors.primaryRed)),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: GwdSpace.lg),
                      ErrorNote(message: _error!),
                    ],
                    const SizedBox(height: GwdSpace.xl),
                    PrimaryButton(
                      label: changed ? 'Save changes' : 'Nothing changed yet',
                      icon: Icons.check_rounded,
                      busy: _busy,
                      onPressed: changed && problem == null ? _save : null,
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
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _pickTime({required bool start}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: (start ? _start : _end) ?? const TimeOfDay(hour: 10, minute: 0),
    );
    if (picked == null || !mounted) return;
    setState(() => start ? _start = picked : _end = picked);
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final store = AppScope.readStore(context);
    final navigator = Navigator.of(context);
    try {
      await store.updateEvent(widget.event.id, _changes);
      navigator.pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() { _busy = false; _error = e.message; });
    } catch (e) {
      if (mounted) setState(() { _busy = false; _error = '$e'; });
    }
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});

  final String label;
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
        padding: const EdgeInsets.symmetric(horizontal: GwdSpace.md, vertical: GwdSpace.sm),
        decoration: BoxDecoration(
          color: selected
              ? GwdColors.primaryRed.withValues(alpha: 0.14)
              : GwdColors.sunkenOf(context),
          borderRadius: BorderRadius.circular(GwdRadius.sm),
          border: Border.all(
            color: selected
                ? GwdColors.primaryRed.withValues(alpha: 0.55)
                : GwdColors.hairlineOf(context),
          ),
        ),
        child: Text(label,
            style: GwdType.footnote.copyWith(
              color: selected ? GwdColors.primaryRed : GwdColors.inkSecondaryOf(context),
            )),
      ),
    );
  }
}
