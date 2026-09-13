import 'package:flutter/material.dart';

/// The club hierarchy.
///
/// These mirror `backend/src/permissions.js` exactly — the wire names must
/// match. Everything here is presentation and *optimistic* permission hinting:
/// the client uses it to avoid offering an action that would be rejected, but
/// the server is always the authority. Never treat a `true` here as permission.
enum ClubRole {
  clubDirector,
  facultyCoordinator,
  president,
  vicePresident,
  secretaryGeneral,
  clubLead,
  clubMember;

  static ClubRole fromWire(String? value) => switch (value) {
        'clubDirector' => ClubRole.clubDirector,
        'facultyCoordinator' => ClubRole.facultyCoordinator,
        'president' => ClubRole.president,
        'vicePresident' => ClubRole.vicePresident,
        'secretaryGeneral' => ClubRole.secretaryGeneral,
        'clubLead' => ClubRole.clubLead,
        _ => ClubRole.clubMember,
      };

  String get wire => name;
}

extension ClubRoleDetails on ClubRole {
  String get title => switch (this) {
        ClubRole.clubDirector => 'Club Director',
        ClubRole.facultyCoordinator => 'Faculty Coordinator',
        ClubRole.president => 'President',
        ClubRole.vicePresident => 'Vice President',
        ClubRole.secretaryGeneral => 'Secretary General',
        ClubRole.clubLead => 'Club Lead',
        ClubRole.clubMember => 'Club Member',
      };

  /// How the greeting addresses this person: "Good morning, President".
  ///
  /// Deliberately no honorific. "Mr." or "Ma'am" would mean guessing someone's
  /// gender from their role or name, and getting that wrong every day is worse
  /// than the small formality it buys. The office itself reads as respectful.
  String get address => switch (this) {
        ClubRole.clubDirector => 'Director',
        ClubRole.facultyCoordinator => 'Coordinator',
        ClubRole.president => 'President',
        ClubRole.vicePresident => 'Vice President',
        ClubRole.secretaryGeneral => 'Secretary General',
        ClubRole.clubLead => 'Lead',
        ClubRole.clubMember => '',
      };

  bool get hasAddress => address.isNotEmpty;

  /// Short form for the role badge — a quiet tag, never a banner.
  String get badge => switch (this) {
        ClubRole.clubDirector => 'DIRECTOR',
        ClubRole.facultyCoordinator => 'FACULTY',
        ClubRole.president => 'PRESIDENT',
        ClubRole.vicePresident => 'VP',
        ClubRole.secretaryGeneral => 'SEC GEN',
        ClubRole.clubLead => 'LEAD',
        ClubRole.clubMember => 'MEMBER',
      };

  /// Rank mirrors the server. VP and Secretary General are deliberately equal.
  int get rank => switch (this) {
        ClubRole.clubDirector => 100,
        ClubRole.facultyCoordinator => 95,
        ClubRole.president => 90,
        ClubRole.vicePresident => 80,
        ClubRole.secretaryGeneral => 80,
        ClubRole.clubLead => 50,
        ClubRole.clubMember => 10,
      };

  /// Supervisors oversee the club rather than compete inside it: no points, no
  /// leaderboard. They can still award points.
  bool get isSupervisor =>
      this == ClubRole.clubDirector || this == ClubRole.facultyCoordinator;

  bool get earnsPoints => !isSupervisor;
  bool get onLeaderboard => !isSupervisor;

  bool get isExecutive => rank >= 80;

  /// Whether the *Assigned* tab exists for this role at all.
  bool get canAssign => this != ClubRole.clubMember;

  /// Anyone with people reporting to them can raise the club.
  bool get canBroadcast => this != ClubRole.clubMember;

  bool get canManageDepartments =>
      isSupervisor || this == ClubRole.president;

  bool get canViewAudit => isSupervisor || this == ClubRole.president;

  /// Roles a person may pick at signup. Supervisors are appointed, never
  /// self-selected.
  static List<ClubRole> get selectableAtSignup => const [
        ClubRole.clubMember,
        ClubRole.clubLead,
        ClubRole.vicePresident,
        ClubRole.secretaryGeneral,
        ClubRole.president,
      ];

  /// Does this role belong to a department? Executives sit above them.
  bool get hasDepartment =>
      this == ClubRole.clubMember || this == ClubRole.clubLead;

  /// Who reviews a signup for this role — the honest line on the pending
  /// screen, so the applicant knows who they are waiting on.
  String get approverLabel => switch (this) {
        ClubRole.clubDirector ||
        ClubRole.facultyCoordinator =>
          'no approval needed',
        ClubRole.president => 'the Club Directors',
        ClubRole.vicePresident ||
        ClubRole.secretaryGeneral ||
        ClubRole.clubLead =>
          'the President',
        ClubRole.clubMember => 'your department Lead',
      };

  /// One line describing what this role does, for the directory and profile.
  String get remit => switch (this) {
        ClubRole.clubDirector => 'Oversees the whole club, with full visibility.',
        ClubRole.facultyCoordinator =>
          'The college\'s coordinator. Directs the leadership and tracks progress.',
        ClubRole.president => 'Leads the club and its executive team.',
        ClubRole.vicePresident => 'Runs delivery across every department.',
        ClubRole.secretaryGeneral => 'Governance, records and compliance.',
        ClubRole.clubLead => 'Runs one department and its members.',
        ClubRole.clubMember => 'Delivers the work on the ground.',
      };

  IconData get icon => switch (this) {
        ClubRole.clubDirector => Icons.verified_outlined,
        ClubRole.facultyCoordinator => Icons.school_outlined,
        ClubRole.president => Icons.military_tech_outlined,
        ClubRole.vicePresident => Icons.hub_outlined,
        ClubRole.secretaryGeneral => Icons.gavel_outlined,
        ClubRole.clubLead => Icons.flag_outlined,
        ClubRole.clubMember => Icons.person_outline,
      };
}

/// Where a signed-up account currently stands.
enum ApprovalStatus {
  pending,
  approved,
  rejected;

  static ApprovalStatus fromWire(String? value) => switch (value) {
        'approved' => ApprovalStatus.approved,
        'rejected' => ApprovalStatus.rejected,
        _ => ApprovalStatus.pending,
      };
}
