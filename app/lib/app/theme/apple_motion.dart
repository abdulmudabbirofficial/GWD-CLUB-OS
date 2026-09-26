import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import 'gwd_theme.dart';

/// ---------------------------------------------------------------------------
/// GWD MOTION SYSTEM
///
/// Everything that moves in this app moves through here. Three rules:
///
///  1. Motion is *interruptible*. Controllers are driven by spring simulations
///     so a gesture reversed halfway settles from its current velocity instead
///     of snapping back to a keyframe.
///  2. Motion is *cheap*. Entrances are opacity + translate + a hair of scale.
///     No blur animations, no animated shadows, no repainting gradients.
///  3. Motion is *optional*. Every primitive collapses to an instant state
///     change when the platform reports "reduce motion".
/// ---------------------------------------------------------------------------

class AppleCurves {
  const AppleCurves._();

  /// The workhorse. Matches the feel of a UIKit standard animation.
  static const standard = Cubic(0.32, 0.72, 0.0, 1.0);

  /// For elements entering the screen — long, soft tail.
  static const enter = Cubic(0.16, 1.0, 0.3, 1.0);

  /// For elements leaving — quick commitment, no lingering.
  static const exit = Cubic(0.4, 0.0, 1.0, 1.0);

  /// Slight overshoot for affirmative state changes (verify, complete).
  static const overshoot = Cubic(0.34, 1.56, 0.44, 1.0);
}

class AppleDuration {
  const AppleDuration._();
  static const instant = Duration(milliseconds: 110);
  static const fast = Duration(milliseconds: 180);
  static const standard = Duration(milliseconds: 280);
  static const slow = Duration(milliseconds: 420);
  static const deliberate = Duration(milliseconds: 620);
}

/// Spring descriptions tuned by feel, not by formula.
class AppleSprings {
  const AppleSprings._();

  /// Press/release of a control. Critically damped — no visible wobble.
  static const press = SpringDescription(mass: 1, stiffness: 620, damping: 42);

  /// Sheets and large surfaces. A touch of settle at the end.
  static const surface = SpringDescription(mass: 1, stiffness: 340, damping: 34);

  /// Playful elements (celebration, badges). Visible bounce.
  static const lively = SpringDescription(mass: 1, stiffness: 420, damping: 22);
}

/// Reads the platform accessibility setting. When a user has asked for reduced
/// motion we honour it everywhere rather than shipping a second design.
bool prefersReducedMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// ---------------------------------------------------------------------------
/// PRESS
/// ---------------------------------------------------------------------------

/// A tappable wrapper whose scale is driven by a spring simulation. Pressing
/// settles toward [pressedScale]; releasing launches a spring from the current
/// value *and current velocity*, so rapid taps never look mechanical.
///
/// On pointer devices it also lifts very slightly on hover, which is what makes
/// the web build feel native rather than like a phone app in a browser.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = 0.972,
    this.hoverLift = true,
    this.haptic = HapticStrength.selection,
    this.behavior = HitTestBehavior.opaque,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double pressedScale;
  final bool hoverLift;
  final HapticStrength haptic;
  final HitTestBehavior behavior;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

enum HapticStrength { none, selection, light, medium }

