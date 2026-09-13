import 'package:flutter/material.dart';

/// Two kinds of document live on an event, and the distinction is the whole
/// point of the feature:
///
///   [file]     — posters, scripts, budgets, photos. Anybody can add one.
///   [approval] — the official paperwork: permission letters, venue bookings,
///                faculty sign-off. Only leadership files one, and only
///                leadership can declare it approved.
enum DocumentKind {
  approval,
  file;

  static DocumentKind fromWire(String? value) =>
      value == 'approval' ? DocumentKind.approval : DocumentKind.file;

  String get wire => name;
}

enum DocumentStatus {
  pending,
  approved,
  rejected,
  replaced;

  static DocumentStatus fromWire(String? value) => switch (value) {
        'approved' => DocumentStatus.approved,
        'rejected' => DocumentStatus.rejected,
        'replaced' => DocumentStatus.replaced,
        _ => DocumentStatus.pending,
      };

  String get wire => name;

  String get label => switch (this) {
        DocumentStatus.pending => 'Awaiting sign-off',
        DocumentStatus.approved => 'Approved',
        DocumentStatus.rejected => 'Sent back',
        DocumentStatus.replaced => 'Replaced',
      };

  Color get tint => switch (this) {
        DocumentStatus.pending => const Color(0xFFD97706),
        DocumentStatus.approved => const Color(0xFF16A34A),
        DocumentStatus.rejected => const Color(0xFFDC2626),
        DocumentStatus.replaced => const Color(0xFF9A9AA4),
      };

  IconData get icon => switch (this) {
        DocumentStatus.pending => Icons.hourglass_empty_rounded,
        DocumentStatus.approved => Icons.verified_rounded,
        DocumentStatus.rejected => Icons.undo_rounded,
        DocumentStatus.replaced => Icons.history_rounded,
      };
}

DateTime? _date(dynamic value) =>
    value == null ? null : DateTime.tryParse(value.toString())?.toLocal();

/// One revision. Kept forever — replacing a permission letter must never make
/// the previous one unreadable.
class DocumentVersion {
  const DocumentVersion({
    required this.version,
    required this.filename,
    required this.uploadedAt,
    required this.uploadedByName,
    required this.superseded,
    this.link,
    this.note = '',
  });

  final int version;
  final String filename;
  final DateTime uploadedAt;
  final String uploadedByName;
  final bool superseded;
  final String? link;
  final String note;

  factory DocumentVersion.fromJson(Map<String, dynamic> json) => DocumentVersion(
        version: (json['version'] as num?)?.toInt() ?? 1,
        filename: json['filename'] as String? ?? 'file',
        uploadedAt: _date(json['uploadedAt']) ?? DateTime.now(),
        uploadedByName: json['uploadedByName'] as String? ?? 'Member',
        superseded: json['superseded'] == true,
        link: json['link'] as String?,
        note: json['note'] as String? ?? '',
      );
}

class EventDocument {
  const EventDocument({
    required this.id,
    required this.eventId,
    required this.kind,
    required this.title,
    required this.status,
    required this.createdByName,
    required this.createdAt,
    required this.version,
    required this.history,
    this.note = '',
    this.decidedByName,
    this.decidedAt,
    this.decisionNote = '',
    this.filename,
    this.sizeBytes = 0,
    this.mimeType = '',
    this.link,
  });

  final String id;
  final String eventId;
  final DocumentKind kind;
  final String title;
  final String note;
  final DocumentStatus status;
  final String createdByName;
  final DateTime createdAt;
  final String? decidedByName;
  final DateTime? decidedAt;
  final String decisionNote;

  final int version;
  final List<DocumentVersion> history;

  final String? filename;
  final int sizeBytes;
  final String mimeType;

  /// Set when the document is a link to somewhere else rather than an upload.
  /// Clubs keep half their paperwork on Drive; refusing to record that just
  /// means it lives in a WhatsApp thread instead.
  final String? link;

  factory EventDocument.fromJson(Map<String, dynamic> json) {
    final current = (json['current'] as Map?)?.cast<String, dynamic>();
    return EventDocument(
      id: json['id'] as String,
      eventId: json['eventId'] as String? ?? '',
      kind: DocumentKind.fromWire(json['kind'] as String?),
      title: json['title'] as String? ?? 'Document',
      note: json['note'] as String? ?? '',
      status: DocumentStatus.fromWire(json['status'] as String?),
      createdByName: json['createdByName'] as String? ?? 'Member',
      createdAt: _date(json['createdAt']) ?? DateTime.now(),
      decidedByName: json['decidedByName'] as String?,
      decidedAt: _date(json['decidedAt']),
      decisionNote: json['decisionNote'] as String? ?? '',
      version: (json['version'] as num?)?.toInt() ?? 1,
      history: ((json['history'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => DocumentVersion.fromJson(e.cast<String, dynamic>()))
          .toList(growable: false),
      filename: current?['filename'] as String?,
      sizeBytes: (current?['size'] as num?)?.toInt() ?? 0,
      mimeType: current?['mimeType'] as String? ?? '',
      link: current?['link'] as String?,
    );
  }

  bool get isLink => link != null && link!.isNotEmpty;

  String get sizeLabel {
    if (isLink) return 'Link';
    if (sizeBytes <= 0) return '';
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).round()} KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  IconData get icon {
    if (isLink) return Icons.link_rounded;
    final name = (filename ?? '').toLowerCase();
    if (name.endsWith('.pdf')) return Icons.picture_as_pdf_outlined;
    if (mimeType.startsWith('image/')) return Icons.image_outlined;
    if (name.endsWith('.doc') || name.endsWith('.docx')) return Icons.description_outlined;
    if (name.endsWith('.xls') || name.endsWith('.xlsx') || name.endsWith('.csv')) {
      return Icons.table_chart_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }
}

/// The document board for one event, plus what this viewer is allowed to do
/// with it. The capability flags come from the server — they hide controls that
/// would be refused, they never grant anything.
class EventDocuments {
  const EventDocuments({
    required this.approvals,
    required this.files,
    required this.canUploadFile,
    required this.canUploadApproval,
    required this.canDecide,
  });

  final List<EventDocument> approvals;
  final List<EventDocument> files;
  final bool canUploadFile;
  final bool canUploadApproval;
  final bool canDecide;

  static List<EventDocument> _parse(dynamic raw) => (raw as List? ?? const [])
      .whereType<Map>()
      .map((e) => EventDocument.fromJson(e.cast<String, dynamic>()))
      .toList(growable: false);

  factory EventDocuments.fromJson(Map<String, dynamic> json) => EventDocuments(
        approvals: _parse(json['approvals']),
        files: _parse(json['files']),
        canUploadFile: json['canUploadFile'] == true,
        canUploadApproval: json['canUploadApproval'] == true,
        canDecide: json['canDecide'] == true,
      );

  static const empty = EventDocuments(
    approvals: [],
    files: [],
    canUploadFile: false,
    canUploadApproval: false,
    canDecide: false,
  );

  int get pendingApprovals =>
      approvals.where((d) => d.status == DocumentStatus.pending).length;
}
