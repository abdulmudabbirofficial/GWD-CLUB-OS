import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme/apple_motion.dart';
import '../../app/theme/gwd_theme.dart';
import '../../app/widgets/common.dart';
import '../../core/models/app_notification.dart';
import '../../core/models/club_alert.dart';
import '../../core/models/club_role.dart';
import 'send_alert_sheet.dart';

/// Alerts.
///
/// Two things live here, kept apart because they answer different questions:
///   *For you*  — what needs *your* attention (assignments, approvals, points)
///   *Club*     — what leadership has broadcast to everyone
///
/// Mixing them is how a notification list becomes unreadable: the one message
/// that actually needed you gets buried under announcements.
class AlertsPage extends StatefulWidget {
  const AlertsPage({super.key});

  @override
  State<AlertsPage> createState() => _AlertsPageState();
}

class _AlertsPageState extends State<AlertsPage> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.storeOf(context);
    final gutter = GwdSpace.gutter(MediaQuery.sizeOf(context).width);
    final personal = store.notifications;
    final broadcasts = store.alerts;

    return Scaffold(
      backgroundColor: GwdColors.canvasOf(context),
      floatingActionButton: store.capabilities.canBroadcast
          ? FloatingActionButton.extended(
              onPressed: () => showSendAlertSheet(context),
              backgroundColor: GwdColors.primaryRed,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.campaign_outlined, size: 20),
              label: Text('Send alert',
                  style: GwdType.headline.copyWith(color: Colors.white)),
            )
          : null,
      body: RefreshIndicator(
        color: GwdColors.primaryRed,
        onRefresh: () async {
          await store.loadNotifications();
          await store.loadAlerts();
        },
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(gutter, GwdSpace.lg, gutter, GwdSpace.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text('Alerts',
                                style: GwdType.largeTitle
                                    .copyWith(color: GwdColors.inkOf(context))),
                          ),
                          if (_tab == 0 && store.unreadNotifications > 0)
                            PressableScale(
                              haptic: HapticStrength.light,
                              onTap: store.markAllRead,
                              child: Text('Mark all read',
                                  style: GwdType.footnote
                                      .copyWith(color: GwdColors.primaryRed)),
                            ),
                        ],
                      ),
                      const SizedBox(height: GwdSpace.lg),
                      _Segments(
                        index: _tab,
                        forYou: store.unreadNotifications,
                        club: broadcasts.length,
                        onChanged: (i) => setState(() => _tab = i),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            if (store.loading && !store.hasLoadedOnce)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: gutter),
                  child: const SkeletonList(count: 5, height: 68),
                ),
              )
            else if (_tab == 0)
              ..._personalSlivers(context, gutter, personal, store)
            else
              ..._clubSlivers(context, gutter, broadcasts, store),
          ],
        ),
      ),
    );
  }

  List<Widget> _personalSlivers(
    BuildContext context, double gutter, List<AppNotification> items, store,
  ) {
    if (items.isEmpty) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            icon: Icons.notifications_none_rounded,
            title: 'Nothing for you yet',
            message:
                'Task assignments, approvals and points land here — and as a push '
                'on your phone when the app is closed.',
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 96),
        sliver: SliverList.builder(
          itemCount: items.length,
          itemBuilder: (context, i) => Padding(
            padding: const EdgeInsets.only(bottom: GwdSpace.sm),
            child: AppleStaggerItem(
              index: i,
              child: _NotificationRow(
                key: ValueKey(items[i].id),
                notification: items[i],
                onTap: () => store.markNotificationRead(items[i].id),
              ),
            ),
          ),
        ),
      ),
    ];
  }

  List<Widget> _clubSlivers(
    BuildContext context, double gutter, List<ClubAlert> items, store,
  ) {
    if (items.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            icon: Icons.campaign_outlined,
            title: 'No club alerts',
            message: store.capabilities.canBroadcast
                ? 'Send one and it reaches everyone instantly.'
                : 'Announcements from the leadership team show up here.',
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 96),
        sliver: SliverList.builder(
          itemCount: items.length,
          itemBuilder: (context, i) => Padding(
            padding: const EdgeInsets.only(bottom: GwdSpace.md),
            child: AppleStaggerItem(
              index: i,
              child: _BroadcastCard(key: ValueKey(items[i].id), alert: items[i]),
            ),
          ),
        ),
      ),
    ];
  }
}

class _Segments extends StatelessWidget {
  const _Segments({
    required this.index,
    required this.onChanged,
    required this.forYou,
    required this.club,
  });

