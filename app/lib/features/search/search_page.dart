import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/responsive.dart';
import '../../app/theme/gwd_theme.dart';
import '../../app/widgets/common.dart';
import '../../core/search/club_search.dart';
import '../departments/department_workspace_page.dart';
import '../directory/directory_page.dart';
import '../events/event_workspace_page.dart';
import '../meetings/meeting_detail_page.dart';
import '../tasks/task_detail_page.dart';

/// One place to find anything in the club.
///
/// There was no search at all before this: the Directory had its own filter and
/// Departments had another, and nothing else had any. "Which event was the
/// drone one?" and "what is Bhavya's department?" both ended in scrolling.
///
/// It searches what the store already holds rather than asking the server.
/// Everything here is in memory, the club is a hundred people, and a round trip
/// per keystroke over college Wi-Fi would be slower, would spend the backend's
/// single thread on something the phone does instantly, and would stop working
/// the moment the laptop went to sleep.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  String _query = '';

  @override
  void initState() {
    super.initState();
    // Opened by tapping a search icon, so the keyboard should already be up.
    // Making somebody tap the field they just navigated to is a wasted tap.
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _open(SearchHit hit) {
    final navigator = Navigator.of(context);
    switch (hit.kind) {
      case SearchKind.member:
        // The directory is where a person's record opens from, and it applies
        // the visibility rules. Jumping straight to a profile would route
        // around a permission the server would refuse anyway.
        navigator.push(MaterialPageRoute(builder: (_) => const DirectoryPage()));
      case SearchKind.department:
        navigator.push(MaterialPageRoute(
          builder: (_) => DepartmentWorkspacePage(departmentId: hit.id),
        ));
      case SearchKind.event:
        navigator.push(MaterialPageRoute(
          builder: (_) => EventWorkspacePage(eventId: hit.id),
        ));
      case SearchKind.task:
        navigator.push(MaterialPageRoute(builder: (_) => TaskDetailPage(taskId: hit.id)));
      case SearchKind.meeting:
        navigator.push(MaterialPageRoute(
          builder: (_) => MeetingDetailPage(meetingId: hit.id),
        ));
      case SearchKind.announcement:
        // Announcements are read where they were sent; there is no detail page
        // for one, and inventing a route to a screen that does not exist is
        // worse than the tap doing nothing.
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.storeOf(context);
    final gutter = GwdSpace.gutter(MediaQuery.sizeOf(context).width);

    final hits = searchClub(
      query: _query,
      members: store.members,
      departments: store.departments,
      events: [...store.eventsOngoing, ...store.eventsUpcoming, ...store.eventsCompleted],
      tasks: store.tasks,
      meetings: [...store.meetingsUpcoming, ...store.meetingsPast],
      announcements: store.alerts,
    );

    // Grouped for reading, in a fixed order so the screen does not reshuffle
    // its headings as somebody types.
    final grouped = <SearchKind, List<SearchHit>>{};
    for (final hit in hits) {
      grouped.putIfAbsent(hit.kind, () => []).add(hit);
    }
    final sections = [
      for (final kind in searchKindOrder)
        if (grouped[kind] != null) MapEntry(kind, grouped[kind]!),
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          focusNode: _focus,
          autocorrect: false,
          textInputAction: TextInputAction.search,
          style: GwdType.body.copyWith(color: GwdColors.inkOf(context)),
          decoration: InputDecoration(
            border: InputBorder.none,
            hintText: 'People, events, work…',
            hintStyle: GwdType.body.copyWith(color: GwdColors.inkTertiaryOf(context)),
          ),
          onChanged: (value) => setState(() => _query = value),
        ),
        actions: [
          if (_query.isNotEmpty)
            IconButton(
              tooltip: 'Clear',
              icon: const Icon(Icons.close_rounded, size: 20),
              onPressed: () {
                _controller.clear();
                setState(() => _query = '');
                _focus.requestFocus();
              },
            ),
        ],
      ),
      body: ContentWidth(
        child: Builder(builder: (context) {
          if (_query.trim().length < 2) {
            return const EmptyState(
              icon: Icons.search_rounded,
              title: 'Find anything',
              message: 'People, departments, events, work, meetings and '
                  'announcements — all from here.',
            );
          }
          if (sections.isEmpty) {
            return EmptyState(
              icon: Icons.search_off_rounded,
              title: 'Nothing matches "${_query.trim()}"',
              message: 'Try a shorter word, or part of a name.',
            );
          }

          // Flattened to one lazy list: a sliver per section would build every
          // heading eagerly on every keystroke.
          final rows = <Widget>[];
          for (final section in sections) {
            rows.add(Padding(
              padding: const EdgeInsets.only(top: GwdSpace.lg, bottom: GwdSpace.xs),
              child: SectionHeader(
                title: searchKindLabel(section.key, section.value.length),
              ),
            ));
            rows.addAll(section.value.map(
              (hit) => Padding(
                padding: const EdgeInsets.only(bottom: GwdSpace.sm),
                child: _HitRow(hit: hit, onTap: () => _open(hit)),
              ),
            ));
          }

          return ListView.builder(
            padding: EdgeInsets.fromLTRB(gutter, 0, gutter, GwdSpace.xxxl),
            itemCount: rows.length,
            itemBuilder: (context, i) => rows[i],
          );
        }),
      ),
    );
  }
}

class _HitRow extends StatelessWidget {
  const _HitRow({required this.hit, required this.onTap});

  final SearchHit hit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tint = _tint(hit.kind);
    return SurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: GwdSpace.lg, vertical: GwdSpace.md),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: GwdColors.readableOn(context, tint).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(GwdRadius.sm),
            ),
            child: Icon(_icon(hit.kind),
                size: 16, color: GwdColors.readableOn(context, tint)),
          ),
          const SizedBox(width: GwdSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(hit.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GwdType.headline.copyWith(color: GwdColors.inkOf(context))),
                if (hit.subtitle != null && hit.subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(hit.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GwdType.footnote
                          .copyWith(color: GwdColors.inkTertiaryOf(context))),
                ],
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, size: 18, color: GwdColors.inkTertiaryOf(context)),
        ],
      ),
    );
  }

  static IconData _icon(SearchKind kind) => switch (kind) {
        SearchKind.member => Icons.person_outline,
        SearchKind.department => Icons.workspaces_outline,
        SearchKind.event => Icons.event_outlined,
        SearchKind.task => Icons.check_circle_outline,
        SearchKind.meeting => Icons.groups_outlined,
        SearchKind.announcement => Icons.campaign_outlined,
      };

  static Color _tint(SearchKind kind) => switch (kind) {
        SearchKind.member => GwdColors.info,
        SearchKind.department => GwdColors.accents[5],
        SearchKind.event => GwdColors.primaryRed,
        SearchKind.task => GwdColors.success,
        SearchKind.meeting => GwdColors.accents[6],
        SearchKind.announcement => GwdColors.warning,
      };
}
