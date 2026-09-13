import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_scope.dart';
import '../../app/theme/apple_motion.dart';
import '../../app/theme/gwd_theme.dart';
import '../../app/widgets/common.dart';
import '../../core/api/api_client.dart';
import '../../core/models/event_bill.dart';

/// File what somebody spent on this event.
///
/// Asks for four things and no more: what it was, how much, who is out of
/// pocket, and a photo of the receipt. It deliberately does **not** ask for
/// bank details — a club app holding members' account numbers is a liability
/// nobody asked for, and the club already knows how it pays people.
Future<void> showFileBillSheet(
  BuildContext context, {
  required String eventId,
  required List<String> categories,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _FileBillSheet(eventId: eventId, categories: categories),
  );
}

class _FileBillSheet extends StatefulWidget {
  const _FileBillSheet({required this.eventId, required this.categories});
  final String eventId;
  final List<String> categories;

  @override
  State<_FileBillSheet> createState() => _FileBillSheetState();
}

class _FileBillSheetState extends State<_FileBillSheet> {
  final _title = TextEditingController();
  final _amount = TextEditingController();
  final _paidBy = TextEditingController();
  final _note = TextEditingController();

  late String _category = widget.categories.isEmpty ? 'Other' : widget.categories.first;
  DateTime _spentOn = DateTime.now();
  PlatformFile? _receipt;
  int _receiptSize = 0;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _paidBy.dispose();
    _note.dispose();
    super.dispose();
  }

  double get _parsedAmount => double.tryParse(_amount.text.trim()) ?? 0;

  bool get _valid => _title.text.trim().length >= 2 && _parsedAmount > 0;

  Future<void> _pickReceipt() async {
    final picked = await FilePicker.pickFile();
    if (picked == null) return;
    final size = picked.lengthSync() ?? await picked.length();
    if (!mounted) return;
    setState(() {
      _receipt = picked;
      _receiptSize = size;
    });
  }

  Future<void> _submit() async {
    final store = AppScope.readStore(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await store.fileBill(
        eventId: widget.eventId,
        title: _title.text.trim(),
        amount: _parsedAmount,
        category: _category,
        note: _note.text.trim(),
        paidByName: _paidBy.text.trim(),
        spentOn: _spentOn,
        receiptBytes: _receipt == null ? null : await _receipt!.readAsBytes(),
        receiptName: _receipt?.name,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(const SnackBar(
        content: Text('Filed. The President and Directors have been told.'),
      ));
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
                const SheetHeader(
                  title: 'What did it cost?',
                  subtitle: 'Money already spent, so the club can pay it back.',
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      GwdSpace.xl, 0, GwdSpace.xl, GwdSpace.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      GwdField(
                        label: 'What the money went on',
                        controller: _title,
                        autofocus: true,
                        hint: 'Poster printing',
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: GwdSpace.lg),

                      Text('HOW MUCH',
                          style: GwdType.eyebrow
                              .copyWith(color: GwdColors.inkTertiaryOf(context))),
                      const SizedBox(height: GwdSpace.xs + 2),
                      TextField(
                        controller: _amount,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                        ],
                        onChanged: (_) => setState(() {}),
                        style: GwdType.title2.merge(GwdType.numeric).copyWith(
                            color: GwdColors.inkOf(context)),
                        decoration: InputDecoration(
                          prefixText: '₹ ',
                          prefixStyle: GwdType.title2.copyWith(
                              color: GwdColors.inkTertiaryOf(context)),
                          hintText: '0',
                          hintStyle: GwdType.title2.copyWith(
                              color: GwdColors.inkTertiaryOf(context)),
                          filled: true,
                          fillColor: GwdColors.sunkenOf(context),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: GwdSpace.lg, vertical: GwdSpace.md),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(GwdRadius.md),
                            borderSide:
                                BorderSide(color: GwdColors.hairlineOf(context)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(GwdRadius.md),
                            borderSide:
                                BorderSide(color: GwdColors.hairlineOf(context)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(GwdRadius.md),
                            borderSide: const BorderSide(
                                color: GwdColors.primaryRed, width: 1.5),
                          ),
                        ),
                      ),
                      if (_parsedAmount > 0) ...[
                        const SizedBox(height: 5),
                        Text(formatRupees(_parsedAmount),
                            style: GwdType.footnote.copyWith(
                                color: GwdColors.inkTertiaryOf(context))),
                      ],
                      const SizedBox(height: GwdSpace.lg),

                      Text('WHAT KIND',
                          style: GwdType.eyebrow
                              .copyWith(color: GwdColors.inkTertiaryOf(context))),
                      const SizedBox(height: GwdSpace.sm),
                      Wrap(
                        spacing: GwdSpace.sm,
                        runSpacing: GwdSpace.sm,
                        children: [
                          for (final category in widget.categories)
                            _Tag(
                              label: category,
                              selected: _category == category,
                              onTap: () => setState(() => _category = category),
                            ),
                        ],
                      ),
                      const SizedBox(height: GwdSpace.lg),

                      Row(
                        children: [
                          Expanded(
                            child: GwdField(
                              label: 'Who paid',
                              controller: _paidBy,
                              hint: 'You, unless you say otherwise',
                            ),
                          ),
                          const SizedBox(width: GwdSpace.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('WHEN',
                                    style: GwdType.eyebrow.copyWith(
                                        color: GwdColors.inkTertiaryOf(context))),
                                const SizedBox(height: GwdSpace.xs + 2),
                                PressableScale(
                                  onTap: () async {
                                    final picked = await showDatePicker(
                                      context: context,
                                      initialDate: _spentOn,
                                      firstDate: DateTime.now()
                                          .subtract(const Duration(days: 365)),
                                      lastDate: DateTime.now(),
                                    );
                                    if (picked != null) {
                                      setState(() => _spentOn = picked);
                                    }
                                  },
                                  child: Container(
                                    height: 48,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: GwdSpace.lg),
                                    alignment: Alignment.centerLeft,
                                    decoration: BoxDecoration(
                                      color: GwdColors.sunkenOf(context),
                                      borderRadius:
                                          BorderRadius.circular(GwdRadius.md),
                                      border: Border.all(
                                          color: GwdColors.hairlineOf(context)),
                                    ),
                                    child: Text(
                                      '${_spentOn.day}/${_spentOn.month}/${_spentOn.year}',
                                      style: GwdType.body.copyWith(
                                          color: GwdColors.inkOf(context)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: GwdSpace.lg),

                      _ReceiptSlot(
                        file: _receipt,
                        sizeBytes: _receiptSize,
                        onTap: _pickReceipt,
                      ),
                      const SizedBox(height: GwdSpace.lg),

                      GwdField(
                        label: 'Note',
                        controller: _note,
                        maxLines: 2,
                        hint: 'A3 colour, 40 copies.',
                      ),

                      if (_error != null) ...[
                        const SizedBox(height: GwdSpace.lg),
                        ErrorNote(message: _error!),
                      ],
                      const SizedBox(height: GwdSpace.xl),
                      PrimaryButton(
                        label: 'File it',
                        icon: Icons.receipt_long_rounded,
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

class _ReceiptSlot extends StatelessWidget {
  const _ReceiptSlot({
    required this.file,
    required this.sizeBytes,
    required this.onTap,
  });

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
                ? GwdColors.warning.withValues(alpha: 0.35)
                : GwdColors.success.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          children: [
            Icon(
              picked == null ? Icons.photo_camera_outlined : Icons.receipt_rounded,
              size: 20,
              color: picked == null ? GwdColors.warning : GwdColors.success,
            ),
            const SizedBox(width: GwdSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    picked?.name ?? 'Attach the receipt',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GwdType.callout.copyWith(
                      color: GwdColors.inkOf(context),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    picked == null
                        // Said plainly: a bill with no proof is a bill somebody
                        // has to take on trust, and that is how these go wrong.
                        ? 'A photo of the bill. Without one this is harder to approve.'
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

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      pressedScale: 0.95,
      haptic: HapticStrength.selection,
      child: AnimatedContainer(
        duration: AppleDuration.fast,
        padding: const EdgeInsets.symmetric(
            horizontal: GwdSpace.md, vertical: GwdSpace.sm),
        decoration: BoxDecoration(
          color: selected ? GwdColors.primaryRed : GwdColors.sunkenOf(context),
          borderRadius: BorderRadius.circular(GwdRadius.sm),
        ),
        child: Text(
          label,
          style: GwdType.footnote.copyWith(
            color: selected ? Colors.white : GwdColors.inkSecondaryOf(context),
          ),
        ),
      ),
    );
  }
}
