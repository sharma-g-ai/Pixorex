/// Core domain types for PPG delivery-note offline scanner.
library;

enum ScanSessionStatus { draft, reviewing, submittedLocal }

enum PageOcrStatus { pending, running, succeeded, failed }

enum OccurrenceRole { quantityBearing, setHeaderNoPrintedQuantity, unresolved }

enum PhysicalQuantityOrigin {
  defaultedFromDocument,
  userEntered,
  operatorConfirmed,
}

enum PhysicalCountState { notChecked, counting, verified, recheck }

enum CaptureMode { camera, developerImageImport, illustrativeFixture }

class ScanSession {
  ScanSession({
    required this.id,
    required this.status,
    required this.formRevision,
    required this.createdAt,
    required this.updatedAt,
    this.deliveryNoteNumber,
    this.declaredPageCount,
    this.operatorEmail,
    this.mode = CaptureMode.camera,
    this.reviewConfirmedRevision,
    this.vesselId = 'vessel-1',
  });

  final String id;

  /// The vessel this delivery note stocks. Fixed when the note is started.
  final String vesselId;
  ScanSessionStatus status;
  String? deliveryNoteNumber;
  int? declaredPageCount;
  int formRevision;
  int? reviewConfirmedRevision;
  String? operatorEmail;
  CaptureMode mode;
  final DateTime createdAt;
  DateTime updatedAt;

  bool get isSubmitted => status == ScanSessionStatus.submittedLocal;
}

class PageCapture {
  PageCapture({
    required this.pageCaptureId,
    required this.sessionId,
    required this.printedPage,
    required this.captureRevision,
    required this.isActive,
    required this.createdAt,
    this.sourceImagePath,
    this.rectifiedImagePath,
    this.ocrStatus = PageOcrStatus.pending,
    this.ocrError,
    this.suggestedPrintedPage,
    this.suggestedDeclaredPageCount,
    this.observedDeliveryNoteNumber,
    this.verifiedDeliveryNoteNumber,
    this.observedPieceCount,
    this.verifiedPieceCount,
    this.verifiedDeclaredPageCount,
    this.pageIdentityConfirmed = false,
    this.rotationDegrees = 0,
    this.pageReviewConfirmed = false,
    this.pieceCountVarianceReviewed = false,
    this.pendingReplacement = false,
  });

  final String pageCaptureId;
  final String sessionId;
  int printedPage;
  int captureRevision;
  bool isActive;
  String? sourceImagePath;
  String? rectifiedImagePath;
  PageOcrStatus ocrStatus;
  String? ocrError;

  /// OCR-suggested printed page; operator must confirm before it becomes printedPage.
  int? suggestedPrintedPage;
  int? suggestedDeclaredPageCount;
  String? observedDeliveryNoteNumber;
  String? verifiedDeliveryNoteNumber;
  int? observedPieceCount;
  int? verifiedPieceCount;
  int? get effectivePieceCount => verifiedPieceCount ?? observedPieceCount;
  int? verifiedDeclaredPageCount;
  bool pageIdentityConfirmed;
  int rotationDegrees;
  bool pageReviewConfirmed;
  bool pieceCountVarianceReviewed;

  /// A retake waiting for the operator to accept it. The old page stays active.
  bool pendingReplacement;
  final DateTime createdAt;
}

class OcrElement {
  OcrElement({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    this.confidence,
  });

  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;
  final double? confidence;

  double get centerX => (left + right) / 2;
  double get centerY => (top + bottom) / 2;
  double get width => right - left;
  double get height => bottom - top;

  Map<String, dynamic> toJson() => {
    'text': text,
    'left': left,
    'top': top,
    'right': right,
    'bottom': bottom,
    'confidence': confidence,
  };

  factory OcrElement.fromJson(Map<String, dynamic> json) => OcrElement(
    text: json['text'] as String,
    left: (json['left'] as num).toDouble(),
    top: (json['top'] as num).toDouble(),
    right: (json['right'] as num).toDouble(),
    bottom: (json['bottom'] as num).toDouble(),
    confidence: (json['confidence'] as num?)?.toDouble(),
  );
}

