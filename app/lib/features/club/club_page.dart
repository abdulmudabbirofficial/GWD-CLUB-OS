import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme/apple_motion.dart';
import '../../app/theme/gwd_theme.dart';
import '../analytics/analytics_page.dart';
import '../approvals/approvals_page.dart';
import '../departments/departments_page.dart';
import '../directory/directory_page.dart';
import '../leaderboard/leaderboard_page.dart';
import 'structure_page.dart';

/// The Club tab.
///
/// One hub for everything that is *not* your day-to-day work: who is in the
/// club, how it is organised, and — for the people entitled to see it —
/// oversight. Pulling these out of the profile sheet means a member can
/// actually find the directory, while admin tools stay invisible to everyone
/// who cannot use them.
class ClubPage extends StatelessWidget {
  const ClubPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.storeOf(context);
    final session = AppScope.sessionOf(context);
    final caps = store.capabilities;
    final gutter = GwdSpace.gutter(MediaQuery.sizeOf(context).width);

    final departments = store.departments.where((d) => d.active).toList();

    var step = 0;
    int next() => step++;

    return Scaffold(
      backgroundColor: GwdColors.canvasOf(context),
      body: RefreshIndicator(
        color: GwdColors.primaryRed,
        onRefresh: () => store.loadAll(silent: true),
        child: ListView(
          padding: EdgeInsets.fromLTRB(gutter, 0, gutter, GwdSpace.xxxl),
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
                      Text(session.clubName,
                          style: GwdType.largeTitle
                              .copyWith(color: GwdColors.inkOf(context))),
                      const SizedBox(height: 2),
                      Text(
                        '${store.members.length} members · ${departments.length} departments',
                        style: GwdType.callout
                            .copyWith(color: GwdColors.inkTertiaryOf(context)),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ---------- people ----------
            const SizedBox(height: GwdSpace.xxl),
            AppleStaggerItem(index: next(), child: const SectionHeader(title: 'People')),
            AppleStaggerItem(
              index: next(),
              child: _Tile(
                icon: Icons.people_outline_rounded,
                tint: GwdColors.primaryRed,
                title: 'Member directory',
                subtitle: 'Everyone in the club, by department',
                onTap: () => _push(context, const DirectoryPage()),
              ),
            ),
            if (caps.onLeaderboard || caps.canViewAudit)
              AppleStaggerItem(
                index: next(),
                child: _Tile(
                  icon: Icons.leaderboard_outlined,
                  tint: GwdColors.warning,
                  title: 'Leaderboard',
                  subtitle: 'One point per completed task',
                  onTap: () => _push(context, const LeaderboardPage()),
                ),
              ),
            if (store.pendingApprovals.isNotEmpty)
              AppleStaggerItem(
                index: next(),
                child: _Tile(
                  icon: Icons.how_to_reg_outlined,
                  tint: GwdColors.success,
                  title: 'Approvals',
                  subtitle: 'People waiting to join',
                  badge: store.pendingApprovals.length,
                  onTap: () => _push(context, const ApprovalsPage()),
                ),
              ),

            // ---------- structure ----------
            const SizedBox(height: GwdSpace.xl),
            AppleStaggerItem(
              index: next(),
              child: const SectionHeader(
                  title: 'Structure', subtitle: 'How the club is organised'),
            ),
            AppleStaggerItem(
              index: next(),
              child: _Tile(
                icon: Icons.account_tree_outlined,
                tint: GwdColors.primaryRed,
                title: 'Club structure',
                subtitle: 'Executive, departments, Leads and members',
                onTap: () => _push(context, const StructurePage()),
              ),
            ),
            if (caps.canManageDepartments)
              AppleStaggerItem(
                index: next(),
                child: _Tile(
                  icon: Icons.workspaces_outline,
                  tint: GwdColors.info,
                  title: 'Manage departments',
                  subtitle: 'Create, rename and assign Leads',
                  onTap: () => _push(context, const DepartmentsPage()),
                ),
              ),

            // ---------- oversight ----------
            if (caps.canViewAudit) ...[
              const SizedBox(height: GwdSpace.xl),
              AppleStaggerItem(
                index: next(),
                child: const SectionHeader(
                    title: 'Oversight', subtitle: 'Visible to supervisors and the President'),
              ),
              AppleStaggerItem(
                index: next(),
                child: _Tile(
                  icon: Icons.insights_outlined,
                  tint: GwdColors.rubyDark,
                  title: 'Analytics & activity',
                  subtitle: 'Completion by department, and the full audit log',
                  onTap: () => _push(context, const AnalyticsPage()),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _push(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.tint,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge = 0,
  });

  final IconData icon;
  final Color tint;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: GwdSpace.sm),
      child: SurfaceCard(
        onTap: onTap,
        padding: const EdgeInsets.all(GwdSpace.md),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(GwdRadius.md),
              ),
              child: Icon(icon, size: 18, color: tint),
            ),
            const SizedBox(width: GwdSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      style: GwdType.headline.copyWith(color: GwdColors.inkOf(context))),
                  const SizedBox(height: 1),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GwdType.footnote
                          .copyWith(color: GwdColors.inkTertiaryOf(context))),
                ],
              ),
            ),
            if (badge > 0) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: GwdColors.primaryRed,
                  borderRadius: BorderRadius.circular(GwdRadius.pill),
                ),
                child: Text('$badge',
                    style: GwdType.caption.copyWith(color: Colors.white, fontSize: 9.5)),
              ),
              const SizedBox(width: GwdSpace.sm),
            ],
            Icon(Icons.chevron_right_rounded,
                size: 18, color: GwdColors.inkTertiaryOf(context)),
          ],
        ),
      ),
    );
  }
}
