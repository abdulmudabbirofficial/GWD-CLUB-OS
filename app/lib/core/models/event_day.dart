/// Running the event on the day.
///
/// Every other event screen answers "is this on track?", which is a planning
/// question asked at a desk. On the day itself nobody is planning: somebody is
/// standing in a corridor with fifteen minutes to go, and the questions are
/// "what is happening now", "what is next", and "who do I ring about the
/// projector".
library;

import 'package:flutter/painting.dart' show Color;

import 'club_event.dart';
import 'club_role.dart';
import 'club_task.dart';
import 'member.dart' show positionLineFor;


DateTime? _date(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.tryParse(value.toString())?.toLocal();
}

class RunSheetItem {
  const RunSheetItem({
    required this.id,
    required this.title,
    this.time = '',
    this.note = '',
    this.ownerUserId,
    this.ownerName,
    this.done = false,
    this.doneAt,
  });

  final String id;
  final String title;

  /// `HH:MM`, or empty for the "at some point" jobs that are not on a schedule.
  final String time;
  final String note;
  final String? ownerUserId;
  final String? ownerName;
  final bool done;
  final DateTime? doneAt;

  factory RunSheetItem.fromJson(Map<String, dynamic> json) => RunSheetItem(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        time: json['time'] as String? ?? '',
        note: json['note'] as String? ?? '',
        ownerUserId: json['ownerUserId'] as String?,
        ownerName: json['ownerName'] as String?,
        done: json['done'] == true,
        doneAt: _date(json['doneAt']),
      );

  bool get timed => time.length == 5;

  /// Minutes past midnight, for comparing against the clock. Untimed rows
  /// return null rather than a sentinel, so they can never be mistaken for
  /// something scheduled at midnight.
  int? get minutes {
    if (!timed) return null;
    final hours = int.tryParse(time.substring(0, 2));
    final mins = int.tryParse(time.substring(3));
    if (hours == null || mins == null) return null;
    return hours * 60 + mins;
  }

  /// "9:05 am" — a bare `09:05` reads like a duration.
  String get clockLabel {
    final total = minutes;
    if (total == null) return '';
    final hours = total ~/ 60;
    final mins = total % 60;
    final suffix = hours < 12 ? 'am' : 'pm';
    final twelve = hours % 12 == 0 ? 12 : hours % 12;
    return '$twelve:${mins.toString().padLeft(2, '0')} $suffix';
  }
}

class DayTeamMember {
  const DayTeamMember({
    required this.id,
    required this.name,
    required this.role,
    this.departmentId,
    this.avatarColor,
    this.mustSetName = false,
    this.phone = '',
    this.isLead = false,
  });

  final String id;
  final String name;
  final String role;
  final String? departmentId;
  final String? avatarColor;
  final bool mustSetName;

  /// Empty for anyone who is not running the event. The server decides; the
  /// client never asks for it and never has it to leak.
  final String phone;
  final bool isLead;

  factory DayTeamMember.fromJson(Map<String, dynamic> json) => DayTeamMember(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Member',
        role: json['role'] as String? ?? 'clubMember',
        departmentId: json['departmentId'] as String?,
        avatarColor: json['avatarColor'] as String?,
        mustSetName: json['mustSetName'] == true,
        phone: json['phone'] as String? ?? '',
        isLead: json['isLead'] == true,
      );

  /// Never print [name] raw. An account handed to somebody who has not yet
  /// chosen a name reads as "No name set", greyed, with the role underneath —
  /// the same rule every other surface in the app follows.
  String get displayName => mustSetName ? 'No name set' : name;
  bool get isUnnamed => mustSetName;

  /// The line under the name. The day view has no department names to hand, so
  /// this is the bare position — which is the one place that is acceptable,
  /// because everybody here is on the same event.
  String get positionLine => positionLineFor(ClubRole.fromWire(role), null);

  Color get tint {
    final hex = avatarColor;
    if (hex != null && hex.startsWith('#') && hex.length == 7) {
      return Color(int.parse('FF${hex.substring(1)}', radix: 16));
    }
    return const Color(0xFF52525B);
  }

