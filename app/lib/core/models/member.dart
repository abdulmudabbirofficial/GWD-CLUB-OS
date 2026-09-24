import 'package:flutter/material.dart';
import 'club_role.dart';

/// The line that goes **under** somebody's name: what they are, and where.
///
/// "Abdul" over "Marketing Lead", "Sanya" over "Marketing member" — one line
/// answering both questions. The bare role on its own ("Club Lead") is nearly
/// useless in a club with six departments: it says what somebody does without
/// saying what they do it for, so six different people read as the same person.
///
/// The executive tier has no department by design, and their office names
/// itself — "President" needs no qualifier, and "President of the club" only
/// adds noise.
///
/// A free function as well as a method on [Member], because the approvals queue
/// has a role and a department name in hand without a [Member] to hang them on,
/// and the phrasing must not drift between the two places.
String positionLineFor(
  ClubRole role,
  String? departmentName, {
  bool superAdmin = false,
  String? customTitle,
}) {
  // One Director carries the Super Admin tier. Their name already reads
  // "Club Director Mudabbir", so the line underneath says what the name does
  // not — the office twice in two lines is noise.
  if (role == ClubRole.clubDirector && superAdmin) return 'Super Admin';
  final where = departmentName?.trim();
  final hasWhere = where != null && where.isNotEmpty;

  // A post the club named itself ("Treasurer") shows in place of the role's
  // own title. It is words only: what they may do still follows the role.
  final custom = customTitle?.trim() ?? '';
  if (custom.isNotEmpty) return hasWhere ? '$custom \u00b7 $where' : custom;

  if (role == ClubRole.clubDirector || !hasWhere) return role.title;
  return switch (role) {
    ClubRole.clubLead => '$where Lead',
    ClubRole.clubMember => '$where member',
    // Anyone senior who happens to sit in a department keeps their office
    // first — it outranks the department they came from.
    _ => '${role.title} · $where',
  };
}

/// A person in the club.
class Member {
  const Member({
    required this.id,
    required this.name,
    required this.role,
    this.email = '',
    this.phone,
    this.departmentId,
    this.points = 0,
    this.approvalStatus = ApprovalStatus.approved,
    this.avatarColor,
    this.completedTasks,
    this.assignedTasks,
    this.completionRate,
    this.rank,
    this.mustChangePassword = false,
    this.mustSetName = false,
    this.passwordResetRequested = false,
    this.knownAs,
    this.superAdmin = false,
    this.customTitle,
  });

  final String id;
  final String name;
  final ClubRole role;
  final String email;
  final String? phone;
  final String? departmentId;
  final int points;
  final ApprovalStatus approvalStatus;
  final String? avatarColor;

  /// Only populated on the leaderboard.
  ///
  /// [rank] is null on purpose for anyone with too little assigned work to rank
  /// fairly — a 1-of-1 must not be shown as beating an 18-of-20.
  final int? completedTasks;
  final int? assignedTasks;
  final int? completionRate;
  final int? rank;

  /// Set when an account was created for somebody, or an admin reset their
  /// password. The app nags until they choose their own — a temporary password
  /// everybody keeps is not a password.
  final bool mustChangePassword;

  /// The account still carries the placeholder it was created with rather than
  /// a person's actual name.
  ///
  /// A server flag rather than something inferred from the text: "Creative
  /// Lead" is a perfectly good name for somebody to have chosen, and guessing
  /// from the string would eventually badger a real person about their own
  /// name. Whoever hands the credentials over can set it, and the holder is
  /// asked to confirm on first sign-in; either clears it.
  final bool mustSetName;

  /// They have said they cannot sign in. Shown to whoever can reset it.
  final bool passwordResetRequested;

  /// The name the club addresses a Director by — "Mudabbir", "Rehman",
  /// "Moin". Stored because it cannot be derived: it is the last word of
  /// "Abdul Mudabbir" but the first of "Rehman Pasha".
  final String? knownAs;

  /// Presentation only. The server decides what the Super Admin may do; this
  /// just lets the app say which Director is which, and hide what would be
  /// refused.
  final bool superAdmin;

  /// A post the Club Director named ("Treasurer"), shown instead of the role's
  /// own title. Words only — everything they may do follows [role].
  final String? customTitle;

  /// What to actually print.
  ///
  /// An account nobody has named yet says so, rather than passing its
  /// placeholder off as a person — six people called "<Department> Lead" is
  /// exactly the state this replaces. Every surface that shows a person should
  /// use this and pair it with the role underneath.
  ///
  /// A Director is addressed by title and the name the club knows them by —
  /// "Club Director Mudabbir" for the one who holds the club's keys, "Director
  /// Rehman" for the others — with the full name still on their record. Never
  /// "Director 1": a number names a seat, not the person in it.
  String get displayName {
    if (mustSetName) return 'No name set';
    final short = knownAs?.trim() ?? '';
    if (role == ClubRole.clubDirector && short.isNotEmpty) {
      return superAdmin ? 'Club Director $short' : 'Director $short';
    }
    return name;
  }

