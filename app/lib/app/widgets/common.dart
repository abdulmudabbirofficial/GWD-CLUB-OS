import 'package:flutter/material.dart';

import '../../core/models/club_role.dart';
import '../theme/apple_motion.dart';
import '../theme/gwd_theme.dart';

/// A person's monogram. Deterministic colour so someone looks the same
/// everywhere in the app.
class Avatar extends StatelessWidget {
  const Avatar({
    super.key,
    required this.initials,
    required this.tint,
    this.size = 40,
    this.selected = false,
    this.heroId,
  });

  final String initials;
  final Color tint;
  final double size;
  final bool selected;

  /// Give the same person's avatar the same [heroId] on a list row and on the
  /// page that row opens, and it flies between the two instead of the row
  /// disappearing and a new circle appearing somewhere else.
  ///
  /// It carries a real meaning, not just polish: the thing that grows into the
  /// header is visibly *the row you touched*, so nobody has to check whose
  /// profile they landed on. Opt-in by id, because a Hero only works when
  /// exactly one widget on each screen claims a tag — two rows for the same
  /// person on one screen would throw.
  final Object? heroId;

  @override
  Widget build(BuildContext context) {
    final circle = _circle(context);
    if (heroId == null) return circle;
    return Hero(
      tag: heroId!,
      // The default flight rebuilds the child against the destination's
      // constraints, which makes a 40pt circle briefly assume the 62pt size
      // and snap. Flying a fixed-size copy keeps the arc smooth.
      flightShuttleBuilder: (context, animation, direction, from, to) {
        final fromSize = (from.widget as Hero).child;
        final toSize = (to.widget as Hero).child;
        return AnimatedBuilder(
          animation: animation,
          builder: (context, _) => direction == HeroFlightDirection.push
              ? (animation.value < 0.5 ? fromSize : toSize)
              : (animation.value < 0.5 ? toSize : fromSize),
        );
      },
      child: circle,
    );
  }

