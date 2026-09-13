import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/responsive.dart';
import '../../app/theme/apple_motion.dart';
import '../../app/theme/gwd_theme.dart';
import '../../app/widgets/common.dart';
import '../../core/api/api_client.dart';
import '../../core/models/club_task.dart';
import '../../core/models/club_role.dart';
import '../../features/events/event_workspace_page.dart';
import '../../features/leaderboard/member_stats_page.dart';

/// One department's workspace.
///
/// Section 25: the event section shows only *this department's* share of each
/// event. A Marketing member opening a festival here sees Marketing's three
/// tasks, not the festival's forty — which is the difference between a useful
/// screen and a wall.
///
/// Section 26: being a Lead lets you run your department's work. It does not
/// make you an administrator of anything else, and nothing on this page grants
/// a power the server would not also grant.
class DepartmentWorkspacePage extends StatefulWidget {
  const DepartmentWorkspacePage({super.key, required this.departmentId});
  final String departmentId;

  @override
  State<DepartmentWorkspacePage> createState() => _DepartmentWorkspacePageState();
}

class _DepartmentWorkspacePageState extends State<DepartmentWorkspacePage> {
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final json = await AppScope.readStore(context)
          .departmentWorkspace(widget.departmentId);
      if (mounted) setState(() => _data = json);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.storeOf(context);
    final department = store.departmentById(widget.departmentId);
    final tint = department?.tint ?? GwdColors.primaryRed;
    final gutter = Layout.of(context).gutter;

    return Scaffold(
      backgroundColor: GwdColors.canvasOf(context),
      appBar: AppBar(title: Text(department?.name ?? 'Department')),
      body: _error != null
          ? EmptyState(
              icon: Icons.lock_outline_rounded,
              title: 'Cannot open this',
              message: _error!,
            )
          : _data == null
              ? const Padding(
                  padding: EdgeInsets.all(GwdSpace.xl),
                  child: SkeletonList(count: 4, height: 88),
                )
              : RefreshIndicator(
                  color: GwdColors.primaryRed,
                  onRefresh: _load,
                  child: _Body(
                    data: _data!,
                    tint: tint,
                    gutter: gutter,
                    departmentId: widget.departmentId,
                  ),
                ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.data,
    required this.tint,
    required this.gutter,
    required this.departmentId,
  });

  final Map<String, dynamic> data;
  final Color tint;
  final double gutter;
  final String departmentId;

