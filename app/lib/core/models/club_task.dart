import 'package:flutter/material.dart';

/// Task status.
///
/// The board reads To do → In progress → Review → Done. `review` is optional:
/// you can send a poster for a look, or just mark it done. Forcing review
/// through every trivial task turns a club into an approvals queue, which is
/// exactly what this app exists to remove.
///
/// `blocked` and `cancelled` exist because real work stalls, but they stay off
/// the main path so the happy path still reads as a short line.
enum TaskStatus {
  pending,
  inProgress,
  review,
  completed,
  blocked,
  cancelled;

  static TaskStatus fromWire(String? value) => switch (value) {
        'inProgress' => TaskStatus.inProgress,
        'review' => TaskStatus.review,
        'completed' => TaskStatus.completed,
        'blocked' => TaskStatus.blocked,
        'cancelled' => TaskStatus.cancelled,
        _ => TaskStatus.pending,
      };

  String get wire => name;

  String get label => switch (this) {
        TaskStatus.pending => 'To do',
        TaskStatus.inProgress => 'In progress',
        TaskStatus.review => 'In review',
        TaskStatus.completed => 'Done',
        TaskStatus.blocked => 'Blocked',
        TaskStatus.cancelled => 'Cancelled',
      };

  /// Column heading on a board, where the label sits above a stack of cards
  /// rather than inside a chip.
  String get boardLabel => switch (this) {
        TaskStatus.pending => 'To do',
        TaskStatus.inProgress => 'In progress',
        TaskStatus.review => 'Review',
        TaskStatus.completed => 'Done',
        TaskStatus.blocked => 'Blocked',
        TaskStatus.cancelled => 'Cancelled',
      };

  /// The four columns of the board, in order. Blocked and cancelled are not
  /// columns — a blocked card stays in its lane wearing a badge, because
  /// moving it somewhere else is how work gets forgotten.
  static const board = [
    TaskStatus.pending,
    TaskStatus.inProgress,
    TaskStatus.review,
    TaskStatus.completed,
  ];

  /// The single next step an owner can take. Drives the one primary button on
  /// the task detail screen — one decision per screen (Section 0).
  TaskStatus? get nextForOwner => switch (this) {
        TaskStatus.pending => TaskStatus.inProgress,
        TaskStatus.inProgress => TaskStatus.completed,
        TaskStatus.blocked => TaskStatus.inProgress,
        // Once it is out for review the owner waits; pulling it back is a
        // secondary action, not the headline button.
        TaskStatus.review || TaskStatus.completed || TaskStatus.cancelled => null,
      };

  String get advanceVerb => switch (this) {
        TaskStatus.pending => 'Start this task',
        TaskStatus.inProgress => 'Mark complete',
        TaskStatus.blocked => 'Resume',
        _ => '',
      };

  /// Position on the track, for the progress rail. Blocked sits at the In
  /// Progress step because that is where work actually stalled.
  int get trackIndex => switch (this) {
        TaskStatus.pending => 0,
        TaskStatus.inProgress || TaskStatus.blocked => 1,
        TaskStatus.review => 2,
        TaskStatus.completed => 3,
        TaskStatus.cancelled => 0,
      };

  Color get tint => switch (this) {
        TaskStatus.pending => const Color(0xFF9A9AA4),
        TaskStatus.inProgress => const Color(0xFF2563EB),
        TaskStatus.review => const Color(0xFF7C3AED),
        TaskStatus.completed => const Color(0xFF16A34A),
        TaskStatus.blocked => const Color(0xFFD97706),
        TaskStatus.cancelled => const Color(0xFF9A9AA4),
      };

  IconData get icon => switch (this) {
        TaskStatus.pending => Icons.radio_button_unchecked,
        TaskStatus.inProgress => Icons.timelapse_rounded,
        TaskStatus.review => Icons.rate_review_outlined,
        TaskStatus.completed => Icons.check_circle_rounded,
        TaskStatus.blocked => Icons.report_problem_outlined,
        TaskStatus.cancelled => Icons.cancel_outlined,
      };

