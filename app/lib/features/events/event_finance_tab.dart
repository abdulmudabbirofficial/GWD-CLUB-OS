import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../../app/app_scope.dart';
import '../../app/responsive.dart';
import '../../app/theme/apple_motion.dart';
import '../../app/theme/gwd_theme.dart';
import '../../app/widgets/common.dart';
import '../../core/api/api_client.dart';
import '../../core/models/event_bill.dart';
import 'file_bill_sheet.dart';

/// What the event cost, and who is still owed money.
///
/// Bookkeeping, not banking. Nothing on this screen moves money and no bank
/// details are stored anywhere — a bill records a spend, carries a photo of the
/// receipt, gets approved, and is marked repaid once the club has actually
/// settled up by whatever means it already uses.
///
/// The separation worth having: whoever files a bill is not the person who
/// approves it. Approving your own expense is the oldest hole in any petty-cash
/// system, so the President cannot wave through their own and a Director does
/// it instead.
class EventFinanceTab extends StatefulWidget {
  const EventFinanceTab({super.key, required this.eventId});
  final String eventId;

  @override
  State<EventFinanceTab> createState() => _EventFinanceTabState();
}

class _EventFinanceTabState extends State<EventFinanceTab> {
  bool _forbidden = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      await AppScope.readStore(context).loadEventFinance(widget.eventId);
    } on ApiException catch (e) {
      if (mounted && e.isForbidden) setState(() => _forbidden = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.storeOf(context);
    final finance = store.financeFor(widget.eventId);
    final gutter = Layout.of(context).gutter;

    if (_forbidden) {
      return const EmptyState(
        icon: Icons.lock_outline_rounded,
        title: 'Not visible to you',
        message:
            'What an event costs is visible to department Leads and club '
            'leadership. If you paid for something, ask your Lead to file it.',
      );
    }

    if (finance == null) {
      return const Padding(
        padding: EdgeInsets.all(GwdSpace.xl),
        child: SkeletonList(count: 3, height: 84),
      );
    }

    var step = 0;
    int next() => step++;

    final pending = finance.bills.where((b) => b.status == BillStatus.pending).toList();
    final owed = finance.bills.where((b) => b.status == BillStatus.approved).toList();
    final settled = finance.bills
        .where((b) => b.status == BillStatus.paid || b.status == BillStatus.rejected)
        .toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: finance.canAdd
          ? FloatingActionButton.small(
              backgroundColor: GwdColors.primaryRed,
              foregroundColor: Colors.white,
              onPressed: () => showFileBillSheet(
                context,
                eventId: widget.eventId,
                categories: finance.categories,
              ),
              child: const Icon(Icons.add_rounded),
            )
          : null,
      body: RefreshIndicator(
        color: GwdColors.primaryRed,
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.fromLTRB(gutter, GwdSpace.lg, gutter, GwdSpace.xxxl + 40),
          children: [
            AppleStaggerItem(index: next(), child: _Summary(finance: finance)),

            if (pending.isNotEmpty) ...[
              const SizedBox(height: GwdSpace.xl),
              AppleStaggerItem(
                index: next(),
                child: SectionHeader(
                  title: 'Waiting on approval',
                  subtitle: finance.canDecide
                      ? 'Yours to decide'
                      : 'With the President and Directors',
                ),
              ),
              for (final bill in pending)
                AppleStaggerItem(
                  index: next(),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: GwdSpace.sm),
                    child: _BillCard(
                        eventId: widget.eventId, bill: bill, finance: finance),
                  ),
                ),
            ],

            if (owed.isNotEmpty) ...[
              const SizedBox(height: GwdSpace.xl),
              AppleStaggerItem(
                index: next(),
                child: const SectionHeader(
                  title: 'Still to repay',
                  subtitle: 'Approved, but the money has not gone back yet',
                ),
              ),
              for (final bill in owed)
                AppleStaggerItem(
                  index: next(),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: GwdSpace.sm),
                    child: _BillCard(
                        eventId: widget.eventId, bill: bill, finance: finance),
                  ),
                ),
            ],

            if (settled.isNotEmpty) ...[
              const SizedBox(height: GwdSpace.xl),
              AppleStaggerItem(
                index: next(),
                child: const SectionHeader(title: 'Closed'),
              ),
              for (final bill in settled)
                AppleStaggerItem(
                  index: next(),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: GwdSpace.sm),
                    child: _BillCard(
                        eventId: widget.eventId, bill: bill, finance: finance),
                  ),
                ),
            ],

            if (finance.bills.isEmpty)
              AppleStaggerItem(
                index: next(),
                child: EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'Nothing spent yet',
                  message: finance.canAdd
                      ? 'When somebody pays for something out of pocket, file it '
                          'here with the receipt so they get it back.'
                      : 'Expenses filed against this event will show up here.',
                  action: finance.canAdd
                      ? SecondaryButton(
                          label: 'File an expense',
                          icon: Icons.add_rounded,
                          onPressed: () => showFileBillSheet(
                            context,
                            eventId: widget.eventId,
                            categories: finance.categories,
                          ),
                        )
                      : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Two numbers, because two numbers are what anybody actually asks: what did
/// this cost, and who is still out of pocket.
class _Summary extends StatelessWidget {
  const _Summary({required this.finance});
  final EventFinance finance;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      emphasis: finance.owed > 0 ? SurfaceEmphasis.live : SurfaceEmphasis.quiet,
      accent: GwdColors.warning,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('SPENT',
                        style: GwdType.eyebrow
                            .copyWith(color: GwdColors.inkTertiaryOf(context))),
                    const SizedBox(height: 3),
                    Text(formatRupees(finance.spent),
                        style: GwdType.title1.merge(GwdType.numeric).copyWith(
                            color: GwdColors.inkOf(context))),
                  ],
                ),
              ),
              Container(
                width: 1,
                height: 44,
                color: GwdColors.hairlineOf(context),
              ),
              const SizedBox(width: GwdSpace.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('STILL OWED',
                        style: GwdType.eyebrow.copyWith(
                            color: finance.owed > 0
                                ? GwdColors.warning
                                : GwdColors.inkTertiaryOf(context))),
                    const SizedBox(height: 3),
                    Text(formatRupees(finance.owed),
                        style: GwdType.title1.merge(GwdType.numeric).copyWith(
                          color: finance.owed > 0
                              ? GwdColors.warning
                              : GwdColors.inkOf(context),
                        )),
                  ],
                ),
              ),
            ],
          ),
          if (finance.awaitingDecision > 0) ...[
            const SizedBox(height: GwdSpace.md),
            GwdChip(
              label: finance.awaitingDecision == 1
                  ? '1 waiting on approval'
                  : '${finance.awaitingDecision} waiting on approval',
              color: GwdColors.warning,
              icon: Icons.hourglass_empty_rounded,
              dense: true,
            ),
          ],
          const SizedBox(height: GwdSpace.md),
          Text(
            'A record of money already spent. Repayment happens however the club '
            'normally pays people — it is just noted here.',
            style: GwdType.caption.copyWith(
                fontSize: 9.5,
                letterSpacing: 0,
                color: GwdColors.inkTertiaryOf(context)),
          ),
        ],
      ),
    );
  }
}

