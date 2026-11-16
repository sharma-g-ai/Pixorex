/// Delegated review: a BU Admin gives waiting scans to a technician as a batch, and the
/// technician approves or rejects them on the phone (contracts 3.4, 3.5, 3.11, 3.15;
/// screens T 74-76). Names follow the contract's snake_case fields.
library;

/// A batch given to me (contract 3.15 / 3.11 `Batch`).
class ReviewBatch {
  const ReviewBatch({
    required this.batchId,
    required this.batchNo,
    required this.createdByName,
    required this.scanCount,
    required this.decidedCount,
    required this.status,
  });
  final String batchId;
  final String batchNo;
  final String createdByName;
  final int scanCount;
  final int decidedCount;

  /// `active`, `completed` or `taken_back`.
  final String status;

  int get open => scanCount - decidedCount;
  String get progress => '$decidedCount of $scanCount reviewed';

  factory ReviewBatch.fromJson(Map<String, dynamic> j) => ReviewBatch(
        batchId: j['batch_id'] as String,
        batchNo: j['batch_no'] as String,
        createdByName: j['created_by_name'] as String,
        scanCount: j['scan_count'] as int,
        decidedCount: j['decided_count'] as int,
        status: j['status'] as String,
      );
}

/// One scan in a batch (contract 3.11 `Assignment`).
class Assignment {
  const Assignment({required this.scanId, required this.recordNo, required this.status, this.removedReason});
  final String scanId;
  final String recordNo;

  /// `assigned`, `decided` or `removed`.
  final String status;

  /// Set when removed: `taken_back`, `reassigned`, `admin_decided`, `user_removed`.
  final String? removedReason;

  /// Only a scan still assigned to me can be reviewed.
  bool get canOpen => status == 'assigned';

  String get statusText => switch (status) {
        'assigned' => 'To review',
        'decided' => 'Done',
        _ => switch (removedReason) {
            'taken_back' => 'Taken back by the admin',
            'reassigned' => 'Reassigned to someone else',
            'admin_decided' => 'Decided by the admin',
            _ => 'Removed from the batch',
          },
      };

  factory Assignment.fromJson(Map<String, dynamic> j) => Assignment(
        scanId: j['scan_id'] as String,
        recordNo: j['record_no'] as String,
        status: j['status'] as String,
        removedReason: j['removed_reason'] as String?,
      );
}

/// One field as submitted for review (contract 3.4 `ReviewField`). Read only.
class ReviewedField {
  const ReviewedField({
    required this.label,
    required this.verificationState,
    this.aiValue,
    this.confidence,
    this.flagReasons = const [],
    this.technicianValue,
    this.unreadableReason,
    this.note,
  });
  final String label;
  final String? aiValue;
  final double? confidence;
  final List<String> flagReasons;
  final String? technicianValue;

  /// `accepted`, `corrected`, `unreadable` or `left_empty`.
  final String verificationState;
  final String? unreadableReason;
  final String? note;

  /// The technician's verdict, as the reviewer reads it.
  String get verdict => switch (verificationState) {
        'corrected' => 'Corrected',
        'unreadable' => unreadableReason == null ? 'Unreadable' : 'Unreadable · ${unreadableReason!.replaceAll('_', ' ')}',
        'left_empty' => 'Left empty',
        _ => 'Kept as read',
      };

  factory ReviewedField.fromJson(Map<String, dynamic> j) => ReviewedField(
        label: j['label'] as String,
        aiValue: j['ai_value'] as String?,
        confidence: (j['confidence'] as num?)?.toDouble(),
        flagReasons: ((j['flag_reasons'] as List?) ?? const []).map((e) => e.toString()).toList(),
        technicianValue: j['technician_value'] as String?,
        verificationState: j['verification_state'] as String,
        unreadableReason: j['unreadable_reason'] as String?,
        note: j['note'] as String?,
      );
}

/// A scan to approve or reject (contract 3.4 `ScanReview`).
class DelegatedScan {
  const DelegatedScan({
    required this.scanId,
    required this.recordNo,
    required this.equipmentTypeName,
    required this.locationPath,
    required this.capturedByName,
    required this.photoUrls,
    required this.emptyRequiredFields,
    required this.fields,
  });
  final String scanId;
  final String recordNo;
  final String equipmentTypeName;
  final String locationPath;
  final String capturedByName;

  /// Signed, valid 15 minutes (photos come without "url" when storage isn't set up).
  final List<String> photoUrls;
  final List<String> emptyRequiredFields;
  final List<ReviewedField> fields;

  factory DelegatedScan.fromJson(Map<String, dynamic> j) {
    final photos = ((j['photos'] as List?) ?? const []).whereType<Map<String, dynamic>>().toList()
      ..sort((a, b) => ((a['photo_no'] as int?) ?? 0).compareTo((b['photo_no'] as int?) ?? 0));
    final revision = j['current_revision'] as Map<String, dynamic>;
    return DelegatedScan(
      scanId: j['scan_id'] as String,
      recordNo: j['record_no'] as String,
      equipmentTypeName: j['equipment_type_name'] as String,
      locationPath: j['location_path'] as String,
      capturedByName: j['captured_by_name'] as String,
      photoUrls: [for (final p in photos) if (p['url'] is String) p['url'] as String],
      emptyRequiredFields: ((revision['empty_required_fields'] as List?) ?? const []).map((e) => e.toString()).toList(),
      fields: ((j['fields'] as List?) ?? const []).map((e) => ReviewedField.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}

/// The reject categories (contract RejectCategory), with the words on the reject sheet.
const rejectCategories = [
  ('image_unclear', 'Image unclear'),
  ('data_correction_needed', 'Data correction needed'),
  ('wrong_equipment_type', 'Wrong equipment type'),
  ('other', 'Other'),
];

/// Said when the scan is no longer the reviewer's to decide.
const takenBackText = 'This scan is no longer assigned to you. The admin took it back or reassigned it.';

/// What to tell the reviewer for a refused decision or a scan they can no longer open; null
/// when the API's own words should be shown instead.
String? decisionProblemText(String code, int status) => switch ((code, status)) {
      ('own-scan', _) => "You can't review your own scan.",
      ('already-decided', _) => 'Someone already decided this scan.',
      (_, 404) => takenBackText,
      _ => null,
    };
