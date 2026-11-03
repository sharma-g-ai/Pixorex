/// Read-only views of the scan endpoints (docs/mobile-api.md sections 5-6).
/// Names follow the contract's snake_case fields.
library;

/// One field as the AI read it (contract 2.24).
class AiField {
  const AiField({
    required this.fieldKey,
    required this.label,
    required this.dataType,
    required this.isRequired,
    required this.isCritical,
    this.aiValue,
    this.confidence,
    this.flagReasons = const [],
  });
  final String fieldKey;
  final String label;
  final String dataType;
  final bool isRequired;
  final bool isCritical;
  final String? aiValue;
  final double? confidence;

  /// `low_confidence`, `format_failed`, `no_confidence`, `missing_required`, `critical_not_found`.
  final List<String> flagReasons;

  bool get isFlagged => flagReasons.isNotEmpty;

  factory AiField.fromJson(Map<String, dynamic> j) => AiField(
        fieldKey: j['field_key'] as String,
        label: j['label'] as String,
        dataType: j['data_type'] as String,
        isRequired: j['is_required'] as bool,
        isCritical: j['is_critical'] as bool,
        aiValue: j['ai_value'] as String?,
        confidence: (j['confidence'] as num?)?.toDouble(),
        flagReasons: ((j['flag_reasons'] as List?) ?? const []).map((e) => e.toString()).toList(),
      );
}

class AttemptSummary {
  const AttemptSummary({
    required this.attemptNo,
    required this.status,
    this.detectedLabel,
    this.suggestedTypeId,
  });
  final int attemptNo;
  final String status;
  final String? detectedLabel;
  final String? suggestedTypeId;

  factory AttemptSummary.fromJson(Map<String, dynamic> j) => AttemptSummary(
        attemptNo: j['attempt_no'] as int,
        status: j['status'] as String,
        detectedLabel: j['detected_label'] as String?,
        suggestedTypeId: j['suggested_type_id'] as String?,
      );
}

/// Contract 2.24. Two independent statuses (`processing_status`, `review_status`).
class Scan {
  const Scan({
    required this.scanId,
    required this.recordNo,
    required this.buId,
    required this.equipmentTypeId,
    required this.equipmentTypeName,
    required this.locationPath,
    required this.processingStatus,
    required this.reviewStatus,
    required this.attemptsUsed,
    this.locationNodeId,
    this.photoUrls = const [],
    this.latestAttempt,
    this.fields = const [],
  });
  final String scanId;
  final String recordNo;
  final String buId;
  final String equipmentTypeId;
  final String equipmentTypeName;
  final String locationPath;
  final String? locationNodeId;
  final String processingStatus;
  final String reviewStatus;
  final int attemptsUsed;

  /// Signed, valid 15 minutes: fetch the scan again for fresh ones.
  final List<String> photoUrls;
  final AttemptSummary? latestAttempt;
  final List<AiField> fields;

  static const maxAttempts = 3;

  /// Extraction has finished, one way or the other: stop polling.
  bool get isSettled => const {'ready_to_review', 'failed', 'retake_required'}.contains(processingStatus);

  /// The AI read a different label than the chosen type (screen 54).
  bool get hasTypeMismatch =>
      processingStatus == 'ready_to_review' &&
      latestAttempt?.suggestedTypeId != null &&
      latestAttempt!.suggestedTypeId != equipmentTypeId;

  factory Scan.fromJson(Map<String, dynamic> j) {
    final photos = ((j['photos'] as List?) ?? const []).cast<Map<String, dynamic>>().toList()
      ..sort((a, b) => (a['photo_no'] as int).compareTo(b['photo_no'] as int));
    final attempt = j['latest_attempt'] as Map<String, dynamic>?;
    return Scan(
      scanId: j['scan_id'] as String,
      recordNo: j['record_no'] as String,
      buId: j['bu_id'] as String,
      equipmentTypeId: j['equipment_type_id'] as String,
      equipmentTypeName: j['equipment_type_name'] as String,
      locationPath: j['location_path'] as String,
      locationNodeId: j['location_node_id'] as String?,
      processingStatus: j['processing_status'] as String,
      reviewStatus: j['review_status'] as String,
      attemptsUsed: j['attempts_used'] as int,
      photoUrls: photos.map((p) => p['view_url'] as String).toList(),
      latestAttempt: attempt == null ? null : AttemptSummary.fromJson(attempt),
      fields: ((j['fields'] as List?) ?? const []).map((e) => AiField.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}

/// A row of My Scans (contract 3.1).
class MyScan {
  const MyScan({
    required this.scanId,
    required this.recordNo,
    required this.equipmentTypeName,
    required this.locationPath,
    required this.processingStatus,
    required this.reviewStatus,
    required this.attemptsUsed,
    required this.updatedAt,
    this.rejectCategory,
  });
  final String scanId;
  final String recordNo;
  final String equipmentTypeName;
  final String locationPath;
  final String processingStatus;
  final String reviewStatus;
  final int attemptsUsed;
  final DateTime updatedAt;
  final String? rejectCategory;

  /// Last level of the path, e.g. "Bin 07" (the API joins levels with " › ").
  String get place => locationPath.split(' › ').last;

  factory MyScan.fromJson(Map<String, dynamic> j) => MyScan(
        scanId: j['scan_id'] as String,
        recordNo: j['record_no'] as String,
        equipmentTypeName: j['equipment_type_name'] as String,
        locationPath: j['location_path'] as String,
        processingStatus: j['processing_status'] as String,
        reviewStatus: j['review_status'] as String,
        attemptsUsed: j['attempts_used'] as int,
        updatedAt: DateTime.parse(j['updated_at'] as String),
        rejectCategory: j['reject_category'] as String?,
      );
}

/// One page of a cursor-paged list (`page.next_cursor` is null on the last page).
class Page<T> {
  const Page(this.items, this.nextCursor);
  final List<T> items;
  final String? nextCursor;

  factory Page.fromJson(Map<String, dynamic> j, T Function(Map<String, dynamic>) item) => Page(
        (j['items'] as List).map((e) => item(e as Map<String, dynamic>)).toList(),
        (j['page'] as Map<String, dynamic>?)?['next_cursor'] as String?,
      );
}
