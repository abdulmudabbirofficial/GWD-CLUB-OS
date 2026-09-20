import 'package:flutter/material.dart';

import '../../app/theme/gwd_theme.dart';

/// A meeting, its invitee list, and who turned up.
///
/// Distinct from a schedule entry, where "Meeting" is only a category: a
/// schedule row is a date and a title, and cannot say who was asked, who came,
/// or what anybody's attendance record is.
enum MeetingStatus {
  scheduled,
  held,
  cancelled;

  static MeetingStatus fromWire(String? value) => switch (value) {
        'held' => MeetingStatus.held,
        'cancelled' => MeetingStatus.cancelled,
        _ => MeetingStatus.scheduled,
      };

  String get wire => name;

  String get label => switch (this) {
        MeetingStatus.scheduled => 'Scheduled',
        MeetingStatus.held => 'Held',
        MeetingStatus.cancelled => 'Cancelled',
      };

  Color get tint => switch (this) {
        MeetingStatus.scheduled => const Color(0xFF2563EB),
        MeetingStatus.held => const Color(0xFF16A34A),
        MeetingStatus.cancelled => const Color(0xFF9A9AA4),
      };

  IconData get icon => switch (this) {
        MeetingStatus.scheduled => Icons.event_available_outlined,
        MeetingStatus.held => GwdIcons.done,
        MeetingStatus.cancelled => GwdIcons.meetingOff,
      };
}

/// Whether somebody turned up.
///
/// `invited` means nobody has recorded it yet — deliberately distinct from
/// `absent`, because "not marked" and "did not come" are different facts and
/// conflating them would quietly damage people's attendance records.
enum AttendanceMark {
  invited,
  attended,
  absent,
  excused;

  static AttendanceMark fromWire(String? value) => switch (value) {
        'attended' => AttendanceMark.attended,
        'absent' => AttendanceMark.absent,
        'excused' => AttendanceMark.excused,
        _ => AttendanceMark.invited,
      };

  String get wire => name;

  String get label => switch (this) {
        AttendanceMark.invited => 'Not recorded',
        AttendanceMark.attended => 'Came',
        AttendanceMark.absent => 'Did not come',
        AttendanceMark.excused => 'Excused',
      };

  Color get tint => switch (this) {
        AttendanceMark.invited => const Color(0xFF9A9AA4),
        AttendanceMark.attended => const Color(0xFF16A34A),
        AttendanceMark.absent => const Color(0xFFDC2626),
        AttendanceMark.excused => const Color(0xFFD97706),
      };

  IconData get icon => switch (this) {
        AttendanceMark.invited => GwdIcons.notRecorded,
        AttendanceMark.attended => GwdIcons.attended,
        AttendanceMark.absent => GwdIcons.absent,
        AttendanceMark.excused => GwdIcons.excused,
      };
}

class MeetingParticipant {
  const MeetingParticipant({
    required this.id,
    required this.name,
    required this.status,
    this.via = 'person',
  });

  final String id;
  final String name;
  final AttendanceMark status;

  /// How they came to be invited: named individually, swept in with their
  /// department, or the person who called it.
  final String via;

  bool get viaDepartment => via == 'department';
  bool get isOrganiser => via == 'organiser';

  factory MeetingParticipant.fromJson(Map<String, dynamic> json) => MeetingParticipant(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? 'Member',
        status: AttendanceMark.fromWire(json['status'] as String?),
        via: json['via'] as String? ?? 'person',
      );
}

class Meeting {
  const Meeting({
    required this.id,
    required this.title,
    required this.date,
    required this.status,
    required this.createdByName,
    required this.participants,
    this.description = '',
    this.startTime = '',
    this.endTime = '',
    this.venue = '',
    this.notes = '',
    this.departments = const [],
    this.invitedCount = 0,
    this.attendedCount = 0,
    this.attendanceRecorded = false,
    this.isInvited = false,
    this.myStatus,
  });

  final String id;
  final String title;
  final String description;
  final DateTime date;
  final String startTime;
  final String endTime;
  final String venue;

  /// What was decided.
  ///
  /// One free-text field rather than a structured minutes format. Nobody in
  /// a club takes formal minutes, and a form with "motion" and "resolution"
  /// on it gets left empty — whereas four lines of "we agreed to move the
  /// fest to the 20th" is what actually gets written, and is what anybody
  /// needs three weeks later.
  final String notes;
  final MeetingStatus status;
  final String createdByName;

