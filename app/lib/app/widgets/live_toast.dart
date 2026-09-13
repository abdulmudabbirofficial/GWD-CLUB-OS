import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/state/club_store.dart';
import '../theme/apple_motion.dart';
import '../theme/gwd_theme.dart';

/// The branded live toast (Section 2).
///
/// Not a Material SnackBar: it enters from a consistent edge, auto-dismisses,
/// and — the part v1 got wrong — **stacks** when several arrive close together
/// rather than replacing whatever was already on screen. The one underneath
/// scales back and dims so the newest stays the focal point.
class LiveToastHost extends StatefulWidget {
  const LiveToastHost({
    super.key,
    required this.store,
    required this.child,
    this.onOpenTask,
  });

  final ClubStore store;
  final Widget child;
  final void Function(String taskId)? onOpenTask;

  @override
  State<LiveToastHost> createState() => _LiveToastHostState();
}

class _LiveToastHostState extends State<LiveToastHost> {
  final Map<String, Timer> _timers = {};

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_schedule);
  }

  @override
  void dispose() {
    widget.store.removeListener(_schedule);
    for (final timer in _timers.values) {
      timer.cancel();
    }
    super.dispose();
  }

  /// Give each toast its own dismissal timer, so a second arrival never resets
  /// the first one's clock.
  void _schedule() {
    for (final toast in widget.store.toasts) {
      _timers.putIfAbsent(
        toast.id,
        () => Timer(
          toast.critical ? const Duration(seconds: 6) : const Duration(seconds: 4),
          () {
            _timers.remove(toast.id);
            if (mounted) widget.store.dismissToast(toast.id);
          },
        ),
      );
    }
    // Drop timers for toasts already gone (dismissed by hand).
    final live = widget.store.toasts.map((t) => t.id).toSet();
    _timers.removeWhere((id, timer) {
      if (live.contains(id)) return false;
      timer.cancel();
      return true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final toasts = widget.store.toasts;

    return Stack(
      children: [
        widget.child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: GwdSpace.md,
                vertical: GwdSpace.sm,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < toasts.length; i++)
                    _StackedToast(
                      key: ValueKey(toasts[i].id),
                      toast: toasts[i],
                      depth: i,
                      onDismiss: () {
                        _timers.remove(toasts[i].id)?.cancel();
                        widget.store.dismissToast(toasts[i].id);
                      },
                      onOpen: () {
                        final taskId = toasts[i].taskId;
                        _timers.remove(toasts[i].id)?.cancel();
                        widget.store.dismissToast(toasts[i].id);
                        if (taskId != null) widget.onOpenTask?.call(taskId);
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StackedToast extends StatefulWidget {
  const _StackedToast({
    super.key,
    required this.toast,
    required this.depth,
    required this.onDismiss,
    required this.onOpen,
  });

  final LiveToast toast;
  final int depth;
  final VoidCallback onDismiss;
  final VoidCallback onOpen;

  @override
  State<_StackedToast> createState() => _StackedToastState();
}

/// The visual identity for each toast kind lives here, not in the store, so
/// core state stays free of widget types.
IconData _iconFor(ToastKind kind) => switch (kind) {
      ToastKind.taskAssigned => Icons.assignment_outlined,
      ToastKind.taskRequest => Icons.pan_tool_alt_outlined,
      ToastKind.approval => Icons.how_to_reg_outlined,
      ToastKind.alert => Icons.campaign_rounded,
      ToastKind.info => Icons.info_outline_rounded,
    };

Color _tintFor(ToastKind kind) => switch (kind) {
      ToastKind.taskAssigned || ToastKind.taskRequest => GwdColors.primaryRed,
      ToastKind.approval => GwdColors.success,
      // A club-wide broadcast gets the warning tone: it is someone deliberately
      // interrupting everyone, and should not look like routine task traffic.
      ToastKind.alert => GwdColors.warning,
      ToastKind.info => GwdColors.info,
    };

class _StackedToastState extends State<_StackedToast> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppleDuration.slow,
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = _tintFor(widget.toast.kind);
    // Each step back in the stack shrinks and fades a little.
    final depthScale = 1.0 - (widget.depth * 0.04);
    final depthOpacity = 1.0 - (widget.depth * 0.22);

    final entrance = CurvedAnimation(parent: _controller, curve: AppleCurves.enter);

    return AnimatedPadding(
      duration: AppleDuration.standard,
      curve: AppleCurves.standard,
      padding: EdgeInsets.only(top: widget.depth == 0 ? 0 : GwdSpace.sm),
      child: FadeTransition(
        opacity: entrance,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -0.35),
            end: Offset.zero,
          ).animate(entrance),
          child: Opacity(
            opacity: depthOpacity.clamp(0.0, 1.0),
            child: Transform.scale(
              scale: depthScale,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Dismissible(
                    key: ValueKey('dismiss-${widget.toast.id}'),
                    direction: DismissDirection.up,
                    onDismissed: (_) => widget.onDismiss(),
                    child: PressableScale(
                      onTap: widget.onOpen,
                      pressedScale: 0.98,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                        decoration: BoxDecoration(
                          color: GwdColors.obsidian,
                          borderRadius: BorderRadius.circular(GwdRadius.xl),
                          border: Border.all(
                            color: accent.withValues(alpha: 0.45),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.32),
                              blurRadius: 28,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.18),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _iconFor(widget.toast.kind),
                                size: 17,
                                color: accent,
                              ),
                            ),
                            const SizedBox(width: GwdSpace.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          widget.toast.title,
                                          style: GwdType.caption.copyWith(
                                            color: accent,
                                            letterSpacing: 0.5,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (widget.toast.critical) ...[
                                        const SizedBox(width: 6),
                                        BreathingDot(color: accent, size: 5.5),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    widget.toast.body,
                                    style: GwdType.footnote.copyWith(
                                      color: Colors.white.withValues(alpha: 0.92),
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: GwdSpace.sm),
                            PressableScale(
                              onTap: widget.onDismiss,
                              haptic: HapticStrength.none,
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 16,
                                  color: Colors.white.withValues(alpha: 0.55),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
