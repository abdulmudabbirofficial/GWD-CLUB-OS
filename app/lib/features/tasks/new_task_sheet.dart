import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme/apple_motion.dart';
import '../../app/theme/gwd_theme.dart';
import '../../app/widgets/common.dart';
import '../../core/api/api_client.dart';
import '../../core/models/club_task.dart';
import '../../core/models/member.dart';
import '../../core/models/recognition.dart';
import '../../core/state/club_store.dart';

Future<void> showNewTaskSheet(BuildContext context) {
  return showGwdSheet(
    context: context,
    builder: (_) => const _NewTaskSheet(),
  );
}

/// Compose a task.
///
/// What this sheet offers depends entirely on who is holding the phone, and
/// that is the point of the redesign. A Director used to be shown every name in
/// the club — forty avatars to pick one from, a decision they are not equipped
/// to make. Now:
///
///   Director · Faculty Coordinator · President · VP · Secretary General
///        → pick a **department**. Its Lead gets it and decides who does it.
///   Department Lead
///        → pick one of **their own members**, and price the work 1/3/5.
///
/// *Request* is the third mode: asking somebody you have no authority over.
/// The server decides which people and departments are valid for each — this
/// sheet only renders the answer.
class _NewTaskSheet extends StatefulWidget {
  const _NewTaskSheet();

  @override
  State<_NewTaskSheet> createState() => _NewTaskSheetState();
}

class _NewTaskSheetState extends State<_NewTaskSheet> {
  final _title = TextEditingController();
  final _description = TextEditingController();

  bool _requestMode = false;
  final Set<String> _selectedPeople = {};
  String? _selectedDepartment;
  DateTime? _due;
  TaskPriority _priority = TaskPriority.normal;
  int _points = 1;

