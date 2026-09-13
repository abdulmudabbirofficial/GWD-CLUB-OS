import 'package:flutter/material.dart';

/// A kind of thing that can go on the club schedule.
///
/// Managed data, not an enum. The schedule used to have three fixed kinds,
/// which was the same mistake departments started with — a club's calendar
/// holds rehearsals, shoots, sponsor visits, exam breaks, whatever that club
/// actually does. President and supervisors create and rename these at runtime.
class ScheduleCategory {
  const ScheduleCategory({
    required this.id,
    required this.name,
    this.icon = 'flag',
    this.colorHex = '#DC2626',
    this.blurb = '',
    this.active = true,
    this.builtIn = false,
    this.count = 0,
  });

  final String id;
  final String name;
  final String icon;
  final String colorHex;
  final String blurb;
  final bool active;
  final bool builtIn;

  /// Upcoming entries using this category — lets the picker show what is
  /// actually in use rather than a wall of equal-looking options.
  final int count;

  factory ScheduleCategory.fromJson(Map<String, dynamic> json) => ScheduleCategory(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Entry',
        icon: json['icon'] as String? ?? 'flag',
        colorHex: json['color'] as String? ?? '#DC2626',
        blurb: json['blurb'] as String? ?? '',
        active: json['active'] as bool? ?? true,
        builtIn: json['builtIn'] as bool? ?? false,
        count: (json['count'] as num?)?.toInt() ?? 0,
      );

  Color get tint => hexToColor(colorHex);
  IconData get iconData => iconFor(icon);

  /// The deadline lane is derived from tasks, not a real category — it has no
  /// id on the server, so it is represented here as a sentinel the UI can show
  /// alongside real categories in the filter bar.
  static const deadlineId = 'deadline';

  static const deadline = ScheduleCategory(
    id: deadlineId,
    name: 'Deadlines',
    icon: 'deadline',
    colorHex: '#B45309',
    blurb: 'Task due dates, straight from the task list',
    builtIn: true,
  );

  bool get isDeadline => id == deadlineId;
}

Color hexToColor(String hex) {
  final cleaned = hex.replaceAll('#', '');
  if (cleaned.length != 6) return const Color(0xFFDC2626);
  return Color(int.parse('FF$cleaned', radix: 16));
}

/// Server sends an icon *name* from a closed set; this maps it to a glyph.
/// A closed set means a typo can never produce a blank square on the calendar.
IconData iconFor(String name) => switch (name) {
      'event' => Icons.celebration_outlined,
      'meeting' => Icons.groups_outlined,
      'marketing' => Icons.campaign_outlined,
      'deadline' => Icons.flag_outlined,
      'workshop' => Icons.handyman_outlined,
      'shoot' => Icons.photo_camera_outlined,
      'rehearsal' => Icons.theater_comedy_outlined,
      'sponsor' => Icons.handshake_outlined,
      'travel' => Icons.directions_bus_outlined,
      'social' => Icons.local_cafe_outlined,
      'deliverable' => Icons.inventory_2_outlined,
      'exam' => Icons.menu_book_outlined,
      'volunteer' => Icons.volunteer_activism_outlined,
      'budget' => Icons.payments_outlined,
      _ => Icons.flag_outlined,
    };

/// The icon names the picker offers, paired with a readable label.
const scheduleIconChoices = <String, String>{
  'event': 'Event',
  'meeting': 'Meeting',
  'marketing': 'Marketing',
  'workshop': 'Workshop',
  'shoot': 'Shoot',
  'rehearsal': 'Rehearsal',
  'sponsor': 'Sponsor',
  'travel': 'Travel',
  'social': 'Social',
  'deliverable': 'Deliverable',
  'exam': 'Exams',
  'volunteer': 'Volunteering',
  'budget': 'Budget',
  'flag': 'Other',
};

const schedulePalette = <String>[
  '#DC2626', '#334155', '#7C3AED', '#B45309', '#0891B2',
  '#15803D', '#BE123C', '#4338CA', '#A16207', '#0F766E',
];
