import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/responsive.dart';
import '../../app/theme/apple_motion.dart';
import '../../app/theme/gwd_theme.dart';
import '../../app/widgets/charts.dart';
import '../../app/widgets/common.dart';
import 'audit_language.dart';

/// The club dashboard, for Directors, the Faculty Coordinator and the President.
///
/// Four questions, in the order somebody running a club actually asks them:
/// how big is the club, what state is its work in, is it speeding up or slowing
/// down, and which departments are carrying it. Then the activity log, for the
/// times the answer to one of those is "why?".
///
/// Deliberately not a BI dashboard. Every chart here answers a question that was
/// already being asked out loud in meetings; none of them exist because the
/// space looked empty. That restraint is the same one the rest of the app runs
/// on — one focal point per screen, depth by drilling down — and it is why this
/// screen lives behind More rather than adding weight to a tab.
class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  List<Map<String, dynamic>> _departments = const [];
  List<Map<String, dynamic>> _audit = const [];
  List<Map<String, dynamic>> _completions = const [];
  Map<String, dynamic> _status = const {};
  Map<String, dynamic> _totals = const {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = AppScope.readStore(context);
    try {
      final analytics = await store.analytics();
      final audit = await store.auditLog();
      if (!mounted) return;
      setState(() {
        _departments = _rows(analytics['departments']);
        _completions = _rows(analytics['completions']);
        _status = (analytics['status'] as Map?)?.cast<String, dynamic>() ?? const {};
        _totals = (analytics['totals'] as Map?)?.cast<String, dynamic>() ?? const {};
        _audit = _rows(audit['entries']);
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
          _loading = false;
        });
      }
    }
  }

  static List<Map<String, dynamic>> _rows(Object? value) => ((value as List?) ?? [])
      .whereType<Map>()
      .map((e) => e.cast<String, dynamic>())
      .toList();

  int _count(Map<String, dynamic> from, String key) => (from[key] as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    final gutter = GwdSpace.gutter(MediaQuery.sizeOf(context).width);

    final pending = _count(_status, 'pending');
    final inProgress = _count(_status, 'inProgress');
    final review = _count(_status, 'review');
    final blocked = _count(_status, 'blocked');
    final completed = _count(_status, 'completed');
    final open = pending + inProgress + review + blocked;

    // The fortnight arrives oldest first, so the last seven entries are this
    // week and the seven before them are the week to compare it against.
    final week = _completions.length >= 7
        ? _completions.sublist(_completions.length - 7)
        : _completions;
    final previous = _completions.length >= 14
        ? _completions.sublist(_completions.length - 14, _completions.length - 7)
        : const <Map<String, dynamic>>[];
    final thisWeek = week.fold<int>(0, (sum, d) => sum + _count(d, 'count'));
    final lastWeek = previous.fold<int>(0, (sum, d) => sum + _count(d, 'count'));

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text('Dashboard', style: GwdType.title3.copyWith(color: GwdColors.inkOf(context))),
      ),
      // Capped on a wide window: rows stretching the full width of a
      // desktop browser or a tablet are unreadable however nicely the
      // type is set.
      body: ContentWidth(
        child: RefreshIndicator(
          color: GwdColors.primaryRed,
          onRefresh: _load,
          child: _loading
              ? Padding(
                  padding: EdgeInsets.symmetric(horizontal: gutter),
                  child: const SkeletonList(count: 4, height: 64),
                )
              : ListView(
                  padding: EdgeInsets.fromLTRB(gutter, GwdSpace.lg, gutter, GwdSpace.xxxl),
                  children: [
                    if (_error != null) ...[
                      ErrorNote(message: _error!, onRetry: _load),
                      const SizedBox(height: GwdSpace.lg),
                    ],

                    // ---------- how big is the club ----------
                    Row(
                      children: [
                        Expanded(
                          child: _Tile(
                            value: _count(_totals, 'people'),
                            label: 'people',
                          ),
                        ),
                        const SizedBox(width: GwdSpace.sm),
                        Expanded(
                          child: _Tile(
                            value: _count(_totals, 'departments'),
                            label: 'departments',
                          ),
                        ),
                        const SizedBox(width: GwdSpace.sm),
                        Expanded(
                          child: _Tile(
                            value: _count(_totals, 'openEvents'),
                            label: 'events on',
                          ),
                        ),
                        const SizedBox(width: GwdSpace.sm),
                        Expanded(
                          child: _Tile(
                            value: _count(_totals, 'overdue'),
                            label: 'overdue',
                            // The only figure here anybody has to do something
                            // about, so it is the only one that gets a colour.
                            tint: _count(_totals, 'overdue') > 0 ? GwdColors.critical : null,
                          ),
                        ),
                      ],
                    ),

                    // ---------- what state is the work in ----------
                    const SizedBox(height: GwdSpace.xxl),
                    const SectionHeader(
                      title: 'The club\'s work',
                      subtitle: 'Every task in the club, by where it has got to',
                    ),
                    if (open + completed == 0)
                      const EmptyState(
                        compact: true,
                        icon: Icons.donut_large_rounded,
                        title: 'No work yet',
                        message: 'The shape of the club\'s work appears once tasks exist.',
                      )
                    else
                      SurfaceCard(
                        child: DonutChart(
                          centreValue: '$open',
                          centreLabel: 'still open',
                          slices: [
                            ChartSlice(
                                label: 'To do',
                                value: pending,
                                tint: GwdColors.inkTertiaryOf(context)),
                            ChartSlice(
                                label: 'In progress',
                                value: inProgress,
                                tint: GwdColors.primaryRed),
                            ChartSlice(
                                label: 'In review', value: review, tint: GwdColors.info),
                            if (blocked > 0)
                              ChartSlice(
                                  label: 'Blocked', value: blocked, tint: GwdColors.warning),
                            ChartSlice(
                                label: 'Done', value: completed, tint: GwdColors.success),
                          ],
                        ),
                      ),

                    // ---------- is it speeding up or slowing down ----------
                    if (week.isNotEmpty) ...[
                      const SizedBox(height: GwdSpace.xxl),
                      SectionHeader(
                        title: 'Finished this week',
                        subtitle: _pace(thisWeek, lastWeek, previous.isNotEmpty),
                      ),
                      SurfaceCard(
                        child: ColumnChart(columns: [
                          for (var i = 0; i < week.length; i++)
                            ChartColumn(
                              label: _initial(week[i]['day'] as String?),
                              value: _count(week[i], 'count'),
                              highlight: i == week.length - 1,
                            ),
                        ]),
                      ),
                    ],

                    // ---------- who is carrying it ----------
                    const SizedBox(height: GwdSpace.xxl),
                    const SectionHeader(
                      title: 'Completion by department',
                      subtitle: 'Tasks finished against tasks created',
                    ),
                    if (_departments.isEmpty)
                      const EmptyState(
                        compact: true,
                        icon: Icons.bar_chart_rounded,
                        title: 'No data yet',
                        message: 'Numbers appear once tasks start moving.',
                      )
                    else
                      SurfaceCard(
                        child: Column(
                          children: [
                            for (var i = 0; i < _departments.length; i++) ...[
                              if (i > 0)
                                Divider(height: GwdSpace.xl, color: GwdColors.hairlineOf(context)),
                              _DepartmentBar(
                                name: '${_departments[i]['name']}',
                                total: _count(_departments[i], 'total'),
                                completed: _count(_departments[i], 'completed'),
                                rate: _count(_departments[i], 'completionRate'),
                                avgHours: (_departments[i]['avgCompletionHours'] as num?)?.toInt(),
                                scale: _departments.fold<int>(
                                    1, (m, d) => _count(d, 'total') > m ? _count(d, 'total') : m),
                              ),
                            ],
                          ],
                        ),
                      ),

                    // ---------- and why ----------
                    const SizedBox(height: GwdSpace.xxl),
                    const SectionHeader(
                      title: 'Activity log',
                      subtitle: 'Who did what, most recent first',
                    ),
                    if (_audit.isEmpty)
                      const EmptyState(
                        compact: true,
                        icon: Icons.history_rounded,
                        title: 'Nothing logged yet',
                        message: 'Actions are recorded here as they happen.',
                      )
                    else
                      for (var i = 0; i < _audit.take(40).length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: GwdSpace.sm),
                          child: AppleStaggerItem(
                            index: i,
                            child: _AuditRow(entry: _audit[i]),
                          ),
                        ),
                  ],
                ),
        ),
      ),
    );
  }

  /// This week against last, in words.
  ///
  /// A bare count is unreadable on its own — eleven tasks is excellent for one
  /// club and a collapse for another. The comparison is the only thing that
  /// makes the number mean anything, and it is deliberately phrased as pace
  /// rather than as a score.
  static String _pace(int thisWeek, int lastWeek, bool haveLastWeek) {
    if (thisWeek == 0 && !haveLastWeek) return 'Nothing finished yet';
    final counted = thisWeek == 1 ? '1 task finished' : '$thisWeek tasks finished';
    if (!haveLastWeek) return counted;
    final delta = thisWeek - lastWeek;
    if (delta == 0) return '$counted · the same as the week before';
    if (delta > 0) return '$counted · $delta more than the week before';
    return '$counted · ${-delta} fewer than the week before';
  }

  /// A single letter for the weekday of a `YYYY-MM-DD` day.
  static String _initial(String? day) {
    if (day == null) return '';
    final parsed = DateTime.tryParse(day);
    if (parsed == null) return '';
    return const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][(parsed.weekday - 1) % 7];
  }
}

