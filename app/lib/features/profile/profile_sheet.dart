import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme/apple_motion.dart';
import '../../app/theme/gwd_theme.dart';
import '../../app/widgets/common.dart';
import '../../core/models/club_role.dart';
import '../../core/services/widget_bridge.dart';
import '../auth/change_password_sheet.dart';
import '../auth/set_name_sheet.dart';

Future<void> showProfileSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _ProfileSheet(),
  );
}

/// You, and your account.
///
/// Deliberately small now. Everything club-wide moved to the Club tab, where
/// people can actually find it — a profile sheet is the last place a new member
/// looks for the member directory.
class _ProfileSheet extends StatelessWidget {
  const _ProfileSheet();

  @override
  Widget build(BuildContext context) {
    final session = AppScope.sessionOf(context);
    final store = AppScope.storeOf(context);
    final me = session.me;
    final role = me?.role ?? ClubRole.clubMember;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.35,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, controller) => Container(
        decoration: BoxDecoration(
          color: GwdColors.canvasOf(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(GwdRadius.xxl)),
        ),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(GwdSpace.xl, 0, GwdSpace.xl, GwdSpace.xxl),
          children: [
            const SheetHeader(title: 'You'),

            if (me != null) ...[
              SurfaceCard(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Avatar(initials: me.initials, tint: me.tint, size: 54),
                        const SizedBox(width: GwdSpace.lg),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Name over position, which is the rule
                              // everywhere in the app: the name identifies the
                              // person, the position only qualifies them.
                              Text(
                                me.displayName,
                                style: GwdType.title3.copyWith(
                                  color: me.isUnnamed
                                      ? GwdColors.inkTertiaryOf(context)
                                      : GwdColors.inkOf(context),
                                ),
                              ),
                              const SizedBox(height: 3),
                              // "Marketing Lead", not "Club Lead" — what you
                              // are and where, the way the club says it.
                              Text(me.positionLine(session.department?.name),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GwdType.footnote.copyWith(
                                      color: GwdColors.inkTertiaryOf(context))),
                            ],
                          ),
                        ),
                        if (store.capabilities.earnsPoints)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              AnimatedCounter(
                                value: me.points,
                                style: GwdType.title2
                                    .copyWith(color: GwdColors.inkOf(context)),
                              ),
                              Text('POINTS',
                                  style: GwdType.caption.copyWith(
                                      color: GwdColors.inkTertiaryOf(context),
                                      fontSize: 8.5)),
                            ],
                          ),
                      ],
                    ),
                    Divider(height: GwdSpace.xl, color: GwdColors.hairlineOf(context)),
                    Row(
                      children: [
                        Icon(role.icon, size: 16, color: GwdColors.inkTertiaryOf(context)),
                        const SizedBox(width: GwdSpace.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(role.title,
                                  style: GwdType.headline
                                      .copyWith(color: GwdColors.inkOf(context))),
                              Text(role.remit,
                                  style: GwdType.footnote.copyWith(
                                      color: GwdColors.inkTertiaryOf(context))),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Divider(height: GwdSpace.xl, color: GwdColors.hairlineOf(context)),
                    Row(
                      children: [
                        Icon(Icons.alternate_email_rounded,
                            size: 16, color: GwdColors.inkTertiaryOf(context)),
                        const SizedBox(width: GwdSpace.md),
                        Text('Email',
                            style: GwdType.callout.copyWith(
                                color: GwdColors.inkTertiaryOf(context))),
                        const Spacer(),
                        Flexible(
                          child: Text(me.email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.end,
                              style: GwdType.headline
                                  .copyWith(color: GwdColors.inkOf(context))),
                        ),
                      ],
                    ),
                    if (session.department != null) ...[
                      Divider(height: GwdSpace.xl, color: GwdColors.hairlineOf(context)),
                      Row(
                        children: [
                          Icon(Icons.workspaces_outline,
                              size: 16, color: GwdColors.inkTertiaryOf(context)),
                          const SizedBox(width: GwdSpace.md),
                          Text('Department',
                              style: GwdType.callout.copyWith(
                                  color: GwdColors.inkTertiaryOf(context))),
                          const Spacer(),
                          Text(session.department!.name,
                              style: GwdType.headline
                                  .copyWith(color: GwdColors.inkOf(context))),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],

            const SizedBox(height: GwdSpace.xl),
            _SettingRow(
              icon: Icons.person_outline_rounded,
              label: me?.mustSetName == true ? 'Add your name' : 'Your name and phone',
              // The one setting worth drawing attention to: until it is set,
              // everybody else in the club sees a placeholder where a person
              // should be.
              highlight: me?.mustSetName == true,
              onTap: () => showSetNameSheet(context),
            ),

            const SizedBox(height: GwdSpace.md),
            _SettingRow(
              icon: Icons.lock_outline_rounded,
              label: 'Change password',
              onTap: () => showChangePasswordSheet(context),
            ),

            const SizedBox(height: GwdSpace.md),
            PressableScale(
              onTap: () async {
                // Clear the home-screen widget so a signed-out phone is not
                // left showing the previous member's workload.
                final navigator = Navigator.of(context);
                final sess = AppScope.readSession(context);
                await WidgetBridge.clear();
                navigator.pop();
                await sess.signOut();
              },
              haptic: HapticStrength.light,
              child: Container(
                padding: const EdgeInsets.all(GwdSpace.md),
                decoration: BoxDecoration(
                  color: GwdColors.surfaceOf(context),
                  borderRadius: BorderRadius.circular(GwdRadius.lg),
                  border: Border.all(color: GwdColors.hairlineOf(context)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.logout_rounded, size: 18, color: GwdColors.critical),
                    const SizedBox(width: GwdSpace.md),
                    Text('Sign out',
                        style: GwdType.headline.copyWith(color: GwdColors.critical)),
                  ],
                ),
              ),
            ),

            const SizedBox(height: GwdSpace.xl),
            Center(
              child: Text(
                'GWD Club OS · v4.0.0',
                style: GwdType.caption.copyWith(color: GwdColors.inkTertiaryOf(context)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One tappable settings line.
///
/// [highlight] spends the accent on a row that is genuinely waiting on the
/// user — used only for an unset name, which everybody else in the club can
/// see. The colour rule holds: one thing at a time, or none.
class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final tint = highlight ? GwdColors.primaryRed : GwdColors.inkOf(context);
    return PressableScale(
      onTap: onTap,
      haptic: HapticStrength.light,
      child: Container(
        padding: const EdgeInsets.all(GwdSpace.md),
        decoration: BoxDecoration(
          color: GwdColors.surfaceOf(context),
          borderRadius: BorderRadius.circular(GwdRadius.lg),
          border: Border.all(
            color: highlight ? GwdColors.primaryRed : GwdColors.hairlineOf(context),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: tint),
            const SizedBox(width: GwdSpace.md),
            Expanded(
              child: Text(label, style: GwdType.headline.copyWith(color: tint)),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 18, color: GwdColors.inkTertiaryOf(context)),
          ],
        ),
      ),
    );
  }
}
