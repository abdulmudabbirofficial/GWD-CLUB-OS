import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_scope.dart';
import '../../app/theme/apple_motion.dart';
import '../../app/theme/gwd_theme.dart';
import '../../app/widgets/common.dart';
import '../../core/models/schedule_entry.dart';
import 'schedule_editor.dart';

/// A schedule entry, in full.
///
/// The thing the old build got wrong: tapping "Core team sync" reopened the
/// calendar editor, which told you nothing and only worked if you had edit
/// rights. Everyone can open this; only people who can edit see edit controls.
class ScheduleEntryPage extends StatefulWidget {
  const ScheduleEntryPage({super.key, required this.entryId});

  final String entryId;

  @override
  State<ScheduleEntryPage> createState() => _ScheduleEntryPageState();
}

class _ScheduleEntryPageState extends State<ScheduleEntryPage> {
  List<Map<String, String>> _attendees = const [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final json = await AppScope.readStore(context).scheduleDetail(widget.entryId);
      if (!mounted) return;
      setState(() {
        _attendees = ((json['attendees'] as List?) ?? [])
            .whereType<Map>()
            .map((e) => {'id': '${e['id']}', 'name': '${e['name']}'})
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.storeOf(context);
    final session = AppScope.sessionOf(context);
    final entry = store.scheduleById(widget.entryId);
    final gutter = GwdSpace.gutter(MediaQuery.sizeOf(context).width);

    if (entry == null) {
      return Scaffold(
        backgroundColor: GwdColors.canvasOf(context),
        appBar: AppBar(),
        body: const EmptyState(
          icon: Icons.event_busy_outlined,
          title: 'Not on the schedule',
          message: 'This entry may have been removed.',
        ),
      );
    }

    final canEdit = store.capabilities.canCreateScheduleEntry;
    final going = entry.isAttending(session.me?.id ?? '');

    return Scaffold(
      backgroundColor: GwdColors.canvasOf(context),
      appBar: AppBar(
        title: Text(entry.categoryName,
            style: GwdType.title3.copyWith(color: GwdColors.inkOf(context))),
        actions: [
          if (canEdit)
            IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_outlined, size: 19),
              onPressed: () => showScheduleEditor(context, existing: entry),
            ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(gutter, 0, gutter, GwdSpace.xxxl),
        children: [
          FluidReveal(
            child: Row(
              children: [
                GwdChip(
                    label: entry.categoryName.toUpperCase(),
                    color: entry.tint,
                    icon: entry.icon),
                const Spacer(),
                Text(entry.relativeLabel,
                    style: GwdType.caption
                        .copyWith(color: GwdColors.inkTertiaryOf(context))),
              ],
            ),
          ),
          const SizedBox(height: GwdSpace.md),
          FluidReveal(
            index: 1,
            child: Text(entry.title,
                style: GwdType.largeTitle.copyWith(color: GwdColors.inkOf(context))),
          ),

          const SizedBox(height: GwdSpace.xl),

          // ---------- the facts ----------
          FluidReveal(
            index: 2,
            child: SurfaceCard(
              child: Column(
                children: [
                  _Fact(
                    icon: Icons.schedule_rounded,
                    label: 'When',
                    value: _when(entry),
                  ),
                  if (entry.location.isNotEmpty) ...[
                    _divider(context),
                    _Fact(
                        icon: Icons.place_outlined,
                        label: 'Where',
                        value: entry.location),
                  ],
                  if (entry.createdByName != null) ...[
                    _divider(context),
                    _Fact(
                        icon: Icons.person_outline,
                        label: 'Added by',
                        value: entry.createdByName!),
                  ],
                  if (store.departmentById(entry.departmentId) != null) ...[
                    _divider(context),
                    _Fact(
                      icon: Icons.workspaces_outline,
                      label: 'Department',
                      value: store.departmentById(entry.departmentId)!.name,
                    ),
                  ],
                ],
              ),
            ),
          ),

          // ---------- marketing specifics ----------
          if (entry.hasContentFields) ...[
            const SizedBox(height: GwdSpace.lg),
            FluidReveal(
              index: 3,
              child: SurfaceCard(
                child: Column(
                  children: [
                    if (entry.platform != null)
                      _Fact(
                          icon: Icons.public_rounded,
                          label: 'Platform',
                          value: entry.platform!.label),
                    if (entry.format != null) ...[
                      _divider(context),
                      _Fact(
                          icon: entry.format!.icon,
                          label: 'Format',
                          value: entry.format!.label),
                    ],
                    if (entry.stage != null) ...[
                      _divider(context),
                      Row(
                        children: [
                          Icon(Icons.timeline_rounded,
                              size: 16, color: GwdColors.inkTertiaryOf(context)),
                          const SizedBox(width: GwdSpace.md),
                          Text('Stage',
                              style: GwdType.callout.copyWith(
                                  color: GwdColors.inkTertiaryOf(context))),
                          const Spacer(),
                          GwdChip(
                              label: entry.stage!.label.toUpperCase(),
                              color: entry.stage!.tint),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],

          if (entry.description.isNotEmpty) ...[
            const SizedBox(height: GwdSpace.lg),
            FluidReveal(
              index: 4,
              child: SurfaceCard(
                child: Text(
                  entry.description,
                  style: GwdType.body.copyWith(color: GwdColors.inkSecondaryOf(context)),
                ),
              ),
            ),
          ],

          if (entry.meetingUrl.isNotEmpty) ...[
            const SizedBox(height: GwdSpace.lg),
            PrimaryButton(
              label: 'Join the meeting',
              icon: Icons.videocam_outlined,
              tone: entry.tint,
              onPressed: () => _open(entry.meetingUrl),
            ),
          ],

          // ---------- RSVP ----------
          if (!entry.isPast) ...[
            const SizedBox(height: GwdSpace.lg),
            _RsvpBar(
              going: going,
              count: entry.rsvps.length,
              busy: _busy,
              onToggle: () async {
                setState(() => _busy = true);
                try {
                  await store.toggleRsvp(entry);
                  await _load();
                } finally {
                  if (mounted) setState(() => _busy = false);
                }
              },
            ),
          ],

          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: GwdSpace.xl),
              child: SkeletonList(count: 1, height: 48),
            )
          else if (_attendees.isNotEmpty) ...[
            const SizedBox(height: GwdSpace.xl),
            SectionHeader(title: 'Going', subtitle: '${_attendees.length} so far'),
            Wrap(
              spacing: GwdSpace.sm,
              runSpacing: GwdSpace.sm,
              children: [
                for (final a in _attendees)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: GwdSpace.md, vertical: 6),
                    decoration: BoxDecoration(
                      color: GwdColors.surfaceOf(context),
                      borderRadius: BorderRadius.circular(GwdRadius.pill),
                      border: Border.all(color: GwdColors.hairlineOf(context)),
                    ),
                    child: Text(a['name'] ?? '',
                        style: GwdType.footnote
                            .copyWith(color: GwdColors.inkSecondaryOf(context))),
                  ),
              ],
            ),
          ],

          if (canEdit) ...[
            const SizedBox(height: GwdSpace.xxl),
            SecondaryButton(
              label: 'Remove from schedule',
              icon: Icons.delete_outline_rounded,
              expand: true,
              destructive: true,
              onPressed: () => _confirmDelete(entry),
            ),
          ],
        ],
      ),
    );
  }

  Widget _divider(BuildContext context) =>
      Divider(height: GwdSpace.xl, color: GwdColors.hairlineOf(context));

  static String _when(ScheduleEntry entry) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final d = entry.date;
    final base = '${d.day} ${months[d.month - 1]} · ${entry.timeLabel}';
    final end = entry.endDate;
    if (end == null) return base;
    final endTime =
        '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}';
    return '$base – $endTime';
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Could not open that link.')));
      }
    }
  }

  Future<void> _confirmDelete(ScheduleEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: GwdColors.surfaceOf(context),
        title: Text('Remove this from the schedule?',
            style: GwdType.title3.copyWith(color: GwdColors.inkOf(context))),
        content: Text(
          'Everyone in the club will stop seeing it. This cannot be undone.',
          style: GwdType.callout.copyWith(color: GwdColors.inkSecondaryOf(context)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove', style: TextStyle(color: GwdColors.critical)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final navigator = Navigator.of(context);
    await AppScope.readStore(context).deleteScheduleEntry(entry.id);
    if (mounted) navigator.pop();
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: GwdColors.inkTertiaryOf(context)),
        const SizedBox(width: GwdSpace.md),
        Text(label,
            style: GwdType.callout.copyWith(color: GwdColors.inkTertiaryOf(context))),
        const SizedBox(width: GwdSpace.md),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GwdType.headline.copyWith(color: GwdColors.inkOf(context)),
          ),
        ),
      ],
    );
  }
}