class _BillCard extends StatelessWidget {
  const _BillCard({
    required this.eventId,
    required this.bill,
    required this.finance,
  });

  final String eventId;
  final EventBill bill;
  final EventFinance finance;

  @override
  Widget build(BuildContext context) {
    final status = bill.status;
    final canDecide = finance.canDecide && status == BillStatus.pending;
    final canSettle = finance.canSettle && status == BillStatus.approved;

    return SurfaceCard(
      padding: const EdgeInsets.all(GwdSpace.lg),
      borderColor: status == BillStatus.pending
          ? GwdColors.warning.withValues(alpha: 0.3)
          : null,
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
                child: Icon(bill.categoryIcon, size: 18, color: status.tint),
              ),
              const SizedBox(width: GwdSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(bill.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GwdType.headline
                            .copyWith(color: GwdColors.inkOf(context))),
                    const SizedBox(height: 2),
                    Text(
                      [bill.category, bill.dateLabel].join('  ·  '),
                      style: GwdType.caption.copyWith(
                          fontSize: 9.5,
                          letterSpacing: 0,
                          color: GwdColors.inkTertiaryOf(context)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: GwdSpace.sm),
              Text(bill.amountLabel,
                  style: GwdType.title3.merge(GwdType.numeric).copyWith(
                      color: GwdColors.inkOf(context))),
            ],
          ),

          const SizedBox(height: GwdSpace.md),
          Row(
            children: [
              GwdChip(
                label: status.label,
                color: status.tint,
                icon: status.icon,
                dense: true,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text('${bill.paidByName} paid',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GwdType.footnote
                        .copyWith(color: GwdColors.inkSecondaryOf(context))),
              ),
            ],
          ),

          if (bill.note.isNotEmpty) ...[
            const SizedBox(height: GwdSpace.sm),
            Text(bill.note,
                style: GwdType.footnote
                    .copyWith(color: GwdColors.inkTertiaryOf(context))),
          ],

          if (bill.decisionNote.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('“${bill.decisionNote}” — ${bill.decidedByName ?? 'leadership'}',
                style: GwdType.footnote
                    .copyWith(color: GwdColors.inkTertiaryOf(context))),
          ],

          if (status == BillStatus.paid && bill.settlementRef.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Repaid — ${bill.settlementRef}',
                style: GwdType.footnote.copyWith(color: GwdColors.success)),
          ],

