import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/responsive.dart';
import '../../app/theme/apple_motion.dart';
import '../../app/theme/gwd_theme.dart';
import '../../app/widgets/common.dart';
import '../../core/models/club_role.dart';
import '../../core/models/department.dart';
import '../../core/models/member.dart';
import '../leaderboard/member_stats_page.dart';

/// Member directory.
///
/// Organised the way the club is, rather than as one long alphabetical list:
/// the people who run it, by office, and then each department as a row you open
/// to find its Lead and its members. A flat list of forty names sorted by rank
/// is technically complete and practically useless — nobody looks for "a member
/// of the club", they look for "whoever runs Marketing".
///
/// Searching flattens it back out, because at that point you *do* know the name.
///
/// Supervisors are not listed for anyone but themselves: a Director's record is
/// visible only to other supervisors, so showing them would just produce rows
/// that refuse to open.
class DirectoryPage extends StatefulWidget {
  const DirectoryPage({super.key, this.departmentId});

  /// Set when this is opened as one department's roster rather than the whole
  /// club, which skips straight past the grouping.
  final String? departmentId;

  @override
  State<DirectoryPage> createState() => _DirectoryPageState();
}

class _DirectoryPageState extends State<DirectoryPage> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// The offices, in the order the club is actually structured.
  static const _executive = [
    ClubRole.clubDirector,
    ClubRole.facultyCoordinator,
    ClubRole.president,
    ClubRole.vicePresident,
    ClubRole.secretaryGeneral,
  ];

  @override
  Widget build(BuildContext context) {
    final store = AppScope.storeOf(context);
    final me = AppScope.sessionOf(context).me;
    final layout = Layout.of(context);
    final department = store.departmentById(widget.departmentId);
    final iAmSupervisor = me?.role.isSupervisor ?? false;

    var visible = store.members;
    if (!iAmSupervisor) {
      visible = visible.where((m) => !m.role.isSupervisor).toList();
    }
    if (widget.departmentId != null) {
      visible = visible.where((m) => m.departmentId == widget.departmentId).toList();
    }

    final searching = _query.trim().isNotEmpty;
    final matches = searching
        ? (visible
            .where((m) =>
                m.name.toLowerCase().contains(_query.toLowerCase()) ||
                m.email.toLowerCase().contains(_query.toLowerCase()))
            .toList()
          ..sort((a, b) {
            final byRank = b.role.rank.compareTo(a.role.rank);
            return byRank != 0 ? byRank : a.name.compareTo(b.name);
          }))
        : const <Member>[];

    return Scaffold(
      backgroundColor: GwdColors.canvasOf(context),
      appBar: AppBar(
        title: Text(department?.name ?? 'Directory',
            style: GwdType.title3.copyWith(color: GwdColors.inkOf(context))),
      ),
      body: ContentWidth(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(layout.gutter, 0, layout.gutter, GwdSpace.md),
              child: TextField(
                controller: _search,
                onChanged: (v) => setState(() => _query = v),
                style: GwdType.body.copyWith(color: GwdColors.inkOf(context)),
                decoration: InputDecoration(
                  hintText: 'Search members',
                  hintStyle:
                      GwdType.body.copyWith(color: GwdColors.inkTertiaryOf(context)),
                  prefixIcon: Icon(Icons.search_rounded,
                      size: 19, color: GwdColors.inkTertiaryOf(context)),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 17),
                          onPressed: () {
                            _search.clear();
                            setState(() => _query = '');
                          },
                        ),
                  filled: true,
                  fillColor: GwdColors.sunkenOf(context),
                  contentPadding: const EdgeInsets.symmetric(vertical: GwdSpace.md),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(GwdRadius.pill),
                    borderSide: BorderSide(color: GwdColors.hairlineOf(context)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(GwdRadius.pill),
                    borderSide: BorderSide(color: GwdColors.hairlineOf(context)),
                  ),
                ),
              ),
            ),
            Expanded(
              child: searching
                  ? _SearchResults(query: _query, matches: matches)
                  : widget.departmentId != null
                      ? _Roster(people: visible, layout: layout)
                      : _Grouped(people: visible, layout: layout),
            ),
          ],
        ),
      ),
    );
  }
}

