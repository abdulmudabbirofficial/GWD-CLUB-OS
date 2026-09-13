import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme/apple_motion.dart';
import '../../app/theme/gwd_theme.dart';
import '../../app/widgets/common.dart';
import '../../core/api/api_client.dart';
import '../../core/models/event_document.dart';

/// Put a document on an event.
///
/// Two ways in, because clubs use both: attach the actual file, or paste a
/// link to where it already lives. Refusing the link just means the permission
/// letter stays in a WhatsApp thread and the app is wrong about what exists.
Future<void> showUploadDocumentSheet(
  BuildContext context, {
  required String eventId,
  required DocumentKind kind,
  EventDocument? replacing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _UploadDocumentSheet(
      eventId: eventId,
      kind: kind,
      replacing: replacing,
    ),
  );
}

class _UploadDocumentSheet extends StatefulWidget {
  const _UploadDocumentSheet({
    required this.eventId,
    required this.kind,
    this.replacing,
  });

  final String eventId;
  final DocumentKind kind;
  final EventDocument? replacing;

  @override
  State<_UploadDocumentSheet> createState() => _UploadDocumentSheetState();
}

class _UploadDocumentSheetState extends State<_UploadDocumentSheet> {
  final _title = TextEditingController();
  final _note = TextEditingController();
  final _link = TextEditingController();

  PlatformFile? _file;

  /// Resolved once at pick time. `lengthSync` is free when the native picker
  /// already reported a size and falls back to reading the file when it did not.
  int _fileSize = 0;

  bool _useLink = false;
  bool _busy = false;
  String? _error;

  bool get _isReplacement => widget.replacing != null;
  bool get _isApproval => widget.kind == DocumentKind.approval;

  @override
  void initState() {
    super.initState();
    if (_isReplacement) _title.text = widget.replacing!.title;
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _link.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final picked = await FilePicker.pickFile();
    if (picked == null) return;
    final size = picked.lengthSync() ?? await picked.length();
    if (!mounted) return;
    setState(() {
      _file = picked;
      _fileSize = size;
      _useLink = false;
      // Name the document after the file unless somebody has already typed
      // something better.
      if (_title.text.trim().isEmpty) {
        _title.text = picked.name.replaceAll(RegExp(r'\.[^.]+$'), '');
      }
    });
  }

  bool get _valid {
    final hasSource = _useLink ? _link.text.trim().length > 8 : _file != null;
    if (_isReplacement) return hasSource;
    return hasSource && _title.text.trim().length >= 2;
  }

