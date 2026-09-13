import 'package:flutter/material.dart';

import 'schedule_category.dart';

/// Where a content post is going.
enum MarketingPlatform {
  instagram, linkedin, youtube, x, whatsapp, other;

  static MarketingPlatform fromWire(String? v) => switch (v) {
        'linkedin' => MarketingPlatform.linkedin,
        'youtube' => MarketingPlatform.youtube,
        'x' => MarketingPlatform.x,
        'whatsapp' => MarketingPlatform.whatsapp,
        'other' => MarketingPlatform.other,
        _ => MarketingPlatform.instagram,
      };

  String get label => switch (this) {
        MarketingPlatform.instagram => 'Instagram',
        MarketingPlatform.linkedin => 'LinkedIn',
        MarketingPlatform.youtube => 'YouTube',
        MarketingPlatform.x => 'X',
        MarketingPlatform.whatsapp => 'WhatsApp',
        MarketingPlatform.other => 'Other',
      };
}

enum MarketingFormat {
  post, reel, story, carousel, video, article;

  static MarketingFormat fromWire(String? v) => switch (v) {
        'reel' => MarketingFormat.reel,
        'story' => MarketingFormat.story,
        'carousel' => MarketingFormat.carousel,
        'video' => MarketingFormat.video,
        'article' => MarketingFormat.article,
        _ => MarketingFormat.post,
      };

  String get label => switch (this) {
        MarketingFormat.post => 'Post',
        MarketingFormat.reel => 'Reel',
        MarketingFormat.story => 'Story',
        MarketingFormat.carousel => 'Carousel',
        MarketingFormat.video => 'Video',
        MarketingFormat.article => 'Article',
      };

  IconData get icon => switch (this) {
        MarketingFormat.post => Icons.image_outlined,
        MarketingFormat.reel => Icons.slow_motion_video_rounded,
        MarketingFormat.story => Icons.auto_stories_outlined,
        MarketingFormat.carousel => Icons.view_carousel_outlined,
        MarketingFormat.video => Icons.videocam_outlined,
        MarketingFormat.article => Icons.article_outlined,
      };
}

enum MarketingStage {
  planned, inProduction, ready, published;

  static MarketingStage fromWire(String? v) => switch (v) {
        'inProduction' => MarketingStage.inProduction,
        'ready' => MarketingStage.ready,
        'published' => MarketingStage.published,
        _ => MarketingStage.planned,
      };

  String get label => switch (this) {
        MarketingStage.planned => 'Planned',
        MarketingStage.inProduction => 'In production',
        MarketingStage.ready => 'Ready',
        MarketingStage.published => 'Published',
      };

  Color get tint => switch (this) {
        MarketingStage.planned => const Color(0xFF9A9AA4),
        MarketingStage.inProduction => const Color(0xFF2563EB),
        MarketingStage.ready => const Color(0xFF16A34A),
        MarketingStage.published => const Color(0xFF7C3AED),
      };
}

/// One thing on the club schedule.
///
/// Two kinds: a real `entry` carrying a club-defined category, or a `deadline`
/// derived from a task with a due date. A deadline **is** a task — the UI must
/// open the task, not a read-only copy of it.
class ScheduleEntry {
  const ScheduleEntry({
    required this.id,
    required this.title,
    required this.date,
    required this.categoryName,
    required this.categoryIcon,
    required this.categoryColorHex,
    this.kind = 'entry',
    this.categoryId,
    this.description = '',
    this.endDate,
    this.location = '',
    this.meetingUrl = '',
    this.departmentId,
    this.createdBy,
    this.createdByName,
    this.rsvps = const [],
    this.platform,
    this.format,
    this.stage,
    this.taskId,
    this.taskStatus,
    this.ownerName,
    this.assignedTo,
    this.assignedToName,
  });

  final String id;
  final String kind; // 'entry' | 'deadline'
  final String? categoryId;
  final String categoryName;
  final String categoryIcon;
  final String categoryColorHex;