  final int index;
  final ValueChanged<int> onChanged;
  final int forYou;
  final int club;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: GwdColors.sunkenOf(context),
        borderRadius: BorderRadius.circular(GwdRadius.md),
      ),
      child: Row(
        children: [
          _seg(context, 0, 'For you', forYou, accent: true),
          _seg(context, 1, 'Club', club),
        ],
      ),
    );
  }

  Widget _seg(BuildContext context, int i, String label, int count, {bool accent = false}) {
    final selected = i == index;
    return Expanded(
      child: PressableScale(
        haptic: HapticStrength.selection,
        pressedScale: 0.98,
        onTap: () => onChanged(i),
        child: AnimatedContainer(
          duration: AppleDuration.standard,
          curve: AppleCurves.standard,
          padding: const EdgeInsets.symmetric(vertical: GwdSpace.sm + 2),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? GwdColors.surfaceOf(context) : Colors.transparent,
            borderRadius: BorderRadius.circular(GwdRadius.sm),
            boxShadow: selected
                ? GwdShadow.resting(Theme.of(context).brightness == Brightness.dark)
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: GwdType.callout.copyWith(
                  color: selected ? GwdColors.inkOf(context) : GwdColors.inkTertiaryOf(context),
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: accent
                        ? GwdColors.primaryRed
                        : GwdColors.inkTertiaryOf(context).withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(GwdRadius.pill),
                  ),
                  child: Text('$count',
                      style: GwdType.caption.copyWith(
                        fontSize: 9,
                        color: accent ? Colors.white : GwdColors.inkSecondaryOf(context),
                      )),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({super.key, required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = !notification.read;

    return SurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.all(GwdSpace.md),
      emphasis: unread && notification.isActionable
          ? SurfaceEmphasis.live
          : SurfaceEmphasis.quiet,
      backgroundColor: unread ? null : GwdColors.canvasOf(context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: notification.tint.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(notification.icon, size: 16, color: notification.tint),
          ),
          const SizedBox(width: GwdSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        notification.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GwdType.headline.copyWith(
                          color: unread
                              ? GwdColors.inkOf(context)
                              : GwdColors.inkSecondaryOf(context),
                        ),
                      ),
                    ),
                    const SizedBox(width: GwdSpace.sm),
                    Text(notification.timeAgo,
                        style: GwdType.caption.copyWith(
                            color: GwdColors.inkTertiaryOf(context), letterSpacing: 0)),
                    if (unread) ...[
                      const SizedBox(width: 6),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                            color: GwdColors.primaryRed, shape: BoxShape.circle),
                      ),
                    ],
                  ],
                ),
                if (notification.body.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    notification.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GwdType.footnote
                        .copyWith(color: GwdColors.inkTertiaryOf(context)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BroadcastCard extends StatelessWidget {
  const _BroadcastCard({super.key, required this.alert});
  final ClubAlert alert;

  @override
  Widget build(BuildContext context) {
    final urgent = alert.urgency == AlertUrgency.urgent;

    return SurfaceCard(
      emphasis: urgent ? SurfaceEmphasis.live : SurfaceEmphasis.quiet,
      accent: alert.urgency.tint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(alert.urgency.icon, size: 15, color: alert.urgency.tint),
              const SizedBox(width: 6),
              if (alert.urgency != AlertUrgency.normal)
                GwdChip(
                    label: alert.urgency.label.toUpperCase(),
                    color: alert.urgency.tint,
                    dense: true),
              const Spacer(),
              Text(alert.timeAgo,
                  style: GwdType.caption
                      .copyWith(color: GwdColors.inkTertiaryOf(context))),
            ],
          ),
          const SizedBox(height: GwdSpace.sm),
          Text(alert.title,
              style: GwdType.title3.copyWith(color: GwdColors.inkOf(context))),
          const SizedBox(height: 4),
          Text(alert.message,
              style: GwdType.body.copyWith(color: GwdColors.inkSecondaryOf(context))),
          const SizedBox(height: GwdSpace.md),
          Row(
            children: [
              // Always signed. An unsigned club-wide alert is how this feature
              // gets abused.
              Text(alert.senderName,
                  style: GwdType.footnote.copyWith(
                      color: GwdColors.inkOf(context), fontWeight: FontWeight.w700)),
              const SizedBox(width: GwdSpace.sm),
              GwdChip(
                  label: alert.senderRole.badge,
                  color: GwdColors.inkTertiaryOf(context),
                  dense: true),
              const Spacer(),
              if (alert.recipientCount > 0)
                Text('${alert.recipientCount} reached',
                    style: GwdType.caption
                        .copyWith(color: GwdColors.inkTertiaryOf(context))),
            ],
          ),
        ],
      ),
    );
  }
}
