import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/responsive.dart';
import '../../app/theme/apple_motion.dart';
import '../../app/theme/gwd_theme.dart';
import '../../app/widgets/common.dart';
import '../../core/api/api_client.dart';
import '../../core/models/department.dart';
import '../../core/models/member.dart';
import 'event_workspace_page.dart';

/// Creating an event, in three steps.
///
/// Split not because forms should be long, but because the three steps are
/// genuinely different decisions: *what* is happening, *who is running it*, and
/// *which department does what*. Mixing them into one scroll is how you get a
/// screen nobody finishes.
///
/// Nothing is saved until the last step commits, so backing out at step three
/// leaves no half-made event behind.
class CreateEventFlow extends StatefulWidget {
  const CreateEventFlow({super.key});

  /// Opens the wizard on the **root** navigator, so it covers the tab bar, and
  /// then opens what it made.
  ///
  /// A creation flow is not a detail page: leaving the tabs visible invites
  /// somebody to switch away mid-way, and the Continue button ends up sharing
  /// the bottom edge with five nav items. Android back is handled in main.dart,
  /// which unwinds the root navigator first.
  ///
  /// The new event's workspace opens on the *caller's* navigator, so it behaves
  /// exactly like tapping the event in the list — tab bar and all.
  static Future<void> open(BuildContext context) async {
    final created = await Navigator.of(context, rootNavigator: true).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const CreateEventFlow(),
      ),
    );
    if (created == null || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EventWorkspacePage(eventId: created)),
    );
  }

  @override
  State<CreateEventFlow> createState() => _CreateEventFlowState();
}

/// One department's share of the event, while the wizard is still open.
class _Responsibility {
  _Responsibility(this.departmentId);
  final String departmentId;
  final notes = TextEditingController();
  final List<String> tasks = [];

  void dispose() => notes.dispose();
}

class _CreateEventFlowState extends State<CreateEventFlow> {
  final _page = PageController();
  int _step = 0;
  bool _saving = false;
  String? _error;

  // Step 1 — what is happening
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _venue = TextEditingController();
  final _speaker = TextEditingController();
  final _organisation = TextEditingController();
  DateTime _date = DateTime.now().add(const Duration(days: 7));
  TimeOfDay? _start;
  TimeOfDay? _end;
  String _type = 'Event';

  // Step 2 — who is running it
  String? _organisingDepartmentId;
  String? _leadUserId;
  final Set<String> _team = {};

  // Step 3 — who does what
  final List<_Responsibility> _responsibilities = [];

  static const _types = ['Event', 'Workshop', 'Seminar', 'Competition', 'Meetup', 'Drive'];

  @override
  void initState() {
    super.initState();
    // The Continue button lives in this widget, but the field that decides
    // whether it is enabled lives in a child step. Without this the button
    // stays greyed out however much you type — the parent never rebuilds.
    _name.addListener(refresh);
  }

