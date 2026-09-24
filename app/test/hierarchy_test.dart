import 'package:flutter_test/flutter_test.dart';
import 'package:gwd_club_os/core/models/club_role.dart';
import 'package:gwd_club_os/core/models/member.dart';

/// How the club's people are named. V8 is specific about this, and every one of
/// these is a label somebody complained about.
void main() {
  Member director(String name, String? knownAs, {bool superAdmin = false}) =>
      Member.fromJson({
        'id': name,
        'name': name,
        'role': 'clubDirector',
        'knownAs': knownAs,
        'superAdmin': superAdmin,
      });

  group('the Directors', () {
    final mudabbir = director('Abdul Mudabbir', 'Mudabbir', superAdmin: true);
    final rehman = director('Rehman Pasha', 'Rehman');
    final moin = director('Mohammed Moin', 'Moin');

    test('are addressed by title and the name the club knows them by', () {
      expect(mudabbir.displayName, 'Director Mudabbir');
      expect(rehman.displayName, 'Director Rehman');
      expect(moin.displayName, 'Director Moin');
    });

    test('the short name is stored, because it cannot be derived', () {
      // Last word of one name, first word of another. Guessing either way gets
      // one of them wrong.
      expect(mudabbir.firstName, 'Mudabbir');
      expect(rehman.firstName, 'Rehman');
    });

    test('only the Super Admin carries the longer title', () {
      expect(mudabbir.positionLine(null), 'Club Director · Super Admin');
      expect(rehman.positionLine(null), 'Director');
      expect(moin.positionLine(null), 'Director');
    });

    test('never "Club Director" for the other two, and never a number', () {
      for (final m in [rehman, moin]) {
        expect(m.positionLine(null), isNot(contains('Club Director')));
        expect(m.displayName, isNot(matches(RegExp(r'\d'))));
      }
    });

    test('a Director without a known-as name still reads as a person', () {
      final unnamedShort = director('Abdul Mudabbir', null);
      expect(unnamedShort.displayName, 'Abdul Mudabbir');
    });

    test('a placeholder is never passed off as a person, Director or not', () {
      final placeholder = Member.fromJson(const {
        'id': 'x',
        'name': 'Club Director Three',
        'role': 'clubDirector',
        'knownAs': 'Three',
        'mustSetName': true,
      });
      expect(placeholder.displayName, 'No name set');
      // And no initials made from the placeholder: "Faculty Coordinator" came
      // out as "FC" on the avatar beside "No name set".
      expect(placeholder.initials, '?');
    });

    test('the flags survive copyWith, which rebuilds the member field by field', () {
      final renamed = mudabbir.copyWith(points: 3);
      expect(renamed.superAdmin, isTrue);
      expect(renamed.knownAs, 'Mudabbir');
      expect(renamed.displayName, 'Director Mudabbir');
    });

    test('knownAs means nothing on anybody who is not a Director', () {
      final president = Member.fromJson(const {
        'id': 'p', 'name': 'Aldrin Paul', 'role': 'president', 'knownAs': 'Aldrin',
      });
      expect(president.displayName, 'Aldrin Paul');
    });
  });

  group('office titles', () {
    test('General Secretary, consistently', () {
      expect(ClubRole.secretaryGeneral.title, 'General Secretary');
      expect(ClubRole.secretaryGeneral.address, 'General Secretary');
      expect(ClubRole.secretaryGeneral.badge, 'GEN SEC');
    });

    test('a Director is a Director', () {
      expect(ClubRole.clubDirector.title, 'Director');
    });

    test('the President is the President, not "Club President"', () {
      expect(ClubRole.president.title, 'President');
    });
  });
}