/// One headline figure at the top of the dashboard.
class _Tile extends StatelessWidget {
  const _Tile({required this.value, required this.label, this.tint});
  final int value;
  final String label;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$value $label',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: GwdSpace.sm, vertical: GwdSpace.md),
        decoration: BoxDecoration(
          color: GwdColors.surfaceOf(context),
          borderRadius: BorderRadius.circular(GwdRadius.lg),
          border: Border.all(color: GwdColors.hairlineOf(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedCounter(
              value: value,
              style: GwdType.title2.merge(GwdType.numeric).copyWith(
                    color: tint ?? GwdColors.inkOf(context),
                    height: 1.0,
                  ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GwdType.micro.copyWith(color: GwdColors.inkTertiaryOf(context)),
            ),
          ],
        ),
      ),
    );
  }
}

class _DepartmentBar extends StatelessWidget {
  const _DepartmentBar({
    required this.name,
    required this.total,
    required this.completed,
    required this.rate,
    required this.scale,
    this.avgHours,
  });

  final String name;
  final int total;
  final int completed;
  final int rate;
  final int scale;
  final int? avgHours;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GwdType.headline.copyWith(color: GwdColors.inkOf(context))),
            ),
            Text('$completed/$total',
                style: GwdType.callout
                    .merge(GwdType.numeric)
                    .copyWith(color: GwdColors.inkSecondaryOf(context))),
          ],
        ),
        const SizedBox(height: GwdSpace.sm),
        // Two-layer bar: the pale layer is everything created, the solid layer
        // is what actually got finished. One mark, two facts.
        LayoutBuilder(
          builder: (context, constraints) {
            final totalWidth = (total / scale).clamp(0.0, 1.0) * constraints.maxWidth;
            final doneWidth = total == 0 ? 0.0 : (completed / total).clamp(0.0, 1.0) * totalWidth;
            return SizedBox(
              height: 8,
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: GwdColors.sunkenOf(context),
                      borderRadius: BorderRadius.circular(GwdRadius.pill),
                    ),
                  ),
                  TweenAnimationBuilder<double>(
                    duration: AppleDuration.deliberate,
                    curve: AppleCurves.standard,
                    tween: Tween(begin: 0, end: totalWidth),
                    builder: (context, w, _) => Container(
                      width: w,
                      decoration: BoxDecoration(
                        color: GwdColors.primaryRed.withValues(alpha: 0.24),
                        borderRadius: BorderRadius.circular(GwdRadius.pill),
                      ),
                    ),
                  ),
                  TweenAnimationBuilder<double>(
                    duration: AppleDuration.deliberate,
                    curve: AppleCurves.standard,
                    tween: Tween(begin: 0, end: doneWidth),
                    builder: (context, w, _) => Container(
                      width: w,
                      decoration: BoxDecoration(
                        color: GwdColors.primaryRed,
                        borderRadius: BorderRadius.circular(GwdRadius.pill),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 6),
        Text(
          avgHours == null
              ? '$rate% finished'
              : '$rate% finished · about ${_readableHours(avgHours!)} each',
          style: GwdType.footnote.copyWith(color: GwdColors.inkTertiaryOf(context)),
        ),
      ],
    );
  }

  /// Hours, until hours stop being a sensible unit.
  ///
  /// A club task that took 172 hours took a week; saying so is the difference
  /// between a figure somebody reads and one they skip.
  static String _readableHours(int hours) {
    if (hours < 1) return 'under an hour';
    if (hours < 48) return '$hours hours';
    return '${(hours / 24).round()} days';
  }
}

