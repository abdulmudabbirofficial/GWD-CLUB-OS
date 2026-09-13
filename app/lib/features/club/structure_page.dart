import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/responsive.dart';
import '../../app/theme/apple_motion.dart';
import '../../app/theme/gwd_theme.dart';
import '../../app/widgets/brand.dart';
import '../../app/widgets/common.dart';
import '../../core/models/club_role.dart';
import '../../core/models/member.dart';
import '../directory/directory_page.dart';
import '../leaderboard/member_stats_page.dart';

/// The club as an org chart.
///
/// President first, then Vice President and Secretary General, then every
/// department. Tapping a department opens its Lead and members; tapping a
/// person opens their record.
///
/// Supervisors are deliberately absent. Directors and the Faculty Coordinator
/// oversee the club rather than sit inside its structure, and their records are
/// not part of the roster people browse.
///
/// Everyone sees department **progress**. Only leadership and Leads can open
/// the individual members of a department that is not their own — for everyone
/// else that drill-down is closed, and the headline number is the answer.
class StructurePage extends StatefulWidget {
  const StructurePage({super.key});

  @override
  State<StructurePage> createState() => _StructurePageState();
}

class _StructurePageState extends State<StructurePage> {
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
      final json = await AppScope.readStore(context).structure();
      if (mounted) setState(() { _data = json; _loading = false; });
    } catch (error) {
      if (mounted) setState(() { _error = '$error'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final executive = ((_data?['executive'] as List?) ?? [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
    final departments = ((_data?['departments'] as List?) ?? [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();

    return Scaffold(
      backgroundColor: GwdColors.canvasOf(context),
      appBar: AppBar(
        title: Text('Structure',
            style: GwdType.title3.copyWith(color: GwdColors.inkOf(context))),
      ),
      body: RefreshIndicator(
        color: GwdColors.primaryRed,
        onRefresh: _load,
        child: ContentWidth(
          child: _loading
              ? const Center(child: Padding(
                  padding: EdgeInsets.all(GwdSpace.xxxl),
                  child: BracketLoader(),
                ))
              : ListView(
                  padding: EdgeInsets.fromLTRB(
                      layout.gutter, GwdSpace.lg, layout.gutter, GwdSpace.xxxl),
                  children: [
                    if (_error != null) ...[
                      ErrorNote(message: _error!),
                      const SizedBox(height: GwdSpace.lg),
                    ],

                    const BrandedSectionHeader(
                      title: 'Executive',
                      subtitle: 'Who leads the club',
                    ),
                    for (var i = 0; i < executive.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: GwdSpace.sm),
                        child: AppleStaggerItem(
                          index: i,
                          child: _SeatCard(seat: executive[i], emphasis: i == 0),
                        ),
                      ),

                    const SizedBox(height: GwdSpace.xl),
                    BrandedSectionHeader(
                      title: 'Departments',
                      subtitle: '${departments.length} running',
                    ),
                    for (var i = 0; i < departments.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: GwdSpace.md),
                        child: AppleStaggerItem(
                          index: i,
                          child: _DepartmentCard(department: departments[i]),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// An executive seat — filled or vacant. A vacant seat is information worth
/// showing, not something to hide.
class _SeatCard extends StatelessWidget {
  const _SeatCard({required this.seat, required this.emphasis});

  final Map<String, dynamic> seat;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final role = ClubRole.fromWire(seat['role'] as String?);
    final holder = (seat['holder'] as Map?)?.cast<String, dynamic>();

    if (holder == null) {
      return SurfaceCard(
        padding: const EdgeInsets.all(GwdSpace.md),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: GwdColors.sunkenOf(context),
                shape: BoxShape.circle,
              ),
              child: Icon(role.icon, size: 18, color: GwdColors.inkTertiaryOf(context)),
            ),
            const SizedBox(width: GwdSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(role.title,
                      style: GwdType.headline
                          .copyWith(color: GwdColors.inkTertiaryOf(context))),
                  Text('Vacant',
                      style: GwdType.footnote
                          .copyWith(color: GwdColors.inkTertiaryOf(context))),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final member = Member.fromJson(holder);
    final canOpen = holder['canOpen'] as bool? ?? false;

    return SurfaceCard(
      padding: const EdgeInsets.all(GwdSpace.md),
      emphasis: emphasis ? SurfaceEmphasis.raised : SurfaceEmphasis.quiet,
      onTap: canOpen
          ? () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => MemberStatsPage(member: member)),
              )
          : null,
      child: Row(
        children: [
          Avatar(initials: member.initials, tint: member.tint, size: emphasis ? 46 : 40),
          const SizedBox(width: GwdSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(member.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: (emphasis ? GwdType.title3 : GwdType.headline)
                        .copyWith(color: GwdColors.inkOf(context))),
                const SizedBox(height: 2),
                Text(role.title,
                    style: GwdType.footnote
                        .copyWith(color: GwdColors.inkTertiaryOf(context))),
              ],
            ),
          ),
          if (canOpen)
            Icon(Icons.chevron_right_rounded,
                size: 18, color: GwdColors.inkTertiaryOf(context)),
        ],
      ),
    );
  }
}

class _DepartmentCard extends StatelessWidget {
  const _DepartmentCard({required this.department});
  final Map<String, dynamic> department;

  @override
  Widget build(BuildContext context) {
    final progress = (department['progress'] as Map?)?.cast<String, dynamic>() ?? const {};
    final lead = (department['lead'] as Map?)?.cast<String, dynamic>();
    final rate = (progress['completionRate'] as num?)?.toInt() ?? 0;
    final assigned = (progress['assigned'] as num?)?.toInt() ?? 0;
    final completed = (progress['completed'] as num?)?.toInt() ?? 0;
    final overdue = (progress['overdue'] as num?)?.toInt() ?? 0;
    final canViewRoster = department['canViewRoster'] as bool? ?? false;
    final memberCount = (department['memberCount'] as num?)?.toInt() ?? 0;

    return SurfaceCard(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => DepartmentPage(
          departmentId: '${department['id']}',
          name: '${department['name']}',
          canViewRoster: canViewRoster,
        ),
      )),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${department['name']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GwdType.title3.copyWith(color: GwdColors.inkOf(context))),
              ),
              if (overdue > 0)
                GwdChip(label: '$overdue OVERDUE', color: GwdColors.critical, dense: true),
              const SizedBox(width: GwdSpace.sm),
              Icon(Icons.chevron_right_rounded,
                  size: 18, color: GwdColors.inkTertiaryOf(context)),
            ],
          ),
          const SizedBox(height: GwdSpace.md),

          // Headline progress — open to everyone, which is the whole point of
          // separating aggregate from individual.
          Row(
            children: [
              Expanded(
                child: TweenAnimationBuilder<double>(
                  duration: AppleDuration.deliberate,
                  curve: AppleCurves.standard,
                  tween: Tween(begin: 0, end: assigned == 0 ? 0 : completed / assigned),
                  builder: (context, t, _) => Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: GwdColors.sunkenOf(context),
                      borderRadius: BorderRadius.circular(GwdRadius.pill),
                    ),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: t.clamp(0.0, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: _rateColor(rate),
                          borderRadius: BorderRadius.circular(GwdRadius.pill),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: GwdSpace.md),
              Text('$rate%',
                  style: GwdType.headline
                      .merge(GwdType.numeric)
                      .copyWith(color: _rateColor(rate))),
            ],
          ),
          const SizedBox(height: GwdSpace.sm),
          Row(
            children: [
              Icon(Icons.flag_outlined, size: 13, color: GwdColors.inkTertiaryOf(context)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  lead == null ? 'No Lead assigned' : '${lead['name']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GwdType.footnote
                      .copyWith(color: GwdColors.inkTertiaryOf(context)),
                ),
              ),
              Text(
                '$completed of $assigned · $memberCount ${memberCount == 1 ? 'member' : 'members'}',
                style: GwdType.footnote
                    .copyWith(color: GwdColors.inkTertiaryOf(context)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Color _rateColor(int rate) {
    if (rate >= 80) return GwdColors.success;
    if (rate >= 50) return GwdColors.info;
    if (rate > 0) return GwdColors.warning;
    return const Color(0xFF9A9AA4);
  }
}

/// One department: its Lead, then its members.
class DepartmentPage extends StatefulWidget {
  const DepartmentPage({
    super.key,
    required this.departmentId,
    required this.name,
    required this.canViewRoster,
  });

  final String departmentId;
  final String name;
  final bool canViewRoster;

  @override
  State<DepartmentPage> createState() => _DepartmentPageState();
}

class _DepartmentPageState extends State<DepartmentPage> {
  List<Member> _members = const [];
  String? _leadId;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.canViewRoster) {
      _load();
    } else {
      _loading = false;
    }
  }

  Future<void> _load() async {
    try {
      final json = await AppScope.readStore(context).departmentRoster(widget.departmentId);
      if (!mounted) return;
      setState(() {
        _leadId = (json['department'] as Map?)?['leadUserId'] as String?;
        _members = ((json['members'] as List?) ?? [])
            .whereType<Map>()
            .map((e) => Member.fromJson(e.cast<String, dynamic>()))
            .toList();
        _loading = false;
      });
    } catch (error) {
      if (mounted) setState(() { _error = '$error'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final lead = _members.where((m) => m.id == _leadId).firstOrNull;
    final rest = _members.where((m) => m.id != _leadId).toList();

    return Scaffold(
      backgroundColor: GwdColors.canvasOf(context),
      appBar: AppBar(
        title: Text(widget.name,
            style: GwdType.title3.copyWith(color: GwdColors.inkOf(context))),
      ),
      body: ContentWidth(
        child: !widget.canViewRoster
            ? const EmptyState(
                icon: Icons.lock_outline_rounded,
                title: 'Members are private',
                message:
                    'You can see this department\'s overall progress, but its '
                    'individual members are visible to their own department and '
                    'the club\'s leadership.',
              )
            : _loading
                ? const Center(child: Padding(
                    padding: EdgeInsets.all(GwdSpace.xxxl),
                    child: BracketLoader(),
                  ))
                : ListView(
                    padding: EdgeInsets.fromLTRB(
                        layout.gutter, GwdSpace.lg, layout.gutter, GwdSpace.xxxl),
                    children: [
                      if (_error != null) ...[
                        ErrorNote(message: _error!),
                        const SizedBox(height: GwdSpace.lg),
                      ],

                      const BrandedSectionHeader(title: 'Lead'),
                      if (lead == null)
                        const EmptyState(
                          compact: true,
                          icon: Icons.flag_outlined,
                          title: 'No Lead yet',
                          message: 'The President can appoint one.',
                        )
                      else
                        MemberRow(member: lead, subtitle: 'Department Lead'),

                      const SizedBox(height: GwdSpace.xl),
                      BrandedSectionHeader(
                        title: 'Members',
                        subtitle: '${rest.length} in this department',
                      ),
                      if (rest.isEmpty)
                        const EmptyState(
                          compact: true,
                          icon: Icons.person_add_alt_outlined,
                          title: 'No members yet',
                          message: 'People appear here once their request is approved.',
                        )
                      else
                        for (var i = 0; i < rest.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: GwdSpace.sm),
                            child: AppleStaggerItem(
                              index: i,
                              child: MemberRow(member: rest[i]),
                            ),
                          ),
                    ],
                  ),
      ),
    );
  }
}
