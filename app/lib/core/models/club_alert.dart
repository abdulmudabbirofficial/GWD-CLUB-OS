import 'package:flutter/material.dart';
import 'club_role.dart';

enum AlertUrgency {
  normal,
  important,
  urgent;

  static AlertUrgency fromWire(String? v) => switch (v) {
        'important' => AlertUrgency.important,
        'urgent' => AlertUrgency.urgent,
        _ => AlertUrgency.normal,
      };

  String get label => switch (this) {
        AlertUrgency.normal => 'Normal',
        AlertUrgency.important => 'Important',
        AlertUrgency.urgent => 'Urgent',
      };

  Color get tint => switch (this) {
        AlertUrgency.normal => const Color(0xFF5C5C66),
        AlertUrgency.important => const Color(0xFFD97706),
        AlertUrgency.urgent => const Color(0xFFDC2626),
      };

  IconData get icon => switch (this) {
        AlertUrgency.normal => Icons.campaign_outlined,
        AlertUrgency.important => Icons.priority_high_rounded,
        AlertUrgency.urgent => Icons.warning_amber_rounded,
      };
}

enum AlertAudience {
  club,
  department,
  leadership;

  static AlertAudience fromWire(String? v) => switch (v) {
        'department' => AlertAudience.department,
        'leadership' => AlertAudience.leadership,
        _ => AlertAudience.club,
      };

  String get label => switch (this) {
        AlertAudience.club => 'Everyone',
        AlertAudience.department => 'Department',
        AlertAudience.leadership => 'Leadership',
      };
}

/// A broadcast raised by someone with people reporting to them.
///
/// Always signed. An anonymous club-wide alert is how this feature turns into
/// noise nobody reads, so the sender's name and role travel with the message.
class ClubAlert {
  const ClubAlert({
    required this.id,
    required this.title,
    required this.message,
    required this.urgency,
    required this.audience,
    required this.senderName,
    required this.senderRole,
    required this.createdAt,
    this.recipientCount = 0,
  });

  final String id;
  final String title;
  final String message;
  final AlertUrgency urgency;
  final AlertAudience audience;
  final String senderName;
  final ClubRole senderRole;
  final int recipientCount;
  final DateTime createdAt;

  factory ClubAlert.fromJson(Map<String, dynamic> json) => ClubAlert(
        id: json['id'] as String,
        title: json['title'] as String? ?? 'Club alert',
        message: json['message'] as String? ?? '',
        urgency: AlertUrgency.fromWire(json['urgency'] as String?),
        audience: AlertAudience.fromWire(json['audience'] as String?),
        senderName: json['senderName'] as String? ?? 'Someone',
        senderRole: ClubRole.fromWire(json['senderRole'] as String?),
        recipientCount: (json['recipientCount'] as num?)?.toInt() ?? 0,
        createdAt:
            DateTime.tryParse(json['createdAt']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
      );

  String get timeAgo {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${createdAt.day}/${createdAt.month}';
  }
}
