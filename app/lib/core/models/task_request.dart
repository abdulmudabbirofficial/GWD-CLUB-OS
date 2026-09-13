import 'club_role.dart';

/// A task you cannot impose.
///
/// Leads use these sideways to other Leads and upward to the executive tier,
/// where they have no authority to assign (Section 3). Accepting one is what
/// creates the actual task.
class TaskRequest {
  const TaskRequest({
    required this.id,
    required this.fromUserId,
    required this.fromName,
    required this.toUserId,
    required this.toName,
    required this.title,
    required this.status,
    this.description = '',
    this.dueDate,
    this.createdAt,
    this.fromDepartmentName,
  });

  final String id;
  final String fromUserId;
  final String fromName;
  final String toUserId;
  final String toName;
  final String title;
  final String description;
  final String status; // pending | accepted | declined
  final DateTime? dueDate;
  final DateTime? createdAt;

  /// Which department is asking. Null for the executive tier, who have none,
  /// and on requests raised before this was recorded.
  final String? fromDepartmentName;

  bool get isPending => status == 'pending';
  bool get isAccepted => status == 'accepted';

  /// "Anvitha · Marketing" — a name alone is often not enough to place
  /// somebody from another department.
  String get fromLabel => fromDepartmentName == null
      ? fromName
      : '$fromName · $fromDepartmentName';

  factory TaskRequest.fromJson(Map<String, dynamic> json) => TaskRequest(
        id: json['id'] as String,
        fromUserId: json['fromUserId'] as String? ?? '',
        fromName: json['fromName'] as String? ?? 'Someone',
        toUserId: json['toUserId'] as String? ?? '',
        toName: json['toName'] as String? ?? 'Someone',
        title: json['title'] as String? ?? 'Untitled',
        description: json['description'] as String? ?? '',
        status: json['status'] as String? ?? 'pending',
        dueDate: json['dueDate'] == null
            ? null
            : DateTime.tryParse(json['dueDate'].toString())?.toLocal(),
        createdAt: json['createdAt'] == null
            ? null
            : DateTime.tryParse(json['createdAt'].toString())?.toLocal(),
        fromDepartmentName: json['fromDepartmentName'] as String?,
      );
}

/// Somebody waiting to be let into the club (Section 4).
class AccessRequest {
  const AccessRequest({
    required this.id,
    required this.userId,
    required this.requestedRole,
    required this.status,
    this.departmentId,
    this.departmentName,
    this.applicantName = 'New member',
    this.applicantEmail = '',
    this.applicantPhone = '',
    this.applicantColor,
    this.applicantNeedsName = false,
    this.createdAt,
  });

  final String id;
  final String userId;
  final ClubRole requestedRole;
  final String status;
  final String? departmentId;
  final String? departmentName;
  final String applicantName;
  final String applicantEmail;
  final String applicantPhone;
  final String? applicantColor;

  /// The account still carries the placeholder it was created with — a seeded
  /// Lead nobody has put a name on yet. The approver is asked to name them
  /// before admitting them, rather than approving an account they cannot
  /// identify.
  final bool applicantNeedsName;

  final DateTime? createdAt;

  factory AccessRequest.fromJson(Map<String, dynamic> json) {
    final applicant = (json['applicant'] as Map?)?.cast<String, dynamic>();
    return AccessRequest(
      id: json['id'] as String,
      userId: json['userId'] as String? ?? '',
      requestedRole: ClubRole.fromWire(json['requestedRole'] as String?),
      status: json['status'] as String? ?? 'pending',
      departmentId: json['departmentId'] as String?,
      departmentName: json['departmentName'] as String?,
      applicantName: applicant?['name'] as String? ?? json['applicantName'] as String? ?? 'New member',
      applicantEmail: applicant?['email'] as String? ?? '',
      applicantPhone: applicant?['phone'] as String? ?? '',
      applicantColor: applicant?['avatarColor'] as String?,
      applicantNeedsName: applicant?['mustSetName'] == true,
      createdAt: json['createdAt'] == null
          ? null
          : DateTime.tryParse(json['createdAt'].toString())?.toLocal(),
    );
  }

  String get initials {
    final words = applicantName.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    if (words.isEmpty) return '?';
    if (words.length == 1) {
      final w = words.first;
      return (w.length >= 2 ? w.substring(0, 2) : w).toUpperCase();
    }
    return '${words.first[0]}${words.last[0]}'.toUpperCase();
  }
}