  AssignmentTargets _targets = AssignmentTargets.empty;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  ClubStore? _store;
  int _knownDepartments = -1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Keep the department list current while the sheet is open.
    //
    // The targets are fetched once when the sheet opens, which covers the
    // ordinary case. But a department created or retired *now* — by somebody
    // else in the club, arriving over the socket — has to show up here too,
    // or the picker is quietly offering a department that no longer exists.
    // Watching the count rather than the whole list keeps this to one refetch
    // per actual change instead of one per store notification.
    final store = AppScope.readStore(context);
    if (!identical(store, _store)) {
      _store?.removeListener(_onStoreChanged);
      _store = store..addListener(_onStoreChanged);
      _knownDepartments = store.departments.where((d) => d.active).length;
    }
  }

  void _onStoreChanged() {
    final live = _store?.departments.where((d) => d.active).length ?? 0;
    if (live == _knownDepartments) return;
    _knownDepartments = live;
    _load();
  }

  Future<void> _load() async {
    try {
      final targets = await AppScope.readStore(context).assignableTargets();
      if (!mounted) return;
      setState(() {
        _targets = targets;
        _loading = false;
        // If the department that was picked has since been retired, drop the
        // selection rather than submitting against something that is gone.
        final ids = {
          ...targets.departments.map((d) => d.id),
          ...targets.requestableDepartments.map((d) => d.id),
        };
        if (_selectedDepartment != null && !ids.contains(_selectedDepartment)) {
          _selectedDepartment = null;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _store?.removeListener(_onStoreChanged);
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  /// True when this person sends work to departments rather than to people.
  ///
  /// Leadership addresses departments *by default* — a Director shown forty
  /// names and asked to pick one is making a decision they are not equipped
  /// for. But "by default" is not "only": the permission matrix lets a
  /// Director assign to the President, Vice President and Secretary General,
  /// and the server has always returned those three in `assignable`. This
  /// getter used to be unconditionally true for leadership, so the sheet
  /// rendered the department picker and nothing else — the three people the
  /// backend was offering had no way onto the screen. A Director could not
  /// give the President a task at all.
  bool get _toDepartment => _targets.canAssignToDepartment && !_requestMode && !_toNamedPerson;

  /// Set when somebody with department-level authority has switched to
  /// addressing a named person instead.
  bool _toNamedPerson = false;

  /// Whether that switch is worth showing: only when the server actually
  /// offered somebody to address directly.
  bool get _canChooseTarget =>
      _targets.canAssignToDepartment && !_requestMode && _targets.assignable.isNotEmpty;

  /// In request mode a Lead can address another **department** instead of a
  /// person — "Technical needs Production on the stage rig". The ask lands on
  /// that department's Lead, who decides whether to take it or pass it on.
  bool get _requestingDepartment => _requestMode && _selectedDepartment != null;

  bool get _canSubmit {
    if (_busy || _title.text.trim().length < 2) return false;
    if (_toDepartment) return _selectedDepartment != null;
    // Either a department or a person will do.
    return _selectedPeople.isNotEmpty || _selectedDepartment != null;
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final store = AppScope.readStore(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (_requestingDepartment) {
        // Addressed to a department; it lands on that department's Lead.
        await store.sendTaskRequest(
          toDepartmentId: _selectedDepartment,
          title: _title.text.trim(),
          description: _description.text.trim(),
          dueDate: _due,
        );
      } else if (_requestMode) {
        // A request goes to one person at a time — it is a conversation, not a
        // broadcast.
        for (final id in _selectedPeople) {
          await store.sendTaskRequest(
            toUserId: id,
            title: _title.text.trim(),
            description: _description.text.trim(),
            dueDate: _due,
          );
        }
      } else if (_toDepartment) {
        await store.createTask(
          title: _title.text.trim(),
          description: _description.text.trim(),
          departmentId: _selectedDepartment,
          dueDate: _due,
          points: _points,
          priority: _priority,
        );
      } else {
        await store.createTask(
          title: _title.text.trim(),
          description: _description.text.trim(),
          assignedTo: _selectedPeople.toList(),
          dueDate: _due,
          points: _points,
          priority: _priority,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      if (_toDepartment) {
        final department = _targets.departments.firstWhere((d) => d.id == _selectedDepartment);
        messenger.showSnackBar(SnackBar(
          content: Text(department.leadName == null
              ? 'Sent to ${department.name}. They have no Lead yet — the '
                  'President has been told.'
              : 'Sent to ${department.name}. '
                  '${department.leadName} will pass it on.'),
        ));
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _due ?? now.add(const Duration(days: 1)),
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _due = picked);
  }

  @override
  Widget build(BuildContext context) {
    final people = _requestMode ? _targets.requestable : _targets.assignable;
    final canRequest = _targets.requestable.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: GwdColors.surfaceOf(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(GwdRadius.xxl)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetHeader(
                title: _requestMode ? 'Ask someone' : 'Give out work',
                subtitle: _requestMode
                    ? 'They accept or decline — you are not their boss.'
                    : _toDepartment
                        ? 'Pick the department. Their Lead decides who does it.'
                        : _toNamedPerson
                            ? 'Goes straight to them, not through a department.'
                            : 'Pick who in your department takes this on.',
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(GwdSpace.xl, 0, GwdSpace.xl, GwdSpace.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (canRequest) ...[
                      _ModeSwitch(
                        requestMode: _requestMode,
                        onChanged: (value) => setState(() {
                          _requestMode = value;
                          _toNamedPerson = false;
                          _selectedPeople.clear();
                          _selectedDepartment = null;
                        }),
                      ),
                      const SizedBox(height: GwdSpace.lg),
                    ],
                    // Department or person, for the tier that may do both.
                    if (_canChooseTarget) ...[
                      _TargetSwitch(
                        toPerson: _toNamedPerson,
                        personLabel: _targets.assignable.length == 1
                            ? _targets.assignable.first.firstName
                            : 'A person',
                        onChanged: (value) => setState(() {
                          _toNamedPerson = value;
                          _selectedPeople.clear();
                          _selectedDepartment = null;
                        }),
                      ),
                      const SizedBox(height: GwdSpace.lg),
                    ],
                    GwdField(
                      label: 'What needs doing',
                      controller: _title,
                      autofocus: true,
                      hint: 'Shoot the teaser',
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: GwdSpace.lg),
                    if (_loading)
                      const SkeletonList(count: 2, height: 54)
                    else if (_toDepartment)
                      _DepartmentPicker(
                        departments: _targets.departments,
                        selected: _selectedDepartment,
                        onChanged: (id) => setState(() => _selectedDepartment = id),
                      )
                    else ...[
                      // A Lead asking across the club picks a department
                      // first — that is the unit the work is described in.
                      // Picking one clears any person, and vice versa: an ask
                      // goes to one place.
                      if (_requestMode && _targets.requestableDepartments.isNotEmpty) ...[
                        Text('ASK A DEPARTMENT',
                            style:
                                GwdType.eyebrow.copyWith(color: GwdColors.inkTertiaryOf(context))),
                        const SizedBox(height: GwdSpace.sm),
                        _DepartmentPicker(
                          departments: _targets.requestableDepartments,
                          selected: _selectedDepartment,
                          onChanged: (id) => setState(() {
                            _selectedDepartment = _selectedDepartment == id ? null : id;
                            _selectedPeople.clear();
                          }),
                        ),
                        if (people.isNotEmpty) ...[
                          const SizedBox(height: GwdSpace.lg),
                          Text('OR ASK A PERSON',
                              style: GwdType.eyebrow
                                  .copyWith(color: GwdColors.inkTertiaryOf(context))),
                          const SizedBox(height: GwdSpace.sm),
                        ],
                      ],
                      if (!_requestMode ||
                          _targets.requestableDepartments.isEmpty ||
                          people.isNotEmpty)
                        _PeoplePicker(
                          people: people,
                          selected: _selectedPeople,
                          requestMode: _requestMode,
                          onToggle: (id) => setState(() {
                            _selectedDepartment = null;
                            if (_requestMode) {
                              // One at a time: a request is a conversation.
                              _selectedPeople
                                ..clear()
                                ..add(id);
                            } else if (!_selectedPeople.remove(id)) {
                              _selectedPeople.add(id);
                            }
                          }),
                        ),
                    ],
                    const SizedBox(height: GwdSpace.lg),
                    if (!_requestMode) ...[
                      _PointPicker(
                        values: _targets.pointValues,
                        selected: _points,
                        toDepartment: _toDepartment,
                        onChanged: (value) => setState(() => _points = value),
                      ),
                      const SizedBox(height: GwdSpace.lg),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: _MiniPicker(
                            label: 'Due',
                            value: _due == null ? 'No date' : '${_due!.day}/${_due!.month}',
                            icon: Icons.event_rounded,
                            muted: _due == null,
                            onTap: _pickDue,
                          ),
                        ),
                        if (!_requestMode) ...[
                          const SizedBox(width: GwdSpace.sm),
                          Expanded(
                            child: _MiniPicker(
                              label: 'Priority',
                              value: _priority.label,
                              icon: Icons.flag_outlined,
                              muted: _priority == TaskPriority.normal,
                              onTap: () => setState(() {
                                _priority = switch (_priority) {
                                  TaskPriority.low => TaskPriority.normal,
                                  TaskPriority.normal => TaskPriority.high,
                                  TaskPriority.high => TaskPriority.low,
                                };
                              }),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: GwdSpace.lg),
                    GwdField(
                      label: 'Notes',
                      controller: _description,
                      maxLines: 3,
                      hint: 'Anything the person doing this should know.',
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: GwdSpace.lg),
                      ErrorNote(message: _error!),
                    ],
                    const SizedBox(height: GwdSpace.xl),
                    PrimaryButton(
                      label: _requestMode
                          ? 'Send request'
                          : _toDepartment
                              ? 'Send to department'
                              : 'Assign it',
                      icon:
                          _requestMode ? Icons.pan_tool_alt_outlined : Icons.arrow_forward_rounded,
                      busy: _busy,
                      onPressed: _canSubmit ? _submit : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Department, or a named person.
///
/// Only shown to the tier that genuinely has both options — the executive and
/// the supervisors, who address departments as a rule but may also give work
/// directly to the President, Vice President or Secretary General. Everyone
/// else has exactly one kind of target and gets no switch to ignore.
class _TargetSwitch extends StatelessWidget {
  const _TargetSwitch({
    required this.toPerson,
    required this.personLabel,
    required this.onChanged,
  });

  final bool toPerson;
  final String personLabel;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: GwdColors.sunkenOf(context),
        borderRadius: BorderRadius.circular(GwdRadius.md),
      ),
      child: Row(
        children: [
          for (final isPerson in [false, true])
            Expanded(
              child: PressableScale(
                onTap: () => onChanged(isPerson),
                pressedScale: 0.97,
                haptic: HapticStrength.selection,
                child: AnimatedContainer(
                  duration: AppleDuration.standard,
                  curve: AppleCurves.standard,
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isPerson == toPerson ? GwdColors.surfaceOf(context) : Colors.transparent,
                    borderRadius: BorderRadius.circular(GwdRadius.sm),
                    boxShadow: isPerson == toPerson
                        ? GwdShadow.resting(Theme.of(context).brightness == Brightness.dark)
                        : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isPerson ? Icons.person_outline_rounded : GwdIcons.department,
                        size: 14,
                        color: isPerson == toPerson
                            ? GwdColors.inkOf(context)
                            : GwdColors.inkTertiaryOf(context),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          isPerson ? personLabel : 'A department',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GwdType.footnote.copyWith(
                            color: isPerson == toPerson
                                ? GwdColors.inkOf(context)
                                : GwdColors.inkTertiaryOf(context),
                            fontWeight: isPerson == toPerson ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.requestMode, required this.onChanged});
  final bool requestMode;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: GwdColors.sunkenOf(context),
        borderRadius: BorderRadius.circular(GwdRadius.md),
      ),
      child: Row(
        children: [
          for (final isRequest in [false, true])
            Expanded(
              child: PressableScale(
                onTap: () => onChanged(isRequest),
                pressedScale: 0.97,
                haptic: HapticStrength.selection,
                child: AnimatedContainer(
                  duration: AppleDuration.standard,
                  curve: AppleCurves.standard,
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isRequest == requestMode
                        ? GwdColors.surfaceOf(context)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(GwdRadius.sm),
                    boxShadow: isRequest == requestMode
                        ? GwdShadow.resting(Theme.of(context).brightness == Brightness.dark)
                        : null,
                  ),
                  child: Text(
                    isRequest ? 'Ask' : 'Assign',
                    style: GwdType.footnote.copyWith(
                      color: isRequest == requestMode
                          ? GwdColors.inkOf(context)
                          : GwdColors.inkTertiaryOf(context),
                      fontWeight: isRequest == requestMode ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The leadership tier's picker: six departments, not forty faces.
///
/// Each row names the Lead who will actually receive it, because "sent to
/// Marketing" should not feel like dropping something into a void — and because
/// a department with no Lead is a fact the sender needs to see.
class _DepartmentPicker extends StatelessWidget {
  const _DepartmentPicker({
    required this.departments,
    required this.selected,
    required this.onChanged,
  });

  final List<AssignableDepartment> departments;
  final String? selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    if (departments.isEmpty) {
      return Text('No departments to send to yet.',
          style: GwdType.footnote.copyWith(color: GwdColors.inkTertiaryOf(context)));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('WHICH DEPARTMENT',
            style: GwdType.eyebrow.copyWith(color: GwdColors.inkTertiaryOf(context))),
        const SizedBox(height: GwdSpace.sm),
        for (final department in departments)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _DepartmentRow(
              department: department,
              selected: selected == department.id,
              onTap: () => onChanged(department.id),
            ),
          ),
      ],
    );
  }
}

class _DepartmentRow extends StatelessWidget {
  const _DepartmentRow({
    required this.department,
    required this.selected,
    required this.onTap,
  });

  final AssignableDepartment department;
  final bool selected;
  final VoidCallback onTap;

  Color get _tint {
    const palette = [
      Color(0xFFDC2626),
      Color(0xFF0B0B0F),
      Color(0xFF9F1239),
      Color(0xFF334155),
      Color(0xFFB45309),
      Color(0xFF15803D),
      Color(0xFF1D4ED8),
      Color(0xFF6D28D9),
    ];
    final seed = department.colorSeed ?? department.id;
    var hash = 0;
    for (final unit in seed.codeUnits) {
      hash = (hash * 31 + unit) & 0x7FFFFFFF;
    }
    return palette[hash % palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final hasLead = department.leadName != null;

    return PressableScale(
      onTap: onTap,
      pressedScale: 0.98,
      haptic: HapticStrength.selection,
      child: AnimatedContainer(
        duration: AppleDuration.fast,
        curve: AppleCurves.standard,
        padding: const EdgeInsets.all(GwdSpace.md),
        decoration: BoxDecoration(
          color: selected ? _tint.withValues(alpha: 0.10) : GwdColors.sunkenOf(context),
          borderRadius: BorderRadius.circular(GwdRadius.md),
          border: Border.all(
            color: selected ? _tint.withValues(alpha: 0.45) : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 30,
              decoration: BoxDecoration(
                color: _tint,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: GwdSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(department.name,
                      style: GwdType.headline.copyWith(color: GwdColors.inkOf(context))),
                  const SizedBox(height: 1),
                  Text(
                    hasLead
                        ? 'Goes to ${department.leadName}'
                        : 'No Lead yet — the President will be told',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GwdType.footnote.copyWith(
                      color: hasLead ? GwdColors.inkTertiaryOf(context) : GwdColors.warning,
                    ),
                  ),
                ],
              ),
            ),
            AnimatedScale(
              scale: selected ? 1 : 0,
              duration: AppleDuration.fast,
              curve: AppleCurves.overshoot,
              child: Icon(Icons.check_circle_rounded, size: 20, color: _tint),
            ),
          ],
        ),
      ),
    );
  }
}

/// A Lead's picker — their own department's members.
class _PeoplePicker extends StatelessWidget {
  const _PeoplePicker({
    required this.people,
    required this.selected,
    required this.requestMode,
    required this.onToggle,
  });

  final List<Member> people;
  final Set<String> selected;
  final bool requestMode;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    if (people.isEmpty) {
      return Text(
        requestMode ? 'Nobody to ask right now.' : 'Nobody in your department yet.',
        style: GwdType.footnote.copyWith(color: GwdColors.inkTertiaryOf(context)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(requestMode ? 'ASK WHO' : 'WHO TAKES IT ON',
            style: GwdType.eyebrow.copyWith(color: GwdColors.inkTertiaryOf(context))),
        const SizedBox(height: GwdSpace.sm),
        SizedBox(
          height: 86,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: people.length,
            separatorBuilder: (_, __) => const SizedBox(width: GwdSpace.md),
            itemBuilder: (context, i) {
              final member = people[i];
              final isSelected = selected.contains(member.id);
              return PressableScale(
                onTap: () => onToggle(member.id),
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
                                  border:
                                      Border.all(color: GwdColors.surfaceOf(context), width: 1.5),
                                ),
                                child:
                                    const Icon(Icons.check_rounded, size: 9, color: Colors.white),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        member.firstName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: GwdType.micro.copyWith(
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
        ),
      ],
    );
  }
}

/// What the task is worth: 1, 3 or 5.
///
/// Three values, never a free number — a spectrum invites haggling, and the
/// difference between 6 and 7 points is not a conversation any club should be
/// having.
class _PointPicker extends StatelessWidget {
  const _PointPicker({
    required this.values,
    required this.selected,
    required this.toDepartment,
    required this.onChanged,
  });

  final List<int> values;
  final int selected;
  final bool toDepartment;
  final ValueChanged<int> onChanged;

  static const _labels = {1: 'Quick', 3: 'Real work', 5: 'Heavy'};

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('WHAT IS IT WORTH',
            style: GwdType.eyebrow.copyWith(color: GwdColors.inkTertiaryOf(context))),
        const SizedBox(height: 3),
        Text(
          toDepartment
              ? 'A starting figure — the Lead can change it when they hand it out.'
              : 'Harder work counts for more.',
          style: GwdType.footnote.copyWith(color: GwdColors.inkTertiaryOf(context)),
        ),
        const SizedBox(height: GwdSpace.sm),
        Row(
          children: [
            for (var i = 0; i < values.length; i++) ...[
              if (i > 0) const SizedBox(width: GwdSpace.sm),
              Expanded(
                child: PressableScale(
                  onTap: () => onChanged(values[i]),
                  pressedScale: 0.96,
                  haptic: HapticStrength.selection,
                  child: AnimatedContainer(
                    duration: AppleDuration.fast,
                    curve: AppleCurves.standard,
                    padding: const EdgeInsets.symmetric(vertical: GwdSpace.md),
                    decoration: BoxDecoration(
                      color: values[i] == selected
                          ? GwdColors.primaryRed
                          : GwdColors.sunkenOf(context),
                      borderRadius: BorderRadius.circular(GwdRadius.md),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${values[i]}',
                          style: GwdType.numeric.copyWith(
                            fontSize: 19,
                            color: values[i] == selected ? Colors.white : GwdColors.inkOf(context),
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          _labels[values[i]] ?? 'pts',
                          style: GwdType.micro.copyWith(
                            letterSpacing: 0.2,
                            color: values[i] == selected
                                ? Colors.white.withValues(alpha: 0.85)
                                : GwdColors.inkTertiaryOf(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _MiniPicker extends StatelessWidget {
  const _MiniPicker({
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
        padding: const EdgeInsets.symmetric(horizontal: GwdSpace.md, vertical: GwdSpace.md),
        decoration: BoxDecoration(
          color: GwdColors.sunkenOf(context),
          borderRadius: BorderRadius.circular(GwdRadius.md),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: GwdColors.inkTertiaryOf(context)),
            const SizedBox(width: GwdSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label.toUpperCase(),
                      style: GwdType.microLabel.copyWith(color: GwdColors.inkTertiaryOf(context))),
                  Text(value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GwdType.footnote.copyWith(
                        color: muted ? GwdColors.inkTertiaryOf(context) : GwdColors.inkOf(context),
                      )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
