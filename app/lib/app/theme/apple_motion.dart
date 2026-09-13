import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

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

class _PressableScaleState extends State<PressableScale>
    with SingleTickerProviderStateMixin {
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

/// Fade + rise + a hair of scale, delayed by [index] so a list of cards lands
/// as a cascade rather than all at once. The delay is capped so long lists do
/// not leave the reader waiting on the last row.
class FluidReveal extends StatefulWidget {
  const FluidReveal({
    super.key,
    required this.child,
    this.index = 0,
    this.stepMs = 46,
    this.maxDelayMs = 420,
    this.offsetY = 16,
    this.scaleFrom = 0.985,
  });

  final Widget child;
  final int index;
  final int stepMs;
  final int maxDelayMs;
  final double offsetY;
  final double scaleFrom;

  @override
  State<FluidReveal> createState() => _FluidRevealState();
}

class _FluidRevealState extends State<FluidReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppleDuration.deliberate,
  );
  late final Animation<double> _eased =
      CurvedAnimation(parent: _controller, curve: AppleCurves.enter);
  bool _scheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_scheduled) return;
    _scheduled = true;

    if (prefersReducedMotion(context)) {
      _controller.value = 1.0;
      return;
    }
    final delayMs =
        (widget.index * widget.stepMs).clamp(0, widget.maxDelayMs).toInt();
    Future<void>.delayed(Duration(milliseconds: delayMs), () {
      if (mounted) _controller.forward();
    });
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
        return Opacity(
          // Fade in faster than the translate so text is readable early.
          opacity: Curves.easeOut.transform(math.min(1.0, t * 1.35)),
          child: Transform.translate(
            offset: Offset(0, widget.offsetY * (1 - t)),
            child: Transform.scale(
              scale: lerpDouble(widget.scaleFrom, 1.0, t),
              child: child,
            ),
          ),
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
    this.baseDelayMs = 46,
    this.offsetY = 16.0,
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

/// Route transition used app-wide: the outgoing page fades and recedes a touch
/// while the incoming page rises. Reads as depth without a hard slide.
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
    if (prefersReducedMotion(context)) {
      return FadeTransition(opacity: animation, child: child);
    }

    final enter = CurvedAnimation(parent: animation, curve: AppleCurves.enter);
    final leave =
        CurvedAnimation(parent: secondaryAnimation, curve: AppleCurves.standard);

    return AnimatedBuilder(
      animation: Listenable.merge([enter, leave]),
      builder: (context, inner) {
        return Opacity(
          opacity: enter.value * (1 - (leave.value * 0.4)),
          child: Transform.translate(
            offset: Offset(0, 24 * (1 - enter.value)),
            child: Transform.scale(
              scale: lerpDouble(0.98, 1.0, enter.value)! -
                  (leave.value * 0.02),
              child: inner,
            ),
          ),
        );
      },
      child: child,
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
          padding: const EdgeInsets.fromLTRB(
              GwdSpace.xl, 0, GwdSpace.md, GwdSpace.md),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: GwdType.title3
                          .copyWith(color: GwdColors.inkOf(context)),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle!,
                        style: GwdType.footnote.copyWith(
                            color: GwdColors.inkSecondaryOf(context)),
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

class _BreathingDotState extends State<BreathingDot>
    with SingleTickerProviderStateMixin {
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

    return AnimatedBuilder(
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
    final track = trackColor ??
        GwdColors.inkTertiaryOf(context).withValues(alpha: 0.18);

    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: progress.clamp(0.0, 1.0)),
        duration: prefersReducedMotion(context)
            ? Duration.zero
            : AppleDuration.deliberate,
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
      canvas.drawArc(
          rect, -math.pi / 2, math.pi * 2 * progress, false, fill);
    }
  }

  @override
  bool shouldRepaint(covariant _ArcPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.trackColor != trackColor;
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
                color: trackColor ??
                    GwdColors.inkTertiaryOf(context).withValues(alpha: 0.16),
              ),
            ),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progress.clamp(0.0, 1.0)),
              duration: prefersReducedMotion(context)
                  ? Duration.zero
                  : AppleDuration.deliberate,
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

/// Gentle ambient float. Kept for the hero constellation and landing page.
class AppleFloat extends StatefulWidget {
  const AppleFloat({
    super.key,
    required this.child,
    this.offsetY = 4.0,
    this.duration = const Duration(milliseconds: 3600),
  });

  final Widget child;
  final double offsetY;
  final Duration duration;

  @override
  State<AppleFloat> createState() => _AppleFloatState();
}

class _AppleFloatState extends State<AppleFloat>
    with SingleTickerProviderStateMixin {
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
        return Transform.translate(
          offset: Offset(0, lerpDouble(-widget.offsetY, widget.offsetY, t)!),
          child: child,
        );
      },
      child: widget.child,
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

class _ApplePulseRingState extends State<ApplePulseRing>
    with SingleTickerProviderStateMixin {
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

/// Waveform meter used on the flagship radar. One shared ticker, no per-bar
/// implicit animations — the previous version rebuilt 34 AnimatedContainers
/// every frame, which is what made the dashboard stutter on mid-range phones.
class AppleDynamicEqualizer extends StatefulWidget {
  const AppleDynamicEqualizer({
    super.key,
    required this.progress,
    this.barCount = 32,
    this.height = 36.0,
    this.color,
  });

  final double progress;
  final int barCount;
  final double height;
  final Color? color;

  @override
  State<AppleDynamicEqualizer> createState() => _AppleDynamicEqualizerState();
}

class _AppleDynamicEqualizerState extends State<AppleDynamicEqualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  @override
  void initState() {
    super.initState();
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? GwdColors.primaryRed;
    final track = GwdColors.inkTertiaryOf(context).withValues(alpha: 0.20);
    final still = prefersReducedMotion(context);

    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _EqualizerPainter(
            phase: still ? 0 : _controller.value * math.pi * 2,
            progress: widget.progress.clamp(0.0, 1.0),
            barCount: widget.barCount,
            color: color,
            trackColor: track,
          ),
        ),
      ),
    );
  }
}

class _EqualizerPainter extends CustomPainter {
  _EqualizerPainter({
    required this.phase,
    required this.progress,
    required this.barCount,
    required this.color,
    required this.trackColor,
  });

  final double phase;
  final double progress;
  final int barCount;
  final Color color;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 3.0;
    final barWidth =
        math.max(2.0, (size.width - (gap * (barCount - 1))) / barCount);
    final activeCount = (progress * barCount).round();
    final paint = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < barCount; i++) {
      final ratio = barCount == 1 ? 0.0 : i / (barCount - 1);
      // Envelope peaks in the middle so the meter reads as a waveform.
      final envelope = (1.0 - (ratio - 0.5).abs() * 1.5).clamp(0.34, 1.0);
      final wave = 0.12 * math.sin(phase + (i * 0.42));
      final h = ((size.height * envelope) + (size.height * wave))
          .clamp(size.height * 0.22, size.height);

      paint.color = i < activeCount ? color : trackColor;
      final x = i * (barWidth + gap);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, size.height - h, barWidth, h),
          Radius.circular(barWidth / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EqualizerPainter old) =>
      old.phase != phase || old.progress != progress || old.color != color;
}
