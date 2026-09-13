import 'package:flutter/widgets.dart';

import '../core/state/club_store.dart';
import '../core/state/session.dart';

/// Provides [Session] and [ClubStore] to the widget tree.
///
/// Deliberately hand-rolled rather than pulling in a state-management package:
/// two ChangeNotifiers is not enough surface to justify the dependency, and
/// this keeps the rebuild path obvious.
class AppScope extends StatefulWidget {
  const AppScope({
    super.key,
    required this.session,
    required this.store,
    required this.child,
  });

  final Session session;
  final ClubStore store;
  final Widget child;

  static _AppScopeState _stateOf(BuildContext context) {
    final state = context.findAncestorStateOfType<_AppScopeState>();
    assert(state != null, 'AppScope is missing from the widget tree.');
    return state!;
  }

  /// Read + subscribe. The widget rebuilds when the session changes.
  static Session sessionOf(BuildContext context) {
    context.dependOnInheritedWidgetOfExactType<_SessionScope>();
    return _stateOf(context).widget.session;
  }

  /// Read + subscribe. The widget rebuilds when any club data changes.
  static ClubStore storeOf(BuildContext context) {
    context.dependOnInheritedWidgetOfExactType<_StoreScope>();
    return _stateOf(context).widget.store;
  }

  /// Read without subscribing — for callbacks that only need to call methods.
  static ClubStore readStore(BuildContext context) => _stateOf(context).widget.store;
  static Session readSession(BuildContext context) => _stateOf(context).widget.session;

  @override
  State<AppScope> createState() => _AppScopeState();
}

class _AppScopeState extends State<AppScope> {
  int _sessionTick = 0;
  int _storeTick = 0;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_onSession);
    widget.store.addListener(_onStore);
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSession);
    widget.store.removeListener(_onStore);
    super.dispose();
  }

  void _onSession() {
    if (mounted) setState(() => _sessionTick++);
  }

  void _onStore() {
    if (mounted) setState(() => _storeTick++);
  }

  @override
  Widget build(BuildContext context) {
    return _SessionScope(
      tick: _sessionTick,
      child: _StoreScope(
        tick: _storeTick,
        child: widget.child,
      ),
    );
  }
}

class _SessionScope extends InheritedWidget {
  const _SessionScope({required this.tick, required super.child});
  final int tick;

  @override
  bool updateShouldNotify(_SessionScope oldWidget) => oldWidget.tick != tick;
}

class _StoreScope extends InheritedWidget {
  const _StoreScope({required this.tick, required super.child});
  final int tick;

  @override
  bool updateShouldNotify(_StoreScope oldWidget) => oldWidget.tick != tick;
}