  @override
  Widget build(BuildContext context) {
    final department = (data['department'] as Map).cast<String, dynamic>();
    final progress = (data['progress'] as Map?)?.cast<String, dynamic>() ?? const {};
    final lead = (data['lead'] as Map?)?.cast<String, dynamic>();
    final events = (data['events'] as List? ?? const []).whereType<Map>().toList();
    final work = (data['work'] as List? ?? const []).whereType<Map>().toList();
    final help = (data['helpRequests'] as List? ?? const []).whereType<Map>().toList();
    final members = (data['members'] as List? ?? const []).whereType<Map>().toList();
    final canViewRoster = data['canViewRoster'] == true;

    var step = 0;
    int next() => step++;

    return ListView(
      padding: EdgeInsets.fromLTRB(gutter, GwdSpace.lg, gutter, GwdSpace.xxxl),
      children: [
        AppleStaggerItem(
          index: next(),
          child: _ProgressCard(
            tint: tint,
            description: department['description'] as String? ?? '',
            assigned: (progress['assigned'] as num?)?.toInt() ?? 0,
            completed: (progress['completed'] as num?)?.toInt() ?? 0,
            rate: (progress['completionRate'] as num?)?.toInt() ?? 0,
            overdue: (progress['overdue'] as num?)?.toInt() ?? 0,
          ),
        ),

        if (lead != null) ...[
          const SizedBox(height: GwdSpace.xl),
          AppleStaggerItem(index: next(), child: const SectionHeader(title: 'Lead')),
          AppleStaggerItem(
            index: next(),
            child: _PersonRow(person: lead, isLead: true),
          ),
        ],

        if (events.isNotEmpty) ...[
          const SizedBox(height: GwdSpace.xl),
          AppleStaggerItem(
            index: next(),
            child: const SectionHeader(
              title: 'Events they are on',
              subtitle: 'Only this department’s share of each one',
            ),
          ),
          for (final event in events)
            AppleStaggerItem(
              index: next(),
              child: Padding(
                padding: const EdgeInsets.only(bottom: GwdSpace.sm),
                child: _EventSlice(event: event.cast<String, dynamic>()),
              ),
            ),
        ],

        if (help.isNotEmpty) ...[
          const SizedBox(height: GwdSpace.xl),
          AppleStaggerItem(
            index: next(),
            child: const SectionHeader(
              title: 'Asking for a hand',
              subtitle: 'Open requests from this department',
            ),
          ),
          for (final request in help)
            AppleStaggerItem(
              index: next(),
              child: Padding(
                padding: const EdgeInsets.only(bottom: GwdSpace.sm),
                child: _HelpRow(request: request.cast<String, dynamic>()),
              ),
            ),
        ],

        if (work.isNotEmpty) ...[
          const SizedBox(height: GwdSpace.xl),
          AppleStaggerItem(
            index: next(),
            child: SectionHeader(
              title: 'Open work',
              subtitle: work.length == 1
                  ? 'One thing on the go'
                  : '${work.length} things on the go',
            ),
          ),
          for (final task in work.take(20))
            AppleStaggerItem(
              index: next(),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _WorkRow(task: task.cast<String, dynamic>()),
              ),
            ),
        ],

        const SizedBox(height: GwdSpace.xl),
        AppleStaggerItem(
          index: next(),
          child: SectionHeader(
            title: 'People',
            subtitle: canViewRoster
                ? null
                : 'You can see this department’s progress, not its individual members',
          ),
        ),
        if (!canViewRoster)
          AppleStaggerItem(
            index: next(),
            child: _RosterLocked(
              count: (department['memberCount'] as num?)?.toInt() ?? 0,
            ),
          )
        else
          for (final member in members)
            AppleStaggerItem(
              index: next(),
              child: Padding(
                padding: const EdgeInsets.only(bottom: GwdSpace.sm),
                child: _PersonRow(
                  person: member.cast<String, dynamic>(),
                  isLead: member['isLead'] == true,
                ),
              ),
            ),
      ],
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({
    required this.tint,
    required this.description,
    required this.assigned,
    required this.completed,
    required this.rate,
    required this.overdue,
  });

  final Color tint;
  final String description;
  final int assigned;
  final int completed;
  final int rate;
  final int overdue;

  @override
  Widget build(BuildContext context) {
    final remaining = assigned - completed;

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ProgressArc(
                progress: assigned == 0 ? 0 : completed / assigned,
                size: 68,
                color: tint,
                child: AnimatedCounter(
                  value: rate,
                  suffix: '%',
                  style: GwdType.numeric
                      .copyWith(fontSize: 17, color: GwdColors.inkOf(context)),
                ),
              ),
              const SizedBox(width: GwdSpace.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      switch ((assigned, remaining)) {
                        (0, _) => 'Nothing assigned yet',
                        (_, 0) => 'Everything done',
                        (_, 1) => 'One task left',
                        _ => '$remaining tasks left',
                      },
                      style: GwdType.title3
                          .copyWith(color: GwdColors.inkOf(context)),
                    ),
                    const SizedBox(height: 2),
                    Text('$completed of $assigned finished',
                        style: GwdType.footnote.copyWith(
                            color: GwdColors.inkTertiaryOf(context))),
                    if (overdue > 0) ...[
                      const SizedBox(height: GwdSpace.sm),
                      GwdChip(
                        label: overdue == 1
                            ? '1 past its date'
                            : '$overdue past their dates',
                        color: GwdColors.warning,
                        icon: Icons.schedule_rounded,
                        dense: true,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: GwdSpace.lg),
            Text(description,
                style: GwdType.callout
                    .copyWith(color: GwdColors.inkSecondaryOf(context))),
          ],
        ],
      ),
    );
  }
}

class _EventSlice extends StatelessWidget {
  const _EventSlice({required this.event});
  final Map<String, dynamic> event;

  @override
  Widget build(BuildContext context) {
    final total = (event['myTotal'] as num?)?.toInt() ?? 0;
    final done = (event['myDone'] as num?)?.toInt() ?? 0;
    final banner = event['banner'] as String?;
    final tint = banner == null || banner.length < 7
        ? GwdColors.primaryRed
        : Color(int.parse('FF${banner.substring(1)}', radix: 16));
    final date = DateTime.tryParse(event['date']?.toString() ?? '')?.toLocal();

    return SurfaceCard(
      padding: const EdgeInsets.all(GwdSpace.md),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => EventWorkspacePage(eventId: event['id'] as String),
      )),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 3, height: 28, color: tint),
              const SizedBox(width: GwdSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(event['name'] as String? ?? 'Event',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GwdType.headline
                            .copyWith(color: GwdColors.inkOf(context))),
                    Text(
                      [
                        if (event['isOrganiser'] == true) 'Organising' else 'Supporting',
                        if (date != null) '${date.day}/${date.month}',
                      ].join('  ·  '),
                      style: GwdType.caption.copyWith(
                          fontSize: 9.5,
                          letterSpacing: 0,
                          color: GwdColors.inkTertiaryOf(context)),
                    ),
                  ],
                ),
              ),
              Text(
                total == 0 ? '—' : '$done/$total',
                style: GwdType.numeric.copyWith(
                    fontSize: 13, color: GwdColors.inkSecondaryOf(context)),
              ),
            ],
          ),
          if ((event['notes'] as String? ?? '').isNotEmpty) ...[
            const SizedBox(height: GwdSpace.sm),
            Padding(
              padding: const EdgeInsets.only(left: 15),
              child: Text(event['notes'] as String,
                  style: GwdType.footnote
                      .copyWith(color: GwdColors.inkSecondaryOf(context))),
            ),
          ],
        ],
      ),
    );
  }
}

