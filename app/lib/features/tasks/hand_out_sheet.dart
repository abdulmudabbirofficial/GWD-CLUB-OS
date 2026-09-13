import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme/apple_motion.dart';
import '../../app/theme/gwd_theme.dart';
import '../../app/widgets/common.dart';
import '../../core/api/api_client.dart';
import '../../core/models/club_role.dart';
import '../../core/models/club_task.dart';

/// Pass a department task on — the second half of the assignment hierarchy.
///
/// The leadership addressed a department; this is the Lead deciding who
/// actually does it, and what it is worth. Pricing lives here rather than at
/// creation because this is the first moment somebody who knows the work is
/// looking at it.
///
/// "I'll do it myself" is a first-class option, not an afterthought: plenty of
/// what lands on a Lead is faster to do than to delegate.
Future<void> showHandOutSheet(BuildContext context, ClubTask task) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _HandOutSheet(task: task),
  );
}

class _HandOutSheet extends StatefulWidget {
  const _HandOutSheet({required this.task});
  final ClubTask task;

  @override
  State<_HandOutSheet> createState() => _HandOutSheetState();
}

class _HandOutSheetState extends State<_HandOutSheet> {
  String? _selected;
  late int _points = widget.task.points > 0 ? widget.task.points : 1;
  bool _busy = false;
  String? _error;

  static const _values = [1, 3, 5];
  static const _labels = {1: 'Quick', 3: 'Real work', 5: 'Heavy'};

  Future<void> _submit() async {
    if (_selected == null) return;
    final store = AppScope.readStore(context);
    final messenger = ScaffoldMessenger.of(context);
    final meId = AppScope.readSession(context).me?.id;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await store.handOutTask(
        widget.task.id,
        assignedTo: _selected!,
        points: _points,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(
        content: Text(_selected == meId
            ? 'Yours now.'
            : 'Passed to ${store.memberName(_selected)}.'),
      ));
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.storeOf(context);
    final session = AppScope.sessionOf(context);
    final me = session.me;

    // Only this department's members. The server enforces it too; this just
    // avoids offering something that would be refused.
    final candidates = store.members
        .where((m) =>
            m.departmentId == widget.task.departmentId &&
            m.role == ClubRole.clubMember)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return Container(
      decoration: BoxDecoration(
        color: GwdColors.surfaceOf(context),
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(GwdRadius.xxl)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetHeader(
                title: widget.task.title,
                subtitle: 'Sent to your department. Who takes it on?',
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    GwdSpace.xl, 0, GwdSpace.xl, GwdSpace.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.task.description.isNotEmpty) ...[
                      Text(widget.task.description,
                          style: GwdType.body.copyWith(
                              color: GwdColors.inkSecondaryOf(context))),
                      const SizedBox(height: GwdSpace.lg),
                    ],

                    // Taking it yourself is often the right answer, so it gets
                    // its own row rather than hiding among the avatars.
                    if (me != null)
                      _SelfOption(
                        selected: _selected == me.id,
                        onTap: () => setState(() => _selected = me.id),
                      ),
                    const SizedBox(height: GwdSpace.lg),

                    Text('OR PASS IT TO',
                        style: GwdType.eyebrow
                            .copyWith(color: GwdColors.inkTertiaryOf(context))),
                    const SizedBox(height: GwdSpace.sm),
                    if (candidates.isEmpty)
                      Text('Nobody else in your department yet.',
                          style: GwdType.footnote.copyWith(
                              color: GwdColors.inkTertiaryOf(context)))
                    else
                      SizedBox(
                        height: 86,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: candidates.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: GwdSpace.md),
                          itemBuilder: (context, i) {
                            final member = candidates[i];
                            final isSelected = _selected == member.id;
                            return PressableScale(
                              onTap: () => setState(() => _selected = member.id),
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
                                                    color: GwdColors.surfaceOf(context),
                                                    width: 1.5),
                                              ),
                                              child: const Icon(Icons.check_rounded,
                                                  size: 9, color: Colors.white),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      member.firstName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
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
                      ),

                    const SizedBox(height: GwdSpace.lg),
                    Text('WHAT IS IT WORTH',
                        style: GwdType.eyebrow
                            .copyWith(color: GwdColors.inkTertiaryOf(context))),
                    const SizedBox(height: 3),
                    Text('You know this work better than whoever sent it.',
                        style: GwdType.footnote
                            .copyWith(color: GwdColors.inkTertiaryOf(context))),
                    const SizedBox(height: GwdSpace.sm),
                    Row(
                      children: [
                        for (var i = 0; i < _values.length; i++) ...[
                          if (i > 0) const SizedBox(width: GwdSpace.sm),
                          Expanded(
                            child: PressableScale(
                              onTap: () => setState(() => _points = _values[i]),
                              pressedScale: 0.96,
                              haptic: HapticStrength.selection,
                              child: AnimatedContainer(
                                duration: AppleDuration.fast,
                                curve: AppleCurves.standard,
                                padding: const EdgeInsets.symmetric(
                                    vertical: GwdSpace.md),
                                decoration: BoxDecoration(
                                  color: _values[i] == _points
                                      ? GwdColors.primaryRed
                                      : GwdColors.sunkenOf(context),
                                  borderRadius:
                                      BorderRadius.circular(GwdRadius.md),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('${_values[i]}',
                                        style: GwdType.numeric.copyWith(
                                          fontSize: 19,
                                          color: _values[i] == _points
                                              ? Colors.white
                                              : GwdColors.inkOf(context),
                                        )),
                                    const SizedBox(height: 1),
                                    Text(
                                      _labels[_values[i]]!,
                                      style: GwdType.caption.copyWith(
                                        fontSize: 9,
                                        letterSpacing: 0.2,
                                        color: _values[i] == _points
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

                    if (_error != null) ...[
                      const SizedBox(height: GwdSpace.lg),
                      ErrorNote(message: _error!),
                    ],
                    const SizedBox(height: GwdSpace.xl),
                    PrimaryButton(
                      label: _selected == me?.id && _selected != null
                          ? 'I’ll do it'
                          : 'Pass it on',
                      icon: Icons.arrow_forward_rounded,
                      busy: _busy,
                      onPressed: _selected == null ? null : _submit,
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

class _SelfOption extends StatelessWidget {
  const _SelfOption({required this.selected, required this.onTap});
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      pressedScale: 0.98,
      haptic: HapticStrength.selection,
      child: AnimatedContainer(
        duration: AppleDuration.fast,
        padding: const EdgeInsets.all(GwdSpace.md),
        decoration: BoxDecoration(
          color: selected
              ? GwdColors.primaryRed.withValues(alpha: 0.10)
              : GwdColors.sunkenOf(context),
          borderRadius: BorderRadius.circular(GwdRadius.md),
          border: Border.all(
            color: selected
                ? GwdColors.primaryRed.withValues(alpha: 0.4)
                : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.pan_tool_alt_outlined,
                size: 18,
                color: selected
                    ? GwdColors.primaryRed
                    : GwdColors.inkTertiaryOf(context)),
            const SizedBox(width: GwdSpace.md),
            Expanded(
              child: Text('I’ll take this one myself',
                  style: GwdType.headline.copyWith(
                    color: selected
                        ? GwdColors.primaryRed
                        : GwdColors.inkOf(context),
                  )),
            ),
            AnimatedScale(
              scale: selected ? 1 : 0,
              duration: AppleDuration.fast,
              curve: AppleCurves.overshoot,
              child: const Icon(Icons.check_circle_rounded,
                  size: 20, color: GwdColors.primaryRed),
            ),
          ],
        ),
      ),
    );
  }
}
