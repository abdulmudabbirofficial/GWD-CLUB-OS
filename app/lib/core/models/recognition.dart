import 'package:flutter/material.dart';

import 'member.dart';

/// Recognition, **per department**.
///
/// There is deliberately no club-wide list. A Cinematography member who shoots
/// two films a term and a Marketing member posting daily are not doing the same
/// job, and ranking them against each other tells nobody anything. Inside a
/// department the work is at least alike, and the group is small enough to read
/// as a team rather than a table.
class DepartmentRecognition {
  const DepartmentRecognition({
    required this.departmentId,
    required this.name,
    required this.members,
    required this.totals,
    this.lead,
    this.colorSeed,
  });

  final String departmentId;
  final String name;
  final String? colorSeed;

  /// Reported apart from [members], never as a row competing with their own
  /// team: the Lead earns from everything the department finishes, so a row
  /// would always sit on top and say nothing.
  final Member? lead;

  final List<Member> members;
  final DepartmentTotals totals;

  factory DepartmentRecognition.fromJson(Map<String, dynamic> json) =>
      DepartmentRecognition(
        departmentId: json['departmentId'] as String? ?? '',
        name: json['name'] as String? ?? 'Department',
        colorSeed: json['colorSeed'] as String?,
        lead: json['lead'] is Map
            ? Member.fromJson((json['lead'] as Map).cast<String, dynamic>())
            : null,
        members: ((json['members'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => Member.fromJson(e.cast<String, dynamic>()))
            .toList(growable: false),
        totals: DepartmentTotals.fromJson(
            (json['totals'] as Map?)?.cast<String, dynamic>() ?? const {}),
      );

  bool get isEmpty => members.isEmpty && lead == null;

  /// Stable per department, so it looks the same here as it does everywhere
  /// else in the app.
  Color get tint {
    const palette = [
      Color(0xFFDC2626), Color(0xFF0B0B0F), Color(0xFF9F1239), Color(0xFF334155),
      Color(0xFFB45309), Color(0xFF15803D), Color(0xFF1D4ED8), Color(0xFF6D28D9),
    ];
    final seed = colorSeed ?? departmentId;
    var hash = 0;
    for (final unit in seed.codeUnits) {
      hash = (hash * 31 + unit) & 0x7FFFFFFF;
    }
    return palette[hash % palette.length];
  }
}

class DepartmentTotals {
  const DepartmentTotals({
    this.people = 0,
    this.assigned = 0,
    this.completed = 0,
    this.points = 0,
    this.completionRate = 0,
  });

  final int people;
  final int assigned;
  final int completed;
  final int points;
  final int completionRate;

  factory DepartmentTotals.fromJson(Map<String, dynamic> json) => DepartmentTotals(
        people: (json['people'] as num?)?.toInt() ?? 0,
        assigned: (json['assigned'] as num?)?.toInt() ?? 0,
        completed: (json['completed'] as num?)?.toInt() ?? 0,
        points: (json['points'] as num?)?.toInt() ?? 0,
        completionRate: (json['completionRate'] as num?)?.toInt() ?? 0,
      );
}

/// One row of the club-wide view: how much work a department was given, and how
/// much of it landed. Open to everyone — aggregate numbers about a *department*
/// give away nothing about any individual.
class DepartmentProgress {
  const DepartmentProgress({
    required this.departmentId,
    required this.name,
    required this.assigned,
    required this.completed,
    required this.open,
    required this.awaitingHandout,
    required this.points,
    required this.completionRate,
    required this.people,
    required this.hasLead,
    this.colorSeed,
  });

  final String departmentId;
  final String name;
  final String? colorSeed;
  final int assigned;
  final int completed;
  final int open;

  /// Work sent to the department that its Lead has not passed on yet. The one
  /// number on this screen somebody can act on today.
  final int awaitingHandout;

  final int points;
  final int completionRate;
  final int people;
  final bool hasLead;

  factory DepartmentProgress.fromJson(Map<String, dynamic> json) => DepartmentProgress(
        departmentId: json['departmentId'] as String? ?? '',
        name: json['name'] as String? ?? 'Department',
        colorSeed: json['colorSeed'] as String?,
        assigned: (json['assigned'] as num?)?.toInt() ?? 0,
        completed: (json['completed'] as num?)?.toInt() ?? 0,
        open: (json['open'] as num?)?.toInt() ?? 0,
        awaitingHandout: (json['awaitingHandout'] as num?)?.toInt() ?? 0,
        points: (json['points'] as num?)?.toInt() ?? 0,
        completionRate: (json['completionRate'] as num?)?.toInt() ?? 0,
        people: (json['people'] as num?)?.toInt() ?? 0,
        hasLead: json['hasLead'] == true,
      );
}

/// A department as an assignment target — what the leadership picks instead of
/// a person.
class AssignableDepartment {
  const AssignableDepartment({
    required this.id,
    required this.name,
    this.leadName,
    this.colorSeed,
  });

  final String id;
  final String name;

  /// Who would actually be woken up. Null is meaningful and shown: a department
  /// with no Lead has nobody to receive the work.
  final String? leadName;
  final String? colorSeed;

  factory AssignableDepartment.fromJson(Map<String, dynamic> json) =>
      AssignableDepartment(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Department',
        leadName: json['leadName'] as String?,
        colorSeed: json['colorSeed'] as String?,
      );
}
