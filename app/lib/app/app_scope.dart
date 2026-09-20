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

  /// Watch **one slice** of the store.
  ///
  /// [storeOf] subscribes to the whole thing, which is fine for a screen that
  /// genuinely redraws whenever anything changes and wrong for everything else.
  /// `ClubStore` notifies from sixty-odd places and a live club fires those
  /// constantly, so a widget showing a single number was being rebuilt by
  /// somebody else's comment on somebody else's task.
  ///
  /// Use this where a widget shows a small, nameable part of the store. Leave
  /// [storeOf] where a screen really does depend on most of it — narrowing a
  /// subscription that was already correct buys nothing and costs a comparison.
  ///
  /// [pick] must return something with a meaningful `==`: a number, a string, a
  /// record of those. Returning a `List` compares by identity and will rebuild
  /// every time regardless, which is the one way to use this and gain nothing.
  static Widget select<T>(
    BuildContext context,
    T Function(ClubStore store) pick,
    Widget Function(BuildContext context, T value) build,
  ) {
    return StoreSelector<T>(pick: pick, builder: build);
  }

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

/// Rebuilds its subtree only when the value it picks out of the store changes.
///
/// The counterpart to [AppScope.storeOf], for widgets that depend on a slice
/// rather than on everything. It listens to the store directly instead of
/// through the inherited scope, so it is unaffected by — and does not
/// participate in — the tree-wide rebuild that `storeOf` subscribers get.
class StoreSelector<T> extends StatefulWidget {
  const StoreSelector({super.key, required this.pick, required this.builder});

  final T Function(ClubStore store) pick;
  final Widget Function(BuildContext context, T value) builder;

  @override
  State<StoreSelector<T>> createState() => _StoreSelectorState<T>();
}

class _StoreSelectorState<T> extends State<StoreSelector<T>> {
  ClubStore? _store;
  late T _value;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = AppScope.readStore(context);
    if (identical(store, _store)) return;
    _store?.removeListener(_onChanged);
    _store = store..addListener(_onChanged);
    _value = widget.pick(store);
  }

  @override
  void didUpdateWidget(StoreSelector<T> old) {
    super.didUpdateWidget(old);
    // The closure is usually rebuilt with the parent, so re-read through the
    // new one rather than trusting a value picked by the old one.
    final store = _store;
    if (store != null) _value = widget.pick(store);
  }

  void _onChanged() {
    final store = _store;
    if (store == null || !mounted) return;
    final next = widget.pick(store);
    if (next == _value) return;
    setState(() => _value = next);
  }

  @override
  void dispose() {
    _store?.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _value);
}
