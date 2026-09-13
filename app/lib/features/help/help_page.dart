import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/responsive.dart';
import '../../app/theme/apple_motion.dart';
import '../../app/theme/gwd_theme.dart';
import '../../app/widgets/common.dart';
import '../../core/api/api_client.dart';
import '../../core/models/help_request.dart';
import 'ask_for_help_sheet.dart';

/// Help & collaboration.
///
/// Two verbs and nothing else: "I need help" and "I can help". The club's real
/// failure mode is not that nobody will pitch in — it is that the person stuck
/// on a poster at 11pm has no way to say so without it sounding like a
/// complaint, and the person free on Tuesday has no way to find them.
///
/// So this is a board, not a ticketing system. No priorities, no SLAs, no
/// assignment authority: anybody can offer, anybody can step back, and the
/// person who asked decides when it is sorted.
class HelpPage extends StatefulWidget {
  const HelpPage({super.key, this.embedded = false});

  /// When true the page drops its own header, because it is being shown inside
  /// another screen that already has one.
  final bool embedded;

  @override
  State<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends State<HelpPage> {
  bool _showResolved = false;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.storeOf(context);
    final gutter = Layout.of(context).gutter;

    final all = store.helpRequests;
    final open = all.where((h) => h.isOpen).toList();
    final resolved = all.where((h) => !h.isOpen).toList();
    final visible = _showResolved ? resolved : open;

    var step = 0;
    int next() => step++;

    return Scaffold(
      backgroundColor: GwdColors.canvasOf(context),
      floatingActionButton: PressableScale(
        onTap: () => showAskForHelpSheet(context),
        haptic: HapticStrength.medium,
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: GwdSpace.xl),
          decoration: BoxDecoration(
            color: GwdColors.primaryRed,
            borderRadius: BorderRadius.circular(GwdRadius.lg),
            boxShadow: GwdShadow.accent(GwdColors.primaryRed),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.pan_tool_alt_outlined, size: 17, color: Colors.white),
              const SizedBox(width: GwdSpace.sm),
              Text('I need help',
                  style: GwdType.headline.copyWith(color: Colors.white)),
            ],
          ),
        ),
      ),
      appBar: widget.embedded
          ? null
          : AppBar(title: const Text('Help & collaboration')),
      body: RefreshIndicator(
        color: GwdColors.primaryRed,
        onRefresh: () => store.loadHelp(),
        child: ListView(
          padding: EdgeInsets.fromLTRB(gutter, GwdSpace.lg, gutter, 96),
          children: [
            AppleStaggerItem(
              index: next(),
              child: _Switcher(
                showResolved: _showResolved,
                openCount: open.length,
                resolvedCount: resolved.length,
                onChanged: (value) => setState(() => _showResolved = value),
              ),
            ),
            const SizedBox(height: GwdSpace.lg),

            if (visible.isEmpty)
              AppleStaggerItem(
                index: next(),
                child: _showResolved
                    ? const EmptyState(
                        icon: Icons.check_circle_outline_rounded,
                        title: 'Nothing sorted yet',
                        message: 'Requests move here once the person who asked closes them.',
                      )
                    : EmptyState(
                        icon: Icons.volunteer_activism_outlined,
                        title: 'Nobody needs a hand',
                        message:
                            'When someone gets stuck, their ask lands here and anybody '
                            'in the club can pick it up.',
                        action: SecondaryButton(
                          label: 'Ask for help',
                          icon: Icons.pan_tool_alt_outlined,
                          onPressed: () => showAskForHelpSheet(context),
                        ),
                      ),
              )
            else
              for (final request in visible)
                AppleStaggerItem(
                  index: next(),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: GwdSpace.md),
                    child: HelpCard(request: request),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _Switcher extends StatelessWidget {
  const _Switcher({
    required this.showResolved,
    required this.openCount,
    required this.resolvedCount,
    required this.onChanged,
  });

  final bool showResolved;
  final int openCount;
  final int resolvedCount;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _Segment(
            label: 'Open',
            count: openCount,
            selected: !showResolved,
            onTap: () => onChanged(false),
          ),
        ),
        const SizedBox(width: GwdSpace.sm),
        Expanded(
          child: _Segment(
            label: 'Sorted',
            count: resolvedCount,
            selected: showResolved,
            onTap: () => onChanged(true),
          ),
        ),
      ],
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      pressedScale: 0.97,
      haptic: HapticStrength.selection,
      child: AnimatedContainer(
        duration: AppleDuration.fast,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? GwdColors.inkOf(context) : GwdColors.surfaceOf(context),
          borderRadius: BorderRadius.circular(GwdRadius.md),
          border: Border.all(
            color: selected ? GwdColors.inkOf(context) : GwdColors.hairlineOf(context),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: GwdType.callout.copyWith(
                  color: selected
                      ? GwdColors.canvasOf(context)
                      : GwdColors.inkSecondaryOf(context),
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                )),
            if (count > 0) ...[
              const SizedBox(width: 5),
              Text('$count',
                  style: GwdType.caption.copyWith(
                    fontSize: 10,
                    color: selected
                        ? GwdColors.canvasOf(context).withValues(alpha: 0.7)
                        : GwdColors.inkTertiaryOf(context),
                  )),
            ],
          ],
        ),
      ),
    );
  }
}

/// One ask. Also used on Home, which is why it is public.
class HelpCard extends StatelessWidget {
  const HelpCard({super.key, required this.request, this.compact = false});

  final HelpRequest request;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.readStore(context);
    final messenger = ScaffoldMessenger.of(context);
    final status = request.status;

