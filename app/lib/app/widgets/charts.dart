import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/apple_motion.dart';
import '../theme/gwd_theme.dart';

/// ---------------------------------------------------------------------------
/// CHARTS
/// ---------------------------------------------------------------------------
///
/// Small, quiet, readable. Every chart here draws itself once on a short reveal
/// and then holds still — nothing pulses, rotates or re-animates on rebuild.
///
/// That restraint is the point. A club dashboard is read in five seconds
/// between lectures, and a figure that is still moving when you look at it is a
/// figure you have to wait for. Motion says "this has just arrived" and nothing
/// else.
///
/// Every chart also states its numbers in words somewhere. A bar whose value
/// you have to estimate against an unlabelled axis is an illustration of data,
/// not a reading of it.

/// One slice of a [DonutChart].
class ChartSlice {
  const ChartSlice({required this.label, required this.value, required this.tint});
  final String label;
  final int value;
  final Color tint;
}

/// A proportion, with the total in the hole and the breakdown beside it.
///
/// Used where the question is "what is this made of" — the split of your work
/// across pending, in progress and done. A donut rather than a pie because the
/// middle is the most valuable space on the shape: it holds the one number
/// everything else is a fraction of.
class DonutChart extends StatelessWidget {
  const DonutChart({
    super.key,
    required this.slices,
    required this.centreValue,
    required this.centreLabel,
    this.size = 116,
    this.thickness = 15,
  });

  final List<ChartSlice> slices;
  final String centreValue;
  final String centreLabel;
  final double size;
  final double thickness;

  @override
  Widget build(BuildContext context) {
    final total = slices.fold<int>(0, (sum, s) => sum + s.value);
    final ink = GwdColors.inkOf(context);

    return Row(
      children: [
        _RevealPaint(
          size: Size(size, size),
          painter: (t) => _DonutPainter(
            slices: slices,
            total: total,
            progress: t,
            thickness: thickness,
            empty: GwdColors.sunkenOf(context),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                centreValue,
                style: GwdType.title2.merge(GwdType.numeric).copyWith(color: ink, height: 1.05),
              ),
              Text(
                centreLabel,
                textAlign: TextAlign.center,
                style: GwdType.micro.copyWith(color: GwdColors.inkTertiaryOf(context)),
              ),
            ],
          ),
        ),
        const SizedBox(width: GwdSpace.xl),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final slice in slices)
                Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: _Key(slice: slice),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.slice});
  final ChartSlice slice;

  @override
  Widget build(BuildContext context) {
    final dim = slice.value == 0;
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: dim ? GwdColors.hairlineOf(context) : slice.tint,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: GwdSpace.sm),
        Expanded(
          child: Text(
            slice.label,
            overflow: TextOverflow.ellipsis,
            style: GwdType.footnote.copyWith(
              color: dim ? GwdColors.inkTertiaryOf(context) : GwdColors.inkSecondaryOf(context),
            ),
          ),
        ),
        const SizedBox(width: GwdSpace.sm),
        Text(
          '${slice.value}',
          style: GwdType.footnote.merge(GwdType.numeric).copyWith(
                color: dim ? GwdColors.inkTertiaryOf(context) : GwdColors.inkOf(context),
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.slices,
    required this.total,
    required this.progress,
    required this.thickness,
    required this.empty,
  });

  final List<ChartSlice> slices;
  final int total;
  final double progress;
  final double thickness;
  final Color empty;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
        thickness / 2, thickness / 2, size.width - thickness, size.height - thickness);
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness
        ..color = empty,
    );

    if (total == 0) return;

    // A hairline of clear space between slices, so two neighbouring colours
    // read as two figures rather than one band that changes hue.
    const gap = 0.035;
    var start = -math.pi / 2;
    for (final slice in slices) {
      if (slice.value == 0) continue;
      final sweep = (slice.value / total) * math.pi * 2;
      canvas.drawArc(
        rect,
        start + gap / 2,
        math.max(0, (sweep - gap) * progress),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = thickness
          ..strokeCap = StrokeCap.butt
          ..color = slice.tint,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.progress != progress || old.total != total || old.slices != slices;
}

/// One labelled bar in a [BarChart].
class ChartBar {
  const ChartBar({
    required this.label,
    required this.value,
    required this.tint,
    this.caption,
    this.onTap,
  });

  final String label;
  final int value;
  final Color tint;

  /// The figure spelled out — "12 of 18 done". Read instead of the bar by
  /// anybody who wants the actual number, which is most people.
  final String? caption;
  final VoidCallback? onTap;
}

/// Horizontal bars, one per row.
///
/// Horizontal rather than vertical because the labels are department names, and
/// vertical bars would either turn them on their side or truncate them to three
/// letters. A chart whose axis nobody can read is a decoration.
///
/// Rows keep the order they are given. Progress surfaces in this app sort
/// alphabetically on purpose — sorting departments by how well they are doing
/// turns a progress panel into a league table.
class BarChart extends StatelessWidget {
  const BarChart({super.key, required this.bars, this.max});

  final List<ChartBar> bars;

  /// The value the full width represents. Defaults to the largest bar, which
  /// makes the rows comparable to each other; pass a fixed ceiling when they
  /// should be comparable to something else.
  final int? max;

  @override
  Widget build(BuildContext context) {
    final ceiling = math.max(1, max ?? bars.fold<int>(1, (m, b) => math.max(m, b.value)));
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < bars.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == bars.length - 1 ? 0 : GwdSpace.lg),
            child: _Bar(bar: bars[i], ceiling: ceiling, index: i),
          ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.bar, required this.ceiling, required this.index});
  final ChartBar bar;
  final int ceiling;
  final int index;

  @override
  Widget build(BuildContext context) {
    final row = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                bar.label,
                overflow: TextOverflow.ellipsis,
                style: GwdType.subhead.copyWith(color: GwdColors.inkOf(context)),
              ),
            ),
            const SizedBox(width: GwdSpace.sm),
            Text(
              bar.caption ?? '${bar.value}',
              style: GwdType.footnote.merge(GwdType.numeric).copyWith(
                    color: GwdColors.inkTertiaryOf(context),
                  ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        _RevealPaint(
          size: const Size(double.infinity, 8),
          delayMs: 40 * index,
          painter: (t) => _BarPainter(
            fraction: (bar.value / ceiling).clamp(0.0, 1.0) * t,
            tint: bar.tint,
            track: GwdColors.sunkenOf(context),
          ),
        ),
      ],
    );

    if (bar.onTap == null) return row;
    return PressableScale(onTap: bar.onTap, pressedScale: 0.99, child: row);
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({required this.fraction, required this.tint, required this.track});
  final double fraction;
  final Color tint;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(size.height / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, radius),
      Paint()..color = track,
    );
    final width = size.width * fraction;
    if (width <= 0.5) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, math.max(width, size.height), size.height),
        radius,
      ),
      Paint()..color = tint,
    );
  }

  @override
  bool shouldRepaint(_BarPainter old) => old.fraction != fraction || old.tint != tint;
}

