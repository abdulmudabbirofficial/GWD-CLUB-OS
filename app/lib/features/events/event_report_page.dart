import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/responsive.dart';
import '../../app/theme/apple_motion.dart';
import '../../app/theme/gwd_theme.dart';
import '../../app/widgets/common.dart';
import '../../core/models/event_report.dart';
import '../../core/plural.dart';

/// What happened, and what the next person should know.
///
/// Half of this page is **derived and never typed**: tasks completed, what it
/// cost, how many people were on it, what paperwork is on file. Asking somebody
/// to fill those in by hand produces numbers that are wrong, and a report with
/// one wrong number in it is a report nobody reads the rest of.
///
/// The typed half is three questions, deliberately not ten. A form long enough
/// to feel like homework gets submitted empty, and an empty report is worse
/// than none — it looks like the event went fine.
class EventReportPage extends StatefulWidget {
  const EventReportPage({super.key, required this.eventId});

  final String eventId;

  @override
  State<EventReportPage> createState() => _EventReportPageState();
}

class _EventReportPageState extends State<EventReportPage> {
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await AppScope.readStore(context).loadEventReport(widget.eventId);
      if (mounted) setState(() { _loading = false; _error = null; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = '$e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = AppScope.storeOf(context).reportFor(widget.eventId);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Event report'),
        actions: [
          if (report != null && report.canEdit)
            IconButton(
              tooltip: report.written ? 'Edit the report' : 'Write the report',
              icon: Icon(report.written ? Icons.edit_rounded : Icons.post_add_rounded),
              onPressed: () => _write(report),
            ),
        ],
      ),
      body: Builder(builder: (context) {
        if (report == null) {
          if (_loading) return const SkeletonList();
          return ErrorNote(
            message: _error ?? 'Could not load the report.',
            onRetry: () async {
              setState(() => _loading = true);
              await _load();
            },
          );
        }
        return RefreshIndicator(
          onRefresh: _load,
          child: ContentWidth(
            child: _Body(report: report, onWrite: () => _write(report)),
          ),
        );
      }),
    );
  }

  Future<void> _write(EventReport report) async {
    await showGwdSheet<void>(
      context: context,
      builder: (_) => _ReportEditor(eventId: widget.eventId, existing: report.entry),
    );
    if (mounted) await _load();
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.report, required this.onWrite});

  final EventReport report;
  final VoidCallback onWrite;

  @override
  Widget build(BuildContext context) {
    final gutter = GwdSpace.gutter(MediaQuery.sizeOf(context).width);
    final figures = report.figures;
    final entry = report.entry;

    return ListView(
      padding: EdgeInsets.fromLTRB(gutter, GwdSpace.md, gutter, GwdSpace.xxxl),
      children: [
        FluidReveal(child: _Head(report: report)),

        const SizedBox(height: GwdSpace.xl),
        const SectionHeader(
          title: 'By the numbers',
          subtitle: 'Counted from the event itself, never typed in',
        ),
        _Figures(figures: figures, attendance: entry?.attendance),

        const SizedBox(height: GwdSpace.xl),
        if (!report.written) ...[
          EmptyState(
            icon: Icons.history_edu_rounded,
            title: 'No write-up yet',
            message: report.canEdit
                ? 'Three questions: what went well, what did not, and what the '
                    'next person running this should know.'
                : 'Whoever ran this event has not written it up yet.',
            action: report.canEdit
                ? PrimaryButton(
                    label: 'Write it up', expand: false, onPressed: onWrite)
                : null,
          ),
        ] else ...[
          const SectionHeader(title: 'How it went'),
          if (entry!.highlights.isNotEmpty)
            _Passage(
              icon: Icons.thumb_up_alt_outlined,
              tint: GwdColors.success,
              title: 'What went well',
              body: entry.highlights,
            ),
          if (entry.challenges.isNotEmpty)
            _Passage(
              icon: Icons.report_problem_outlined,
              tint: GwdColors.warning,
              title: 'What did not',
              body: entry.challenges,
            ),
          if (entry.learnings.isNotEmpty)
            _Passage(
              icon: Icons.lightbulb_outline_rounded,
              tint: GwdColors.info,
              title: 'For next time',
              body: entry.learnings,
            ),
          if (entry.submittedByName != null) ...[
            const SizedBox(height: GwdSpace.md),
            Text(
              'Written up by ${entry.submittedByName}'
              '${entry.submittedAt != null ? ' · ${_when(entry.submittedAt!)}' : ''}',
              style: GwdType.caption.copyWith(color: GwdColors.inkTertiaryOf(context)),
            ),
          ],
        ],
      ],
    );
  }

  static String _when(DateTime at) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${at.day} ${months[at.month - 1]} ${at.year}';
  }
}

