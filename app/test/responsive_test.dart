import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gwd_club_os/app/app_scope.dart';
import 'package:gwd_club_os/app/theme/gwd_theme.dart';
import 'package:gwd_club_os/core/api/api_client.dart';
import 'package:gwd_club_os/core/api/socket_client.dart';
import 'package:gwd_club_os/core/state/club_store.dart';
import 'package:gwd_club_os/core/state/session.dart';
import 'package:gwd_club_os/features/alerts/alerts_page.dart';
import 'package:gwd_club_os/features/alerts/send_alert_sheet.dart';
import 'package:gwd_club_os/features/analytics/analytics_page.dart';
import 'package:gwd_club_os/features/approvals/approvals_page.dart';
import 'package:gwd_club_os/features/auth/change_password_sheet.dart';
import 'package:gwd_club_os/features/auth/pending_page.dart';
import 'package:gwd_club_os/features/auth/sign_in_page.dart';
import 'package:gwd_club_os/features/auth/sign_up_page.dart';
import 'package:gwd_club_os/features/club/structure_page.dart';
import 'package:gwd_club_os/features/departments/department_workspace_page.dart';
import 'package:gwd_club_os/features/departments/departments_page.dart';
import 'package:gwd_club_os/features/directory/directory_page.dart';
import 'package:gwd_club_os/features/events/create_event_flow.dart';
import 'package:gwd_club_os/features/events/event_day_page.dart';
import 'package:gwd_club_os/features/events/event_report_page.dart';
import 'package:gwd_club_os/features/events/event_templates_page.dart';
import 'package:gwd_club_os/features/events/event_workspace_page.dart';
import 'package:gwd_club_os/features/help/ask_for_help_sheet.dart';
import 'package:gwd_club_os/features/help/help_page.dart';
import 'package:gwd_club_os/features/leaderboard/leaderboard_page.dart';
import 'package:gwd_club_os/features/leaderboard/member_stats_page.dart';
import 'package:gwd_club_os/features/leaderboard/my_overview_page.dart';
import 'package:gwd_club_os/features/meetings/meeting_detail_page.dart';
import 'package:gwd_club_os/features/meetings/meetings_page.dart';
import 'package:gwd_club_os/features/meetings/new_meeting_sheet.dart';
import 'package:gwd_club_os/features/profile/profile_sheet.dart';
import 'package:gwd_club_os/features/schedule/category_admin_page.dart';
import 'package:gwd_club_os/features/schedule/schedule_page.dart';
import 'package:gwd_club_os/features/search/search_page.dart';
import 'package:gwd_club_os/features/tasks/ask_for_work_sheet.dart';
import 'package:gwd_club_os/features/tasks/new_task_sheet.dart';
import 'package:gwd_club_os/features/tasks/task_detail_page.dart';
import 'package:gwd_club_os/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Every screen, at every size the club will actually hold it.
///
/// "Responsive" is only a claim until something renders the app at 320 wide
/// with a long name in it and looks. This does, against responses recorded
/// from a real server (test/fixtures, stuffed with long names on purpose), for
/// the three kinds of account that see different screens - and fails on any
/// overflow, the yellow-and-black stripe that means text or a row does not fit.
///
/// Re-record the fixtures with the QA server whenever an API shape changes.

class _FakeApi extends ApiClient {
  _FakeApi(this.responses) : super(baseUrlProvider: () => 'http://test.invalid');
  final Map<String, dynamic> responses;

  Map<String, dynamic> _lookup(String path, Map<String, dynamic>? query) {
    final q = (query == null || query.isEmpty)
        ? ''
        : '?${query.entries.map((e) => '${e.key}=${e.value}').join('&')}';
    final hit = responses['$path$q'] ?? responses[path];
    if (hit is! Map) return <String, dynamic>{};
    return (jsonDecode(jsonEncode(hit)) as Map).cast<String, dynamic>();
  }

  @override
  Future<Map<String, dynamic>> get(String path,
          {Map<String, dynamic>? query, Duration? timeout}) async =>
      _lookup(path, query);

