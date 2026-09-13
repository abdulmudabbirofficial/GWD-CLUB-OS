import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme/apple_motion.dart';
import '../../app/theme/gwd_theme.dart';
import '../../app/widgets/common.dart';
import '../../core/models/club_role.dart';

/// Section 4.2 — the waiting room.
///
/// The account exists and can sign in, but sees nothing until someone approves
/// it. This screen's job is to be honest about *who* is being waited on, and to
/// notice the moment approval lands without making the user relaunch.
class PendingApprovalPage extends StatefulWidget {
  const PendingApprovalPage({super.key});

  @override
  State<PendingApprovalPage> createState() => _PendingApprovalPageState();
}

class _PendingApprovalPageState extends State<PendingApprovalPage> {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    // The socket is not connected while pending — the server rejects the
    // handshake for unapproved accounts — so a slow poll is the honest way to
    // notice approval. 15s is frequent enough to feel immediate, cheap enough
    // to leave running.
    _poll = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) AppScope.readSession(context).refresh();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = AppScope.sessionOf(context);
    final me = session.me;
    final rejected = me?.approvalStatus == ApprovalStatus.rejected;

    return Scaffold(
      backgroundColor: GwdColors.canvasOf(context),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(GwdSpace.xxl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FluidReveal(
                    child: Container(
                      width: 78,
                      height: 78,
                      decoration: BoxDecoration(
                        color: rejected
                            ? GwdColors.criticalSoft
                            : GwdColors.primaryRed.withValues(alpha: 0.10),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: rejected
                          ? const Icon(Icons.block_outlined,
                              size: 32, color: GwdColors.critical)
                          : ApplePulseRing(
                              glowColor: GwdColors.primaryRed,
                              child: Icon(
                                me?.role.icon ?? Icons.hourglass_empty_rounded,
                                size: 30,
                                color: GwdColors.primaryRed,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: GwdSpace.xl),

                  FluidReveal(
                    index: 1,
                    child: Text(
                      rejected ? 'Request declined' : 'Waiting for approval',
                      textAlign: TextAlign.center,
                      style: GwdType.title1.copyWith(color: GwdColors.inkOf(context)),
                    ),
                  ),
                  const SizedBox(height: GwdSpace.sm),
                  FluidReveal(
                    index: 2,
                    child: Text(
                      rejected
                          ? 'Your request to join was not approved. Speak to your department Lead if you think this is a mistake.'
                          : 'Your request is with ${me?.role.approverLabel ?? 'the club'}. '
                              'You will be let in as soon as it is reviewed — no need to sign in again.',
                      textAlign: TextAlign.center,
                      style: GwdType.body.copyWith(color: GwdColors.inkSecondaryOf(context)),
                    ),
                  ),

                  if (me != null) ...[
                    const SizedBox(height: GwdSpace.xxl),
                    FluidReveal(
                      index: 3,
                      child: SurfaceCard(
                        child: Row(
                          children: [
                            Avatar(initials: me.initials, tint: me.tint, size: 42),
                            const SizedBox(width: GwdSpace.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(me.name,
                                      style: GwdType.headline
                                          .copyWith(color: GwdColors.inkOf(context))),
                                  const SizedBox(height: 2),
                                  Text(me.email,
                                      style: GwdType.footnote.copyWith(
                                          color: GwdColors.inkTertiaryOf(context))),
                                ],
                              ),
                            ),
                            RoleBadge(role: me.role),
                          ],
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: GwdSpace.xxl),
                  if (!rejected)
                    SecondaryButton(
                      label: 'Check again',
                      icon: Icons.refresh_rounded,
                      expand: true,
                      onPressed: () => AppScope.readSession(context).refresh(),
                    ),
                  const SizedBox(height: GwdSpace.md),
                  SecondaryButton(
                    label: 'Sign out',
                    expand: true,
                    destructive: true,
                    onPressed: () => AppScope.readSession(context).signOut(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
