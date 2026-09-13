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
import '../models/event_document.dart';
import '../models/help_request.dart';
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
    this.taskId,
    this.critical = false,
  });

  final String id;
  final String title;
  final String body;
  final ToastKind kind;
  final String? taskId;
  final bool critical;
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
  });

  final String id;
  final String title;
  final DateTime date;
  final String categoryName;
  final String categoryIcon;
  final String categoryColorHex;
  final String location;
  final String? taskId;

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
    this.canViewAudit = false,
    this.canAwardPoints = false,
    this.earnsPoints = true,
    this.onLeaderboard = true,
    this.pendingApprovals = 0,
  });

  final bool canAssign;
  final bool canEditSchedule;
  final bool canCreateScheduleEntry;
  final bool canBroadcast;
  final bool canManageDepartments;
  final bool canViewAudit;
  final bool canAwardPoints;
  final bool earnsPoints;
  final bool onLeaderboard;
  final int pendingApprovals;

  factory Capabilities.fromJson(Map<String, dynamic> json) => Capabilities(
        canAssign: json['canAssign'] as bool? ?? false,
        canEditSchedule: json['canEditSchedule'] as bool? ?? false,
        canCreateScheduleEntry: json['canCreateScheduleEntry'] as bool? ?? false,
        canBroadcast: json['canBroadcast'] as bool? ?? false,
        canManageDepartments: json['canManageDepartments'] as bool? ?? false,
        canViewAudit: json['canViewAudit'] as bool? ?? false,
        canAwardPoints: json['canAwardPoints'] as bool? ?? false,
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

  // --- help & collaboration -------------------------------------------------
  List<HelpRequest> helpRequests = const [];

  WhatsNext whatsNext = const WhatsNext();
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
      ]);
      if (capabilities.canViewAudit || session.role == ClubRole.clubLead) {
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
    progress = WeekProgress.fromJson(
        (json['progress'] as Map?)?.cast<String, dynamic>() ?? const {});

    today = ((json['today'] as List?) ?? [])
        .whereType<Map>()
        .map((e) => TodayItem.fromJson(e.cast<String, dynamic>()))
        .toList();

    final next = json['whatsNext'] as Map<String, dynamic>?;
    if (next == null) {
      whatsNext = const WhatsNext();
    } else if (next['kind'] == 'task' && next['task'] != null) {
      whatsNext = WhatsNext(task: ClubTask.fromJson((next['task'] as Map).cast<String, dynamic>()));
    } else if (next['kind'] == 'schedule' && next['entry'] != null) {
      whatsNext = WhatsNext(
          entry: ScheduleEntry.fromJson((next['entry'] as Map).cast<String, dynamic>()));
    } else {
      whatsNext = const WhatsNext();
    }
  }

  Future<void> loadTasks() async {
    final json = await _api.get('/api/tasks');
    tasks = listFrom(json, 'tasks', ClubTask.fromJson);
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
      tasks.where((t) => t.assignedBy == _meId && t.assignedTo != _meId).toList()
        ..sort(_byUrgency);

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
  List<ScheduleCategory> get activeCategories =>
      categories.where((c) => c.active).toList();

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
      if (departmentId != null)
        'departmentId': departmentId
      else
        'assignedTo': assignedTo,
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
      await _loadHome();
      await session.refresh();
      unawaited(loadSchedule());
      // Completing work changes a completion rate, which is what the board
      // ranks on.
      unawaited(loadLeaderboard());
    } on ApiException {
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

  Future<List<TaskComment>> taskComments(String taskId) async {
    final json = await _api.get('/api/tasks/$taskId');
    return listFrom(json, 'comments', TaskComment.fromJson);
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
  Future<void> respondToRequest(String id, {required bool accept}) async {
    await _api.post('/api/task-requests/$id/${accept ? 'accept' : 'decline'}');
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
  Future<Map<String, dynamic>> memberStats(String userId) =>
      _api.get('/api/users/$userId/stats');

  /// The club as an org chart: executive seats, then departments with their
  /// Lead and headline progress.
  Future<Map<String, dynamic>> structure() =>
      _api.get('/api/departments/structure');

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
  Future<List<Map<String, String>>> alertAudiences() async {
    final json = await _api.get('/api/alerts/audiences');
    return ((json['audiences'] as List?) ?? [])
        .whereType<Map>()
        .map((e) => {'id': '${e['id']}', 'label': '${e['label']}'})
        .toList();
  }

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

  /// Everyone in recognition, flattened — for looking one person up without
  /// caring which list they are in.
  Member? recognitionRowFor(String? userId) {
    if (userId == null) return null;
    for (final group in recognition) {
      if (group.lead?.id == userId) return group.lead;
      for (final m in group.members) {
        if (m.id == userId) return m;
      }
    }
    for (final m in unaffiliated) {
      if (m.id == userId) return m;
    }
    return null;
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

  ClubEvent? eventById(String? id) {
    if (id == null) return null;
    for (final list in [eventsOngoing, eventsUpcoming, eventsCompleted]) {
      for (final event in list) {
        if (event.id == id) return event;
      }
    }
    return null;
  }

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

  Future<Map<String, dynamic>> eventChecklist(String id) =>
      _api.get('/api/events/$id/checklist');

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
    });
    await loadEvents();
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

  Future<void> addEventDepartment(String eventId, String departmentId,
      {String notes = ''}) async {
    await _api.post('/api/events/$eventId/departments',
        {'departmentId': departmentId, 'notes': notes});
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
    await _api.post('/api/events/$eventId/tasks/$taskId/claim',
        {if (userId != null) 'userId': userId});
    await Future.wait([loadEventBoard(eventId), loadTasks()]);
    notifyListeners();
  }

  /// Move a card on an event board.
  ///
  /// Optimistic: the card moves immediately and snaps back if the server
  /// refuses, because a board that waits for a round trip before the card
  /// moves feels broken on college Wi-Fi.
  Future<void> setEventTaskStatus(
      String eventId, EventTaskCard card, TaskStatus next) async {
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
    final json = await _api.post('/api/auth/password', {
      'currentPassword': current,
      'newPassword': next,
    });
    // The server revokes every token issued before the change — including the
    // one that just made this request — and hands back a replacement. Adopt it,
    // or succeeding at changing your password signs you straight out.
    final token = json['token'] as String?;
    if (token != null) {
      await session.adoptToken(token, user: (json['user'] as Map?)?.cast<String, dynamic>());
    }
    await session.refresh();
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
    final next = [...tasks];
    if (index >= 0) {
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
        final existing = tasks.any((t) => t.id == task.id);
        _upsertTask(task);
        // Event work moving on somebody else's screen should move on this one
        // too — but only refetch the board actually open, not all of them.
        final eventId = task.eventId;
        if (eventId != null && _boards.containsKey(eventId)) {
          unawaited(loadEventBoard(eventId));
          unawaited(loadEventWorkspace(eventId));
        }
        if (event.name == 'task:created' && !existing && task.assignedTo == _meId) {
          _addToast(LiveToast(
            id: 'task-${task.id}',
            title: 'NEW TASK',
            body: task.title,
            kind: ToastKind.taskAssigned,
            taskId: task.id,
            critical: true,
          ));
        }
        unawaited(_pushToWidget());

      case 'notification:new':
        unawaited(loadNotifications());

      case 'alert:new':
        final alert = ClubAlert.fromJson(event.data);
        if (!alerts.any((a) => a.id == alert.id)) {
          alerts = [alert, ...alerts];
        }
        _addToast(LiveToast(
          id: 'alert-${alert.id}',
          title: alert.urgency == AlertUrgency.urgent
              ? 'URGENT · ${alert.senderName}'
              : 'CLUB ALERT · ${alert.senderName}',
          body: alert.title,
          kind: ToastKind.alert,
          critical: alert.urgency != AlertUrgency.normal,
        ));

      case 'taskRequest:created':
        final request = TaskRequest.fromJson(event.data);
        if (request.toUserId == _meId) {
          _addToast(LiveToast(
            id: 'req-${request.id}',
            title: 'TASK REQUEST',
            body: '${request.fromName} asked you to take on "${request.title}".',
            kind: ToastKind.taskRequest,
            critical: true,
          ));
          unawaited(loadRequests());
        }

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
        final incoming = Department.fromJson(event.data);
        final index = departments.indexWhere((d) => d.id == incoming.id);
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

      case 'event:deleted':
        final id = event.data['id'];
        eventsUpcoming = eventsUpcoming.where((e) => e.id != id).toList();
        eventsOngoing = eventsOngoing.where((e) => e.id != id).toList();
        eventsCompleted = eventsCompleted.where((e) => e.id != id).toList();

      case 'eventDocument:changed':
        final id = event.data['eventId'] as String?;
        if (id != null && _documents.containsKey(id)) {
          unawaited(loadEventDocuments(id));
          unawaited(loadEventWorkspace(id));
        }

      case 'help:created':
      case 'help:updated':
      case 'help:deleted':
        unawaited(loadHelp());

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

  @visibleForTesting
  void debugAddToast(LiveToast toast) => _addToast(toast);

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
