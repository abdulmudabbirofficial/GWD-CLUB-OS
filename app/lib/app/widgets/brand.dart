import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/apple_motion.dart';
import '../theme/gwd_theme.dart';

/// ---------------------------------------------------------------------------
/// GWD BRAND
///
/// The logo frames "GWD" between two open corner brackets — a bottom-left and a
/// top-right. That bracket is the strongest thing the mark owns, so it is
/// treated here as a reusable device rather than something that appears once on
/// a splash screen: it frames section headers, marks empty states, and becomes
/// the loading indicator.
///
/// Using a real brand element in place of stock Material chrome is most of what
/// separates an app that looks like *this club's* from one that looks generic.
/// ---------------------------------------------------------------------------

/// The two open corner brackets, drawn rather than bitmapped so they stay crisp
/// at any size and can be animated and themed.
class BracketFrame extends StatelessWidget {
  const BracketFrame({
    super.key,
    required this.child,
    this.color,
    this.thickness = 2,
    this.armLength = 0.34,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    this.progress = 1.0,
  });

  final Widget child;
  final Color? color;
  final double thickness;

  /// Arm length as a fraction of the shorter side.
  final double armLength;
  final EdgeInsets padding;

  /// 0 → brackets absent, 1 → fully drawn. Animatable.
  final double progress;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BracketPainter(
        color: color ?? GwdColors.primaryRed,
        thickness: thickness,
        armLength: armLength,
        progress: progress,
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _BracketPainter extends CustomPainter {
  _BracketPainter({
    required this.color,
    required this.thickness,
    required this.armLength,
    required this.progress,
  });

  final Color color;
  final double thickness;
  final double armLength;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.square
      ..style = PaintingStyle.stroke;

    final arm = math.min(size.width, size.height) * armLength;
    final h = arm * progress;
    final inset = thickness / 2;

    // Bottom-left bracket: up the left edge, then along the bottom.
    final left = Path()
      ..moveTo(inset, size.height - inset - h)
      ..lineTo(inset, size.height - inset)
      ..lineTo(inset + h, size.height - inset);

    // Top-right bracket: mirrored.
    final right = Path()
      ..moveTo(size.width - inset, inset + h)
      ..lineTo(size.width - inset, inset)
      ..lineTo(size.width - inset - h, inset);

    canvas.drawPath(left, paint);
    canvas.drawPath(right, paint);
  }

  @override
  bool shouldRepaint(_BracketPainter old) =>
      old.color != color || old.progress != progress || old.thickness != thickness;
}

/// The full logo lockup.
///
/// The asset has an opaque white background, so on a dark canvas it is seated
/// on its own light plate rather than floating as a white rectangle.
class GwdLogo extends StatelessWidget {
  const GwdLogo({super.key, this.size = 96, this.plate = true});

  final double size;
  final bool plate;

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      'assets/images/club_logo_red.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );
    if (!plate) return image;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(size * 0.22),
        boxShadow: GwdShadow.resting(Theme.of(context).brightness == Brightness.dark),
      ),
      clipBehavior: Clip.antiAlias,
      child: image,
    );
  }
}

/// The compact mark — "GWD" inside its brackets. Drawn, so it themes and
/// animates. Used where the full lockup would be too heavy.
class GwdMark extends StatelessWidget {
  const GwdMark({
    super.key,
    this.size = 46,
    this.color,
    this.background,
    this.progress = 1.0,
  });

  final double size;
  final Color? color;
  final Color? background;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? Colors.white;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background ?? GwdColors.primaryRed,
        borderRadius: BorderRadius.circular(size * 0.24),
      ),
      child: BracketFrame(
        color: tint.withValues(alpha: 0.85),
        thickness: math.max(1.2, size * 0.035),
        armLength: 0.42,
        progress: progress,
        padding: EdgeInsets.all(size * 0.16),
        child: FittedBox(
          child: Text(
            'GWD',
            style: GwdType.caption.copyWith(
              color: tint,
              fontSize: size * 0.26,
              letterSpacing: size * 0.006,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

/// The brand loading indicator: the brackets draw themselves in, hold, and
/// repeat. Replaces the stock spinner on any full-screen wait.
class BracketLoader extends StatefulWidget {
  const BracketLoader({super.key, this.size = 56, this.color});

  final double size;
  final Color? color;

  @override
  State<BracketLoader> createState() => _BracketLoaderState();
}

class _BracketLoaderState extends State<BracketLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        // Draw in over the first 55%, hold, then fade the whole thing out.
        final t = _controller.value;
        final draw = Curves.easeOutCubic.transform((t / 0.55).clamp(0.0, 1.0));
        final fade = t < 0.75 ? 1.0 : 1.0 - ((t - 0.75) / 0.25);
        return Opacity(
          opacity: fade.clamp(0.0, 1.0),
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: BracketFrame(
              color: widget.color ?? GwdColors.primaryRed,
              thickness: 2.4,
              armLength: 0.45,
              progress: draw,
              padding: EdgeInsets.zero,
              child: const SizedBox.expand(),
            ),
          ),
        );
      },
    );
  }
}

/// Section header wearing the brand: a short bracket rule before the label.
/// Replaces the plain uppercase eyebrow so even the quiet furniture is ours.
class BrandedSectionHeader extends StatelessWidget {
  const BrandedSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.accent,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final tint = accent ?? GwdColors.primaryRed;
    return Padding(
      padding: const EdgeInsets.only(bottom: GwdSpace.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // A single bracket arm, echoing the mark.
          Container(
            width: 3,
            height: subtitle == null ? 14 : 26,
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: GwdSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title.toUpperCase(),
                  style: GwdType.eyebrow.copyWith(color: GwdColors.inkOf(context)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: GwdType.footnote
                        .copyWith(color: GwdColors.inkTertiaryOf(context)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: GwdSpace.sm),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// Wordmark for headers: "GWD" with the club name beside it.
class GwdWordmark extends StatelessWidget {
  const GwdWordmark({super.key, this.subtitle, this.compact = false});

  final String? subtitle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GwdMark(size: compact ? 34 : 46),
        SizedBox(width: compact ? GwdSpace.sm : GwdSpace.md),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'GWD Club',
              style: (compact ? GwdType.title3 : GwdType.title2)
                  .copyWith(color: GwdColors.inkOf(context)),
            ),
            if (subtitle != null)
              Text(
                subtitle!,
                style: GwdType.footnote
                    .copyWith(color: GwdColors.inkTertiaryOf(context)),
              ),
          ],
        ),
      ],
    );
  }
}

/// An animated entrance for the brand mark — used on the splash and sign-in so
/// the first thing the app does is draw its own logo.
class AnimatedGwdMark extends StatefulWidget {
  const AnimatedGwdMark({super.key, this.size = 72});
  final double size;

  @override
  State<AnimatedGwdMark> createState() => _AnimatedGwdMarkState();
}

class _AnimatedGwdMarkState extends State<AnimatedGwdMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppleDuration.deliberate,
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (prefersReducedMotion(context)) return GwdMark(size: widget.size);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = Curves.easeOutCubic.transform(_controller.value);
        return Transform.scale(
          scale: 0.9 + (0.1 * t),
          child: GwdMark(size: widget.size, progress: t),
        );
      },
    );
  }
}
