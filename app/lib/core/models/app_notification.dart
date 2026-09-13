import 'package:flutter/material.dart';

/// One notification.
///
/// The server renders `title` and `body` from a single copy table that FCM also
/// uses, so a push that arrives while the app is closed reads identically to
/// the in-app entry it lands next to (Section 6.5).
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    this.read = false,
    this.payload = const {},
  });

  final String id;
  final String type;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool read;
  final Map<String, dynamic> payload;

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
        id: json['id'] as String,
        type: json['type'] as String? ?? 'unknown',
        title: json['title'] as String? ?? 'GWD Club',
        body: json['body'] as String? ?? '',
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
        read: json['read'] as bool? ?? false,
        payload: (json['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
      );

  AppNotification copyWith({bool? read}) => AppNotification(
        id: id,
        type: type,
        title: title,
        body: body,
        createdAt: createdAt,
        read: read ?? this.read,
        payload: payload,
      );

  /// Notifications that ask the user to *do* something get the accent; the
  /// rest stay quiet. This is the "spend crimson only where it's needed" rule
  /// applied to the notification list.
  bool get isActionable => const {
        'approvalNeeded',
        'taskRequestReceived',
        'taskAssigned',
      }.contains(type);

  IconData get icon => switch (type) {
        'taskAssigned' => Icons.assignment_outlined,
        'taskRequestReceived' => Icons.pan_tool_alt_outlined,
        'taskRequestAccepted' => Icons.check_circle_outline,
        'taskRequestDeclined' => Icons.do_not_disturb_alt_outlined,
        'taskCompleted' => Icons.task_alt_rounded,
        'approvalNeeded' => Icons.how_to_reg_outlined,
        'approvalGranted' => Icons.verified_outlined,
        'approvalRejected' => Icons.block_outlined,
        'approvalObserved' => Icons.visibility_outlined,
        'eventReminder' => Icons.event_outlined,
        'pointsEarned' => Icons.auto_awesome_outlined,
        'departmentChanged' => Icons.swap_horiz_rounded,
        'taskComment' => Icons.mode_comment_outlined,
        _ => Icons.notifications_none_rounded,
      };

  Color get tint => switch (type) {
        'approvalNeeded' || 'taskRequestReceived' => const Color(0xFFDC2626),
        'approvalGranted' || 'taskCompleted' || 'taskRequestAccepted' => const Color(0xFF16A34A),
        'approvalRejected' || 'taskRequestDeclined' => const Color(0xFFD97706),
        'pointsEarned' => const Color(0xFFB45309),
        _ => const Color(0xFF5C5C66),
      };

  String get timeAgo {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${createdAt.day}/${createdAt.month}';
  }
}
