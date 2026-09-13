import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/responsive.dart';
import '../../app/theme/apple_motion.dart';
import '../../app/theme/gwd_theme.dart';
import '../../app/widgets/brand.dart';
import '../../app/widgets/common.dart';
import '../../core/models/recognition.dart';
import 'department_chart.dart';
import 'recognition_rows.dart';

/// One department's recognition, on its own page.
///
/// This used to expand inline on the Recognition list. Expanding pushed every
/// other department off the screen while still only having room for a name and
/// a number, which is the worst of both — the list stopped being scannable and
/// the detail never got the space to say anything.
///
/// A page has room for what somebody actually came to find out: how much work
/// the department was given, how much landed, what is still sitting unassigned,
/// and then the people. The rule from the list still holds here — no ranks, no
/// podium, nothing telling anybody they are beating anybody.
///
/// Reads from the store on every build rather than taking a snapshot, so
/// awarding points or finishing a task updates this page underneath the user
/// instead of leaving it quietly disagreeing with the directory.
class DepartmentRecognitionPage extends StatelessWidget {
  const DepartmentRecognitionPage({super.key, required this.departmentId});

  final String departmentId;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.storeOf(context);
    final me = AppScope.sessionOf(context).me;
    final layout = Layout.of(context);

    final group = store.recognition
        .where((g) => g.departmentId == departmentId)
        .cast<DepartmentRecognition?>()
        .firstWhere((g) => true, orElse: () => null);

    // The club-wide row for the same department: given vs finished, and what is
    // still waiting on its Lead. Absent is fine — it is a separate endpoint.
    final progress = store.departmentProgress
        .where((p) => p.departmentId == departmentId)
        .cast<DepartmentProgress?>()
        .firstWhere((p) => true, orElse: () => null);

    if (group == null) {
      return Scaffold(
        backgroundColor: GwdColors.canvasOf(context),
        appBar: AppBar(
          title: Text('Department',
              style: GwdType.title3.copyWith(color: GwdColors.inkOf(context))),
        ),
        body: const EmptyState(
          icon: Icons.workspaces_outline,
          title: 'Department not found',
          message: 'It may have been renamed or retired since this was opened.',
        ),
      );
    }

    final tint = group.tint;
    final totals = group.totals;

