import 'package:flutter/material.dart';

/// A department.
///
/// v1 modelled these as a Dart `enum`, which is precisely why the President
/// could not create one without a rebuild. They are now plain data from the
/// server — created, renamed and deactivated at runtime (Section 3.1).
class Department {
  const Department({
    required this.id,
    required this.name,
    this.description = '',
    this.leadUserId,
    this.active = true,
    this.memberCount = 0,
    this.colorSeed,
    this.assigned = 0,
    this.completed = 0,
    this.completionRate = 0,
  });

  final String id;
  final String name;
  final String description;
  final String? leadUserId;
  final bool active;
  final int memberCount;
  final String? colorSeed;

  /// Headline progress. Deliberately open to every member — knowing Marketing
  /// is 60% through its work gives away nothing about any individual.
  final int assigned;
  final int completed;
  final int completionRate;

  factory Department.fromJson(Map<String, dynamic> json) => Department(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Untitled',
        description: json['description'] as String? ?? '',
        leadUserId: json['leadUserId'] as String?,
        active: json['active'] as bool? ?? true,
        memberCount: (json['memberCount'] as num?)?.toInt() ?? 0,
        colorSeed: json['colorSeed'] as String?,
        assigned: (json['assigned'] as num?)?.toInt() ?? 0,
        completed: (json['completed'] as num?)?.toInt() ?? 0,
        completionRate: (json['completionRate'] as num?)?.toInt() ?? 0,
      );

  bool get hasLead => leadUserId != null && leadUserId!.isNotEmpty;

  /// Departments are user-created, so their colour has to be derived rather
  /// than looked up. A stable hash keeps a department the same colour
  /// everywhere in the app and across sessions.
  Color get tint {
    const palette = [
      Color(0xFFDC2626), // crimson
      Color(0xFF0B0B0F), // ink
      Color(0xFF9F1239), // ruby
      Color(0xFF334155), // slate
      Color(0xFFB45309), // amber deep
      Color(0xFF15803D), // green deep
      Color(0xFF1D4ED8), // blue deep
      Color(0xFF6D28D9), // violet deep
    ];
    final seed = colorSeed ?? id;
    var hash = 0;
    for (final unit in seed.codeUnits) {
      hash = (hash * 31 + unit) & 0x7FFFFFFF;
    }
    return palette[hash % palette.length];
  }

  /// Two-letter monogram for the department avatar.
  String get initials {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    if (words.isEmpty) return '—';
    if (words.length == 1) {
      final w = words.first;
      return (w.length >= 2 ? w.substring(0, 2) : w).toUpperCase();
    }
    return '${words.first[0]}${words.elementAt(1)[0]}'.toUpperCase();
  }

  Department copyWith({String? name, String? description, bool? active, String? leadUserId}) =>
      Department(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
        leadUserId: leadUserId ?? this.leadUserId,
        active: active ?? this.active,
        memberCount: memberCount,
        colorSeed: colorSeed,
      );
}
