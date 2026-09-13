import 'package:flutter/material.dart';

import '../../app/theme/apple_motion.dart';
import '../../app/theme/gwd_theme.dart';
import '../../core/models/club_task.dart';

/// One task in a list.
///
/// Keyed by task id at the call site, so when a live update arrives the row
/// animates its own change rather than the whole list flashing.
class TaskCard extends StatelessWidget {
  const TaskCard({
    super.key,
    required this.task,
    required this.onTap,
    this.subtitle,
  });

  final ClubTask task;
  final VoidCallback onTap;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final overdue = task.isOverdue;
    final done = task.status == TaskStatus.completed;

    return SurfaceCard(
      onTap: onTap,
      emphasis: overdue ? SurfaceEmphasis.live : SurfaceEmphasis.quiet,
      accent: overdue ? GwdColors.critical : null,
      padding: const EdgeInsets.all(GwdSpace.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The status mark animates between states rather than swapping.
          AnimatedContainer(
            duration: AppleDuration.standard,
            curve: AppleCurves.overshoot,
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: task.status.tint.withValues(alpha: done ? 1 : 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              task.status.icon,
              size: 17,
              color: done ? Colors.white : task.status.tint,
            ),
          ),
          const SizedBox(width: GwdSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedDefaultTextStyle(
                  duration: AppleDuration.standard,
                  style: GwdType.headline.copyWith(
                    color: done
                        ? GwdColors.inkTertiaryOf(context)
                        : GwdColors.inkOf(context),
                    decoration: done ? TextDecoration.lineThrough : TextDecoration.none,
                    decorationColor: GwdColors.inkTertiaryOf(context),
                  ),
                  child: Text(task.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    if (subtitle != null)
                      Flexible(
                        child: Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GwdType.footnote
                              .copyWith(color: GwdColors.inkTertiaryOf(context)),
                        ),
                      ),
                    if (subtitle != null && task.dueLabel != null) ...[
                      const SizedBox(width: GwdSpace.sm),
                      Container(
                        width: 3,
                        height: 3,
                        decoration: BoxDecoration(
                          color: GwdColors.inkTertiaryOf(context),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: GwdSpace.sm),
                    ],
                    if (task.dueLabel != null)
                      Text(
                        task.dueLabel!,
                        style: GwdType.footnote.copyWith(
                          color: overdue
                              ? GwdColors.critical
                              : GwdColors.inkTertiaryOf(context),
                          fontWeight: overdue ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (task.priority == TaskPriority.high && !done) ...[
            const SizedBox(width: GwdSpace.sm),
            const Icon(Icons.keyboard_double_arrow_up_rounded,
                size: 16, color: GwdColors.warning),
          ],
        ],
      ),
    );
  }
}
