/// The shape of an event the club runs more than once.
///
/// Most of a club's calendar is repeats: a workshop a month, a guest lecture a
/// term, the same fest every year. Rebuilding the same departments and the same
/// twenty opening tasks by hand each time is tedious, and tedium is how things
/// get dropped — the poster brief that was in last year's plan and that nobody
/// remembered this year.
///
/// A template task carries an **offset**, never a date. `offsetDays: -14` means
/// "fourteen days before the event", which survives being used again next term;
/// a stored date would be wrong the second time and every time after.
library;

DateTime? _date(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.tryParse(value.toString())?.toLocal();
}

class TemplateTask {
  const TemplateTask({
    required this.title,
    this.description = '',
    this.offsetDays,
    this.points = 1,
    this.priority = 'normal',
  });

  final String title;
  final String description;

  /// Days from the event date. Negative is before it, positive after, and null
  /// means the task deliberately has no deadline of its own.
  final int? offsetDays;
  final int points;
  final String priority;

  factory TemplateTask.fromJson(Map<String, dynamic> json) => TemplateTask(
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        offsetDays: (json['offsetDays'] as num?)?.toInt(),
        points: (json['points'] as num?)?.toInt() ?? 1,
        priority: json['priority'] as String? ?? 'normal',
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        'description': description,
        if (offsetDays != null) 'offsetDays': offsetDays,
        'points': points,
        'priority': priority,
      };

  /// Resolve the offset against a real event date.
  DateTime? dueFor(DateTime eventDate) => offsetDays == null
      ? null
      : DateTime(eventDate.year, eventDate.month, eventDate.day)
          .add(Duration(days: offsetDays!));

  /// "14 days before", "on the day", "2 days after" — the phrasing a person
  /// would use, because "-14" is a number you have to decode.
  String get whenLabel {
    final offset = offsetDays;
    if (offset == null) return 'No deadline';
    if (offset == 0) return 'On the day';
    final days = offset.abs();
    final unit = days == 1 ? 'day' : 'days';
    return offset < 0 ? '$days $unit before' : '$days $unit after';
  }
}

class TemplateResponsibility {
  const TemplateResponsibility({
    required this.departmentId,
    this.notes = '',
    this.tasks = const [],
  });

  final String departmentId;
  final String notes;
  final List<TemplateTask> tasks;

  factory TemplateResponsibility.fromJson(Map<String, dynamic> json) =>
      TemplateResponsibility(
        departmentId: json['departmentId'] as String? ?? '',
        notes: json['notes'] as String? ?? '',
        tasks: (json['tasks'] as List? ?? const [])
            .whereType<Map>()
            .map((t) => TemplateTask.fromJson(t.cast<String, dynamic>()))
            .toList(growable: false),
      );

  Map<String, dynamic> toJson() => {
        'departmentId': departmentId,
        'notes': notes,
        'tasks': tasks.map((t) => t.toJson()).toList(growable: false),
      };
}

class EventTemplate {
  const EventTemplate({
    required this.id,
    required this.name,
    this.description = '',
    this.type = 'event',
    this.venue = '',
    this.startTime = '',
    this.endTime = '',
    this.organizingDepartmentId,
    this.supportingDepartmentIds = const [],
    this.responsibilities = const [],
    this.departmentCount = 0,
    this.taskCount = 0,
    this.usageCount = 0,
    this.lastUsedAt,
    this.createdBy,
  });

  final String id;
  final String name;
  final String description;
  final String type;
  final String venue;
  final String startTime;
  final String endTime;
  final String? organizingDepartmentId;
  final List<String> supportingDepartmentIds;
  final List<TemplateResponsibility> responsibilities;

  /// Counted by the server so a card can say what applying this will do
  /// without walking the whole tree to find out.
  final int departmentCount;
  final int taskCount;
  final int usageCount;
  final DateTime? lastUsedAt;
  final String? createdBy;

  factory EventTemplate.fromJson(Map<String, dynamic> json) => EventTemplate(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Untitled template',
        description: json['description'] as String? ?? '',
        type: json['type'] as String? ?? 'event',
        venue: json['venue'] as String? ?? '',
        startTime: json['startTime'] as String? ?? '',
        endTime: json['endTime'] as String? ?? '',
        organizingDepartmentId: json['organizingDepartmentId'] as String?,
        supportingDepartmentIds: (json['supportingDepartmentIds'] as List? ?? const [])
            .map((e) => e.toString())
            .toList(growable: false),
        responsibilities: (json['responsibilities'] as List? ?? const [])
            .whereType<Map>()
            .map((r) => TemplateResponsibility.fromJson(r.cast<String, dynamic>()))
            .toList(growable: false),
        departmentCount: (json['departmentCount'] as num?)?.toInt() ?? 0,
        taskCount: (json['taskCount'] as num?)?.toInt() ?? 0,
        usageCount: (json['usageCount'] as num?)?.toInt() ?? 0,
        lastUsedAt: _date(json['lastUsedAt']),
        createdBy: json['createdBy'] as String?,
      );

  /// "Used 4 times", or an honest "Not used yet" rather than "Used 0 times".
  String get usageLabel => switch (usageCount) {
        0 => 'Not used yet',
        1 => 'Used once',
        final n => 'Used $n times',
      };
}
