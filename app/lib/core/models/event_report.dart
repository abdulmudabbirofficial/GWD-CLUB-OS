/// What happened, and what to do differently.
///
/// Half of this is **derived and never typed**: how many tasks were completed,
/// what it cost, how many people were on it. Asking somebody to fill those in
/// by hand produces numbers that are wrong, and a report with one wrong number
/// in it is a report nobody reads the rest of.
///
/// The typed half is three questions, deliberately not ten. A form long enough
/// to feel like homework gets submitted empty, and an empty report is worse
/// than none — it looks like the event went fine.
library;

import 'club_event.dart';


DateTime? _date(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.tryParse(value.toString())?.toLocal();
}

class EventReportEntry {
  const EventReportEntry({
    this.attendance,
    this.highlights = '',
    this.challenges = '',
    this.learnings = '',
    this.submittedByName,
    this.submittedAt,
    this.updatedAt,
  });

  final int? attendance;
  final String highlights;
  final String challenges;
  final String learnings;
  final String? submittedByName;
  final DateTime? submittedAt;
  final DateTime? updatedAt;

  factory EventReportEntry.fromJson(Map<String, dynamic> json) => EventReportEntry(
        attendance: (json['attendance'] as num?)?.toInt(),
        highlights: json['highlights'] as String? ?? '',
        challenges: json['challenges'] as String? ?? '',
        learnings: json['learnings'] as String? ?? '',
        submittedByName: json['submittedByName'] as String?,
        submittedAt: _date(json['submittedAt']),
        updatedAt: _date(json['updatedAt']),
      );

  bool get isEmpty =>
      attendance == null &&
      highlights.isEmpty &&
      challenges.isEmpty &&
      learnings.isEmpty;
}

class EventReportFigures {
  const EventReportFigures({
    this.taskCount = 0,
    this.taskCompleted = 0,
    this.pointsEarned = 0,
    this.departmentCount = 0,
    this.teamSize = 0,
    this.spentPaise = 0,
    this.owedPaise = 0,
    this.billCount = 0,
    this.documentCount = 0,
    this.approvalsApproved = 0,
    this.runSheetTotal = 0,
    this.runSheetDone = 0,
  });

  final int taskCount;
  final int taskCompleted;
  final int pointsEarned;
  final int departmentCount;
  final int teamSize;

  /// Paise, never rupees — see the finance model. A float total drifts.
  final int spentPaise;
  final int owedPaise;
  final int billCount;
  final int documentCount;
  final int approvalsApproved;
  final int runSheetTotal;
  final int runSheetDone;

  factory EventReportFigures.fromJson(Map<String, dynamic> json) {
    int n(String key) => (json[key] as num?)?.toInt() ?? 0;
    return EventReportFigures(
      taskCount: n('taskCount'),
      taskCompleted: n('taskCompleted'),
      pointsEarned: n('pointsEarned'),
      departmentCount: n('departmentCount'),
      teamSize: n('teamSize'),
      spentPaise: n('spentPaise'),
      owedPaise: n('owedPaise'),
      billCount: n('billCount'),
      documentCount: n('documentCount'),
      approvalsApproved: n('approvalsApproved'),
      runSheetTotal: n('runSheetTotal'),
      runSheetDone: n('runSheetDone'),
    );
  }

  int get completionRate =>
      taskCount == 0 ? 0 : ((taskCompleted / taskCount) * 100).round();
}

class EventReport {
  const EventReport({
    required this.event,
    required this.figures,
    this.entry,
    this.canEdit = false,
  });

  final ClubEvent event;
  final EventReportFigures figures;
  final EventReportEntry? entry;
  final bool canEdit;

  factory EventReport.fromJson(Map<String, dynamic> json) => EventReport(
        event: ClubEvent.fromJson((json['event'] as Map).cast<String, dynamic>()),
        figures: EventReportFigures.fromJson(
            (json['derived'] as Map? ?? const {}).cast<String, dynamic>()),
        entry: json['report'] is Map
            ? EventReportEntry.fromJson((json['report'] as Map).cast<String, dynamic>())
            : null,
        canEdit: json['canEdit'] == true,
      );

  bool get written => entry != null && !entry!.isEmpty;
}
