import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_scope.dart';
import '../../app/responsive.dart';
import '../../app/theme/apple_motion.dart';
import '../../app/theme/gwd_theme.dart';
import '../../app/widgets/brand.dart';
import '../../app/widgets/common.dart';
import '../../core/api/socket_client.dart';
import '../../core/models/event_day.dart';
import '../../core/plural.dart';
import '../tasks/task_detail_page.dart';

/// Running the event, on the day.
///
/// Every other event screen answers "is this on track?" — a planning question,
/// asked at a desk, with a week to act on the answer. On the day itself nobody
/// is planning. Somebody is standing in a corridor with fifteen minutes to go,
/// and there are exactly three questions: what is on now, what is next, and who
/// do I ring about the projector.
///
/// So this screen is not another tab of the workspace. It drops the charts, the
/// burndown and the department breakdown entirely, and leads with the one thing
/// that matters at that moment — which is the same rule as everywhere else in
/// the app, just with a different definition of "now".
///
/// The clock ticks. A run sheet that needs pulling to refresh is a run sheet
/// that is wrong every time you glance at it.
class EventDayPage extends StatefulWidget {
  const EventDayPage({super.key, required this.eventId});

  final String eventId;

  @override
  State<EventDayPage> createState() => _EventDayPageState();
}

class _EventDayPageState extends State<EventDayPage> {
  Timer? _tick;
  DateTime _now = DateTime.now();
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    // Every fifteen seconds, not every second: the screen only ever changes at
    // a minute boundary, and a per-second rebuild of a list this size is heat
    // in somebody's pocket for no visible gain.
    _tick = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      await AppScope.readStore(context).loadEventDay(widget.eventId);
      if (mounted) setState(() { _loading = false; _error = null; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = '$e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.storeOf(context);
    final day = store.dayFor(widget.eventId);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Event day'),
        actions: [
          if (day != null && day.canEdit)
            IconButton(
              tooltip: 'Add to the run sheet',
              icon: const Icon(Icons.add_rounded),
              onPressed: () => _addItem(day),
            ),
        ],
      ),
      body: Builder(builder: (context) {
        if (day == null) {
          if (_loading) return const SkeletonList();
          return ErrorNote(
            message: _error ?? 'Could not load the day.',
            onRetry: () async {
              setState(() => _loading = true);
              await _load();
            },
          );
        }
        return RefreshIndicator(
          onRefresh: _load,
          child: ContentWidth(child: _Body(day: day, now: _now, onChanged: _load)),
        );
      }),
    );
  }

  Future<void> _addItem(EventDay day) async {
    await showRunSheetItemSheet(context, eventId: widget.eventId, team: day.team);
    if (mounted) await _load();
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.day, required this.now, required this.onChanged});

  final EventDay day;
  final DateTime now;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final gutter = GwdSpace.gutter(MediaQuery.sizeOf(context).width);
    final current = day.currentAt(now);
    final next = day.nextAt(now);
    final scheduled = day.scheduled;
    final anytime = day.anytime;

    return ListView(
      padding: EdgeInsets.fromLTRB(gutter, GwdSpace.md, gutter, GwdSpace.xxxl),
      children: [
        _Header(day: day, now: now),

        // The one focal thing. Everything below is reference; this is the
        // answer to the only question somebody opens this screen to ask.
        if (current != null || next != null) ...[
          const SizedBox(height: GwdSpace.lg),
          FluidReveal(
            child: _FocalCard(
              day: day,
              current: current,
              next: next,
              onChanged: onChanged,
            ),
          ),
        ],

        if (scheduled.isEmpty && anytime.isEmpty) ...[
          const SizedBox(height: GwdSpace.xl),
          EmptyState(
            icon: Icons.schedule_rounded,
            title: 'No run sheet yet',
            message: day.canEdit
                ? 'Put the day in order — doors open, sound check, speaker on. '
                    'Anyone on the team can tick a row off as it happens.'
                : 'Whoever is running this event has not written one yet.',
          ),
        ],

        if (scheduled.isNotEmpty) ...[
          const SizedBox(height: GwdSpace.xl),
          SectionHeader(
            title: 'The run sheet',
            trailing: Text('${day.runSheetDone} of ${day.runSheet.length} done',
                style: GwdType.caption
                    .copyWith(color: GwdColors.inkTertiaryOf(context))),
          ),
          const SizedBox(height: GwdSpace.sm),
          for (var i = 0; i < scheduled.length; i++)
            AppleStaggerItem(
              index: i,
              child: _RunSheetRow(
                item: scheduled[i],
                day: day,
                now: now,
                isCurrent: current?.id == scheduled[i].id,
                onChanged: onChanged,
              ),
            ),
        ],

        if (anytime.isNotEmpty) ...[
          const SizedBox(height: GwdSpace.xl),
          const SectionHeader(
            title: 'At some point',
            // Untimed jobs are real work with no place on a clock. Giving them
            // a made-up time would put them in the schedule wrongly; leaving
            // them off the screen loses them.
          ),
          const SizedBox(height: GwdSpace.sm),
          for (var i = 0; i < anytime.length; i++)
            AppleStaggerItem(
              index: i,
              child: _RunSheetRow(
                item: anytime[i],
                day: day,
                now: now,
                isCurrent: false,
                onChanged: onChanged,
              ),
            ),
        ],

        if (day.team.isNotEmpty) ...[
          const SizedBox(height: GwdSpace.xl),
          SectionHeader(
            title: 'Who is on it',
            trailing: Text(people(day.team.length),
                style: GwdType.caption
                    .copyWith(color: GwdColors.inkTertiaryOf(context))),
          ),
          const SizedBox(height: GwdSpace.sm),
          for (var i = 0; i < day.team.length; i++)
            AppleStaggerItem(index: i, child: _TeamRow(member: day.team[i])),
        ],

        if (day.openTasks.isNotEmpty) ...[
          const SizedBox(height: GwdSpace.xl),
          SectionHeader(
            title: 'Still open',
            trailing: Text(countOf(day.openTaskCount, 'task'),
                style: GwdType.caption
                    .copyWith(color: GwdColors.inkTertiaryOf(context))),
          ),
          const SizedBox(height: GwdSpace.sm),
          for (var i = 0; i < day.openTasks.length && i < 8; i++)
            AppleStaggerItem(index: i, child: _OpenTaskRow(task: day.openTasks[i])),
        ],

        if (day.pendingApprovals > 0) ...[
          const SizedBox(height: GwdSpace.lg),
          SurfaceCard(
            emphasis: SurfaceEmphasis.raised,
            padding: const EdgeInsets.all(GwdSpace.lg),
            child: Row(
              children: [
                const Icon(Icons.pending_actions_rounded,
                    size: 20, color: GwdColors.warning),
                const SizedBox(width: GwdSpace.md),
                Expanded(
                  child: Text(
                    '${countOf(day.pendingApprovals, 'approval')} still waiting on a '
                    'decision. Worth chasing before anybody asks to see the paperwork.',
                    style: GwdType.footnote
                        .copyWith(color: GwdColors.inkSecondaryOf(context)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.day, required this.now});

  final EventDay day;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final event = day.event;
    final tint = event.bannerColor;
    final accent = GwdColors.readableOn(context, tint);
    final today = DateTime(now.year, now.month, now.day) ==
        DateTime(event.date.year, event.date.month, event.date.day);

    return SurfaceCard(
      emphasis: SurfaceEmphasis.live,
      padding: const EdgeInsets.all(GwdSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (today) ...[
                LiveDot(
                    connected: AppScope.storeOf(context).liveStatus ==
                        LiveStatus.connected),
                const SizedBox(width: GwdSpace.sm),
              ],
              Text(
                today ? 'TODAY' : event.whenLabel.toUpperCase(),
                style: GwdType.eyebrow.copyWith(color: accent),
              ),
              const Spacer(),
              Text(_clock(now), style: GwdType.numeric.copyWith(color: accent)),
            ],
          ),
          const SizedBox(height: GwdSpace.sm),
          Text(event.name,
              style: GwdType.title2.copyWith(color: GwdColors.inkOf(context))),
          if (event.venue.isNotEmpty || event.startTime.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              [
                if (event.startTime.isNotEmpty) event.startTime,
                if (event.venue.isNotEmpty) event.venue,
              ].join(' · '),
              style: GwdType.footnote.copyWith(color: GwdColors.inkTertiaryOf(context)),
            ),
          ],
        ],
      ),
    );
  }

  static String _clock(DateTime now) {
    final hours = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final suffix = now.hour < 12 ? 'am' : 'pm';
    return '$hours:${now.minute.toString().padLeft(2, '0')} $suffix';
  }
}

/// What is on now, and what is next — the whole reason the screen exists.
class _FocalCard extends StatelessWidget {
  const _FocalCard({
    required this.day,
    required this.current,
    required this.next,
    required this.onChanged,
  });

  final EventDay day;
  final RunSheetItem? current;
  final RunSheetItem? next;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final here = current;
    return SurfaceCard(
      emphasis: SurfaceEmphasis.raised,
      padding: const EdgeInsets.all(GwdSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (here != null) ...[
            Text('HAPPENING NOW',
                style: GwdType.eyebrow.copyWith(color: GwdColors.primaryRed)),
            const SizedBox(height: GwdSpace.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(here.title,
                      style: GwdType.title3
                          .copyWith(color: GwdColors.inkOf(context))),
                ),
                const SizedBox(width: GwdSpace.md),
                _TickButton(
                  item: here,
                  eventId: day.event.id,
                  onChanged: onChanged,
                ),
              ],
            ),
            if (here.note.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(here.note,
                  style: GwdType.footnote
                      .copyWith(color: GwdColors.inkSecondaryOf(context))),
            ],
            if (here.ownerName != null) ...[
              const SizedBox(height: GwdSpace.xs),
              Text('${here.ownerName} has this one',
                  style: GwdType.caption
                      .copyWith(color: GwdColors.inkTertiaryOf(context))),
            ],
          ] else ...[
            Text('NOT STARTED YET',
                style: GwdType.eyebrow.copyWith(color: GwdColors.inkTertiaryOf(context))),
            const SizedBox(height: GwdSpace.xs),
            Text('The day has not reached the first item.',
                style: GwdType.body.copyWith(color: GwdColors.inkSecondaryOf(context))),
          ],
          if (next != null) ...[
            const SizedBox(height: GwdSpace.lg),
            Divider(height: 1, color: GwdColors.hairlineOf(context)),
            const SizedBox(height: GwdSpace.md),
            Row(
              children: [
                Icon(Icons.arrow_forward_rounded,
                    size: 15, color: GwdColors.inkTertiaryOf(context)),
                const SizedBox(width: GwdSpace.sm),
                Text('Next  ',
                    style: GwdType.caption
                        .copyWith(color: GwdColors.inkTertiaryOf(context))),
                Text(next!.clockLabel,
                    style: GwdType.numeric
                        .copyWith(color: GwdColors.inkSecondaryOf(context))),
                const SizedBox(width: GwdSpace.sm),
                Expanded(
                  child: Text(next!.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GwdType.footnote
                          .copyWith(color: GwdColors.inkOf(context))),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _RunSheetRow extends StatelessWidget {
  const _RunSheetRow({
    required this.item,
    required this.day,
    required this.now,
    required this.isCurrent,
    required this.onChanged,
  });

  final RunSheetItem item;
  final EventDay day;
  final DateTime now;
  final bool isCurrent;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final minutes = now.hour * 60 + now.minute;
    final at = item.minutes;
    // Late means: its time has gone, and nobody has ticked it. Not a telling
    // off — the point is that it is the row somebody should look at.
    final late = !item.done && at != null && at < minutes && !isCurrent;

    return Padding(
      padding: const EdgeInsets.only(bottom: GwdSpace.sm),
      child: SurfaceCard(
        emphasis: isCurrent ? SurfaceEmphasis.raised : SurfaceEmphasis.quiet,
        onTap: day.canEdit
            ? () => showRunSheetItemSheet(context,
                eventId: day.event.id, team: day.team, existing: item)
                .then((_) => onChanged())
            : null,
        padding: const EdgeInsets.symmetric(
            horizontal: GwdSpace.lg, vertical: GwdSpace.md),
        child: Row(
          children: [
            SizedBox(
              width: 58,
              child: Text(
                item.timed ? item.clockLabel : '—',
                style: GwdType.numeric.copyWith(
                  color: item.done
                      ? GwdColors.inkTertiaryOf(context)
                      : late
                          ? GwdColors.warning
                          : GwdColors.inkSecondaryOf(context),
                ),
              ),
            ),
            const SizedBox(width: GwdSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.title,
                    style: GwdType.headline.copyWith(
                      color: item.done
                          ? GwdColors.inkTertiaryOf(context)
                          : GwdColors.inkOf(context),
                      decoration: item.done ? TextDecoration.lineThrough : null,
                      decorationColor: GwdColors.inkTertiaryOf(context),
                    ),
                  ),
                  if (item.ownerName != null || item.note.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      [
                        if (item.ownerName != null) item.ownerName!,
                        if (item.note.isNotEmpty) item.note,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GwdType.caption
                          .copyWith(color: GwdColors.inkTertiaryOf(context)),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: GwdSpace.sm),
            _TickButton(item: item, eventId: day.event.id, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

/// Ticking a row off.
///
/// Open to **anyone on the team**, which is why it is a button on every row
/// rather than something behind an edit sheet. On the day the person who
/// finishes setting the stage is whoever was nearest, and making them find the
/// event lead to have it marked done is how a run sheet stops being updated by
/// eleven in the morning.
class _TickButton extends StatefulWidget {
  const _TickButton({
    required this.item,
    required this.eventId,
    required this.onChanged,
  });

  final RunSheetItem item;
  final String eventId;
  final Future<void> Function() onChanged;

  @override
  State<_TickButton> createState() => _TickButtonState();
}

class _TickButtonState extends State<_TickButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final done = widget.item.done;
    return PressableScale(
      haptic: HapticStrength.light,
      onTap: _busy ? null : _toggle,
      child: AnimatedContainer(
        duration: AppleDuration.fast,
        curve: AppleCurves.standard,
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: done
              ? GwdColors.success.withValues(alpha: 0.16)
              : GwdColors.sunkenOf(context),
          shape: BoxShape.circle,
          border: Border.all(
            color: done
                ? GwdColors.success.withValues(alpha: 0.55)
                : GwdColors.hairlineOf(context),
          ),
        ),
        child: _busy
            ? const SizedBox(
                width: 14, height: 14, child: BracketLoader(size: 14))
            : Icon(
                done ? Icons.check_rounded : Icons.circle_outlined,
                size: 16,
                color: done ? GwdColors.success : GwdColors.inkTertiaryOf(context),
              ),
      ),
    );
  }

  Future<void> _toggle() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await AppScope.readStore(context).updateRunSheetItem(
        widget.eventId,
        widget.item.id,
        done: !widget.item.done,
      );
      if (!widget.item.done) HapticFeedback.mediumImpact();
      await widget.onChanged();
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// The team, with a call button.
///
/// The phone number is the genuinely useful half of this screen, and the only
/// private thing on it. The server sends it only to whoever is running the
/// event; for everybody else `phone` arrives empty and no button is drawn, so
/// the client never has a number it could leak.
class _TeamRow extends StatelessWidget {
  const _TeamRow({required this.member});

  final DayTeamMember member;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: GwdSpace.sm),
      child: SurfaceCard(
        padding: const EdgeInsets.symmetric(
            horizontal: GwdSpace.lg, vertical: GwdSpace.md),
        child: Row(
          children: [
            Avatar(initials: member.initials, tint: member.tint, size: 34),
            const SizedBox(width: GwdSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    member.displayName,
                    style: GwdType.headline.copyWith(
                      color: member.isUnnamed
                          ? GwdColors.inkTertiaryOf(context)
                          : GwdColors.inkOf(context),
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    member.isLead ? 'Running this event' : member.positionLine,
                    style: GwdType.caption
                        .copyWith(color: GwdColors.inkTertiaryOf(context)),
                  ),
                ],
              ),
            ),
            if (member.phone.isNotEmpty)
              IconButton(
                tooltip: 'Call ${member.isUnnamed ? 'them' : member.name}',
                icon: const Icon(Icons.call_rounded, size: 19),
                color: GwdColors.success,
                onPressed: () => _call(member.phone),
              ),
          ],
        ),
      ),
    );
  }

  static Future<void> _call(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'[^\d+]'), ''));
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _OpenTaskRow extends StatelessWidget {
  const _OpenTaskRow({required this.task});

  final DayTask task;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: GwdSpace.sm),
      child: SurfaceCard(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => TaskDetailPage(taskId: task.id)),
        ),
        padding: const EdgeInsets.symmetric(
            horizontal: GwdSpace.lg, vertical: GwdSpace.md),
        child: Row(
          children: [
            Icon(task.status.icon, size: 17, color: task.status.tint),
            const SizedBox(width: GwdSpace.md),
            Expanded(
              child: Text(task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GwdType.headline.copyWith(color: GwdColors.inkOf(context))),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 18, color: GwdColors.inkTertiaryOf(context)),
          ],
        ),
      ),
    );
  }
}