class _PressableScaleState extends State<PressableScale> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController.unbounded(
    vsync: this,
    value: 1.0,
  );
  bool _hovered = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _springTo(double target) {
    _controller.animateWith(
      SpringSimulation(
        AppleSprings.press,
        _controller.value,
        target,
        _controller.velocity,
      ),
    );
  }

  void _fireHaptic() {
    switch (widget.haptic) {
      case HapticStrength.none:
        break;
      case HapticStrength.selection:
        HapticFeedback.selectionClick();
      case HapticStrength.light:
        HapticFeedback.lightImpact();
      case HapticStrength.medium:
        HapticFeedback.mediumImpact();
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    if (!enabled) return widget.child;

    if (prefersReducedMotion(context)) {
      return GestureDetector(
        behavior: widget.behavior,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: widget.child,
      );
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        if (widget.hoverLift) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (widget.hoverLift) setState(() => _hovered = false);
      },
      child: GestureDetector(
        behavior: widget.behavior,
        onTapDown: (_) => _springTo(widget.pressedScale),
        onTapUp: (_) {
          _springTo(1.0);
          if (widget.onTap != null) {
            _fireHaptic();
            widget.onTap!();
          }
        },
        onTapCancel: () => _springTo(1.0),
        onLongPress: widget.onLongPress == null
            ? null
            : () {
                HapticFeedback.mediumImpact();
                widget.onLongPress!();
              },
        child: AnimatedScale(
          scale: _hovered ? 1.012 : 1.0,
          duration: AppleDuration.fast,
          curve: AppleCurves.standard,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) => Transform.scale(
              scale: _controller.value,
              child: child,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Legacy name kept so existing screens keep compiling. New code should reach
/// for [PressableScale] directly.
class AppleBouncy extends StatelessWidget {
  const AppleBouncy({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scaleFactor = 0.972,
    this.duration = AppleDuration.fast,
    this.hitTestBehavior = HitTestBehavior.opaque,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scaleFactor;
  final Duration duration;
  final HitTestBehavior hitTestBehavior;

  @override
  Widget build(BuildContext context) => PressableScale(
        onTap: onTap,
        onLongPress: onLongPress,
        pressedScale: scaleFactor,
        behavior: hitTestBehavior,
        child: child,
      );
}

/// ---------------------------------------------------------------------------
/// ENTRANCES
/// ---------------------------------------------------------------------------

/// A row settling into place as its page arrives.
///
/// **Content is visible from the first frame.** This used to fade every row in
/// from nothing, one after another — up to 200ms of cascade and then 420ms each
/// — so opening any screen showed an empty backdrop that filled in row by row,
/// which reads as the app loading, not the app arriving. It was reported
/// exactly that way. Each of those fades was also an `Opacity` between 0 and 1,
/// which makes the engine draw the row off-screen and composite it back, every
/// frame, for every row at once.
///
/// And because lists build rows as they scroll into view, **every row that
/// appeared while scrolling ran the same fade** — the stutter at the bottom of
/// the directory.
///
/// So now: no opacity at all, a short rise measured in pixels, and only while
/// the page it belongs to is arriving. A row that mounts later — scrolled into
/// view, or filled in when data lands — is simply there.
class FluidReveal extends StatefulWidget {
  const FluidReveal({
    super.key,
    required this.child,
    this.index = 0,
    this.stepMs = 22,
    this.maxDelayMs = 90,
    this.offsetY = 10,
    this.scaleFrom = 1.0,
  });

  final Widget child;
  final int index;
  final int stepMs;
  final int maxDelayMs;
  final double offsetY;

  /// Kept for call sites that pass it; the reveal no longer scales, because a
  /// scaled row resamples its text every frame and looks soft while it moves.
  final double scaleFrom;

  @override
  State<FluidReveal> createState() => _FluidRevealState();
}

class _FluidRevealState extends State<FluidReveal> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    value: 1.0,
  );
  late final Animation<double> _eased =
      CurvedAnimation(parent: _controller, curve: AppleCurves.enter);
  bool _decided = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_decided) return;
    _decided = true;
    if (prefersReducedMotion(context)) return;

    // Only while the page is arriving. Anything that mounts once it has
    // arrived is content the person is already looking at, and making it move
    // is making them wait.
    final arriving = ModalRoute.of(context)?.animation?.status == AnimationStatus.forward;
    if (!arriving) return;

    _controller.value = 0.0;
    final delayMs = (widget.index * widget.stepMs).clamp(0, widget.maxDelayMs).toInt();
    if (delayMs == 0) {
      _controller.forward();
    } else {
      Future<void>.delayed(Duration(milliseconds: delayMs), () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _eased,
      builder: (context, child) {
        final t = _eased.value;
        if (t >= 1.0) return child!;
        return Transform.translate(
          offset: Offset(0, widget.offsetY * (1 - t)),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Legacy name, now backed by [FluidReveal].
class AppleStaggerItem extends StatelessWidget {
  const AppleStaggerItem({
    super.key,
    required this.child,
    required this.index,
    this.baseDelayMs = 22,
    this.offsetY = 10.0,
  });

  final Widget child;
  final int index;
  final int baseDelayMs;
  final double offsetY;

  @override
  Widget build(BuildContext context) => FluidReveal(
        index: index,
        stepMs: baseDelayMs,
        offsetY: offsetY,
        child: child,
      );
}

/// ---------------------------------------------------------------------------
/// TRANSITIONS
/// ---------------------------------------------------------------------------

/// Route transition used app-wide: the new page slides over the old one.
///
/// It used to fade the whole incoming page in with an `Opacity` — and every
/// page is transparent, drawn over the app's backdrop — so for the length of
/// the transition you saw the red backdrop through the page, and then its rows
/// faded in on top: "the background shows, then it loads". A full-screen
/// opacity is also the most expensive thing to animate, because the engine
/// redraws the whole page off-screen and blends it back on every frame.
///
/// Now each route paints its own backdrop, so a page arriving covers the one
/// underneath completely, and the only thing animated is position — which the
/// GPU does for free. The page underneath drifts back a third of the way, the
/// way a stack of cards does, and a faint edge on the incoming page keeps the
/// two apart. A full-screen flow (creating an event) rises from the bottom
/// instead, because it is a task you enter, not a page you drill into.
class FluidPageTransitionsBuilder extends PageTransitionsBuilder {
  const FluidPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final page = _OpaquePage(child: child);
    if (prefersReducedMotion(context)) return page;

    final enter = CurvedAnimation(
      parent: animation,
      curve: AppleCurves.enter,
      reverseCurve: AppleCurves.exit,
    );
    final leave = CurvedAnimation(parent: secondaryAnimation, curve: AppleCurves.standard);

    final incoming = SlideTransition(
      position: Tween<Offset>(
        begin: route.fullscreenDialog ? const Offset(0, 1) : const Offset(1, 0),
        end: Offset.zero,
      ).animate(enter),
      child: page,
    );
    return SlideTransition(
      position: Tween<Offset>(begin: Offset.zero, end: const Offset(-0.3, 0)).animate(leave),
      child: incoming,
    );
  }
}

/// A route's page with the app's backdrop under it, so it is opaque.
///
/// The backdrop is two gradients, painted once per page — far cheaper than the
/// alternative of blending a see-through page over the one beneath it.
class _OpaquePage extends StatelessWidget {
  const _OpaquePage({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: GwdColors.backdropBase(isDark),
        // The edge a sliding page catches the light on. One cheap shadow on
        // the page itself, not one per card inside it.
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.55 : 0.12),
            blurRadius: 12,
          ),
        ],
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: GwdColors.backdropBloom(isDark)),
        child: child,
      ),
    );
  }
}

/// Swaps between sibling views (tabs) along a shared axis. Direction is derived
/// from whether the index moved forward or back, so navigation reads spatially.
class FluidTabSwitcher extends StatelessWidget {
  const FluidTabSwitcher({
    super.key,
    required this.index,
    required this.child,
    this.axis = Axis.horizontal,
  });

  final int index;
  final Widget child;
  final Axis axis;

  @override
  Widget build(BuildContext context) {
    if (prefersReducedMotion(context)) {
      return KeyedSubtree(key: ValueKey(index), child: child);
    }

    return AnimatedSwitcher(
      duration: AppleDuration.slow,
      switchInCurve: AppleCurves.enter,
      switchOutCurve: AppleCurves.exit,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.topCenter,
        children: [
          ...previousChildren,
          if (currentChild != null) currentChild,
        ],
      ),
      transitionBuilder: (child, animation) {
        final entering = child.key == ValueKey(index);
        final slide = Tween<Offset>(
          begin: Offset(
            axis == Axis.horizontal ? (entering ? 0.035 : -0.035) : 0,
            axis == Axis.vertical ? (entering ? 0.035 : -0.035) : 0,
          ),
          end: Offset.zero,
        ).animate(animation);

        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: slide, child: child),
        );
      },
      child: KeyedSubtree(key: ValueKey(index), child: child),
    );
  }
}

