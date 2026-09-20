import '../models/club_alert.dart';
import '../models/club_event.dart';
import '../models/club_task.dart';
import '../models/department.dart';
import '../models/meeting.dart';
import '../models/club_role.dart';
import '../models/member.dart';

/// What a search result points at.
enum SearchKind { member, department, event, task, meeting, announcement }

/// One result.
///
/// Deliberately not a widget and deliberately not carrying a route: the whole
/// point of keeping this a plain value is that the matching and the ranking can
/// be tested without a widget tree, and that is where every search bug of any
/// consequence lives.
class SearchHit {
  const SearchHit({
    required this.kind,
    required this.id,
    required this.title,
    required this.score,
    this.subtitle,
  });

  final SearchKind kind;
  final String id;
  final String title;
  final String? subtitle;

  /// Higher is a better match. See [_score].
  final int score;
}

/// Everything the club can be searched across, in one call.
///
/// Runs against the store's own lists rather than asking the server. The club
/// is a hundred people and the data is already in memory, so a round trip per
/// keystroke over college Wi-Fi would be slower, would spend the backend's one
/// thread on something the phone can do instantly, and would stop working the
/// moment the laptop went to sleep.
///
/// [limitPerKind] keeps one very common word — a department name that half the
/// tasks mention — from burying the other categories.
List<SearchHit> searchClub({
  required String query,
  List<Member> members = const [],
  List<Department> departments = const [],
  List<ClubEvent> events = const [],
  List<ClubTask> tasks = const [],
  List<Meeting> meetings = const [],
  List<ClubAlert> announcements = const [],
  int limitPerKind = 6,
}) {
  final needle = query.trim().toLowerCase();
  // One character matches most of the club and answers nothing.
  if (needle.length < 2) return const [];

  final hits = <SearchHit>[];

  void consider(
    SearchKind kind,
    String id,
    String? title, {
    String? subtitle,
    String? alsoSearch,
  }) {
    if (title == null || title.isEmpty) return;
    final score = _score(needle, title, alsoSearch);
    if (score == 0) return;
    hits.add(SearchHit(
      kind: kind,
      id: id,
      title: title,
      subtitle: subtitle,
      score: score,
    ));
  }

  for (final m in members) {
    // `displayName`, never the raw name: an account created for somebody who
    // has not signed in yet holds a placeholder there, and matching on it would
    // surface "No name set" as a person.
    consider(SearchKind.member, m.id, m.displayName,
        subtitle: m.role.title, alsoSearch: m.email);
  }
  for (final d in departments) {
    if (!d.active) continue;
    consider(SearchKind.department, d.id, d.name, subtitle: 'Department');
  }
  for (final e in events) {
    consider(SearchKind.event, e.id, e.name,
        subtitle: e.venue, alsoSearch: e.description);
  }
  for (final t in tasks) {
    consider(SearchKind.task, t.id, t.title,
        subtitle: t.status.label, alsoSearch: t.description);
  }
  for (final m in meetings) {
    consider(SearchKind.meeting, m.id, m.title, subtitle: m.venue);
  }
  for (final a in announcements) {
    consider(SearchKind.announcement, a.id, a.title,
        subtitle: 'Announcement', alsoSearch: a.message);
  }

  // Sort once, then cap per category, so the best of each kind survives even
  // when another kind matched forty times.
  hits.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    return byScore != 0 ? byScore : a.title.toLowerCase().compareTo(b.title.toLowerCase());
  });

  final kept = <SearchHit>[];
  final counts = <SearchKind, int>{};
  for (final hit in hits) {
    final n = counts[hit.kind] ?? 0;
    if (n >= limitPerKind) continue;
    counts[hit.kind] = n + 1;
    kept.add(hit);
  }
  return kept;
}

/// How good a match this is, or 0 for none.
///
/// Three tiers, because they are three genuinely different things to a reader:
/// what they typed *is* this, what they typed starts a word in it, and what
/// they typed appears somewhere inside it. Ranking by where the match landed is
/// the difference between typing "pr" and getting the PR department first
/// rather than "Approve the poster copy".
int _score(String needle, String title, String? extra) {
  final haystack = title.toLowerCase();

  if (haystack == needle) return 100;
  if (haystack.startsWith(needle)) return 80;

  // A word boundary inside the title — "social" finding "Marketing & Social".
  for (final word in haystack.split(RegExp(r'[\s&/,.-]+'))) {
    if (word.startsWith(needle)) return 60;
  }
  if (haystack.contains(needle)) return 40;

  // Only then the secondary field: an email, a description, the body of an
  // announcement. A title match should always outrank a body match.
  final other = extra?.toLowerCase();
  if (other != null && other.contains(needle)) return 20;

  return 0;
}

/// The heading a group of results sits under.
String searchKindLabel(SearchKind kind, int count) => switch (kind) {
      SearchKind.member => count == 1 ? 'Person' : 'People',
      SearchKind.department => count == 1 ? 'Department' : 'Departments',
      SearchKind.event => count == 1 ? 'Event' : 'Events',
      SearchKind.task => count == 1 ? 'Task' : 'Tasks',
      SearchKind.meeting => count == 1 ? 'Meeting' : 'Meetings',
      SearchKind.announcement => count == 1 ? 'Announcement' : 'Announcements',
    };

/// The order categories appear in.
///
/// People and departments first: a search in a club app is most often somebody
/// trying to find a person, and a name is the thing people remember.
const searchKindOrder = <SearchKind>[
  SearchKind.member,
  SearchKind.department,
  SearchKind.event,
  SearchKind.task,
  SearchKind.meeting,
  SearchKind.announcement,
];
