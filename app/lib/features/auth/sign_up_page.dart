import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme/apple_motion.dart';
import '../../app/theme/gwd_theme.dart';
import '../../app/widgets/common.dart';
import '../../core/models/club_role.dart';
import '../../core/models/department.dart';

/// Section 4.1 — name, email, phone, department.
///
/// Role is asked for too, because the approval chain routes on it: a Member
/// goes to their department Lead, a Lead goes to the President. Asking up front
/// is what lets the request land with the right person first time.
class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();

  ClubRole _role = ClubRole.clubMember;
  Department? _department;
  List<Department> _departments = const [];
  bool _loadingDepartments = true;

  @override
  void initState() {
    super.initState();
    _loadDepartments();
  }

  Future<void> _loadDepartments() async {
    final list = await AppScope.readSession(context).publicDepartments();
    if (!mounted) return;
    setState(() {
      _departments = list;
      _loadingDepartments = false;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    if (_name.text.trim().length < 2) return false;
    if (!_email.text.contains('@')) return false;
    if (_phone.text.trim().length < 7) return false;
    if (_password.text.length < 8) return false;
    if (_role.hasDepartment && _department == null) return false;
    return true;
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    FocusScope.of(context).unfocus();
    final session = AppScope.readSession(context);
    final ok = await session.signUp(
      name: _name.text.trim(),
      email: _email.text.trim(),
      phone: _phone.text.trim(),
      password: _password.text,
      role: _role,
      departmentId: _role.hasDepartment ? _department?.id : null,
    );
    // On success the root listens to the session and swaps to the pending
    // screen, so this route just needs to get out of the way.
    if (ok && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final session = AppScope.sessionOf(context);

    return Scaffold(
      backgroundColor: GwdColors.canvasOf(context),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Back to sign in',
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: GwdSpace.gutter(MediaQuery.sizeOf(context).width),
              vertical: GwdSpace.lg,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppleStaggerItem(
                    index: 0,
                    child: Text('Request access',
                        style: GwdType.largeTitle.copyWith(color: GwdColors.inkOf(context))),
                  ),
                  const SizedBox(height: GwdSpace.xs),
                  AppleStaggerItem(
                    index: 1,
                    child: Text(
                      'Your request goes to ${_role.approverLabel} for approval.',
                      style: GwdType.callout.copyWith(color: GwdColors.inkSecondaryOf(context)),
                    ),
                  ),
                  const SizedBox(height: GwdSpace.xxl),

                  AppleStaggerItem(
                    index: 2,
                    child: GwdField(
                      label: 'Full name',
                      controller: _name,
                      hint: 'Aisha Khan',
                      textInputAction: TextInputAction.next,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(height: GwdSpace.lg),
                  AppleStaggerItem(
                    index: 3,
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
                    index: 4,
                    child: GwdField(
                      label: 'Phone number',
                      controller: _phone,
                      hint: '+91 98765 43210',
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                    ),
                  ),
                  const SizedBox(height: GwdSpace.lg),
                  AppleStaggerItem(
                    index: 5,
                    child: GwdField(
                      label: 'Password',
                      controller: _password,
                      obscure: true,
                      hint: 'At least 8 characters',
                      textInputAction: TextInputAction.done,
                    ),
                  ),

                  const SizedBox(height: GwdSpace.xl),
                  AppleStaggerItem(
                    index: 6,
                    child: _RolePicker(
                      value: _role,
                      onChanged: (role) => setState(() {
                        _role = role;
                        if (!role.hasDepartment) _department = null;
                      }),
                    ),
                  ),

                  if (_role.hasDepartment) ...[
                    const SizedBox(height: GwdSpace.xl),
                    AppleStaggerItem(
                      index: 7,
                      child: _DepartmentPicker(
                        departments: _departments,
                        loading: _loadingDepartments,
                        value: _department,
                        onChanged: (d) => setState(() => _department = d),
                      ),
                    ),
                  ],

                  if (session.error != null) ...[
                    const SizedBox(height: GwdSpace.lg),
                    ErrorNote(message: session.error!),
                  ],

                  const SizedBox(height: GwdSpace.xxl),
                  PrimaryButton(
                    label: 'Send request',
                    busy: session.busy,
                    onPressed: _canSubmit ? _submit : null,
                  ),
                  const SizedBox(height: GwdSpace.xxl),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RolePicker extends StatelessWidget {
  const _RolePicker({required this.value, required this.onChanged});

  final ClubRole value;
  final ValueChanged<ClubRole> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('I AM JOINING AS',
            style: GwdType.eyebrow.copyWith(color: GwdColors.inkTertiaryOf(context))),
        const SizedBox(height: GwdSpace.sm),
        Wrap(
          spacing: GwdSpace.sm,
          runSpacing: GwdSpace.sm,
          children: [
            for (final role in ClubRoleDetails.selectableAtSignup)
              PressableScale(
                haptic: HapticStrength.selection,
                onTap: () => onChanged(role),
                child: AnimatedContainer(
                  duration: AppleDuration.fast,
                  curve: AppleCurves.standard,
                  padding: const EdgeInsets.symmetric(
                      horizontal: GwdSpace.md + 2, vertical: GwdSpace.sm + 2),
                  decoration: BoxDecoration(
                    color: role == value
                        ? GwdColors.primaryRed
                        : GwdColors.surfaceOf(context),
                    borderRadius: BorderRadius.circular(GwdRadius.md),
                    border: Border.all(
                      color: role == value
                          ? GwdColors.primaryRed
                          : GwdColors.hairlineOf(context),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(role.icon,
                          size: 14,
                          color: role == value ? Colors.white : GwdColors.inkSecondaryOf(context)),
                      const SizedBox(width: 6),
                      Text(
                        role.title,
                        style: GwdType.callout.copyWith(
                          color: role == value ? Colors.white : GwdColors.inkOf(context),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _DepartmentPicker extends StatelessWidget {
  const _DepartmentPicker({
    required this.departments,
    required this.loading,
    required this.value,
    required this.onChanged,
  });

  final List<Department> departments;
  final bool loading;
  final Department? value;
  final ValueChanged<Department> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('DEPARTMENT',
            style: GwdType.eyebrow.copyWith(color: GwdColors.inkTertiaryOf(context))),
        const SizedBox(height: GwdSpace.sm),
        if (loading)
          const SkeletonList(count: 2, height: 46)
        else if (departments.isEmpty)
          Text(
            'No departments are open for signup yet. Ask the President to add one.',
            style: GwdType.footnote.copyWith(color: GwdColors.inkSecondaryOf(context)),
          )
        else
          Column(
            children: [
              for (final department in departments)
                Padding(
                  padding: const EdgeInsets.only(bottom: GwdSpace.sm),
                  child: PressableScale(
                    haptic: HapticStrength.selection,
                    onTap: () => onChanged(department),
                    child: AnimatedContainer(
                      duration: AppleDuration.fast,
                      curve: AppleCurves.standard,
                      padding: const EdgeInsets.all(GwdSpace.md),
                      decoration: BoxDecoration(
                        color: GwdColors.surfaceOf(context),
                        borderRadius: BorderRadius.circular(GwdRadius.lg),
                        border: Border.all(
                          color: department.id == value?.id
                              ? GwdColors.primaryRed
                              : GwdColors.hairlineOf(context),
                          width: department.id == value?.id ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Avatar(
                            initials: department.initials,
                            tint: department.tint,
                            size: 34,
                            selected: department.id == value?.id,
                          ),
                          const SizedBox(width: GwdSpace.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(department.name,
                                    style: GwdType.headline
                                        .copyWith(color: GwdColors.inkOf(context))),
                                if (department.description.isNotEmpty)
                                  Text(
                                    department.description,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GwdType.footnote.copyWith(
                                        color: GwdColors.inkTertiaryOf(context)),
                                  ),
                              ],
                            ),
                          ),
                          if (department.id == value?.id)
                            const Icon(Icons.check_circle_rounded,
                                size: 20, color: GwdColors.primaryRed),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