/// ---------------------------------------------------------------------------
/// SHEETS
/// ---------------------------------------------------------------------------

/// A modal sheet that rises on a spring and can be flung away. Replaces the
/// stock `showModalBottomSheet` curve, which lands flat.
Future<T?> showMorphSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: isScrollControlled,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(
      alpha: Theme.of(context).brightness == Brightness.dark ? 0.62 : 0.34,
    ),
    elevation: 0,
    clipBehavior: Clip.none,
    transitionAnimationController: _sheetController(context),
    builder: builder,
  );
}

/// Open a modal sheet with the app's own keyboard and height behaviour.
///
/// Every sheet in the app goes through here rather than calling
/// `showModalBottomSheet` directly, because the two things that keep going
/// wrong are the two things no individual sheet should be deciding for itself.
///
/// The five `DraggableScrollableSheet` sheets are the deliberate exception and
/// should stay that way. They size themselves as a fraction of the screen and
/// add the keyboard inset as scroll room *inside* their own list, which is the
/// right answer for a sheet you can drag to full height. Wrapping one in this
/// would cap a height it is supposed to control and lift a sheet that has
/// already made room for itself.
Future<T?> showGwdSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isDismissible = true,
  bool enableDrag = true,
  double maxHeightFactor = 0.94,
}) {
  return showModalBottomSheet<T>(
    context: context,
    // Over the whole app, tab bar included. Left to the default, a sheet opens
    // on the tab's own navigator, *under* the bar, and the bar sits across the
    // bottom of it - which is exactly where every sheet keeps its button.
    // Everything a sheet reads (session, store) is scoped above the root, so
    // nothing is lost by opening here.
    useRootNavigator: true,
    isScrollControlled: true,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(
      alpha: Theme.of(context).brightness == Brightness.dark ? 0.62 : 0.34,
    ),
    elevation: 0,
    builder: (context) => SheetShell(
      maxHeightFactor: maxHeightFactor,
      child: Builder(builder: builder),
    ),
  );
}

