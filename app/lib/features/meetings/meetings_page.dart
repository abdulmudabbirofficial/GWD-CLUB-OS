import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/responsive.dart';
import '../../app/theme/apple_motion.dart';
import '../../app/theme/gwd_theme.dart';
import '../../app/widgets/common.dart';
import '../../core/models/meeting.dart';
import 'meeting_detail_page.dart';
import 'new_meeting_sheet.dart';

/// Meetings, and who turned up.
///
/// A meeting is not a schedule entry with a different label: it carries an
/// invitee list and an attendance record, and those are what every attendance
/// figure in the app is derived from.
///
/// Two sections, because they answer different questions. "What am I expected
/// at?" is a plan; "did people come?" is a record, and the second is only
/// interesting once the first has happened.
class MeetingsPage extends StatefulWidget {
  const MeetingsPage({super.key});

  @override
  State<MeetingsPage> createState() => _MeetingsPageState();
}

class _MeetingsPageState extends State<MeetingsPage> {
  @override
  void initState() {
    super.initState();
    // The store owns the data; this only asks it to refresh on open. Live
    // updates arrive over the socket and rebuild this page for free.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppScope.readStore(context).loadMeetings();
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.storeOf(context);
    final layout = Layout.of(context);
    final upcoming = store.meetingsUpcoming;
    final past = store.meetingsPast;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text('Meetings', style: GwdType.title3.copyWith(color: GwdColors.inkOf(context))),
      ),
      floatingActionButton: store.canScheduleMeetings
          ? FloatingActionButton.extended(
              onPressed: () => showNewMeetingSheet(context),
              backgroundColor: GwdColors.primaryRed,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: Text('Call a meeting', style: GwdType.headline.copyWith(color: Colors.white)),
            )
          : null,
      body: RefreshIndicator(
        color: GwdColors.primaryRed,
        onRefresh: store.loadMeetings,
        child: ContentWidth(
          child: upcoming.isEmpty && past.isEmpty
              ? ListView(children: [
                  const SizedBox(height: 70),
                  EmptyState(
                    icon: Icons.groups_2_outlined,
                    title: 'No meetings yet',
                    message: store.canScheduleMeetings
                        ? 'Call one and everybody invited is told straight away.'
                        : 'You will see meetings here as soon as you are invited to one.',
                  ),
                ])
              : CustomScrollView(
                  slivers: [
                    if (upcoming.isNotEmpty) ...[
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                            layout.gutter, GwdSpace.lg, layout.gutter, 0),
                        sliver: const SliverToBoxAdapter(
                          child: SectionHeader(title: 'Coming up'),
                        ),
                      ),
                      SliverPadding(
                        padding: EdgeInsets.symmetric(horizontal: layout.gutter),
                        sliver: SliverList.builder(
                          itemCount: upcoming.length,
                          itemBuilder: (context, i) => _row(upcoming[i], i),
                        ),
                      ),
                    ],
                    if (past.isNotEmpty) ...[
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          layout.gutter,
                          upcoming.isEmpty ? GwdSpace.lg : GwdSpace.xl,
                          layout.gutter,
                          0,
                        ),
                        sliver: SliverToBoxAdapter(
                          child: SectionHeader(
                            title: 'Been and gone',
                            subtitle:
                                past.any((m) => !m.attendanceRecorded && !m.isCancelled)
                                    ? 'Some still need attendance recording'
                                    : null,
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: EdgeInsets.symmetric(horizontal: layout.gutter),
                        sliver: SliverList.builder(
                          itemCount: past.length,
                          itemBuilder: (context, i) =>
                              _row(past[i], upcoming.length + i),
                        ),
                      ),
                    ],
                    const SliverToBoxAdapter(
                      child: SizedBox(height: GwdSpace.xxxl + 40),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  /// One row, staggered only while it is part of the first screenful.
  ///
  /// A meeting list runs the whole term. Building and animating every card to
  /// show the five that fit is work nobody sees, and a card that fades in as
  /// you scroll past it reads as the list lagging.
  Widget _row(Meeting meeting, int index) => Padding(
        padding: const EdgeInsets.only(bottom: GwdSpace.sm),
        child: index < 8
            ? AppleStaggerItem(index: index, child: MeetingCard(meeting: meeting))
            : MeetingCard(meeting: meeting),
      );
}

/// One meeting, as a row.
class MeetingCard extends StatelessWidget {
  const MeetingCard({super.key, required this.meeting, this.compact = false});

  final Meeting meeting;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final needsAttendance = meeting.isPast && !meeting.attendanceRecorded && !meeting.isCancelled;

    return SurfaceCard(
      padding: const EdgeInsets.all(GwdSpace.md),
      borderColor: meeting.isToday && !meeting.isCancelled
          ? GwdColors.primaryRed.withValues(alpha: 0.35)
          : null,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => MeetingDetailPage(meetingId: meeting.id)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DateBlock(meeting: meeting),
              const SizedBox(width: GwdSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      meeting.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GwdType.headline.copyWith(
                        color: GwdColors.inkOf(context),
                        decoration: meeting.isCancelled ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    if (meeting.whenAndWhere.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(meeting.whenAndWhere,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              GwdType.footnote.copyWith(color: GwdColors.inkTertiaryOf(context))),
                    ],
                    const SizedBox(height: 2),
                    Text(meeting.whoLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GwdType.caption.copyWith(
                            fontSize: 10,
                            letterSpacing: 0,
                            color: GwdColors.inkTertiaryOf(context))),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 18, color: GwdColors.inkTertiaryOf(context)),
            ],
          ),
          if (!compact) ...[
            const SizedBox(height: GwdSpace.sm),
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                if (meeting.isCancelled)
                  const GwdChip(
                      label: 'Cancelled',
                      color: GwdColors.inkTertiary,
                      icon: Icons.event_busy_outlined,
                      dense: true),
                if (meeting.isToday && !meeting.isCancelled)
                  const GwdChip(
                      label: 'Today',
                      color: GwdColors.primaryRed,
                      icon: Icons.today_rounded,
                      dense: true),
                // The one thing on this card somebody can act on.
                if (needsAttendance)
                  const GwdChip(
                      label: 'Attendance not recorded',
                      color: GwdColors.warning,
                      icon: Icons.how_to_reg_outlined,
                      dense: true),
                if (meeting.attendanceRecorded)
                  GwdChip(
                      label: '${meeting.attendedCount} of ${meeting.invitedCount} came',
                      color: GwdColors.success,
                      icon: Icons.check_rounded,
                      dense: true),
                // How this viewer was marked, if they were.
                if (meeting.myStatus != null && meeting.myStatus != AttendanceMark.invited)
                  GwdChip(
                      label: 'You: ${meeting.myStatus!.label.toLowerCase()}',
                      color: meeting.myStatus!.tint,
                      icon: meeting.myStatus!.icon,
                      dense: true),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// The date, as a block rather than a line of text — it is the thing people
/// scan a meeting list for.
class _DateBlock extends StatelessWidget {
  const _DateBlock({required this.meeting});
  final Meeting meeting;

  static const _months = [
    'JAN',
    'FEB',
    'MAR',
    'APR',
    'MAY',
    'JUN',
    'JUL',
    'AUG',
    'SEP',
    'OCT',
    'NOV',
    'DEC',
  ];

  @override
  Widget build(BuildContext context) {
    final live = meeting.isToday && !meeting.isCancelled;
    return Container(
      width: 48,
      padding: const EdgeInsets.symmetric(vertical: GwdSpace.sm),
      decoration: BoxDecoration(
        color: live ? GwdColors.primaryRed.withValues(alpha: 0.10) : GwdColors.sunkenOf(context),
        borderRadius: BorderRadius.circular(GwdRadius.md),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_months[meeting.date.month - 1],
              style: GwdType.micro.copyWith(
                color: live ? GwdColors.primaryRed : GwdColors.inkTertiaryOf(context),
              )),
          Text('${meeting.date.day}',
              style: GwdType.title3.merge(GwdType.numeric).copyWith(
                    color: live ? GwdColors.primaryRed : GwdColors.inkOf(context),
                  )),
        ],
      ),
    );
  }
}
