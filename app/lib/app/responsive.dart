import 'package:flutter/widgets.dart';

import 'theme/gwd_theme.dart';

/// Window size classes.
///
/// Named after what they mean for *layout* rather than after devices, because
/// "tablet" is not a size — a phone in landscape and a small tablet in portrait
/// want the same treatment.
enum WindowSize {
  /// Phones, and anything narrow. Bottom navigation, single column.
  compact,

  /// Large phones in landscape, small tablets. Side rail, single wide column.
  medium,

  /// Tablets in landscape, desktop, web. Side rail, two columns.
  expanded;

  static WindowSize of(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 640) return WindowSize.compact;
    if (width < 1080) return WindowSize.medium;
    return WindowSize.expanded;
  }

  bool get isCompact => this == WindowSize.compact;

  /// Wide layouts move navigation to the side: a bottom bar on a tablet wastes
  /// the whole width and puts the controls miles from the user's hands.
  bool get usesRail => this != WindowSize.compact;

  /// Only the widest class earns a second column. Splitting a medium window
  /// produces two cramped columns instead of one comfortable one.
  bool get twoColumn => this == WindowSize.expanded;
}

/// Layout numbers derived from the window, in one place so screens do not each
/// invent their own breakpoints.
class Layout {
  const Layout(this.size, this.width);

  factory Layout.of(BuildContext context) =>
      Layout(WindowSize.of(context), MediaQuery.sizeOf(context).width);

  final WindowSize size;
  final double width;

  bool get isCompact => size.isCompact;
  bool get usesRail => size.usesRail;
  bool get twoColumn => size.twoColumn;

  /// Horizontal page gutter.
  double get gutter => GwdSpace.gutter(width);

  /// Content is capped so text lines stay readable on a wide screen. A
  /// full-width paragraph on a 1400px window is unreadable no matter how nicely
  /// it is set.
  double get maxContentWidth => switch (size) {
        WindowSize.compact => double.infinity,
        WindowSize.medium => 720,
        WindowSize.expanded => 760,
      };

  /// How many cards fit across a grid of tiles.
  int get gridColumns => switch (size) {
        WindowSize.compact => 2,
        WindowSize.medium => 3,
        WindowSize.expanded => 4,
      };
}

/// Centres and caps page content on wide screens, and does nothing on a phone.
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child, this.maxWidth});

  final Widget child;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final cap = maxWidth ?? layout.maxContentWidth;
    if (cap == double.infinity) return child;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: cap),
        child: child,
      ),
    );
  }
}

/// Two columns side by side on an expanded window, stacked otherwise.
///
/// The point is that the *same* screen code serves both: there is no separate
/// tablet build to keep in sync.
class Adaptive2Up extends StatelessWidget {
  const Adaptive2Up({
    super.key,
    required this.primary,
    required this.secondary,
    this.spacing = GwdSpace.xl,
    this.primaryFlex = 3,
    this.secondaryFlex = 2,
  });

  final Widget primary;
  final Widget secondary;
  final double spacing;
  final int primaryFlex;
  final int secondaryFlex;

  @override
  Widget build(BuildContext context) {
    if (!Layout.of(context).twoColumn) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [primary, SizedBox(height: spacing), secondary],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: primaryFlex, child: primary),
        SizedBox(width: spacing),
        Expanded(flex: secondaryFlex, child: secondary),
      ],
    );
  }
}
