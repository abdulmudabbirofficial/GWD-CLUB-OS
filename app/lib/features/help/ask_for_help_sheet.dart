import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme/apple_motion.dart';
import '../../app/theme/gwd_theme.dart';
import '../../app/widgets/common.dart';
import '../../core/api/api_client.dart';

/// "I need help."
///
/// One required field. Everything else is optional, because the whole value of
/// this feature is that asking costs nothing — a form that demands a category,
/// a priority and a deadline is a form people close.
Future<void> showAskForHelpSheet(BuildContext context, {String? eventId}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _AskForHelpSheet(eventId: eventId),
  );
}

class _AskForHelpSheet extends StatefulWidget {
  const _AskForHelpSheet({this.eventId});
  final String? eventId;

  @override
  State<_AskForHelpSheet> createState() => _AskForHelpSheetState();
}

class _AskForHelpSheetState extends State<_AskForHelpSheet> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final Set<String> _skills = {};
  String? _eventId;
  bool _busy = false;
  String? _error;

  /// Not a taxonomy — just the things clubs actually need a spare pair of hands
  /// for. Tapping one saves typing; nobody is forced to pick.
  static const _common = [
    'Design',
    'Writing',
    'Photography',
    'Editing',
    'Setup',
    'On the day',
  ];

  @override
  void initState() {
    super.initState();
    _eventId = widget.eventId;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final store = AppScope.readStore(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await store.askForHelp(
        title: _title.text.trim(),
        description: _description.text.trim(),
        skills: _skills.toList(),
        eventId: _eventId,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Asked. Your department has been told.')),
      );
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
    final events = store.eventsActive;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
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
                const SheetHeader(
                  title: 'What do you need a hand with?',
                  subtitle: 'Your department sees it first. Anyone in the club can offer.',
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      GwdSpace.xl, 0, GwdSpace.xl, GwdSpace.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      GwdField(
                        label: 'In one line',
                        controller: _title,
                        autofocus: true,
                        hint: 'Need two people for the stage backdrop on Friday',
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: GwdSpace.lg),
                      GwdField(
                        label: 'More, if it helps',
                        controller: _description,
                        maxLines: 3,
                        hint: 'When, where, and what it involves.',
                      ),
                      const SizedBox(height: GwdSpace.lg),

                      Text('WHAT WOULD HELP',
                          style: GwdType.eyebrow
                              .copyWith(color: GwdColors.inkTertiaryOf(context))),
                      const SizedBox(height: GwdSpace.sm),
                      Wrap(
                        spacing: GwdSpace.sm,
                        runSpacing: GwdSpace.sm,
                        children: [
                          for (final skill in _common)
                            _Tag(
                              label: skill,
                              selected: _skills.contains(skill),
                              onTap: () => setState(() {
                                if (!_skills.remove(skill)) _skills.add(skill);
                              }),
                            ),
                        ],
                      ),

                      if (events.isNotEmpty) ...[
                        const SizedBox(height: GwdSpace.lg),
                        Text('IS THIS FOR AN EVENT?',
                            style: GwdType.eyebrow.copyWith(
                                color: GwdColors.inkTertiaryOf(context))),
                        const SizedBox(height: GwdSpace.sm),
                        Wrap(
                          spacing: GwdSpace.sm,
                          runSpacing: GwdSpace.sm,
                          children: [
                            for (final event in events.take(6))
                              _Tag(
                                label: event.name,
                                selected: _eventId == event.id,
                                onTap: () => setState(() =>
                                    _eventId = _eventId == event.id ? null : event.id),
                              ),
                          ],
                        ),
                      ],

                      if (_error != null) ...[
                        const SizedBox(height: GwdSpace.lg),
                        ErrorNote(message: _error!),
                      ],
                      const SizedBox(height: GwdSpace.xl),
                      PrimaryButton(
                        label: 'Ask',
                        icon: Icons.pan_tool_alt_outlined,
                        busy: _busy,
                        onPressed:
                            _title.text.trim().length >= 4 ? _submit : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      pressedScale: 0.95,
      haptic: HapticStrength.selection,
      child: AnimatedContainer(
        duration: AppleDuration.fast,
        padding: const EdgeInsets.symmetric(
            horizontal: GwdSpace.md, vertical: GwdSpace.sm),
        decoration: BoxDecoration(
          color: selected ? GwdColors.primaryRed : GwdColors.sunkenOf(context),
          borderRadius: BorderRadius.circular(GwdRadius.sm),
        ),
        child: Text(
          label,
          style: GwdType.footnote.copyWith(
            color: selected ? Colors.white : GwdColors.inkSecondaryOf(context),
          ),
        ),
      ),
    );
  }
}