  Future<void> _submit() async {
    final store = AppScope.readStore(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Read lazily, at submit: a picked file stays a handle until it is
      // actually being sent, so browsing for the wrong PDF does not pull 15 MB
      // into memory.
      final bytes = _useLink ? null : await _file!.readAsBytes();
      if (_isReplacement) {
        await store.replaceDocument(
          eventId: widget.eventId,
          documentId: widget.replacing!.id,
          note: _note.text.trim(),
          bytes: bytes,
          filename: _useLink ? null : _file!.name,
          link: _useLink ? _link.text.trim() : null,
        );
      } else {
        await store.uploadEventDocument(
          eventId: widget.eventId,
          kind: widget.kind,
          title: _title.text.trim(),
          note: _note.text.trim(),
          bytes: bytes,
          filename: _useLink ? null : _file!.name,
          link: _useLink ? _link.text.trim() : null,
        );
      }
      if (mounted) Navigator.of(context).pop();
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
                  title: _isReplacement
                      ? 'File a new version'
                      : _isApproval
                          ? 'File an official approval'
                          : 'Add a file',
                  subtitle: _isReplacement
                      ? 'The old version stays on the record.'
                      : _isApproval
                          ? 'Permission letters, venue bookings, faculty sign-off.'
                          : 'Posters, scripts, budgets — anything the team needs.',
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      GwdSpace.xl, 0, GwdSpace.xl, GwdSpace.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_isApproval && !_isReplacement) ...[
                        _ApprovalNotice(),
                        const SizedBox(height: GwdSpace.lg),
                      ],

                      if (!_isReplacement) ...[
                        GwdField(
                          label: 'What is it',
                          controller: _title,
                          hint: _isApproval
                              ? 'Principal’s permission letter'
                              : 'Poster — final',
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: GwdSpace.lg),
                      ],

                      _SourceSwitch(
                        useLink: _useLink,
                        onChanged: (value) => setState(() => _useLink = value),
                      ),
                      const SizedBox(height: GwdSpace.md),

                      if (_useLink)
                        GwdField(
                          label: 'Link',
                          controller: _link,
                          hint: 'https://drive.google.com/…',
                          keyboardType: TextInputType.url,
                          onChanged: (_) => setState(() {}),
                        )
                      else
                        _FileSlot(file: _file, sizeBytes: _fileSize, onTap: _pick),

                      const SizedBox(height: GwdSpace.lg),
                      GwdField(
                        label: _isReplacement ? 'What changed' : 'Note (optional)',
                        controller: _note,
                        maxLines: 2,
                        hint: _isReplacement
                            ? 'Venue moved to Block C'
                            : 'Anything worth knowing about it',
                      ),

                      if (_error != null) ...[
                        const SizedBox(height: GwdSpace.lg),
                        ErrorNote(message: _error!),
                      ],
                      const SizedBox(height: GwdSpace.xl),
                      PrimaryButton(
                        label: _isReplacement ? 'File new version' : 'Add it',
                        icon: Icons.upload_rounded,
                        busy: _busy,
                        onPressed: _valid ? _submit : null,
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

/// Says out loud what filing is and is not.
///
/// The single most damaging confusion in this feature would be somebody
/// believing that uploading the letter means the college has approved it.
class _ApprovalNotice extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(GwdSpace.md),
      decoration: BoxDecoration(
        color: GwdColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(GwdRadius.md),
        border: Border.all(color: GwdColors.warning.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, size: 15, color: GwdColors.warning),
          const SizedBox(width: GwdSpace.sm),
          Expanded(
            child: Text(
              'This goes on the record as awaiting sign-off. The President, '
              'Vice President or Secretary General marks it approved.',
              style:
                  GwdType.footnote.copyWith(color: GwdColors.inkSecondaryOf(context)),
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceSwitch extends StatelessWidget {
  const _SourceSwitch({required this.useLink, required this.onChanged});
  final bool useLink;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _Option(label: 'Attach a file', icon: Icons.attach_file_rounded, selected: !useLink, onTap: () => onChanged(false))),
        const SizedBox(width: GwdSpace.sm),
        Expanded(child: _Option(label: 'Paste a link', icon: Icons.link_rounded, selected: useLink, onTap: () => onChanged(true))),
      ],
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      pressedScale: 0.97,
      haptic: HapticStrength.selection,
      child: AnimatedContainer(
        duration: AppleDuration.fast,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? GwdColors.primaryRed.withValues(alpha: 0.10)
              : GwdColors.sunkenOf(context),
          borderRadius: BorderRadius.circular(GwdRadius.md),
          border: Border.all(
            color: selected
                ? GwdColors.primaryRed.withValues(alpha: 0.35)
                : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 14,
                color: selected
                    ? GwdColors.primaryRed
                    : GwdColors.inkTertiaryOf(context)),
            const SizedBox(width: 6),
            Text(
              label,
              style: GwdType.footnote.copyWith(
                color: selected
                    ? GwdColors.primaryRed
                    : GwdColors.inkSecondaryOf(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileSlot extends StatelessWidget {
  const _FileSlot({required this.file, required this.sizeBytes, required this.onTap});
  final PlatformFile? file;
  final int sizeBytes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final picked = file;
    return PressableScale(
      onTap: onTap,
      pressedScale: 0.98,
      child: Container(
        padding: const EdgeInsets.all(GwdSpace.lg),
        decoration: BoxDecoration(
          color: GwdColors.sunkenOf(context),
          borderRadius: BorderRadius.circular(GwdRadius.md),
          border: Border.all(
            color: picked == null
                ? GwdColors.hairlineOf(context)
                : GwdColors.primaryRed.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Icon(
              picked == null ? Icons.cloud_upload_outlined : Icons.description_rounded,
              size: 20,
              color: picked == null
                  ? GwdColors.inkTertiaryOf(context)
                  : GwdColors.primaryRed,
            ),
            const SizedBox(width: GwdSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    picked?.name ?? 'Choose a file',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GwdType.callout.copyWith(
                      color: picked == null
                          ? GwdColors.inkSecondaryOf(context)
                          : GwdColors.inkOf(context),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    picked == null
                        ? 'PDF, image or document, up to 15 MB'
                        : _size(sizeBytes),
                    style: GwdType.caption.copyWith(
                        fontSize: 9.5,
                        letterSpacing: 0,
                        color: GwdColors.inkTertiaryOf(context)),
                  ),
                ],
              ),
            ),
            if (picked != null)
              Icon(Icons.swap_horiz_rounded,
                  size: 16, color: GwdColors.inkTertiaryOf(context)),
          ],
        ),
      ),
    );
  }

  String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
