import 'package:circular_clip_route/circular_clip_route.dart';
import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/responsive.dart';
import '../../app/theme/apple_motion.dart';
import '../../app/theme/gwd_theme.dart';
import '../../app/widgets/brand.dart';
import '../../app/widgets/common.dart';
import '../../core/models/recognition.dart';
import 'department_chart.dart';
import 'department_recognition_page.dart';
import 'recognition_rows.dart';

/// Recognition — **per department, never club-wide**.
///
/// A single club-wide board compares a Cinematography member who shoots two
/// films a term against a Marketing member posting daily. They are not doing
/// the same job and the comparison tells nobody anything. Inside a department
/// the work is at least alike, and the group is small enough to read as a team
/// rather than a table.
///
/// Points are 1, 3 or 5 per task, set by the Lead when they hand it out, so a
/// hard job counts for more than an easy one. The Lead is shown *above* their
/// team rather than in it: they earn from everything the department finishes,
/// so a row would always sit on top and say nothing.
///
/// Reads straight from the store rather than fetching its own copy — the old
/// version loaded once in initState, so awarding points changed the directory
/// and this screen silently disagreed with it.
class LeaderboardPage extends StatefulWidget {
  const LeaderboardPage({super.key});

  @override
  State<LeaderboardPage> createState() => _LeaderboardPageState();
}

class _LeaderboardPageState extends State<LeaderboardPage> {
  @override
  void initState() {
    super.initState();
    // Each department tile shows what that department was given against what it
    // finished, which comes from a different endpoint to the boards themselves.
    // Without this the tiles would show zeros until something else happened to
    // load it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppScope.readStore(context).loadDepartmentProgress();
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.storeOf(context);
    final me = AppScope.sessionOf(context).me;
    final layout = Layout.of(context);
    final groups = store.recognition;

    return Scaffold(
      backgroundColor: GwdColors.canvasOf(context),
      appBar: AppBar(
        title: Text('Recognition',
            style: GwdType.title3.copyWith(color: GwdColors.inkOf(context))),
      ),
      body: RefreshIndicator(
        color: GwdColors.primaryRed,
        onRefresh: () async {
          await store.loadLeaderboard();
          await store.loadDepartmentProgress();
        },
        child: ContentWidth(
          child: store.loading && groups.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(GwdSpace.xxxl),
                    child: BracketLoader(),
                  ),
                )
              : groups.isEmpty
                  ? const EmptyState(
                      icon: Icons.volunteer_activism_outlined,
                      title: 'Nothing to show yet',
                      message:
                          'Once tasks start being handed out and finished, each '
                          'department’s progress shows up here.',
                    )
                  : ListView(
                      padding: EdgeInsets.fromLTRB(
                          layout.gutter, GwdSpace.lg, layout.gutter, GwdSpace.xxxl),
                      children: [
                        const _Preamble(),

                        // The club in one picture, before the per-department
                        // rows. Given against finished is the question everyone
                        // asks first, and it is aggregate — it gives away
                        // nothing about any individual.
                        if (store.departmentProgress.length >= 2) ...[
                          const SizedBox(height: GwdSpace.lg),
                          SurfaceCard(
                            padding: const EdgeInsets.fromLTRB(GwdSpace.md,
                                GwdSpace.lg, GwdSpace.md, GwdSpace.md),
                            child: ClubProgressChart(
                                departments: store.departmentProgress),
                          ),
                        ],

                        const SizedBox(height: GwdSpace.xl),

                        for (var i = 0; i < groups.length; i++)
                          AppleStaggerItem(
                            index: i,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: GwdSpace.md),
                              child: _DepartmentTile(
                                group: groups[i],
                                progress: store.departmentProgress
                                    .where((p) =>
                                        p.departmentId == groups[i].departmentId)
                                    .cast<DepartmentProgress?>()
                                    .firstWhere((p) => true, orElse: () => null),
                                mine: groups[i].departmentId == me?.departmentId,
                              ),
                            ),
                          ),

                        if (store.unaffiliated.isNotEmpty) ...[
                          const SizedBox(height: GwdSpace.lg),
                          const BrandedSectionHeader(
                            title: 'Running the club',
                            subtitle: 'Not inside any one department',
                          ),
                          for (final person in store.unaffiliated)
                            Padding(
                              padding: const EdgeInsets.only(bottom: GwdSpace.sm),
                              child: RecognitionMemberRow(
                                member: person,
                                isMe: person.id == me?.id,
                                tint: GwdColors.inkSecondaryOf(context),
                              ),
                            ),
                        ],
                      ],
                    ),
        ),
      ),
    );
  }
}