/// Keeps a sheet clear of the keyboard, and shorter than the screen.
///
/// `showModalBottomSheet` anchors its child to the bottom of the *screen* and
/// hands it the full screen height, keyboard or no keyboard. A sheet that does
/// nothing about that is laid out underneath the keyboard and simply cannot be
/// read — which is exactly what the app shipped: a tap on "Assign task" opened
/// something the user could see one rounded corner of.
///
/// The lift is measured rather than assumed. Subtracting the inset from a
/// constraint that has *already* had it taken out leaves a sheet with no height
/// to draw in, and a sheet with no height is a full-screen black rectangle —
/// the other half of the same bug. So this asks whether the room has been made
/// before making it.
class SheetShell extends StatelessWidget {
  const SheetShell({super.key, required this.child, this.maxHeightFactor = 0.94});

  final Widget child;

  /// How much of the free space the sheet may take. Never all of it: a sliver
  /// of scrim left showing is what tells you this is a sheet you can dismiss
  /// rather than a screen you have been moved to.
  final double maxHeightFactor;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context).height;
    final inset = MediaQuery.viewInsetsOf(context).bottom;

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxHeight.isFinite ? constraints.maxHeight : screen;
        // Room already made upstream? Then do not make it twice.
        final lift = available > screen - inset + 1.0 ? inset : 0.0;
        final room = math.max(160.0, available - lift);

        return Padding(
          padding: EdgeInsets.only(bottom: lift),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: room * maxHeightFactor),
            child: child,
          ),
        );
      },
    );
  }
}

AnimationController? _sheetController(BuildContext context) {
  if (prefersReducedMotion(context)) return null;
  return AnimationController(
    vsync: Navigator.of(context),
    duration: const Duration(milliseconds: 460),
    reverseDuration: const Duration(milliseconds: 280),
  );
}

/// Standard chrome for the top of a modal sheet: grabber, title, close.
class SheetHeader extends StatelessWidget {
  const SheetHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.accent,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Color? accent;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 38,
          height: 4.5,
          margin: const EdgeInsets.only(top: 10, bottom: 14),
          decoration: BoxDecoration(
            color: GwdColors.inkTertiaryOf(context).withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(GwdRadius.pill),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(GwdSpace.xl, 0, GwdSpace.md, GwdSpace.md),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: GwdType.title3.copyWith(color: GwdColors.inkOf(context)),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle!,
                        style: GwdType.footnote.copyWith(color: GwdColors.inkSecondaryOf(context)),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ],
    );
  }
}

/// ---------------------------------------------------------------------------
/// LIVE ELEMENTS
/// ---------------------------------------------------------------------------

/// A number that rolls to its new value instead of cutting. Uses tabular
/// figures so the layout does not shift while digits change.
class AnimatedCounter extends StatelessWidget {
  const AnimatedCounter({
    super.key,
    required this.value,
    this.style,
    this.suffix = '',
    this.prefix = '',
    this.duration = AppleDuration.deliberate,
  });