/// The whole club, by office then by department.
class _Grouped extends StatelessWidget {
  const _Grouped({required this.people, required this.layout});

  final List<Member> people;
  final Layout layout;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.storeOf(context);
    final departments = store.departments.where((d) => d.active).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    // One row per office, in club order. Directors come as a pair, so the
    // grouping is by role rather than by a single seat.
    final offices = <MapEntry<ClubRole, List<Member>>>[];
    for (final role in _DirectoryPageState._executive) {
      final holders = people.where((m) => m.role == role).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      if (holders.isNotEmpty) offices.add(MapEntry(role, holders));
    }

    var step = 0;
    int next() => step++;

    return ListView(
      padding:
          EdgeInsets.fromLTRB(layout.gutter, 0, layout.gutter, GwdSpace.xxxl),
      children: [
        if (offices.isNotEmpty) ...[
          AppleStaggerItem(
            index: next(),
            child: const SectionHeader(
              title: 'Running the club',
              subtitle: 'The people every department reports through',
            ),
          ),
          for (final office in offices)
            for (final person in office.value)
              AppleStaggerItem(
                index: next(),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: GwdSpace.sm),
                  child: MemberRow(member: person, subtitle: person.role.title),
                ),
              ),
        ],

        const SizedBox(height: GwdSpace.xl),
        AppleStaggerItem(
          index: next(),
          child: SectionHeader(
            title: 'Departments',
            subtitle: departments.length == 1
                ? 'Open it to see the Lead and members'
                : 'Open one to see its Lead and members',
          ),
        ),
        for (final d in departments)
          AppleStaggerItem(
            index: next(),
            child: Padding(
              padding: const EdgeInsets.only(bottom: GwdSpace.sm),
              child: _DepartmentTile(
                department: d,
                people: people.where((m) => m.departmentId == d.id).toList(),
              ),
            ),
          ),

        if (departments.isEmpty && offices.isEmpty)
          const EmptyState(
            icon: Icons.person_search_outlined,
            title: 'Nobody here yet',
            message: 'Approved members appear here, grouped by department.',
          ),
      ],
    );
  }
}

class _DepartmentTile extends StatelessWidget {
  const _DepartmentTile({required this.department, required this.people});

  final Department department;
  final List<Member> people;

  @override
  Widget build(BuildContext context) {
    final lead = people.where((m) => m.id == department.leadUserId).firstOrNull;
    final tint = department.tint;

    return SurfaceCard(
      padding: const EdgeInsets.all(GwdSpace.md),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => DirectoryPage(departmentId: department.id),
      )),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(GwdRadius.md),
            ),
            child: Text(department.initials,
                style: GwdType.caption
                    .copyWith(color: tint, fontSize: 13, letterSpacing: 0)),
          ),
          const SizedBox(width: GwdSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(department.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GwdType.headline
                        .copyWith(color: GwdColors.inkOf(context))),
                const SizedBox(height: 1),
                Text(
                  [
                    lead != null ? 'Led by ${lead.firstName}' : 'No Lead yet',
                    people.length == 1 ? '1 person' : '${people.length} people',
                  ].join('  ·  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GwdType.footnote.copyWith(
                    color: lead == null
                        ? GwdColors.warning
                        : GwdColors.inkTertiaryOf(context),
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded,
              size: 18, color: GwdColors.inkTertiaryOf(context)),
        ],
      ),
    );
  }
}

/// One department opened: its Lead first, then everyone else.
class _Roster extends StatelessWidget {
  const _Roster({required this.people, required this.layout});

  final List<Member> people;
  final Layout layout;

