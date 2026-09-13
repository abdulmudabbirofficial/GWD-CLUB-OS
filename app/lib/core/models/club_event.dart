import 'package:flutter/material.dart';

import 'club_task.dart';

/// An event is a *project*: a team, department responsibilities, the work under
/// those, and the official paperwork. Not to be confused with a
/// [ScheduleEntry], which is a date and a title on the club calendar.
enum EventStatus {
  draft,
  planning,
  approved,
  ongoing,
  completed,
  cancelled;

  static EventStatus fromWire(String? value) => switch (value) {
        'draft' => EventStatus.draft,
        'approved' => EventStatus.approved,
        'ongoing' => EventStatus.ongoing,
        'completed' => EventStatus.completed,
        'cancelled' => EventStatus.cancelled,
        _ => EventStatus.planning,
      };

  String get wire => name;

  String get label => switch (this) {
        EventStatus.draft => 'Draft',
        EventStatus.planning => 'Planning',
        EventStatus.approved => 'Approved',
        EventStatus.ongoing => 'Happening now',
        EventStatus.completed => 'Done',
        EventStatus.cancelled => 'Cancelled',
      };

  Color get tint => switch (this) {
        EventStatus.draft => const Color(0xFF9A9AA4),
        EventStatus.planning => const Color(0xFF2563EB),
        EventStatus.approved => const Color(0xFF0891B2),
        EventStatus.ongoing => const Color(0xFFDC2626),
        EventStatus.completed => const Color(0xFF16A34A),
        EventStatus.cancelled => const Color(0xFF9A9AA4),
      };

  IconData get icon => switch (this) {
        EventStatus.draft => Icons.edit_note_rounded,
        EventStatus.planning => Icons.architecture_rounded,
        EventStatus.approved => Icons.verified_outlined,
        EventStatus.ongoing => Icons.sensors_rounded,
        EventStatus.completed => Icons.check_circle_rounded,
        EventStatus.cancelled => Icons.cancel_outlined,
      };

  /// Which statuses a manager may move to from here. Deliberately a short
  /// forward path plus an escape hatch — an event that can go anywhere from
  /// anywhere means the status stops telling you anything.
  List<EventStatus> get nextOptions => switch (this) {
        EventStatus.draft => const [EventStatus.planning, EventStatus.cancelled],
        EventStatus.planning => const [EventStatus.approved, EventStatus.cancelled],
        EventStatus.approved => const [EventStatus.ongoing, EventStatus.completed, EventStatus.cancelled],
        EventStatus.ongoing => const [EventStatus.completed, EventStatus.cancelled],
        EventStatus.completed => const [EventStatus.ongoing],
        EventStatus.cancelled => const [EventStatus.planning],
      };
}

DateTime? _date(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.tryParse(value.toString())?.toLocal();
}

List<String> _ids(dynamic value) =>
    value is List ? value.map((e) => e.toString()).toList(growable: false) : const [];

class ClubEvent {
  const ClubEvent({
    required this.id,
    required this.name,
    required this.date,
    required this.status,
    this.description = '',
    this.type = 'event',
    this.startTime = '',
    this.endTime = '',
    this.venue = '',
    this.banner,
    this.organizingDepartmentId,
    this.organizingDepartmentName,
    this.leadUserId,
    this.leadName,
    this.supportingDepartmentIds = const [],
    this.teamUserIds = const [],
    this.speakerName = '',
    this.guestDetails = '',
    this.externalOrganisation = '',
    this.taskCount = 0,
    this.taskCompleted = 0,
    this.progress = 0,
  });

  final String id;
  final String name;
  final String description;
  final String type;
  final DateTime date;
  final String startTime;
  final String endTime;
  final String venue;
  final EventStatus status;

  /// A colour rather than an image. Clubs rarely have artwork ready at the
  /// point an event is created, and an empty grey rectangle looks broken —
  /// whereas a deliberate colour, stable per event, looks designed.
  final String? banner;

  final String? organizingDepartmentId;
  final String? organizingDepartmentName;
  final String? leadUserId;
  final String? leadName;
  final List<String> supportingDepartmentIds;
  final List<String> teamUserIds;

  final String speakerName;
  final String guestDetails;
  final String externalOrganisation;

  final int taskCount;
  final int taskCompleted;
  final int progress;