          if (bill.hasReceipt) ...[
            const SizedBox(height: GwdSpace.md),
            PressableScale(
              onTap: () => _openReceipt(context, bill),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.receipt_outlined,
                      size: 14, color: GwdColors.inkSecondaryOf(context)),
                  const SizedBox(width: 5),
                  Text('View receipt',
                      style: GwdType.footnote
                          .copyWith(color: GwdColors.inkSecondaryOf(context))),
                ],
              ),
            ),
          ] else if (status == BillStatus.pending) ...[
            const SizedBox(height: GwdSpace.sm),
            Row(
              children: [
                const Icon(Icons.info_outline_rounded,
                    size: 13, color: GwdColors.warning),
                const SizedBox(width: 5),
                Text('No receipt attached',
                    style: GwdType.footnote.copyWith(color: GwdColors.warning)),
              ],
            ),
          ],

          if (canDecide) ...[
            const SizedBox(height: GwdSpace.lg),
            Row(
              children: [
                Expanded(
                  child: _Action(
                    label: 'Approve',
                    icon: Icons.check_rounded,
                    tint: GwdColors.success,
                    onTap: () => _decide(context, eventId, bill, true),
                  ),
                ),
                const SizedBox(width: GwdSpace.sm),
                Expanded(
                  child: _Action(
                    label: 'Decline',
                    icon: Icons.close_rounded,
                    tint: GwdColors.critical,
                    onTap: () => _decide(context, eventId, bill, false),
                  ),
                ),
              ],
            ),
          ],

          if (canSettle) ...[
            const SizedBox(height: GwdSpace.lg),
            _Action(
              label: 'Mark repaid',
              icon: Icons.done_all_rounded,
              tint: GwdColors.success,
              expand: true,
              onTap: () => _settle(context, eventId, bill),
            ),
          ],
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.label,
    required this.icon,
    required this.tint,
    required this.onTap,
    this.expand = false,
  });

  final String label;
  final IconData icon;
  final Color tint;
  final VoidCallback onTap;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final button = PressableScale(
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
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

Future<void> _decide(
  BuildContext context,
  String eventId,
  EventBill bill,
  bool approved,
) async {
  final store = AppScope.readStore(context);
  final messenger = ScaffoldMessenger.of(context);
  final controller = TextEditingController();

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: GwdColors.surfaceOf(dialogContext),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GwdRadius.xl)),
      title: Text(approved ? 'Approve this expense?' : 'Decline it?',
          style: GwdType.title3.copyWith(color: GwdColors.inkOf(dialogContext))),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            approved
                ? 'This records that you, by name, approved ${bill.amountLabel} '
                    'for "${bill.title}". ${bill.paidByName} can then be repaid.'
                : 'Say why, so whoever filed it knows what to do next.',
            style: GwdType.callout
                .copyWith(color: GwdColors.inkSecondaryOf(dialogContext)),
          ),
          const SizedBox(height: GwdSpace.lg),
          GwdField(
            label: approved ? 'Note (optional)' : 'Reason',
            controller: controller,
            maxLines: 2,
            autofocus: !approved,
          ),
        ],
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
          child: Text(
            approved ? 'Approve' : 'Decline',
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
      await store.decideBill(
        eventId: eventId,
        billId: bill.id,
        approved: approved,
        note: controller.text.trim(),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
  controller.dispose();
}

Future<void> _settle(BuildContext context, String eventId, EventBill bill) async {
  final store = AppScope.readStore(context);
  final messenger = ScaffoldMessenger.of(context);
  final controller = TextEditingController();

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: GwdColors.surfaceOf(dialogContext),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GwdRadius.xl)),
      title: Text('Already repaid?',
          style: GwdType.title3.copyWith(color: GwdColors.inkOf(dialogContext))),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This does not send anything — pay ${bill.paidByName} the '
            '${bill.amountLabel} however the club normally does, then note it '
            'here so the list stops showing a debt that no longer exists.',
            style: GwdType.callout
                .copyWith(color: GwdColors.inkSecondaryOf(dialogContext)),
          ),
          const SizedBox(height: GwdSpace.lg),
          GwdField(
            label: 'Reference (optional)',
            controller: controller,
            hint: 'UPI 12 Mar, cash, bank transfer…',
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text('Not yet',
              style: GwdType.callout
                  .copyWith(color: GwdColors.inkSecondaryOf(dialogContext))),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text('Mark repaid',
              style: GwdType.callout.copyWith(
                  color: GwdColors.success, fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );

  if (confirmed == true) {
    try {
      await store.settleBill(
        eventId: eventId,
        billId: bill.id,
        reference: controller.text.trim(),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
  controller.dispose();
}

Future<void> _openReceipt(BuildContext context, EventBill bill) async {
  final store = AppScope.readStore(context);
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(const SnackBar(content: Text('Opening receipt…')));
  try {
    final path = await store.downloadReceipt(
      bill.id,
      filename: bill.receiptName ?? 'receipt',
    );
    messenger.hideCurrentSnackBar();
    final result = await OpenFilex.open(path);
    if (result.type != ResultType.done) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Nothing on this device can open that kind of file.'),
      ));
    }
  } on ApiException catch (e) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  }
}