  String get initials {
    if (mustSetName) return '?';
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    if (words.isEmpty) return '?';
    if (words.length == 1) {
      final w = words.first;
      return (w.length >= 2 ? w.substring(0, 2) : w).toUpperCase();
    }
    return '${words.first[0]}${words.last[0]}'.toUpperCase();
  }
}

class DayTask {
  const DayTask({
    required this.id,
    required this.title,
    required this.status,
    this.dueDate,
    this.departmentId,
    this.assignedTo,
  });

  final String id;
  final String title;
  final TaskStatus status;
  final DateTime? dueDate;
  final String? departmentId;
  final String? assignedTo;

  factory DayTask.fromJson(Map<String, dynamic> json) => DayTask(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        status: TaskStatus.fromWire(json['status'] as String?),
        dueDate: _date(json['dueDate']),
        departmentId: json['departmentId'] as String?,
        assignedTo: json['assignedTo'] as String?,
      );
}

class EventDay {
  const EventDay({
    required this.event,
    this.runSheet = const [],
    this.runSheetDone = 0,
    this.canEdit = false,
    this.team = const [],
    this.openTasks = const [],
    this.openTaskCount = 0,
    this.pendingApprovals = 0,
  });

  final ClubEvent event;
  final List<RunSheetItem> runSheet;
  final int runSheetDone;
  final bool canEdit;
  final List<DayTeamMember> team;
  final List<DayTask> openTasks;
  final int openTaskCount;
  final int pendingApprovals;

  factory EventDay.fromJson(Map<String, dynamic> json) => EventDay(
        event: ClubEvent.fromJson((json['event'] as Map).cast<String, dynamic>()),
        runSheet: (json['runSheet'] as List? ?? const [])
            .whereType<Map>()
            .map((i) => RunSheetItem.fromJson(i.cast<String, dynamic>()))
            .toList(growable: false),
        runSheetDone: (json['runSheetDone'] as num?)?.toInt() ?? 0,
        canEdit: json['canEdit'] == true,
        team: (json['team'] as List? ?? const [])
            .whereType<Map>()
            .map((m) => DayTeamMember.fromJson(m.cast<String, dynamic>()))
            .toList(growable: false),
        openTasks: (json['openTasks'] as List? ?? const [])
            .whereType<Map>()
            .map((t) => DayTask.fromJson(t.cast<String, dynamic>()))
            .toList(growable: false),
        openTaskCount: (json['openTaskCount'] as num?)?.toInt() ?? 0,
        pendingApprovals: (json['pendingApprovals'] as num?)?.toInt() ?? 0,
      );

  /// What is on right now, derived from **this device's** clock.
  ///
  /// The server deliberately does not compute it: the person holding the phone
  /// is the one standing in the room, and a `currentItem` baked into a response
  /// goes stale the moment the screen is left open. Deriving it here is one
  /// source of truth rather than two that disagree five minutes apart.
  ///
  /// "Now" is the last timed row whose time has passed and which is not yet
  /// ticked off — so an overrunning item stays current rather than the screen
  /// jumping ahead to something that has not started.
  RunSheetItem? currentAt(DateTime now) {
    final minutes = now.hour * 60 + now.minute;
    RunSheetItem? current;
    for (final item in runSheet) {
      final at = item.minutes;
      if (at == null || at > minutes) continue;
      current = item;
    }
    return current;
  }

  /// The first timed row still to come.
  RunSheetItem? nextAt(DateTime now) {
    final minutes = now.hour * 60 + now.minute;
    for (final item in runSheet) {
      final at = item.minutes;
      if (at != null && at > minutes) return item;
    }
    return null;
  }

  /// The untimed jobs, which belong in their own list rather than pretending
  /// to a place on the schedule.
  List<RunSheetItem> get anytime =>
      runSheet.where((i) => !i.timed).toList(growable: false);

  List<RunSheetItem> get scheduled =>
      runSheet.where((i) => i.timed).toList(growable: false);
}
