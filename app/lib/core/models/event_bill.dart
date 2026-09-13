import 'package:flutter/material.dart';

/// Event finance.
///
/// Bookkeeping, not banking: this records what an event cost, carries a photo
/// of the receipt, routes it for approval, and notes when the club actually
/// paid the person back. It moves no money and stores no bank details.
enum BillStatus {
  pending,
  approved,
  rejected,
  paid;

  static BillStatus fromWire(String? value) => switch (value) {
        'approved' => BillStatus.approved,
        'rejected' => BillStatus.rejected,
        'paid' => BillStatus.paid,
        _ => BillStatus.pending,
      };

  String get wire => name;

  String get label => switch (this) {
        BillStatus.pending => 'Waiting on approval',
        BillStatus.approved => 'Approved — not yet repaid',
        BillStatus.rejected => 'Not approved',
        BillStatus.paid => 'Repaid',
      };

  String get shortLabel => switch (this) {
        BillStatus.pending => 'Pending',
        BillStatus.approved => 'To repay',
        BillStatus.rejected => 'Declined',
        BillStatus.paid => 'Repaid',
      };

  Color get tint => switch (this) {
        BillStatus.pending => const Color(0xFFD97706),
        BillStatus.approved => const Color(0xFF2563EB),
        BillStatus.rejected => const Color(0xFFDC2626),
        BillStatus.paid => const Color(0xFF16A34A),
      };

  IconData get icon => switch (this) {
        BillStatus.pending => Icons.hourglass_empty_rounded,
        BillStatus.approved => Icons.check_circle_outline_rounded,
        BillStatus.rejected => Icons.block_rounded,
        BillStatus.paid => Icons.verified_rounded,
      };
}

DateTime? _date(dynamic value) =>
    value == null ? null : DateTime.tryParse(value.toString())?.toLocal();

class EventBill {
  const EventBill({
    required this.id,
    required this.eventId,
    required this.title,
    required this.amount,
    required this.category,
    required this.status,
    required this.paidByName,
    required this.createdByName,
    required this.createdAt,
    required this.hasReceipt,
    this.note = '',
    this.spentOn,
    this.departmentName,
    this.decidedByName,
    this.decidedAt,
    this.decisionNote = '',
    this.settledByName,
    this.settledAt,
    this.settlementRef = '',
    this.receiptName,
  });

  final String id;
  final String eventId;
  final String title;
  final String note;

  /// In rupees. The server keeps paise so no total ever drifts by a rounding
  /// error; this is the already-divided figure for display.
  final double amount;

  final String category;
  final BillStatus status;
  final DateTime? spentOn;

  /// Who is out of pocket — often not the person who filed it.
  final String paidByName;

  final String? departmentName;
  final String createdByName;
  final DateTime createdAt;
  final String? decidedByName;
  final DateTime? decidedAt;
  final String decisionNote;
  final String? settledByName;
  final DateTime? settledAt;

  /// How the repayment was made — "UPI ref 88231". Never an account number.
  final String settlementRef;

  final bool hasReceipt;
  final String? receiptName;

  factory EventBill.fromJson(Map<String, dynamic> json) => EventBill(
        id: json['id'] as String,
        eventId: json['eventId'] as String? ?? '',
        title: json['title'] as String? ?? 'Expense',
        note: json['note'] as String? ?? '',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        category: json['category'] as String? ?? 'Other',
        status: BillStatus.fromWire(json['status'] as String?),
        spentOn: _date(json['spentOn']),
        paidByName: json['paidByName'] as String? ?? 'Member',
        departmentName: json['departmentName'] as String?,
        createdByName: json['createdByName'] as String? ?? 'Member',
        createdAt: _date(json['createdAt']) ?? DateTime.now(),
        decidedByName: json['decidedByName'] as String?,
        decidedAt: _date(json['decidedAt']),
        decisionNote: json['decisionNote'] as String? ?? '',
        settledByName: json['settledByName'] as String?,
        settledAt: _date(json['settledAt']),
        settlementRef: json['settlementRef'] as String? ?? '',
        hasReceipt: json['hasReceipt'] == true,
        receiptName: json['receiptName'] as String?,
      );

  /// Indian grouping (1,45,000) rather than 145,000 — this is a college club in
  /// India and the other format reads wrong to everyone using it.
  String get amountLabel => formatRupees(amount);

  String get dateLabel {
    final when = spentOn ?? createdAt;
    return '${when.day}/${when.month}/${when.year}';
  }

  IconData get categoryIcon => switch (category) {
        'Printing' => Icons.print_outlined,
        'Venue' => Icons.meeting_room_outlined,
        'Refreshments' => Icons.local_cafe_outlined,
        'Travel' => Icons.directions_bus_outlined,
        'Props & materials' => Icons.handyman_outlined,
        'Equipment' => Icons.speaker_outlined,
        'Guest hospitality' => Icons.card_giftcard_outlined,
        _ => Icons.receipt_long_outlined,
      };
}

/// ₹1,45,000.50 — lakh/crore grouping.
String formatRupees(double amount) {
  final negative = amount < 0;
  final fixed = amount.abs().toStringAsFixed(2);
  final parts = fixed.split('.');
  final whole = parts[0];
  final decimals = parts[1] == '00' ? '' : '.${parts[1]}';

  String grouped;
  if (whole.length <= 3) {
    grouped = whole;
  } else {
    final last3 = whole.substring(whole.length - 3);
    var rest = whole.substring(0, whole.length - 3);
    final chunks = <String>[];
    while (rest.length > 2) {
      chunks.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) chunks.insert(0, rest);
    grouped = '${chunks.join(',')},$last3';
  }
  return '${negative ? '-' : ''}₹$grouped$decimals';
}

/// One event's money, plus what this viewer may do with it.
class EventFinance {
  const EventFinance({
    required this.bills,
    required this.spent,
    required this.owed,
    required this.pending,
    required this.paid,
    required this.categories,
    required this.canAdd,
    required this.canDecide,
    required this.canSettle,
  });

  final List<EventBill> bills;

  /// Everything filed, whatever happened to it — the honest "what did this
  /// event cost" number.
  final double spent;

  /// Approved but not yet handed back: what the club owes its own members.
  final double owed;

  final double pending;
  final double paid;
  final List<String> categories;

  final bool canAdd;
  final bool canDecide;
  final bool canSettle;

  factory EventFinance.fromJson(Map<String, dynamic> json) {
    final totals = (json['totals'] as Map?)?.cast<String, dynamic>() ?? const {};
    double amount(String key) => (totals[key] as num?)?.toDouble() ?? 0;
    return EventFinance(
      bills: ((json['bills'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => EventBill.fromJson(e.cast<String, dynamic>()))
          .toList(growable: false),
      spent: amount('spent'),
      owed: amount('owed'),
      pending: amount('pending'),
      paid: amount('paid'),
      categories: ((json['categories'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(growable: false),
      canAdd: json['canAdd'] == true,
      canDecide: json['canDecide'] == true,
      canSettle: json['canSettle'] == true,
    );
  }

  int get awaitingDecision =>
      bills.where((b) => b.status == BillStatus.pending).length;
}
