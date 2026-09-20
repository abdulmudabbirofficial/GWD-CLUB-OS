import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gwd_club_os/app/app_scope.dart';
import 'package:gwd_club_os/core/api/socket_client.dart';
import 'package:gwd_club_os/core/models/club_task.dart';
import 'package:gwd_club_os/core/state/club_store.dart';
import 'package:gwd_club_os/core/state/session.dart';

/// A store that can be nudged without a server behind it.
///
/// `notifyListeners` is protected, which is the right call for a class every
/// screen listens to — a subclass is how a test is meant to reach it.
class _TestStore extends ClubStore {
  _TestStore()
      : super(
          session: Session(),
          // Never connected. Constructing one is enough: the store only
          // subscribes to its stream, and nothing here emits.
          socket: SocketClient(baseUrlProvider: () => ''),
        );

  void bump() => notifyListeners();
}

ClubTask _task(String id) => ClubTask.fromJson({
      'id': id,
      'title': 'Task $id',
      'status': 'pending',
    });

void main() {
  // ---------------------------------------------------------------------
  // WHO REBUILDS WHEN
  // ---------------------------------------------------------------------
  //
  // `ClubStore` notifies from around sixty places and a live club fires those
  // constantly. Every widget using `AppScope.storeOf` rebuilds on all of them,
  // which is why one comment on somebody else's task was redrawing the whole
  // of Home. These pin the narrower subscription that replaced it.
  group('StoreSelector', () {
    late _TestStore store;

    Widget host(Widget child) => MaterialApp(
          home: AppScope(session: store.session, store: store, child: child),
        );

    setUp(() => store = _TestStore());
    tearDown(() => store.dispose());

    testWidgets('does not rebuild when the value it watches is unchanged',
        (tester) async {
      var builds = 0;
      await tester.pumpWidget(host(
        StoreSelector<int>(
          pick: (s) => s.tasks.length,
          builder: (_, value) {
            builds += 1;
            return Text('$value', textDirection: TextDirection.ltr);
          },
        ),
      ));
      expect(builds, 1);

      // Three notifications that change nothing this widget is looking at —
      // the shape of every live event about somebody else's work.
      store.bump();
      store.bump();
      store.bump();
      await tester.pump();

      expect(builds, 1, reason: 'an unrelated store change must not rebuild it');
    });

    testWidgets('rebuilds exactly once when the value changes', (tester) async {
      var builds = 0;
      await tester.pumpWidget(host(
        StoreSelector<int>(
          pick: (s) => s.tasks.length,
          builder: (_, value) {
            builds += 1;
            return Text('$value', textDirection: TextDirection.ltr);
          },
        ),
      ));
      expect(builds, 1);
      expect(find.text('0'), findsOneWidget);

      store.tasks = [_task('a'), _task('b')];
      store.bump();
      await tester.pump();

      expect(builds, 2);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('a record of counts compares by value, not identity',
        (tester) async {
      // The nav badges watch a record. If records compared by identity this
      // would rebuild on every notification and the whole exercise would be
      // pointless, so it is worth pinning.
      var builds = 0;
      await tester.pumpWidget(host(
        StoreSelector<({int open, int unread})>(
          pick: (s) => (
            open: s.tasks.where((t) => t.status.isOpen).length,
            unread: s.unreadNotifications,
          ),
          builder: (_, value) {
            builds += 1;
            return Text('${value.open}', textDirection: TextDirection.ltr);
          },
        ),
      ));
      expect(builds, 1);

      store.bump();
      await tester.pump();
      expect(builds, 1, reason: 'equal records must compare equal');

      store.tasks = [_task('a')];
      store.bump();
      await tester.pump();
      expect(builds, 2);
    });

    testWidgets('stops listening when it leaves the tree', (tester) async {
      var builds = 0;
      Widget selector() => StoreSelector<int>(
            pick: (s) => s.tasks.length,
            builder: (_, value) {
              builds += 1;
              return Text('$value', textDirection: TextDirection.ltr);
            },
          );

      await tester.pumpWidget(host(selector()));
      expect(builds, 1);

      await tester.pumpWidget(host(const SizedBox.shrink()));
      store.tasks = [_task('a')];
      store.bump();
      await tester.pump();

      expect(builds, 1, reason: 'a disposed selector must not rebuild');
    });
  });
}
