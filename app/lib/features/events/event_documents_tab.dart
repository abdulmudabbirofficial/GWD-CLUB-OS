import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_scope.dart';
import '../../app/responsive.dart';
import '../../app/theme/apple_motion.dart';
import '../../app/theme/gwd_theme.dart';
import '../../app/widgets/common.dart';
import '../../core/api/api_client.dart';
import '../../core/models/event_document.dart';
import 'upload_document_sheet.dart';

/// The event's paperwork.
///
/// Split into two sections that look and behave differently on purpose:
///
///   Official approvals — the permission letters and venue bookings. These
///     carry a status, a named approver and a full version history, because
///     "who said yes, to which version, when" is the entire point of them.
///   Files — posters, scripts, budgets. Anyone can add one; they carry no
///     status, because pretending a poster needs sign-off is theatre.
///
/// Every control here is offered only when the server says this person may use
/// it — and the server checks again on the request. Hiding a button is a
/// courtesy, never the security boundary.
class EventDocumentsTab extends StatefulWidget {
  const EventDocumentsTab({
    super.key,
    required this.eventId,
    required this.eventName,
  });

  final String eventId;
  final String eventName;

  @override
  State<EventDocumentsTab> createState() => _EventDocumentsTabState();
}

class _EventDocumentsTabState extends State<EventDocumentsTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppScope.readStore(context).loadEventDocuments(widget.eventId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.storeOf(context);
    final docs = store.documentsFor(widget.eventId);
    final gutter = Layout.of(context).gutter;

    if (docs == null) {
      return const Padding(
        padding: EdgeInsets.all(GwdSpace.xl),
        child: SkeletonList(count: 3, height: 84),
      );
    }

    var step = 0;
    int next() => step++;

    return ListView(
      padding: EdgeInsets.fromLTRB(gutter, GwdSpace.lg, gutter, GwdSpace.xxxl),
      children: [
        AppleStaggerItem(
          index: next(),
          child: SectionHeader(
            title: 'Official approvals',
            subtitle: docs.canUploadApproval
                ? 'Permission letters, venue bookings, faculty sign-off'
                : 'Filed and signed off by club leadership',
            trailing: docs.canUploadApproval
                ? _AddButton(
                    onTap: () => showUploadDocumentSheet(
                      context,
                      eventId: widget.eventId,
                      kind: DocumentKind.approval,
                    ),
                  )
                : null,
          ),
        ),

        if (docs.approvals.isEmpty)
          AppleStaggerItem(
            index: next(),
            child: _QuietEmpty(
              icon: Icons.assignment_outlined,
              message: docs.canUploadApproval
                  ? 'Nothing on file yet. Add the permission letter when it comes through.'
                  : 'No official paperwork filed for this event yet.',
            ),
          )
        else
          for (final doc in docs.approvals)
            AppleStaggerItem(
              index: next(),
              child: Padding(
                padding: const EdgeInsets.only(bottom: GwdSpace.sm),
                child: _ApprovalCard(
                  eventId: widget.eventId,
                  document: doc,
                  canDecide: docs.canDecide,
                  canReplace: docs.canUploadApproval,
                ),
              ),
            ),

        const SizedBox(height: GwdSpace.xxl),
        AppleStaggerItem(
          index: next(),
          child: SectionHeader(
            title: 'Files',
            subtitle: 'Posters, scripts, budgets — anything the team needs',
            trailing: docs.canUploadFile
                ? _AddButton(
                    onTap: () => showUploadDocumentSheet(
                      context,
                      eventId: widget.eventId,
                      kind: DocumentKind.file,
                    ),
                  )
                : null,
          ),
        ),

        if (docs.files.isEmpty)
          AppleStaggerItem(
            index: next(),
            child: const _QuietEmpty(
              icon: Icons.folder_open_outlined,
              message: 'Nothing shared yet. Drop in the poster draft to get started.',
            ),
          )
        else
          for (final doc in docs.files)
            AppleStaggerItem(
              index: next(),
              child: Padding(
                padding: const EdgeInsets.only(bottom: GwdSpace.sm),
                child: _FileRow(eventId: widget.eventId, document: doc),
              ),
            ),
      ],
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => PressableScale(
        onTap: onTap,
        haptic: HapticStrength.light,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: GwdColors.primaryRed.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(GwdRadius.sm),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add_rounded, size: 13, color: GwdColors.primaryRed),
              const SizedBox(width: 3),
              Text('Add',
                  style: GwdType.caption.copyWith(
                      fontSize: 10, color: GwdColors.primaryRed, letterSpacing: 0.2)),
            ],
          ),
        ),
      );
}

class _QuietEmpty extends StatelessWidget {
  const _QuietEmpty({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(GwdSpace.lg),
        decoration: BoxDecoration(
          color: GwdColors.sunkenOf(context),
          borderRadius: BorderRadius.circular(GwdRadius.lg),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: GwdColors.inkTertiaryOf(context)),
            const SizedBox(width: GwdSpace.md),
            Expanded(
              child: Text(message,
                  style: GwdType.footnote
                      .copyWith(color: GwdColors.inkTertiaryOf(context))),
            ),
          ],
        ),
      );
}