  @override
  Future<Map<String, dynamic>> post(String path,
          [Map<String, dynamic>? body, Duration? timeout]) async =>
      <String, dynamic>{};

  @override
  Future<Map<String, dynamic>> patch(String path, [Map<String, dynamic>? body]) async =>
      <String, dynamic>{};

  @override
  Future<Map<String, dynamic>> put(String path, [Map<String, dynamic>? body]) async =>
      <String, dynamic>{};

  @override
  Future<Map<String, dynamic>> delete(String path, [Map<String, dynamic>? body]) async =>
      <String, dynamic>{};
}

class _NoSocket extends SocketClient {
  _NoSocket() : super(baseUrlProvider: () => '');
  @override
  void connect(String token) {}
  @override
  void disconnect() {}
}

class _Fixture {
  _Fixture(this.role, Map<String, dynamic> json)
      : user = (json['user'] as Map).cast<String, dynamic>(),
        responses = (json['responses'] as Map).cast<String, dynamic>();
  final String role;
  final Map<String, dynamic> user;
  final Map<String, dynamic> responses;

  static _Fixture load(String role) => _Fixture(
      role, jsonDecode(File('test/fixtures/$role.json').readAsStringSync()) as Map<String, dynamic>);

  List<Map<String, dynamic>> list(String path, String key) =>
      ((responses[path] as Map?)?[key] as List? ?? const [])
          .cast<Map>()
          .map((m) => m.cast<String, dynamic>())
          .toList();
}

Future<ClubStore> _storeFor(_Fixture fixture) async {
  SharedPreferences.setMockInitialValues({});
  final session = Session(api: _FakeApi(fixture.responses));
  await session.adoptToken('test-token', user: fixture.user);
  final store = ClubStore(session: session, socket: _NoSocket());
  await store.loadAll();
  return store;
}

class _Size {
  const _Size(this.name, this.width, this.height, {this.text = 1.0});
  final String name;
  final double width;
  final double height;
  final double text;
}

const _sizes = [
  _Size('small phone 320x568', 320, 568),
  _Size('android 360x740', 360, 740),
  _Size('iphone 393x852', 393, 852),
  _Size('pro max 430x932', 430, 932),
  _Size('phone landscape 844x390', 844, 390),
  _Size('tablet 768x1024', 768, 1024),
  _Size('tablet landscape 1024x768', 1024, 768),
  _Size('laptop 1440x900', 1440, 900),
  _Size('desktop 1920x1080', 1920, 1080),
  _Size('android 360x740 at 1.5x text', 360, 740, text: 1.5),
  _Size('iphone 393x852 at 2x text', 393, 852, text: 2.0),
];

/// The sizes detail pages and sheets are checked at: the extremes and the
/// most common, rather than every size again.
const _detailSizes = [
  _Size('small phone 320x568', 320, 568),
  _Size('iphone 393x852', 393, 852),
  _Size('phone landscape 844x390', 844, 390),
  _Size('tablet 768x1024', 768, 1024),
  _Size('laptop 1440x900', 1440, 900),
  _Size('android 360x740 at 1.5x text', 360, 740, text: 1.5),
];

void _setSize(WidgetTester tester, _Size size) {
  tester.view.physicalSize = Size(size.width * 2, size.height * 2);
  tester.view.devicePixelRatio = 2;
  tester.platformDispatcher.textScaleFactorTestValue = size.text;
}

void _reset(WidgetTester tester) {
  tester.view.resetPhysicalSize();
  tester.view.resetDevicePixelRatio();
  tester.platformDispatcher.clearTextScaleFactorTestValue();
  tester.platformDispatcher.clearPlatformBrightnessTestValue();
}