  @override
  Widget build(BuildContext context) {
    if (people.isEmpty) {
      return const EmptyState(
        icon: Icons.person_search_outlined,
        title: 'Nobody here yet',
        message: 'Members appear once they are approved into this department.',
      );
    }

    final leads = people.where((m) => m.role == ClubRole.clubLead).toList();
    final members = people.where((m) => m.role != ClubRole.clubLead).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    // Flattened so the list can be built lazily. Every row carries its own
    // animation controller, and an eager `ListView(children: [...])` creates
    // one per member the moment the screen opens — fine for six people, a
    // visible stutter for a club of a hundred. A builder keeps roughly a
    // screenful alive instead.
    final rows = <Widget Function(int)>[
      if (leads.isNotEmpty) ...[
        (_) => const SectionHeader(title: 'Lead'),
        for (final lead in leads)
          (i) => Padding(
                padding: const EdgeInsets.only(bottom: GwdSpace.sm),
                child: MemberRow(member: lead),
              ),
        (_) => const SizedBox(height: GwdSpace.lg),
      ],
      (_) => SectionHeader(
            title: 'Members',
            subtitle: members.isEmpty ? 'Nobody else yet' : null,
          ),
      for (final member in members)
        (i) => Padding(
              padding: const EdgeInsets.only(bottom: GwdSpace.sm),
              child: MemberRow(member: member),
            ),
    ];

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(layout.gutter, 0, layout.gutter, GwdSpace.xxxl),
      itemCount: rows.length,
      itemBuilder: (context, i) => AppleStaggerItem(index: i, child: rows[i](i)),
    );
  }
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({required this.query, required this.matches});

  final String query;
  final List<Member> matches;

  @override
  Widget build(BuildContext context) {
    final gutter = Layout.of(context).gutter;
    if (matches.isEmpty) {
      return EmptyState(
        icon: Icons.person_search_outlined,
        title: 'No match',
        message: 'Nobody matches "$query".',
      );
    }
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(gutter, 0, gutter, GwdSpace.xxxl),
      itemCount: matches.length,
      itemBuilder: (context, i) => Padding(
        padding: const EdgeInsets.only(bottom: GwdSpace.sm),
        child: MemberRow(member: matches[i]),
      ),
    );
  }
}

/// One person in a list, opening their full record.
///
/// Shared by the directory and the department roster so a member looks and
/// behaves the same wherever you meet them.
class MemberRow extends StatelessWidget {
  const MemberRow({super.key, required this.member, this.subtitle});

  final Member member;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.storeOf(context);
    final department = store.departmentById(member.departmentId);

    return SurfaceCard(
      padding: const EdgeInsets.all(GwdSpace.md),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => MemberStatsPage(member: member)),
      ),
      child: Row(
        children: [
          Avatar(initials: member.initials, tint: member.tint, size: 40),
          const SizedBox(width: GwdSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // An account nobody has named yet says so, rather than passing
                // its placeholder off as a person. The position moves into the
                // line underneath, which is where a position belongs.
                Text(member.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GwdType.headline.copyWith(
                      color: member.isUnnamed
                          ? GwdColors.inkTertiaryOf(context)
                          : GwdColors.inkOf(context),
                    )),
                const SizedBox(height: 2),
                Text(
                  // What they are and where, on one line — "Marketing Lead",
                  // not "Club Lead". A caller can override it with something
                  // more useful for its own context (a completion count, say).
                  subtitle ?? member.positionLine(department?.name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GwdType.footnote
                      .copyWith(color: GwdColors.inkTertiaryOf(context)),
                ),
              ],
            ),
          ),
          if (member.role.earnsPoints && member.points > 0) ...[
            Text('${member.points}',
                style: GwdType.callout.merge(GwdType.numeric).copyWith(
                      color: GwdColors.inkTertiaryOf(context),
                    )),
            const SizedBox(width: GwdSpace.sm),
          ],
          RoleBadge(role: member.role, dense: true),
          const SizedBox(width: GwdSpace.xs),
          Icon(Icons.chevron_right_rounded,
              size: 18, color: GwdColors.inkTertiaryOf(context)),
        ],
      ),
    );
  }
}
