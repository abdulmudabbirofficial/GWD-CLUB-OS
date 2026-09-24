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
import '../leaderboard/my_overview_page.dart';
import '../meetings/meetings_page.dart';
import '../profile/profile_sheet.dart';
import '../schedule/schedule_page.dart';
import 'structure_page.dart';
import '../../core/plural.dart';
import '../events/event_templates_page.dart';

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
      // Transparent so the shell's wash shows through; see ClubShell.
      backgroundColor: Colors.transparent,
      // Capped on a wide window: rows stretching the full width of a
      // desktop browser or a tablet are unreadable however nicely the
      // type is set.
      body: ContentWidth(
        child: RefreshIndicator(
          color: GwdColors.primaryRed,
          onRefresh: () => store.loadAll(silent: true),
          child: ListView(
            padding: EdgeInsets.fromLTRB(layout.gutter, 0, layout.gutter, GwdSpace.xxxl),
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
                  title: 'Schedule',
                  subtitle: 'Meetings, shoots, deadlines — the whole calendar',
                  onTap: () => _push(context, const SchedulePage()),
                ),
              ),
              AppleStaggerItem(
                index: next(),
                child: _Tile(
                  icon: Icons.groups_2_outlined,
                  title: 'Meetings',
                  // Separate from the Schedule on purpose: a schedule entry is a
                  // date, a meeting has an invitee list and an attendance record,
                  // and every attendance figure in the app comes from here.
                  subtitle: 'Who is expected, and who turned up',
                  badge: store.meetingsAwaitingAttendance,
                  onTap: () => _push(context, const MeetingsPage()),
                ),
              ),
              AppleStaggerItem(
                index: next(),
                child: _Tile(
                  icon: Icons.campaign_outlined,
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
                  title: 'Member directory',
                  subtitle: 'Everyone in the club, by department',
                  onTap: () => _push(context, const DirectoryPage()),
                ),
              ),
              AppleStaggerItem(
                index: next(),
                child: _Tile(
                  icon: Icons.account_tree_outlined,
                  title: 'Club structure',
                  subtitle: 'Executive, departments, Leads and members',
                  onTap: () => _push(context, const StructurePage()),
                ),
              ),
              if (caps.onLeaderboard || caps.hasOversight)
                AppleStaggerItem(
                  index: next(),
                  child: _Tile(
                    icon: Icons.favorite_outline_rounded,
                    // Not "leaderboard". It is still everyone's progress in one
                    // place — it just is not a contest.
                    title: 'Recognition',
                    subtitle: 'Everyone’s progress, and points given by hand',
                    onTap: () => _push(context, const LeaderboardPage()),
                  ),
                ),
              // Only for people who actually give work out. For everyone else
              // the answer is always "nothing", and a tile that is always empty
              // is a tile that teaches people to stop looking.
              if (caps.canAssign)
                AppleStaggerItem(
                  index: next(),
                  child: _Tile(
                    icon: Icons.outbox_outlined,
                    title: 'What I handed out',
                    subtitle: 'How your assigned work is going, without opening each person',
                    onTap: () => _push(context, const MyOverviewPage()),
                  ),
                ),
              if (store.pendingApprovals.isNotEmpty)
                AppleStaggerItem(
                  index: next(),
                  child: _Tile(
                    icon: Icons.how_to_reg_outlined,
                    title: 'Approvals',
                    subtitle: 'People waiting to join',
                    badge: store.pendingApprovals.length,
                    onTap: () => _push(context, const ApprovalsPage()),
                  ),
                ),

              // ---------- running the club ----------
              // Templates sit with "what is happening" rather than under
              // Running the club: everybody can read them, and the member being
              // asked to help run a guest lecture is exactly who benefits from
              // seeing what one involves.
              if (store.eventTemplates.isNotEmpty)
                AppleStaggerItem(
                  index: next(),
                  child: _Tile(
                    icon: Icons.bookmarks_outlined,
                    title: 'Event templates',
                    subtitle: 'The shapes the club runs again',
                    onTap: () => _push(context, const EventTemplatesPage()),
                  ),
                ),

              if (caps.canManageDepartments || caps.canViewDashboard) ...[
                const SizedBox(height: GwdSpace.xl),
                AppleStaggerItem(
                  index: next(),
                  child: const SectionHeader(
                    title: 'Running the club',
                    subtitle: 'For the people who run the club',
                  ),
                ),
                if (caps.canManageDepartments)
                  AppleStaggerItem(
                    index: next(),
                    child: _Tile(
                      icon: Icons.workspaces_outline,
                      title: 'Manage departments',
                      subtitle: 'Create, rename and assign Leads',
                      onTap: () => _push(context, const DepartmentsPage()),
                    ),
                  ),
                if (caps.canViewDashboard)
                  AppleStaggerItem(
                    index: next(),
                    child: _Tile(
                      icon: Icons.insights_outlined,
                      title: 'Dashboard',
                      subtitle: 'The club in numbers, and the full audit log',
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
                    '${session.clubName} · ${countOf(store.members.length, 'member')}',
                    style: GwdType.caption.copyWith(color: GwdColors.inkTertiaryOf(context)),
                  ),
                ),
              ),
            ],
          ),
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
                // displayName, never `me.name`: an account created for somebody
                // who has not signed in yet has a placeholder there.
                // Shrinks rather than cutting the name itself off the end.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(me.displayName,
                      maxLines: 1,
                      style: GwdType.title2.copyWith(
                        color: me.isUnnamed
                            ? GwdColors.inkTertiaryOf(context)
                            : GwdColors.inkOf(context),
                      )),
                ),
                const SizedBox(height: 3),
                // "Creative Lead", as one line. A LEAD badge sitting next to the
                // word "Creative" makes the reader assemble the sentence, and
                // in a club with six departments the bare role says what
                // somebody does without saying what they do it for.
                Text(me.positionLine(department?.name),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GwdType.footnote.copyWith(color: GwdColors.inkTertiaryOf(context))),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, size: 18, color: GwdColors.inkTertiaryOf(context)),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge = 0,
  });

  final IconData icon;
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
            // Quiet, every one of them. Each row used to carry its own colour
            // — red, blue, amber, green, violet down one screen — which is the
            // look of a generated app and spends colour on things that need
            // nothing. The crimson badge is what asks for attention here.
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: GwdColors.sunkenOf(context),
                borderRadius: BorderRadius.circular(GwdRadius.md),
                border: Border.all(color: GwdColors.hairlineOf(context)),
              ),
              child: Icon(icon, size: 18, color: GwdColors.inkSecondaryOf(context)),
            ),
            const SizedBox(width: GwdSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: GwdType.headline.copyWith(color: GwdColors.inkOf(context))),
                  const SizedBox(height: 1),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GwdType.footnote.copyWith(color: GwdColors.inkTertiaryOf(context))),
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
                child: Text('$badge', style: GwdType.micro.copyWith(color: Colors.white)),
              ),
              const SizedBox(width: GwdSpace.sm),
            ],
            Icon(Icons.chevron_right_rounded, size: 18, color: GwdColors.inkTertiaryOf(context)),
          ],
        ),
      ),
    );
  }
}