class _RsvpBar extends StatelessWidget {
  const _RsvpBar({
    required this.going,
    required this.count,
    required this.busy,
    required this.onToggle,
  });

  final bool going;
  final int count;
  final bool busy;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      haptic: HapticStrength.medium,
      onTap: busy ? null : onToggle,
      child: AnimatedContainer(
        duration: AppleDuration.standard,
        curve: AppleCurves.standard,
        padding: const EdgeInsets.symmetric(
            horizontal: GwdSpace.lg, vertical: GwdSpace.md),
        decoration: BoxDecoration(
          color: going
              ? GwdColors.success.withValues(alpha: 0.12)
              : GwdColors.surfaceOf(context),
          borderRadius: BorderRadius.circular(GwdRadius.lg),
          border: Border.all(
            color: going ? GwdColors.success : GwdColors.hairlineOf(context),
          ),
        ),
        child: Row(
          children: [
            AnimatedScale(
              duration: AppleDuration.fast,
              curve: AppleCurves.overshoot,
              scale: going ? 1.1 : 1,
              child: Icon(
                going ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
                size: 20,
                color: going ? GwdColors.success : GwdColors.inkSecondaryOf(context),
              ),
            ),
            const SizedBox(width: GwdSpace.md),
            Expanded(
              child: Text(
                going ? "You're going" : 'Count me in',
                style: GwdType.headline.copyWith(
                  color: going ? GwdColors.success : GwdColors.inkOf(context),
                ),
              ),
            ),
            if (count > 0)
              Text('$count going',
                  style: GwdType.footnote
                      .copyWith(color: GwdColors.inkTertiaryOf(context))),
          ],
        ),
      ),
    );
  }
}
