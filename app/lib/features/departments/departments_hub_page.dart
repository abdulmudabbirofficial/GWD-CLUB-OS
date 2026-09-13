import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/responsive.dart';
import '../../app/theme/apple_motion.dart';
import '../../app/theme/gwd_theme.dart';
import '../../app/widgets/common.dart';
import '../../core/models/department.dart';
import '../../core/models/recognition.dart';
import 'department_workspace_page.dart';

/// The Departments tab.
///
/// Section 31: this is *Department Progress*, never a performance ranking.
/// Departments are listed alphabetically — never sorted by how well they are
/// doing — and nothing here compares one to another. Knowing Marketing is 60%
/// through its work is useful context for the whole club; a league table of
/// departments quietly stops people covering for each other.
class DepartmentsHubPage extends StatelessWidget {
  const DepartmentsHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.storeOf(context);
    final session = AppScope.sessionOf(context);
    final layout = Layout.of(context);

    final departments = store.departments.where((d) => d.active).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final mine = departments.where((d) => d.id == session.me?.departmentId).toList();
    final others = departments.where((d) => d.id != session.me?.departmentId).toList();

    var step = 0;
    int next() => step++;

    return Scaffold(
      backgroundColor: GwdColors.canvasOf(context),
      body: RefreshIndicator(
        color: GwdColors.primaryRed,
        onRefresh: () => store.loadDepartments(),
        child: ListView(
          padding: EdgeInsets.fromLTRB(layout.gutter, 0, layout.gutter, GwdSpace.xxxl),
          children: [
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.only(top: GwdSpace.lg),
                child: AppleStaggerItem(
                  index: next(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Departments',
                          style: GwdType.largeTitle
                              .copyWith(color: GwdColors.inkOf(context))),
                      const SizedBox(height: 2),
                      Text(
                        departments.length == 1
                            ? 'One department'
                            : '${departments.length} departments, ${store.members.length} people',
                        style: GwdType.callout
                            .copyWith(color: GwdColors.inkTertiaryOf(context)),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // The club at a glance, before any one department. Everyone sees
            // it — aggregate numbers about a department give away nothing about
            // any individual, and knowing where the club is stretched is
            // exactly the context members usually lack.
            if (store.departmentProgress.isNotEmpty) ...[
              const SizedBox(height: GwdSpace.xxl),
              AppleStaggerItem(
                index: next(),
                child: const SectionHeader(
                  title: 'The club right now',
                  subtitle: 'Given against finished, across every department',
                ),
              ),
              AppleStaggerItem(
                index: next(),
                child: _ClubTotals(rows: store.departmentProgress),
              ),
            ],

            if (mine.isNotEmpty) ...[
              const SizedBox(height: GwdSpace.xxl),
              AppleStaggerItem(
                index: next(),
                child: const SectionHeader(title: 'Yours'),
              ),
              for (final d in mine)
                AppleStaggerItem(
                  index: next(),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: GwdSpace.md),
                    child: _DepartmentTile(
                      department: d,
                      isMine: true,
                      onTap: () => _open(context, d),
                    ),
                  ),
                ),
            ],

            if (others.isNotEmpty) ...[
              const SizedBox(height: GwdSpace.xl),
              AppleStaggerItem(
                index: next(),
                child: SectionHeader(
                  title: mine.isEmpty ? 'The club' : 'Everyone else',
                  subtitle: 'How each part of the club is getting on',
                ),
              ),
              for (final d in others)
                AppleStaggerItem(
                  index: next(),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: GwdSpace.md),
                    child: _DepartmentTile(
                      department: d,
                      isMine: false,
                      onTap: () => _open(context, d),
                    ),
                  ),
                ),
            ],

            if (departments.isEmpty)
              const EmptyState(
                icon: Icons.workspaces_outline,
                title: 'No departments yet',
                message: 'The President sets these up, and everything else hangs off them.',
              ),
          ],
        ),
      ),
    );
  }

  void _open(BuildContext context, Department department) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DepartmentWorkspacePage(departmentId: department.id),
    ));
  }
}

/// Given against finished, for the whole club and then per department.
///
/// Deliberately not a ranking: rows stay in the order they arrive
/// (alphabetical), the copy never compares one department to another, and the
/// only pointed number is work that has been *sent* somewhere and not yet
/// passed on — because that is the one thing on this screen somebody can fix
/// today.
class _ClubTotals extends StatelessWidget {
  const _ClubTotals({required this.rows});
  final List<DepartmentProgress> rows;