  /// Departments invited wholesale. "the Marketing team" reads better on a
  /// card than eleven names.
  final List<({String id, String name})> departments;

  final List<MeetingParticipant> participants;
  final int invitedCount;
  final int attendedCount;

  /// Has anybody actually done the marking? Without this the UI cannot tell
  /// "nobody came" from "nobody has recorded it yet".
  final bool attendanceRecorded;

  final bool isInvited;
  final AttendanceMark? myStatus;

  bool get isCancelled => status == MeetingStatus.cancelled;

  /// By calendar day, never by timestamp. A 10am meeting is still today's
  /// meeting at 2pm — comparing a stored time against `now` is what made
  /// events vanish on the morning they ran.
  bool get isToday {
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month && date.day == now.day;
  }

  bool get isPast {
    final today = DateTime.now();
    final day = DateTime(date.year, date.month, date.day);
    return day.isBefore(DateTime(today.year, today.month, today.day));
  }

  /// "17:00–18:00 · Seminar Hall 1", skipping whatever is missing.
  String get whenAndWhere {
    final parts = <String>[];
    if (startTime.isNotEmpty) {
      parts.add(endTime.isNotEmpty ? '$startTime–$endTime' : startTime);
    }
    if (venue.isNotEmpty) parts.add(venue);
    return parts.join(' · ');
  }

  /// "Tech and Production", or the headcount when it was individuals.
  String get whoLabel {
    if (departments.isNotEmpty) {
      final names = departments.map((d) => d.name).toList();
      if (names.length == 1) return '${names.first} team';
      if (names.length == 2) return '${names[0]} and ${names[1]} teams';
      return '${names.length} teams';
    }
    return invitedCount == 1 ? '1 person' : '$invitedCount people';
  }

  factory Meeting.fromJson(Map<String, dynamic> json) => Meeting(
        id: json['id'] as String,
        title: json['title'] as String? ?? 'Meeting',
        description: json['description'] as String? ?? '',
        date: DateTime.tryParse(json['date']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
        startTime: json['startTime'] as String? ?? '',
        endTime: json['endTime'] as String? ?? '',
        venue: json['venue'] as String? ?? '',
        notes: json['notes'] as String? ?? '',
        status: MeetingStatus.fromWire(json['status'] as String?),
        createdByName: json['createdByName'] as String? ?? 'Member',
        departments: ((json['departments'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => (
                  id: e['id'] as String? ?? '',
                  name: e['name'] as String? ?? 'Department',
                ))
            .toList(growable: false),
        participants: ((json['participants'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => MeetingParticipant.fromJson(e.cast<String, dynamic>()))
            .toList(growable: false),
        invitedCount: (json['invitedCount'] as num?)?.toInt() ?? 0,
        attendedCount: (json['attendedCount'] as num?)?.toInt() ?? 0,
        attendanceRecorded: json['attendanceRecorded'] == true,
        isInvited: json['isInvited'] == true,
        myStatus:
            json['myStatus'] == null ? null : AttendanceMark.fromWire(json['myStatus'] as String?),
      );
}

/// One person's attendance record, derived from the meetings themselves.
class AttendanceRecord {
  const AttendanceRecord({
    this.invited = 0,
    this.attended = 0,
    this.absent = 0,
    this.upcoming = 0,
    this.rate,
  });

  final int invited;
  final int attended;
  final int absent;
  final int upcoming;

  /// Null when nothing has been recorded yet.
  ///
  /// Deliberately nullable rather than 0: "no meetings marked" and "came to
  /// none of them" are different facts, and showing 0% for the first reads
  /// like a failing grade somebody has not earned.
  final int? rate;

  bool get hasData => rate != null;

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) => AttendanceRecord(
        invited: (json['invited'] as num?)?.toInt() ?? 0,
        attended: (json['attended'] as num?)?.toInt() ?? 0,
        absent: (json['absent'] as num?)?.toInt() ?? 0,
        upcoming: (json['upcoming'] as num?)?.toInt() ?? 0,
        rate: (json['rate'] as num?)?.toInt(),
      );
}