/* --------------------------------------------------------------- the sheet */

/// Add or edit one run-sheet row.
///
/// `onChanged` on the title drives the Save button rather than `onSubmitted`:
/// the Done key is something people reasonably never press, and a Save that
/// sits dead while somebody types has shipped in this app twice already.
Future<void> showRunSheetItemSheet(
  BuildContext context, {
  required String eventId,
  required List<DayTeamMember> team,
  RunSheetItem? existing,
}) {
  return showGwdSheet<void>(
    context: context,
    builder: (_) => _RunSheetItemSheet(
      eventId: eventId,
      team: team,
      existing: existing,
    ),
  );
}

class _RunSheetItemSheet extends StatefulWidget {
  const _RunSheetItemSheet({
    required this.eventId,
    required this.team,
    this.existing,
  });

  final String eventId;
  final List<DayTeamMember> team;
  final RunSheetItem? existing;

  @override
  State<_RunSheetItemSheet> createState() => _RunSheetItemSheetState();
}

class _RunSheetItemSheetState extends State<_RunSheetItemSheet> {
  late final _title = TextEditingController(text: widget.existing?.title ?? '');
  late final _note = TextEditingController(text: widget.existing?.note ?? '');
  late TimeOfDay? _time = _parse(widget.existing?.time);
  late String? _owner = widget.existing?.ownerUserId;
  bool _busy = false;
  String? _error;