/// Frames, not pumpAndSettle: loaders and live-event dots animate for as long
/// as they are on screen, so "settled" never comes.
Future<void> _frames(WidgetTester tester, [int ms = 900]) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Scroll every vertical list on screen to its end, so rows that are only
/// built when scrolled to are laid out and checked too.
Future<void> _scrollThrough(WidgetTester tester) async {
  final scrollables = find.byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.down);
  final count = scrollables.evaluate().length;
  for (var i = 0; i < count && i < 3; i++) {
    final target = scrollables.at(i);
    if (target.evaluate().isEmpty) continue;
    for (var step = 0; step < 6; step++) {
      await tester.drag(target, const Offset(0, -900), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 120));
    }
  }
  await _frames(tester, 300);
}

/// AppScope above the MaterialApp, as in the real app: sheets open on the root
/// navigator, which a scope inside `home` does not cover.
Widget _host(ClubStore store, Widget child) => AppScope(
      session: store.session,
      store: store,
      child: MaterialApp(
        theme: GwdTheme.light(),
        darkTheme: GwdTheme.dark(),
        themeMode: ThemeMode.dark,
        home: child,
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    // Plugins with nothing behind them in a test.
    for (final name in ['home_widget', 'plugins.flutter.io/url_launcher', 'flutter.baseflow.com/permissions/methods']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(name), (call) async => null);
    }
  });

  final roles = ['super', 'lead', 'member'];

  for (final role in roles) {
    group('$role account', () {
      for (final size in _sizes) {
        testWidgets('every tab fits on a ${size.name}', (tester) async {
          final fixture = _Fixture.load(role);
          final problems = <String>[];
          final original = FlutterError.onError;
          FlutterError.onError = (details) {
            final line = details.exceptionAsString().split('\n').first;
            if (Platform.environment['GWD_DEBUG_LAYOUT'] != null && !problems.contains(line)) {
              // ignore: avoid_print
              print('----- $line\n${details.toString().split('\n').take(70).join('\n')}');
            }
            problems.add(line);
          };
          final semantics = tester.ensureSemantics();
          try {
            _setSize(tester, size);
            tester.platformDispatcher.platformBrightnessTestValue =
                size.width == 393 ? Brightness.light : Brightness.dark;
            final store = await _storeFor(fixture);
            await tester.pumpWidget(GwdClubApp(session: store.session, store: store));
            await _frames(tester, 1500);

            for (final tab in ['Home', 'Events', 'Work', 'Departments', 'More']) {
              final before = problems.length;
              final button = find.bySemanticsLabel(RegExp('^$tab'));
              if (button.evaluate().isNotEmpty) {
                await tester.tap(button.first, warnIfMissed: false);
              }
              await _frames(tester, 700);
              await _scrollThrough(tester);
              for (var i = before; i < problems.length; i++) {
                problems[i] = '[$tab] ${problems[i]}';
              }
            }
            await tester.pumpWidget(const SizedBox());
            await _frames(tester, 300);
          } finally {
            FlutterError.onError = original;
            semantics.dispose();
            _reset(tester);
          }
          expect(problems.toSet().toList(), isEmpty, reason: '$role on ${size.name}');
        });
      }

      testWidgets('every detail page and sheet fits', (tester) async {
        final fixture = _Fixture.load(role);
        final problems = <String>{};
        final original = FlutterError.onError;
        var current = '';
        FlutterError.onError = (details) {
          final line = '$current: ${details.exceptionAsString().split('\n').first}';
          if (Platform.environment['GWD_DEBUG_LAYOUT'] != null && !problems.contains(line)) {
            // ignore: avoid_print
            print('----- $line\n${details.toString().split('\n').take(70).join('\n')}');
          }
          problems.add(line);
        };
        try {
          final events = [
            ...fixture.list('/api/events', 'upcoming'),
            ...fixture.list('/api/events', 'ongoing'),
            ...fixture.list('/api/events', 'past'),
          ];
          final departments = fixture.list('/api/departments', 'departments');
          final users = fixture.list('/api/users', 'users');
          final meetings = [
            ...fixture.list('/api/meetings', 'upcoming'),
            ...fixture.list('/api/meetings', 'past'),
          ];
          final tasks = fixture.list('/api/tasks?scope=mine', 'tasks').isNotEmpty
              ? fixture.list('/api/tasks?scope=mine', 'tasks')
              : fixture.list('/api/tasks', 'tasks');

          final pages = <String, Widget Function()>{
            'Directory': () => const DirectoryPage(),
            'Structure': () => const StructurePage(),
            'Recognition': () => const LeaderboardPage(),
            'What I handed out': () => const MyOverviewPage(),
            'Schedule': () => const SchedulePage(),
            'Meetings': () => const MeetingsPage(),
            'Help': () => const HelpPage(),
            'Alerts': () => const AlertsPage(),
            'Approvals': () => const ApprovalsPage(),
            'Dashboard': () => const AnalyticsPage(),
            'Templates': () => const EventTemplatesPage(),
            'Manage departments': () => const DepartmentsPage(),
            'Categories': () => const CategoryAdminPage(),
            'Search': () => const SearchPage(),
            'Sign in': () => const SignInPage(),
            'Sign up': () => const SignUpPage(),
            'Pending': () => const PendingApprovalPage(),
            for (final e in events.take(2)) ...{
              'Event ${e['name']}': () => EventWorkspacePage(eventId: e['id'] as String),
              'Event day ${e['name']}': () => EventDayPage(eventId: e['id'] as String),
              'Event report ${e['name']}': () => EventReportPage(eventId: e['id'] as String),
            },
            for (final d in departments.take(2))
              'Department ${d['name']}': () => DepartmentWorkspacePage(departmentId: d['id'] as String),
            for (final u in users.take(4))
              'Member ${u['name']}': () => MemberStatsPage(userId: u['id'] as String),
            for (final m in meetings.take(2))
              'Meeting ${m['title']}': () => MeetingDetailPage(meetingId: m['id'] as String),
            for (final t in tasks.take(3))
              'Task ${t['title']}': () => TaskDetailPage(taskId: t['id'] as String),
          };

          final sheets = <String, Future<void> Function(BuildContext)>{
            'New task sheet': showNewTaskSheet,
            'Ask for work sheet': showAskForWorkSheet,
            'Ask for help sheet': (c) => showAskForHelpSheet(c),
            'Send alert sheet': showSendAlertSheet,
            'New meeting sheet': showNewMeetingSheet,
            'Profile sheet': showProfileSheet,
            'Forgot password sheet': (c) => showForgotPasswordSheet(c),
            'Create event': CreateEventFlow.open,
          };

          for (final size in _detailSizes) {
            _setSize(tester, size);
            final store = await _storeFor(fixture);

            for (final entry in pages.entries) {
              current = '${entry.key} @ ${size.name}';
              await tester.pumpWidget(_host(store, entry.value()));
              await _frames(tester, 800);
              // Every tab of a tabbed page, not only the first.
              final tabs = find.byType(Tab);
              final tabCount = tabs.evaluate().length;
              for (var i = 0; i < tabCount; i++) {
                current = '${entry.key} (tab ${i + 1}) @ ${size.name}';
                await tester.tap(tabs.at(i), warnIfMissed: false);
                await _frames(tester, 500);
                await _scrollThrough(tester);
              }
              if (tabCount == 0) await _scrollThrough(tester);
            }

            for (final entry in sheets.entries) {
              current = '${entry.key} @ ${size.name}';
              late BuildContext context;
              await tester.pumpWidget(_host(store, Scaffold(body: Builder(builder: (c) {
                context = c;
                return const SizedBox.expand();
              }))));
              await tester.pump();
              // Not awaited: the sheet stays open while it is checked.
              // ignore: unawaited_futures
              entry.value(context);
              await _frames(tester, 900);
              await _scrollThrough(tester);
            }
            await tester.pumpWidget(const SizedBox());
            await _frames(tester, 300);
          }
        } finally {
          FlutterError.onError = original;
          _reset(tester);
        }
        expect(problems.toList(), isEmpty, reason: '$role detail pages');
      });
    });
  }
}