    return SurfaceCard(
      padding: const EdgeInsets.all(GwdSpace.lg),
      emphasis: status == HelpStatus.open && !request.mine
          ? SurfaceEmphasis.quiet
          : SurfaceEmphasis.quiet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: status.tint.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(GwdRadius.sm),
                ),
                child: Icon(status.icon, size: 16, color: status.tint),
              ),
              const SizedBox(width: GwdSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(request.title,
                        maxLines: compact ? 2 : 3,
                        overflow: TextOverflow.ellipsis,
                        style: GwdType.headline
                            .copyWith(color: GwdColors.inkOf(context))),
                    const SizedBox(height: 2),
                    Text(
                      [
                        request.mine ? 'You asked' : request.createdByName,
                        if (request.departmentName != null) request.departmentName!,
                        request.ageLabel,
                      ].join('  ·  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GwdType.caption.copyWith(
                          fontSize: 9.5,
                          letterSpacing: 0,
                          color: GwdColors.inkTertiaryOf(context)),
                    ),
                  ],
                ),
              ),
            ],
          ),

          if (!compact && request.description.isNotEmpty) ...[
            const SizedBox(height: GwdSpace.md),
            Text(request.description,
                style: GwdType.callout
                    .copyWith(color: GwdColors.inkSecondaryOf(context))),
          ],

          if (request.skills.isNotEmpty || request.eventName != null) ...[
            const SizedBox(height: GwdSpace.md),
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                if (request.eventName != null)
                  GwdChip(
                    label: request.eventName!,
                    color: GwdColors.primaryRed,
                    icon: Icons.event_rounded,
                    dense: true,
                  ),
                for (final skill in request.skills)
                  GwdChip(
                    label: skill,
                    color: GwdColors.inkTertiaryOf(context),
                    dense: true,
                  ),
              ],
            ),
          ],

          if (request.helpers.isNotEmpty) ...[
            const SizedBox(height: GwdSpace.md),
            Row(
              children: [
                const Icon(Icons.handshake_outlined,
                    size: 13, color: GwdColors.success),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    request.helpers.length == 1
                        ? '${request.helpers.first.name.split(' ').first} is on it'
                        : '${request.helpers.length} people are on it',
                    style:
                        GwdType.footnote.copyWith(color: GwdColors.success),
                  ),
                ),
              ],
            ),
            for (final helper in request.helpers.where((h) => h.note.isNotEmpty))
              Padding(
                padding: const EdgeInsets.only(left: 18, top: 2),
                child: Text('“${helper.note}”',
                    style: GwdType.footnote
                        .copyWith(color: GwdColors.inkTertiaryOf(context))),
              ),
          ],

          if (!compact) ...[
            const SizedBox(height: GwdSpace.lg),
            _Actions(
              request: request,
              onOffer: () => _run(
                  messenger, () => store.offerHelp(request.id), 'Thanks — they have been told.'),
              onWithdraw: () => _run(
                  messenger, () => store.withdrawOffer(request.id), 'Stepped back.'),
              onResolve: () => _run(
                  messenger,
                  () => store.setHelpStatus(request.id, HelpStatus.resolved),
                  'Marked sorted.'),
              onDelete: () => _run(
                  messenger, () => store.withdrawHelpRequest(request.id), 'Withdrawn.'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _run(
    ScaffoldMessengerState messenger,
    Future<void> Function() action,
    String success,
  ) async {
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(success)));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.request,
    required this.onOffer,
    required this.onWithdraw,
    required this.onResolve,
    required this.onDelete,
  });

  final HelpRequest request;
  final VoidCallback onOffer;
  final VoidCallback onWithdraw;
  final VoidCallback onResolve;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    if (request.status == HelpStatus.resolved) {
      return Row(
        children: [
          const Icon(Icons.check_circle_rounded, size: 14, color: GwdColors.success),
          const SizedBox(width: 5),
          Text('Sorted',
              style: GwdType.footnote.copyWith(color: GwdColors.success)),
        ],
      );
    }

    // The person who asked closes it — never a helper, and never a Lead tidying
    // the board. Somebody else declaring your problem solved is the fastest way
    // to make people stop asking.
    if (request.mine) {
      return Row(
        children: [
          Expanded(
            child: _Action(
              label: 'Sorted, thanks',
              icon: Icons.check_rounded,
              tint: GwdColors.success,
              onTap: onResolve,
            ),
          ),
          const SizedBox(width: GwdSpace.sm),
          _Action(
            label: 'Withdraw',
            icon: Icons.close_rounded,
            tint: GwdColors.inkTertiaryOf(context),
            onTap: onDelete,
          ),
        ],
      );
    }

    if (request.helping) {
      return Row(
        children: [
          Expanded(
            child: _Action(
              label: 'You are helping — step back',
              icon: Icons.undo_rounded,
              tint: GwdColors.inkTertiaryOf(context),
              onTap: onWithdraw,
            ),
          ),
        ],
      );
    }

    return _Action(
      label: 'I can help',
      icon: Icons.volunteer_activism_rounded,
      tint: GwdColors.primaryRed,
      onTap: onOffer,
      expand: true,
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.label,
    required this.icon,
    required this.tint,
    required this.onTap,
    this.expand = false,
  });

  final String label;
  final IconData icon;
  final Color tint;
  final VoidCallback onTap;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final button = PressableScale(
      onTap: onTap,
      haptic: HapticStrength.medium,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: GwdSpace.md),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(GwdRadius.md),
          border: Border.all(color: tint.withValues(alpha: 0.28)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: tint),
            const SizedBox(width: 6),
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GwdType.callout
                      .copyWith(color: tint, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}
