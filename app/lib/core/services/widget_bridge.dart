import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

/// Bridge to the native home-screen widgets (Section 7).
///
/// Flutter cannot draw OS launcher widgets itself, so this writes shared data
/// that a native Android Glance/RemoteViews provider and an iOS WidgetKit
/// extension read and render.
///
/// A note on the honest expectation gap between platforms:
///   * Android can be nudged to redraw almost immediately, so the widget tracks
///     the app closely.
///   * iOS meters widget refreshes through WidgetKit's timeline budget —
///     typically 15–30 minutes, or on a push. It is *not* real-time, and the
///     brief is explicit that we should not promise otherwise.
class WidgetBridge {
  const WidgetBridge._();

  /// Must match the Android provider class and the iOS App Group / kind.
  static const _androidProvider = 'GwdClubWidgetProvider';
  static const _iosWidgetKind = 'GwdClubWidget';
  static const _appGroupId = 'group.com.gwd.clubos';

  static bool _initialised = false;

  static Future<void> _ensureInit() async {
    if (_initialised) return;
    try {
      await HomeWidget.setAppGroupId(_appGroupId);
      _initialised = true;
    } catch (_) {
      // Not fatal — on platforms without widget support this is a no-op and
      // the app must carry on completely unaffected.
    }
  }

  /// Publish the compact snapshot the widget renders:
  /// "3 tasks pending · next due 4 PM today".
  static Future<void> publish({
    required int pendingCount,
    String? nextTitle,
    String? nextDue,
  }) async {
    if (kIsWeb) return; // no launcher widgets on the web
    try {
      await _ensureInit();
      await Future.wait([
        HomeWidget.saveWidgetData<int>('pendingCount', pendingCount),
        HomeWidget.saveWidgetData<String>('nextTitle', nextTitle ?? ''),
        HomeWidget.saveWidgetData<String>('nextDue', nextDue ?? ''),
        HomeWidget.saveWidgetData<String>(
          'updatedAt',
          DateTime.now().toIso8601String(),
        ),
      ]);
      await HomeWidget.updateWidget(
        androidName: _androidProvider,
        iOSName: _iosWidgetKind,
      );
    } catch (error) {
      debugPrint('[widget] update skipped: $error');
    }
  }

  /// Clear the widget on sign-out so a signed-out phone is not left showing
  /// the previous member's workload on its home screen.
  static Future<void> clear() => publish(pendingCount: 0, nextTitle: '', nextDue: '');
}
