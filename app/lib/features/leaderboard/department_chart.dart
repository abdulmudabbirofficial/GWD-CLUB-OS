import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../app/theme/apple_motion.dart';
import '../../app/theme/gwd_theme.dart';
import '../../core/models/member.dart';
import '../../core/models/recognition.dart';

/// Who is carrying what, inside one department.
///
/// The list underneath already says the same thing in numbers. A chart adds the
/// one thing a list cannot: the **shape** of the department — whether the work
/// is spread across the team or sitting on two people — which is the question
/// somebody actually opens this page to answer.
///
/// Each bar is one person, split into what they have finished and what is still
/// open. Height is therefore how much they were trusted with, and the filled
/// portion is how much of it landed. Somebody with a tall mostly-empty bar is
/// overloaded, not idle, and that distinction is invisible in a points column.
///
/// Deliberately **not** a ranking: no positions, no medals, no axis of "best".
/// It stays inside one department, where the work is at least alike — the rule
/// the whole recognition feature is built on.
class DepartmentChart extends StatelessWidget {
  const DepartmentChart({
    super.key,
    required this.members,
    required this.tint,
  });

  final List<Member> members;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    // Anybody who has never been given anything has no bar to draw, and a row
    // of zeroes reads as an accusation rather than information.
    final shown = members
        .where((m) => (m.assignedTasks ?? 0) > 0)
        .take(12)
        .toList();

    if (shown.length < 2) return const SizedBox.shrink();

    final tallest = shown
        .map((m) => (m.assignedTasks ?? 0))
        .fold<int>(0, (a, b) => a > b ? a : b);
    // A little headroom, and never a zero axis.
    final maxY = (tallest + 1).toDouble();

    final open = GwdColors.inkTertiaryOf(context).withValues(alpha: 0.22);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _Key(color: tint, label: 'Finished'),
            const SizedBox(width: GwdSpace.md),
            _Key(color: open, label: 'Still open'),
          ],
        ),
        const SizedBox(height: GwdSpace.md),
        SizedBox(
          height: 150,
          child: BarChart(
            BarChartData(
              maxY: maxY,
              minY: 0,
              alignment: BarChartAlignment.spaceAround,
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => GwdColors.inkOf(context),
                  tooltipBorderRadius: BorderRadius.circular(GwdRadius.sm),
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final member = shown[group.x];
                    final done = member.completedTasks ?? 0;
                    final all = member.assignedTasks ?? 0;
                    return BarTooltipItem(
                      '${member.displayName}\n',
                      GwdType.footnote.copyWith(
                        color: GwdColors.surfaceOf(context),
                        fontWeight: FontWeight.w700,
                      ),
                      children: [
                        TextSpan(
                          text: '$done of $all done',
                          style: GwdType.caption.copyWith(
                            color: GwdColors.surfaceOf(context).withValues(alpha: 0.8),
                            letterSpacing: 0,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: GwdColors.hairlineOf(context),
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 26,
                    // Whole tasks only — half a task is not a thing.
                    interval: maxY <= 5 ? 1 : (maxY / 4).ceilToDouble(),
                    getTitlesWidget: (value, meta) => Text(
                      value.toInt().toString(),
                      style: GwdType.caption.copyWith(
                        fontSize: 9,
                        letterSpacing: 0,
                        color: GwdColors.inkTertiaryOf(context),
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 26,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i >= shown.length) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          shown[i].initials,
                          style: GwdType.caption.copyWith(
                            fontSize: 9,
                            letterSpacing: 0,
                            color: GwdColors.inkTertiaryOf(context),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < shown.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: (shown[i].assignedTasks ?? 0).toDouble(),
                        width: 18,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                        // The whole bar is the grey "still open" ground; the
                        // stack item paints the finished portion over it, so
                        // the two always add up to what they were given.
                        color: open,
                        rodStackItems: [
                          BarChartRodStackItem(
                            0,
                            (shown[i].completedTasks ?? 0).toDouble(),
                            tint,
                          ),
                        ],
                      ),
                    ],
                  ),
              ],
            ),
            // fl_chart animates the bars up on first layout; the app's own
            // spring timing keeps it feeling like the rest of the UI rather
            // than like a chart library.
            duration: AppleDuration.deliberate,
            curve: AppleCurves.enter,
          ),
        ),
      ],
    );
  }
}