  factory ClubEvent.fromJson(Map<String, dynamic> json) => ClubEvent(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Untitled event',
        description: json['description'] as String? ?? '',
        type: json['type'] as String? ?? 'event',
        date: _date(json['date']) ?? DateTime.now(),
        startTime: json['startTime'] as String? ?? '',
        endTime: json['endTime'] as String? ?? '',
        venue: json['venue'] as String? ?? '',
        status: EventStatus.fromWire(json['status'] as String?),
        banner: json['banner'] as String?,
        organizingDepartmentId: json['organizingDepartmentId'] as String?,
        organizingDepartmentName: json['organizingDepartmentName'] as String?,
        leadUserId: json['leadUserId'] as String?,
        leadName: json['leadName'] as String?,
        supportingDepartmentIds: _ids(json['supportingDepartmentIds']),
        teamUserIds: _ids(json['teamUserIds']),
        speakerName: json['speakerName'] as String? ?? '',
        guestDetails: json['guestDetails'] as String? ?? '',
        externalOrganisation: json['externalOrganisation'] as String? ?? '',
        taskCount: (json['taskCount'] as num?)?.toInt() ?? 0,
        taskCompleted: (json['taskCompleted'] as num?)?.toInt() ?? 0,
        progress: (json['progress'] as num?)?.toInt() ?? 0,
      );

  Color get bannerColor {
    final hex = banner;
    if (hex == null || hex.length < 7) return const Color(0xFFDC2626);
    return Color(int.parse('FF${hex.substring(1)}', radix: 16));
  }

