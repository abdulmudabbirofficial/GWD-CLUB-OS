import 'dart:async';
import 'dart:io' show File;

import 'package:flutter/foundation.dart';
// Color and IconData: the store resolves a category's look once, so every
// screen rendering it does not have to repeat the lookup.
import 'package:flutter/material.dart' show Color, IconData;
import 'package:path_provider/path_provider.dart';

import '../api/api_client.dart';
import '../api/socket_client.dart';
import '../models/app_notification.dart';
import '../models/club_alert.dart';
import '../models/club_event.dart';
import '../models/club_role.dart';
import '../models/club_task.dart';
import '../models/department.dart';
import '../models/event_bill.dart';
import '../models/event_day.dart';
import '../models/event_document.dart';
import '../models/event_report.dart';
import '../models/event_template.dart';
import '../models/help_request.dart';
import '../models/meeting.dart';
import '../models/member.dart';
import '../models/recognition.dart';
import '../models/schedule_category.dart';
import '../models/schedule_entry.dart';
import '../models/task_request.dart';
import '../services/widget_bridge.dart';
import 'session.dart';

/// What kind of thing a live toast is announcing.
enum ToastKind { taskAssigned, taskRequest, approval, alert, info }

/// A transient branded alert.
class LiveToast {
  LiveToast({
    required this.id,
    required this.title,
    required this.body,
    required this.kind,
    this.target = const NotificationTarget.none(),
    this.critical = false,
  });

  final String id;
  final String title;
  final String body;
  final ToastKind kind;

  /// Where tapping it goes. Previously this was a bare `taskId`, so a toast
  /// about anything other than a task was a dead tap.
  final NotificationTarget target;

  final bool critical;

  bool get opensSomething => target.kind != NotificationTargetKind.none;
}

/// What the compose sheet may offer, as the server sees it.
///
/// The leadership tier gets [departments] and no individuals; a Lead gets their
/// own members by name. The client renders this answer and never invents one.
class AssignmentTargets {
  const AssignmentTargets({
    required this.assignable,
    required this.requestable,
    required this.departments,
    required this.canAssignToDepartment,
    required this.pointValues,
    this.requestableDepartments = const [],
  });

  final List<Member> assignable;
  final List<Member> requestable;
  final List<AssignableDepartment> departments;
  final bool canAssignToDepartment;
  final List<int> pointValues;

  /// Departments a Lead may **ask** for a hand — everyone else's, never their
  /// own. "Technical needs Production on the stage rig" is how the work is
  /// described, so the ask is addressed to the department rather than to
  /// whichever person over there happens to be free.
  final List<AssignableDepartment> requestableDepartments;

  static const empty = AssignmentTargets(
    assignable: [],
    requestable: [],
    departments: [],
    canAssignToDepartment: false,
    pointValues: [1, 3, 5],
  );
}

int _n(Map<String, dynamic>? json, String key) => (json?[key] as num?)?.toInt() ?? 0;

/// The club, in aggregate, for the people running it.
///
/// Home used to show everybody three tiles counting their *own* tasks. For a
/// Director, who is almost never given a task, that read "0 open, 0 due, 0
/// points" on every visit. The people running the club need the club. Counts
/// only — nothing here names anybody.
class ClubOverview {
  const ClubOverview({
    this.openWork = 0,
    this.overdue = 0,
    this.unassigned = 0,
    this.blocked = 0,
    this.members = 0,
    this.departmentsWithoutLead = 0,
    this.documentsAwaiting = 0,
    this.billsAwaiting = 0,
    this.joinsAwaiting = 0,
  });

  final int openWork;
  final int overdue;

  /// Sent to a department and not yet handed to anybody.
  final int unassigned;
  final int blocked;
  final int members;
  final int departmentsWithoutLead;
  final int documentsAwaiting;
  final int billsAwaiting;
  final int joinsAwaiting;

  factory ClubOverview.fromJson(Map<String, dynamic> json) {
    final waiting = (json['awaitingDecision'] as Map?)?.cast<String, dynamic>();
    return ClubOverview(
      openWork: _n(json, 'openWork'),
      overdue: _n(json, 'overdue'),
      unassigned: _n(json, 'unassigned'),
      blocked: _n(json, 'blocked'),
      members: _n(json, 'members'),
      departmentsWithoutLead: _n(json, 'departmentsWithoutLead'),
      documentsAwaiting: _n(waiting, 'documents'),
      billsAwaiting: _n(waiting, 'bills'),
      joinsAwaiting: _n(waiting, 'joins'),
    );
  }

  /// Nothing stuck anywhere a leader would need to look.
  bool get isCalm => overdue == 0 && unassigned == 0 && blocked == 0 && departmentsWithoutLead == 0;
}

/// A Lead's own department at a glance: the triage pile first.
class DepartmentPulse {
  const DepartmentPulse({
    this.incoming = 0,
    this.open = 0,
    this.overdue = 0,
    this.joins = 0,
    this.members = 0,
  });

  /// Work addressed to the department and waiting for its Lead to hand out.
  final int incoming;
  final int open;
  final int overdue;
  final int joins;
  final int members;

  factory DepartmentPulse.fromJson(Map<String, dynamic> json) => DepartmentPulse(
        incoming: _n(json, 'incoming'),
        open: _n(json, 'open'),
        overdue: _n(json, 'overdue'),
        joins: _n(json, 'joins'),
        members: _n(json, 'members'),
      );
}

/// Home's single focal point.
class WhatsNext {
  const WhatsNext({this.task, this.entry});
  final ClubTask? task;
  final ScheduleEntry? entry;
  bool get isEmpty => task == null && entry == null;
}

/// One row on Home's "today" strip — a schedule entry or a task due today.
class TodayItem {
  const TodayItem({
    required this.id,
    required this.title,
    required this.date,
    required this.categoryName,
    required this.categoryIcon,
    required this.categoryColorHex,
    this.location = '',
    this.taskId,
    this.meetingId,
  });

  final String id;
  final String title;
  final DateTime date;
  final String categoryName;
  final String categoryIcon;
  final String categoryColorHex;
  final String location;

  /// Set on the rows that are really something else wearing a schedule row's
  /// clothes. Tapping one opens the actual thing, never a read-only copy of it.
  final String? taskId;
  final String? meetingId;

  Color get tint => hexToColor(categoryColorHex);
  IconData get icon => iconFor(categoryIcon);