  /// True when [displayName] is standing in for a name rather than being one.
  /// Callers grey it out; it is not a real person's name to render in full ink.
  bool get isUnnamed => mustSetName;

  /// The line that goes **under** the name: what they are, and where.
  ///
  /// "Abdul" over "Marketing Lead", "Sanya" over "Marketing member" — one line
  /// that answers both questions at once. The bare role on its own ("Club
  /// Lead") is nearly useless in a club with six departments: it says what
  /// somebody does without saying what they do it for, so six different people
  /// read as the same person.
  ///
  /// The executive tier has no department by design, and their office already
  /// names itself — "President" needs no qualifier and "President of the club"
  /// only adds noise.
  String positionLine(String? departmentName) =>
      positionLineFor(role, departmentName, superAdmin: superAdmin, customTitle: customTitle);

  factory Member.fromJson(Map<String, dynamic> json) => Member(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Unknown',
        role: ClubRole.fromWire(json['role'] as String?),
        email: json['email'] as String? ?? '',
        phone: json['phone'] as String?,
        departmentId: json['departmentId'] as String?,
        points: (json['points'] as num?)?.toInt() ?? 0,
        approvalStatus: ApprovalStatus.fromWire(json['approvalStatus'] as String?),
        avatarColor: json['avatarColor'] as String?,
        completedTasks: (json['completedTasks'] as num?)?.toInt(),
        assignedTasks: (json['assignedTasks'] as num?)?.toInt(),
        completionRate: (json['completionRate'] as num?)?.toInt(),
        rank: (json['rank'] as num?)?.toInt(),
        mustChangePassword: json['mustChangePassword'] == true,
        mustSetName: json['mustSetName'] == true,
        passwordResetRequested: json['passwordResetRequested'] == true,
        knownAs: json['knownAs'] as String?,
        superAdmin: json['superAdmin'] == true,
        customTitle: json['customTitle'] as String?,
      );

  Color get tint {
    final hex = avatarColor;
    if (hex != null && hex.startsWith('#') && hex.length == 7) {
      return Color(int.parse('FF${hex.substring(1)}', radix: 16));
    }
    return const Color(0xFF52525B);
  }

  String get initials {
    // A placeholder is not a person, so it has no initials. "Faculty
    // Coordinator" came out as "FC" on the avatar while the name beside it
    // correctly read "No name set".
    if (mustSetName) return '?';
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    if (words.isEmpty) return '?';
    if (words.length == 1) {
      final w = words.first;
      return (w.length >= 2 ? w.substring(0, 2) : w).toUpperCase();
    }
    return '${words.first[0]}${words.last[0]}'.toUpperCase();
  }

  /// "Aisha" — used wherever the full name would crowd the line. The name the
  /// club actually uses, where there is one: greeting Director Mudabbir as
  /// "Abdul" would be using a name nobody calls him.
  String get firstName {
    final short = knownAs?.trim() ?? '';
    if (short.isNotEmpty) return short;
    return name.trim().split(RegExp(r'\s+')).first;
  }

  /// The name for a row too narrow for the whole thing: "Nishta", but
  /// "Director Rehman" — cutting a Director to the first word would leave
  /// only the title.
  String get shortName {
    if (mustSetName) return 'No name set';
    if (role == ClubRole.clubDirector && (knownAs?.trim().isNotEmpty ?? false)) {
      return displayName;
    }
    return firstName;
  }

  Member copyWith({
    String? name,
    String? phone,
    int? points,
    ClubRole? role,
    ApprovalStatus? approvalStatus,
    bool? mustSetName,
    String? customTitle,
  }) =>
      Member(
        id: id,
        name: name ?? this.name,
        role: role ?? this.role,
        email: email,
        phone: phone ?? this.phone,
        departmentId: departmentId,
        points: points ?? this.points,
        approvalStatus: approvalStatus ?? this.approvalStatus,
        avatarColor: avatarColor,
        completedTasks: completedTasks,
        assignedTasks: assignedTasks,
        completionRate: completionRate,
        rank: rank,
        mustChangePassword: mustChangePassword,
        mustSetName: mustSetName ?? this.mustSetName,
        passwordResetRequested: passwordResetRequested,
        knownAs: knownAs,
        superAdmin: superAdmin,
        customTitle: customTitle ?? this.customTitle,
      );
}