class _Head extends StatelessWidget {
  const _Head({required this.report});

  final EventReport report;

  @override
  Widget build(BuildContext context) {
    final event = report.event;
    final accent = GwdColors.readableOn(context, event.bannerColor);

    return SurfaceCard(
      emphasis: SurfaceEmphasis.raised,
      padding: const EdgeInsets.all(GwdSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(event.status.label.toUpperCase(),
              style: GwdType.eyebrow.copyWith(color: accent)),
          const SizedBox(height: GwdSpace.xs),
          Text(event.name,
              style: GwdType.title2.copyWith(color: GwdColors.inkOf(context))),
          const SizedBox(height: 2),
          Text(
            [
              event.whenLabel,
              if (event.venue.isNotEmpty) event.venue,
            ].join(' · '),
            style: GwdType.footnote.copyWith(color: GwdColors.inkTertiaryOf(context)),
          ),
        ],
      ),
    );
  }
}

class _Figures extends StatelessWidget {
  const _Figures({required this.figures, required this.attendance});

  final EventReportFigures figures;
  final int? attendance;

  @override
  Widget build(BuildContext context) {
    final tiles = <_Figure>[
      if (attendance != null)
        _Figure('Came along', '$attendance', Icons.groups_rounded, GwdColors.primaryRed),
      _Figure(
        'Work finished',
        '${figures.taskCompleted} of ${figures.taskCount}',
        Icons.task_alt_rounded,
        GwdColors.success,
      ),
      _Figure('On the team', '${figures.teamSize}', Icons.people_outline_rounded,
          GwdColors.info),
      _Figure('Departments', '${figures.departmentCount}',
          Icons.workspaces_outline, GwdColors.accents[5]),
      if (figures.billCount > 0)
        _Figure('Spent', _money(figures.spentPaise), Icons.receipt_long_rounded,
            GwdColors.warning),
      if (figures.owedPaise > 0)
        _Figure('Still owed', _money(figures.owedPaise),
            Icons.account_balance_wallet_outlined, GwdColors.primaryRed),
      if (figures.runSheetTotal > 0)
        _Figure('Run sheet', '${figures.runSheetDone} of ${figures.runSheetTotal}',
            Icons.schedule_rounded, GwdColors.accents[6]),
      if (figures.documentCount > 0)
        _Figure('Paperwork', countOf(figures.documentCount, 'file'),
            Icons.folder_outlined, GwdColors.info),
      if (figures.pointsEarned > 0)
        _Figure('Points earned', '${figures.pointsEarned}',
            Icons.auto_awesome_rounded, GwdColors.accents[1]),
    ];

    return LayoutBuilder(builder: (context, constraints) {
      // Two per row on a phone, three once there is room. A fixed count makes
      // one of them a sliver on a narrow screen and an empty field on a wide.
      final columns = constraints.maxWidth >= 560 ? 3 : 2;
      const gap = GwdSpace.sm;
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (var i = 0; i < tiles.length; i++)
            SizedBox(
              width: width,
              child: AppleStaggerItem(index: i, child: _FigureTile(figure: tiles[i])),
            ),
        ],
      );
    });
  }

  /// Paise to rupees with lakh/crore grouping — ₹1,45,000, not ₹145,000.
  static String _money(int paise) {
    final rupees = (paise / 100).round();
    final digits = rupees.toString();
    if (digits.length <= 3) return '₹$digits';
    final last3 = digits.substring(digits.length - 3);
    var rest = digits.substring(0, digits.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    return '₹${parts.join(',')},$last3';
  }
}

class _Figure {
  const _Figure(this.label, this.value, this.icon, this.tint);
  final String label;
  final String value;
  final IconData icon;
  final Color tint;
}

class _FigureTile extends StatelessWidget {
  const _FigureTile({required this.figure});

  final _Figure figure;