/// One line of the activity log.
///
/// The log stores machine actions (`task.create.department`) and a detail blob.
/// Printing the action with its dots turned into spaces produced rows reading
/// "Task create department", forty of them identical, which is a log that
/// technically contains the answer and cannot be read. Each action is phrased
/// as something that happened to something named.
class _AuditRow extends StatelessWidget {
  const _AuditRow({required this.entry});
  final Map<String, dynamic> entry;

  @override
  Widget build(BuildContext context) {
    final action = '${entry['action'] ?? ''}';
    final detail = (entry['detail'] as Map?)?.cast<String, dynamic>() ?? const {};
    final actor = '${entry['actorName'] ?? 'Someone'}';
    final when = DateTime.tryParse('${entry['createdAt'] ?? ''}');

    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: GwdSpace.lg, vertical: GwdSpace.md),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: GwdColors.sunkenOf(context),
              borderRadius: BorderRadius.circular(GwdRadius.sm),
            ),
            child: Icon(_iconFor(action), size: 15, color: GwdColors.inkSecondaryOf(context)),
          ),
          const SizedBox(width: GwdSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  describeAudit(action, detail),
                  style: GwdType.callout.copyWith(color: GwdColors.inkOf(context)),
                ),
                const SizedBox(height: 1),
                Text(
                  when == null ? actor : '$actor · ${_ago(when)}',
                  style: GwdType.footnote.copyWith(color: GwdColors.inkTertiaryOf(context)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static IconData _iconFor(String action) {
    if (action.startsWith('task')) return Icons.check_circle_outline_rounded;
    if (action.startsWith('event')) return Icons.event_outlined;
    if (action.startsWith('meeting')) return Icons.groups_outlined;
    if (action.startsWith('help')) return Icons.volunteer_activism_outlined;
    if (action.startsWith('alert')) return Icons.campaign_outlined;
    if (action.startsWith('points')) return Icons.auto_awesome_outlined;
    if (action.startsWith('bill')) return Icons.receipt_long_outlined;
    if (action.startsWith('document')) return Icons.description_outlined;
    if (action.startsWith('department')) return Icons.workspaces_outline;
    if (action.startsWith('category') || action.startsWith('schedule')) {
      return Icons.calendar_month_outlined;
    }
    if (action.startsWith('password')) return Icons.lock_outline_rounded;
    if (action.startsWith('user') || action == 'signup') return Icons.person_outline;
    return Icons.bolt_outlined;
  }

  static String _ago(DateTime when) {
    final diff = DateTime.now().difference(when);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${when.day}/${when.month}';
  }
}