/// One column of a [ColumnChart].
class ChartColumn {
  const ChartColumn({required this.label, required this.value, this.highlight = false});
  final String label;
  final int value;

  /// Today, in a week of days. Exactly one column should carry it.
  final bool highlight;
}

/// A short run of vertical columns — a week, a term, a handful of buckets.
///
/// Only for series short enough to label every column. The moment an axis needs
/// to skip labels, this is the wrong chart.
class ColumnChart extends StatelessWidget {
  const ColumnChart({
    super.key,
    required this.columns,
    this.height = 96,
    this.tint = GwdColors.primaryRed,
  });

  final List<ChartColumn> columns;
  final double height;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final ceiling = math.max(1, columns.fold<int>(1, (m, c) => math.max(m, c.value)));
    final quiet = GwdColors.inkTertiaryOf(context);

    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < columns.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      columns[i].value == 0 ? '' : '${columns[i].value}',
                      style: GwdType.micro.merge(GwdType.numeric).copyWith(
                            color: columns[i].highlight ? tint : quiet,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Expanded(
                      child: _RevealPaint(
                        size: const Size(double.infinity, double.infinity),
                        delayMs: 30 * i,
                        painter: (t) => _ColumnPainter(
                          fraction: (columns[i].value / ceiling).clamp(0.0, 1.0) * t,
                          tint: columns[i].highlight
                              ? tint
                              : (columns[i].value == 0
                                  ? GwdColors.sunkenOf(context)
                                  : tint.withValues(alpha: 0.34)),
                          empty: columns[i].value == 0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      columns[i].label,
                      style: GwdType.micro.copyWith(
                        color: columns[i].highlight ? GwdColors.inkOf(context) : quiet,
                        fontWeight: columns[i].highlight ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ColumnPainter extends CustomPainter {
  _ColumnPainter({required this.fraction, required this.tint, required this.empty});
  final double fraction;
  final Color tint;
  final bool empty;

  @override
  void paint(Canvas canvas, Size size) {
    // An empty day still gets a mark. A gap in a row of columns reads as
    // missing data; a flat stub reads as nothing happened, which is the truth.
    final h = empty ? 3.0 : math.max(3.0, size.height * fraction);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, size.height - h, size.width, h),
        const Radius.circular(4),
      ),
      Paint()..color = tint,
    );
  }

  @override
  bool shouldRepaint(_ColumnPainter old) => old.fraction != fraction || old.tint != tint;
}

/// Runs a painter from 0 to 1 once, then leaves it alone.
class _RevealPaint extends StatefulWidget {
  const _RevealPaint({
    required this.size,
    required this.painter,
    this.child,
    this.delayMs = 0,
  });

  final Size size;
  final CustomPainter Function(double t) painter;
  final Widget? child;
  final int delayMs;

  @override
  State<_RevealPaint> createState() => _RevealPaintState();
}

class _RevealPaintState extends State<_RevealPaint> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  );
  late final Animation<double> _t = CurvedAnimation(parent: _c, curve: AppleCurves.enter);

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Somebody who has asked the system to stop animating is usually asking
    // because motion makes a screen hard to use, not because they dislike it.
    if (prefersReducedMotion(context)) {
      return CustomPaint(
        size: widget.size,
        painter: widget.painter(1),
        child: widget.child == null ? null : Center(child: widget.child),
      );
    }
    return AnimatedBuilder(
      animation: _t,
      builder: (context, child) => CustomPaint(
        size: widget.size,
        painter: widget.painter(_t.value),
        child: child,
      ),
      child: widget.child == null ? null : Center(child: widget.child),
    );
  }
}
