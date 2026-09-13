import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme/apple_motion.dart';
import '../../app/theme/gwd_theme.dart';
import '../../app/widgets/brand.dart';
import '../../app/widgets/common.dart';
import '../../core/state/session.dart';
import 'change_password_sheet.dart';
import 'sign_up_page.dart';

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final session = AppScope.readSession(context);
    if (_email.text.trim().isEmpty || _password.text.isEmpty) return;
    FocusScope.of(context).unfocus();
    await session.signIn(email: _email.text.trim(), password: _password.text);
  }

  @override
  Widget build(BuildContext context) {
    final session = AppScope.sessionOf(context);

    return Scaffold(
      backgroundColor: GwdColors.canvasOf(context),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: GwdSpace.gutter(MediaQuery.sizeOf(context).width),
              vertical: GwdSpace.xxl,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // The club's actual mark, drawn and animated in. First
                  // impression of the app is its own logo, not a stock glyph.
                  const AppleStaggerItem(
                    index: 0,
                    child: Center(child: GwdLogo(size: 110)),
                  ),
                  const SizedBox(height: GwdSpace.xl),
                  AppleStaggerItem(
                    index: 1,
                    child: Center(
                      child: Text(
                        'Get Work Done',
                        style: GwdType.eyebrow.copyWith(
                          color: GwdColors.inkTertiaryOf(context),
                          letterSpacing: 2.2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: GwdSpace.xxxl),

                  AppleStaggerItem(
                    index: 1,
                    child: Text('Sign in',
                        style: GwdType.largeTitle.copyWith(color: GwdColors.inkOf(context))),
                  ),
                  const SizedBox(height: GwdSpace.xl),

                  AppleStaggerItem(
                    index: 2,
                    child: GwdField(
                      label: 'Email',
                      controller: _email,
                      hint: 'you@college.edu',
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                    ),
                  ),
                  const SizedBox(height: GwdSpace.lg),
                  AppleStaggerItem(
                    index: 3,
                    child: GwdField(
                      label: 'Password',
                      controller: _password,
                      obscure: true,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                    ),
                  ),

                  if (session.error != null) ...[
                    const SizedBox(height: GwdSpace.lg),
                    ErrorNote(message: session.error!),
                  ],

                  const SizedBox(height: GwdSpace.xxl),
                  AppleStaggerItem(
                    index: 4,
                    child: PrimaryButton(
                      label: 'Sign in',
                      busy: session.busy,
                      onPressed: _submit,
                    ),
                  ),

                  const SizedBox(height: GwdSpace.md),
                  AppleStaggerItem(
                    index: 4,
                    child: Center(
                      child: PressableScale(
                        onTap: () => showForgotPasswordSheet(
                          context,
                          email: _email.text.trim(),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(GwdSpace.sm),
                          child: Text(
                            'Forgotten your password?',
                            style: GwdType.footnote.copyWith(
                                color: GwdColors.inkTertiaryOf(context)),
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: GwdSpace.md),
                  AppleStaggerItem(
                    index: 5,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('New to the club?',
                            style: GwdType.callout
                                .copyWith(color: GwdColors.inkSecondaryOf(context))),
                        const SizedBox(width: GwdSpace.xs),
                        PressableScale(
                          haptic: HapticStrength.selection,
                          onTap: () {
                            session.clearError();
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const SignUpPage()),
                            );
                          },
                          child: Text(
                            'Request access',
                            style: GwdType.callout.copyWith(
                              color: GwdColors.primaryRed,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // The server address is baked in at build time, and a router
                  // handing the laptop a new IP silently breaks every installed
                  // copy. Being able to retype it beats reinstalling — so it is
                  // quiet normally, and offers itself when a connection fails.
                  const SizedBox(height: GwdSpace.xxl),
                  AppleStaggerItem(
                    index: 6,
                    child: _ServerAddress(
                      highlighted: session.error?.contains("reach") ?? false,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows which server this build talks to, and lets the user change it.
///
/// Deliberately understated until something fails: most people never need it,
/// but when the address is wrong it is the only thing that can fix the app
/// without a reinstall.
class _ServerAddress extends StatelessWidget {
  const _ServerAddress({required this.highlighted});

  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final session = AppScope.sessionOf(context);
    final shown = session.baseUrl.isEmpty ? 'this site' : session.baseUrl;

    return PressableScale(
      haptic: HapticStrength.selection,
      onTap: () => _edit(context, session),
      child: AnimatedContainer(
        duration: AppleDuration.standard,
        curve: AppleCurves.standard,
        padding: const EdgeInsets.symmetric(
            horizontal: GwdSpace.md, vertical: GwdSpace.sm + 2),
        decoration: BoxDecoration(
          color: highlighted
              ? GwdColors.primaryRed.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(GwdRadius.md),
          border: Border.all(
            color: highlighted
                ? GwdColors.primaryRed.withValues(alpha: 0.4)
                : GwdColors.hairlineOf(context),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.dns_outlined,
                size: 13,
                color: highlighted
                    ? GwdColors.primaryRed
                    : GwdColors.inkTertiaryOf(context)),
            const SizedBox(width: GwdSpace.sm),
            Flexible(
              child: Text(
                shown,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GwdType.footnote.copyWith(
                  color: highlighted
                      ? GwdColors.primaryRed
                      : GwdColors.inkTertiaryOf(context),
                ),
              ),
            ),
            const SizedBox(width: GwdSpace.sm),
            Text('Change',
                style: GwdType.caption.copyWith(color: GwdColors.primaryRed)),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, Session session) async {
    final controller = TextEditingController(text: session.serverOverride ?? session.baseUrl);
    final messenger = ScaffoldMessenger.of(context);

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: GwdColors.surfaceOf(context),
        title: Text('Server address',
            style: GwdType.title3.copyWith(color: GwdColors.inkOf(context))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The address your club\'s server is running on. Your laptop prints '
              'it when the backend starts.',
              style: GwdType.footnote
                  .copyWith(color: GwdColors.inkSecondaryOf(context)),
            ),
            const SizedBox(height: GwdSpace.lg),
            GwdField(
              label: 'Address',
              controller: controller,
              hint: '10.0.0.5:4000',
              autofocus: true,
              keyboardType: TextInputType.url,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (saved != true) return;
    final ok = await session.setServer(controller.text);
    messenger.showSnackBar(SnackBar(
      content: Text(ok
          ? 'Now using ${session.baseUrl}'
          : 'That does not look like a server address.'),
    ));
  }
}