/// The club in one picture: what each department was given, and how much of it
/// landed.
///
/// Alphabetical, never sorted by completion — sorting a progress panel by how
/// well people are doing turns it into a league table, which is the one thing
/// recognition here is not. The eye can still see which bars are full; it just
/// is not being told which department "wins".
class ClubProgressChart extends StatelessWidget {
  const ClubProgressChart({super.key, required this.departments});

  final List<DepartmentProgress> departments;

  @override
  Widget build(BuildContext context) {
    final shown = departments.where((d) => d.assigned > 0).toList();
    if (shown.length < 2) return const SizedBox.shrink();

    final tallest = shown.map((d) => d.assigned).fold<int>(0, (a, b) => a > b ? a : b);
    final maxY = (tallest + 1).toDouble();
    final open = GwdColors.inkTertiaryOf(context).withValues(alpha: 0.22);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const _Key(color: GwdColors.primaryRed, label: 'Finished'),
            const SizedBox(width: GwdSpace.md),
            _Key(color: open, label: 'Still open'),
          ],
        ),
        const SizedBox(height: GwdSpace.md),
        SizedBox(
          height: 160,
          child: BarChart(
            BarChartData(
              maxY: maxY,
              minY: 0,
              alignment: BarChartAlignment.spaceAround,
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => GwdColors.inkOf(context),
                  tooltipBorderRadius: BorderRadius.circular(GwdRadius.sm),
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final d = shown[group.x];
                    return BarTooltipItem(
                      '${d.name}\n',
                      GwdType.footnote.copyWith(
                        color: GwdColors.surfaceOf(context),
                        fontWeight: FontWeight.w700,
                      ),
                      children: [
                        TextSpan(
                          text: '${d.completed} of ${d.assigned} done'
                              '${d.awaitingHandout > 0 ? '\n${d.awaitingHandout} not handed out yet' : ''}',
                          style: GwdType.caption.copyWith(
                            color: GwdColors.surfaceOf(context).withValues(alpha: 0.8),
                            letterSpacing: 0,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) =>
                    FlLine(color: GwdColors.hairlineOf(context), strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 26,
                    interval: maxY <= 5 ? 1 : (maxY / 4).ceilToDouble(),
                    getTitlesWidget: (value, meta) => Text(
                      value.toInt().toString(),
                      style: GwdType.caption.copyWith(
                        fontSize: 9,
                        letterSpacing: 0,
                        color: GwdColors.inkTertiaryOf(context),
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i >= shown.length) return const SizedBox.shrink();
                      // Department names are long; the first word is enough to
                      // find yourself, and the tooltip carries the rest.
                      final short = shown[i].name.split(RegExp(r'[\s&]+')).first;
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          short.length > 9 ? short.substring(0, 8) : short,
                          style: GwdType.caption.copyWith(
                            fontSize: 8.5,
                            letterSpacing: 0,
                            color: GwdColors.inkTertiaryOf(context),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < shown.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: shown[i].assigned.toDouble(),
                        width: 20,
                        borderRadius:
                            const BorderRadius.vertical(top: Radius.circular(4)),
                        color: open,
                        rodStackItems: [
                          BarChartRodStackItem(
                            0,
                            shown[i].completed.toDouble(),
                            GwdColors.primaryRed,
                          ),
                        ],
                      ),
                    ],
                  ),
              ],
            ),
            duration: AppleDuration.deliberate,
            curve: AppleCurves.enter,
          ),
        ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: GwdType.caption.copyWith(
            fontSize: 9.5,
            letterSpacing: 0,
            color: GwdColors.inkTertiaryOf(context),
          ),
        ),
      ],
    );
  }
}
