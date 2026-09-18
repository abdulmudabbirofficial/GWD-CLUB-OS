import 'package:flutter/material.dart';

import '../../app/theme/gwd_theme.dart';

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
        createdAt:
            DateTime.tryParse(json['createdAt']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
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
  ///
  /// The test is strictly "is somebody blocked until this person acts" — not
  /// "is this important". `taskCompleted` is good news and `pointsAwarded` is
  /// nice to read, but neither is waiting on the reader, and marking them
  /// urgent is how the accent stops meaning anything.
  bool get isActionable => const {
        'approvalNeeded',
        'taskRequestReceived',
        'taskAssigned',
        // A Lead has been handed work for their department and nothing moves
        // until they pass it on. This was missing, which made the one
        // notification in the app that is purely a queue look like FYI.
        'departmentTaskAssigned',
        'departmentTaskUnclaimed',
        'helpRequested',
        'documentPending',
        'billFiled',
        'passwordResetRequested',
        'meetingInvited',
        'workReturnedToDepartment',
        'taskDueReminder',
      }.contains(type);

  IconData get icon => switch (type) {
        // work
        'taskAssigned' => GwdIcons.task,
        'departmentTaskAssigned' => Icons.inbox_outlined,
        'departmentTaskUnclaimed' => GwdIcons.blocked,
        'workReturnedToDepartment' => Icons.assignment_return_outlined,
        'taskRequestReceived' => GwdIcons.help,
        'taskRequestAccepted' => GwdIcons.done,
        'taskRequestDeclined' => GwdIcons.declined,
        'taskCompleted' => GwdIcons.done,
        'taskComment' => Icons.mode_comment_outlined,
        'taskDueReminder' => Icons.schedule_rounded,
        // joining and accounts
        'approvalNeeded' => Icons.how_to_reg_outlined,
        'approvalGranted' => GwdIcons.approved,
        'approvalRejected' => GwdIcons.declined,
        'approvalObserved' => Icons.visibility_outlined,
        'passwordResetRequested' => Icons.lock_reset_rounded,
        'passwordReset' => Icons.lock_outline_rounded,
        'profileRenamed' => Icons.badge_outlined,
        // the club
        'clubAlert' => Icons.campaign_outlined,
        'departmentChanged' => Icons.swap_horiz_rounded,
        'departmentCreated' => GwdIcons.department,
        'pointsEarned' || 'pointsAwarded' => Icons.auto_awesome_outlined,
        // events
        'eventCreated' => GwdIcons.event,
        'eventUpdated' => Icons.edit_calendar_outlined,
        'eventCancelled' => GwdIcons.cancelled,
        'documentPending' => GwdIcons.waiting,
        'documentDecision' => GwdIcons.approved,
        'billFiled' => GwdIcons.money,
        'billDecision' => GwdIcons.approved,
        'billSettled' => GwdIcons.settled,
        // help
        'helpRequested' => GwdIcons.help,
        'helpOffered' => Icons.volunteer_activism_outlined,
        'helpResolved' => GwdIcons.done,
        'helpJoined' => Icons.playlist_add_check_rounded,
        // meetings
        'meetingInvited' => GwdIcons.meeting,
        'meetingMoved' => Icons.update_rounded,
        'meetingCancelled' => GwdIcons.meetingOff,
        _ => Icons.notifications_none_rounded,
      };

  Color get tint => switch (type) {
        // needs you
        'approvalNeeded' ||
        'taskRequestReceived' ||
        'departmentTaskAssigned' ||
        'departmentTaskUnclaimed' ||
        'workReturnedToDepartment' ||
        'passwordResetRequested' =>
          const Color(0xFFDC2626),
        // went well
        'approvalGranted' ||
        'taskCompleted' ||
        'taskRequestAccepted' ||
        'helpResolved' ||
        'helpOffered' ||
        'billSettled' =>
          const Color(0xFF16A34A),
        // did not, or wants attention
        'approvalRejected' ||
        'taskRequestDeclined' ||
        'taskDueReminder' ||
        'documentPending' ||
        'billFiled' ||
        'helpRequested' =>
          const Color(0xFFD97706),
        // called off
        'eventCancelled' || 'meetingCancelled' => const Color(0xFF9A9AA4),
        'pointsEarned' || 'pointsAwarded' => const Color(0xFFB45309),
        'meetingInvited' || 'meetingMoved' || 'clubAlert' => const Color(0xFF2563EB),
        _ => const Color(0xFF5C5C66),
      };

  // ------------------------------------------------------------- deep links

  /// Where tapping this should go.
  ///
  /// Until this existed, tapping any notification only marked it read — "New
  /// task assigned" led nowhere, which makes the whole list read as a log
  /// rather than a way in. The destination is derived from the payload ids the
  /// server sends; anything without one falls back to the screen that lists
  /// its kind, which is still somewhere rather than nowhere.
  NotificationTarget get target {
    String? id(String key) {
      final value = payload[key];
      if (value == null) return null;
      final text = value.toString();
      return text.isEmpty || text == 'null' ? null : text;
    }

    final taskId = id('taskId');
    final meetingId = id('meetingId');
    final helpId = id('helpId');
    final eventId = id('eventId');

    // Most specific first: a notification about a task on an event should open
    // the task, not the festival it belongs to.
    if (taskId != null) return NotificationTarget.task(taskId);
    if (meetingId != null) return NotificationTarget.meeting(meetingId);
    if (helpId != null) return NotificationTarget.help(helpId);
    if (eventId != null) return NotificationTarget.event(eventId);

    return switch (type) {
      'approvalNeeded' || 'approvalObserved' => const NotificationTarget.approvals(),
      'passwordResetRequested' => const NotificationTarget.directory(),
      'taskRequestReceived' ||
      'taskRequestAccepted' ||
      'taskRequestDeclined' =>
        const NotificationTarget.requests(),
      'taskDueReminder' || 'taskAssigned' => const NotificationTarget.myWork(),
      'departmentTaskAssigned' ||
      'departmentTaskUnclaimed' ||
      'workReturnedToDepartment' =>
        const NotificationTarget.incoming(),
      'helpRequested' ||
      'helpOffered' ||
      'helpResolved' ||
      'helpJoined' =>
        const NotificationTarget.helpBoard(),
      'meetingInvited' ||
      'meetingMoved' ||
      'meetingCancelled' =>
        const NotificationTarget.meetings(),
      'pointsEarned' || 'pointsAwarded' => const NotificationTarget.recognition(),
      'departmentCreated' || 'departmentChanged' => const NotificationTarget.departments(),
      'clubAlert' => const NotificationTarget.broadcasts(),
      'profileRenamed' || 'passwordReset' => const NotificationTarget.profile(),
      // Approval outcomes for the person themselves, and anything a future
      // server sends that this build predates. Staying put is correct: it is
      // better than throwing somebody onto an unrelated screen.
      _ => const NotificationTarget.none(),
    };
  }

  bool get opensSomething => target.kind != NotificationTargetKind.none;

  String get timeAgo {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${createdAt.day}/${createdAt.month}';
  }
}

