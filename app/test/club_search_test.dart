import 'package:flutter_test/flutter_test.dart';
import 'package:gwd_club_os/core/models/club_task.dart';
import 'package:gwd_club_os/core/models/department.dart';
import 'package:gwd_club_os/core/models/member.dart';
import 'package:gwd_club_os/core/search/club_search.dart';

Member _member(String id, String name, {String email = 'x@gwd.club'}) =>
    Member.fromJson({
      'id': id,
      'name': name,
      'email': email,
      'role': 'clubMember',
      'approvalStatus': 'approved',
    });

Department _dept(String id, String name, {bool active = true}) =>
    Department.fromJson({'id': id, 'name': name, 'active': active});

ClubTask _task(String id, String title, {String description = ''}) =>
    ClubTask.fromJson({
      'id': id,
      'title': title,
      'description': description,
      'status': 'pending',
    });

List<String> _titles(List<SearchHit> hits) => [for (final h in hits) h.title];

void main() {
  group('searchClub', () {
    test('one letter searches nothing', () {
      // A single character matches most of the club and answers no question.
      final hits = searchClub(
        query: 'a',
        members: [_member('1', 'Anvitha'), _member('2', 'Aldrin')],
      );
      expect(hits, isEmpty);
    });

    test('blank and whitespace search nothing', () {
      expect(searchClub(query: '', members: [_member('1', 'Anvitha')]), isEmpty);
      expect(searchClub(query: '   ', members: [_member('1', 'Anvitha')]), isEmpty);
    });

    test('finds across every kind at once', () {
      final hits = searchClub(
        query: 'drone',
        members: [_member('1', 'Drone Pilot')],
        departments: [_dept('d1', 'Drones')],
        tasks: [_task('t1', 'Charge the drone batteries')],
      );
      expect(hits.map((h) => h.kind).toSet(), {
        SearchKind.member,
        SearchKind.department,
        SearchKind.task,
      });
    });

    test('ranks where the match landed, not what it found first', () {
      // Typing "pr" should surface the PR department before a task that merely
      // contains the letters. This is the whole reason for scoring.
      final hits = searchClub(
        query: 'pr',
        departments: [_dept('d1', 'PR & HR')],
        tasks: [_task('t1', 'Approve the poster copy')],
      );
      expect(_titles(hits).first, 'PR & HR');
    });

    test('an exact match beats a prefix match', () {
      final hits = searchClub(
        query: 'creative',
        departments: [_dept('d1', 'Creative'), _dept('d2', 'Creative Writing')],
      );
      expect(_titles(hits), ['Creative', 'Creative Writing']);
    });

    test('matches a word inside a name', () {
      // "Marketing & Social Media" has to be findable by "social".
      final hits = searchClub(
        query: 'social',
        departments: [_dept('d1', 'Marketing & Social Media')],
      );
      expect(_titles(hits), ['Marketing & Social Media']);
    });

    test('a title match outranks a body match', () {
      final hits = searchClub(
        query: 'poster',
        tasks: [
          _task('t1', 'Call the printer', description: 'about the poster'),
          _task('t2', 'Poster for the night'),
        ],
      );
      expect(_titles(hits).first, 'Poster for the night');
    });

    test('an email finds the person, but scores below their name', () {
      final byEmail = searchClub(
        query: 'bhavya',
        members: [_member('1', 'Someone Else', email: 'bhavya@gwd.club')],
      );
      expect(byEmail, hasLength(1));

      final both = searchClub(
        query: 'bhavya',
        members: [
          _member('1', 'Someone Else', email: 'bhavya@gwd.club'),
          _member('2', 'Bhavya'),
        ],
      );
      expect(_titles(both).first, 'Bhavya');
    });

    test('a retired department is not offered', () {
      // Retiring hides it everywhere else; search would be the one place it
      // came back from the dead.
      final hits = searchClub(
        query: 'ghost',
        departments: [_dept('d1', 'Ghost Writing', active: false)],
      );
      expect(hits, isEmpty);
    });

    test('one noisy kind cannot bury the others', () {
      final hits = searchClub(
        query: 'club',
        departments: [_dept('d1', 'Club Admin')],
        tasks: [for (var i = 0; i < 30; i += 1) _task('t$i', 'Club task $i')],
        limitPerKind: 6,
      );
      expect(hits.where((h) => h.kind == SearchKind.task), hasLength(6));
      expect(hits.where((h) => h.kind == SearchKind.department), hasLength(1));
    });

    test('is case insensitive and ignores surrounding space', () {
      final hits = searchClub(
        query: '  CREATIVE  ',
        departments: [_dept('d1', 'Creative')],
      );
      expect(_titles(hits), ['Creative']);
    });

    test('every kind has a heading, singular and plural', () {
      for (final kind in searchKindOrder) {
        expect(searchKindLabel(kind, 1), isNotEmpty);
        expect(searchKindLabel(kind, 2), isNotEmpty);
        expect(searchKindLabel(kind, 1), isNot(searchKindLabel(kind, 2)));
      }
    });
  });
}
