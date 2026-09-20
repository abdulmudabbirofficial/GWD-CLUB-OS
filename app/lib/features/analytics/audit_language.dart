/// Turning stored audit actions into sentences.
///
/// The log stores machine actions (`task.create.department`) alongside a detail
/// blob. Printing the action with its dots turned into spaces produced rows
/// reading "Task create department" — forty of them identical apart from the
/// timestamp, which is a log that technically contains the answer and cannot be
/// read.
///
/// Its own file because it is the only genuinely fiddly logic on that screen and
/// the only part worth testing: a switch this long is exactly where a new action
/// added on the server quietly falls through.
library;

/// What happened, in a sentence.
///
/// Deliberately total. An action this build has never heard of still produces
/// something readable, because a new audit action added on the server must
/// never make the log look broken on a client that has not been rebuilt.
String describeAudit(String action, Map<String, dynamic> detail) {
  String named(String key, [String fallback = '']) {
    final value = detail[key];
    if (value == null) return fallback;
    final text = '$value'.trim();
    return text.isEmpty ? fallback : text;
  }

  final title = named('title', named('name', named('departmentName')));
  final quoted = title.isEmpty ? '' : ' “$title”';
  final department = named('departmentName');

  return switch (action) {
    'task.create.department' =>
      department.isEmpty ? 'Sent$quoted to a department' : 'Sent$quoted to $department',
    'task.create' => 'Created the task$quoted',
    'task.distribute' => 'Handed out$quoted',
    'task.update' => 'Updated$quoted',
    'task.delete' => 'Deleted$quoted',
    'taskRequest.create' => 'Asked somebody to take on$quoted',
    'taskRequest.accept' => 'Accepted a task request',
    'event.create' => 'Created the event$quoted',
    'event.update' => 'Updated the event$quoted',
    'event.status' => 'Moved an event to ${named('status', 'a new stage')}',
    'event.cancel' => 'Cancelled the event$quoted',
    'event.delete' => 'Deleted the event$quoted',
    'event.department.add' => department.isEmpty
        ? 'Brought a department into an event'
        : 'Brought $department into an event',
    'event.task.create' => 'Added$quoted to an event',
    'event.task.claim' => 'Picked up$quoted',
    'document.upload' => 'Filed the document$quoted',
    'document.replace' => 'Replaced the document$quoted',
    'document.decision' => 'Decided on the document$quoted',
    'document.delete' => 'Removed the document$quoted',
    'bill.create' => 'Filed the expense$quoted',
    'bill.decision' => 'Decided on the expense$quoted',
    'bill.settle' => 'Marked an expense as paid',
    'bill.delete' => 'Removed an expense',
    'department.create' => 'Created the department$quoted',
    'department.update' => 'Renamed a department',
    'department.setLead' => 'Changed who leads a department',
    'department.deactivate' => 'Retired a department',
    'category.create' => 'Added the schedule category$quoted',
    'category.update' => 'Changed a schedule category',
    'category.delete' => 'Retired a schedule category',
    'schedule.create' => 'Added$quoted to the schedule',
    'schedule.delete' => 'Removed something from the schedule',
    'meeting.create' => 'Called the meeting$quoted',
    'meeting.update' => 'Changed a meeting',
    'meeting.attendance' => 'Took attendance at a meeting',
    'help.create' => 'Asked for help with$quoted',
    'help.offer' => 'Offered to help',
    'help.status' => 'Closed a request for help',
    'alert.broadcast' => 'Sent a club alert',
    'points.award' => 'Awarded ${named('points', 'some')} points by hand',
    'signup' => 'Signed up',
    'user.rename' => 'Set somebody’s name',
    'user.roleChange' => 'Changed somebody’s role',
    'user.remove' => 'Removed somebody from the club',
    'password.change' => 'Changed their password',
    'password.forgot' => 'Asked for a password reset',
    'password.reset' => 'Reset somebody’s password',
    _ => _tidy(action),
  };
}

/// Last resort for an action this build has never heard of.
String _tidy(String action) {
  final words = action
      .split(RegExp(r'[._]'))
      .where((w) => w.isNotEmpty)
      .map((w) => w.replaceAllMapped(RegExp('([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}'))
      .join(' ');
  if (words.isEmpty) return 'Something happened';
  return words[0].toUpperCase() + words.substring(1).toLowerCase();
}