  factory TodayItem.fromJson(Map<String, dynamic> json) => TodayItem(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        date: DateTime.tryParse(json['date']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
        categoryName: json['categoryName'] as String? ?? 'Entry',
        categoryIcon: json['categoryIcon'] as String? ?? 'flag',
        categoryColorHex: json['categoryColor'] as String? ?? '#DC2626',
        location: json['location'] as String? ?? '',
        taskId: json['taskId'] as String?,
        meetingId: json['meetingId'] as String?,
      );

  String get timeLabel =>
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

/// Weekly momentum, as one ratio rather than a chart.
class WeekProgress {
  const WeekProgress({this.done = 0, this.total = 0, this.ratio = 0});
  final int done;
  final int total;
  final double ratio;

  factory WeekProgress.fromJson(Map<String, dynamic> json) => WeekProgress(
        done: (json['done'] as num?)?.toInt() ?? 0,
        total: (json['total'] as num?)?.toInt() ?? 0,
        ratio: (json['ratio'] as num?)?.toDouble() ?? 0,
      );
}

/// Server-reported capabilities. The client mirrors these to hide actions that
/// would be rejected; it never uses them to *grant* anything.
class Capabilities {
  const Capabilities({
    this.canAssign = false,
    this.canEditSchedule = false,
    this.canCreateScheduleEntry = false,
    this.canBroadcast = false,
    this.canManageDepartments = false,
    this.hasOversight = false,
    this.canViewDashboard = false,
    this.canAwardPoints = false,
    this.canChangeRole = false,
    this.canAppointSupervisors = false,
    this.isSuperAdmin = false,
    this.earnsPoints = true,
    this.onLeaderboard = true,
    this.pendingApprovals = 0,
  });

  final bool canAssign;
  final bool canEditSchedule;
  final bool canCreateScheduleEntry;
  final bool canBroadcast;
  final bool canManageDepartments;

  /// Directors, the Faculty Coordinator and the President: the approvals
  /// queue and the whole club's recognition page.
  final bool hasOversight;

  /// The Dashboard and its audit log — the Club Director's alone since V8.1.
  final bool canViewDashboard;
  final bool canAwardPoints;

  /// Appoint somebody to an office. President and supervisors only.
  final bool canChangeRole;

  /// ...and into the supervisor tier, which is Directors alone. The client
  /// offers the shorter list rather than a choice the server would refuse.
  final bool canAppointSupervisors;

  /// The one Director above the others. Presentation and hiding only; the
  /// server decides what it grants.
  final bool isSuperAdmin;

  final bool earnsPoints;
  final bool onLeaderboard;
  final int pendingApprovals;

  factory Capabilities.fromJson(Map<String, dynamic> json) => Capabilities(
        canAssign: json['canAssign'] as bool? ?? false,
        canEditSchedule: json['canEditSchedule'] as bool? ?? false,
        canCreateScheduleEntry: json['canCreateScheduleEntry'] as bool? ?? false,
        canBroadcast: json['canBroadcast'] as bool? ?? false,
        canManageDepartments: json['canManageDepartments'] as bool? ?? false,
        hasOversight: json['hasOversight'] as bool? ?? false,
        canViewDashboard: json['canViewDashboard'] as bool? ?? false,
        canAwardPoints: json['canAwardPoints'] as bool? ?? false,
        canChangeRole: json['canChangeRole'] as bool? ?? false,
        canAppointSupervisors: json['canAppointSupervisors'] as bool? ?? false,
        isSuperAdmin: json['isSuperAdmin'] as bool? ?? false,
        earnsPoints: json['earnsPoints'] as bool? ?? true,
        onLeaderboard: json['onLeaderboard'] as bool? ?? true,
        pendingApprovals: (json['pendingApprovals'] as num?)?.toInt() ?? 0,
      );
}

/// The live data store.
///
/// Everything the app renders lives here. REST fills it on load; the socket
/// keeps it current. Screens listen and rebuild — they never fetch for
/// themselves, which is what makes a change on web appear on the phone without
/// anyone pulling to refresh.
class ClubStore extends ChangeNotifier {
  ClubStore({required this.session, SocketClient? socket})
      : socket = socket ?? SocketClient(baseUrlProvider: (() => session.baseUrl)) {
    _subscription = this.socket.events.listen(_onLiveEvent);
    this.socket.status.addListener(_onStatusChanged);
    // A rejected handshake means this session is finished — drop to sign-in
    // rather than showing stale data behind a socket that will never connect.
    this.socket.onUnauthorized = () => unawaited(session.signOut());
  }

  final Session session;
  final SocketClient socket;
  late final StreamSubscription<LiveEvent> _subscription;

  ApiClient get _api => session.api;

  // ----------------------------------------------------------------- state
  List<ClubTask> tasks = const [];
  List<Department> departments = const [];
  List<Member> members = const [];
  List<AppNotification> notifications = const [];
  List<ScheduleEntry> schedule = const [];
  List<ScheduleCategory> categories = const [];
  List<ClubAlert> alerts = const [];
  List<TaskRequest> incomingRequests = const [];
  List<TaskRequest> outgoingRequests = const [];
  List<AccessRequest> pendingApprovals = const [];
  List<TodayItem> today = const [];

  // --- meetings -------------------------------------------------------------
  /// Meetings this person can see: everyone sees what they were invited to,
  /// leadership sees all of them so clashes are visible.
  List<Meeting> meetingsUpcoming = const [];
  List<Meeting> meetingsPast = const [];
  bool canScheduleMeetings = false;

  /// Meetings that have happened and still have nobody marked.
  ///
  /// Only counted for people who can actually record it — a badge a member
  /// cannot clear is a badge they learn to ignore. This is the one thing about
  /// meetings that genuinely needs somebody, so it is the only thing that gets
  /// to nag.
  int get meetingsAwaitingAttendance => canScheduleMeetings
      ? meetingsPast.where((m) => !m.attendanceRecorded && !m.isCancelled).length
      : 0;

  /// Recognition, per department. There is no club-wide list by design — see
  /// [DepartmentRecognition].
  List<DepartmentRecognition> recognition = const [];

  /// People with no department: the executive tier. Shown plainly so they are
  /// not silently missing, never mixed into a department's list.
  List<Member> unaffiliated = const [];

  /// How much work each department was given and how much landed. Open to
  /// everyone — aggregate numbers give away nothing about an individual.
  List<DepartmentProgress> departmentProgress = const [];

  int rankingThreshold = 3;

  // --- events --------------------------------------------------------------
  List<ClubEvent> eventsUpcoming = const [];
  List<ClubEvent> eventsOngoing = const [];
  List<ClubEvent> eventsCompleted = const [];
  bool canCreateEvents = false;

  /// Per-event detail, cached and kept live.
  ///
  /// The alternative — each workspace screen fetching for itself in initState —
  /// is exactly the bug that made awarding points never reach the leaderboard.
  /// A screen reads [workspaceFor]; the socket invalidates it.
  final Map<String, EventWorkspace> _workspaces = {};
  final Map<String, List<EventTaskCard>> _boards = {};
  final Map<String, EventDocuments> _documents = {};
  final Map<String, List<EventActivity>> _timelines = {};
  final Map<String, EventDay> _days = {};
  final Map<String, EventReport> _reports = {};

  /// Saved event shapes, club-wide rather than per-event, so the create wizard
  /// can offer them the moment it opens instead of loading behind a spinner on
  /// the first screen somebody sees.
  List<EventTemplate> eventTemplates = const [];

  // --- help & collaboration -------------------------------------------------
  List<HelpRequest> helpRequests = const [];

  WhatsNext whatsNext = const WhatsNext();

  /// Set for the people running the club; null for everybody else.
  ClubOverview? overview;

  /// Set for a department Lead; null for everybody else.
  DepartmentPulse? myDepartmentPulse;
  Capabilities capabilities = const Capabilities();
  WeekProgress progress = const WeekProgress();
  int unreadNotifications = 0;
  int pendingCount = 0;
  int inProgressCount = 0;
  int completedThisWeek = 0;
  int upcomingCount = 0;

  bool loading = false;
  bool hasLoadedOnce = false;
  String? loadError;

  final List<LiveToast> toasts = [];

  /// The id of the task whose comment thread just changed, for whichever task
  /// page happens to be open.
  ///
  /// A `ValueNotifier` rather than a `notifyListeners()` on the store: a
  /// comment on somebody else's task must not rebuild Home, the Work tab and
  /// every board for every member of the club. Threads are fetched by the
  /// detail page directly, so this is a nudge addressed to one screen.
  final ValueNotifier<String?> commentsChangedFor = ValueNotifier(null);

  /// The id of a meeting that just changed, for a meeting page that is open.
  ///
  /// The meetings list refreshed on every change, but an *open* meeting page
  /// holds its own copy and never heard: if the organiser cancelled it, wrote
  /// up what was decided or recorded attendance while you were looking, your
  /// screen stayed as it was. Same shape as [commentsChangedFor] — a nudge
  /// with an id, so only the page it is about reloads.
  final ValueNotifier<String?> meetingChangedFor = ValueNotifier(null);

  /// Refetch Home's figures shortly, once, however many changes arrive.
  ///
  /// The club-wide and department figures on Home come from `/api/home`, and
  /// nothing refreshed them when work moved, so a Director's "3 overdue" was
  /// right only as of opening the app. Refetching on every change would be a
  /// burst of the heaviest request the app makes; a club finishing a sprint
  /// sends dozens of task updates a minute. So changes arriving together cost
  /// one request, a moment after the last of them — and only for people whose
  /// Home actually shows those figures.
  Timer? _homeRefresh;
  void _refreshHomeSoon() {
    if (overview == null && myDepartmentPulse == null) return;
    _homeRefresh?.cancel();
    _homeRefresh = Timer(const Duration(milliseconds: 1200), () async {
      try {
        await _loadHome();
        notifyListeners();
      } catch (_) {
        // Home keeps what it had; the next change or pull-to-refresh retries.
      }
    });
  }

  void _nudgeMeeting(String? id) {
    if (id == null || id.isEmpty) return;
    meetingChangedFor.value = id;
    // Cleared at once, or a second change to the same meeting would be silent.
    meetingChangedFor.value = null;
  }

  LiveStatus get liveStatus => socket.status.value;

  // ------------------------------------------------------------- lifecycle
  void start() {
    final token = session.token;
    if (token != null) socket.connect(token);
    unawaited(loadAll());
  }

  void stop() {
    socket.disconnect();
    tasks = const [];
    members = const [];
    notifications = const [];
    schedule = const [];
    alerts = const [];
    incomingRequests = const [];
    outgoingRequests = const [];
    pendingApprovals = const [];
    today = const [];
    // Cleared on sign-out with everything else, or the next person to use this
    // phone sees the previous member's meetings.
    meetingsUpcoming = const [];
    meetingsPast = const [];
    canScheduleMeetings = false;
    recognition = const [];
    unaffiliated = const [];
    departmentProgress = const [];
    eventsUpcoming = const [];
    eventsOngoing = const [];
    eventsCompleted = const [];
    helpRequests = const [];
    _workspaces.clear();
    _boards.clear();
    _documents.clear();
    _timelines.clear();
    whatsNext = const WhatsNext();
    capabilities = const Capabilities();
    progress = const WeekProgress();
    hasLoadedOnce = false;
    toasts.clear();
    notifyListeners();
  }

  LiveStatus _lastStatus = LiveStatus.idle;

  void _onStatusChanged() {
    final next = socket.status.value;
    if (next == _lastStatus) return; // ignore churn; it rebuilds the whole tree
    _lastStatus = next;

    // Reconnected after a drop — resync, because events that fired while we
    // were away were delivered to nobody on this socket.
    if (next == LiveStatus.connected && hasLoadedOnce) {
      unawaited(loadAll(silent: true));
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription.cancel();
    socket.status.removeListener(_onStatusChanged);
    socket.dispose();
    commentsChangedFor.dispose();
    meetingChangedFor.dispose();
    _homeRefresh?.cancel();
    super.dispose();
  }

  // ------------------------------------------------------------------ load
  Future<void> loadAll({bool silent = false}) async {
    if (!silent) {
      loading = true;
      loadError = null;
      notifyListeners();
    }
    try {
      await Future.wait([
        _loadHome(),
        loadTasks(),
        loadDepartments(),
        loadNotifications(),
        loadCategories(),
        loadSchedule(),
        loadAlerts(),
        loadRequests(),
        loadMembers(),
        loadLeaderboard(),
        loadDepartmentProgress(),
        loadEvents(),
        loadHelp(),
        loadIncoming(),
        // Adding a `load*` method is two edits, not one. `loadIncoming` was
        // once written, called from two write paths, and left out of here —
        // so a Lead's triage pile was empty until they happened to assign
        // something. Anything the app must have on open belongs in this list.
        loadMeetings(),
        loadEventTemplates(),
      ]);
      if (capabilities.hasOversight || session.role == ClubRole.clubLead) {
        await loadPendingApprovals();
      }
      hasLoadedOnce = true;
      loadError = null;
    } on ApiException catch (e) {
      loadError = e.message;
    } catch (_) {
      loadError = 'Could not reach the server.';
    } finally {
      loading = false;
      notifyListeners();
      unawaited(_pushToWidget());
    }
  }

  Future<void> _loadHome() async {
    final json = await _api.get('/api/home');
    final counts = json['counts'] as Map<String, dynamic>?;
    pendingCount = (counts?['pending'] as num?)?.toInt() ?? 0;
    inProgressCount = (counts?['inProgress'] as num?)?.toInt() ?? 0;
    completedThisWeek = (counts?['completedThisWeek'] as num?)?.toInt() ?? 0;
    unreadNotifications = (counts?['unreadNotifications'] as num?)?.toInt() ?? 0;
    upcomingCount = (counts?['upcoming'] as num?)?.toInt() ?? 0;

    capabilities =
        Capabilities.fromJson((json['capabilities'] as Map?)?.cast<String, dynamic>() ?? const {});
    progress =
        WeekProgress.fromJson((json['progress'] as Map?)?.cast<String, dynamic>() ?? const {});

    today = ((json['today'] as List?) ?? [])
        .whereType<Map>()
        .map((e) => TodayItem.fromJson(e.cast<String, dynamic>()))
        .toList();

    final overviewJson = (json['overview'] as Map?)?.cast<String, dynamic>();
    overview = overviewJson == null ? null : ClubOverview.fromJson(overviewJson);
    final deptJson = (json['myDepartment'] as Map?)?.cast<String, dynamic>();
    myDepartmentPulse = deptJson == null ? null : DepartmentPulse.fromJson(deptJson);

    final next = json['whatsNext'] as Map<String, dynamic>?;
    if (next == null) {
      whatsNext = const WhatsNext();
    } else if (next['kind'] == 'task' && next['task'] != null) {
      whatsNext = WhatsNext(task: ClubTask.fromJson((next['task'] as Map).cast<String, dynamic>()));
    } else if (next['kind'] == 'schedule' && next['entry'] != null) {
      whatsNext =
          WhatsNext(entry: ScheduleEntry.fromJson((next['entry'] as Map).cast<String, dynamic>()));
    } else {
      whatsNext = const WhatsNext();
    }
  }

  Future<void> loadTasks() async {
    // Two reads, merged. The general list leaves event work out on purpose -
    // one festival would bury everybody's own to-do list - but event work that
    // is *yours* is still yours, and `scope=mine` is the read that carries it.
    // Loading only the general list meant a Lead with four festival jobs saw
    // "No tasks for you" on Work while Home named one of them as next.
    final results = await Future.wait([
      _api.get('/api/tasks'),
      _api.get('/api/tasks', query: {'scope': 'mine'}),
    ]);
    final byId = <String, ClubTask>{};
    for (final json in results) {
      for (final task in listFrom(json, 'tasks', ClubTask.fromJson)) {
        byId[task.id] = task;
      }
    }
    tasks = byId.values.toList();
    // Wholesale replacements do not go through _upsertTask, so the widget is
    // refreshed here too.
    unawaited(_pushToWidget());
  }

  Future<void> loadDepartments() async {
    final json = await _api.get('/api/departments',
        query: {if (capabilities.canManageDepartments) 'includeInactive': 'true'});
    departments = listFrom(json, 'departments', Department.fromJson);
  }

  Future<void> loadMembers() async {
    final json = await _api.get('/api/users');
    members = listFrom(json, 'users', Member.fromJson);
  }

  Future<void> loadNotifications() async {
    final json = await _api.get('/api/notifications');
    notifications = listFrom(json, 'notifications', AppNotification.fromJson);
    unreadNotifications = (json['unread'] as num?)?.toInt() ?? 0;
  }

  Future<void> loadSchedule() async {
    final json = await _api.get('/api/schedule');
    schedule = listFrom(json, 'entries', ScheduleEntry.fromJson)
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  Future<void> loadCategories() async {
    final json = await _api.get('/api/categories/schedule', query: {
      if (capabilities.canManageDepartments) 'includeInactive': 'true',
    });
    categories = listFrom(json, 'categories', ScheduleCategory.fromJson);
  }

  Future<void> loadAlerts() async {
    final json = await _api.get('/api/alerts');
    alerts = listFrom(json, 'alerts', ClubAlert.fromJson);
  }

  Future<void> loadRequests() async {
    final incoming = await _api.get('/api/task-requests', query: {'direction': 'incoming'});
    incomingRequests = listFrom(incoming, 'requests', TaskRequest.fromJson);
    final outgoing = await _api.get('/api/task-requests', query: {'direction': 'outgoing'});
    outgoingRequests = listFrom(outgoing, 'requests', TaskRequest.fromJson);
  }

  Future<void> loadPendingApprovals() async {
    try {
      final json = await _api.get('/api/access/pending');
      pendingApprovals = listFrom(json, 'requests', AccessRequest.fromJson);
    } on ApiException {
      pendingApprovals = const [];
    }
  }

  // --------------------------------------------------------------- queries
  String get _meId => session.me?.id ?? '';

  List<ClubTask> get myTasks =>
      tasks.where((t) => t.assignedTo == _meId).toList()..sort(_byUrgency);

  List<ClubTask> get assignedByMe =>
      tasks.where((t) => t.assignedBy == _meId && t.assignedTo != _meId).toList()..sort(_byUrgency);

  int _byUrgency(ClubTask a, ClubTask b) {
    if (a.status.isOpen != b.status.isOpen) return a.status.isOpen ? -1 : 1;
    final ad = a.dueDate;
    final bd = b.dueDate;
    if (ad != null && bd != null) return ad.compareTo(bd);
    if (ad != null) return -1;
    if (bd != null) return 1;
    return (b.updatedAt ?? DateTime(0)).compareTo(a.updatedAt ?? DateTime(0));
  }

  Department? departmentById(String? id) {
    if (id == null) return null;
    for (final d in departments) {
      if (d.id == id) return d;
    }
    return null;
  }

  Member? memberById(String? id) {
    if (id == null) return null;
    if (id == session.me?.id) return session.me;
    for (final m in members) {
      if (m.id == id) return m;
    }
    return null;
  }

  String memberName(String? id) => memberById(id)?.name ?? 'Someone';

  ScheduleEntry? scheduleById(String id) {
    for (final e in schedule) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// `null` → everything. [ScheduleCategory.deadlineId] → the derived task
  /// deadlines. Anything else → that category.
  List<ScheduleEntry> entriesIn(String? categoryId) {
    if (categoryId == null) return schedule;
    if (categoryId == ScheduleCategory.deadlineId) {
      return schedule.where((e) => e.isDeadline).toList();
    }
    return schedule.where((e) => e.categoryId == categoryId).toList();
  }

  /// Categories that can be picked when creating, plus the derived deadline
  /// pseudo-category for filtering only.
  List<ScheduleCategory> get activeCategories => categories.where((c) => c.active).toList();

  ScheduleCategory? categoryById(String? id) {
    if (id == null) return null;
    if (id == ScheduleCategory.deadlineId) return ScheduleCategory.deadline;
    for (final c in categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  List<ScheduleEntry> get upcoming =>
      schedule.where((e) => !e.isPast).toList()..sort((a, b) => a.date.compareTo(b.date));

  // --------------------------------------------------------------- actions
  /// Create work — either addressed to a whole department, or to named people.
  ///
  /// Exactly one of [departmentId] and [assignedTo] is used. The leadership
  /// tier sends to a department and its Lead decides who does it; a Lead names
  /// their own member directly.
  Future<ClubTask?> createTask({
    required String title,
    List<String> assignedTo = const [],
    String? departmentId,
    String description = '',
    DateTime? dueDate,
    int? points,
    TaskPriority priority = TaskPriority.normal,
  }) async {
    final json = await _api.post('/api/tasks', {
      'title': title,
      'description': description,
      if (departmentId != null) 'departmentId': departmentId else 'assignedTo': assignedTo,
      if (dueDate != null) 'dueDate': dueDate.toUtc().toIso8601String(),
      if (points != null) 'points': points,
      'priority': priority.name,
    });
    final created = listFrom(json, 'tasks', ClubTask.fromJson);
    for (final task in created) {
      _upsertTask(task);
    }
    notifyListeners();
    unawaited(loadSchedule()); // a due date puts it on the deadline lane
    unawaited(loadIncoming());
    return created.isEmpty ? null : created.first;
  }

  Future<void> setTaskStatus(ClubTask task, TaskStatus next) async {
    final previous = task;
    _upsertTask(task.copyWith(status: next));
    notifyListeners();
    try {
      final json = await _api.patch('/api/tasks/${task.id}', {'status': next.wire});
      final updated = json['task'];
      if (updated is Map) _upsertTask(ClubTask.fromJson(updated.cast<String, dynamic>()));
      // The change is already on screen and confirmed. What follows only
      // tidies figures elsewhere, so it runs alongside rather than in front:
      // awaited one after another, it kept the button busy for two more round
      // trips after the thing it stood for had happened.
      unawaited(Future.wait([_loadHome(), session.refresh()])
          .then((_) => notifyListeners())
          .catchError((_) {}));
      unawaited(loadSchedule());
      // Completing work changes a completion rate, which is what the board
      // ranks on.
      unawaited(loadLeaderboard());
    } catch (_) {
      // Put it back on *any* failure, not only one the server answered. A
      // dropped connection that is not an ApiException would otherwise leave
      // the task showing done on this phone and open everywhere else.
      _upsertTask(previous);
      rethrow;
    } finally {
      notifyListeners();
      unawaited(_pushToWidget());
    }
  }

  Future<void> deleteTask(String id) async {
    await _api.delete('/api/tasks/$id');
    tasks = tasks.where((t) => t.id != id).toList();
    notifyListeners();
    // A removal is not an upsert, so it needs its own nudge — otherwise the
    // widget keeps counting a task that no longer exists.
    unawaited(_pushToWidget());
    unawaited(loadSchedule()); // it may have been carrying a deadline
  }

  /// One task and its thread, fetched directly.
  ///
  /// The general task list deliberately excludes event work, so a card opened
  /// from an event board is not in [tasks]. Rather than widen that list — and
  /// bury everybody's own to-do list under a festival — the detail screen falls
  /// back to this.
  Future<({ClubTask? task, List<TaskComment> comments})> taskDetail(String taskId) async {
    final json = await _api.get('/api/tasks/$taskId');
    final raw = json['task'];
    return (
      task: raw is Map ? ClubTask.fromJson(raw.cast<String, dynamic>()) : null,
      comments: listFrom(json, 'comments', TaskComment.fromJson),
    );
  }

  Future<TaskComment?> addComment(String taskId, String body) async {
    final json = await _api.post('/api/tasks/$taskId/comments', {'body': body});
    final comment = json['comment'];
    return comment is Map ? TaskComment.fromJson(comment.cast<String, dynamic>()) : null;
  }

  /// Everything the compose sheet needs, as the server sees it.
  ///
  /// The shape mirrors the two-step hierarchy: the leadership tier gets
  /// [departments] and no individuals; a Lead gets their own members by name.
  Future<AssignmentTargets> assignableTargets() async {
    final json = await _api.get('/api/users/assignable');
    return AssignmentTargets(
      assignable: listFrom(json, 'assignable', Member.fromJson),
      requestable: listFrom(json, 'requestable', Member.fromJson),
      departments: listFrom(json, 'departments', AssignableDepartment.fromJson),
      requestableDepartments:
          listFrom(json, 'requestableDepartments', AssignableDepartment.fromJson),
      canAssignToDepartment: json['canAssignToDepartment'] == true,
      pointValues: ((json['pointValues'] as List?) ?? const [1, 3, 5])
          .map((e) => (e as num).toInt())
          .toList(growable: false),
    );
  }

  /// Hand a department task to somebody — the second half of the hierarchy.
  ///
  /// Pricing happens here, not at creation, because this is the moment
  /// somebody who knows the work is looking at it.
  Future<void> handOutTask(
    String taskId, {
    required String assignedTo,
    int? points,
    DateTime? dueDate,
  }) async {
    await _api.post('/api/tasks/$taskId/assign', {
      'assignedTo': assignedTo,
      if (points != null) 'points': points,
      if (dueDate != null) 'dueDate': dueDate.toUtc().toIso8601String(),
    });
    await Future.wait([loadTasks(), loadIncoming(), _loadHome()]);
    notifyListeners();
  }

  /// Work addressed to this Lead's department that nobody has been given yet.
  List<ClubTask> incoming = const [];

  Future<void> loadIncoming() async {
    if (session.role != ClubRole.clubLead) {
      incoming = const [];
      return;
    }
    final json = await _api.get('/api/tasks', query: {'scope': 'incoming'});
    incoming = listFrom(json, 'tasks', ClubTask.fromJson);
  }

  /// Ask somebody to take something on.
  ///
  /// Exactly one of [toUserId] or [toDepartmentId]. A department request lands
  /// on that department's Lead — which is how the work is actually described
  /// ("Technical needs Production on the stage rig"), and saves the asker
  /// working out which person over there is free.
  Future<void> sendTaskRequest({
    String? toUserId,
    String? toDepartmentId,
    required String title,
    String description = '',
    DateTime? dueDate,
  }) async {
    assert(
      (toUserId == null) != (toDepartmentId == null),
      'A request goes to one person or one department, never both or neither.',
    );
    await _api.post('/api/task-requests', {
      if (toUserId != null) 'toUserId': toUserId,
      if (toDepartmentId != null) 'toDepartmentId': toDepartmentId,
      'title': title,
      'description': description,
      if (dueDate != null) 'dueDate': dueDate.toUtc().toIso8601String(),
    });
    await loadRequests();
    notifyListeners();
  }

  /// Accepting turns the request into a real task, so the work, the deadline
  /// lane on the schedule and Home all have to catch up — not just the request
  /// list.
  ///
  /// [points] prices a member's ask for work, which becomes the member's task.
  Future<void> respondToRequest(String id, {required bool accept, int? points}) async {
    await _api.post(
      '/api/task-requests/$id/${accept ? 'accept' : 'decline'}',
      points == null ? null : {'points': points},
    );
    await Future.wait([loadRequests(), loadTasks(), loadSchedule(), _loadHome()]);
    notifyListeners();
  }

  Future<void> decideAccess(String id, {required bool approve}) async {
    await _api.post('/api/access/$id/${approve ? 'approve' : 'reject'}');
    await Future.wait([loadPendingApprovals(), loadMembers()]);
    await _loadHome();
    notifyListeners();
  }

  Future<void> createDepartment(String name, {String description = ''}) async {
    await _api.post('/api/departments', {'name': name, 'description': description});
    await loadDepartments();
    notifyListeners();
  }

  Future<void> updateDepartment(String id,
      {String? name, String? description, bool? active}) async {
    await _api.patch('/api/departments/$id', {
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (active != null) 'active': active,
    });
    await loadDepartments();
    notifyListeners();
  }

  Future<void> setDepartmentLead(String departmentId, String? userId) async {
    await _api.put('/api/departments/$departmentId/lead', {'userId': userId});
    await Future.wait([loadDepartments(), loadMembers()]);
    notifyListeners();
  }

  Future<void> deactivateDepartment(String id) async {
    await _api.delete('/api/departments/$id');
    await loadDepartments();
    notifyListeners();
  }

  // -------------------------------------------------------------- schedule
  Future<void> saveScheduleEntry({
    String? id,
    required String categoryId,
    required String title,
    required DateTime date,
    String description = '',
    String location = '',
    String meetingUrl = '',
    MarketingPlatform? platform,
    MarketingFormat? format,
    MarketingStage? stage,
  }) async {
    final body = {
      'categoryId': categoryId,
      'title': title,
      'date': date.toUtc().toIso8601String(),
      'description': description,
      'location': location,
      'meetingUrl': meetingUrl,
      if (platform != null) 'platform': platform.name,
      if (format != null) 'format': format.name,
      if (stage != null) 'stage': stage.name,
    };
    if (id == null) {
      await _api.post('/api/schedule', body);
    } else {
      await _api.patch('/api/schedule/$id', body);
    }
    await loadSchedule();
    await _loadHome();
    notifyListeners();
  }

  Future<void> deleteScheduleEntry(String id) async {
    await _api.delete('/api/schedule/$id');
    schedule = schedule.where((e) => e.id != id).toList();
    notifyListeners();
  }

  Future<void> toggleRsvp(ScheduleEntry entry) async {
    final going = !entry.isAttending(_meId);
    await _api.post('/api/schedule/${entry.id}/rsvp', {'going': going});
    await loadSchedule();
    notifyListeners();
  }

  Future<Map<String, dynamic>> scheduleDetail(String id) => _api.get('/api/schedule/$id');

  // ------------------------------------------------------------ categories
  Future<void> saveCategory({
    String? id,
    required String name,
    required String icon,
    required String color,
    String blurb = '',
  }) async {
    final body = {'name': name, 'icon': icon, 'color': color, 'blurb': blurb};
    if (id == null) {
      await _api.post('/api/categories/schedule', body);
    } else {
      await _api.patch('/api/categories/schedule/$id', body);
    }
    await loadCategories();
    await loadSchedule();
    notifyListeners();
  }

  /// Returns the server's message when a category was hidden rather than
  /// deleted, so the UI can explain what happened instead of silently doing
  /// something different from what the button said.
  Future<String?> removeCategory(String id) async {
    final json = await _api.delete('/api/categories/schedule/$id');
    await loadCategories();
    await loadSchedule();
    notifyListeners();
    return json['message'] as String?;
  }

  /// "What did I hand out, and who has done it?" — scoped to the caller.
  Future<Map<String, dynamic>> myOverview() => _api.get('/api/users/my-overview');

  /// Remove somebody from the club. Directors only; the server is the
  /// authority and refuses anyone else.
  ///
  /// Their work is not deleted with them — the server returns tasks they
  /// carried to the triage pile — so everything that could have changed is
  /// reloaded rather than just the member list.
  Future<void> removeMember(String userId) async {
    await _api.delete('/api/users/$userId');
    await Future.wait([
      loadMembers(),
      loadDepartments(),
      loadTasks(),
      loadIncoming(),
      loadLeaderboard(),
      _loadHome(),
    ]);
    notifyListeners();
  }

  // ----------------------------------------------------------- member stats
  Future<Map<String, dynamic>> memberStats(String userId) => _api.get('/api/users/$userId/stats');

  /// The club as an org chart: executive seats, then departments with their
  /// Lead and headline progress.
  Future<Map<String, dynamic>> structure() => _api.get('/api/departments/structure');

  /// The people in one department. The server refuses this for a Member asking
  /// about someone else's department.
  Future<Map<String, dynamic>> departmentRoster(String departmentId) =>
      _api.get('/api/departments/$departmentId/roster');

  /// One department's workspace: its people, its work, the events it is on the
  /// hook for, and who is asking it for help. The server decides how much of
  /// the people section comes back.
  Future<Map<String, dynamic>> departmentWorkspace(String departmentId) =>
      _api.get('/api/departments/$departmentId/workspace');

  // ---------------------------------------------------------------- alerts

  Future<int> sendAlert({
    required String title,
    required String message,
    required AlertAudience audience,
    AlertUrgency urgency = AlertUrgency.normal,
  }) async {
    final json = await _api.post('/api/alerts', {
      'title': title,
      'message': message,
      'audience': audience.name,
      'urgency': urgency.name,
    });
    await loadAlerts();
    notifyListeners();
    return (json['reach'] as num?)?.toInt() ?? 0;
  }

  // ---------------------------------------------------------------- points
  Future<void> awardPoints(String userId, int points, String reason) async {
    await _api.post('/api/users/$userId/award', {'points': points, 'reason': reason});
    // Refresh both: the directory shows the new total, and the board has to
    // move too or the award looks like it did nothing.
    await Future.wait([loadMembers(), loadLeaderboard()]);
    notifyListeners();
  }

  Future<void> markNotificationRead(String id) async {
    notifications = [
      for (final n in notifications) n.id == id ? n.copyWith(read: true) : n,
    ];
    unreadNotifications = notifications.where((n) => !n.read).length;
    notifyListeners();
    await _api.post('/api/notifications/$id/read');
  }

  Future<void> markAllRead() async {
    notifications = [for (final n in notifications) n.copyWith(read: true)];
    unreadNotifications = 0;
    notifyListeners();
    await _api.post('/api/notifications/read-all');
  }

  /// Recognition lives in the store, not in the page.
  ///
  /// It used to be fetched once in the screen's initState, which meant awarding
  /// someone points changed the directory but never the board — it had no way
  /// to hear about it. Everything that can move a standing now refreshes this:
  /// awards, task completions, and the `user:updated` socket event.
  Future<void> loadLeaderboard() async {
    final json = await _api.get('/api/users/leaderboard');
    recognition = listFrom(json, 'departments', DepartmentRecognition.fromJson);
    unaffiliated = listFrom(json, 'unaffiliated', Member.fromJson);
    rankingThreshold = (json['rankingThreshold'] as num?)?.toInt() ?? rankingThreshold;
  }

  Future<void> loadDepartmentProgress() async {
    final json = await _api.get('/api/users/department-overview');
    departmentProgress = listFrom(json, 'departments', DepartmentProgress.fromJson);
  }

  Future<Map<String, dynamic>> analytics() => _api.get('/api/analytics');
  Future<Map<String, dynamic>> auditLog() => _api.get('/api/audit');

  // =========================================================== events
  Future<void> loadEvents() async {
    final json = await _api.get('/api/events');
    eventsUpcoming = listFrom(json, 'upcoming', ClubEvent.fromJson);
    eventsOngoing = listFrom(json, 'ongoing', ClubEvent.fromJson);
    eventsCompleted = listFrom(json, 'completed', ClubEvent.fromJson);
    canCreateEvents = json['canCreate'] == true;
  }

  /// Everything currently in flight — what Home and the Events tab lead with.
  List<ClubEvent> get eventsActive => [...eventsOngoing, ...eventsUpcoming];

  EventWorkspace? workspaceFor(String id) => _workspaces[id];
  List<EventTaskCard>? boardFor(String id) => _boards[id];
  EventDocuments? documentsFor(String id) => _documents[id];
  List<EventActivity>? timelineFor(String id) => _timelines[id];

  Future<void> loadEventWorkspace(String id) async {
    final json = await _api.get('/api/events/$id');
    _workspaces[id] = EventWorkspace.fromJson(json);
    notifyListeners();
  }

  Future<void> loadEventBoard(String id, {String? departmentId}) async {
    final json = await _api.get('/api/events/$id/work',
        query: {if (departmentId != null) 'departmentId': departmentId});
    _boards[id] = listFrom(json, 'tasks', EventTaskCard.fromJson);
    notifyListeners();
  }

  Future<void> loadEventDocuments(String id) async {
    final json = await _api.get('/api/events/$id/documents');
    _documents[id] = EventDocuments.fromJson(json);
    notifyListeners();
  }

  Future<void> loadEventTimeline(String id) async {
    final json = await _api.get('/api/events/$id/timeline');
    _timelines[id] = listFrom(json, 'timeline', EventActivity.fromJson);
    notifyListeners();
  }

  // --- the day itself -------------------------------------------------------

  EventDay? dayFor(String id) => _days[id];

  Future<void> loadEventDay(String id) async {
    final json = await _api.get('/api/events/$id/day');
    _days[id] = EventDay.fromJson(json);
    notifyListeners();
  }

  Future<void> addRunSheetItem(
    String eventId, {
    required String title,
    String time = '',
    String note = '',
    String? ownerUserId,
  }) async {
    await _api.post('/api/events/$eventId/runsheet', {
      'title': title,
      'time': time,
      'note': note,
      if (ownerUserId != null) 'ownerUserId': ownerUserId,
    });
    await loadEventDay(eventId);
  }

  /// Tick a row off, or edit it.
  ///
  /// Only the keys actually passed are sent. The server lets anyone on the team
  /// tick a row but only the event lead rewrite one, and it decides that by
  /// looking at whether the body contains anything beyond `done` — so sending
  /// the whole item back on every tick would have a helper's tick refused as an
  /// edit they are not allowed to make.
  Future<void> updateRunSheetItem(
    String eventId,
    String itemId, {
    bool? done,
    String? title,
    String? time,
    String? note,
    String? ownerUserId,
  }) async {
    await _api.patch('/api/events/$eventId/runsheet/$itemId', {
      if (done != null) 'done': done,
      if (title != null) 'title': title,
      if (time != null) 'time': time,
      if (note != null) 'note': note,
      if (ownerUserId != null) 'ownerUserId': ownerUserId,
    });
    await loadEventDay(eventId);
  }

  Future<void> deleteRunSheetItem(String eventId, String itemId) async {
    await _api.delete('/api/events/$eventId/runsheet/$itemId');
    await loadEventDay(eventId);
  }

  // --- afterwards -----------------------------------------------------------

  EventReport? reportFor(String id) => _reports[id];

  Future<void> loadEventReport(String id) async {
    final json = await _api.get('/api/events/$id/report');
    _reports[id] = EventReport.fromJson(json);
    notifyListeners();
  }

  Future<void> saveEventReport(
    String eventId, {
    int? attendance,
    String highlights = '',
    String challenges = '',
    String learnings = '',
  }) async {
    await _api.put('/api/events/$eventId/report', {
      'attendance': attendance,
      'highlights': highlights,
      'challenges': challenges,
      'learnings': learnings,
    });
    await loadEventReport(eventId);
  }

  // --- templates ------------------------------------------------------------

  Future<void> loadEventTemplates() async {
    final json = await _api.get('/api/event-templates');
    eventTemplates = listFrom(json, 'templates', EventTemplate.fromJson);
    notifyListeners();
  }

  /// Save an event that already exists as a template.
  ///
  /// This is how most templates actually get made. Nobody sits down to write an
  /// abstract plan; they finish running a workshop, it went well, and they want
  /// the next one to start from the same place.
  Future<EventTemplate?> saveEventAsTemplate(String eventId, {String name = ''}) async {
    final json = await _api.post('/api/event-templates/from-event/$eventId', {
      if (name.isNotEmpty) 'name': name,
    });
    await loadEventTemplates();
    final created = json['template'];
    return created is Map
        ? EventTemplate.fromJson(created.cast<String, dynamic>())
        : null;
  }

  Future<void> updateEventTemplate(String id, Map<String, dynamic> changes) async {
    await _api.patch('/api/event-templates/$id', changes);
    await loadEventTemplates();
  }

  Future<void> deleteEventTemplate(String id) async {
    await _api.delete('/api/event-templates/$id');
    await loadEventTemplates();
  }

  /// Create an event and everything under it in one commit.
  ///
  /// The wizard collects the team and each department's opening tasks before
  /// anything is saved, so splitting this up would leave half-made events in
  /// the database every time somebody backs out at the last step.
  Future<ClubEvent?> createEvent({
    required String name,
    required DateTime date,
    required String organizingDepartmentId,
    String description = '',
    String type = 'event',
    String venue = '',
    String startTime = '',
    String endTime = '',
    String? leadUserId,
    List<String> supportingDepartmentIds = const [],
    List<String> teamUserIds = const [],
    String speakerName = '',
    String guestDetails = '',
    String externalOrganisation = '',
    List<Map<String, dynamic>> responsibilities = const [],
    String? templateId,
  }) async {
    final json = await _api.post('/api/events', {
      'name': name,
      'description': description,
      'type': type,
      'date': date.toUtc().toIso8601String(),
      'venue': venue,
      'startTime': startTime,
      'endTime': endTime,
      'organizingDepartmentId': organizingDepartmentId,
      if (leadUserId != null) 'leadUserId': leadUserId,
      'supportingDepartmentIds': supportingDepartmentIds,
      'teamUserIds': teamUserIds,
      'speakerName': speakerName,
      'guestDetails': guestDetails,
      'externalOrganisation': externalOrganisation,
      'responsibilities': responsibilities,
      // Attribution only. The template was applied in the wizard, so what is
      // posted here is whatever the person left after editing it.
      if (templateId != null) 'templateId': templateId,
    });
    await Future.wait([loadEvents(), loadEventTemplates()]);
    notifyListeners();
    final created = json['event'];
    return created is Map ? ClubEvent.fromJson(created.cast<String, dynamic>()) : null;
  }

  Future<void> updateEvent(String id, Map<String, dynamic> changes) async {
    await _api.patch('/api/events/$id', changes);
    await Future.wait([loadEvents(), loadEventWorkspace(id)]);
    notifyListeners();
  }

  /// Move an event's status.
  ///
  /// Returns the completion checklist when the server refuses because work is
  /// still open, so the caller can show what is outstanding and offer to close
  /// it anyway — a club's reality is that the last two tasks often never get
  /// ticked.
  Future<Map<String, dynamic>?> setEventStatus(
    String id,
    EventStatus status, {
    bool force = false,
  }) async {
    try {
      await _api.post('/api/events/$id/status', {'status': status.wire, 'force': force});
    } on ApiException catch (e) {
      if (e.statusCode == 409) {
        final json = await _api.get('/api/events/$id/checklist');
        return json;
      }
      rethrow;
    }
    await Future.wait([loadEvents(), loadEventWorkspace(id)]);
    notifyListeners();
    return null;
  }

  Future<void> addEventDepartment(String eventId, String departmentId, {String notes = ''}) async {
    await _api
        .post('/api/events/$eventId/departments', {'departmentId': departmentId, 'notes': notes});
    await Future.wait([loadEventWorkspace(eventId), loadEventBoard(eventId)]);
    notifyListeners();
  }

  Future<void> addEventTask({
    required String eventId,
    required String departmentId,
    required String title,
    String description = '',
    String? assignedTo,
    DateTime? dueDate,
    TaskPriority priority = TaskPriority.normal,
  }) async {
    await _api.post('/api/events/$eventId/tasks', {
      'departmentId': departmentId,
      'title': title,
      'description': description,
      if (assignedTo != null) 'assignedTo': assignedTo,
      if (dueDate != null) 'dueDate': dueDate.toUtc().toIso8601String(),
      'priority': priority.name,
    });
    await Future.wait([loadEventBoard(eventId), loadEventWorkspace(eventId)]);
    notifyListeners();
  }

  Future<void> claimEventTask(String eventId, String taskId, {String? userId}) async {
    await _api
        .post('/api/events/$eventId/tasks/$taskId/claim', {if (userId != null) 'userId': userId});
    await Future.wait([loadEventBoard(eventId), loadTasks()]);
    notifyListeners();
  }

  /// Move a card on an event board.
  ///
  /// Optimistic: the card moves immediately and snaps back if the server
  /// refuses, because a board that waits for a round trip before the card
  /// moves feels broken on college Wi-Fi.
  Future<void> setEventTaskStatus(String eventId, EventTaskCard card, TaskStatus next) async {
    final board = _boards[eventId];
    if (board != null) {
      _boards[eventId] = [
        for (final t in board)
          if (t.id == card.id)
            EventTaskCard(
              id: t.id,
              title: t.title,
              description: t.description,
              status: next,
              departmentId: t.departmentId,
              departmentName: t.departmentName,
              assignedTo: t.assignedTo,
              assigneeName: t.assigneeName,
              assigneeColor: t.assigneeColor,
              dueDate: t.dueDate,
              priority: t.priority,
              commentCount: t.commentCount,
            )
          else
            t,
      ];
      notifyListeners();
    }
    try {
      await _api.patch('/api/tasks/${card.id}', {'status': next.wire});
    } on ApiException {
      if (board != null) _boards[eventId] = board;
      notifyListeners();
      rethrow;
    }
    await Future.wait([
      loadEventBoard(eventId),
      loadEventWorkspace(eventId),
      loadLeaderboard(),
      session.refresh(),
    ]);
    notifyListeners();
  }

  /// Cancel an event, or remove a cancelled one outright.
  ///
  /// Two steps by design: cancelling keeps the work and the paperwork, and only
  /// something already cancelled can be purged. A live event can never be
  /// destroyed by one mistaken tap.
  ///
  /// Cancelling takes its tasks and deadlines with it, so the work list, the
  /// schedule and Home all have to catch up — not just the event list.
  Future<void> cancelEvent(String id, {bool purge = false}) async {
    await _api.delete('/api/events/$id${purge ? '?purge=true' : ''}');
    await Future.wait([loadEvents(), loadTasks(), loadSchedule(), _loadHome()]);
    notifyListeners();
  }

  // -------------------------------------------------------------- documents
  Future<void> uploadEventDocument({
    required String eventId,
    required DocumentKind kind,
    required String title,
    String note = '',
    List<int>? bytes,
    String? filename,
    String? link,
  }) async {
    await _api.upload('/api/events/$eventId/documents',
        fields: {
          'kind': kind.wire,
          'title': title,
          'note': note,
          if (link != null && link.isNotEmpty) 'link': link,
        },
        bytes: bytes,
        filename: filename);
    await Future.wait([loadEventDocuments(eventId), loadEventWorkspace(eventId)]);
    notifyListeners();
  }

  Future<void> replaceDocument({
    required String eventId,
    required String documentId,
    String note = '',
    List<int>? bytes,
    String? filename,
    String? link,
  }) async {
    await _api.upload('/api/documents/$documentId/versions',
        fields: {
          'note': note,
          if (link != null && link.isNotEmpty) 'link': link,
        },
        bytes: bytes,
        filename: filename);
    await loadEventDocuments(eventId);
    notifyListeners();
  }

  Future<void> decideDocument({
    required String eventId,
    required String documentId,
    required bool approved,
    String note = '',
  }) async {
    await _api.post('/api/documents/$documentId/decision', {
      'status': approved ? 'approved' : 'rejected',
      'note': note,
    });
    await Future.wait([loadEventDocuments(eventId), loadEventWorkspace(eventId)]);
    notifyListeners();
  }

  Future<void> deleteDocument(String eventId, String documentId) async {
    await _api.delete('/api/documents/$documentId');
    await Future.wait([loadEventDocuments(eventId), loadEventWorkspace(eventId)]);
    notifyListeners();
  }

  /// Download a document to a local file and return its path.
  ///
  /// The bytes have to travel through the API client because the route is
  /// authenticated — the token is a header, never a query parameter — so the
  /// URL cannot simply be handed to the system browser. The file lands in the
  /// cache directory under the document's real name, so whatever opens it
  /// shows the name the person filed it under.
  Future<String> downloadDocument(
    String documentId, {
    int? version,
    required String filename,
  }) async {
    final result = await _api.download(
      '/api/documents/$documentId/file',
      query: {if (version != null) 'version': version},
    );
    final directory = await getTemporaryDirectory();
    final safe = filename.replaceAll(RegExp(r'[^\w\-. ]'), '_');
    final file = File('${directory.path}/gwd-$documentId-${version ?? 0}-$safe');
    await file.writeAsBytes(result.bytes);
    return file.path;
  }

  // ============================================================ finance
  //
  // A record of what an event cost and whether the person who paid has been
  // repaid. Nothing here moves money, and no bank details are stored.

  final Map<String, EventFinance> _finance = {};

  EventFinance? financeFor(String eventId) => _finance[eventId];

  Future<void> loadEventFinance(String eventId) async {
    final json = await _api.get('/api/events/$eventId/bills');
    _finance[eventId] = EventFinance.fromJson(json);
    notifyListeners();
  }

  Future<void> fileBill({
    required String eventId,
    required String title,
    required double amount,
    required String category,
    String note = '',
    String paidByName = '',
    DateTime? spentOn,
    List<int>? receiptBytes,
    String? receiptName,
  }) async {
    await _api.upload(
      '/api/events/$eventId/bills',
      fields: {
        'title': title,
        'amount': amount.toString(),
        'category': category,
        'note': note,
        if (paidByName.isNotEmpty) 'paidByName': paidByName,
        if (spentOn != null) 'spentOn': spentOn.toUtc().toIso8601String(),
      },
      fieldName: 'receipt',
      bytes: receiptBytes,
      filename: receiptName,
    );
    await loadEventFinance(eventId);
  }

  Future<void> decideBill({
    required String eventId,
    required String billId,
    required bool approved,
    String note = '',
  }) async {
    await _api.post('/api/bills/$billId/decision', {
      'status': approved ? 'approved' : 'rejected',
      'note': note,
    });
    await loadEventFinance(eventId);
  }

  Future<void> settleBill({
    required String eventId,
    required String billId,
    String reference = '',
  }) async {
    await _api.post('/api/bills/$billId/settle', {'reference': reference});
    await loadEventFinance(eventId);
  }

  Future<void> deleteBill(String eventId, String billId) async {
    await _api.delete('/api/bills/$billId');
    await loadEventFinance(eventId);
  }

  /// Download a receipt to a local file and return its path. Same reasoning as
  /// [downloadDocument]: the route is authenticated, so the URL cannot simply
  /// be handed to the browser.
  Future<String> downloadReceipt(String billId, {required String filename}) async {
    final result = await _api.download('/api/bills/$billId/receipt');
    final directory = await getTemporaryDirectory();
    final safe = filename.replaceAll(RegExp(r'[^\w\-. ]'), '_');
    final file = File('${directory.path}/gwd-receipt-$billId-$safe');
    await file.writeAsBytes(result.bytes);
    return file.path;
  }

  // ============================================================= identity
  /// Set your own name and phone.
  ///
  /// Refreshes the session rather than patching locally, because the name
  /// appears in the shell, on Home, and against everything you have ever been
  /// assigned — one round trip is cheaper than hunting all of that down.
  Future<void> updateMyProfile({String? name, String? phone}) async {
    await _api.patch('/api/users/me', {
      if (name != null) 'name': name,
      if (phone != null) 'phone': phone,
    });
    await session.refresh();
    await loadMembers();
    notifyListeners();
  }

  /// Put a real name on somebody else's account.
  ///
  /// Exists because accounts are created *for* people — the seeded Lead
  /// accounts arrive with a placeholder — and whoever hands the credentials
  /// over is the one who knows whose account it is.
  Future<void> renameMember(String userId, String name) async {
    await _api.patch('/api/users/$userId/name', {'name': name});
    await loadMembers();
    // The rename may have been of somebody sitting in the approval queue, which
    // is a separate list from the directory.
    await loadPendingApprovals();
    notifyListeners();
  }

  // =========================================================== passwords
  Future<void> changePassword({
    required String current,
    required String next,
  }) async {
    // Given a long leash on purpose.
    //
    // This is the slowest call the app makes: bcrypt verifies the old password
    // and hashes the new one - a second of deliberate CPU before the database
    // is touched - and the write then goes to a hosted cluster. On the ordinary
    // twenty-second budget it times out, and the way it fails is the problem
    // rather than the wait: the server finishes the change regardless, revoking
    // the token the client is still holding, so the *next* request 401s and the
    // user is thrown back to sign-in having apparently done nothing wrong. It
    // reproduced every time on a first sign-in, which is precisely when a
    // seeded account is forced through this sheet.
    final json = await _api.post(
      '/api/auth/password',
      {'currentPassword': current, 'newPassword': next},
      ApiClient.passwordTimeout,
    );
    // The server revokes every token issued before the change — including the
    // one that just made this request — and hands back a replacement. Adopt it,
    // or succeeding at changing your password signs you straight out.
    final token = json['token'] as String?;
    if (token != null) {
      await session.adoptToken(token, user: (json['user'] as Map?)?.cast<String, dynamic>());

      // And re-handshake the socket, which is still holding the token the
      // server has just revoked. Adopting the replacement fixes REST and
      // leaves the live connection stale: its next reconnect is rejected, a
      // rejected handshake signs the user out, and the user is signed out for
      // the crime of successfully changing their password. That is precisely
      // what a seeded account hits on its very first sign-in, because the
      // forced change runs one screen in.
      socket.connect(token);
    }
    await session.refresh();
    notifyListeners();
  }

  /// Appoint somebody to a different office.
  ///
  /// The server is the authority on every rule around this - the singleton
  /// caps, not promoting yourself, only a Director appointing a Director - and
  /// it refuses with a message written to be shown as-is. The client's job is
  /// to offer the choice and repeat the answer.
  /// A null [role] keeps the one they have; a null [customTitle] leaves their
  /// title alone, and an empty one clears it.
  Future<void> changeRole(String userId, ClubRole? role, {String? customTitle}) async {
    await _api.patch('/api/users/$userId/role', {
      if (role != null) 'role': role.wire,
      if (customTitle != null) 'customTitle': customTitle,
    });
    await loadMembers();
    await loadDepartments();
    notifyListeners();
  }

  /// Reset somebody else's. Returns the temporary password, shown **once** to
  /// the person doing the reset so they can pass it on.
  Future<String> resetPasswordFor(String userId) async {
    final json = await _api.post('/api/users/$userId/reset-password');
    await loadMembers();
    notifyListeners();
    return json['temporaryPassword'] as String? ?? '';
  }

  // ============================================== help & collaboration
  Future<void> loadHelp() async {
    final json = await _api.get('/api/help');
    helpRequests = listFrom(json, 'requests', HelpRequest.fromJson);
  }

  // ------------------------------------------------------------- meetings
  Future<void> loadMeetings() async {
    final json = await _api.get('/api/meetings');
    meetingsUpcoming = listFrom(json, 'upcoming', Meeting.fromJson);
    meetingsPast = listFrom(json, 'past', Meeting.fromJson);
    canScheduleMeetings = json['canSchedule'] == true;
  }

  /// One meeting in full, with its participant list.
  ///
  /// The list endpoint deliberately does not carry every invitee — thirty
  /// meetings times thirty names is a payload nobody reads — so the detail
  /// screen asks for the one it is showing. It also returns whether *this*
  /// viewer may record attendance, so the UI never offers a control the server
  /// would refuse.
  Future<Map<String, dynamic>> meetingDetail(String id) => _api.get('/api/meetings/$id');

  /// What came out of a meeting.
  ///
  /// These are ordinary tasks carrying the meeting's id, not a private
  /// checklist — which is the whole point. A meeting screen with its own list
  /// of agreements is exactly how they get forgotten: written down in the room,
  /// appearing in nobody's work, read again only when the same thing goes wrong
  /// at the next meeting. Read live from the task list, so one completed on the
  /// Work tab shows as done here with nothing keeping the two in step.
  Future<List<ClubTask>> meetingActions(String id) async {
    final json = await _api.get('/api/meetings/$id/actions');
    return listFrom(json, 'actions', ClubTask.fromJson);
  }

  Future<void> addMeetingAction(
    String meetingId, {
    required String title,
    String description = '',
    String? assignedTo,
    String? departmentId,
    DateTime? dueDate,
    int? points,
  }) async {
    await _api.post('/api/meetings/$meetingId/actions', {
      'title': title,
      'description': description,
      if (assignedTo != null) 'assignedTo': assignedTo,
      if (departmentId != null) 'departmentId': departmentId,
      if (dueDate != null) 'dueDate': dueDate.toUtc().toIso8601String(),
      if (points != null) 'points': points,
    });
    // It is a real task, so it belongs in the real task list immediately —
    // including the asker's own, if they gave it to themselves.
    await Future.wait([loadTasks(), loadIncoming()]);
  }

  Future<void> saveMeetingNotes(String meetingId, String notes) =>
      _api.patch('/api/meetings/$meetingId', {'notes': notes});

  /// Call a meeting. Invitees arrive as named people, whole departments, or
  /// both — the server resolves a department to its members once, at creation,
  /// so the attendance sheet cannot change underneath the record later.
  Future<void> createMeeting({
    required String title,
    required DateTime date,
    String description = '',
    String startTime = '',
    String endTime = '',
    String venue = '',
    List<String> userIds = const [],
    List<String> departmentIds = const [],
  }) async {
    await _api.post('/api/meetings', {
      'title': title,
      'description': description,
      'date': date.toUtc().toIso8601String(),
      'startTime': startTime,
      'endTime': endTime,
      'venue': venue,
      'userIds': userIds,
      'departmentIds': departmentIds,
    });
    // A meeting is a commitment with a date, so the schedule and Home have to
    // know about it too — not just the meetings list.
    await Future.wait([loadMeetings(), loadSchedule(), _loadHome()]);
    notifyListeners();
  }

  Future<void> updateMeeting(
    String id, {
    String? title,
    String? description,
    DateTime? date,
    String? startTime,
    String? endTime,
    String? venue,
    MeetingStatus? status,
  }) async {
    await _api.patch('/api/meetings/$id', {
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (date != null) 'date': date.toUtc().toIso8601String(),
      if (startTime != null) 'startTime': startTime,
      if (endTime != null) 'endTime': endTime,
      if (venue != null) 'venue': venue,
      if (status != null) 'status': status.wire,
    });
    await Future.wait([loadMeetings(), loadSchedule(), _loadHome()]);
    notifyListeners();
  }

  /// Record who turned up — the whole sheet in one call.
  ///
  /// Attendance is what every profile figure is derived from, so the boards
  /// and the member list are refreshed with it rather than being left showing
  /// the previous numbers.
  Future<void> markAttendance(String meetingId, Map<String, AttendanceMark> marks) async {
    await _api.post('/api/meetings/$meetingId/attendance', {
      'attendance': marks.entries.map((e) => {'userId': e.key, 'status': e.value.wire}).toList(),
    });
    await Future.wait([loadMeetings(), loadMembers(), _loadHome()]);
    notifyListeners();
  }

  List<HelpRequest> get openHelp => helpRequests.where((h) => h.isOpen).toList();

  Future<void> askForHelp({
    required String title,
    required DateTime neededBy,
    required int maxHelpers,
    String description = '',
    List<String> skills = const [],
    String? departmentId,
    String? eventId,
  }) async {
    await _api.post('/api/help', {
      'title': title,
      'description': description,
      'skills': skills,
      'neededBy': neededBy.toUtc().toIso8601String(),
      'maxHelpers': maxHelpers,
      if (departmentId != null) 'departmentId': departmentId,
      if (eventId != null) 'eventId': eventId,
    });
    await loadHelp();
    notifyListeners();
  }

  /// Offering puts the ask on your own task list, with the deadline it carried,
  /// so the work has to be reloaded too — otherwise the new item does not show
  /// until something else happens to refresh it.
  Future<void> offerHelp(String id, {String note = ''}) async {
    await _api.post('/api/help/$id/offer', {'note': note});
    await Future.wait([loadHelp(), loadTasks(), loadSchedule(), _loadHome()]);
    notifyListeners();
  }

  /// Stepping back takes the task off your list with it, so the same surfaces
  /// need refreshing as when you offered.
  Future<void> withdrawOffer(String id) async {
    await _api.delete('/api/help/$id/offer');
    await Future.wait([loadHelp(), loadTasks(), loadSchedule(), _loadHome()]);
    notifyListeners();
  }

  Future<void> setHelpStatus(String id, HelpStatus status) async {
    await _api.post('/api/help/$id/status', {'status': status.wire});
    await loadHelp();
    notifyListeners();
  }

  Future<void> withdrawHelpRequest(String id) async {
    await _api.delete('/api/help/$id');
    helpRequests = helpRequests.where((h) => h.id != id).toList();
    notifyListeners();
  }

  // ------------------------------------------------------------ live events
  void _upsertTask(ClubTask task) {
    final index = tasks.indexWhere((t) => t.id == task.id);
    // The same rule as `loadTasks`, so a live update and a reload agree: event
    // work belongs in this list only when it is yours. Everybody else's lives
    // on its event's board.
    final belongs = task.eventId == null || task.assignedTo == _meId;
    final next = [...tasks];
    if (!belongs) {
      if (index < 0) return;
      next.removeAt(index);
    } else if (index >= 0) {
      next[index] = task;
    } else {
      next.insert(0, task);
    }
    tasks = next;
    // Every single-task change funnels through here, so this is the one place
    // that cannot be forgotten. The widget used to refresh only on a full
    // reload, on a status change, and on one socket event — so being *given* a
    // task, or picking one up by offering help, left the home screen showing a
    // stale count until something else happened to reload everything.
    unawaited(_pushToWidget());
  }

  void _onLiveEvent(LiveEvent event) {
    switch (event.name) {
      case 'task:created':
      case 'task:updated':
        final task = ClubTask.fromJson(event.data);
        _upsertTask(task);
        _nudgeMeeting(task.meetingId);
        _refreshHomeSoon();
        // Event work moving on somebody else's screen should move on this one
        // too — but only refetch the board actually open, not all of them.
        final eventId = task.eventId;
        if (eventId != null && _boards.containsKey(eventId)) {
          unawaited(loadEventBoard(eventId));
          unawaited(loadEventWorkspace(eventId));
        }
        // Same rule for the day view and the write-up: both count open work,
        // so a task finished on somebody else's phone changes what they say.
        // Only the ones actually open — a club with forty past events must not
        // refetch forty payloads because one task moved.
        if (eventId != null && _days.containsKey(eventId)) {
          unawaited(loadEventDay(eventId));
        }
        if (eventId != null && _reports.containsKey(eventId)) {
          unawaited(loadEventReport(eventId));
        }
        // No toast here either: the server writes a `taskAssigned`
        // notification for the same person at the same moment, and that is
        // where toasts come from now.
        unawaited(_pushToWidget());

      case 'notification:new':
        unawaited(loadNotifications());
        // Every live toast now comes from here.
        //
        // Toasts used to be raised from three *other* streams — a new task, a
        // new alert, a new task request — which meant the other thirty
        // notification types arrived in total silence while the app was open:
        // a meeting invite, work handed to your department, a document waiting
        // on you. The server already writes a notification for all of them,
        // with copy identical to the push, so that is the one place to read.
        _toastFor(AppNotification.fromJson(event.data));

      case 'alert:new':
        final alert = ClubAlert.fromJson(event.data);
        if (!alerts.any((a) => a.id == alert.id)) {
          alerts = [alert, ...alerts];
        }
      // No toast here: the same broadcast arrives as a `clubAlert`
      // notification, and raising one from both streams showed it twice.

      case 'taskRequest:created':
      case 'taskRequest:updated':
        unawaited(loadRequests());

      case 'accessRequest:created':
      case 'accessRequest:updated':
        unawaited(loadPendingApprovals());

      // The socket payload is intentionally thin — the category's name and
      // colour live in another collection — so refetch rather than render a
      // half-formed entry.
      case 'schedule:created':
      case 'schedule:updated':
        unawaited(loadSchedule());

      case 'schedule:deleted':
        schedule = schedule.where((e) => e.id != event.data['id']).toList();

      case 'department:created':
      case 'department:updated':
        // The live payload carries the department's own fields, never its
        // figures — member count and progress are computed per request. Built
        // from the payload alone, every rename or change of Lead showed the
        // department as "0 people, nothing done" until the next full reload.
        final index = departments.indexWhere((d) => d.id == event.data['id']);
        final before = index >= 0 ? departments[index] : null;
        final incoming = Department.fromJson({
          if (before != null) ...{
            'memberCount': before.memberCount,
            'assigned': before.assigned,
            'completed': before.completed,
            'completionRate': before.completionRate,
          },
          ...event.data,
        });
        final next = [...departments];
        if (index >= 0) {
          next[index] = incoming;
        } else {
          next.add(incoming);
        }
        departments = next;

      case 'department:deleted':
        departments = departments.where((d) => d.id != event.data['id']).toList();

      // The socket payload for an event is deliberately thin — progress and
      // team names are not on it — so refetch the list rather than rendering a
      // half-formed card.
      case 'event:created':
      case 'event:updated':
        unawaited(loadEvents());
        final id = event.data['id'] as String?;
        if (id != null && _workspaces.containsKey(id)) {
          unawaited(loadEventWorkspace(id));
          if (_timelines.containsKey(id)) unawaited(loadEventTimeline(id));
        }
        if (id != null && _days.containsKey(id)) unawaited(loadEventDay(id));
        if (id != null && _reports.containsKey(id)) unawaited(loadEventReport(id));

      case 'event:deleted':
        final id = event.data['id'];
        eventsUpcoming = eventsUpcoming.where((e) => e.id != id).toList();
        eventsOngoing = eventsOngoing.where((e) => e.id != id).toList();
        eventsCompleted = eventsCompleted.where((e) => e.id != id).toList();

      case 'eventDocument:changed':
        _refreshHomeSoon();
        final id = event.data['eventId'] as String?;
        if (id != null && _documents.containsKey(id)) {
          unawaited(loadEventDocuments(id));
          unawaited(loadEventWorkspace(id));
        }

      // Only the event's *id* travels for money and documents, never the
      // figures — so refetch, and only for the event actually open. Refetching
      // every board the app has ever loaded would turn one person filing an
      // expense into a burst of requests from everybody in the club.
      case 'bill:changed':
        _refreshHomeSoon();
        final id = event.data['eventId'] as String?;
        if (id != null && _finance.containsKey(id)) {
          unawaited(loadEventFinance(id));
          unawaited(loadEventWorkspace(id));
        }

      // A comment thread is only ever shown on an open task detail page, which
      // fetches it directly rather than through the store. Rebroadcasting is
      // enough: the page listens and refetches its own thread.
      case 'comment:changed':
        final taskId = event.data['taskId'] as String?;
        if (taskId != null) {
          commentsChangedFor.value = taskId;
          // Cleared straight away so a second comment on the *same* task still
          // fires: a ValueNotifier is silent when the value does not change,
          // which would have made every reply after the first one invisible.
          commentsChangedFor.value = null;
        }

      case 'category:changed':
        unawaited(loadCategories());
        // A retired category leaves every entry that used it without a name or
        // a colour until the schedule is refetched too.
        unawaited(loadSchedule());

      case 'help:created':
      case 'help:updated':
      case 'help:deleted':
        unawaited(loadHelp());

      case 'meeting:created':
      case 'meeting:updated':
      case 'meeting:deleted':
        unawaited(loadMeetings());
        _nudgeMeeting(event.data['id'] as String?);
        // A meeting carries a date, so the schedule and Home's "what's next"
        // move with it.
        unawaited(loadSchedule());
        _refreshHomeSoon();
        // Attendance is what every profile and department figure is derived
        // from, so recording it has to refresh those too — otherwise the
        // numbers only catch up on the next cold start.
        if (event.data['attendanceRecorded'] == true) {
          unawaited(loadMembers());
        }

      case 'user:updated':
        // Points or a role changed somewhere — the board may have moved.
        unawaited(loadLeaderboard());
        final id = event.data['id'] as String?;
        if (id == _meId) {
          session.applyLiveUser(event.data);
        } else {
          final index = members.indexWhere((m) => m.id == id);
          if (index >= 0) {
            final next = [...members];
            next[index] = Member.fromJson({
              ...event.data,
              'email': members[index].email,
              'avatarColor': members[index].avatarColor,
            });
            members = next;
          }
        }
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------- toasts

  /// Raise a live toast for a notification that just arrived.
  ///
  /// Not everything gets one. A toast interrupts whatever the person is
  /// looking at, so it is spent on what needs them — the same test
  /// [AppNotification.isActionable] applies to the accent in the list. The
  /// rest still land in Alerts and still bump the badge; they just do not
  /// shove themselves in front of somebody mid-sentence.
  ///
  /// The one exception is a club alert, which is a human deliberately
  /// interrupting everybody and has already been counted out loud in the
  /// compose sheet.
  void _toastFor(AppNotification notification) {
    final urgent = notification.type == 'clubAlert';
    if (!notification.isActionable && !urgent) return;

    _addToast(LiveToast(
      // Keyed on the notification so the same one arriving twice — a
      // reconnect replaying, say — cannot stack up.
      id: 'note-${notification.id}',
      title: notification.title.toUpperCase(),
      body: notification.body,
      kind: switch (notification.type) {
        'taskAssigned' || 'departmentTaskAssigned' => ToastKind.taskAssigned,
        'taskRequestReceived' => ToastKind.taskRequest,
        'approvalNeeded' => ToastKind.approval,
        'clubAlert' => ToastKind.alert,
        _ => ToastKind.info,
      },
      target: notification.target,
      critical: urgent || notification.isActionable,
    ));
  }

  void _addToast(LiveToast toast) {
    if (toasts.any((t) => t.id == toast.id)) return;
    toasts.insert(0, toast);
    // Stack gracefully: show at most three, oldest falls off the bottom.
    if (toasts.length > 3) toasts.removeRange(3, toasts.length);
    notifyListeners();
  }

  void dismissToast(String id) {
    toasts.removeWhere((t) => t.id == id);
    notifyListeners();
  }

  // ---------------------------------------------------- home-screen widget
  Future<void> _pushToWidget() async {
    final open = tasks.where((t) => t.assignedTo == _meId && t.status.isOpen).toList()
      ..sort(_byUrgency);
    ClubTask? next;
    for (final t in open) {
      if (t.dueDate != null) {
        next = t;
        break;
      }
    }
    next ??= open.isEmpty ? null : open.first;
    await WidgetBridge.publish(
      pendingCount: open.length,
      nextTitle: next?.title,
      nextDue: next?.dueLabel,
    );
  }
}