  final num value;
  final TextStyle? style;
  final String suffix;
  final String prefix;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final resolved = (style ?? GwdType.title2).merge(GwdType.numeric);
    if (prefersReducedMotion(context)) {
      return Text('$prefix${value.round()}$suffix', style: resolved);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: duration,
      curve: AppleCurves.enter,
      builder: (context, v, _) => Text(
        '$prefix${v.round()}$suffix',
        style: resolved,
        maxLines: 1,
      ),
    );
  }
}

/// Slow, shallow breathing used on genuinely live status dots. Deliberately
/// subtle — a heartbeat, not a strobe.
class BreathingDot extends StatefulWidget {
  const BreathingDot({
    super.key,
    required this.color,
    this.size = 7,
    this.active = true,
  });

  final Color color;
  final double size;
  final bool active;

  @override
  State<BreathingDot> createState() => _BreathingDotState();
}

class _BreathingDotState extends State<BreathingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant BreathingDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.active && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active || prefersReducedMotion(context)) {
      return Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      );
    }

    // Its own layer: without the boundary every frame of the breath repainted
    // whatever card it sits in - the event banner, the toast - not just the dot.
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = Curves.easeInOutSine.transform(_controller.value);
          return Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: widget.color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.18 + (t * 0.28)),
                  blurRadius: 4 + (t * 6),
                  spreadRadius: t * 2.2,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// A progress ring that sweeps to its value on a decelerating curve.
class ProgressArc extends StatelessWidget {
  const ProgressArc({
    super.key,
    required this.progress,
    required this.color,
    this.size = 54,
    this.strokeWidth = 5,
    this.trackColor,
    this.child,
  });

  final double progress;
  final Color color;
  final double size;
  final double strokeWidth;
  final Color? trackColor;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final track = trackColor ?? GwdColors.inkTertiaryOf(context).withValues(alpha: 0.18);

    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: progress.clamp(0.0, 1.0)),
        duration: prefersReducedMotion(context) ? Duration.zero : AppleDuration.deliberate,
        curve: AppleCurves.enter,
        builder: (context, value, _) => CustomPaint(
          painter: _ArcPainter(
            progress: value,
            color: color,
            trackColor: track,
            strokeWidth: strokeWidth,
          ),
          child: child == null ? null : Center(child: child),
        ),
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  _ArcPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
    required this.strokeWidth,
  });

  final double progress;
  final Color color;
  final Color trackColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset(strokeWidth / 2, strokeWidth / 2) &
        Size(size.width - strokeWidth, size.height - strokeWidth);

    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, -math.pi / 2, math.pi * 2, false, track);
    if (progress > 0) {
      canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * progress, false, fill);
    }
  }

  @override
  bool shouldRepaint(covariant _ArcPainter old) =>
      old.progress != progress || old.color != color || old.trackColor != trackColor;
}

/// A thin horizontal meter that fills on a decelerating curve.
class FluidMeter extends StatelessWidget {
  const FluidMeter({
    super.key,
    required this.progress,
    required this.color,
    this.height = 6,
    this.trackColor,
  });

  final double progress;
  final Color color;
  final double height;
  final Color? trackColor;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(
                color: trackColor ?? GwdColors.inkTertiaryOf(context).withValues(alpha: 0.16),
              ),
            ),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progress.clamp(0.0, 1.0)),
              duration: prefersReducedMotion(context) ? Duration.zero : AppleDuration.deliberate,
              curve: AppleCurves.enter,
              builder: (context, value, _) => FractionallySizedBox(
                widthFactor: value,
                alignment: Alignment.centerLeft,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(height),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pulsing ring for a single genuinely-live avatar. Never apply to a list.
class ApplePulseRing extends StatefulWidget {
  const ApplePulseRing({
    super.key,
    required this.child,
    required this.glowColor,
    this.maxBlur = 18.0,
    this.maxSpread = 2.5,
    this.duration = const Duration(milliseconds: 2200),
  });

  final Widget child;
  final Color glowColor;
  final double maxBlur;
  final double maxSpread;
  final Duration duration;

  @override
  State<ApplePulseRing> createState() => _ApplePulseRingState();
}

class _ApplePulseRingState extends State<ApplePulseRing> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: widget.duration);

  @override
  void initState() {
    super.initState();
    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (prefersReducedMotion(context)) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeInOutSine.transform(_controller.value);
        return DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.glowColor.withValues(alpha: 0.10 + (t * 0.26)),
                blurRadius: widget.maxBlur * (0.4 + t * 0.6),
                spreadRadius: widget.maxSpread * t,
              ),
            ],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
