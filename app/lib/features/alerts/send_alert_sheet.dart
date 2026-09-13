import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_scope.dart';
import '../../app/theme/apple_motion.dart';
import '../../app/theme/gwd_theme.dart';
import '../../app/widgets/common.dart';
import '../../core/models/club_alert.dart';
import '../../core/models/club_role.dart';

Future<void> showSendAlertSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _SendAlertSheet(),
  );
}

/// Compose a club alert.
///
/// This is the one screen in the app that deliberately adds friction: it tells
/// you exactly how many people you are about to interrupt, before you can send.
/// A broadcast that reaches forty phones should not feel like sending a chat
/// message.
class _SendAlertSheet extends StatefulWidget {
  const _SendAlertSheet();

  @override
  State<_SendAlertSheet> createState() => _SendAlertSheetState();
}

class _SendAlertSheetState extends State<_SendAlertSheet> {
  final _title = TextEditingController();
  final _message = TextEditingController();

  AlertAudience _audience = AlertAudience.club;
  AlertUrgency _urgency = AlertUrgency.normal;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _message.dispose();
    super.dispose();
  }

  bool get _canSend =>
      _title.text.trim().length >= 3 && _message.text.trim().length >= 3 && !_busy;

  /// How many people this actually reaches, computed from what we already know
  /// so the number is honest before the send, not after.
  int _reach() {
    final store = AppScope.readStore(context);
    final me = AppScope.readSession(context).me;
    final others = store.members.where((m) => m.id != me?.id);
    return switch (_audience) {
      AlertAudience.club => others.length,
      AlertAudience.department =>
        others.where((m) => m.departmentId == me?.departmentId).length,
      AlertAudience.leadership =>
        others.where((m) => m.role != ClubRole.clubMember).length,
    };
  }

  Future<void> _send() async {
    if (!_canSend) return;
    setState(() { _busy = true; _error = null; });
    try {
      final reach = await AppScope.readStore(context).sendAlert(
        title: _title.text.trim(),
        message: _message.text.trim(),
        audience: _audience,
        urgency: _urgency,
      );
      await HapticFeedback.mediumImpact();
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Alert sent to $reach ${reach == 1 ? 'person' : 'people'}.')),
      );
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = AppScope.sessionOf(context);
    final me = session.me;
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final reach = _reach();

    // Urgent is reserved, so the word keeps meaning something.
    final canUseUrgent =
        (me?.role.isSupervisor ?? false) || me?.role == ClubRole.president;

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, controller) => Container(
        decoration: BoxDecoration(
          color: GwdColors.canvasOf(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(GwdRadius.xxl)),
        ),
        child: Column(
          children: [
            const SheetHeader(
              title: 'Send a club alert',
              subtitle: 'Goes to everyone you choose, immediately',
            ),
            Expanded(
              child: ListView(
                controller: controller,
                padding: EdgeInsets.fromLTRB(
                    GwdSpace.xl, 0, GwdSpace.xl, GwdSpace.xl + inset),
                children: [
                  GwdField(
                    label: 'Subject',
                    controller: _title,
                    hint: 'Venue changed for tonight',
                    autofocus: true,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: GwdSpace.lg),
                  GwdField(
                    label: 'Message',
                    controller: _message,
                    hint: 'Block C instead of the auditorium. Same time.',
                    maxLines: 4,
                  ),

                  const SizedBox(height: GwdSpace.xl),
                  Text('WHO GETS IT',
                      style: GwdType.eyebrow
                          .copyWith(color: GwdColors.inkTertiaryOf(context))),
                  const SizedBox(height: GwdSpace.sm),
                  Row(
                    children: [
                      for (final audience in AlertAudience.values)
                        if (audience != AlertAudience.department || me?.departmentId != null)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(right: GwdSpace.sm),
                              child: _Choice(
                                label: audience.label,
                                selected: audience == _audience,
                                onTap: () => setState(() => _audience = audience),
                              ),
                            ),
                          ),
                    ],
                  ),

                  const SizedBox(height: GwdSpace.xl),
                  Text('URGENCY',
                      style: GwdType.eyebrow
                          .copyWith(color: GwdColors.inkTertiaryOf(context))),
                  const SizedBox(height: GwdSpace.sm),
                  Row(
                    children: [
                      for (final urgency in AlertUrgency.values)
                        if (urgency != AlertUrgency.urgent || canUseUrgent)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(right: GwdSpace.sm),
                              child: _Choice(
                                label: urgency.label,
                                tint: urgency.tint,
                                icon: urgency.icon,
                                selected: urgency == _urgency,
                                onTap: () => setState(() => _urgency = urgency),
                              ),
                            ),
                          ),
                    ],
                  ),

                  const SizedBox(height: GwdSpace.xl),
                  // The friction: say the number out loud before sending.
                  Container(
                    padding: const EdgeInsets.all(GwdSpace.md),
                    decoration: BoxDecoration(
                      color: GwdColors.sunkenOf(context),
                      borderRadius: BorderRadius.circular(GwdRadius.md),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.people_outline_rounded,
                            size: 16, color: GwdColors.inkSecondaryOf(context)),
                        const SizedBox(width: GwdSpace.md),
                        Expanded(
                          child: Text(
                            reach == 0
                                ? 'Nobody in that audience yet.'
                                : 'This will interrupt $reach ${reach == 1 ? 'person' : 'people'} right now.',
                            style: GwdType.footnote
                                .copyWith(color: GwdColors.inkSecondaryOf(context)),
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: GwdSpace.lg),
                    ErrorNote(message: _error!),
                  ],

                  const SizedBox(height: GwdSpace.xl),
                  PrimaryButton(
                    label: 'Send alert',
                    icon: Icons.campaign_rounded,
                    busy: _busy,
                    tone: _urgency.tint == GwdColors.inkSecondary
                        ? GwdColors.primaryRed
                        : _urgency.tint,
                    onPressed: _canSend ? _send : null,
                  ),
                  const SizedBox(height: GwdSpace.md),
                  Center(
                    child: Text(
                      'Sent as ${me?.name ?? 'you'} · ${me?.role.title ?? ''}',
                      style: GwdType.caption
                          .copyWith(color: GwdColors.inkTertiaryOf(context)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.onTap,
    this.tint,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? tint;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final color = tint ?? GwdColors.inkOf(context);
    return PressableScale(
      haptic: HapticStrength.selection,
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppleDuration.fast,
        curve: AppleCurves.standard,
        padding: const EdgeInsets.symmetric(vertical: GwdSpace.md),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? color : GwdColors.surfaceOf(context),
          borderRadius: BorderRadius.circular(GwdRadius.md),
          border: Border.all(color: selected ? color : GwdColors.hairlineOf(context)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon,
                  size: 13,
                  color: selected ? Colors.white : GwdColors.inkSecondaryOf(context)),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GwdType.footnote.copyWith(
                  color: selected ? Colors.white : GwdColors.inkOf(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