  final String title;
  final String description;
  final DateTime date;
  final DateTime? endDate;
  final String location;
  final String meetingUrl;
  final String? departmentId;
  final String? createdBy;
  final String? createdByName;
  final List<String> rsvps;

  final MarketingPlatform? platform;
  final MarketingFormat? format;
  final MarketingStage? stage;

  final String? taskId;
  final String? taskStatus;
  final String? ownerName;

  /// On a deadline, who actually owes it. Null on a club entry, and null on a
  /// department task nobody has picked up yet — a deadline with no name on it
  /// is everybody's, which is how it becomes nobody's.
  final String? assignedTo;
  final String? assignedToName;

  bool get isDeadline => kind == 'deadline';

  /// Is this mine — work assigned to me, or something I said I would be at?
  ///
  /// Answered on the client because the schedule is already loaded: toggling
  /// between "the club" and "me" should be instant, not a round trip. The
  /// server can narrow the same way (`?mine=1`) for anything that wants only
  /// the personal slice.
  bool isMine(String? userId) {
    if (userId == null) return false;
    if (isDeadline) return assignedTo == userId;
    return rsvps.contains(userId);
  }
  Color get tint => hexToColor(categoryColorHex);
  IconData get icon => iconFor(categoryIcon);

  /// True when this entry carries content-calendar fields worth rendering.
  bool get hasContentFields => platform != null || format != null || stage != null;

  factory ScheduleEntry.fromJson(Map<String, dynamic> json) => ScheduleEntry(
        id: json['id'] as String,
        kind: json['kind'] as String? ?? 'entry',
        categoryId: json['categoryId'] as String?,
        categoryName: json['categoryName'] as String? ?? 'Entry',
        categoryIcon: json['categoryIcon'] as String? ?? 'flag',
        categoryColorHex: json['categoryColor'] as String? ?? '#DC2626',
        title: json['title'] as String? ?? 'Untitled',
        description: json['description'] as String? ?? '',
        date: DateTime.tryParse(json['date']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
        endDate: json['endDate'] == null
            ? null
            : DateTime.tryParse(json['endDate'].toString())?.toLocal(),
        location: json['location'] as String? ?? '',
        meetingUrl: json['meetingUrl'] as String? ?? '',
        departmentId: json['departmentId'] as String?,
        createdBy: json['createdBy'] as String?,
        createdByName: json['createdByName'] as String?,
        rsvps: (json['rsvps'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        platform: json['platform'] == null
            ? null
            : MarketingPlatform.fromWire(json['platform'] as String?),
        format: json['format'] == null
            ? null
            : MarketingFormat.fromWire(json['format'] as String?),
        stage: json['stage'] == null
            ? null
            : MarketingStage.fromWire(json['stage'] as String?),
        taskId: json['taskId'] as String?,
        taskStatus: json['taskStatus'] as String?,
        ownerName: json['ownerName'] as String?,
        assignedTo: json['assignedTo'] as String?,
        assignedToName: json['assignedToName'] as String?,
      );

  bool get isPast => (endDate ?? date).isBefore(DateTime.now());

  bool get isToday {
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month && date.day == now.day;
  }

  DateTime get day => DateTime(date.year, date.month, date.day);

  bool isAttending(String userId) => rsvps.contains(userId);

  /// "14:30" — what people actually scan a schedule for.
  String get timeLabel =>
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

  /// "In 3 days" / "Today, 16:00" — for the focal card.
  String get relativeLabel {
    final now = DateTime.now();
    final diff = date.difference(now);
    if (diff.isNegative) {
      final days = -diff.inDays;
      if (days == 0) return 'Earlier today';
      if (days == 1) return 'Yesterday';
      return '$days days ago';
    }
    if (diff.inMinutes < 60) return 'In ${diff.inMinutes} min';
    if (isToday) return 'Today, $timeLabel';
    if (diff.inDays <= 1) return 'Tomorrow, $timeLabel';
    if (diff.inDays < 7) return 'In ${diff.inDays} days';
    return '${date.day}/${date.month}';
  }
}