  static TimeOfDay? _parse(String? value) {
    if (value == null || value.length != 5) return null;
    final hours = int.tryParse(value.substring(0, 2));
    final mins = int.tryParse(value.substring(3));
    if (hours == null || mins == null) return null;
    return TimeOfDay(hour: hours, minute: mins);
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    final inset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: Container(
        decoration: BoxDecoration(
          color: GwdColors.raisedOf(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(GwdRadius.xl)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: GwdSpace.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SheetHeader(
                  title: editing ? 'Edit this moment' : 'Add to the run sheet',
                  subtitle: 'A time is optional — leave it off for the jobs '
                      'that just need doing at some point.',
                ),
                const SizedBox(height: GwdSpace.md),
                GwdField(
                  label: 'What happens',
                  controller: _title,
                  hint: 'Doors open',
                  autofocus: !editing,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: GwdSpace.md),
                Row(
                  children: [
                    Expanded(
                      child: SecondaryButton(
                        label: _time == null
                            ? 'Set a time'
                            : _time!.format(context),
                        icon: Icons.schedule_rounded,
                        onPressed: _pickTime,
                      ),
                    ),
                    if (_time != null) ...[
                      const SizedBox(width: GwdSpace.sm),
                      IconButton(
                        tooltip: 'Clear the time',
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () => setState(() => _time = null),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: GwdSpace.md),
                GwdField(
                  label: 'Note (optional)',
                  controller: _note,
                  hint: 'Check the mics are on first',
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                ),
                if (widget.team.isNotEmpty) ...[
                  const SizedBox(height: GwdSpace.lg),
                  Text('Who has it',
                      style: GwdType.caption
                          .copyWith(color: GwdColors.inkTertiaryOf(context))),
                  const SizedBox(height: GwdSpace.sm),
                  Wrap(
                    spacing: GwdSpace.sm,
                    runSpacing: GwdSpace.sm,
                    children: [
                      _OwnerChip(
                        label: 'Nobody yet',
                        selected: _owner == null,
                        onTap: () => setState(() => _owner = null),
                      ),
                      for (final member in widget.team)
                        _OwnerChip(
                          label: member.mustSetName ? 'No name set' : member.name,
                          selected: _owner == member.id,
                          onTap: () => setState(() => _owner = member.id),
                        ),
                    ],
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: GwdSpace.md),
                  Text(_error!,
                      style: GwdType.footnote.copyWith(color: GwdColors.primaryRed)),
                ],
                const SizedBox(height: GwdSpace.lg),
                Row(
                  children: [
                    if (editing) ...[
                      IconButton(
                        tooltip: 'Remove it',
                        icon: const Icon(Icons.delete_outline_rounded),
                        color: GwdColors.primaryRed,
                        onPressed: _busy ? null : _delete,
                      ),
                      const SizedBox(width: GwdSpace.sm),
                    ],
                    Expanded(
                      child: PrimaryButton(
                        label: editing ? 'Save it' : 'Add it',
                        busy: _busy,
                        onPressed:
                            _title.text.trim().length < 2 ? null : _save,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? TimeOfDay.now(),
    );
    if (picked != null && mounted) setState(() => _time = picked);
  }

  String get _wireTime => _time == null
      ? ''
      : '${_time!.hour.toString().padLeft(2, '0')}:'
          '${_time!.minute.toString().padLeft(2, '0')}';

  Future<void> _save() async {
    setState(() { _busy = true; _error = null; });
    final store = AppScope.readStore(context);
    final navigator = Navigator.of(context);
    try {
      if (widget.existing == null) {
        await store.addRunSheetItem(
          widget.eventId,
          title: _title.text.trim(),
          time: _wireTime,
          note: _note.text.trim(),
          ownerUserId: _owner,
        );
      } else {
        await store.updateRunSheetItem(
          widget.eventId,
          widget.existing!.id,
          title: _title.text.trim(),
          time: _wireTime,
          note: _note.text.trim(),
          // Sent even when null, so clearing the owner actually clears it.
          ownerUserId: _owner ?? '',
        );
      }
      navigator.pop();
    } catch (e) {
      if (mounted) setState(() { _busy = false; _error = '$e'; });
    }
  }

  Future<void> _delete() async {
    setState(() { _busy = true; _error = null; });
    final store = AppScope.readStore(context);
    final navigator = Navigator.of(context);
    try {
      await store.deleteRunSheetItem(widget.eventId, widget.existing!.id);
      navigator.pop();
    } catch (e) {
      if (mounted) setState(() { _busy = false; _error = '$e'; });
    }
  }
}

class _OwnerChip extends StatelessWidget {
  const _OwnerChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppleDuration.fast,
        curve: AppleCurves.standard,
        padding: const EdgeInsets.symmetric(
            horizontal: GwdSpace.md, vertical: GwdSpace.sm),
        decoration: BoxDecoration(
          color: selected
              ? GwdColors.primaryRed.withValues(alpha: 0.14)
              : GwdColors.sunkenOf(context),
          borderRadius: BorderRadius.circular(GwdRadius.pill),
          border: Border.all(
            color: selected
                ? GwdColors.primaryRed.withValues(alpha: 0.55)
                : GwdColors.hairlineOf(context),
          ),
        ),
        child: Text(
          label,
          style: GwdType.footnote.copyWith(
            color: selected ? GwdColors.primaryRed : GwdColors.inkSecondaryOf(context),
          ),
        ),
      ),
    );
  }
}
