import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gwd_club_os/app/theme/gwd_theme.dart';
import 'package:gwd_club_os/app/widgets/common.dart';
import 'package:gwd_club_os/core/models/app_notification.dart';
import 'package:gwd_club_os/core/models/club_alert.dart';
import 'package:gwd_club_os/core/models/club_event.dart';
import 'package:gwd_club_os/core/models/club_role.dart';
import 'package:gwd_club_os/core/models/club_task.dart';
import 'package:gwd_club_os/core/models/department.dart';
import 'package:gwd_club_os/core/models/event_bill.dart';
import 'package:gwd_club_os/core/models/event_document.dart';
import 'package:gwd_club_os/core/models/help_request.dart';
import 'package:gwd_club_os/core/models/recognition.dart';
import 'package:gwd_club_os/core/models/member.dart';
import 'package:gwd_club_os/core/models/schedule_category.dart';
import 'package:gwd_club_os/core/models/schedule_entry.dart';

void main() {
  group('ClubRole', () {
    test('round-trips every role through the wire format', () {
      for (final role in ClubRole.values) {
        expect(ClubRole.fromWire(role.wire), role);
      }
    });

    test('falls back to the least-privileged role for unknown input', () {
      // A server that grows a new role must never accidentally grant the client
      // more than Member until the app is updated to understand it.
      expect(ClubRole.fromWire('galacticOverlord'), ClubRole.clubMember);
      expect(ClubRole.fromWire(null), ClubRole.clubMember);
    });

    test('mirrors the server permission matrix', () {
      // A Member is the one role that cannot assign — this decides whether the
      // "Assigned" tab exists at all.
      expect(ClubRole.clubMember.canAssign, isFalse);
      for (final role in ClubRole.values.where((r) => r != ClubRole.clubMember)) {
        expect(role.canAssign, isTrue, reason: '${role.name} should be able to assign');
      }

      // Broadcasting is everyone-but-Members, or the feature becomes noise.
      expect(ClubRole.clubMember.canBroadcast, isFalse);
      expect(ClubRole.clubLead.canBroadcast, isTrue);

      // Department management: President and supervisors only.
      expect(ClubRole.president.canManageDepartments, isTrue);
      expect(ClubRole.clubDirector.canManageDepartments, isTrue);
      expect(ClubRole.facultyCoordinator.canManageDepartments, isTrue);
      expect(ClubRole.vicePresident.canManageDepartments, isFalse);
      expect(ClubRole.clubLead.canManageDepartments, isFalse);
    });

    test('places the Faculty Coordinator between Directors and the President', () {
      expect(ClubRole.facultyCoordinator.rank,
          lessThan(ClubRole.clubDirector.rank));
      expect(ClubRole.facultyCoordinator.rank,
          greaterThan(ClubRole.president.rank));
    });

    test('VP and Secretary General are the same tier', () {
      expect(ClubRole.vicePresident.rank, ClubRole.secretaryGeneral.rank);
      expect(ClubRole.president.rank, greaterThan(ClubRole.vicePresident.rank));
      expect(ClubRole.clubLead.rank, greaterThan(ClubRole.clubMember.rank));
    });

    test('supervisors oversee rather than compete', () {
      // Directors and the Faculty Coordinator earn no points and stay off the
      // leaderboard — a supervisor topping the board the members are working up
      // would make it meaningless.
      for (final role in [ClubRole.clubDirector, ClubRole.facultyCoordinator]) {
        expect(role.isSupervisor, isTrue, reason: role.name);
        expect(role.earnsPoints, isFalse, reason: role.name);
        expect(role.onLeaderboard, isFalse, reason: role.name);
      }
      // Everyone else does compete.
      for (final role in ClubRole.values.where((r) => !r.isSupervisor)) {
        expect(role.earnsPoints, isTrue, reason: role.name);
        expect(role.onLeaderboard, isTrue, reason: role.name);
      }
    });

    test('greets by office, never by a guessed honorific', () {
      // "Good morning, President" — not "Mr. President". Guessing someone's
      // gender from their role and getting it wrong every morning is worse than
      // the formality it would buy.
      expect(ClubRole.president.address, 'President');
      expect(ClubRole.clubDirector.address, 'Director');
      expect(ClubRole.facultyCoordinator.address, 'Coordinator');
      for (final role in ClubRole.values) {
        expect(role.address, isNot(contains('Mr')), reason: role.name);
        expect(role.address, isNot(contains('Ms')), reason: role.name);
        expect(role.address, isNot(contains('Madam')), reason: role.name);
      }
      // A plain Member is greeted by name alone — no office to address.
      expect(ClubRole.clubMember.hasAddress, isFalse);
    });

    test('supervisors cannot be chosen at signup', () {
      for (final role in [ClubRole.clubDirector, ClubRole.facultyCoordinator]) {
        expect(ClubRoleDetails.selectableAtSignup, isNot(contains(role)));
      }
    });

    test('only Members and Leads belong to a department', () {
      expect(ClubRole.clubMember.hasDepartment, isTrue);
      expect(ClubRole.clubLead.hasDepartment, isTrue);
      expect(ClubRole.president.hasDepartment, isFalse);
      expect(ClubRole.facultyCoordinator.hasDepartment, isFalse);
    });
  });

  group('TaskStatus', () {
    test('walks the three-step happy path', () {
      expect(TaskStatus.pending.nextForOwner, TaskStatus.inProgress);
      expect(TaskStatus.inProgress.nextForOwner, TaskStatus.completed);
      expect(TaskStatus.completed.nextForOwner, isNull);
    });

    test('blocked resumes into In Progress, not back to Pending', () {
      expect(TaskStatus.blocked.nextForOwner, TaskStatus.inProgress);
      expect(TaskStatus.blocked.trackIndex, TaskStatus.inProgress.trackIndex);
    });

    test('knows which states are still open work', () {
      expect(TaskStatus.pending.isOpen, isTrue);
      expect(TaskStatus.inProgress.isOpen, isTrue);
      expect(TaskStatus.blocked.isOpen, isTrue);
      expect(TaskStatus.completed.isOpen, isFalse);
      expect(TaskStatus.cancelled.isOpen, isFalse);
    });
  });

  group('ClubTask', () {
    ClubTask taskDue(Duration offset, {TaskStatus status = TaskStatus.pending}) => ClubTask(
          id: 't1',
          title: 'Design the poster',
          status: status,
          dueDate: DateTime.now().add(offset),
        );

    test('flags overdue only for work still open', () {
      expect(taskDue(const Duration(days: -2)).isOverdue, isTrue);
      expect(taskDue(const Duration(days: 2)).isOverdue, isFalse);
      // A task finished late is not "overdue" — there is nothing left to chase.
      expect(taskDue(const Duration(days: -2), status: TaskStatus.completed).isOverdue,
          isFalse);
    });

    test('describes due dates in human terms', () {
      expect(taskDue(const Duration(hours: 2)).dueLabel, 'Due today');
      expect(taskDue(const Duration(days: 1, hours: 2)).dueLabel, 'Due tomorrow');
      expect(taskDue(const Duration(days: -3)).dueLabel, contains('overdue'));
    });
  });

  group('ScheduleCategory', () {
    test('parses a club-defined category', () {
      final category = ScheduleCategory.fromJson({
        'id': 'c1',
        'name': 'Sponsor visit',
        'icon': 'sponsor',
        'color': '#0891B2',
        'count': 4,
      });
      // Categories are managed data, not an enum — a club invents its own.
      expect(category.name, 'Sponsor visit');
      expect(category.tint, const Color(0xFF0891B2));
      expect(category.count, 4);
    });

    test('falls back to a drawable icon for an unknown name', () {
      // A typo must never leave a blank square on the calendar.
      expect(iconFor('not-a-real-icon'), Icons.flag_outlined);
    });

    test('offers only icons it can actually draw', () {
      for (final name in scheduleIconChoices.keys) {
        expect(iconFor(name), isNotNull, reason: name);
      }
    });

    test('treats deadlines as a category the UI can filter on', () {
      // Deadlines are derived from tasks, but a member just sees another kind
      // of thing on the calendar, so it behaves like a category in the filter.
      expect(ScheduleCategory.deadline.isDeadline, isTrue);
      expect(ScheduleCategory.deadline.id, ScheduleCategory.deadlineId);
    });

    test('survives a malformed colour', () {
      expect(hexToColor('nonsense'), const Color(0xFFDC2626));
    });
  });

  group('ScheduleEntry', () {
    ScheduleEntry at(Duration offset, {String kind = 'entry'}) => ScheduleEntry(
          id: 'e1',
          kind: kind,
          title: 'Core team sync',
          categoryName: 'Meeting',
          categoryIcon: 'meeting',
          categoryColorHex: '#334155',
          date: DateTime.now().add(offset),
        );

    test('carries its category through from the server', () {
      final entry = ScheduleEntry.fromJson({
        'id': 'm1',
        'kind': 'entry',
        'categoryId': 'c9',
        'categoryName': 'Marketing',
        'categoryIcon': 'marketing',
        'categoryColor': '#7C3AED',
        'title': 'Teaser reel',
        'date': DateTime.now().toUtc().toIso8601String(),
        'platform': 'instagram',
        'format': 'reel',
        'stage': 'ready',
      });
      expect(entry.categoryName, 'Marketing');
      expect(entry.tint, const Color(0xFF7C3AED));
      expect(entry.platform, MarketingPlatform.instagram);
      expect(entry.format, MarketingFormat.reel);
      expect(entry.stage, MarketingStage.ready);
      expect(entry.hasContentFields, isTrue);
    });

    test('knows when it has no content fields to show', () {
      expect(at(const Duration(days: 1)).hasContentFields, isFalse);
    });

    test('recognises a task deadline', () {
      final entry = ScheduleEntry.fromJson({
        'id': 'task:abc',
        'kind': 'deadline',
        'categoryName': 'Deadline',
        'categoryIcon': 'deadline',
        'categoryColor': '#B45309',
        'title': 'Book the venue',
        'date': DateTime.now().toUtc().toIso8601String(),
        'taskId': 'abc',
        'taskStatus': 'pending',
      });
      // A deadline *is* a task — the schedule must send you to the task, not to
      // a read-only copy of it.
      expect(entry.isDeadline, isTrue);
      expect(entry.taskId, 'abc');
    });

    test('treats an ended entry as past', () {
      expect(at(const Duration(days: -2)).isPast, isTrue);
      expect(at(const Duration(days: 2)).isPast, isFalse);
    });

    test('tracks RSVPs per user', () {
      final entry = ScheduleEntry(
        id: '1',
        title: 'Orientation',
        categoryName: 'Event',
        categoryIcon: 'event',
        categoryColorHex: '#DC2626',
        date: DateTime.now().add(const Duration(days: 1)),
        rsvps: const ['u1', 'u2'],
      );
      expect(entry.isAttending('u1'), isTrue);
      expect(entry.isAttending('u9'), isFalse);
    });

    test('pads the time so a schedule column lines up', () {
      final entry = ScheduleEntry(
        id: '1',
        title: 'Sync',
        categoryName: 'Meeting',
        categoryIcon: 'meeting',
        categoryColorHex: '#334155',
        date: DateTime(2026, 9, 13, 9, 5),
      );
      expect(entry.timeLabel, '09:05');
    });
  });

  group('leaderboard fairness', () {
    test('a member carries assigned as well as completed', () {
      final member = Member.fromJson({
        'id': '1',
        'name': 'Aisha',
        'role': 'clubMember',
        'assignedTasks': 20,
        'completedTasks': 18,
        'completionRate': 90,
        'rank': 1,
      });
      // Both numbers travel together so a ranking can be checked rather than
      // taken on trust.
      expect(member.assignedTasks, 20);
      expect(member.completedTasks, 18);
      expect(member.completionRate, 90);
    });

    test('too little work means unranked, not a misleading 100%', () {
      final member = Member.fromJson({
        'id': '2',
        'name': 'New joiner',
        'role': 'clubMember',
        'assignedTasks': 1,
        'completedTasks': 1,
        'completionRate': 100,
        'rank': null,
      });
      expect(member.rank, isNull, reason: '1-of-1 must not outrank 18-of-20');
    });
  });

  group('ClubAlert', () {
    test('escalates urgency distinctly', () {
      final tints = AlertUrgency.values.map((u) => u.tint).toSet();
      expect(tints.length, AlertUrgency.values.length);
    });

    test('always carries its sender', () {
      final alert = ClubAlert.fromJson({
        'id': 'a1',
        'title': 'Venue moved',
        'message': 'Block C, 4pm.',
        'urgency': 'urgent',
        'audience': 'club',
        'senderName': 'Aisha Khan',
        'senderRole': 'president',
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      });
      // An unsigned club-wide alert is how this feature gets abused.
      expect(alert.senderName, 'Aisha Khan');
      expect(alert.senderRole, ClubRole.president);
      expect(alert.urgency, AlertUrgency.urgent);
    });
  });

  group('Department', () {
    test('gives the same colour to the same department every time', () {
      const a = Department(id: 'dept-1', name: 'Creative');
      const b = Department(id: 'dept-1', name: 'Creative renamed');
      const c = Department(id: 'dept-2', name: 'Creative');
      // Colour follows identity, not the display name, so renaming a
      // department does not make it look like a different one.
      expect(a.tint, b.tint);
      expect(a.tint, isNot(equals(c.tint)));
    });

    test('builds a monogram from the name', () {
      expect(const Department(id: '1', name: 'Social Media & Marketing').initials, 'SM');
      expect(const Department(id: '2', name: 'PR').initials, 'PR');
      expect(const Department(id: '3', name: '').initials, '—');
    });
  });

  group('Member', () {
    test('builds initials from one or many names', () {
      const solo = Member(id: '1', name: 'Prince', role: ClubRole.clubMember);
      const full = Member(id: '2', name: 'Aisha Noor Khan', role: ClubRole.clubLead);
      expect(solo.initials, 'PR');
      expect(full.initials, 'AK');
      expect(full.firstName, 'Aisha');
    });

    test('parses the avatar colour the server assigned', () {
      final member = Member.fromJson({
        'id': '1',
        'name': 'Test',
        'role': 'facultyCoordinator',
        'avatarColor': '#DC2626',
      });
      expect(member.tint, const Color(0xFFDC2626));
      expect(member.role, ClubRole.facultyCoordinator);
    });
  });

  group('AppNotification', () {
    test('reserves the accent for things that need action', () {
      AppNotification of(String type) => AppNotification(
            id: '1', type: type, title: 't', body: 'b', createdAt: DateTime.now(),
          );
      expect(of('approvalNeeded').isActionable, isTrue);
      expect(of('taskAssigned').isActionable, isTrue);
      // Informational ones stay quiet — the "spend crimson sparingly" rule.
      expect(of('pointsEarned').isActionable, isFalse);
      expect(of('taskCompleted').isActionable, isFalse);
    });
  });

  // =========================================================== EVENTS (v3)
  group('ClubEvent', () {
    ClubEvent build({
      String? date,
      String status = 'planning',
      int taskCount = 0,
      int taskCompleted = 0,
    }) =>
        ClubEvent.fromJson({
          'id': 'e1',
          'name': 'Tech Fest',
          'date': date ?? DateTime.now().add(const Duration(days: 5)).toIso8601String(),
          'status': status,
          'banner': '#0891B2',
          'taskCount': taskCount,
          'taskCompleted': taskCompleted,
          'progress': taskCount == 0 ? 0 : ((taskCompleted / taskCount) * 100).round(),
        });

    test('round-trips every status through the wire format', () {
      for (final status in EventStatus.values) {
        expect(EventStatus.fromWire(status.wire), status);
      }
    });

    test('falls back to planning for a status it does not know', () {
      // A server that grows a new status must not crash an older app.
      expect(EventStatus.fromWire('interdimensional'), EventStatus.planning);
      expect(EventStatus.fromWire(null), EventStatus.planning);
    });

    test('describes when it is in words, not arithmetic', () {
      expect(build(date: DateTime.now().toIso8601String()).whenLabel, 'Today');
      expect(
        build(date: DateTime.now().add(const Duration(days: 1)).toIso8601String())
            .whenLabel,
        'Tomorrow',
      );
      expect(
        build(date: DateTime.now().add(const Duration(days: 3)).toIso8601String())
            .whenLabel,
        'In 3 days',
      );
    });

    test('parses its banner colour and survives a malformed one', () {
      expect(build().bannerColor, const Color(0xFF0891B2));
      final broken = ClubEvent.fromJson({
        'id': 'e2',
        'name': 'x',
        'date': DateTime.now().toIso8601String(),
        'banner': 'nope',
      });
      expect(broken.bannerColor, isA<Color>());
    });

    test('offers a short forward path, never every status from every status', () {
      // An event that can go anywhere from anywhere means the status stops
      // telling anybody anything.
      for (final status in EventStatus.values) {
        expect(status.nextOptions.contains(status), isFalse,
            reason: '${status.name} should not offer itself');
        expect(status.nextOptions.length, lessThanOrEqualTo(3));
      }
      expect(EventStatus.planning.nextOptions, contains(EventStatus.approved));
      expect(EventStatus.ongoing.nextOptions, contains(EventStatus.completed));
    });
  });

  group('TaskStatus review lane', () {
    test('the board is exactly four columns', () {
      expect(TaskStatus.board,
          [TaskStatus.pending, TaskStatus.inProgress, TaskStatus.review, TaskStatus.completed]);
      // Blocked is not a column: a blocked card stays in its lane wearing a
      // badge, because moving it somewhere else is how work gets forgotten.
      expect(TaskStatus.board.contains(TaskStatus.blocked), isFalse);
    });

    test('an owner never waves their own work through review', () {
      expect(TaskStatus.review.nextForOwner, isNull);
      expect(TaskStatus.inProgress.nextForOwner, TaskStatus.completed);
    });

    test('review counts as open work', () {
      expect(TaskStatus.review.isOpen, isTrue);
      expect(TaskStatus.completed.isOpen, isFalse);
    });

    test('carries the event it belongs to', () {
      final task = ClubTask.fromJson({
        'id': 't1',
        'title': 'Poster',
        'status': 'review',
        'eventId': 'e1',
      });
      expect(task.eventId, 'e1');
      expect(task.status, TaskStatus.review);
      // Copying must not drop it, or event work falls off its own board.
      expect(task.copyWith(status: TaskStatus.completed).eventId, 'e1');
    });
  });

  group('EventDocument', () {
    EventDocument build({String kind = 'approval', String status = 'pending'}) =>
        EventDocument.fromJson({
          'id': 'd1',
          'eventId': 'e1',
          'kind': kind,
          'title': 'Venue permission',
          'status': status,
          'createdByName': 'President',
          'createdAt': DateTime.now().toIso8601String(),
          'version': 2,
          'current': {
            'filename': 'venue.pdf',
            'size': 250000,
            'mimeType': 'application/pdf',
          },
          'history': [
            {'version': 1, 'filename': 'venue.pdf', 'superseded': true},
            {'version': 2, 'filename': 'venue.pdf', 'superseded': false},
          ],
        });

    test('an uploaded approval is pending, not approved', () {
      // Filing a letter and the college signing it are different events, and
      // conflating them is the hole the whole permission model exists to close.
      expect(build().status, DocumentStatus.pending);
      expect(build().status.label, 'Awaiting sign-off');
    });

    test('keeps every version and marks the old ones superseded', () {
      final doc = build();
      expect(doc.version, 2);
      expect(doc.history.length, 2);
      expect(doc.history.first.superseded, isTrue);
      expect(doc.history.last.superseded, isFalse);
    });

    test('reads a file size a person can parse', () {
      expect(build().sizeLabel, '244 KB');
    });

    test('a link is not a stored file', () {
      final link = EventDocument.fromJson({
        'id': 'd2',
        'kind': 'file',
        'title': 'Drive folder',
        'status': 'approved',
        'createdByName': 'Lead',
        'version': 1,
        'history': const [],
        'current': {'link': 'https://drive.google.com/x', 'filename': 'Drive folder'},
      });
      expect(link.isLink, isTrue);
      expect(link.sizeLabel, 'Link');
    });

    test('capability flags default closed', () {
      // If the server says nothing, the client must offer nothing — never the
      // other way round.
      const empty = EventDocuments.empty;
      expect(empty.canUploadApproval, isFalse);
      expect(empty.canDecide, isFalse);
      expect(empty.canUploadFile, isFalse);
    });
  });

  group('HelpRequest', () {
    HelpRequest build({String status = 'open', List<Map<String, dynamic>> helpers = const []}) =>
        HelpRequest.fromJson({
          'id': 'h1',
          'title': 'Need a hand with the backdrop',
          'status': status,
          'createdByName': 'Aisha',
          'createdAt': DateTime.now().toIso8601String(),
          'helpers': helpers,
          'mine': false,
          'helping': false,
          'skills': const ['Design'],
        });

    test('round-trips every status', () {
      for (final status in HelpStatus.values) {
        expect(HelpStatus.fromWire(status.wire), status);
      }
      expect(HelpStatus.fromWire('gibberish'), HelpStatus.open);
    });

    test('reads as an ask, never as a ticket', () {
      // The copy matters here: this feature only works if asking feels free.
      expect(HelpStatus.open.label, 'Looking for someone');
      expect(HelpStatus.resolved.label, 'Sorted');
    });

    test('knows who has offered', () {
      final claimed = build(status: 'assigned', helpers: [
        {'id': 'u2', 'name': 'Rahul', 'note': 'Free after 2pm'},
      ]);
      expect(claimed.helpers.length, 1);
      expect(claimed.helpers.first.note, 'Free after 2pm');
      expect(claimed.isOpen, isTrue);
      expect(build(status: 'resolved').isOpen, isFalse);
    });
  });

  // ================================================ ASSIGNMENT + MONEY (v3.1)
  group('DepartmentRecognition', () {
    DepartmentRecognition build() => DepartmentRecognition.fromJson({
          'departmentId': 'd1',
          'name': 'Creative',
          'lead': {'id': 'u1', 'name': 'Aisha Khan', 'role': 'clubLead', 'points': 24},
          'members': [
            {'id': 'u2', 'name': 'Rahul', 'role': 'clubMember', 'points': 9,
              'assignedTasks': 4, 'completedTasks': 3},
            {'id': 'u3', 'name': 'Sana', 'role': 'clubMember', 'points': 3,
              'assignedTasks': 2, 'completedTasks': 1},
          ],
          'totals': {'people': 3, 'assigned': 6, 'completed': 4, 'points': 12,
            'completionRate': 67},
        });

    test('the Lead is kept out of their own team\'s list', () {
      // They earn from everything the department finishes, so a row would
      // always top it and say nothing.
      final group = build();
      expect(group.lead?.name, 'Aisha Khan');
      expect(group.members.any((m) => m.id == 'u1'), isFalse);
      expect(group.members.length, 2);
    });

    test('carries the department\'s own totals', () {
      expect(build().totals.assigned, 6);
      expect(build().totals.completed, 4);
      expect(build().totals.points, 12);
    });

    test('gives the same department the same colour every time', () {
      expect(build().tint, build().tint);
    });
  });

  group('DepartmentProgress', () {
    test('reports work sent but not yet handed out', () {
      // The one number on the club overview somebody can act on today.
      final row = DepartmentProgress.fromJson({
        'departmentId': 'd1',
        'name': 'Technical',
        'assigned': 10,
        'completed': 6,
        'open': 4,
        'awaitingHandout': 2,
        'completionRate': 60,
        'people': 5,
        'hasLead': true,
      });
      expect(row.awaitingHandout, 2);
      expect(row.open, 4);
      expect(row.hasLead, isTrue);
    });
  });

  group('AssignableDepartment', () {
    test('a department with no Lead is a fact, not a blank', () {
      final none = AssignableDepartment.fromJson({'id': 'd1', 'name': 'PR & HR'});
      expect(none.leadName, isNull);
      final led = AssignableDepartment.fromJson(
          {'id': 'd2', 'name': 'Creative', 'leadName': 'Aisha'});
      expect(led.leadName, 'Aisha');
    });
  });

  group('EventBill', () {
    EventBill build({String status = 'pending', double amount = 1450.5}) =>
        EventBill.fromJson({
          'id': 'b1',
          'eventId': 'e1',
          'title': 'Poster printing',
          'amount': amount,
          'category': 'Printing',
          'status': status,
          'paidByName': 'Aisha',
          'createdByName': 'Creative Lead',
          'createdAt': DateTime.now().toIso8601String(),
          'hasReceipt': true,
        });

    test('round-trips every status', () {
      for (final status in BillStatus.values) {
        expect(BillStatus.fromWire(status.wire), status);
      }
      expect(BillStatus.fromWire('gibberish'), BillStatus.pending);
    });

    test('an approved bill still reads as a debt, not as done', () {
      // The distinction the whole feature turns on: approved means somebody is
      // still out of pocket.
      expect(BillStatus.approved.label, 'Approved — not yet repaid');
      expect(BillStatus.paid.label, 'Repaid');
    });

    test('records who is out of pocket, which is not always who filed it', () {
      final bill = build();
      expect(bill.paidByName, 'Aisha');
      expect(bill.createdByName, 'Creative Lead');
    });

    test('formats money the way India writes it', () {
      expect(formatRupees(1450.5), '₹1,450.50');
      expect(formatRupees(145000), '₹1,45,000');
      expect(formatRupees(12345678), '₹1,23,45,678');
      expect(formatRupees(500), '₹500');
    });

    test('capability flags default closed', () {
      // If the server says nothing, offer nothing — never the other way round.
      final finance = EventFinance.fromJson(const {});
      expect(finance.canAdd, isFalse);
      expect(finance.canDecide, isFalse);
      expect(finance.canSettle, isFalse);
    });

    test('separates what was spent from what is still owed', () {
      final finance = EventFinance.fromJson({
        'bills': const [],
        'totals': {'spent': 5000.0, 'owed': 1450.5, 'pending': 0.0, 'paid': 3549.5},
      });
      expect(finance.spent, 5000);
      expect(finance.owed, 1450.5);
    });
  });

  group('Member accounts', () {
    test('flags an account still using a password somebody else knows', () {
      final seeded = Member.fromJson({
        'id': 'u1', 'name': 'Creative Lead', 'role': 'clubLead',
        'mustChangePassword': true,
      });
      expect(seeded.mustChangePassword, isTrue);
      expect(seeded.passwordResetRequested, isFalse);
    });

    test('and one whose owner has said they are locked out', () {
      final stuck = Member.fromJson({
        'id': 'u2', 'name': 'Rahul', 'role': 'clubMember',
        'passwordResetRequested': true,
      });
      expect(stuck.passwordResetRequested, isTrue);
    });

    test('both default to false rather than null', () {
      final plain = Member.fromJson({'id': 'u3', 'name': 'Sana', 'role': 'clubMember'});
      expect(plain.mustChangePassword, isFalse);
      expect(plain.passwordResetRequested, isFalse);
    });
  });

  group('naming', () {
    // A club where six people are called "<Department> Lead" is the state this
    // replaces. The name identifies the person; the position only qualifies
    // them, and belongs on the line underneath.
    test('an account created for somebody does not pass its placeholder off as a name', () {
      final seeded = Member.fromJson({
        'id': 'u1', 'name': 'Creative Lead', 'role': 'clubLead',
        'mustSetName': true,
      });
      expect(seeded.isUnnamed, isTrue);
      expect(seeded.displayName, 'No name set');
      expect(seeded.name, 'Creative Lead',
          reason: 'the raw value is kept so an admin can see what it was');
    });

    test('a real name is printed as given', () {
      final named = Member.fromJson({
        'id': 'u2', 'name': 'Ananya Rao', 'role': 'clubLead',
      });
      expect(named.isUnnamed, isFalse);
      expect(named.displayName, 'Ananya Rao');
    });

    test('the flag is what decides it, never the text', () {
      // Somebody genuinely called this must not be badgered about their own
      // name, which is exactly what string-matching the placeholder would do.
      final person = Member.fromJson({
        'id': 'u3', 'name': 'Creative Lead', 'role': 'clubMember',
        'mustSetName': false,
      });
      expect(person.isUnnamed, isFalse);
      expect(person.displayName, 'Creative Lead');
    });

    test('absent means named, so an older server never blanks the directory', () {
      final legacy = Member.fromJson({'id': 'u4', 'name': 'Rahul', 'role': 'clubMember'});
      expect(legacy.mustSetName, isFalse);
      expect(legacy.displayName, 'Rahul');
    });

    test('renaming clears the flag through copyWith', () {
      final before = Member.fromJson({
        'id': 'u5', 'name': 'Technical Lead', 'role': 'clubLead',
        'mustSetName': true,
      });
      final after = before.copyWith(name: 'Imran Qureshi', mustSetName: false);
      expect(after.displayName, 'Imran Qureshi');
      expect(after.isUnnamed, isFalse);
      expect(before.displayName, 'No name set',
          reason: 'copyWith must not mutate the original');
    });
  });

  group('position line', () {
    Member as_(String role, {String? name}) => Member.fromJson({
          'id': 'u1', 'name': name ?? 'Abdul', 'role': role,
        });

    // "Abdul" over "Marketing Lead" — one line saying what somebody is and
    // where. The bare role is nearly useless in a club with six departments.
    test('a Lead is named for their department', () {
      expect(as_('clubLead').positionLine('Marketing'), 'Marketing Lead');
    });

    test('a member likewise', () {
      expect(as_('clubMember').positionLine('Marketing'), 'Marketing member');
    });

    test('the executive tier names itself and takes no department', () {
      expect(as_('president').positionLine(null), 'President');
      expect(as_('secretaryGeneral').positionLine(null), 'Secretary General');
    });

    test('a senior person sitting in a department keeps their office first', () {
      expect(as_('vicePresident').positionLine('Creative'),
          'Vice President · Creative');
    });

    test('no department falls back to the plain role, never a dangling word', () {
      expect(as_('clubLead').positionLine(null), 'Club Lead');
      expect(as_('clubMember').positionLine(''), 'Club Member');
      expect(as_('clubLead').positionLine('   '), 'Club Lead');
    });

    test('the free function and the method agree', () {
      expect(positionLineFor(ClubRole.clubLead, 'PR & HR'),
          as_('clubLead').positionLine('PR & HR'));
    });
  });

  group('personal calendar', () {
    ScheduleEntry deadline({String? assignedTo}) => ScheduleEntry.fromJson({
          'id': 'task:1', 'kind': 'deadline', 'title': 'Poster',
          'date': DateTime.now().toIso8601String(),
          'categoryName': 'Deadline', 'categoryIcon': 'deadline',
          'categoryColor': '#B45309',
          'assignedTo': assignedTo,
        });

    test('a deadline is mine when it is assigned to me', () {
      expect(deadline(assignedTo: 'me').isMine('me'), isTrue);
    });

    test('and not when it is somebody else\'s', () {
      expect(deadline(assignedTo: 'them').isMine('me'), isFalse);
    });

    test('work nobody has picked up yet is nobody\'s', () {
      // A department task awaiting hand-out has no assignee. It must not show
      // on a personal calendar — it is the Lead's triage pile, not a debt.
      expect(deadline(assignedTo: null).isMine('me'), isFalse);
    });

    test('a club entry is mine only once I have said I am going', () {
      final entry = ScheduleEntry.fromJson({
        'id': 'e1', 'kind': 'entry', 'title': 'Fest',
        'date': DateTime.now().toIso8601String(),
        'categoryName': 'Event', 'categoryIcon': 'event', 'categoryColor': '#DC2626',
        'rsvps': const ['someone'],
      });
      expect(entry.isMine('me'), isFalse);

      final going = ScheduleEntry.fromJson({
        'id': 'e1', 'kind': 'entry', 'title': 'Fest',
        'date': DateTime.now().toIso8601String(),
        'categoryName': 'Event', 'categoryIcon': 'event', 'categoryColor': '#DC2626',
        'rsvps': const ['someone', 'me'],
      });
      expect(going.isMine('me'), isTrue);
    });

    test('signed out, nothing is mine', () {
      expect(deadline(assignedTo: 'me').isMine(null), isFalse);
    });
  });

  group('design system', () {
    test('numbers use tabular figures so live counters do not jitter', () {
      expect(
        GwdType.numeric.fontFeatures!.any((f) => f.feature == 'tnum'),
        isTrue,
        reason: 'points and counts update live and must not reflow',
      );
    });

    test('light and dark themes are both defined', () {
      expect(GwdTheme.light().brightness, Brightness.light);
      expect(GwdTheme.dark().brightness, Brightness.dark);
    });
  });

  group('widgets', () {
    testWidgets('empty states render a title and message, not a spinner',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: EmptyState(
            icon: Icons.inbox_outlined,
            title: 'No tasks for you',
            message: 'When someone assigns you work, it appears here.',
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('No tasks for you'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('every role renders a badge', (tester) async {
      for (final role in ClubRole.values) {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: RoleBadge(role: role)),
        ));
        await tester.pumpAndSettle();
        expect(find.text(role.badge), findsOneWidget, reason: role.name);
      }
    });

    testWidgets('primary button reports busy state instead of staying tappable',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PrimaryButton(label: 'Assign', busy: true, onPressed: () => taps++),
        ),
      ));
      await tester.pump();
      await tester.tap(find.byType(PrimaryButton));
      await tester.pump();
      expect(taps, 0, reason: 'a busy button must not fire twice');
    });
  });
}