  /// Rebuild the flow's chrome. Child steps call this after changing anything
  /// the Continue button's enabled state depends on.
  void refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _name.removeListener(refresh);
    _page.dispose();
    _name.dispose();
    _description.dispose();
    _venue.dispose();
    _speaker.dispose();
    _organisation.dispose();
    for (final r in _responsibilities) {
      r.dispose();
    }
    super.dispose();
  }

  bool get _step1Valid => _name.text.trim().length >= 2;
  bool get _step2Valid => _organisingDepartmentId != null;

  void _go(int step) {
    // Seed step three with the organising department the moment we arrive,
    // rather than in that step's initState — a PageView keeps its children
    // alive, so initState would run once with whatever was chosen then and
    // never notice the department changing afterwards.
    if (step == 2) {
      final owner = _organisingDepartmentId;
      if (owner != null && !_responsibilities.any((r) => r.departmentId == owner)) {
        _responsibilities.insert(0, _Responsibility(owner));
      }
    }
    setState(() => _step = step);
    _page.animateToPage(step,
        duration: AppleDuration.standard, curve: AppleCurves.standard);
  }

  Future<void> _submit() async {
    final store = AppScope.readStore(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final event = await store.createEvent(
        name: _name.text.trim(),
        description: _description.text.trim(),
        type: _type,
        date: DateTime(_date.year, _date.month, _date.day),
        venue: _venue.text.trim(),
        startTime: _start == null ? '' : _format(_start!),
        endTime: _end == null ? '' : _format(_end!),
        organizingDepartmentId: _organisingDepartmentId!,
        leadUserId: _leadUserId,
        supportingDepartmentIds: _responsibilities
            .map((r) => r.departmentId)
            .where((id) => id != _organisingDepartmentId)
            .toList(),
        teamUserIds: _team.toList(),
        speakerName: _speaker.text.trim(),
        externalOrganisation: _organisation.text.trim(),
        responsibilities: [
          for (final r in _responsibilities)
            {
              'departmentId': r.departmentId,
              'notes': r.notes.text.trim(),
              'tasks': [
                for (final t in r.tasks) {'title': t},
              ],
            },
        ],
      );
      if (!mounted) return;
      // Hand the id back; `open` decides where to show it.
      Navigator.of(context).pop(event?.id);
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _saving = false;
      });
    }
  }

  String _format(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final store = AppScope.storeOf(context);
    final layout = Layout.of(context);
    final departments = store.departments.where((d) => d.active).toList();

    final canAdvance = switch (_step) {
      0 => _step1Valid,
      1 => _step2Valid,
      _ => true,
    };

    return Scaffold(
      backgroundColor: GwdColors.canvasOf(context),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(['What is happening', 'Who is running it', 'Who does what'][_step]),
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(layout.gutter, 0, layout.gutter, GwdSpace.lg),
            child: _StepRail(step: _step, total: 3),
          ),
          Expanded(
            child: ContentWidth(
              child: PageView(
                controller: _page,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _StepBasics(state: this),
                  _StepTeam(state: this, departments: departments, members: store.members),
                  _StepWork(state: this, departments: departments),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  layout.gutter, GwdSpace.md, layout.gutter, GwdSpace.md),
              child: Column(
                children: [
                  if (_error != null) ...[
                    ErrorNote(message: _error!),
                    const SizedBox(height: GwdSpace.md),
                  ],
                  Row(
                    children: [
                      if (_step > 0) ...[
                        SecondaryButton(
                          label: 'Back',
                          icon: Icons.arrow_back_rounded,
                          onPressed: _saving ? null : () => _go(_step - 1),
                        ),
                        const SizedBox(width: GwdSpace.md),
                      ],
                      Expanded(
                        child: PrimaryButton(
                          label: _step == 2 ? 'Create event' : 'Continue',
                          icon: _step == 2 ? Icons.check_rounded : null,
                          busy: _saving,
                          onPressed: canAdvance
                              ? () => _step == 2 ? _submit() : _go(_step + 1)
                              : null,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Three segments that fill as you go. A dot-and-line stepper reads as
/// decoration; a filling rail reads as progress.
class _StepRail extends StatelessWidget {
  const _StepRail({required this.step, required this.total});
  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < total; i++) ...[
          Expanded(
            child: AnimatedContainer(
              duration: AppleDuration.standard,
              curve: AppleCurves.standard,
              height: 3,
              decoration: BoxDecoration(
                color: i <= step ? GwdColors.primaryRed : GwdColors.sunkenOf(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          if (i < total - 1) const SizedBox(width: 5),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------- step one

class _StepBasics extends StatefulWidget {
  const _StepBasics({required this.state});
  final _CreateEventFlowState state;

  @override
  State<_StepBasics> createState() => _StepBasicsState();
}

class _StepBasicsState extends State<_StepBasics> {
  _CreateEventFlowState get s => widget.state;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: s._date,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (picked != null) setState(() => s._date = picked);
  }

  Future<void> _pickTime({required bool start}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: (start ? s._start : s._end) ?? const TimeOfDay(hour: 10, minute: 0),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        s._start = picked;
      } else {
        s._end = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final gutter = Layout.of(context).gutter;
    return ListView(
      padding: EdgeInsets.fromLTRB(gutter, 0, gutter, GwdSpace.xxl),
      children: [
        GwdField(
          label: 'Event name',
          controller: s._name,
          hint: 'Tech Fest 2026',
          autofocus: true,
        ),
        const SizedBox(height: GwdSpace.lg),

        Text('KIND', style: GwdType.eyebrow.copyWith(color: GwdColors.inkTertiaryOf(context))),
        const SizedBox(height: GwdSpace.sm),
        Wrap(
          spacing: GwdSpace.sm,
          runSpacing: GwdSpace.sm,
          children: [
            for (final type in _CreateEventFlowState._types)
              _Choice(
                label: type,
                selected: s._type == type,
                onTap: () => setState(() => s._type = type),
              ),
          ],
        ),
        const SizedBox(height: GwdSpace.lg),

        _Row(
          children: [
            _PickerTile(
              label: 'Date',
              value: '${s._date.day}/${s._date.month}/${s._date.year}',
              icon: Icons.event_rounded,
              onTap: _pickDate,
            ),
            _PickerTile(
              label: 'Starts',
              value: s._start == null ? 'Optional' : s._format(s._start!),
              icon: Icons.schedule_rounded,
              muted: s._start == null,
              onTap: () => _pickTime(start: true),
            ),
            _PickerTile(
              label: 'Ends',
              value: s._end == null ? 'Optional' : s._format(s._end!),
              icon: Icons.schedule_rounded,
              muted: s._end == null,
              onTap: () => _pickTime(start: false),
            ),
          ],
        ),
        const SizedBox(height: GwdSpace.lg),

        GwdField(label: 'Venue', controller: s._venue, hint: 'Main auditorium'),
        const SizedBox(height: GwdSpace.lg),
        GwdField(
          label: 'What is it',
          controller: s._description,
          hint: 'A couple of lines so people know what they are signing up to.',
          maxLines: 4,
        ),
        const SizedBox(height: GwdSpace.lg),

        // Guests are optional and most events have none, so they sit behind a
        // disclosure rather than adding two empty fields to every single event.
        _Disclosure(
          title: 'Guest or speaker',
          subtitle: 'Only if someone is coming in from outside',
          children: [
            GwdField(label: 'Name', controller: s._speaker, hint: 'Dr. A. Sharma'),
            const SizedBox(height: GwdSpace.md),
            GwdField(
              label: 'Organisation',
              controller: s._organisation,
              hint: 'Where they are from',
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- step two

class _StepTeam extends StatefulWidget {
  const _StepTeam({
    required this.state,
    required this.departments,
    required this.members,
  });

  final _CreateEventFlowState state;
  final List<Department> departments;
  final List<Member> members;

  @override
  State<_StepTeam> createState() => _StepTeamState();
}

class _StepTeamState extends State<_StepTeam> {
  _CreateEventFlowState get s => widget.state;

  @override
  Widget build(BuildContext context) {
    final gutter = Layout.of(context).gutter;
    return ListView(
      padding: EdgeInsets.fromLTRB(gutter, 0, gutter, GwdSpace.xxl),
      children: [
        Text(
          'Which department owns this?',
          style: GwdType.title3.copyWith(color: GwdColors.inkOf(context)),
        ),
        const SizedBox(height: GwdSpace.xs),
        Text(
          'They handle the paperwork and answer for it.',
          style: GwdType.footnote.copyWith(color: GwdColors.inkTertiaryOf(context)),
        ),
        const SizedBox(height: GwdSpace.md),
        Wrap(
          spacing: GwdSpace.sm,
          runSpacing: GwdSpace.sm,
          children: [
            for (final d in widget.departments)
              _Choice(
                label: d.name,
                selected: s._organisingDepartmentId == d.id,
                onTap: () {
                  setState(() => s._organisingDepartmentId = d.id);
                  // Step 2's Continue depends on this, and that button is the
                  // parent's.
                  s.refresh();
                },
              ),
          ],
        ),
        const SizedBox(height: GwdSpace.xxl),

        Text(
          'Who is leading it?',
          style: GwdType.title3.copyWith(color: GwdColors.inkOf(context)),
        ),
        const SizedBox(height: GwdSpace.xs),
        Text(
          'Leave this and you take it on yourself.',
          style: GwdType.footnote.copyWith(color: GwdColors.inkTertiaryOf(context)),
        ),
        const SizedBox(height: GwdSpace.md),
        _PeopleGrid(
          members: widget.members,
          selected: {if (s._leadUserId != null) s._leadUserId!},
          onTap: (id) => setState(
              () => s._leadUserId = s._leadUserId == id ? null : id),
        ),
        const SizedBox(height: GwdSpace.xxl),

        Text(
          'Core team',
          style: GwdType.title3.copyWith(color: GwdColors.inkOf(context)),
        ),
        const SizedBox(height: GwdSpace.xs),
        Text(
          'The people who should hear about every change. Anyone can still help '
          'without being on this list.',
          style: GwdType.footnote.copyWith(color: GwdColors.inkTertiaryOf(context)),
        ),
        const SizedBox(height: GwdSpace.md),
        _PeopleGrid(
          members: widget.members,
          selected: s._team,
          onTap: (id) => setState(() {
            if (!s._team.remove(id)) s._team.add(id);
          }),
        ),
      ],
    );
  }
}

// -------------------------------------------------------------- step three

class _StepWork extends StatefulWidget {
  const _StepWork({required this.state, required this.departments});
  final _CreateEventFlowState state;
  final List<Department> departments;

  @override
  State<_StepWork> createState() => _StepWorkState();
}

class _StepWorkState extends State<_StepWork> {
  _CreateEventFlowState get s => widget.state;

  /// Starting points, not a fixed menu.
  ///
  /// Every club event needs roughly these things done, and typing them out for
  /// the fifth time is how people give up on planning inside an app. They are
  /// suggestions: tap to add, then edit or delete freely.
  static const _suggestions = <String, List<String>>{
    'Creative': ['Design the poster', 'Stage and backdrop', 'Certificates'],
    'Marketing': ['Announcement post', 'Story countdown', 'Post-event recap'],
    'PR': ['Contact colleges', 'Invite the guest', 'Press coverage'],
    'Technical': ['Sound and projector check', 'Registration form', 'Live stream'],
    'Operations': ['Book the venue', 'Refreshments', 'Seating plan'],
  };

  void _addDepartment(String id) {
    if (s._responsibilities.any((r) => r.departmentId == id)) return;
    setState(() => s._responsibilities.add(_Responsibility(id)));
  }

  Future<void> _addTask(_Responsibility r) async {
    final controller = TextEditingController();
    final added = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
        child: Container(
          decoration: BoxDecoration(
            color: GwdColors.surfaceOf(sheetContext),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(GwdRadius.xxl)),
          ),
          padding: const EdgeInsets.all(GwdSpace.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SheetHeader(title: 'Add a task'),
              const SizedBox(height: GwdSpace.lg),
              GwdField(
                label: 'What needs doing',
                controller: controller,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (value) => Navigator.of(sheetContext).pop(value),
              ),
              const SizedBox(height: GwdSpace.lg),
              PrimaryButton(
                label: 'Add',
                onPressed: () => Navigator.of(sheetContext).pop(controller.text),
              ),
            ],
          ),
        ),
      ),
    );
    controller.dispose();
    if (added != null && added.trim().length >= 2) {
      setState(() => r.tasks.add(added.trim()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final gutter = Layout.of(context).gutter;
    final used = s._responsibilities.map((r) => r.departmentId).toSet();
    final remaining = widget.departments.where((d) => !used.contains(d.id)).toList();

    return ListView(
      padding: EdgeInsets.fromLTRB(gutter, 0, gutter, GwdSpace.xxl),
      children: [
        Text(
          'Split the work',
          style: GwdType.title3.copyWith(color: GwdColors.inkOf(context)),
        ),
        const SizedBox(height: GwdSpace.xs),
        Text(
          'Say what each department is on the hook for. You can leave tasks '
          'unassigned — people pick them up from the board.',
          style: GwdType.footnote.copyWith(color: GwdColors.inkTertiaryOf(context)),
        ),
        const SizedBox(height: GwdSpace.lg),

        for (final r in s._responsibilities)
          Padding(
            padding: const EdgeInsets.only(bottom: GwdSpace.md),
            child: _ResponsibilityCard(
              responsibility: r,
              department: widget.departments
                  .firstWhere((d) => d.id == r.departmentId,
                      orElse: () => widget.departments.first),
              suggestions: _suggestions[widget.departments
                      .firstWhere((d) => d.id == r.departmentId,
                          orElse: () => widget.departments.first)
                      .name] ??
                  const ['Plan it out', 'Do the thing', 'Wrap up'],
              onAddTask: () => _addTask(r),
              onSuggestion: (title) => setState(() {
                if (!r.tasks.contains(title)) r.tasks.add(title);
              }),
              onRemoveTask: (title) => setState(() => r.tasks.remove(title)),
              onRemove: r.departmentId == s._organisingDepartmentId
                  ? null
                  : () => setState(() {
                        s._responsibilities.remove(r);
                        r.dispose();
                      }),
            ),
          ),

        if (remaining.isNotEmpty) ...[
          const SizedBox(height: GwdSpace.sm),
          Text('BRING IN ANOTHER DEPARTMENT',
              style: GwdType.eyebrow.copyWith(color: GwdColors.inkTertiaryOf(context))),
          const SizedBox(height: GwdSpace.sm),
          Wrap(
            spacing: GwdSpace.sm,
            runSpacing: GwdSpace.sm,
            children: [
              for (final d in remaining)
                _Choice(
                  label: d.name,
                  selected: false,
                  icon: Icons.add_rounded,
                  onTap: () => _addDepartment(d.id),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ResponsibilityCard extends StatelessWidget {
  const _ResponsibilityCard({
    required this.responsibility,
    required this.department,
    required this.suggestions,
    required this.onAddTask,
    required this.onSuggestion,
    required this.onRemoveTask,
    required this.onRemove,
  });

  final _Responsibility responsibility;
  final Department department;
  final List<String> suggestions;
  final VoidCallback onAddTask;
  final ValueChanged<String> onSuggestion;
  final ValueChanged<String> onRemoveTask;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final unused = suggestions.where((s) => !responsibility.tasks.contains(s)).toList();

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: department.tint,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: GwdSpace.sm),
              Expanded(
                child: Text(department.name,
                    style: GwdType.headline.copyWith(color: GwdColors.inkOf(context))),
              ),
              if (onRemove != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close_rounded,
                      size: 16, color: GwdColors.inkTertiaryOf(context)),
                  onPressed: onRemove,
                ),
            ],
          ),
          const SizedBox(height: GwdSpace.sm),
          TextField(
            controller: responsibility.notes,
            style: GwdType.callout.copyWith(color: GwdColors.inkOf(context)),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'What are they responsible for?',
              hintStyle:
                  GwdType.callout.copyWith(color: GwdColors.inkTertiaryOf(context)),
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          if (responsibility.tasks.isNotEmpty) ...[
            const SizedBox(height: GwdSpace.md),
            for (final task in responsibility.tasks)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  children: [
                    Icon(Icons.radio_button_unchecked,
                        size: 13, color: GwdColors.inkTertiaryOf(context)),
                    const SizedBox(width: GwdSpace.sm),
                    Expanded(
                      child: Text(task,
                          style: GwdType.callout
                              .copyWith(color: GwdColors.inkSecondaryOf(context))),
                    ),
                    PressableScale(
                      onTap: () => onRemoveTask(task),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.remove_circle_outline_rounded,
                            size: 14, color: GwdColors.inkTertiaryOf(context)),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: GwdSpace.md),
          Wrap(
            spacing: GwdSpace.sm,
            runSpacing: GwdSpace.sm,
            children: [
              _Choice(
                label: 'Add task',
                icon: Icons.add_rounded,
                selected: false,
                onTap: onAddTask,
              ),
              for (final suggestion in unused.take(3))
                _Choice(
                  label: suggestion,
                  icon: Icons.bolt_rounded,
                  selected: false,
                  subtle: true,
                  onTap: () => onSuggestion(suggestion),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ shared bits

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.subtle = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final bool subtle;

  @override
  Widget build(BuildContext context) {
    final fg = selected
        ? Colors.white
        : (subtle ? GwdColors.inkTertiaryOf(context) : GwdColors.inkOf(context));

    return PressableScale(
      onTap: onTap,
      pressedScale: 0.95,
      haptic: HapticStrength.selection,
      child: AnimatedContainer(
        duration: AppleDuration.fast,
        curve: AppleCurves.standard,
        padding: const EdgeInsets.symmetric(
            horizontal: GwdSpace.md, vertical: GwdSpace.sm + 1),
        decoration: BoxDecoration(
          color: selected ? GwdColors.primaryRed : GwdColors.surfaceOf(context),
          borderRadius: BorderRadius.circular(GwdRadius.md),
          border: Border.all(
            color: selected ? GwdColors.primaryRed : GwdColors.hairlineOf(context),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: fg),
              const SizedBox(width: 5),
            ],
            Text(label, style: GwdType.footnote.copyWith(color: fg)),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            Expanded(child: children[i]),
            if (i < children.length - 1) const SizedBox(width: GwdSpace.sm),
          ],
        ],
      );
}

class _PickerTile extends StatelessWidget {
  const _PickerTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
    this.muted = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      pressedScale: 0.97,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: GwdSpace.md, vertical: GwdSpace.md),
        decoration: BoxDecoration(
          color: GwdColors.sunkenOf(context),
          borderRadius: BorderRadius.circular(GwdRadius.md),
          border: Border.all(color: GwdColors.hairlineOf(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label.toUpperCase(),
                style: GwdType.eyebrow
                    .copyWith(color: GwdColors.inkTertiaryOf(context), fontSize: 9)),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(icon, size: 13, color: GwdColors.inkTertiaryOf(context)),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GwdType.footnote.copyWith(
                      color: muted
                          ? GwdColors.inkTertiaryOf(context)
                          : GwdColors.inkOf(context),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A collapsed section. Optional detail should cost a tap, not screen space.
class _Disclosure extends StatefulWidget {
  const _Disclosure({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  State<_Disclosure> createState() => _DisclosureState();
}

class _DisclosureState extends State<_Disclosure> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(GwdSpace.md),
      child: Column(
        children: [
          PressableScale(
            onTap: () => setState(() => _open = !_open),
            pressedScale: 0.99,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(widget.title,
                          style: GwdType.headline
                              .copyWith(color: GwdColors.inkOf(context))),
                      const SizedBox(height: 1),
                      Text(widget.subtitle,
                          style: GwdType.footnote
                              .copyWith(color: GwdColors.inkTertiaryOf(context))),
                    ],
                  ),
                ),
                AnimatedRotation(
                  turns: _open ? 0.5 : 0,
                  duration: AppleDuration.standard,
                  curve: AppleCurves.standard,
                  child: Icon(Icons.expand_more_rounded,
                      size: 20, color: GwdColors.inkTertiaryOf(context)),
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: AppleDuration.standard,
            curve: AppleCurves.standard,
            alignment: Alignment.topCenter,
            child: _open
                ? Padding(
                    padding: const EdgeInsets.only(top: GwdSpace.lg),
                    child: Column(children: widget.children),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// A scrollable strip of people. A dropdown of 40 names is unusable on a phone;
/// faces and initials are how anybody actually recognises a colleague.
class _PeopleGrid extends StatelessWidget {
  const _PeopleGrid({
    required this.members,
    required this.selected,
    required this.onTap,
  });

  final List<Member> members;
  final Set<String> selected;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    if (members.isEmpty) {
      return Text('Nobody to pick from yet.',
          style: GwdType.footnote.copyWith(color: GwdColors.inkTertiaryOf(context)));
    }
    return SizedBox(
      height: 86,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: members.length,
        separatorBuilder: (_, __) => const SizedBox(width: GwdSpace.md),
        itemBuilder: (context, i) {
          final member = members[i];
          final isSelected = selected.contains(member.id);
          return PressableScale(
            onTap: () => onTap(member.id),
            pressedScale: 0.92,
            haptic: HapticStrength.selection,
            child: SizedBox(
              width: 58,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    children: [
                      Avatar(
                        initials: member.initials,
                        tint: member.tint,
                        size: 46,
                        selected: isSelected,
                      ),
                      if (isSelected)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: GwdColors.primaryRed,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: GwdColors.canvasOf(context), width: 1.5),
                            ),
                            child: const Icon(Icons.check_rounded,
                                size: 9, color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    member.name.split(' ').first,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: GwdType.caption.copyWith(
                      fontSize: 9.5,
                      letterSpacing: 0,
                      color: isSelected
                          ? GwdColors.inkOf(context)
                          : GwdColors.inkTertiaryOf(context),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
