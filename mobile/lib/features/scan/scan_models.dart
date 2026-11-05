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
    this.submitted,
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

  /// Only on a rejected scan: what the technician sent for this field (design 69 "Was").
  final SubmittedField? submitted;

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
        submitted: j['submitted'] == null ? null : SubmittedField.fromJson(j['submitted'] as Map<String, dynamic>),
      );
}

/// The technician's answer for one field in the revision the reviewer rejected.
class SubmittedField {
  const SubmittedField({required this.verificationState, this.value, this.unreadableReason, this.note});
  final String verificationState;
  final String? value;
  final String? unreadableReason;
  final String? note;

  factory SubmittedField.fromJson(Map<String, dynamic> j) => SubmittedField(
        verificationState: j['verification_state'] as String,
        value: j['value'] as String?,
        unreadableReason: j['unreadable_reason'] as String?,
        note: j['note'] as String?,
      );
}

/// Why the reviewer sent a scan back (design 68-69).
class Rejection {
  const Rejection({required this.category, required this.reviewerName, required this.decidedAt, this.note});
  final String category;
  final String? note;
  final String reviewerName;
  final DateTime decidedAt;

  /// The reviewer's fixed categories, as on the reject sheet (design 75).
  String get categoryLabel => switch (category) {
        'image_unclear' => 'Image unclear',
        'data_correction_needed' => 'Data correction needed',
        'wrong_equipment_type' => 'Wrong equipment type',
        _ => 'Other',
      };

  factory Rejection.fromJson(Map<String, dynamic> j) => Rejection(
        category: j['category'] as String,
        note: j['note'] as String?,
        reviewerName: j['reviewer_name'] as String,
        decidedAt: DateTime.parse(j['decided_at'] as String),
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
    this.rejection,
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

  /// Set while the scan is rejected.
  final Rejection? rejection;

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
      rejection: j['rejection'] == null ? null : Rejection.fromJson(j['rejection'] as Map<String, dynamic>),
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
    this.resubmitted = false,
    this.retakeOfScanId,
    this.reviewerName,
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

  /// A rejected scan fixed and sent back to the reviewer (design 70).
  final bool resubmitted;

  /// Set on a scan that replaces another one (design 73).
  final String? retakeOfScanId;

  /// Who rejected it, who a fix goes back to, or who rejected the scan a retake replaces.
  final String? reviewerName;

  String get place => shortPlace(locationPath);

  /// Opens Scan details: nothing for the technician to fill in, so the screen shows where it
  /// is and what happened.
  bool get opensDetails =>
      const {'waiting_for_approval', 'approved', 'closed', 'discarded'}.contains(reviewStatus) ||
      (reviewStatus == 'draft' && const {'failed', 'retake_required'}.contains(processingStatus));

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
        resubmitted: j['resubmitted'] as bool? ?? false,
        retakeOfScanId: j['retake_of_scan_id'] as String?,
        reviewerName: j['reviewer_name'] as String?,
      );
}

/// Where a scan is, short enough for a list row: "Bin 07", or "Bin 07 · B" when the path
/// goes below the bin (design 41: "Bin 07 · Sub-bin B"). The API joins levels with " › ".
String shortPlace(String locationPath) {
  final parts = locationPath.split(' › ');
  return parts.length >= 4 ? parts.sublist(parts.length - 2).join(' · ') : parts.last;
}

/// A scan ID as people read it: 1000000040 becomes "100 000 004 0" (9-digit counter, then the
/// check digit). Anything else is shown as it is.
String formatScanId(String recordNo) {
  final m = RegExp(r'^([0-9]{3})([0-9]{3})([0-9]{3})([0-9])$').firstMatch(recordNo);
  return m == null ? recordNo : '${m[1]} ${m[2]} ${m[3]} ${m[4]}';
}

/// One event in a scan's story (contract 3.16). The API words the title; "you" is the caller.
class HistoryEvent {
  const HistoryEvent({required this.kind, required this.at, required this.title, this.detail});
  final String kind;
  final DateTime at;
  final String title;
  final String? detail;

  factory HistoryEvent.fromJson(Map<String, dynamic> j) => HistoryEvent(
        kind: j['kind'] as String,
        at: DateTime.parse(j['at'] as String),
        title: j['title'] as String,
        detail: j['detail'] as String?,
      );
}

/// What happened to a scan and where it is now (contract 3.16).
class ScanHistory {
  const ScanHistory({required this.recordNo, required this.events, required this.nowText, this.since, required this.needsTechnician});
  final String recordNo;
  final List<HistoryEvent> events;
  final String nowText;
  final DateTime? since;
  final bool needsTechnician;

  factory ScanHistory.fromJson(Map<String, dynamic> j) {
    final now = j['now'] as Map<String, dynamic>;
    return ScanHistory(
      recordNo: j['record_no'] as String,
      events: (j['events'] as List).map((e) => HistoryEvent.fromJson(e as Map<String, dynamic>)).toList(),
      nowText: now['text'] as String,
      since: now['since'] == null ? null : DateTime.parse(now['since'] as String),
      needsTechnician: now['needs_technician'] as bool,
    );
  }
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