  @override
  Widget build(BuildContext context) {
    final tint = GwdColors.readableOn(context, figure.tint);
    return SurfaceCard(
      padding: const EdgeInsets.all(GwdSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(figure.icon, size: 17, color: tint),
          const SizedBox(height: GwdSpace.sm),
          Text(figure.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GwdType.title3.copyWith(color: GwdColors.inkOf(context))),
          const SizedBox(height: 1),
          Text(figure.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GwdType.caption
                  .copyWith(color: GwdColors.inkTertiaryOf(context))),
        ],
      ),
    );
  }
}

class _Passage extends StatelessWidget {
  const _Passage({
    required this.icon,
    required this.tint,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color tint;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final accent = GwdColors.readableOn(context, tint);
    return Padding(
      padding: const EdgeInsets.only(bottom: GwdSpace.sm),
      child: SurfaceCard(
        padding: const EdgeInsets.all(GwdSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: accent),
                const SizedBox(width: GwdSpace.sm),
                Text(title,
                    style: GwdType.eyebrow.copyWith(color: accent)),
              ],
            ),
            const SizedBox(height: GwdSpace.sm),
            Text(body,
                style: GwdType.body.copyWith(
                    color: GwdColors.inkSecondaryOf(context), height: 1.45)),
          ],
        ),
      ),
    );
  }
}

/* --------------------------------------------------------------- the sheet */

class _ReportEditor extends StatefulWidget {
  const _ReportEditor({required this.eventId, this.existing});

  final String eventId;
  final EventReportEntry? existing;

  @override
  State<_ReportEditor> createState() => _ReportEditorState();
}

class _ReportEditorState extends State<_ReportEditor> {
  late final _attendance =
      TextEditingController(text: widget.existing?.attendance?.toString() ?? '');
  late final _highlights = TextEditingController(text: widget.existing?.highlights ?? '');
  late final _challenges = TextEditingController(text: widget.existing?.challenges ?? '');
  late final _learnings = TextEditingController(text: widget.existing?.learnings ?? '');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _attendance.dispose();
    _highlights.dispose();
    _challenges.dispose();
    _learnings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: GwdColors.canvasOf(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(GwdRadius.xxl)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetHeader(
              title: 'How did it go?',
              subtitle: 'Three questions. Skip any of them — a short honest note '
                  'is worth more than a full form nobody meant.',
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                    GwdSpace.xl, 0, GwdSpace.xl, GwdSpace.xl),
                child: Column(
                  children: [
                    GwdField(
                      label: 'How many came',
                      controller: _attendance,
                      hint: 'Optional — a rough count is fine',
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: GwdSpace.lg),
                    GwdField(
                      label: 'What went well',
                      controller: _highlights,
                      hint: 'The hall was full and the sound held up',
                      maxLines: 3,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                    const SizedBox(height: GwdSpace.lg),
                    GwdField(
                      label: 'What did not',
                      controller: _challenges,
                      hint: 'The projector took twenty minutes to find',
                      maxLines: 3,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                    const SizedBox(height: GwdSpace.lg),
                    GwdField(
                      label: 'What the next person should know',
                      controller: _learnings,
                      hint: 'Book the AV desk a week out, not the day before',
                      maxLines: 3,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: GwdSpace.lg),
                      ErrorNote(message: _error!),
                    ],
                    const SizedBox(height: GwdSpace.xl),
                    PrimaryButton(
                      label: 'Save the report',
                      busy: _busy,
                      onPressed: _save,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final typed = _attendance.text.trim();
    // Parsed here as well as on the server, so a typo comes back as a sentence
    // under the field instead of a round trip ending in a red toast.
    final attendance = typed.isEmpty ? null : int.tryParse(typed);
    if (typed.isNotEmpty && (attendance == null || attendance < 0)) {
      setState(() => _error = 'How many came has to be a plain number, or left blank.');
      return;
    }

    setState(() { _busy = true; _error = null; });
    final store = AppScope.readStore(context);
    final navigator = Navigator.of(context);
    try {
      await store.saveEventReport(
        widget.eventId,
        attendance: attendance,
        highlights: _highlights.text.trim(),
        challenges: _challenges.text.trim(),
        learnings: _learnings.text.trim(),
      );
      navigator.pop();
    } catch (e) {
      if (mounted) setState(() { _busy = false; _error = '$e'; });
    }
  }
}