  bool get isOpen =>
      this == TaskStatus.pending ||
      this == TaskStatus.inProgress ||
      this == TaskStatus.review ||
      this == TaskStatus.blocked;
}

enum TaskPriority {
  low,
  normal,
  high;

  static TaskPriority fromWire(String? value) => switch (value) {
        'low' => TaskPriority.low,
        'high' => TaskPriority.high,
        _ => TaskPriority.normal,
      };

  String get label => switch (this) {
        TaskPriority.low => 'Low',
        TaskPriority.normal => 'Normal',
        TaskPriority.high => 'High',
      };
}

class ClubTask {
  const ClubTask({
    required this.id,
    required this.title,
    required this.status,
    this.description = '',
    this.assignedBy,
    this.assignedTo,
    this.departmentId,
    this.eventId,
    this.dueDate,
    this.points = 0,
    this.priority = TaskPriority.normal,
    this.createdAt,
    this.updatedAt,
    this.completedAt,
  });

  final String id;
  final String title;
  final String description;
  final String? assignedBy;
  final String? assignedTo;
  final String? departmentId;

  /// Set when this task is part of an event, which is what keeps event work
  /// off the general task list — it lives on the event's board instead.
  final String? eventId;
  final TaskStatus status;
  final DateTime? dueDate;
  final int points;
  final TaskPriority priority;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? completedAt;

  static DateTime? _date(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString())?.toLocal();
  }

  factory ClubTask.fromJson(Map<String, dynamic> json) => ClubTask(
        id: json['id'] as String,
        title: json['title'] as String? ?? 'Untitled task',
        description: json['description'] as String? ?? '',
        assignedBy: json['assignedBy'] as String?,
        assignedTo: json['assignedTo'] as String?,
        departmentId: json['departmentId'] as String?,
        eventId: json['eventId'] as String?,
        status: TaskStatus.fromWire(json['status'] as String?),
        dueDate: _date(json['dueDate']),
        points: (json['points'] as num?)?.toInt() ?? 0,
        priority: TaskPriority.fromWire(json['priority'] as String?),
        createdAt: _date(json['createdAt']),
        updatedAt: _date(json['updatedAt']),
        completedAt: _date(json['completedAt']),
      );

  bool get isOverdue =>
      dueDate != null && status.isOpen && dueDate!.isBefore(DateTime.now());

  /// "today", "tomorrow", "in 3 days", "2 days ago" — short enough for a chip.
  String? get dueLabel {
    final due = dueDate;
    if (due == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(due.year, due.month, due.day);
    final days = target.difference(today).inDays;
    if (days == 0) return 'Due today';
    if (days == 1) return 'Due tomorrow';
    if (days == -1) return 'Due yesterday';
    if (days < 0) return '${-days} days overdue';
    if (days < 7) return 'Due in $days days';
    if (days < 14) return 'Due next week';
    return 'Due ${due.day}/${due.month}';
  }

  ClubTask copyWith({TaskStatus? status, String? title, String? description, DateTime? dueDate}) => ClubTask(
        id: id,
        title: title ?? this.title,
        description: description ?? this.description,
        assignedBy: assignedBy,
        assignedTo: assignedTo,
        departmentId: departmentId,
        eventId: eventId,
        status: status ?? this.status,
        dueDate: dueDate ?? this.dueDate,
        points: points,
        priority: priority,
        createdAt: createdAt,
        updatedAt: updatedAt,
        completedAt: completedAt,
      );
}

/// A comment on a task — keeps context attached to the work (Section 10).
class TaskComment {
  const TaskComment({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final String authorId;
  final String authorName;
  final String body;
  final DateTime createdAt;

  factory TaskComment.fromJson(Map<String, dynamic> json) => TaskComment(
        id: json['id'] as String,
        authorId: json['authorId'] as String? ?? '',
        authorName: json['authorName'] as String? ?? 'Unknown',
        body: json['body'] as String? ?? '',
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
      );
}