  Widget _circle(BuildContext context) {
    // The monogram is painted in the tint, on a wash of the same tint, so a
    // colour too close to the background is not dull — it is invisible. Avatar
    // colours come from the database and some of them predate the palette that
    // replaced them, so this cannot be left to the palette to get right.
    final ink = GwdColors.readableOn(context, tint);
    return AnimatedContainer(
      duration: AppleDuration.fast,
      curve: AppleCurves.standard,
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: ink.withValues(alpha: 0.12),
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? ink : ink.withValues(alpha: 0.22),
          width: selected ? 2 : 1,
        ),
      ),
      child: Text(
        initials,
        style: GwdType.caption.copyWith(
          color: ink,
          fontSize: size * 0.34,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

/// The quiet role tag from Section 2 — a tag, never a banner.
class RoleBadge extends StatelessWidget {
  const RoleBadge({super.key, required this.role, this.dense = false});

  final ClubRole role;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    // Supervisors get the accent, student leadership the ink treatment,
    // everyone else grey. Three levels of emphasis, not seven colours.
    final color = switch (role) {
      ClubRole.clubDirector || ClubRole.facultyCoordinator => GwdColors.primaryRed,
      ClubRole.president ||
      ClubRole.vicePresident ||
      ClubRole.secretaryGeneral =>
        GwdColors.inkOf(context),
      ClubRole.clubLead => GwdColors.inkSecondaryOf(context),
      ClubRole.clubMember => GwdColors.inkTertiaryOf(context),
    };
    return GwdChip(label: role.badge, color: color, dense: dense);
  }
}

/// A designed empty state. Section 2 is explicit that these should feel as
/// finished as the populated screens, so no bare centred spinner or shrug.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: GwdSpace.xxl,
          vertical: compact ? GwdSpace.xl : GwdSpace.xxxl,
        ),
        child: FluidReveal(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: compact ? 52 : 64,
                height: compact ? 52 : 64,
                decoration: BoxDecoration(
                  color: GwdColors.sunkenOf(context),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: compact ? 24 : 28,
                  color: GwdColors.inkTertiaryOf(context),
                ),
              ),
              SizedBox(height: compact ? GwdSpace.md : GwdSpace.lg),
              Text(
                title,
                textAlign: TextAlign.center,
                style: GwdType.title3.copyWith(color: GwdColors.inkOf(context)),
              ),
              const SizedBox(height: GwdSpace.xs),
              Text(
                message,
                textAlign: TextAlign.center,
                style: GwdType.callout.copyWith(color: GwdColors.inkSecondaryOf(context)),
              ),
              if (action != null) ...[
                const SizedBox(height: GwdSpace.xl),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Skeleton rows that mirror the shape of the content being loaded, so the
/// layout does not jump when real data lands.
class SkeletonList extends StatefulWidget {
  const SkeletonList({super.key, this.count = 4, this.height = 78});
  final int count;
  final double height;

  @override
  State<SkeletonList> createState() => _SkeletonListState();
}

class _SkeletonListState extends State<SkeletonList> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

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
        final t = 0.45 + (_controller.value * 0.35);
        return Column(
          children: [
            for (var i = 0; i < widget.count; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: GwdSpace.md),
                child: Opacity(
                  opacity: t,
                  child: Container(
                    height: widget.height,
                    decoration: BoxDecoration(
                      color: GwdColors.sunkenOf(context),
                      borderRadius: BorderRadius.circular(GwdRadius.xl),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The one primary button in the app. There should rarely be two on a screen —
/// one primary decision per screen is the whole design principle.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.busy = false,
    this.expand = true,
    this.tone,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  final bool expand;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    final color = tone ?? GwdColors.primaryRed;

    final child = AnimatedContainer(
      duration: AppleDuration.fast,
      curve: AppleCurves.standard,
      height: 50,
      padding: EdgeInsets.symmetric(horizontal: expand ? GwdSpace.lg : GwdSpace.xxl),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: enabled ? color : GwdColors.sunkenOf(context),
        borderRadius: BorderRadius.circular(GwdRadius.lg),
        boxShadow: enabled ? GwdShadow.accent(color) : null,
      ),
      child: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon,
                      size: 17, color: enabled ? Colors.white : GwdColors.inkTertiaryOf(context)),
                  const SizedBox(width: GwdSpace.sm),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GwdType.headline.copyWith(
                      color: enabled ? Colors.white : GwdColors.inkTertiaryOf(context),
                    ),
                  ),
                ),
              ],
            ),
    );

