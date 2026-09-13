import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme/apple_motion.dart';
import '../../app/theme/gwd_theme.dart';
import '../../app/widgets/common.dart';
import '../../core/api/api_client.dart';
import '../../core/models/member.dart';

/// "What should we call you?"
///
/// Opened two ways: pushed at somebody on first sign-in whose account still
/// carries the placeholder it was created with, or voluntarily from Account &
/// settings to correct it later.
///
/// Forced, it is not dismissable. An account named after its job is how a club
/// ends up with six people called "Lead" and none called anything — and the
/// name is the part everybody else reads, on every task, every approval and
/// every board in the app.
Future<bool> showSetNameSheet(
  BuildContext context, {
  bool forced = false,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: !forced,
    enableDrag: !forced,
    backgroundColor: Colors.transparent,
    builder: (_) => PopScope(
      canPop: !forced,
      child: _SetNameSheet(forced: forced),
    ),
  );
  return saved ?? false;
}

class _SetNameSheet extends StatefulWidget {
  const _SetNameSheet({required this.forced});
  final bool forced;

  @override
  State<_SetNameSheet> createState() => _SetNameSheetState();
}

class _SetNameSheetState extends State<_SetNameSheet> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final me = AppScope.readSession(context).me;
    // Seed the field only when the existing name is a real one. Prefilling a
    // placeholder invites somebody to press Save on "Creative Lead", which is
    // the exact outcome this sheet exists to prevent.
    _name = TextEditingController(text: me?.mustSetName == true ? '' : me?.name ?? '');
    _phone = TextEditingController(text: me?.phone ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  /// A full name, not an initial. Two characters is the floor the server also
  /// enforces; asking for a surname would be wrong for plenty of real people.
  bool get _valid => _name.text.trim().length >= 2;

  Future<void> _submit() async {
    final store = AppScope.readStore(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await store.updateMyProfile(
        name: _name.text.trim(),
        phone: _phone.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      messenger.showSnackBar(
        const SnackBar(content: Text('Saved. That is how the club will see you.')),
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
    final me = AppScope.sessionOf(context).me;

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
                SheetHeader(
                  title: widget.forced ? 'What should we call you?' : 'Your name',
                  subtitle: widget.forced
                      ? 'This account was set up for you, so it does not have your name on it yet.'
                      : 'How the rest of the club sees you.',
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      GwdSpace.xl, 0, GwdSpace.xl, GwdSpace.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      GwdField(
                        label: 'Your full name',
                        controller: _name,
                        autofocus: true,
                        hint: 'The name people know you by',
                        textCapitalization: TextCapitalization.words,
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: GwdSpace.lg),
                      GwdField(
                        label: 'Phone (optional)',
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) {
                          if (_valid) _submit();
                        },
                      ),

                      // Say out loud what the name is *not*. The position is
                      // already known from the role and is shown underneath the
                      // name everywhere, so putting it in this box duplicates
                      // one thing and loses another.
                      if (me != null) ...[
                        const SizedBox(height: GwdSpace.lg),
                        _PreviewCard(
                          name: _name.text.trim().isEmpty
                              ? 'Your name'
                              : _name.text.trim(),
                          faded: _name.text.trim().isEmpty,
                          me: me,
                          department:
                              AppScope.sessionOf(context).department?.name,
                        ),
                      ],

                      if (_error != null) ...[
                        const SizedBox(height: GwdSpace.lg),
                        ErrorNote(message: _error!),
                      ],
                      const SizedBox(height: GwdSpace.xl),
                      PrimaryButton(
                        label: widget.forced ? 'That is me' : 'Save',
                        icon: Icons.person_outline_rounded,
                        busy: _busy,
                        onPressed: _valid ? _submit : null,
                      ),
                      if (!widget.forced) ...[
                        const SizedBox(height: GwdSpace.sm),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: Text('Cancel',
                              style: GwdType.callout.copyWith(
                                  color: GwdColors.inkTertiaryOf(context))),
                        ),
                      ],
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

/// Shows the name over the position, exactly as the rest of the app renders it,
/// so the distinction between the two is visible while you type rather than
/// explained in a paragraph nobody reads.
class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.name,
    required this.faded,
    required this.me,
    this.department,
  });

  final String name;
  final bool faded;
  final Member me;
  final String? department;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(GwdSpace.lg),
      decoration: BoxDecoration(
        color: GwdColors.sunkenOf(context),
        borderRadius: BorderRadius.circular(GwdRadius.md),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: me.tint.withValues(alpha: faded ? 0.25 : 1),
              shape: BoxShape.circle,
            ),
            child: Text(
              faded ? '?' : _initialsOf(name),
              style: GwdType.footnote.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: GwdSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GwdType.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: faded
                        ? GwdColors.inkTertiaryOf(context)
                        : GwdColors.inkOf(context),
                  ),
                ),
                Text(
                  me.positionLine(department),
                  style: GwdType.footnote
                      .copyWith(color: GwdColors.inkTertiaryOf(context)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _initialsOf(String value) {
    final words =
        value.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) {
      final w = words.first;
      return (w.length >= 2 ? w.substring(0, 2) : w).toUpperCase();
    }
    return '${words.first[0]}${words.last[0]}'.toUpperCase();
  }
}
