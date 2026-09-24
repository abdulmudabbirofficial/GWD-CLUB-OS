import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme/apple_motion.dart';
import '../../app/theme/gwd_theme.dart';
import '../../app/widgets/common.dart';
import '../../core/api/api_client.dart';
import '../../core/models/member.dart';
import '../../core/models/task_request.dart';

/// A member asking their own Lead for work.
///
/// The one way work reaches a member other than being handed it: they say what
/// they would like to take on, and their Lead says yes (pricing it 1, 3 or 5)
/// or no. A member gives work to nobody, their Lead included, and asks nobody
/// else - so this sheet has no recipient picker at all. It is always their Lead.
Future<void> showAskForWorkSheet(BuildContext context) {
  return showGwdSheet(
    context: context,
    builder: (_) => const _AskForWorkSheet(),
  );
}

/// The Lead's side: say yes to a member's ask, and price it on the way.
///
/// Returns the points chosen, or null if they backed out. Pricing belongs here
/// for the same reason it belongs to every hand-out: the Lead is the only
/// person who knows whether "design the poster" is twenty minutes or a weekend.
Future<int?> showPriceAskSheet(BuildContext context, TaskRequest request) {
  return showGwdSheet<int>(
    context: context,
    builder: (_) => _PriceAskSheet(request: request),
  );
}

/// This member's Lead, if their department has one they can see.
Member? leadOfMine(BuildContext context) {
  final store = AppScope.readStore(context);
  final me = AppScope.readSession(context).me;
  final leadId = store.departmentById(me?.departmentId)?.leadUserId;
  return store.memberById(leadId);
}

class _AskForWorkSheet extends StatefulWidget {
  const _AskForWorkSheet();

  @override
  State<_AskForWorkSheet> createState() => _AskForWorkSheetState();
}

class _AskForWorkSheetState extends State<_AskForWorkSheet> {
  final _title = TextEditingController();
  final _details = TextEditingController();
  DateTime? _due;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _details.dispose();
    super.dispose();
  }

  bool get _canSend => !_busy && _title.text.trim().length >= 2;

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

  Future<void> _send(Member lead) async {
    if (!_canSend) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final store = AppScope.readStore(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await store.sendTaskRequest(
        toUserId: lead.id,
        title: _title.text.trim(),
        description: _details.text.trim(),
        dueDate: _due,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(
        content: Text('Sent to ${lead.shortName}. You will hear back when they decide.'),
      ));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not reach the server.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lead = leadOfMine(context);
    final department =
        AppScope.storeOf(context).departmentById(AppScope.sessionOf(context).me?.departmentId);

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
              const SheetHeader(
                title: 'Ask for work',
                subtitle: 'Your Lead decides, and it lands on your list if they say yes.',
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(GwdSpace.xl, 0, GwdSpace.xl, GwdSpace.xl),
                child: lead == null
                    ? Text(
                        department == null
                            ? 'You are not in a department yet, so there is nobody to ask.'
                            : '${department.name} has no Lead yet. Once one is appointed, '
                                'you can ask them for work here.',
                        style: GwdType.callout.copyWith(color: GwdColors.inkSecondaryOf(context)),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Who it goes to, said once and not changeable: it is
                          // always their own Lead.
                          Container(
                            padding: const EdgeInsets.all(GwdSpace.md),
                            decoration: BoxDecoration(
                              color: GwdColors.sunkenOf(context),
                              borderRadius: BorderRadius.circular(GwdRadius.md),
                            ),
                            child: Row(
                              children: [
                                Avatar(initials: lead.initials, tint: lead.tint, size: 36),
                                const SizedBox(width: GwdSpace.md),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(lead.displayName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GwdType.headline
                                              .copyWith(color: GwdColors.inkOf(context))),
                                      Text(lead.positionLine(department?.name),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GwdType.footnote.copyWith(
                                              color: GwdColors.inkTertiaryOf(context))),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: GwdSpace.lg),
                          GwdField(
                            label: 'What would you like to work on?',
                            hint: 'Design the event poster',
                            controller: _title,
                            autofocus: true,
                            textCapitalization: TextCapitalization.sentences,
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: GwdSpace.md),
                          GwdField(
                            label: 'Anything they should know? (optional)',
                            controller: _details,
                            maxLines: 3,
                            textCapitalization: TextCapitalization.sentences,
                          ),
                          const SizedBox(height: GwdSpace.md),
                          SecondaryButton(
                            label: _due == null
                                ? 'Add a date (optional)'
                                : 'By ${_due!.day}/${_due!.month}/${_due!.year}',
                            icon: Icons.event_outlined,
                            expand: true,
                            onPressed: _pickDue,
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: GwdSpace.lg),
                            ErrorNote(message: _error!),
                          ],
                          const SizedBox(height: GwdSpace.xl),
                          PrimaryButton(
                            label: 'Ask ${lead.shortName}',
                            icon: Icons.send_rounded,
                            busy: _busy,
                            onPressed: _canSend ? () => _send(lead) : null,
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

class _PriceAskSheet extends StatefulWidget {
  const _PriceAskSheet({required this.request});
  final TaskRequest request;

  @override
  State<_PriceAskSheet> createState() => _PriceAskSheetState();
}

class _PriceAskSheetState extends State<_PriceAskSheet> {
  static const _values = [1, 3, 5];
  static const _labels = {1: 'Quick', 3: 'Real work', 5: 'Heavy'};
  int _points = 1;

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    return Container(
      decoration: BoxDecoration(
        color: GwdColors.surfaceOf(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(GwdRadius.xxl)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHeader(
              title: 'Give it to ${request.fromName}',
              subtitle: '“${request.title}” goes on their list.',
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(GwdSpace.xl, 0, GwdSpace.xl, GwdSpace.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('WHAT IS IT WORTH',
                      style: GwdType.eyebrow.copyWith(color: GwdColors.inkTertiaryOf(context))),
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
                              padding: const EdgeInsets.symmetric(vertical: GwdSpace.md),
                              decoration: BoxDecoration(
                                color: _values[i] == _points
                                    ? GwdColors.primaryRed
                                    : GwdColors.sunkenOf(context),
                                borderRadius: BorderRadius.circular(GwdRadius.md),
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
                                    style: GwdType.micro.copyWith(
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
                  const SizedBox(height: GwdSpace.xl),
                  PrimaryButton(
                    label: 'Give it to them',
                    icon: Icons.check_rounded,
                    onPressed: () => Navigator.of(context).pop(_points),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
