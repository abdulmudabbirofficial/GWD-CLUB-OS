import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_scope.dart';
import '../../app/responsive.dart';
import '../../app/theme/apple_motion.dart';
import '../../app/theme/gwd_theme.dart';
import '../../app/widgets/brand.dart';
import '../../app/widgets/common.dart';
import '../../core/api/api_client.dart';
import '../../core/models/club_role.dart';
import '../../core/models/club_task.dart';
import '../../core/models/member.dart';

/// One member's full record.
///
/// Previously tapping someone opened nothing but an award-points sheet, which
/// told you nothing about them. This is the actual record: who they are, how to
/// reach them, which department, what they have been given and what they have
/// finished. Awarding points is *one action on it*, not the whole screen.
///
/// Access is the server's call (`canViewMemberDetail`): leadership and Leads
/// see anyone, a Member sees their own department plus the executive above
/// them, and a supervisor's record is visible only to other supervisors.
class MemberStatsPage extends StatefulWidget {
  /// Either a [Member] already in hand — from the directory or the recognition
  /// list, where the row is right there — or just a [userId], for the places
  /// that only know an id (a department roster, an event team). The record
  /// comes from the server either way; passing the member only saves a blank
  /// frame while it loads.
  const MemberStatsPage({super.key, this.member, this.userId})
      : assert(member != null || userId != null,
            'MemberStatsPage needs a member or a userId.');

  final Member? member;
  final String? userId;

  @override
  State<MemberStatsPage> createState() => _MemberStatsPageState();
}

class _MemberStatsPageState extends State<MemberStatsPage> {
  Map<String, dynamic>? _stats;
  Map<String, dynamic>? _department;
  Member? _full;
  List<Map<String, dynamic>> _recent = const [];
  bool _loading = true;
  String? _error;
  bool _forbidden = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _userId => widget.member?.id ?? widget.userId!;

