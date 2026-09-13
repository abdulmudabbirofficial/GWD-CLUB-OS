import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/responsive.dart';
import '../../app/theme/apple_motion.dart';
import '../../app/theme/gwd_theme.dart';
import '../../app/widgets/common.dart';
import '../alerts/alerts_page.dart';
import '../analytics/analytics_page.dart';
import '../approvals/approvals_page.dart';
import '../departments/departments_page.dart';
import '../directory/directory_page.dart';
import '../help/help_page.dart';
import '../leaderboard/leaderboard_page.dart';
import '../profile/profile_sheet.dart';
import '../schedule/schedule_page.dart';
import 'structure_page.dart';

/// Everything that does not earn a tab of its own.
///
/// Grouped by the question it answers rather than by who built it: what is the
/// club doing, who is in it, and — only for the people entitled to it —
/// oversight. Admin tools stay invisible to everyone who cannot use them, which
/// is why this page looks different depending on who is holding the phone.
class MorePage extends StatelessWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.storeOf(context);
    final session = AppScope.sessionOf(context);
    final caps = store.capabilities;
    final layout = Layout.of(context);
    final me = session.me;

    var step = 0;
    int next() => step++;

    return Scaffold(
      backgroundColor: GwdColors.canvasOf(context),
      body: RefreshIndicator(
        color: GwdColors.primaryRed,
        onRefresh: () => store.loadAll(silent: true),
        child: ListView(
          padding:
              EdgeInsets.fromLTRB(layout.gutter, 0, layout.gutter, GwdSpace.xxxl),
          children: [
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.only(top: GwdSpace.lg),
                child: AppleStaggerItem(
                  index: next(),
                  child: _ProfileHeader(),
                ),
              ),
            ),

            // ---------- what is happening ----------
            const SizedBox(height: GwdSpace.xxl),
            AppleStaggerItem(
              index: next(),
              child: const SectionHeader(title: 'What is happening'),
            ),
            AppleStaggerItem(
              index: next(),
              child: _Tile(
                icon: Icons.calendar_month_rounded,
                tint: GwdColors.primaryRed,
                title: 'Schedule',
                subtitle: 'Meetings, shoots, deadlines — the whole calendar',
                onTap: () => _push(context, const SchedulePage()),
              ),
            ),
            AppleStaggerItem(
              index: next(),
              child: _Tile(
                icon: Icons.campaign_outlined,
                tint: GwdColors.warning,
                title: 'Announcements',
                subtitle: 'Alerts sent to the club',
                badge: store.unreadNotifications,
                onTap: () => _push(context, const AlertsPage()),
              ),
            ),
            AppleStaggerItem(
              index: next(),
              child: _Tile(
                icon: Icons.volunteer_activism_outlined,
                tint: GwdColors.success,
                title: 'Help & collaboration',
                subtitle: 'Who needs a hand, and who is offering',
                badge: store.openHelp.length,
                onTap: () => _push(context, const HelpPage()),
              ),
            ),

            // ---------- people ----------
            const SizedBox(height: GwdSpace.xl),
            AppleStaggerItem(
              index: next(),
              child: const SectionHeader(title: 'People'),
            ),
            AppleStaggerItem(
              index: next(),
              child: _Tile(
                icon: Icons.people_outline_rounded,
                tint: GwdColors.info,
                title: 'Member directory',
                subtitle: 'Everyone in the club, by department',
                onTap: () => _push(context, const DirectoryPage()),
              ),
            ),
            AppleStaggerItem(
              index: next(),
              child: _Tile(
                icon: Icons.account_tree_outlined,
                tint: GwdColors.inkSecondaryOf(context),
                title: 'Club structure',
                subtitle: 'Executive, departments, Leads and members',
                onTap: () => _push(context, const StructurePage()),
              ),
            ),
            if (caps.onLeaderboard || caps.canViewAudit)
              AppleStaggerItem(
                index: next(),
                child: _Tile(
                  icon: Icons.favorite_outline_rounded,
                  tint: GwdColors.rubyDark,
                  // Not "leaderboard". It is still everyone's progress in one
                  // place — it just is not a contest.
                  title: 'Recognition',
                  subtitle: 'Everyone’s progress, and points given by hand',
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

            // ---------- running the club ----------
            if (caps.canManageDepartments || caps.canViewAudit) ...[
              const SizedBox(height: GwdSpace.xl),
              AppleStaggerItem(
                index: next(),
                child: const SectionHeader(
                  title: 'Running the club',
                  subtitle: 'Visible to supervisors and the President',
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
              if (caps.canViewAudit)
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

            // ---------- you ----------
            const SizedBox(height: GwdSpace.xl),
            AppleStaggerItem(
              index: next(),
              child: const SectionHeader(title: 'You'),
            ),
            AppleStaggerItem(
              index: next(),
              child: _Tile(
                icon: Icons.settings_outlined,
                tint: GwdColors.inkTertiaryOf(context),
                title: 'Account & settings',
                subtitle: me?.email ?? 'Server address, sign out',
                onTap: () => showProfileSheet(context),
              ),
            ),

            const SizedBox(height: GwdSpace.xxl),
            AppleStaggerItem(
              index: next(),
              child: Center(
                child: Text(
                  '${session.clubName} · ${store.members.length} members',
                  style: GwdType.caption
                      .copyWith(color: GwdColors.inkTertiaryOf(context)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _push(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
}

class _ProfileHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final session = AppScope.sessionOf(context);
    final store = AppScope.readStore(context);
    final me = session.me;
    if (me == null) return const SizedBox.shrink();

    final department = store.departmentById(me.departmentId);

    return SurfaceCard(
      onTap: () => showProfileSheet(context),
      child: Row(
        children: [
          Avatar(initials: me.initials, tint: me.tint, size: 52),
          const SizedBox(width: GwdSpace.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(me.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GwdType.title2
                        .copyWith(color: GwdColors.inkOf(context))),
                const SizedBox(height: 3),
                Row(
                  children: [
                    RoleBadge(role: me.role, dense: true),
                    if (department != null) ...[
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(department.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GwdType.footnote.copyWith(
                                color: GwdColors.inkTertiaryOf(context))),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded,
              size: 18, color: GwdColors.inkTertiaryOf(context)),
        ],
      ),
    );
  }
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
                      style: GwdType.headline
                          .copyWith(color: GwdColors.inkOf(context))),
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
                    style: GwdType.caption
                        .copyWith(color: Colors.white, fontSize: 9.5)),
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