/// An official approval. Wears its status, its approver and its version count,
/// because those three facts are what somebody is actually checking.
class _ApprovalCard extends StatelessWidget {
  const _ApprovalCard({
    required this.eventId,
    required this.document,
    required this.canDecide,
    required this.canReplace,
  });

  final String eventId;
  final EventDocument document;
  final bool canDecide;
  final bool canReplace;

  @override
  Widget build(BuildContext context) {
    final status = document.status;

    return SurfaceCard(
      padding: const EdgeInsets.all(GwdSpace.lg),
      borderColor: status == DocumentStatus.pending
          ? GwdColors.warning.withValues(alpha: 0.35)
          : null,
      onTap: () => _open(context, document),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: status.tint.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(GwdRadius.md),
                ),
                child: Icon(document.icon, size: 18, color: status.tint),
              ),
              const SizedBox(width: GwdSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(document.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GwdType.headline
                            .copyWith(color: GwdColors.inkOf(context))),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        GwdChip(
                          label: status.label,
                          color: status.tint,
                          icon: status.icon,
                          dense: true,
                        ),
                        if (document.version > 1) ...[
                          const SizedBox(width: 5),
                          GwdChip(
                            label: 'v${document.version}',
                            color: GwdColors.inkTertiaryOf(context),
                            dense: true,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: GwdSpace.md),
          Text(
            status == DocumentStatus.approved && document.decidedByName != null
                ? 'Signed off by ${document.decidedByName}'
                : status == DocumentStatus.rejected && document.decidedByName != null
                    ? 'Sent back by ${document.decidedByName}'
                    : 'Filed by ${document.createdByName}',
            style:
                GwdType.footnote.copyWith(color: GwdColors.inkSecondaryOf(context)),
          ),
          if (document.decisionNote.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('“${document.decisionNote}”',
                style: GwdType.footnote
                    .copyWith(color: GwdColors.inkTertiaryOf(context))),
          ],

          if (canDecide && status == DocumentStatus.pending) ...[
            const SizedBox(height: GwdSpace.lg),
            Row(
              children: [
                Expanded(
                  child: _DecisionButton(
                    label: 'Approve',
                    icon: Icons.verified_rounded,
                    tint: GwdColors.success,
                    onTap: () => _decide(context, eventId, document, true),
                  ),
                ),
                const SizedBox(width: GwdSpace.sm),
                Expanded(
                  child: _DecisionButton(
                    label: 'Send back',
                    icon: Icons.undo_rounded,
                    tint: GwdColors.critical,
                    onTap: () => _decide(context, eventId, document, false),
                  ),
                ),
              ],
            ),
          ],

          if (document.history.length > 1) ...[
            const SizedBox(height: GwdSpace.md),
            _VersionHistory(eventId: eventId, document: document),
          ],

          if (canReplace) ...[
            const SizedBox(height: GwdSpace.md),
            PressableScale(
              onTap: () => showUploadDocumentSheet(
                context,
                eventId: eventId,
                kind: DocumentKind.approval,
                replacing: document,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.upload_file_rounded,
                      size: 14, color: GwdColors.inkTertiaryOf(context)),
                  const SizedBox(width: 5),
                  Text('File a new version',
                      style: GwdType.footnote
                          .copyWith(color: GwdColors.inkTertiaryOf(context))),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DecisionButton extends StatelessWidget {
  const _DecisionButton({
    required this.label,
    required this.icon,
    required this.tint,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => PressableScale(
        onTap: onTap,
        haptic: HapticStrength.medium,
        child: Container(
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(GwdRadius.md),
            border: Border.all(color: tint.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: tint),
              const SizedBox(width: 6),
              Text(label,
                  style: GwdType.callout
                      .copyWith(color: tint, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
}

Future<void> _decide(
  BuildContext context,
  String eventId,
  EventDocument document,
  bool approved,
) async {
  final store = AppScope.readStore(context);
  final messenger = ScaffoldMessenger.of(context);
  final controller = TextEditingController();

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: GwdColors.surfaceOf(dialogContext),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(GwdRadius.xl)),
      title: Text(
        approved ? 'Approve this document?' : 'Send it back?',
        style: GwdType.title3.copyWith(color: GwdColors.inkOf(dialogContext)),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            approved
                ? 'This records that you, by name, signed off “${document.title}”. '
                    'Everyone on the event will see it as approved.'
                : 'Say what needs fixing so the next version lands right.',
            style: GwdType.callout
                .copyWith(color: GwdColors.inkSecondaryOf(dialogContext)),
          ),
          const SizedBox(height: GwdSpace.lg),
          GwdField(
            label: approved ? 'Note (optional)' : 'What needs changing',
            controller: controller,
            maxLines: 2,
            autofocus: !approved,
          ),
        ],
      ),
      actions: [
        // Neutral, deliberately. Crimson is the app's accent, so a red
        // "Cancel" reads as the dangerous button — which is backwards.
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text('Cancel',
              style: GwdType.callout
                  .copyWith(color: GwdColors.inkSecondaryOf(dialogContext))),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(
            approved ? 'Approve' : 'Send back',
            style: GwdType.callout.copyWith(
                color: approved ? GwdColors.success : GwdColors.critical,
                fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );

  if (confirmed == true) {
    try {
      await store.decideDocument(
        eventId: eventId,
        documentId: document.id,
        approved: approved,
        note: controller.text.trim(),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
  controller.dispose();
}

/// Previous versions, collapsed. History has to be reachable — that is the
/// whole reason for keeping it — but it should not crowd the current version.
class _VersionHistory extends StatefulWidget {
  const _VersionHistory({required this.eventId, required this.document});
  final String eventId;
  final EventDocument document;

  @override
  State<_VersionHistory> createState() => _VersionHistoryState();
}

class _VersionHistoryState extends State<_VersionHistory> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final older = widget.document.history.where((v) => v.superseded).toList();
    if (older.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PressableScale(
          onTap: () => setState(() => _expanded = !_expanded),
          pressedScale: 0.99,
          child: Row(
            children: [
              Icon(Icons.history_rounded,
                  size: 14, color: GwdColors.inkTertiaryOf(context)),
              const SizedBox(width: 5),
              Text(
                older.length == 1
                    ? 'One earlier version'
                    : '${older.length} earlier versions',
                style: GwdType.footnote
                    .copyWith(color: GwdColors.inkTertiaryOf(context)),
              ),
              const Spacer(),
              AnimatedRotation(
                turns: _expanded ? 0.5 : 0,
                duration: AppleDuration.standard,
                child: Icon(Icons.expand_more_rounded,
                    size: 16, color: GwdColors.inkTertiaryOf(context)),
              ),
            ],
          ),
        ),
        AnimatedSize(
          duration: AppleDuration.standard,
          curve: AppleCurves.standard,
          alignment: Alignment.topCenter,
          child: _expanded
              ? Padding(
                  padding: const EdgeInsets.only(top: GwdSpace.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final version in older.reversed)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: PressableScale(
                            onTap: () => _open(context, widget.document,
                                version: version.version),
                            child: Row(
                              children: [
                                Text('v${version.version}',
                                    style: GwdType.caption.copyWith(
                                        fontSize: 9.5,
                                        letterSpacing: 0,
                                        color: GwdColors.inkTertiaryOf(context))),
                                const SizedBox(width: GwdSpace.sm),
                                Expanded(
                                  child: Text(
                                    version.note.isEmpty
                                        ? version.filename
                                        : version.note,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GwdType.footnote.copyWith(
                                        color:
                                            GwdColors.inkSecondaryOf(context)),
                                  ),
                                ),
                                Text(version.uploadedByName.split(' ').first,
                                    style: GwdType.caption.copyWith(
                                        fontSize: 9,
                                        letterSpacing: 0,
                                        color:
                                            GwdColors.inkTertiaryOf(context))),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.eventId, required this.document});
  final String eventId;
  final EventDocument document;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(GwdSpace.md),
      onTap: () => _open(context, document),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: GwdColors.sunkenOf(context),
              borderRadius: BorderRadius.circular(GwdRadius.sm),
            ),
            child: Icon(document.icon,
                size: 16, color: GwdColors.inkSecondaryOf(context)),
          ),
          const SizedBox(width: GwdSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(document.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GwdType.callout.copyWith(
                        color: GwdColors.inkOf(context),
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 1),
                Text(
                  [
                    document.createdByName.split(' ').first,
                    if (document.sizeLabel.isNotEmpty) document.sizeLabel,
                  ].join('  ·  '),
                  style: GwdType.caption.copyWith(
                      fontSize: 9.5,
                      letterSpacing: 0,
                      color: GwdColors.inkTertiaryOf(context)),
                ),
              ],
            ),
          ),
          Icon(document.isLink ? Icons.open_in_new_rounded : Icons.download_rounded,
              size: 16, color: GwdColors.inkTertiaryOf(context)),
        ],
      ),
    );
  }
}

/// Open a document.
///
/// A link goes to the browser. A stored file cannot: the route needs the
/// session token, which travels as a header, so the app fetches the bytes
/// itself and then hands the local file to whatever the phone already uses to
/// read a PDF.
Future<void> _open(BuildContext context, EventDocument document, {int? version}) async {
  final store = AppScope.readStore(context);
  final messenger = ScaffoldMessenger.of(context);

  final link = document.link;
  if (link != null && link.isNotEmpty && version == null) {
    final uri = Uri.tryParse(link);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
    return;
  }

  messenger.showSnackBar(
    SnackBar(
      duration: const Duration(seconds: 30),
      content: Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          ),
          const SizedBox(width: GwdSpace.md),
          Expanded(child: Text('Opening ${document.title}…')),
        ],
      ),
    ),
  );

  try {
    final path = await store.downloadDocument(
      document.id,
      version: version,
      filename: document.filename ?? document.title,
    );
    messenger.hideCurrentSnackBar();
    final result = await OpenFilex.open(path);
    if (result.type != ResultType.done) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Nothing on this device can open that kind of file.'),
        ),
      );
    }
  } on ApiException catch (e) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  }
}
