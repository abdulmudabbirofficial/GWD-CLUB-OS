import 'package:flutter_test/flutter_test.dart';
import 'package:gwd_club_os/core/models/club_task.dart';
import 'package:gwd_club_os/core/models/task_request.dart';

/// A member asks their own Lead for work; they give work to nobody. The server
/// decides all of it - these check the app reads what it is told.
void main() {
  group('asking for work', () {
    test('a member’s ask is read as asking for work', () {
      final ask = TaskRequest.fromJson(const {
        'id': 'r1', 'fromUserId': 'm', 'fromName': 'Meera', 'toUserId': 'l',
        'toName': 'Dikshit', 'title': 'Design the poster', 'status': 'pending',
        'asksForWork': true,
      });
      expect(ask.asksForWork, isTrue);
      expect(ask.isPending, isTrue);
    });

    test('anything else is an ordinary request, including an older server', () {
      final request = TaskRequest.fromJson(const {
        'id': 'r2', 'fromUserId': 'a', 'fromName': 'A', 'toUserId': 'b',
        'toName': 'B', 'title': 'Stage rig', 'status': 'pending',
      });
      expect(request.asksForWork, isFalse);
    });
  });

  group('due labels', () {
    final longAgo = DateTime.now().subtract(const Duration(days: 4));

    test('open work that is late says so', () {
      final late = ClubTask.fromJson({
        'id': 't1', 'title': 'Late', 'status': 'inProgress',
        'dueDate': longAgo.toIso8601String(),
      });
      expect(late.dueLabel, contains('overdue'));
    });

    test('finished work is never called overdue', () {
      final done = ClubTask.fromJson({
        'id': 't2', 'title': 'Done', 'status': 'completed',
        'dueDate': longAgo.toIso8601String(),
      });
      expect(done.dueLabel, isNot(contains('overdue')));
      expect(done.dueLabel, startsWith('Due '));
    });
  });
}
