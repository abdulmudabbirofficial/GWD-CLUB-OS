import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme/apple_motion.dart';
import '../../app/theme/gwd_theme.dart';
import '../../app/widgets/common.dart';

/// Section 10 — one clean chart screen for Directors and the President.
///
/// Explicitly *not* a BI dashboard with many charts: that is the stacked-cards
/// problem this rebuild exists to escape. One comparison, one list, nothing
/// else.
class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  List<Map<String, dynamic>> _departments = const [];
  List<Map<String, dynamic>> _audit = const [];
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
        _departments = ((analytics['departments'] as List?) ?? [])
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
        _audit = ((audit['entries'] as List?) ?? [])
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
        _loading = false;
      });
    } catch (error) {
      if (mounted) setState(() { _error = '$error'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final gutter = GwdSpace.gutter(MediaQuery.sizeOf(context).width);
    final maxTotal = _departments.fold<int>(
        1, (max, d) => (d['total'] as num?)!.toInt() > max ? (d['total'] as num).toInt() : max);

    return Scaffold(
      backgroundColor: GwdColors.canvasOf(context),
      appBar: AppBar(
        title: Text('Activity',
            style: GwdType.title3.copyWith(color: GwdColors.inkOf(context))),
      ),
      body: RefreshIndicator(
        color: GwdColors.primaryRed,
        onRefresh: _load,
        child: _loading
            ? Padding(
                padding: EdgeInsets.symmetric(horizontal: gutter),
                child: const SkeletonList(count: 4, height: 64),
              )
            : ListView(
                padding:
                    EdgeInsets.fromLTRB(gutter, GwdSpace.lg, gutter, GwdSpace.xxxl),
                children: [
                  if (_error != null) ...[
                    ErrorNote(message: _error!),
                    const SizedBox(height: GwdSpace.lg),
                  ],

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
                              Divider(
                                  height: GwdSpace.xl,
                                  color: GwdColors.hairlineOf(context)),
                            _DepartmentBar(
                              name: '${_departments[i]['name']}',
                              total: (_departments[i]['total'] as num?)?.toInt() ?? 0,
                              completed:
                                  (_departments[i]['completed'] as num?)?.toInt() ?? 0,
                              rate: (_departments[i]['completionRate'] as num?)
                                      ?.toInt() ??
                                  0,
                              avgHours:
                                  (_departments[i]['avgCompletionHours'] as num?)
                                      ?.toInt(),
                              scale: maxTotal,
                            ),
                          ],
                        ],
                      ),
                    ),

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
            final doneWidth = total == 0
                ? 0.0
                : (completed / total).clamp(0.0, 1.0) * totalWidth;
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
                        color: GwdColors.primaryRed.withValues(alpha: 0.22),
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
        const SizedBox(height: 5),
        Text(
          [
            '$rate% complete',
            if (avgHours != null) 'avg ${avgHours}h to finish',
          ].join(' · '),
          style: GwdType.footnote.copyWith(color: GwdColors.inkTertiaryOf(context)),
        ),
      ],
    );
  }
}

class _AuditRow extends StatelessWidget {
  const _AuditRow({required this.entry});
  final Map<String, dynamic> entry;

  static const _labels = {
    'signup': 'signed up',
    'task.create': 'created a task',
    'task.update': 'updated a task',
    'task.delete': 'deleted a task',
    'access.approve': 'approved a member',
    'access.reject': 'declined a member',
    'department.create': 'created a department',
    'department.update': 'edited a department',
    'department.setLead': 'changed a department Lead',
    'department.deactivate': 'deactivated a department',
    'calendar.create': 'added a calendar entry',
    'calendar.delete': 'removed a calendar entry',
    'taskRequest.create': 'sent a task request',
    'taskRequest.accept': 'accepted a task request',
    'user.roleChange': 'changed someone\'s role',
  };

  @override
  Widget build(BuildContext context) {
    final action = '${entry['action']}';
    final when = DateTime.tryParse('${entry['createdAt']}')?.toLocal();

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: GwdSpace.md, vertical: GwdSpace.sm + 2),
      decoration: BoxDecoration(
        color: GwdColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(GwdRadius.md),
        border: Border.all(color: GwdColors.hairlineOf(context)),
      ),
      child: Row(
        children: [
          Expanded(
            child: RichText(
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                style: GwdType.footnote
                    .copyWith(color: GwdColors.inkSecondaryOf(context)),
                children: [
                  TextSpan(
                    text: '${entry['actorName']} ',
                    style: GwdType.footnote.copyWith(
                        color: GwdColors.inkOf(context), fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: _labels[action] ?? action),
                ],
              ),
            ),
          ),
          if (when != null) ...[
            const SizedBox(width: GwdSpace.sm),
            Text(
              '${when.day}/${when.month}',
              style: GwdType.caption.copyWith(
                  color: GwdColors.inkTertiaryOf(context), letterSpacing: 0),
            ),
          ],
        ],
      ),
    );
  }
}
