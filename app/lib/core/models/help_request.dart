import 'package:flutter/material.dart';

/// Help & collaboration.
///
/// Two verbs: "I need help" and "I can help". A club's real failure mode is not
/// that nobody will pitch in — it is that the person stuck on a poster at 11pm
/// has no way to say so without it sounding like a complaint, and the person
/// free on Tuesday has no way to find them.
enum HelpStatus {
  open,
  assigned,
  inProgress,
  resolved;

  static HelpStatus fromWire(String? value) => switch (value) {
        'assigned' => HelpStatus.assigned,
        'inProgress' => HelpStatus.inProgress,
        'resolved' => HelpStatus.resolved,
        _ => HelpStatus.open,
      };

  String get wire => name;

  String get label => switch (this) {
        HelpStatus.open => 'Looking for someone',
        HelpStatus.assigned => 'Someone is on it',
        HelpStatus.inProgress => 'Being sorted',
        HelpStatus.resolved => 'Sorted',
      };

  String get shortLabel => switch (this) {
        HelpStatus.open => 'Open',
        HelpStatus.assigned => 'Claimed',
        HelpStatus.inProgress => 'Active',
        HelpStatus.resolved => 'Sorted',
      };

  Color get tint => switch (this) {
        HelpStatus.open => const Color(0xFFD97706),
        HelpStatus.assigned => const Color(0xFF2563EB),
        HelpStatus.inProgress => const Color(0xFF7C3AED),
        HelpStatus.resolved => const Color(0xFF16A34A),
      };

  IconData get icon => switch (this) {
        HelpStatus.open => Icons.pan_tool_outlined,
        HelpStatus.assigned => Icons.handshake_outlined,
        HelpStatus.inProgress => Icons.bolt_rounded,
        HelpStatus.resolved => Icons.check_circle_rounded,
      };
}

class HelpOffer {
  const HelpOffer({required this.id, required this.name, this.note = '', this.at});

  final String id;
  final String name;
  final String note;
  final DateTime? at;

  factory HelpOffer.fromJson(Map<String, dynamic> json) => HelpOffer(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? 'Member',
        note: json['note'] as String? ?? '',
        at: DateTime.tryParse(json['at']?.toString() ?? '')?.toLocal(),
      );
}

class HelpRequest {
  const HelpRequest({
    required this.id,
    required this.title,
    required this.status,
    required this.createdByName,
    required this.createdAt,
    required this.helpers,
    required this.mine,
    required this.helping,
    this.description = '',
    this.skills = const [],
    this.departmentId,
    this.departmentName,
    this.eventId,
    this.eventName,
  });

  final String id;
  final String title;
  final String description;
  final HelpStatus status;
  final List<String> skills;
  final String? departmentId;
  final String? departmentName;
  final String? eventId;
  final String? eventName;
  final String createdByName;
  final DateTime createdAt;
  final List<HelpOffer> helpers;

  /// Did I raise this?
  final bool mine;

  /// Have I already offered?
  final bool helping;

  factory HelpRequest.fromJson(Map<String, dynamic> json) => HelpRequest(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        status: HelpStatus.fromWire(json['status'] as String?),
        skills: ((json['skills'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(growable: false),
        departmentId: json['departmentId'] as String?,
        departmentName: json['departmentName'] as String?,
        eventId: json['eventId'] as String?,
        eventName: json['eventName'] as String?,
        createdByName: json['createdByName'] as String? ?? 'Member',
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '')?.toLocal() ??
            DateTime.now(),
        helpers: ((json['helpers'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => HelpOffer.fromJson(e.cast<String, dynamic>()))
            .toList(growable: false),
        mine: json['mine'] == true,
        helping: json['helping'] == true,
      );

  bool get isOpen => status != HelpStatus.resolved;

  String get ageLabel {
    final minutes = DateTime.now().difference(createdAt).inMinutes;
    if (minutes < 1) return 'just now';
    if (minutes < 60) return '${minutes}m ago';
    if (minutes < 60 * 24) return '${(minutes / 60).floor()}h ago';
    final days = (minutes / (60 * 24)).floor();
    return days == 1 ? 'yesterday' : '${days}d ago';
  }
}
