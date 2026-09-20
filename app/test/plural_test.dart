import 'package:flutter_test/flutter_test.dart';
import 'package:gwd_club_os/core/plural.dart';

void main() {
  // "1 people" shipped on the Recognition screen, four times on one page. It
  // is the kind of thing that makes an app feel unfinished, and every screen
  // had grown its own inline ternary rather than sharing one.
  group('countOf', () {
    test('counts one thing', () {
      expect(countOf(1, 'task'), '1 task');
      expect(countOf(1, 'department'), '1 department');
    });

    test('counts several', () {
      expect(countOf(0, 'task'), '0 tasks');
      expect(countOf(2, 'task'), '2 tasks');
      expect(countOf(47, 'member'), '47 members');
    });

    test('takes an irregular plural when the rule does not fit', () {
      expect(countOf(1, 'person', 'people'), '1 person');
      expect(countOf(3, 'person', 'people'), '3 people');
    });
  });

  group('people', () {
    test('never says "1 people"', () {
      expect(people(1), '1 person');
      expect(people(0), '0 people');
      expect(people(14), '14 people');
    });
  });
}
