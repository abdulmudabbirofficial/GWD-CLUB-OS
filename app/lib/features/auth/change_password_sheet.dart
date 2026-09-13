import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme/apple_motion.dart';
import '../../app/theme/gwd_theme.dart';
import '../../app/widgets/common.dart';
import '../../core/api/api_client.dart';

/// Choose your own password.
///
/// Opened two ways: voluntarily from Account & settings, or pushed at somebody
/// whose account was created for them — a seeded Lead, or anybody whose
/// password an admin has just reset. In that second case it is not dismissable,
/// because a temporary password everybody keeps is not a password.
Future<bool> showChangePasswordSheet(
  BuildContext context, {
  bool forced = false,
}) async {
  final changed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: !forced,
    enableDrag: !forced,
    backgroundColor: Colors.transparent,
    builder: (_) => PopScope(
      canPop: !forced,
      child: _ChangePasswordSheet(forced: forced),
    ),
  );
  return changed ?? false;
}

class _ChangePasswordSheet extends StatefulWidget {
  const _ChangePasswordSheet({required this.forced});
  final bool forced;

  @override
  State<_ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<_ChangePasswordSheet> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String? get _problem {
    final next = _next.text;
    if (_current.text.isEmpty) return null;
    if (next.isEmpty) return null;
    if (next.length < 8) return 'At least 8 characters.';
    if (next == _current.text) return 'That is the one you already have.';
    if (_confirm.text.isNotEmpty && _confirm.text != next) {
      return 'The two do not match.';
    }
    return null;
  }

  bool get _valid =>
      _current.text.isNotEmpty &&
      _next.text.length >= 8 &&
      _confirm.text == _next.text &&
      _next.text != _current.text;

  Future<void> _submit() async {
    final store = AppScope.readStore(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await store.changePassword(current: _current.text, next: _next.text);
      if (!mounted) return;
      Navigator.of(context).pop(true);
      messenger.showSnackBar(
        const SnackBar(content: Text('Password changed.')),
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
                  title: widget.forced ? 'Choose your own password' : 'Change password',
                  subtitle: widget.forced
                      ? 'The one you were given was temporary — somebody else knows it.'
                      : 'You will need the one you use now.',
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      GwdSpace.xl, 0, GwdSpace.xl, GwdSpace.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      GwdField(
                        label: widget.forced ? 'The one you were given' : 'Current password',
                        controller: _current,
                        obscure: true,
                        autofocus: true,
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: GwdSpace.lg),
                      GwdField(
                        label: 'New password',
                        controller: _next,
                        obscure: true,
                        hint: 'At least 8 characters',
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: GwdSpace.lg),
                      GwdField(
                        label: 'Type it again',
                        controller: _confirm,
                        obscure: true,
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) {
                          if (_valid) _submit();
                        },
                      ),

                      if (_problem != null) ...[
                        const SizedBox(height: GwdSpace.md),
                        Row(
                          children: [
                            Icon(Icons.info_outline_rounded,
                                size: 14, color: GwdColors.inkTertiaryOf(context)),
                            const SizedBox(width: 6),
                            Text(_problem!,
                                style: GwdType.footnote.copyWith(
                                    color: GwdColors.inkTertiaryOf(context))),
                          ],
                        ),
                      ],

                      if (_error != null) ...[
                        const SizedBox(height: GwdSpace.lg),
                        ErrorNote(message: _error!),
                      ],
                      const SizedBox(height: GwdSpace.xl),
                      PrimaryButton(
                        label: 'Save it',
                        icon: Icons.lock_outline_rounded,
                        busy: _busy,
                        onPressed: _valid ? _submit : null,
                      ),
                      if (!widget.forced) ...[
                        const SizedBox(height: GwdSpace.sm),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: Text('Not now',
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

/// "I cannot sign in."
///
/// Deliberately not an emailed reset link: that needs an SMTP account the club
/// does not have, and a club is not an anonymous internet service — every
/// member can find the President in a corridor, which is a stronger identity
/// check than an inbox anyway.
Future<void> showForgotPasswordSheet(BuildContext context, {String? email}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ForgotPasswordSheet(initialEmail: email),
  );
}

class _ForgotPasswordSheet extends StatefulWidget {
  const _ForgotPasswordSheet({this.initialEmail});
  final String? initialEmail;

  @override
  State<_ForgotPasswordSheet> createState() => _ForgotPasswordSheetState();
}

class _ForgotPasswordSheetState extends State<_ForgotPasswordSheet> {
  late final _email = TextEditingController(text: widget.initialEmail ?? '');
  bool _busy = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final session = AppScope.readSession(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await session.requestPasswordReset(_email.text.trim());
      if (mounted) setState(() => _sent = true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                  title: _sent ? 'Asked' : 'Forgotten your password?',
                  subtitle: _sent
                      ? null
                      : 'A Director or the President will set you a new one.',
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      GwdSpace.xl, 0, GwdSpace.xl, GwdSpace.xl),
                  child: _sent
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(GwdSpace.lg),
                              decoration: BoxDecoration(
                                color: GwdColors.successSoft,
                                borderRadius: BorderRadius.circular(GwdRadius.md),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.check_circle_outline_rounded,
                                      size: 18, color: GwdColors.success),
                                  const SizedBox(width: GwdSpace.md),
                                  Expanded(
                                    child: Text(
                                      'They have been told. They will pass you a '
                                      'temporary password — you will be asked to '
                                      'pick your own when you sign in with it.',
                                      style: GwdType.callout.copyWith(
                                          color: GwdColors.inkSecondaryOf(context)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: GwdSpace.xl),
                            PrimaryButton(
                              label: 'Done',
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'There is no reset email — the club does not run a '
                              'mail server. Instead this tells the people who can '
                              'fix it, and they hand you a new password however '
                              'they normally reach you.',
                              style: GwdType.footnote.copyWith(
                                  color: GwdColors.inkTertiaryOf(context)),
                            ),
                            const SizedBox(height: GwdSpace.lg),
                            GwdField(
                              label: 'Your email',
                              controller: _email,
                              autofocus: true,
                              keyboardType: TextInputType.emailAddress,
                              onChanged: (_) => setState(() {}),
                              onSubmitted: (_) => _submit(),
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: GwdSpace.lg),
                              ErrorNote(message: _error!),
                            ],
                            const SizedBox(height: GwdSpace.xl),
                            PrimaryButton(
                              label: 'Ask for a reset',
                              icon: Icons.help_outline_rounded,
                              busy: _busy,
                              onPressed:
                                  _email.text.contains('@') ? _submit : null,
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