    final button = PressableScale(
      onTap: enabled ? onPressed : null,
      haptic: HapticStrength.medium,
      child: child,
    );

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// Quieter secondary action. Progressive disclosure (Section 2) means most
/// actions look like this, not like a primary button.
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.expand = false,
    this.destructive = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? GwdColors.critical : GwdColors.inkOf(context);
    final button = PressableScale(
      onTap: onPressed,
      haptic: HapticStrength.light,
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: GwdSpace.lg),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: GwdColors.surfaceOf(context),
          borderRadius: BorderRadius.circular(GwdRadius.lg),
          border: Border.all(color: GwdColors.hairlineOf(context)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: color),
              const SizedBox(width: GwdSpace.sm),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GwdType.callout.copyWith(color: color, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// A labelled text field matching the surface language.
class GwdField extends StatelessWidget {
  const GwdField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.obscure = false,
    this.keyboardType,
    this.maxLines = 1,
    this.textInputAction,
    this.onSubmitted,
    this.onChanged,
    this.autofocus = false,
    this.enabled = true,
    this.textCapitalization = TextCapitalization.none,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final int maxLines;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  /// Fires on every keystroke.
  ///
  /// Needed wherever a button's enabled state depends on this field: relying on
  /// [onSubmitted] means the button only wakes up once the keyboard's Done key
  /// is pressed, which people reasonably never do. That shipped as a dead
  /// "Save it" button once already.
  final ValueChanged<String>? onChanged;

  final bool autofocus;
  final bool enabled;

  /// Mostly for name fields: a phone keyboard that does not auto-capitalise
  /// makes people type their own name in lower case, and it is then rendered
  /// that way on every board in the club.
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: GwdType.eyebrow.copyWith(color: GwdColors.inkTertiaryOf(context)),
        ),
        const SizedBox(height: GwdSpace.xs + 2),
        TextField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          maxLines: obscure ? 1 : maxLines,
          textInputAction: textInputAction,
          onSubmitted: onSubmitted,
          onChanged: onChanged,
          autofocus: autofocus,
          enabled: enabled,
          textCapitalization: textCapitalization,
          style: GwdType.body.copyWith(color: GwdColors.inkOf(context)),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GwdType.body.copyWith(color: GwdColors.inkTertiaryOf(context)),
            filled: true,
            fillColor: GwdColors.sunkenOf(context),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: GwdSpace.lg,
              vertical: GwdSpace.md + 2,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(GwdRadius.md),
              borderSide: BorderSide(color: GwdColors.hairlineOf(context)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(GwdRadius.md),
              borderSide: BorderSide(color: GwdColors.hairlineOf(context)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(GwdRadius.md),
              borderSide: const BorderSide(color: GwdColors.primaryRed, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

/// Inline error line. Server messages are written to be shown as-is.
class ErrorNote extends StatelessWidget {
  const ErrorNote({super.key, required this.message, this.onRetry, this.retryLabel = 'Try again'});

  final String message;

  /// What to do about it.
  ///
  /// Most of what fails here fails because a laptop on college Wi-Fi went to
  /// sleep or somebody walked out of range, and both of those fix themselves.
  /// Telling somebody their tasks could not be loaded and leaving them holding
  /// a dead screen turns a two-second problem into a reason to close the app.
  final Future<void> Function()? onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    return FluidReveal(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(GwdSpace.md),
        decoration: BoxDecoration(
          color: GwdColors.tintOf(context, GwdColors.critical),
          borderRadius: BorderRadius.circular(GwdRadius.md),
          border: Border.all(color: GwdColors.tintBorderOf(context, GwdColors.critical)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline_rounded, size: 16, color: GwdColors.critical),
            const SizedBox(width: GwdSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    message,
                    style: GwdType.footnote.copyWith(color: GwdColors.rubyDark),
                  ),
                  if (onRetry != null) ...[
                    const SizedBox(height: GwdSpace.sm),
                    _RetryButton(onRetry: onRetry!, label: retryLabel),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The retry itself, which has to say that it is trying.
///
/// A button that does nothing visible for four seconds gets pressed again, and
/// then a third time, and the screen ends up with three requests in flight for
/// something that was only ever going to work once.
class _RetryButton extends StatefulWidget {
  const _RetryButton({required this.onRetry, required this.label});

  final Future<void> Function() onRetry;
  final String label;

  @override
  State<_RetryButton> createState() => _RetryButtonState();
}

class _RetryButtonState extends State<_RetryButton> {
  bool _busy = false;

  Future<void> _run() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onRetry();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: !_busy,
      label: widget.label,
      child: PressableScale(
        onTap: _busy ? null : _run,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_busy)
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.6,
                  color: GwdColors.critical,
                ),
              )
            else
              const Icon(Icons.refresh_rounded, size: 14, color: GwdColors.critical),
            const SizedBox(width: 6),
            Text(
              _busy ? 'Trying…' : widget.label,
              style: GwdType.footnote.copyWith(
                color: GwdColors.critical,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tiny live-connection indicator. Honest about the socket state rather than
/// pretending everything is fine when the connection has dropped.
class LiveDot extends StatelessWidget {
  const LiveDot({super.key, required this.connected});
  final bool connected;

  @override
  Widget build(BuildContext context) {
    if (connected) {
      return Semantics(
        label: 'Live updates connected',
        child: const BreathingDot(color: GwdColors.success, size: 6),
      );
    }
    return Semantics(
      label: 'Reconnecting',
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: GwdColors.warning.withValues(alpha: 0.7),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
