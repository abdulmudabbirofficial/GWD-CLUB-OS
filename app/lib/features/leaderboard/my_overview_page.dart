import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/responsive.dart';
import '../../app/theme/apple_motion.dart';
import '../../app/theme/gwd_theme.dart';
import '../../app/widgets/common.dart';
import '../../core/api/api_client.dart';
import '../../core/models/club_role.dart';
import '../../core/models/member.dart';
import 'member_stats_page.dart';

/// "What did I hand out, and who has done it?"
///
/// The question a Director or a Lead opens the app to answer. Before this they
/// had to reconstruct it — open each person, read their list, keep a tally in
/// their head — so most people did not bother and work quietly went unchased.
///
/// Ordered by **outstanding work**, unlike recognition, which is deliberately
/// never ordered by performance. The difference is the purpose: recognition is
/// about acknowledging people, and this is about finding what needs a nudge. A
/// list whose job is "who needs chasing" is useless if the answer is buried
/// alphabetically.
class MyOverviewPage extends StatefulWidget {
  const MyOverviewPage({super.key});

  @override
  State<MyOverviewPage> createState() => _MyOverviewPageState();
}

class _MyOverviewPageState extends State<MyOverviewPage> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final json = await AppScope.readStore(context).myOverview();
      if (!mounted) return;
      setState(() {
        _data = json;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    } catch (error) {
      if (mounted) setState(() { _error = '$error'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final totals = (_data?['totals'] as Map?)?.cast<String, dynamic>() ?? const {};
    final people = ((_data?['people'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();

    final assigned = (totals['assigned'] as num?)?.toInt() ?? 0;

    return Scaffold(
      backgroundColor: GwdColors.canvasOf(context),
      appBar: AppBar(
        title: Text('What I handed out',
            style: GwdType.title3.copyWith(color: GwdColors.inkOf(context))),
      ),
      body: RefreshIndicator(
        color: GwdColors.primaryRed,
        onRefresh: _load,
        child: ContentWidth(
          child: _loading
              ? Padding(
                  padding: EdgeInsets.symmetric(horizontal: layout.gutter),
                  child: const SkeletonList(count: 5, height: 68),
                )
              : _error != null
                  ? ListView(children: [
                      const SizedBox(height: 60),
                      EmptyState(
                        icon: Icons.error_outline_rounded,
                        title: 'Could not load',
                        message: _error!,
                      ),
                    ])
                  : assigned == 0
                      ? ListView(children: const [
                          SizedBox(height: 60),
                          EmptyState(
                            icon: Icons.outbox_outlined,
                            title: 'You have not given out any work yet',
                            message:
                                'Once you assign something, this is where you '
                                'see how it is going without opening each person.',
                          ),
                        ])
                      : ListView(
                          padding: EdgeInsets.fromLTRB(
                              layout.gutter, GwdSpace.lg, layout.gutter, GwdSpace.xxxl),
                          children: [
                            AppleStaggerItem(
                              index: 0,
                              child: _Totals(totals: totals),
                            ),

                            const SizedBox(height: GwdSpace.xxl),
                            AppleStaggerItem(
                              index: 1,
                              child: SectionHeader(
                                title: 'Who has it',
                                subtitle: people.isEmpty
                                    ? null
                                    : 'Most outstanding first',
                              ),
                            ),

                            if (people.isEmpty)
                              const EmptyState(
                                compact: true,
                                icon: Icons.inbox_outlined,
                                title: 'Nobody has it yet',
                                message:
                                    'Everything you sent is still waiting to be '
                                    'handed out by a department Lead.',
                              )
                            else
                              for (var i = 0; i < people.length; i++)
                                AppleStaggerItem(
                                  index: 2 + i,
                                  child: Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: GwdSpace.sm),
                                    child: _PersonProgress(row: people[i]),
                                  ),
                                ),
                          ],
                        ),
        ),
      ),
    );
  }
}

/// The four numbers, before any names.
class _Totals extends StatelessWidget {
  const _Totals({required this.totals});
  final Map<String, dynamic> totals;

  int _n(String key) => (totals[key] as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    final waiting = _n('awaitingHandout');
    final overdue = _n('overdue');

    return Column(
      children: [
        SurfaceCard(
          emphasis: SurfaceEmphasis.raised,
          child: Row(
            children: [
              _Stat(label: 'GIVEN', value: _n('assigned')),
              _Divider(),
              _Stat(label: 'DONE', value: _n('completed'), tint: GwdColors.success),
              _Divider(),
              _Stat(label: 'STILL OPEN', value: _n('open')),
              _Divider(),
              _Stat(
                label: 'OVERDUE',
                value: overdue,
                tint: overdue > 0 ? GwdColors.critical : null,
              ),
            ],
          ),
        ),

        // Work that has not reached a person yet is not somebody being slow —
        // it is a Lead who has not passed it on, and that is a different
        // conversation.
        if (waiting > 0) ...[
          const SizedBox(height: GwdSpace.md),
          Container(
            padding: const EdgeInsets.all(GwdSpace.md),
            decoration: BoxDecoration(
              color: GwdColors.warning.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(GwdRadius.md),
            ),
            child: Row(
              children: [
                const Icon(Icons.inbox_rounded, size: 16, color: GwdColors.warning),
                const SizedBox(width: GwdSpace.md),
                Expanded(
                  child: Text(
                    waiting == 1
                        ? '1 of these has not been handed out by its department yet.'
                        : '$waiting of these have not been handed out by their departments yet.',
                    style: GwdType.footnote
                        .copyWith(color: GwdColors.inkSecondaryOf(context)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.tint});
  final String label;
  final int value;
  final Color? tint;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          children: [
            AnimatedCounter(
              value: value,
              style: GwdType.title2.merge(GwdType.numeric).copyWith(
                    color: tint ?? GwdColors.inkOf(context),
                  ),
            ),
            const SizedBox(height: 2),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: GwdType.caption.copyWith(
                    fontSize: 8.5, color: GwdColors.inkTertiaryOf(context))),
          ],
        ),
      );
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 26, color: GwdColors.hairlineOf(context));
}

/// One person, and how their share is going.
class _PersonProgress extends StatelessWidget {
  const _PersonProgress({required this.row});
  final Map<String, dynamic> row;

  int _n(String key) => (row[key] as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    final assigned = _n('assigned');
    final completed = _n('completed');
    final open = _n('open');
    final overdue = _n('overdue');
    final name = row['name'] as String? ?? 'Member';
    final role = ClubRole.fromWire(row['role'] as String?);
    final department = row['departmentName'] as String?;

    final progress = assigned == 0 ? 0.0 : completed / assigned;

    return SurfaceCard(
      padding: const EdgeInsets.all(GwdSpace.md),
      borderColor: overdue > 0 ? GwdColors.critical.withValues(alpha: 0.35) : null,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MemberStatsPage(userId: row['id'] as String?),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Avatar(initials: _initials(name), tint: _tint(row), size: 36),
              const SizedBox(width: GwdSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GwdType.headline
                            .copyWith(color: GwdColors.inkOf(context))),
                    Text(positionLineFor(role, department),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GwdType.footnote
                            .copyWith(color: GwdColors.inkTertiaryOf(context))),
                  ],
                ),
              ),
              Text('$completed of $assigned',
                  style: GwdType.callout.merge(GwdType.numeric).copyWith(
                        color: GwdColors.inkSecondaryOf(context),
                      )),
            ],
          ),

          const SizedBox(height: GwdSpace.sm),
          // A bar rather than a percentage: "3 of 5" and a filled bar say the
          // same thing faster, and a percentage invites comparing people.
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progress),
              duration: AppleDuration.deliberate,
              curve: AppleCurves.enter,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 5,
                backgroundColor: GwdColors.sunkenOf(context),
                valueColor: AlwaysStoppedAnimation(
                  overdue > 0 ? GwdColors.critical : GwdColors.success,
                ),
              ),
            ),
          ),

          if (open > 0 || overdue > 0) ...[
            const SizedBox(height: GwdSpace.sm),
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                if (overdue > 0)
                  GwdChip(
                    label: overdue == 1 ? '1 overdue' : '$overdue overdue',
                    color: GwdColors.critical,
                    icon: Icons.schedule_rounded,
                    dense: true,
                  ),
                if (open - overdue > 0)
                  GwdChip(
                    label: '${open - overdue} still going',
                    color: GwdColors.inkTertiaryOf(context),
                    dense: true,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _initials(String value) {
    final words =
        value.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) {
      final w = words.first;
      return (w.length >= 2 ? w.substring(0, 2) : w).toUpperCase();
    }
    return '${words.first[0]}${words.last[0]}'.toUpperCase();
  }

  static Color _tint(Map<String, dynamic> row) {
    final hex = row['avatarColor'] as String?;
    if (hex != null && hex.startsWith('#') && hex.length == 7) {
      return Color(int.parse('FF${hex.substring(1)}', radix: 16));
    }
    return const Color(0xFF52525B);
  }
}