class _WorkRow extends StatelessWidget {
  const _WorkRow({required this.task});
  final Map<String, dynamic> task;

  @override
  Widget build(BuildContext context) {
    final status = TaskStatus.fromWire(task['status'] as String?);
    final overdue = task['overdue'] == true;
    final due = DateTime.tryParse(task['dueDate']?.toString() ?? '')?.toLocal();

    return Row(
      children: [
        Icon(status.icon, size: 14, color: status.tint),
        const SizedBox(width: GwdSpace.sm),
        Expanded(
          child: Text(task['title'] as String? ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GwdType.callout.copyWith(color: GwdColors.inkOf(context))),
        ),
        if (task['assigneeName'] != null) ...[
          Text((task['assigneeName'] as String).split(' ').first,
              style: GwdType.caption.copyWith(
                  fontSize: 9.5,
                  letterSpacing: 0,
                  color: GwdColors.inkTertiaryOf(context))),
          const SizedBox(width: GwdSpace.sm),
        ],
        if (due != null)
          Text('${due.day}/${due.month}',
              style: GwdType.caption.copyWith(
                fontSize: 9.5,
                letterSpacing: 0,
                color: overdue ? GwdColors.critical : GwdColors.inkTertiaryOf(context),
              )),
      ],
    );
  }
}

class _HelpRow extends StatelessWidget {
  const _HelpRow({required this.request});
  final Map<String, dynamic> request;

  @override
  Widget build(BuildContext context) {
    final helpers = (request['helpers'] as num?)?.toInt() ?? 0;
    return SurfaceCard(
      padding: const EdgeInsets.all(GwdSpace.md),
      child: Row(
        children: [
          Icon(
            helpers > 0 ? Icons.handshake_outlined : Icons.pan_tool_outlined,
            size: 15,
            color: helpers > 0 ? GwdColors.success : GwdColors.warning,
          ),
          const SizedBox(width: GwdSpace.md),
          Expanded(
            child: Text(request['title'] as String? ?? '',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GwdType.callout.copyWith(color: GwdColors.inkOf(context))),
          ),
          if (helpers > 0)
            Text(helpers == 1 ? '1 helping' : '$helpers helping',
                style: GwdType.caption.copyWith(
                    fontSize: 9.5, letterSpacing: 0, color: GwdColors.success)),
        ],
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.person, required this.isLead});
  final Map<String, dynamic> person;
  final bool isLead;

  @override
  Widget build(BuildContext context) {
    final name = person['name'] as String? ?? 'Member';
    final colorHex = person['avatarColor'] as String?;
    final tint = colorHex == null || colorHex.length < 7
        ? GwdColors.inkSecondaryOf(context)
        : Color(int.parse('FF${colorHex.substring(1)}', radix: 16));

    return SurfaceCard(
      padding: const EdgeInsets.all(GwdSpace.md),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => MemberStatsPage(userId: person['id'] as String),
      )),
      child: Row(
        children: [
          Avatar(initials: _initials(name), tint: tint, size: 38, selected: isLead),
          const SizedBox(width: GwdSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name,
                    style: GwdType.headline
                        .copyWith(color: GwdColors.inkOf(context))),
                const SizedBox(height: 1),
                Text(ClubRole.fromWire(person['role'] as String?).title,
                    style: GwdType.footnote
                        .copyWith(color: GwdColors.inkTertiaryOf(context))),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded,
              size: 18, color: GwdColors.inkTertiaryOf(context)),
        ],
      ),
    );
  }

  String _initials(String name) {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    if (words.isEmpty) return '?';
    if (words.length == 1) {
      final w = words.first;
      return (w.length >= 2 ? w.substring(0, 2) : w).toUpperCase();
    }
    return '${words.first[0]}${words.last[0]}'.toUpperCase();
  }
}

/// Honest about the boundary rather than pretending the section is empty.
class _RosterLocked extends StatelessWidget {
  const _RosterLocked({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(GwdSpace.lg),
      decoration: BoxDecoration(
        color: GwdColors.sunkenOf(context),
        borderRadius: BorderRadius.circular(GwdRadius.lg),
      ),
      child: Row(
        children: [
          Icon(Icons.groups_outlined, size: 20, color: GwdColors.inkTertiaryOf(context)),
          const SizedBox(width: GwdSpace.md),
          Expanded(
            child: Text(
              count == 1
                  ? 'One person here. Individual records are kept within the department.'
                  : '$count people here. Individual records are kept within the department.',
              style: GwdType.footnote
                  .copyWith(color: GwdColors.inkTertiaryOf(context)),
            ),
          ),
        ],
      ),
    );
  }
}