class OcrObservation {
  OcrObservation({
    required this.ocrRunId,
    required this.pageCaptureId,
    required this.captureRevision,
    required this.engineName,
    required this.engineVersion,
    required this.imageWidth,
    required this.imageHeight,
    required this.elements,
    this.lines = const [],
    this.symbols = const [],
    this.fieldQuantityReads = const {},
    this.fieldEvidence = const {},
    required this.createdAt,
    this.elapsedMs,
  });

  final String ocrRunId;
  final String pageCaptureId;
  final int captureRevision;
  final String engineName;
  final String engineVersion;
  final int imageWidth;
  final int imageHeight;
  final List<OcrElement> elements;
  final List<OcrElement> lines;
  final List<OcrElement> symbols;
  final Map<String, int> fieldQuantityReads;
  final Map<String, dynamic> fieldEvidence;
  final int? elapsedMs;
  final DateTime createdAt;
}

class ParsedOccurrence {
  ParsedOccurrence({
    required this.occurrenceId,
    required this.pageCaptureId,
    required this.sourcePage,
    required this.articleNumber,
    required this.role,
    this.documentQuantity,
    this.unit = 'PC',
    this.productContext,
    this.issues = const [],
    this.blockTop,
    this.blockBottom,
    this.rowCenterY,
    this.quantityColumnLeft,
    this.suspectedQuantity,
  });

  final String occurrenceId;
  final String pageCaptureId;
  final int sourcePage;
  final String articleNumber;
  final OccurrenceRole role;
  final int? documentQuantity;
  final String unit;
  final String? productContext;
  final List<String> issues;
  final double? blockTop;
  final double? blockBottom;

  /// Product-description baseline, above the article and batch detail rows.
  final double? rowCenterY;

  /// Left edge of the printed Total Qty header in OCR image coordinates.
  final double? quantityColumnLeft;

  /// A possible OCR fusion; never accept the same value from a retry alone.
  final int? suspectedQuantity;

  bool get isQuantityBearing =>
      role == OccurrenceRole.quantityBearing && documentQuantity != null;
}

class DocumentLine {
  DocumentLine({
    required this.occurrenceId,
    required this.sessionId,
    required this.articleNumber,
    required this.documentQuantity,
    required this.physicalQuantity,
    required this.physicalOrigin,
    required this.sourcePage,
    required this.pageCaptureId,
    this.unit = 'PC',
    this.productContext,
    this.varianceReason,
    this.reviewConfirmed = false,
    this.physicalQuantityConfirmed = false,
    this.rawOcrArticle,
    this.rawOcrQuantity,
    PhysicalCountState? physicalCountState,
    String? countedArticleNumber,
  }) : physicalCountState =
           physicalCountState ??
           (physicalQuantityConfirmed
               ? PhysicalCountState.verified
               : physicalOrigin == PhysicalQuantityOrigin.defaultedFromDocument
               ? PhysicalCountState.notChecked
               : PhysicalCountState.counting),
       countedArticleNumber =
           countedArticleNumber ??
           (physicalQuantityConfirmed ||
                   physicalOrigin !=
                       PhysicalQuantityOrigin.defaultedFromDocument
               ? articleNumber
               : null);

  final String occurrenceId;
  final String sessionId;
  String articleNumber;
  int documentQuantity;
  int physicalQuantity;
  PhysicalQuantityOrigin physicalOrigin;
  String unit;
  int sourcePage;
  String pageCaptureId;
  String? productContext;
  String? varianceReason;
  bool reviewConfirmed;
  bool physicalQuantityConfirmed;
  String? rawOcrArticle;
  int? rawOcrQuantity;

  PhysicalCountState physicalCountState;
  String? countedArticleNumber;

