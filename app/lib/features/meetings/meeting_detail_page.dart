import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/responsive.dart';
import '../../app/theme/apple_motion.dart';
import '../../app/theme/gwd_theme.dart';
import '../../app/widgets/common.dart';
import '../../core/api/api_client.dart';
import '../../core/models/meeting.dart';

/// One meeting, and the attendance sheet.
///
/// The sheet is the point of the screen. It is filled in by somebody looking at
/// a room, so it is built for that: every name on one page, two taps each, one
/// save at the end. A per-person round trip would leave half-marked meetings
/// behind the first time the network wobbled.
class MeetingDetailPage extends StatefulWidget {
  const MeetingDetailPage({super.key, required this.meetingId});
  final String meetingId;

  @override
  State<MeetingDetailPage> createState() => _MeetingDetailPageState();
}

class _MeetingDetailPageState extends State<MeetingDetailPage> {
  Meeting? _meeting;
  bool _canMark = false;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  /// Marks made on this screen but not yet saved. Kept apart from the meeting
  /// so an arriving live update cannot silently overwrite what somebody is
  /// halfway through recording.
  final Map<String, AttendanceMark> _draft = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final json = await AppScope.readStore(context).meetingDetail(widget.meetingId);
      if (!mounted) return;
      setState(() {
        _meeting = Meeting.fromJson((json['meeting'] as Map).cast<String, dynamic>());
        _canMark = json['canMarkAttendance'] == true;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
          _loading = false;
        });
      }
    }
  }

  AttendanceMark _markFor(MeetingParticipant p) => _draft[p.id] ?? p.status;

  Future<void> _save() async {
    if (_draft.isEmpty) return;
    final store = AppScope.readStore(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await store.markAttendance(widget.meetingId, _draft);
      _draft.clear();
      await _load();
      messenger.showSnackBar(const SnackBar(content: Text('Attendance recorded.')));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Mark everybody who has not been touched as present.
  ///
  /// Most meetings are mostly-attended, so this plus a handful of corrections
  /// is far less work than thirty individual taps — and less error-prone.
  void _markRestPresent() {
    final meeting = _meeting;
    if (meeting == null) return;
    setState(() {
      for (final p in meeting.participants) {
        if (_markFor(p) == AttendanceMark.invited) {
          _draft[p.id] = AttendanceMark.attended;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final meeting = _meeting;

    return Scaffold(
      backgroundColor: GwdColors.canvasOf(context),
      appBar: AppBar(
        title: Text('Meeting', style: GwdType.title3.copyWith(color: GwdColors.inkOf(context))),
        actions: [
          if (meeting != null && _canMark && !meeting.isCancelled)
            IconButton(
              tooltip: 'Cancel this meeting',
              icon: const Icon(Icons.event_busy_outlined, size: 20),
              onPressed: _confirmCancel,
            ),
        ],
      ),
      bottomNavigationBar: _draft.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding:
                    EdgeInsets.fromLTRB(layout.gutter, GwdSpace.sm, layout.gutter, GwdSpace.sm),
                child: PrimaryButton(
                  label: _draft.length == 1 ? 'Save 1 change' : 'Save ${_draft.length} changes',
                  icon: Icons.check_rounded,
                  busy: _busy,
                  onPressed: _save,
                ),
              ),
            ),
      body: _loading
          ? Padding(
              padding: EdgeInsets.symmetric(horizontal: layout.gutter),
              child: const SkeletonList(count: 5, height: 60),
            )
          : meeting == null
              ? EmptyState(
                  icon: Icons.event_busy_outlined,
                  title: 'Meeting not found',
                  message: _error ?? 'It may have been removed.',
                )
              : ContentWidth(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                        layout.gutter, GwdSpace.lg, layout.gutter, GwdSpace.xxxl),
                    children: [
                      FluidReveal(
                        child: Text(meeting.title,
                            style: GwdType.largeTitle.copyWith(color: GwdColors.inkOf(context))),
                      ),
                      const SizedBox(height: GwdSpace.sm),
                      FluidReveal(
                        index: 1,
                        child: Wrap(
                          spacing: GwdSpace.sm,
                          runSpacing: GwdSpace.sm,
                          children: [
                            GwdChip(
                                label: meeting.status.label.toUpperCase(),
                                color: meeting.status.tint,
                                icon: meeting.status.icon),
                            GwdChip(
                                label: _dateLabel(meeting.date).toUpperCase(),
                                color: GwdColors.inkSecondaryOf(context),
                                icon: Icons.event_rounded),
                            if (meeting.whenAndWhere.isNotEmpty)
                              GwdChip(
                                  label: meeting.whenAndWhere,
                                  color: GwdColors.inkTertiaryOf(context),
                                  icon: Icons.place_outlined),
                          ],
                        ),
                      ),
                      if (meeting.description.isNotEmpty) ...[
                        const SizedBox(height: GwdSpace.lg),
                        FluidReveal(
                          index: 2,
                          child: SurfaceCard(
                            child: Text(meeting.description,
                                style: GwdType.body
                                    .copyWith(color: GwdColors.inkSecondaryOf(context))),
                          ),
                        ),
                      ],
                      const SizedBox(height: GwdSpace.xl),
                      SectionHeader(
                        title: 'Who was asked',
                        subtitle: meeting.attendanceRecorded
                            ? '${meeting.attendedCount} of ${meeting.invitedCount} came'
                            : '${meeting.invitedCount} invited · '
                                '${_canMark ? "tap to record who came" : "attendance not recorded yet"}',
                        trailing: _canMark && !meeting.isCancelled
                            ? TextButton(
                                onPressed: _markRestPresent,
                                child: Text('All present',
                                    style: GwdType.footnote.copyWith(color: GwdColors.primaryRed)),
                              )
                            : null,
                      ),
                      for (final p in meeting.participants)
                        Padding(
                          padding: const EdgeInsets.only(bottom: GwdSpace.xs),
                          child: _ParticipantRow(
                            participant: p,
                            mark: _markFor(p),
                            editable: _canMark && !meeting.isCancelled,
                            changed: _draft.containsKey(p.id),
                            onChanged: (next) => setState(() {
                              if (next == p.status) {
                                _draft.remove(p.id);
                              } else {
                                _draft[p.id] = next;
                              }
                            }),
                          ),
                        ),
                      const SizedBox(height: GwdSpace.xl),
                      Text('Called by ${meeting.createdByName}.',
                          style:
                              GwdType.footnote.copyWith(color: GwdColors.inkTertiaryOf(context))),
                    ],
                  ),
                ),
    );
  }

  static String _dateLabel(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${d.day} ${months[d.month - 1]}';
  }

  Future<void> _confirmCancel() async {
    final store = AppScope.readStore(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: GwdColors.surfaceOf(dialogContext),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GwdRadius.xl)),
        title: Text('Call this meeting off?',
            style: GwdType.title3.copyWith(color: GwdColors.inkOf(dialogContext))),
        content: Text(
          'Everybody invited is told. It stops counting towards anybody\'s '
          'attendance, so nobody is marked absent for a meeting that did not '
          'happen.',
          style: GwdType.callout.copyWith(color: GwdColors.inkSecondaryOf(dialogContext)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Keep it',
                style: GwdType.callout.copyWith(color: GwdColors.inkSecondaryOf(dialogContext))),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Cancel the meeting',
                style: GwdType.callout
                    .copyWith(color: GwdColors.critical, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await store.updateMeeting(widget.meetingId, status: MeetingStatus.cancelled);
      await _load();
      messenger.showSnackBar(const SnackBar(content: Text('Meeting cancelled.')));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$error')));
    }
  }
}

/// One name on the sheet.
///
/// Three states rather than a checkbox: "not recorded" has to stay visibly
/// different from "did not come", or somebody skimming a half-filled sheet
/// marks people absent who were simply never reached.
class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({
    required this.participant,
    required this.mark,
    required this.editable,
    required this.changed,
    required this.onChanged,
  });

  final MeetingParticipant participant;
  final AttendanceMark mark;
  final bool editable;
  final bool changed;
  final ValueChanged<AttendanceMark> onChanged;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(GwdSpace.sm + 2),
      borderColor: changed ? GwdColors.primaryRed.withValues(alpha: 0.35) : null,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(participant.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GwdType.callout.copyWith(color: GwdColors.inkOf(context))),
                Text(
                  participant.isOrganiser
                      ? 'Called the meeting'
                      : participant.viaDepartment
                          ? 'Invited with their team'
                          : 'Invited individually',
                  style: GwdType.micro.copyWith(color: GwdColors.inkTertiaryOf(context)),
                ),
              ],
            ),
          ),
          if (!editable)
            GwdChip(label: mark.label, color: mark.tint, icon: mark.icon, dense: true)
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _MarkButton(
                  icon: Icons.check_rounded,
                  tint: GwdColors.success,
                  selected: mark == AttendanceMark.attended,
                  onTap: () => onChanged(AttendanceMark.attended),
                ),
                const SizedBox(width: 6),
                _MarkButton(
                  icon: Icons.close_rounded,
                  tint: GwdColors.critical,
                  selected: mark == AttendanceMark.absent,
                  onTap: () => onChanged(AttendanceMark.absent),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _MarkButton extends StatelessWidget {
  const _MarkButton({
    required this.icon,
    required this.tint,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final Color tint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      pressedScale: 0.9,
      haptic: HapticStrength.selection,
      child: AnimatedContainer(
        duration: AppleDuration.fast,
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? tint : GwdColors.sunkenOf(context),
          borderRadius: BorderRadius.circular(GwdRadius.sm),
        ),
        child:
            Icon(icon, size: 18, color: selected ? Colors.white : GwdColors.inkTertiaryOf(context)),
      ),
    );
  }
}
