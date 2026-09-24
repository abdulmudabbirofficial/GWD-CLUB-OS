import '../../core/models/club_task.dart';

/// One line of the grouped work list: a heading, or a task.
///
/// Flattened into a single list so the whole thing stays one lazy sliver.
/// Nesting a sliver per group would build every group's header eagerly and
/// bring back the problem the builder exists to avoid.
class WorkRow {
  const WorkRow._({this.heading, this.task});

  factory WorkRow.heading(String title) => WorkRow._(heading: title);
  factory WorkRow.task(ClubTask task) => WorkRow._(task: task);

  final String? heading;
  final ClubTask? task;

  bool get isHeading => heading != null;
}

/// Your work, in the order it actually presses on you.
///
/// Overdue first, because it is the only group anybody has to do something
/// about today. Then today, then what is coming.
///
/// *Waiting* is pulled out of the dated sequence entirely: work in review or
/// blocked is not yours to move, and leaving it among the dated groups makes a
/// day look fuller than it is while hiding the things you can actually finish.
///
/// Empty groups are dropped, so a member with four tasks sees one heading and
/// not six.
///
/// [now] is injectable because the boundaries here are days: a test written
/// against the wall clock passes all afternoon and fails at ten to midnight.
List<WorkRow> groupWork(List<ClubTask> tasks, {DateTime? now}) {
  final clock = now ?? DateTime.now();
  final today = DateTime(clock.year, clock.month, clock.day);
  final weekEnd = today.add(const Duration(days: 7));

  final overdue = <ClubTask>[];
  final due = <ClubTask>[];
  final soon = <ClubTask>[];
  final undated = <ClubTask>[];
  final waiting = <ClubTask>[];
  final done = <ClubTask>[];

  for (final task in tasks) {
    if (task.status == TaskStatus.completed) {
      done.add(task);
      continue;
    }
    // Review and blocked both mean somebody else has it. Grouping them by
    // their due date would keep asking for something you cannot give.
    if (task.status == TaskStatus.review || task.status == TaskStatus.blocked) {
      waiting.add(task);
      continue;
    }
    final date = task.dueDate;
    if (date == null) {
      undated.add(task);
      continue;
    }
    final day = DateTime(date.year, date.month, date.day);
    if (day.isBefore(today)) {
      overdue.add(task);
    } else if (day == today) {
      due.add(task);
    } else if (day.isBefore(weekEnd)) {
      soon.add(task);
    } else {
      undated.add(task);
    }
  }

  int byDate(ClubTask a, ClubTask b) {
    final x = a.dueDate;
    final y = b.dueDate;
    if (x == null && y == null) return 0;
    if (x == null) return 1;
    if (y == null) return -1;
    return x.compareTo(y);
  }

  for (final list in [overdue, due, soon, undated, waiting]) {
    list.sort(byDate);
  }
  // Most recently finished first: the useful end of a completed list is the
  // end you just added to.
  done.sort((a, b) => (b.completedAt ?? b.updatedAt ?? DateTime(0))
      .compareTo(a.completedAt ?? a.updatedAt ?? DateTime(0)));

  final rows = <WorkRow>[];
  void section(String title, List<ClubTask> items) {
    if (items.isEmpty) return;
    rows.add(WorkRow.heading(title));
    rows.addAll(items.map(WorkRow.task));
  }

  section('Overdue', overdue);
  section('Today', due);
  section('This week', soon);
  // "Later", not "Anytime": this group also holds work due beyond the week,
  // and a heading that says "anytime" over a card that says "due next week"
  // contradicts itself.
  section('Later', undated);
  section('Waiting on somebody else', waiting);
  // Kept short on purpose. This is a record that the day went somewhere, not
  // an archive — the full history is on the task itself.
  section('Recently done', done.take(5).toList());

  return rows;
}