    return Scaffold(
      backgroundColor: GwdColors.canvasOf(context),
      appBar: AppBar(
        title: Text(group.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GwdType.title3.copyWith(color: GwdColors.inkOf(context))),
      ),
      body: RefreshIndicator(
        color: GwdColors.primaryRed,
        onRefresh: () async {
          await store.loadLeaderboard();
          await store.loadDepartmentProgress();
        },
        child: ContentWidth(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
                layout.gutter, GwdSpace.lg, layout.gutter, GwdSpace.xxxl),
            children: [
              // ---------- the headline numbers ----------
              AppleStaggerItem(
                index: 0,
                child: _Headline(group: group, progress: progress, tint: tint),
              ),

              // ---------- what is waiting on somebody ----------
              if (progress != null && progress.awaitingHandout > 0) ...[
                const SizedBox(height: GwdSpace.md),
                AppleStaggerItem(
                  index: 1,
                  child: _WaitingNote(count: progress.awaitingHandout),
                ),
              ],

              // ---------- the shape of the department ----------
              // How the work is spread, which a list of numbers cannot show.
              // Hides itself when there is not enough to compare.
              if (group.members.length >= 2) ...[
                const SizedBox(height: GwdSpace.xl),
                AppleStaggerItem(
                  index: 1,
                  child: SurfaceCard(
                    padding: const EdgeInsets.fromLTRB(
                        GwdSpace.md, GwdSpace.lg, GwdSpace.md, GwdSpace.md),
                    child: DepartmentChart(members: group.members, tint: tint),
                  ),
                ),
              ],

              // ---------- the Lead ----------
              if (group.lead != null) ...[
                const SizedBox(height: GwdSpace.xxl),
                const AppleStaggerItem(
                  index: 2,
                  child: BrandedSectionHeader(
                    title: 'Lead',
                    subtitle: 'Earns from everything the department finishes',
                  ),
                ),
                AppleStaggerItem(
                  index: 3,
                  child: LeadCard(
                    lead: group.lead!,
                    tint: tint,
                    isMe: group.lead!.id == me?.id,
                    departmentPoints: totals.points,
                  ),
                ),
              ],

              // ---------- the team ----------
              const SizedBox(height: GwdSpace.xxl),
              AppleStaggerItem(
                index: 4,
                child: BrandedSectionHeader(
                  title: 'The team',
                  subtitle: group.members.isEmpty
                      ? null
                      : '${group.members.length} '
                          '${group.members.length == 1 ? 'person' : 'people'}, '
                          'most points first',
                ),
              ),
              if (group.members.isEmpty)
                const EmptyState(
                  compact: true,
                  icon: Icons.person_search_outlined,
                  title: 'Nobody here yet',
                  message: 'Members appear once their Lead approves them.',
                )
              else
                for (var i = 0; i < group.members.length; i++)
                  AppleStaggerItem(
                    index: 5 + i,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: GwdSpace.sm),
                      child: RecognitionMemberRow(
                        member: group.members[i],
                        isMe: group.members[i].id == me?.id,
                        tint: tint,
                      ),
                    ),
                  ),

              const SizedBox(height: GwdSpace.xxl),
              Text(
                'Ordered by points earned, which is the figure the Lead '
                'calibrated when they handed each task out. Nothing here ranks '
                'one department against another.',
                style: GwdType.footnote
                    .copyWith(color: GwdColors.inkTertiaryOf(context)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The four numbers somebody actually came for, above everything else.
class _Headline extends StatelessWidget {
  const _Headline({
    required this.group,
    required this.progress,
    required this.tint,
  });

  final DepartmentRecognition group;
  final DepartmentProgress? progress;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final totals = group.totals;
    final assigned = progress?.assigned ?? totals.assigned;
    final completed = progress?.completed ?? totals.completed;
    final open = progress?.open ?? (assigned - completed).clamp(0, assigned);

    return SurfaceCard(
      emphasis: SurfaceEmphasis.raised,
      padding: const EdgeInsets.all(GwdSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 34,
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: GwdSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(group.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GwdType.title3
                            .copyWith(color: GwdColors.inkOf(context))),
                    Text(
                      totals.people == 0
                          ? 'Nobody here yet'
                          : '${totals.people} '
                              '${totals.people == 1 ? 'person' : 'people'}',
                      style: GwdType.footnote
                          .copyWith(color: GwdColors.inkTertiaryOf(context)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: GwdSpace.lg),

          // Given / finished / still going / points. Counts, never a
          // percentage headline — "72%" invites comparison with the department
          // next door, which is the one thing this screen must not do.
          Row(
            children: [
              _Stat(label: 'GIVEN', value: assigned),
              _Divider(),
              _Stat(label: 'FINISHED', value: completed, tint: tint),
              _Divider(),
              _Stat(label: 'STILL GOING', value: open),
              _Divider(),
              _Stat(label: 'POINTS', value: totals.points),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.tint});

  final String label;
  final int value;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          AnimatedCounter(
            value: value,
            style: GwdType.title2.merge(GwdType.numeric).copyWith(
                  color: tint ?? GwdColors.inkOf(context),
                ),
          ),
          const SizedBox(height: 2),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: GwdType.caption.copyWith(
                  fontSize: 8.5, color: GwdColors.inkTertiaryOf(context))),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 26,
        color: GwdColors.hairlineOf(context),
      );
}

/// Work the department has been given that its Lead has not passed on yet.
///
/// The one number on this page somebody can act on today, so it gets the
/// accent and plain language rather than sitting as a fifth statistic.
class _WaitingNote extends StatelessWidget {
  const _WaitingNote({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(GwdSpace.md),
      decoration: BoxDecoration(
        color: GwdColors.primaryRed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(GwdRadius.md),
      ),
      child: Row(
        children: [
          const Icon(Icons.inbox_rounded, size: 16, color: GwdColors.primaryRed),
          const SizedBox(width: GwdSpace.md),
          Expanded(
            child: Text(
              count == 1
                  ? '1 task is waiting to be handed out.'
                  : '$count tasks are waiting to be handed out.',
              style: GwdType.footnote
                  .copyWith(color: GwdColors.inkSecondaryOf(context)),
            ),
          ),
        ],
      ),
    );
  }
}