  int get daysAway {
    final now = DateTime.now();
    return DateTime(date.year, date.month, date.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
  }

  /// "Today", "Tomorrow", "In 5 days", "3 weeks ago" — a phrase, because a bare
  /// date makes you do arithmetic to know whether to panic.
  String get whenLabel {
    final days = daysAway;
    if (days == 0) return 'Today';
    if (days == 1) return 'Tomorrow';
    if (days == -1) return 'Yesterday';
    if (days > 1 && days < 7) return 'In $days days';
    if (days >= 7 && days < 14) return 'Next week';
    if (days >= 14) return 'In ${(days / 7).round()} weeks';
    if (days > -7) return '${-days} days ago';
    return '${(-days / 7).round()} weeks ago';
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String get dateLabel => '${date.day} ${_months[date.month - 1]}';
  String get fullDateLabel => '${date.day} ${_months[date.month - 1]} ${date.year}';

  String get timeLabel {
    if (startTime.isEmpty) return '';
    return endTime.isEmpty ? startTime : '$startTime – $endTime';
  }
}

/// One department's share of an event, with its progress.
class EventDepartment {
  const EventDepartment({
    required this.departmentId,
    required this.name,
    required this.total,
    required this.done,
    required this.progress,
    this.notes = '',
  });

  final String departmentId;
  final String name;
  final String notes;
  final int total;
  final int done;
  final int progress;

  factory EventDepartment.fromJson(Map<String, dynamic> json) => EventDepartment(
        departmentId: json['departmentId'] as String? ?? '',
        name: json['name'] as String? ?? 'Department',
        notes: json['notes'] as String? ?? '',
        total: (json['total'] as num?)?.toInt() ?? 0,
        done: (json['done'] as num?)?.toInt() ?? 0,
        progress: (json['progress'] as num?)?.toInt() ?? 0,
      );
}

class EventTeamMember {
  const EventTeamMember({
    required this.id,
    required this.name,
    required this.role,
    required this.isLead,
    this.avatarColor,
  });

  final String id;
  final String name;
  final String role;
  final bool isLead;
  final String? avatarColor;

  factory EventTeamMember.fromJson(Map<String, dynamic> json) => EventTeamMember(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? 'Member',
        role: json['role'] as String? ?? 'clubMember',
        isLead: json['isLead'] == true,
        avatarColor: json['avatarColor'] as String?,
      );
}

/// A due date on the event, flattened for the overview.
class EventDeadline {
  const EventDeadline({
    required this.id,
    required this.title,
    required this.dueDate,
    required this.overdue,
    this.departmentName,
  });

  final String id;
  final String title;
  final DateTime dueDate;
  final bool overdue;
  final String? departmentName;

  factory EventDeadline.fromJson(Map<String, dynamic> json) => EventDeadline(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        dueDate: _date(json['dueDate']) ?? DateTime.now(),
        overdue: json['overdue'] == true,
        departmentName: json['departmentName'] as String?,
      );
}

/// One line of the event's history.
class EventActivity {
  const EventActivity({
    required this.at,
    required this.kind,
    required this.text,
    this.who,
  });

  final DateTime at;
  final String kind;
  final String text;
  final String? who;

  factory EventActivity.fromJson(Map<String, dynamic> json) => EventActivity(
        at: _date(json['at']) ?? DateTime.now(),
        kind: json['kind'] as String? ?? '',
        text: json['text'] as String? ?? '',
        who: json['who'] as String?,
      );

  IconData get icon => switch (kind) {
        'taskCompleted' => Icons.check_circle_outline_rounded,
        'document' => Icons.attach_file_rounded,
        'event.create' => Icons.auto_awesome_rounded,
        'event.status' => Icons.flag_outlined,
        'document.decision' => Icons.verified_outlined,
        _ => Icons.circle_outlined,
      };
}

/// Everything the event Overview tab needs, in one object.
class EventWorkspace {
  const EventWorkspace({
    required this.event,
    required this.team,
    required this.departments,
    required this.deadlines,
    required this.canManage,
    required this.documentCount,
    required this.approvalsApproved,
    required this.approvalsPending,
  });

  final ClubEvent event;
  final List<EventTeamMember> team;
  final List<EventDepartment> departments;
  final List<EventDeadline> deadlines;
  final bool canManage;
  final int documentCount;
  final int approvalsApproved;
  final int approvalsPending;

  factory EventWorkspace.fromJson(Map<String, dynamic> json) {
    final docs = (json['documents'] as Map?)?.cast<String, dynamic>() ?? const {};
    return EventWorkspace(
      event: ClubEvent.fromJson((json['event'] as Map).cast<String, dynamic>()),
      team: ((json['team'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => EventTeamMember.fromJson(e.cast<String, dynamic>()))
          .toList(growable: false),
      departments: ((json['departments'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => EventDepartment.fromJson(e.cast<String, dynamic>()))
          .toList(growable: false),
      deadlines: ((json['upcomingDeadlines'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => EventDeadline.fromJson(e.cast<String, dynamic>()))
          .toList(growable: false),
      canManage: json['canManage'] == true,
      documentCount: (docs['total'] as num?)?.toInt() ?? 0,
      approvalsApproved: (docs['approvalsApproved'] as num?)?.toInt() ?? 0,
      approvalsPending: (docs['approvalsPending'] as num?)?.toInt() ?? 0,
    );
  }
}

/// A card on the event board. Carries the display names the board needs so it
/// does not have to cross-reference the member list for every card.
class EventTaskCard {
  const EventTaskCard({
    required this.id,
    required this.title,
    required this.status,
    this.description = '',
    this.departmentId,
    this.departmentName,
    this.assignedTo,
    this.assigneeName,
    this.assigneeColor,
    this.dueDate,
    this.priority = 'normal',
    this.commentCount = 0,
  });

  final String id;
  final String title;
  final String description;
  final TaskStatus status;
  final String? departmentId;
  final String? departmentName;
  final String? assignedTo;
  final String? assigneeName;
  final String? assigneeColor;
  final DateTime? dueDate;
  final String priority;
  final int commentCount;

  factory EventTaskCard.fromJson(Map<String, dynamic> json) => EventTaskCard(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        status: TaskStatus.fromWire(json['status'] as String?),
        departmentId: json['departmentId'] as String?,
        departmentName: json['departmentName'] as String?,
        assignedTo: json['assignedTo'] as String?,
        assigneeName: json['assigneeName'] as String?,
        assigneeColor: json['assigneeColor'] as String?,
        dueDate: _date(json['dueDate']),
        priority: json['priority'] as String? ?? 'normal',
        commentCount: (json['commentCount'] as num?)?.toInt() ?? 0,
      );

  bool get isOverdue =>
      dueDate != null && status.isOpen && dueDate!.isBefore(DateTime.now());

  Color get accent {
    final hex = assigneeColor;
    if (hex == null || hex.length < 7) return status.tint;
    return Color(int.parse('FF${hex.substring(1)}', radix: 16));
  }
}