class _Preamble extends StatelessWidget {
  const _Preamble();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(GwdSpace.md),
      decoration: BoxDecoration(
        color: GwdColors.sunkenOf(context),
        borderRadius: BorderRadius.circular(GwdRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.favorite_outline_rounded,
              size: 16, color: GwdColors.inkTertiaryOf(context)),
          const SizedBox(width: GwdSpace.md),
          Expanded(
            child: Text(
              'Each department keeps its own list — a Cinematography member and a '
              'Marketing member are not doing the same job, so comparing them says '
              'nothing. Tasks are worth 1, 3 or 5 points, set by the Lead when they '
              'hand the work out.',
              style: GwdType.footnote
                  .copyWith(color: GwdColors.inkSecondaryOf(context)),
            ),
          ),
        ],
      ),
    );
  }
}

/// One department, as a row that opens its own page.
///
/// This used to expand in place. Expanding pushed every other department off
/// the screen while still only having room for a name and a number — the list
/// stopped being scannable and the detail never got the space to say anything.
/// A tile carries the summary; the page carries the rest.
class _DepartmentTile extends StatelessWidget {
  const _DepartmentTile({
    required this.group,
    required this.progress,
    required this.mine,
  });

  final DepartmentRecognition group;
  final DepartmentProgress? progress;

  /// The viewer's own department gets a tinted edge — not a position, just a
  /// way to find yourself in an alphabetical list.
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final tint = group.tint;
    final totals = group.totals;
    final waiting = progress?.awaitingHandout ?? 0;

    return SurfaceCard(
      padding: const EdgeInsets.all(GwdSpace.lg),
      borderColor: mine ? tint.withValues(alpha: 0.3) : null,
      // The department's page opens as a circle spreading from the row you
      // tapped, in that department's own colour. It ties the tile to the page
      // it became — you can see where you came from — where a slide would just
      // be another screen arriving from the right.
      //
      // Reduced-motion is honoured: the flag comes from the platform, and
      // somebody who has asked for less movement gets the ordinary transition.
      onTap: () {
        if (prefersReducedMotion(context)) {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) =>
                DepartmentRecognitionPage(departmentId: group.departmentId),
          ));
          return;
        }
        Navigator.of(context).push(CircularClipRoute(
          builder: (_) =>
              DepartmentRecognitionPage(departmentId: group.departmentId),
          expandFrom: context,
          curve: AppleCurves.enter,
          reverseCurve: AppleCurves.exit,
          transitionDuration: AppleDuration.standard,
        ));
      },
      child: Row(
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        GwdType.title3.copyWith(color: GwdColors.inkOf(context))),
                const SizedBox(height: 1),
                Text(
                  // Factual, never comparative.
                  switch ((totals.people, totals.completed)) {
                    (0, _) => 'Nobody here yet',
                    (_, 0) => '${totals.people} people · nothing finished yet',
                    (_, final done) =>
                      '${totals.people} people · $done finished · '
                          '${totals.points} points',
                  },
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GwdType.footnote
                      .copyWith(color: GwdColors.inkTertiaryOf(context)),
                ),
              ],
            ),
          ),

          // The one thing on this list somebody can act on today.
          if (waiting > 0) ...[
            const SizedBox(width: GwdSpace.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: GwdSpace.sm, vertical: 3),
              decoration: BoxDecoration(
                color: GwdColors.primaryRed.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(GwdRadius.sm),
              ),
              child: Text('$waiting waiting',
                  style: GwdType.caption.copyWith(
                      fontSize: 9.5,
                      letterSpacing: 0,
                      color: GwdColors.primaryRed)),
            ),
          ],

          const SizedBox(width: GwdSpace.xs),
          Icon(Icons.chevron_right_rounded,
              size: 20, color: GwdColors.inkTertiaryOf(context)),
        ],
      ),
    );
  }
}

// LeadCard and RecognitionMemberRow live in recognition_rows.dart — shared with
// the department page so the same person cannot render differently depending on
// which screen you reached them from.
