import 'package:flutter_test/flutter_test.dart';
import 'package:gwd_club_os/core/models/event_day.dart';
import 'package:gwd_club_os/core/models/event_report.dart';
import 'package:gwd_club_os/core/models/event_template.dart';

/// The three surfaces an event grows once a club runs the same thing twice:
/// a saved shape to start from, a run sheet for the day, and an account of
/// what happened afterwards.
///
/// The logic worth testing here is all derivation — what is on *now*, what a
/// `-14` offset means in words, what a deadline resolves to against a real
/// date. None of it involves the server, and all of it is the sort of thing
/// that quietly goes wrong at a boundary.
void main() {
  EventDay dayWith(List<Map<String, dynamic>> rows) => EventDay.fromJson({
        'event': {
          'id': 'e1',
          'name': 'Guest Lecture',
          'date': DateTime.now().toIso8601String(),
          'status': 'ongoing',
        },
        'runSheet': rows,
      });

  Map<String, dynamic> row(String id, String time, String title,
          {bool done = false}) =>
      {'id': id, 'time': time, 'title': title, 'done': done};

  group('run sheet times', () {
    test('a time parses to minutes past midnight', () {
      final item = RunSheetItem.fromJson(row('a', '09:05', 'Doors'));
      expect(item.timed, isTrue);
      expect(item.minutes, 545);
    });

    test('an untimed row has no minutes rather than a sentinel', () {
      // A zero here would sort it as midnight, which is the top of the list —
      // exactly where an "at some point" job must not appear.
      final item = RunSheetItem.fromJson(row('a', '', 'Tidy the hall'));
      expect(item.timed, isFalse);
      expect(item.minutes, isNull);
      expect(item.clockLabel, '');
    });

    test('the clock reads as a time, not a duration', () {
      String label(String wire) => RunSheetItem.fromJson(row('a', wire, 'x')).clockLabel;
      expect(label('09:05'), '9:05 am');
      expect(label('13:00'), '1:00 pm');
      // The two that a twelve-hour clock always gets wrong.
      expect(label('00:30'), '12:30 am');
      expect(label('12:00'), '12:00 pm');
    });
  });

  group('what is on now', () {
    final day = dayWith([
      row('a', '09:00', 'Doors open'),
      row('b', '10:00', 'Speaker on'),
      row('c', '16:00', 'Pack down'),
      row('d', '', 'Return the mics'),
    ]);

    DateTime at(int hour, int minute) => DateTime(2026, 3, 12, hour, minute);

    test('before the first item nothing is current, but something is next', () {
      expect(day.currentAt(at(8, 0)), isNull);
      expect(day.nextAt(at(8, 0))?.title, 'Doors open');
    });

    test('the last item whose time has passed is the current one', () {
      expect(day.currentAt(at(10, 30))?.title, 'Speaker on');
      expect(day.nextAt(at(10, 30))?.title, 'Pack down');
    });

    test('an item that overruns stays current rather than the screen jumping on', () {
      // 15:59 is nearly six hours after the speaker started. The screen still
      // says "Speaker on", because nothing after it has begun — jumping ahead
      // to "Pack down" would tell the person in the room something untrue.
      expect(day.currentAt(at(15, 59))?.title, 'Speaker on');
    });

    test('after the last item there is nothing next', () {
      expect(day.currentAt(at(23, 0))?.title, 'Pack down');
      expect(day.nextAt(at(23, 0)), isNull);
    });

    test('untimed rows are never current and never next', () {
      for (var hour = 0; hour < 24; hour++) {
        expect(day.currentAt(at(hour, 0))?.title, isNot('Return the mics'));
        expect(day.nextAt(at(hour, 0))?.title, isNot('Return the mics'));
      }
      expect(day.anytime.map((i) => i.title), ['Return the mics']);
      expect(day.scheduled.length, 3);
    });
  });

  group('template offsets', () {
    TemplateTask task(int? offset) =>
        TemplateTask.fromJson({'title': 'Book the hall', 'offsetDays': offset});

    test('an offset reads as the phrase a person would use', () {
      // "-14" is a number you have to decode; the whole reason templates store
      // an offset instead of a date is that it still makes sense next term.
      expect(task(-14).whenLabel, '14 days before');
      expect(task(-1).whenLabel, '1 day before');
      expect(task(0).whenLabel, 'On the day');
      expect(task(2).whenLabel, '2 days after');
      expect(task(null).whenLabel, 'No deadline');
    });

    test('an offset resolves against a real event date', () {
      final event = DateTime(2026, 3, 15, 18, 30);
      expect(task(-14).dueFor(event), DateTime(2026, 3, 1));
      expect(task(0).dueFor(event), DateTime(2026, 3, 15));
      expect(task(2).dueFor(event), DateTime(2026, 3, 17));
    });

    test('it crosses a month and a year boundary correctly', () {
      expect(task(-14).dueFor(DateTime(2026, 1, 5)), DateTime(2025, 12, 22));
      // 2028 is a leap year: fourteen days before 1 March is 16 February.
      expect(task(-14).dueFor(DateTime(2028, 3, 1)), DateTime(2028, 2, 16));
    });

    test('a task with no offset keeps no deadline', () {
      // Inventing "the day of" would put a deadline on work that deliberately
      // had none.
      expect(task(null).dueFor(DateTime(2026, 3, 15)), isNull);
    });

    test('usage reads honestly rather than as "used 0 times"', () {
      EventTemplate withUses(int n) =>
          EventTemplate.fromJson({'id': 't1', 'name': 'Workshop', 'usageCount': n});
      expect(withUses(0).usageLabel, 'Not used yet');
      expect(withUses(1).usageLabel, 'Used once');
      expect(withUses(4).usageLabel, 'Used 4 times');
    });
  });

  group('report figures', () {
    test('a completion rate of nothing is nought, not a division by zero', () {
      expect(const EventReportFigures().completionRate, 0);
    });

    test('and otherwise rounds', () {
      expect(
        const EventReportFigures(taskCount: 3, taskCompleted: 2).completionRate,
        67,
      );
    });

    test('an absent report is absent, not an empty one', () {
      // The difference matters: no report means "nobody has written this up",
      // and an empty one would read as "it went fine".
      final none = EventReport.fromJson({
        'event': {'id': 'e1', 'name': 'x', 'date': DateTime.now().toIso8601String()},
        'derived': const <String, dynamic>{},
      });
      expect(none.entry, isNull);
      expect(none.written, isFalse);
    });

    test('a report with only blank answers still does not count as written', () {
      final blank = EventReport.fromJson({
        'event': {'id': 'e1', 'name': 'x', 'date': DateTime.now().toIso8601String()},
        'derived': const <String, dynamic>{},
        'report': const {'highlights': '', 'challenges': '', 'learnings': ''},
      });
      expect(blank.written, isFalse);
    });

    test('an attendance of zero is an answer, not a blank', () {
      // Somebody recording that nobody turned up is information. It must not
      // be swallowed by a null check.
      final entry = EventReportEntry.fromJson(const {'attendance': 0});
      expect(entry.attendance, 0);
      expect(entry.isEmpty, isFalse);
    });
  });

  group('the day team', () {
    test('a phone number the server withheld is simply absent', () {
      final member = DayTeamMember.fromJson(const {
        'id': 'u1', 'name': 'Asha', 'role': 'clubLead', 'phone': '',
      });
      expect(member.phone, isEmpty);
    });

    test('an account with no name set reads as such, never as its raw name', () {
      final member = DayTeamMember.fromJson(const {
        'id': 'u1', 'name': 'Marketing Lead', 'role': 'clubLead', 'mustSetName': true,
      });
      expect(member.displayName, 'No name set');
      expect(member.isUnnamed, isTrue);
      expect(member.initials, '?');
    });

    test('and one that has shows its own initials', () {
      final member = DayTeamMember.fromJson(const {
        'id': 'u1', 'name': 'Asha Menon', 'role': 'clubMember',
      });
      expect(member.displayName, 'Asha Menon');
      expect(member.initials, 'AM');
    });
  });
}