/// What a notification opens. A plain description, resolved to an actual route
/// by the UI — the model has no business importing pages.
enum NotificationTargetKind {
  none,
  task,
  meeting,
  help,
  event,
  approvals,
  directory,
  requests,
  myWork,
  incoming,
  helpBoard,
  meetings,
  recognition,
  departments,
  broadcasts,
  profile,
}

class NotificationTarget {
  const NotificationTarget._(this.kind, [this.id]);

  const NotificationTarget.none() : this._(NotificationTargetKind.none);
  const NotificationTarget.task(String id) : this._(NotificationTargetKind.task, id);
  const NotificationTarget.meeting(String id) : this._(NotificationTargetKind.meeting, id);
  const NotificationTarget.help(String id) : this._(NotificationTargetKind.help, id);
  const NotificationTarget.event(String id) : this._(NotificationTargetKind.event, id);
  const NotificationTarget.approvals() : this._(NotificationTargetKind.approvals);
  const NotificationTarget.directory() : this._(NotificationTargetKind.directory);
  const NotificationTarget.requests() : this._(NotificationTargetKind.requests);
  const NotificationTarget.myWork() : this._(NotificationTargetKind.myWork);
  const NotificationTarget.incoming() : this._(NotificationTargetKind.incoming);
  const NotificationTarget.helpBoard() : this._(NotificationTargetKind.helpBoard);
  const NotificationTarget.meetings() : this._(NotificationTargetKind.meetings);
  const NotificationTarget.recognition() : this._(NotificationTargetKind.recognition);
  const NotificationTarget.departments() : this._(NotificationTargetKind.departments);
  const NotificationTarget.broadcasts() : this._(NotificationTargetKind.broadcasts);
  const NotificationTarget.profile() : this._(NotificationTargetKind.profile);

  final NotificationTargetKind kind;
  final String? id;
}
