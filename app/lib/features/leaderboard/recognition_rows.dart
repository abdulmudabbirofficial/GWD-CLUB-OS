import 'package:flutter/material.dart';

import '../../app/theme/apple_motion.dart';
import '../../app/theme/gwd_theme.dart';
import '../../app/widgets/common.dart';
import '../../core/models/member.dart';
import 'member_stats_page.dart';

/// The two rows recognition is made of, shared by the department list and the
/// department page so the same person cannot render differently depending on
/// which screen you reached them from.
///
/// Neither row carries a rank, a position number or a medal. Recognition is
/// about who is doing the work, not who is beating whom.

/// The Lead, above the list rather than inside it.
///
/// They are credited for everything their department finishes — their job is
/// getting the team's work done, so a department that delivers is a Lead who
/// delivered. Putting them in the list would mean they always top it, which
/// says nothing and would quietly discourage everyone below.
class LeadCard extends StatelessWidget {
  const LeadCard({
    super.key,
    required this.lead,
    required this.tint,
    required this.isMe,
    required this.departmentPoints,
  });

  final Member lead;
  final Color tint;
  final bool isMe;
  final int departmentPoints;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => MemberStatsPage(member: lead)),
      ),
      pressedScale: 0.99,
      child: Container(
        padding: const EdgeInsets.all(GwdSpace.md),
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(GwdRadius.md),
        ),
        child: Row(
          children: [
            Stack(
              children: [
                Avatar(initials: lead.initials, tint: tint, size: 40, selected: true),
                Positioned(
                  right: -1,
                  bottom: -1,
                  child: Container(
                    padding: const EdgeInsets.all(2.5),
                    decoration: BoxDecoration(
                      color: tint,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: GwdColors.surfaceOf(context), width: 1.5),
                    ),
                    child: const Icon(Icons.star_rounded, size: 8, color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(width: GwdSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(isMe ? '${lead.displayName} (you)' : lead.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GwdType.headline.copyWith(
                          color: lead.isUnnamed
                              ? GwdColors.inkTertiaryOf(context)
                              : GwdColors.inkOf(context))),
                  const SizedBox(height: 1),
                  Text('Lead · earns from everything the department finishes',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GwdType.caption.copyWith(
                          fontSize: 9.5,
                          letterSpacing: 0,
                          color: GwdColors.inkTertiaryOf(context))),
                ],
              ),
            ),
            AnimatedCounter(
              value: lead.points,
              suffix: ' pts',
              style: GwdType.callout
                  .copyWith(color: tint, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

/// One person on a department's board.
class RecognitionMemberRow extends StatelessWidget {
  const RecognitionMemberRow({
    super.key,
    required this.member,
    required this.isMe,
    required this.tint,
  });

  final Member member;
  final bool isMe;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final assigned = member.assignedTasks ?? 0;
    final completed = member.completedTasks ?? 0;

    return SurfaceCard(
      padding: const EdgeInsets.all(GwdSpace.md),
      borderColor: isMe ? tint.withValues(alpha: 0.4) : null,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => MemberStatsPage(member: member)),
      ),
      child: Row(
        children: [
          Avatar(initials: member.initials, tint: member.tint, size: 36),
          const SizedBox(width: GwdSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(isMe ? '${member.displayName} (you)' : member.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GwdType.headline.copyWith(
                        color: member.isUnnamed
                            ? GwdColors.inkTertiaryOf(context)
                            : GwdColors.inkOf(context))),
                const SizedBox(height: 2),
                Text(
                  assigned == 0
                      ? 'nothing assigned yet'
                      : '$completed of $assigned done',
                  style: GwdType.footnote
                      .copyWith(color: GwdColors.inkTertiaryOf(context)),
                ),
              ],
            ),
          ),
          const SizedBox(width: GwdSpace.sm),
          // Points count up rather than jump-cutting, so work finishing while
          // you are looking at the screen is visible.
          AnimatedCounter(
            value: member.points,
            suffix: ' pts',
            style: GwdType.callout.copyWith(
              color: member.points > 0
                  ? GwdColors.inkOf(context)
                  : GwdColors.inkTertiaryOf(context),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