  Future<void> _load() async {
    try {
      final json = await AppScope.readStore(context).memberStats(_userId);
      if (!mounted) return;
      setState(() {
        _stats = (json['stats'] as Map?)?.cast<String, dynamic>();
        _department = (json['department'] as Map?)?.cast<String, dynamic>();
        final user = (json['user'] as Map?)?.cast<String, dynamic>();
        if (user != null) _full = Member.fromJson(user);
        _recent = ((json['recentTasks'] as List?) ?? [])
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _forbidden = e.isForbidden;
          _error = e.message;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) setState(() { _error = '$error'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.storeOf(context);
    final member = _full ?? widget.member ?? store.memberById(widget.userId);

    // Opened by id, and neither the server nor the store has the person yet.
    if (member == null) {
      return Scaffold(
        backgroundColor: GwdColors.canvasOf(context),
        appBar: AppBar(),
        body: _forbidden || _error != null
            ? EmptyState(
                icon: Icons.lock_outline_rounded,
                title: 'Not visible to you',
                message: _error ?? 'You cannot open this record.',
              )
            : const Padding(
                padding: EdgeInsets.all(GwdSpace.xl),
                child: SkeletonList(count: 3, height: 92),
              ),
      );
    }

    final layout = Layout.of(context);
    final s = _stats;

    final assigned = (s?['assigned'] as num?)?.toInt() ?? 0;
    final completed = (s?['completed'] as num?)?.toInt() ?? 0;
    final rate = (s?['completionRate'] as num?)?.toInt() ?? 0;
    final ranked = s?['ranked'] as bool? ?? false;
    final canAward = store.capabilities.canAwardPoints && member.role.earnsPoints;

    return Scaffold(
      backgroundColor: GwdColors.canvasOf(context),
      appBar: AppBar(
        title: Text(member.role.title,
            style: GwdType.title3.copyWith(color: GwdColors.inkOf(context))),
      ),
      body: RefreshIndicator(
        color: GwdColors.primaryRed,
        onRefresh: _load,
        child: ContentWidth(
          child: _forbidden
              ? const EmptyState(
                  icon: Icons.lock_outline_rounded,
                  title: 'Not visible to you',
                  message:
                      'You can open members of your own department, and the club\'s '
                      'leadership. Other departments show their overall progress '
                      'instead.',
                )
              : ListView(
                  padding:
                      EdgeInsets.fromLTRB(layout.gutter, 0, layout.gutter, GwdSpace.xxxl),
                  children: [
                    // ---------- identity ----------
                    FluidReveal(
                      child: Row(
                        children: [
                          Avatar(initials: member.initials, tint: member.tint, size: 62),
                          const SizedBox(width: GwdSpace.lg),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(member.displayName,
                                    style: GwdType.title1.copyWith(
                                      color: member.isUnnamed
                                          ? GwdColors.inkTertiaryOf(context)
                                          : GwdColors.inkOf(context),
                                    )),
                                const SizedBox(height: 3),
                                // What they are and where, on one line —
                                // "Marketing Lead". The badge beside it used to
                                // say "LEAD" next to a separate department
                                // name, which made the reader assemble the
                                // sentence themselves.
                                Text(
                                    member.positionLine(
                                        _department?['name'] as String?),
                                    style: GwdType.callout.copyWith(
                                        color:
                                            GwdColors.inkSecondaryOf(context))),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: GwdSpace.md),
                    FluidReveal(
                      index: 1,
                      child: Text(member.role.remit,
                          style: GwdType.callout
                              .copyWith(color: GwdColors.inkSecondaryOf(context))),
                    ),

                    const SizedBox(height: GwdSpace.xxl),

                    if (_loading)
                      const Center(child: Padding(
                        padding: EdgeInsets.all(GwdSpace.xxl),
                        child: BracketLoader(),
                      ))
                    else if (_error != null)
                      ErrorNote(message: _error!)
                    else ...[
                      // ---------- how to reach them ----------
                      const BrandedSectionHeader(title: 'Contact'),
                      FluidReveal(
                        index: 2,
                        child: SurfaceCard(
                          child: Column(
                            children: [
                              _ContactRow(
                                icon: Icons.mail_outline_rounded,
                                label: 'Email',
                                value: member.email,
                                onTap: member.email.isEmpty
                                    ? null
                                    : () => _open('mailto:${member.email}'),
                              ),
                              if ((member.phone ?? '').isNotEmpty) ...[
                                Divider(height: GwdSpace.xl,
                                    color: GwdColors.hairlineOf(context)),
                                _ContactRow(
                                  icon: Icons.phone_outlined,
                                  label: 'Phone',
                                  value: member.phone!,
                                  onTap: () => _open('tel:${member.phone}'),
                                ),
                              ],
                              if (_department?['leadName'] != null
                                  && _department?['isLead'] != true) ...[
                                Divider(height: GwdSpace.xl,
                                    color: GwdColors.hairlineOf(context)),
                                _ContactRow(
                                  icon: Icons.flag_outlined,
                                  label: 'Reports to',
                                  value: '${_department!['leadName']}',
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),

                      // ---------- the headline ratio ----------
                      const SizedBox(height: GwdSpace.xl),
                      const BrandedSectionHeader(
                        title: 'Workload',
                        subtitle: 'What they have been given, and what has landed',
                      ),
                      FluidReveal(
                        index: 3,
                        child: SurfaceCard(
                          emphasis: SurfaceEmphasis.raised,
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  ProgressArc(
                                    progress: assigned == 0 ? 0 : completed / assigned,
                                    color: _rateColor(rate),
                                    size: 74,
                                    child: AnimatedCounter(
                                      value: rate,
                                      suffix: '%',
                                      style: GwdType.title3
                                          .copyWith(color: GwdColors.inkOf(context)),
                                    ),
                                  ),
                                  const SizedBox(width: GwdSpace.lg),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text('$completed of $assigned done',
                                            style: GwdType.title3.copyWith(
                                                color: GwdColors.inkOf(context))),
                                        const SizedBox(height: 4),
                                        Text(
                                          ranked
                                              ? 'Steadily getting through it'
                                              : 'Still early — not much assigned yet',
                                          style: GwdType.footnote.copyWith(
                                              color: GwdColors.inkTertiaryOf(context)),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              if (member.role.earnsPoints) ...[
                                Divider(height: GwdSpace.xl,
                                    color: GwdColors.hairlineOf(context)),
                                Row(
                                  children: [
                                    Icon(Icons.auto_awesome_outlined,
                                        size: 15,
                                        color: GwdColors.inkTertiaryOf(context)),
                                    const SizedBox(width: GwdSpace.md),
                                    Text('Points',
                                        style: GwdType.callout.copyWith(
                                            color: GwdColors.inkTertiaryOf(context))),
                                    const Spacer(),
                                    AnimatedCounter(
                                      value: member.points,
                                      style: GwdType.headline
                                          .copyWith(color: GwdColors.inkOf(context)),
                                    ),
                                  ],
                                ),
                              ],
                              if (((s?['assignedByThem'] as num?)?.toInt() ?? 0) > 0) ...[
                                Divider(height: GwdSpace.xl,
                                    color: GwdColors.hairlineOf(context)),
                                Row(
                                  children: [
                                    Icon(Icons.outbox_outlined,
                                        size: 15,
                                        color: GwdColors.inkTertiaryOf(context)),
                                    const SizedBox(width: GwdSpace.md),
                                    Text('Handed out to others',
                                        style: GwdType.callout.copyWith(
                                            color: GwdColors.inkTertiaryOf(context))),
                                    const Spacer(),
                                    Text('${s!['assignedByThem']}',
                                        style: GwdType.headline
                                            .merge(GwdType.numeric)
                                            .copyWith(color: GwdColors.inkOf(context))),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: GwdSpace.lg),
                      FluidReveal(index: 4, child: _Breakdown(stats: s ?? const {})),

                      if ((s?['avgCompletionHours'] as num?) != null) ...[
                        const SizedBox(height: GwdSpace.md),
                        SurfaceCard(
                          padding: const EdgeInsets.all(GwdSpace.md),
                          child: Row(
                            children: [
                              Icon(Icons.timer_outlined,
                                  size: 16, color: GwdColors.inkTertiaryOf(context)),
                              const SizedBox(width: GwdSpace.md),
                              Expanded(
                                child: Text('Typically finishes in',
                                    style: GwdType.callout.copyWith(
                                        color: GwdColors.inkSecondaryOf(context))),
                              ),
                              Text('${s!['avgCompletionHours']}h',
                                  style: GwdType.headline
                                      .merge(GwdType.numeric)
                                      .copyWith(color: GwdColors.inkOf(context))),
                            ],
                          ),
                        ),
                      ],

                      // ---------- recent work ----------
                      if (_recent.isNotEmpty) ...[
                        const SizedBox(height: GwdSpace.xxl),
                        const BrandedSectionHeader(title: 'Recent work'),
                        for (var i = 0; i < _recent.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: GwdSpace.sm),
                            child: AppleStaggerItem(
                                index: i, child: _RecentRow(task: _recent[i])),
                          ),
                      ] else if (assigned == 0) ...[
                        const SizedBox(height: GwdSpace.xl),
                        const EmptyState(
                          compact: true,
                          icon: Icons.inbox_outlined,
                          title: 'No work yet',
                          message: 'Nothing has been assigned to them so far.',
                        ),
                      ],

                      // ---------- one action, not the whole screen ----------
                      if (canAward) ...[
                        const SizedBox(height: GwdSpace.xxl),
                        PrimaryButton(
                          label: 'Award points',
                          icon: Icons.auto_awesome_outlined,
                          onPressed: () => _award(member),
                        ),
                      ],

                      // Naming an account that arrived without one. Loud while
                      // the name is still a placeholder, because until it is
                      // set this person appears as "No name set" on every board
                      // in the club; quiet afterwards, since correcting a
                      // spelling is not something anybody comes here to do.
                      if (store.capabilities.canManageDepartments) ...[
                        const SizedBox(height: GwdSpace.md),
                        if (member.mustSetName)
                          PrimaryButton(
                            label: 'Set their name',
                            icon: Icons.person_outline_rounded,
                            onPressed: () => _rename(member),
                          )
                        else
                          SecondaryButton(
                            label: 'Change their name',
                            icon: Icons.badge_outlined,
                            expand: true,
                            onPressed: () => _rename(member),
                          ),
                      ],

                      // Resetting somebody's password is a real action but a
                      // rare one, so it stays a quiet secondary — surfaced
                      // loudly only when they have actually asked for it.
                      if (store.capabilities.canManageDepartments) ...[
                        const SizedBox(height: GwdSpace.md),
                        if (member.passwordResetRequested)
                          Padding(
                            padding: const EdgeInsets.only(bottom: GwdSpace.sm),
                            child: Container(
                              padding: const EdgeInsets.all(GwdSpace.md),
                              decoration: BoxDecoration(
                                color: GwdColors.warning.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(GwdRadius.md),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.error_outline_rounded,
                                      size: 15, color: GwdColors.warning),
                                  const SizedBox(width: GwdSpace.sm),
                                  Expanded(
                                    child: Text(
                                      '${member.firstName} says they cannot sign in.',
                                      style: GwdType.footnote.copyWith(
                                          color: GwdColors.inkSecondaryOf(context)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        SecondaryButton(
                          label: 'Reset their password',
                          icon: Icons.lock_reset_rounded,
                          expand: true,
                          onPressed: () => _resetPassword(member),
                        ),
                      ],
                    ],
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _award(Member member) async {
    await showAwardSheet(context, member);
    if (mounted) await _load();
  }

  /// Put a real name on an account.
  ///
  /// Whoever hands the credentials over is the one who knows whose account it
  /// is, and this is where they are looking at it. The person is told their
  /// name was changed — finding that out later, silently, is worse than the
  /// rename itself.
  Future<void> _rename(Member member) async {
    final store = AppScope.readStore(context);
    final messenger = ScaffoldMessenger.of(context);
    final controller = TextEditingController(
      text: member.mustSetName ? '' : member.name,
    );

    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final valid = controller.text.trim().length >= 2;
            return AlertDialog(
              backgroundColor: GwdColors.surfaceOf(dialogContext),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(GwdRadius.xl)),
              title: Text(
                member.mustSetName ? 'Who is this?' : 'Change their name',
                style:
                    GwdType.title3.copyWith(color: GwdColors.inkOf(dialogContext)),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    member.mustSetName
                        ? 'This account was created before anyone held it, so it '
                            'still shows ${member.role.title} instead of a person.'
                        : 'They will be told their name was changed.',
                    style: GwdType.callout
                        .copyWith(color: GwdColors.inkSecondaryOf(dialogContext)),
                  ),
                  const SizedBox(height: GwdSpace.lg),
                  GwdField(
                    label: 'Full name',
                    controller: controller,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    onChanged: (_) => setDialogState(() {}),
                    onSubmitted: (_) {
                      if (valid) {
                        Navigator.of(dialogContext).pop(controller.text.trim());
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text('Cancel',
                      style: GwdType.callout.copyWith(
                          color: GwdColors.inkSecondaryOf(dialogContext))),
                ),
                TextButton(
                  onPressed: valid
                      ? () => Navigator.of(dialogContext).pop(controller.text.trim())
                      : null,
                  child: Text('Save',
                      style: GwdType.callout.copyWith(
                        color: valid
                            ? GwdColors.primaryRed
                            : GwdColors.inkTertiaryOf(dialogContext),
                        fontWeight: FontWeight.w700,
                      )),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
    if (name == null || !mounted) return;

    try {
      await store.renameMember(member.id, name);
      if (mounted) await _load();
      messenger.showSnackBar(SnackBar(content: Text('Named $name.')));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  /// Reset somebody's password and show the temporary one **once**.
  ///
  /// Shown rather than emailed because the club has no mail server — and
  /// because handing it over in person is a stronger identity check than an
  /// inbox. It is not recoverable afterwards, so the dialog says so and offers
  /// a copy button.
  Future<void> _resetPassword(Member member) async {
    final store = AppScope.readStore(context);
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: GwdColors.surfaceOf(dialogContext),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(GwdRadius.xl)),
        title: Text('Reset ${member.firstName}’s password?',
            style: GwdType.title3.copyWith(color: GwdColors.inkOf(dialogContext))),
        content: Text(
          'Their current password stops working immediately. You will be given a '
          'temporary one to pass on, and they will be asked to choose their own.',
          style:
              GwdType.callout.copyWith(color: GwdColors.inkSecondaryOf(dialogContext)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Cancel',
                style: GwdType.callout
                    .copyWith(color: GwdColors.inkSecondaryOf(dialogContext))),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Reset it',
                style: GwdType.callout.copyWith(
                    color: GwdColors.primaryRed, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final temporary = await store.resetPasswordFor(member.id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: GwdColors.surfaceOf(dialogContext),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(GwdRadius.xl)),
          title: Text('Give this to ${member.firstName}',
              style: GwdType.title3.copyWith(color: GwdColors.inkOf(dialogContext))),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(GwdSpace.lg),
                decoration: BoxDecoration(
                  color: GwdColors.sunkenOf(dialogContext),
                  borderRadius: BorderRadius.circular(GwdRadius.md),
                ),
                child: SelectableText(
                  temporary,
                  textAlign: TextAlign.center,
                  style: GwdType.title3.merge(GwdType.numeric).copyWith(
                      color: GwdColors.inkOf(dialogContext), letterSpacing: 1.5),
                ),
              ),
              const SizedBox(height: GwdSpace.md),
              Text(
                'It is not shown again. They will be asked to pick their own '
                'password the first time they sign in with it.',
                style: GwdType.footnote
                    .copyWith(color: GwdColors.inkTertiaryOf(dialogContext)),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: temporary));
                Navigator.of(dialogContext).pop();
                messenger.showSnackBar(
                  const SnackBar(content: Text('Copied.')),
                );
              },
              child: Text('Copy',
                  style: GwdType.callout.copyWith(
                      color: GwdColors.primaryRed, fontWeight: FontWeight.w700)),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text('Done',
                  style: GwdType.callout
                      .copyWith(color: GwdColors.inkSecondaryOf(dialogContext))),
            ),
          ],
        ),
      );
      if (mounted) await _load();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  static Color _rateColor(int rate) {
    if (rate >= 80) return GwdColors.success;
    if (rate >= 50) return GwdColors.info;
    return GwdColors.warning;
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      children: [
        Icon(icon, size: 16, color: GwdColors.inkTertiaryOf(context)),
        const SizedBox(width: GwdSpace.md),
        Text(label,
            style: GwdType.callout.copyWith(color: GwdColors.inkTertiaryOf(context))),
        const SizedBox(width: GwdSpace.md),
        Expanded(
          child: Text(
            value.isEmpty ? '—' : value,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GwdType.headline.copyWith(
              color: onTap == null ? GwdColors.inkOf(context) : GwdColors.primaryRed,
            ),
          ),
        ),
        if (onTap != null) ...[
          const SizedBox(width: 4),
          const Icon(Icons.open_in_new_rounded, size: 13, color: GwdColors.primaryRed),
        ],
      ],
    );
    if (onTap == null) return row;
    return PressableScale(onTap: onTap, haptic: HapticStrength.light, child: row);
  }
}

class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.stats});
  final Map<String, dynamic> stats;

  @override
  Widget build(BuildContext context) {
    int n(String key) => (stats[key] as num?)?.toInt() ?? 0;

    final rows = <(String, int, Color, IconData)>[
      ('Completed', n('completed'), GwdColors.success, Icons.check_circle_rounded),
      ('In progress', n('inProgress'), GwdColors.info, Icons.timelapse_rounded),
      ('Pending', n('pending'), GwdColors.inkTertiaryOf(context), Icons.radio_button_unchecked),
      if (n('blocked') > 0)
        ('Blocked', n('blocked'), GwdColors.warning, Icons.report_problem_outlined),
      if (n('overdue') > 0)
        ('Overdue', n('overdue'), GwdColors.critical, Icons.schedule_rounded),
    ];

    final total = n('assigned');

    return SurfaceCard(
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: GwdSpace.md),
            Row(
              children: [
                Icon(rows[i].$4, size: 15, color: rows[i].$3),
                const SizedBox(width: GwdSpace.md),
                SizedBox(
                  width: 88,
                  child: Text(rows[i].$1,
                      style: GwdType.callout
                          .copyWith(color: GwdColors.inkSecondaryOf(context))),
                ),
                Expanded(
                  child: TweenAnimationBuilder<double>(
                    duration: AppleDuration.deliberate,
                    curve: AppleCurves.standard,
                    tween: Tween(begin: 0, end: total == 0 ? 0 : rows[i].$2 / total),
                    builder: (context, t, _) => Container(
                      height: 7,
                      decoration: BoxDecoration(
                        color: GwdColors.sunkenOf(context),
                        borderRadius: BorderRadius.circular(GwdRadius.pill),
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: t.clamp(0.0, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: rows[i].$3,
                            borderRadius: BorderRadius.circular(GwdRadius.pill),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: GwdSpace.md),
                SizedBox(
                  width: 26,
                  child: Text('${rows[i].$2}',
                      textAlign: TextAlign.right,
                      style: GwdType.callout.merge(GwdType.numeric).copyWith(
                            color: GwdColors.inkOf(context),
                          )),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.task});
  final Map<String, dynamic> task;

  @override
  Widget build(BuildContext context) {
    final status = TaskStatus.fromWire(task['status'] as String?);
    return SurfaceCard(
      padding: const EdgeInsets.all(GwdSpace.md),
      child: Row(
        children: [
          Icon(status.icon, size: 16, color: status.tint),
          const SizedBox(width: GwdSpace.md),
          Expanded(
            child: Text(
              '${task['title']}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GwdType.callout.copyWith(
                color: status == TaskStatus.completed
                    ? GwdColors.inkTertiaryOf(context)
                    : GwdColors.inkOf(context),
                decoration: status == TaskStatus.completed
                    ? TextDecoration.lineThrough
                    : TextDecoration.none,
                decorationColor: GwdColors.inkTertiaryOf(context),
              ),
            ),
          ),
          const SizedBox(width: GwdSpace.sm),
          GwdChip(label: status.label.toUpperCase(), color: status.tint, dense: true),
        ],
      ),
    );
  }
}

/// Recognise someone.
///
/// Tasks are a flat one point each, which cannot capture the person who
/// rescued an event or carried a week nobody logged. Limited to supervisors and
/// the President so it stays meaningful.
Future<void> showAwardSheet(BuildContext context, Member member) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AwardSheet(member: member),
  );
}

class _AwardSheet extends StatefulWidget {
  const _AwardSheet({required this.member});
  final Member member;

  @override
  State<_AwardSheet> createState() => _AwardSheetState();
}

class _AwardSheetState extends State<_AwardSheet> {
  final _reason = TextEditingController();
  int _points = 1;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _award() async {
    setState(() { _busy = true; _error = null; });
    try {
      final store = AppScope.readStore(context);
      final navigator = Navigator.of(context);
      final messenger = ScaffoldMessenger.of(context);
      await store.awardPoints(widget.member.id, _points, _reason.text.trim());
      navigator.pop();
      messenger.showSnackBar(SnackBar(
        content: Text(
            '$_points point${_points == 1 ? '' : 's'} to ${widget.member.firstName}.'),
      ));
    } catch (error) {
      if (mounted) setState(() { _error = '$error'; _busy = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final member = widget.member;

    return Container(
      decoration: BoxDecoration(
        color: GwdColors.canvasOf(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(GwdRadius.xxl)),
      ),
      padding: EdgeInsets.only(bottom: inset),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetHeader(title: 'Recognise ${member.firstName}', subtitle: member.role.title),
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(GwdSpace.xl, 0, GwdSpace.xl, GwdSpace.xl),
              child: Column(
                children: [
                  Text('HOW MANY POINTS',
                      style: GwdType.eyebrow
                          .copyWith(color: GwdColors.inkTertiaryOf(context))),
                  const SizedBox(height: GwdSpace.sm),
                  Row(
                    children: [
                      for (final n in const [1, 2, 3, 5, 10])
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: GwdSpace.sm),
                            child: PressableScale(
                              haptic: HapticStrength.selection,
                              onTap: () => setState(() => _points = n),
                              child: AnimatedContainer(
                                duration: AppleDuration.fast,
                                padding:
                                    const EdgeInsets.symmetric(vertical: GwdSpace.md),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: _points == n
                                      ? GwdColors.primaryRed
                                      : GwdColors.surfaceOf(context),
                                  borderRadius: BorderRadius.circular(GwdRadius.md),
                                  border: Border.all(
                                    color: _points == n
                                        ? GwdColors.primaryRed
                                        : GwdColors.hairlineOf(context),
                                  ),
                                ),
                                child: Text('+$n',
                                    style: GwdType.headline
                                        .merge(GwdType.numeric)
                                        .copyWith(
                                          color: _points == n
                                              ? Colors.white
                                              : GwdColors.inkOf(context),
                                        )),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: GwdSpace.lg),
                  GwdField(
                    label: 'What for',
                    controller: _reason,
                    hint: 'Ran the whole registration desk solo',
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: GwdSpace.lg),
                    ErrorNote(message: _error!),
                  ],
                  const SizedBox(height: GwdSpace.xl),
                  PrimaryButton(
                    label: 'Award $_points point${_points == 1 ? '' : 's'}',
                    icon: Icons.auto_awesome_outlined,
                    busy: _busy,
                    onPressed: _award,
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
