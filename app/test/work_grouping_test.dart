import 'package:flutter_test/flutter_test.dart';
import 'package:gwd_club_os/core/models/club_task.dart';
import 'package:gwd_club_os/features/tasks/work_grouping.dart';

/// Midday on a fixed Wednesday. Every boundary here is a *day*, so a test
/// written against the wall clock passes all afternoon and fails at ten to
/// midnight — which this project has been bitten by before.
final _now = DateTime(2026, 3, 11, 12);

ClubTask _task(
  String id, {
  DateTime? due,
  String status = 'pending',
  DateTime? completed,
}) =>
    ClubTask.fromJson({
      'id': id,
      'title': 'Task $id',
      'status': status,
      if (due != null) 'dueDate': due.toIso8601String(),
      if (completed != null) 'completedAt': completed.toIso8601String(),
    });

List<String> _headings(List<WorkRow> rows) =>
    [for (final r in rows) if (r.isHeading) r.heading!];

List<String> _idsUnder(List<WorkRow> rows, String heading) {
  final out = <String>[];
  var inside = false;
  for (final row in rows) {
    if (row.isHeading) {
      inside = row.heading == heading;
      continue;
    }
    if (inside) out.add(row.task!.id);
  }
  return out;
}

void main() {
  group('groupWork', () {
    test('nothing in, nothing out — no empty headings', () {
      expect(groupWork(const [], now: _now), isEmpty);
    });

    test('only the groups that have something in them get a heading', () {
      final rows = groupWork([_task('a', due: _now)], now: _now);
      expect(_headings(rows), ['Today']);
    });

    test('sorts the day into the order it presses on you', () {
      final rows = groupWork([
        _task('later', due: _now.add(const Duration(days: 20))),
        _task('today', due: _now),
        _task('late', due: _now.subtract(const Duration(days: 2))),
        _task('week', due: _now.add(const Duration(days: 3))),
        _task('someday'),
      ], now: _now);

      expect(_headings(rows), ['Overdue', 'Today', 'This week', 'Anytime']);
      expect(_idsUnder(rows, 'Overdue'), ['late']);
      expect(_idsUnder(rows, 'Today'), ['today']);
      expect(_idsUnder(rows, 'This week'), ['week']);
      // Undated work and work due beyond the week are the same thing to
      // somebody planning today: not now.
      expect(_idsUnder(rows, 'Anytime'), containsAll(['later', 'someday']));
    });

    test('a task due earlier today is still due today, not overdue', () {
      // The boundary is the day, not the hour. Something due at 9am is not
      // moved to Overdue at 9:01 — it is still what you are doing today.
      final rows = groupWork([_task('a', due: DateTime(2026, 3, 11, 9))], now: _now);
      expect(_headings(rows), ['Today']);
    });

    test('work somebody else is holding leaves the dated run', () {
      // In review or blocked means you cannot move it. Listing it under Today
      // keeps asking for something you are not able to give.
      final rows = groupWork([
        _task('mine', due: _now),
        _task('review', due: _now, status: 'review'),
        _task('stuck', due: _now, status: 'blocked'),
      ], now: _now);

      expect(_headings(rows), ['Today', 'Waiting on somebody else']);
      expect(_idsUnder(rows, 'Today'), ['mine']);
      expect(_idsUnder(rows, 'Waiting on somebody else'), ['review', 'stuck']);
    });

    test('overdue work is listed oldest first', () {
      final rows = groupWork([
        _task('b', due: _now.subtract(const Duration(days: 2))),
        _task('a', due: _now.subtract(const Duration(days: 9))),
        _task('c', due: _now.subtract(const Duration(days: 1))),
      ], now: _now);
      expect(_idsUnder(rows, 'Overdue'), ['a', 'b', 'c']);
    });

    test('recently done shows the last five, newest first', () {
      final rows = groupWork([
        for (var i = 0; i < 8; i += 1)
          _task('d$i',
              status: 'completed',
              completed: _now.subtract(Duration(days: i))),
      ], now: _now);

      final done = _idsUnder(rows, 'Recently done');
      expect(done, hasLength(5), reason: 'this is a receipt, not an archive');
      expect(done.first, 'd0');
      expect(done.last, 'd4');
    });

    test('every task given ends up somewhere', () {
      // A task that matches no branch would vanish from the screen while still
      // counting towards the badge, which is the worst kind of wrong.
      final tasks = [
        _task('a', due: _now.subtract(const Duration(days: 1))),
        _task('b', due: _now),
        _task('c', due: _now.add(const Duration(days: 2))),
        _task('d'),
        _task('e', status: 'review'),
        _task('f', status: 'blocked'),
        _task('g', status: 'completed', completed: _now),
        _task('h', status: 'inProgress', due: _now),
      ];
      final rows = groupWork(tasks, now: _now);
      final placed = [for (final r in rows) if (!r.isHeading) r.task!.id];
      expect(placed.toSet(), tasks.map((t) => t.id).toSet());
    });
  });
}
