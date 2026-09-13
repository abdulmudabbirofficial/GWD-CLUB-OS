import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/responsive.dart';
import '../../app/theme/apple_motion.dart';
import '../../app/theme/gwd_theme.dart';
import '../../app/widgets/common.dart';
import '../../core/models/club_event.dart';

/// What has happened on this event.
///
/// Section 18 is explicit that this should give visibility without becoming
/// surveillance, and the difference is what gets recorded. This shows things
/// that *happened to the event* — a task finished, paperwork filed, the status
/// moved. It does not show who was late, who has not opened the app, or how
/// long anything sat in someone's lane. Names appear because "Marketing
/// finished the poster" is useful information; nothing here counts misses.
class EventUpdatesTab extends StatefulWidget {
  const EventUpdatesTab({super.key, required this.eventId});
  final String eventId;

  @override
  State<EventUpdatesTab> createState() => _EventUpdatesTabState();
}

class _EventUpdatesTabState extends State<EventUpdatesTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppScope.readStore(context).loadEventTimeline(widget.eventId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.storeOf(context);
    final timeline = store.timelineFor(widget.eventId);
    final gutter = Layout.of(context).gutter;

    if (timeline == null) {
      return const Padding(
        padding: EdgeInsets.all(GwdSpace.xl),
        child: SkeletonList(count: 5, height: 56),
      );
    }

    if (timeline.isEmpty) {
      return const EmptyState(
        icon: Icons.timeline_rounded,
        title: 'Nothing has happened yet',
        message: 'As work gets done and paperwork lands, it shows up here.',
      );
    }

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(gutter, GwdSpace.xl, gutter, GwdSpace.xxxl),
      itemCount: timeline.length,
      itemBuilder: (context, i) => AppleStaggerItem(
        index: i,
        child: _TimelineRow(
          activity: timeline[i],
          first: i == 0,
          last: i == timeline.length - 1,
        ),
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.activity,
    required this.first,
    required this.last,
  });

  final EventActivity activity;
  final bool first;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final tint = switch (activity.kind) {
      'taskCompleted' => GwdColors.success,
      'document' => GwdColors.info,
      'document.decision' => GwdColors.success,
      'event.status' => GwdColors.primaryRed,
      _ => GwdColors.inkTertiaryOf(context),
    };

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A drawn rail rather than a divider between cards: an event's history
          // is a sequence, and the line is what says so.
          SizedBox(
            width: 26,
            child: Column(
              children: [
                Container(
                  width: 2,
                  height: 8,
                  color: first ? Colors.transparent : GwdColors.hairlineOf(context),
                ),
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: tint,
                    shape: BoxShape.circle,
                    border: Border.all(color: GwdColors.canvasOf(context), width: 2),
                  ),
                ),
                Expanded(
                  child: Container(
                    width: 2,
                    color: last ? Colors.transparent : GwdColors.hairlineOf(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: GwdSpace.sm),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: GwdSpace.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(activity.icon, size: 13, color: tint),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          activity.text,
                          style: GwdType.callout
                              .copyWith(color: GwdColors.inkOf(context)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Padding(
                    padding: const EdgeInsets.only(left: 18),
                    child: Text(
                      [
                        if (activity.who != null) activity.who!,
                        _when(activity.at),
                      ].join('  ·  '),
                      style: GwdType.caption.copyWith(
                          fontSize: 9.5,
                          letterSpacing: 0,
                          color: GwdColors.inkTertiaryOf(context)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _when(DateTime at) {
    final minutes = DateTime.now().difference(at).inMinutes;
    if (minutes < 1) return 'just now';
    if (minutes < 60) return '${minutes}m ago';
    if (minutes < 60 * 24) return '${(minutes / 60).floor()}h ago';
    final days = (minutes / (60 * 24)).floor();
    if (days == 1) return 'yesterday';
    if (days < 7) return '${days}d ago';
    return '${at.day}/${at.month}';
  }
}