  bool get hasPhysicalCount =>
      physicalCountState != PhysicalCountState.notChecked;
  bool get needsArticleReconciliation =>
      hasPhysicalCount && countedArticleNumber != articleNumber;
  bool get isPhysicalVerified =>
      physicalQuantityConfirmed &&
      physicalCountState == PhysicalCountState.verified &&
      !needsArticleReconciliation;

  DocumentLine copy() => DocumentLine(
    occurrenceId: occurrenceId,
    sessionId: sessionId,
    articleNumber: articleNumber,
    documentQuantity: documentQuantity,
    physicalQuantity: physicalQuantity,
    physicalOrigin: physicalOrigin,
    sourcePage: sourcePage,
    pageCaptureId: pageCaptureId,
    unit: unit,
    productContext: productContext,
    varianceReason: varianceReason,
    reviewConfirmed: reviewConfirmed,
    physicalQuantityConfirmed: physicalQuantityConfirmed,
    physicalCountState: physicalCountState,
    countedArticleNumber: countedArticleNumber,
    rawOcrArticle: rawOcrArticle,
    rawOcrQuantity: rawOcrQuantity,
  );

  int get variance => physicalQuantity - documentQuantity;
}

class DocumentContext {
  DocumentContext({
    required this.contextId,
    required this.sessionId,
    required this.articleNumber,
    required this.sourcePage,
    required this.pageCaptureId,
    this.heading,
  });

  final String contextId;
  final String sessionId;
  final String articleNumber;
  final String? heading;
  final int sourcePage;
  final String pageCaptureId;
}

class CorrectionRecord {
  CorrectionRecord({
    required this.id,
    required this.sessionId,
    required this.field,
    required this.beforeValue,
    required this.afterValue,
    required this.reason,
    required this.createdAt,
    this.occurrenceId,
  });

  final String id;
  final String sessionId;
  final String? occurrenceId;
  final String field;
  final String beforeValue;
  final String afterValue;
  final String reason;
  final DateTime createdAt;
}

class PhysicalAdjustment {
  PhysicalAdjustment({
    required this.id,
    required this.sessionId,
    required this.occurrenceId,
    required this.beforeQuantity,
    required this.afterQuantity,
    required this.reason,
    required this.createdAt,
    this.action = 'adjustment',
  });

  final String id;
  final String sessionId;
  final String occurrenceId;
  final int beforeQuantity;
  final int afterQuantity;
  final String reason;
  final DateTime createdAt;
  final String action;
}

class SubmittedForm {
  SubmittedForm({
    required this.submissionId,
    required this.sessionId,
    required this.snapshotJson,
    required this.submittedAt,
  });

  final String submissionId;
  final String sessionId;
  final String snapshotJson;
  final DateTime submittedAt;
}

/// Read-only progress figures for one saved delivery note, for list screens.
class SessionProgress {
  const SessionProgress({
    required this.session,
    this.pageCount = 0,
    this.checkedPageCount = 0,
    this.itemCount = 0,
    this.countedItemCount = 0,
    this.verifiedItemCount = 0,
    this.documentTotal = 0,
    this.countedTotal = 0,
    this.submittedAt,
  });

  final ScanSession session;
  final int pageCount;
  final int checkedPageCount;
  final int itemCount;

  /// Items with any physical count, including running counts.
  final int countedItemCount;
  final int verifiedItemCount;
  final int documentTotal;
  final int countedTotal;
  final DateTime? submittedAt;

  bool get hasPhysicalCounts => countedItemCount > 0;
}

class ParsedPageResult {
  ParsedPageResult({
    required this.pageCaptureId,
    required this.printedPage,
    required this.occurrences,
    this.deliveryNoteNumber,
    this.pieceCount,
    this.declaredPageCount,
    this.printedPageDetected = false,
    this.pageRole = 'unknown',
    this.issues = const [],
  });

  final String pageCaptureId;
  final int printedPage;
  final String? deliveryNoteNumber;
  final int? pieceCount;
  final int? declaredPageCount;
  final bool printedPageDetected;
  final String pageRole;
  final List<ParsedOccurrence> occurrences;
  final List<String> issues;
}