  @override
  Widget build(BuildContext context) {
    final assigned = rows.fold(0, (n, r) => n + r.assigned);
    final completed = rows.fold(0, (n, r) => n + r.completed);
    final waiting = rows.fold(0, (n, r) => n + r.awaitingHandout);
    final rate = assigned == 0 ? 0 : ((completed / assigned) * 100).round();

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ProgressArc(
                progress: assigned == 0 ? 0 : completed / assigned,
                size: 68,
                color: GwdColors.primaryRed,
                child: AnimatedCounter(
                  value: rate,
                  suffix: '%',
                  style: GwdType.numeric
                      .copyWith(fontSize: 17, color: GwdColors.inkOf(context)),
                ),
              ),
              const SizedBox(width: GwdSpace.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      assigned == 0
                          ? 'No work handed out yet'
                          : '$completed of $assigned finished',
                      style:
                          GwdType.title3.copyWith(color: GwdColors.inkOf(context)),
                    ),
                    const SizedBox(height: 2),
                    Text('Across ${rows.length} departments',
                        style: GwdType.footnote.copyWith(
                            color: GwdColors.inkTertiaryOf(context))),
                    if (waiting > 0) ...[
                      const SizedBox(height: GwdSpace.sm),
                      GwdChip(
                        label: waiting == 1
                            ? '1 still to be handed out'
                            : '$waiting still to be handed out',
                        color: GwdColors.warning,
                        icon: Icons.inbox_rounded,
                        dense: true,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          if (rows.any((r) => r.assigned > 0)) ...[
            const SizedBox(height: GwdSpace.lg),
            Divider(height: 1, color: GwdColors.hairlineOf(context)),
            const SizedBox(height: GwdSpace.md),
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  children: [
                    SizedBox(
                      width: 108,
                      child: Text(row.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GwdType.footnote
                              .copyWith(color: GwdColors.inkOf(context))),
                    ),
                    const SizedBox(width: GwdSpace.sm),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(GwdRadius.pill),
                        child: TweenAnimationBuilder<double>(
                          duration: AppleDuration.deliberate,
                          curve: AppleCurves.enter,
                          tween: Tween(
                              begin: 0,
                              end: row.assigned == 0
                                  ? 0
                                  : row.completed / row.assigned),
                          builder: (context, value, _) => LinearProgressIndicator(
                            value: value,
                            minHeight: 6,
                            backgroundColor: GwdColors.sunkenOf(context),
                            valueColor: AlwaysStoppedAnimation(
                                GwdColors.inkSecondaryOf(context)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: GwdSpace.md),
                    SizedBox(
                      width: 52,
                      child: Text(
                        row.assigned == 0
                            ? 'none'
                            : '${row.completed}/${row.assigned}',
                        textAlign: TextAlign.right,
                        style: GwdType.footnote.merge(GwdType.numeric).copyWith(
                            color: GwdColors.inkTertiaryOf(context)),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _DepartmentTile extends StatelessWidget {
  const _DepartmentTile({
    required this.department,
    required this.isMine,
    required this.onTap,
  });

  final Department department;
  final bool isMine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.readStore(context);
    final tint = department.tint;
    final lead = store.memberById(department.leadUserId);
    final remaining = department.assigned - department.completed;

    return SurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.all(GwdSpace.lg),
      borderColor: isMine ? tint.withValues(alpha: 0.3) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(GwdRadius.md),
                ),
                child: Text(department.initials,
                    style: GwdType.caption
                        .copyWith(color: tint, fontSize: 13, letterSpacing: 0)),
              ),
              const SizedBox(width: GwdSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(department.name,
                        style: GwdType.title3
                            .copyWith(color: GwdColors.inkOf(context))),
                    const SizedBox(height: 1),
                    Text(
                      [
                        if (lead != null) 'Led by ${lead.firstName}',
                        department.memberCount == 1
                            ? '1 person'
                            : '${department.memberCount} people',
                      ].join('  ·  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GwdType.footnote
                          .copyWith(color: GwdColors.inkTertiaryOf(context)),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  size: 18, color: GwdColors.inkTertiaryOf(context)),
            ],
          ),

          if (department.assigned > 0) ...[
            const SizedBox(height: GwdSpace.lg),
            ClipRRect(
              borderRadius: BorderRadius.circular(GwdRadius.pill),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: department.completionRate / 100),
                duration: AppleDuration.slow,
                curve: AppleCurves.enter,
                builder: (context, value, _) => LinearProgressIndicator(
                  value: value,
                  minHeight: 5,
                  backgroundColor: GwdColors.sunkenOf(context),
                  valueColor: AlwaysStoppedAnimation(tint),
                ),
              ),
            ),
            const SizedBox(height: GwdSpace.sm),
            Text(
              // Encouraging and factual. "72% — 3rd of 5" is a scoreboard
              // nobody asked for; "4 left to go" is something you can act on.
              switch (remaining) {
                0 => 'Everything done. Nice.',
                1 => 'One task left to go',
                _ => '$remaining of ${department.assigned} still to go',
              },
              style: GwdType.footnote.copyWith(
                color: remaining == 0
                    ? GwdColors.success
                    : GwdColors.inkSecondaryOf(context),
              ),
            ),
          ] else ...[
            const SizedBox(height: GwdSpace.md),
            Text('Nothing on their plate right now',
                style: GwdType.footnote
                    .copyWith(color: GwdColors.inkTertiaryOf(context))),
          ],
        ],
      ),
    );
  }
}
