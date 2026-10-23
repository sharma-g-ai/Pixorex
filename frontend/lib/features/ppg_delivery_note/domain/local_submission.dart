import 'dart:convert';

import '../domain/models.dart';
import '../domain/validation.dart';

/// Builds and validates the immutable local submission snapshot.
class LocalSubmissionService {
  Map<String, dynamic> buildSnapshot({
    required String submissionId,
    required ScanSession session,
    required List<DocumentLine> lines,
    required List<DocumentContext> contexts,
    required List<PageCapture> activePages,
    required DateTime submittedAt,
  }) {
    final pageOne = activePages.where((p) => p.printedPage == 1).firstOrNull;
    final documentTotal = lines.fold<int>(
      0,
      (sum, line) => sum + line.documentQuantity,
    );
    final physicalTotal = lines.fold<int>(
      0,
      (sum, line) => sum + line.physicalQuantity,
    );
    return {
      'submission_id': submissionId,
      'scan_session_id': session.id,
      'status': 'SUBMITTED_LOCAL',
      'delivery_note_number': session.deliveryNoteNumber,
      'declared_page_count': session.declaredPageCount,
      'printed_piece_count_ocr': pageOne?.observedPieceCount,
      'printed_piece_count': pageOne?.effectivePieceCount,
      'document_quantity_total': documentTotal,
      'physical_quantity_total': physicalTotal,
      'submitted_at': submittedAt.toUtc().toIso8601String(),
      'form_revision': session.formRevision,
      'operator_email': session.operatorEmail,
      'mode': switch (session.mode) {
        CaptureMode.camera => 'CAMERA',
        CaptureMode.developerImageImport => 'DEVELOPER_IMAGE_IMPORT',
        CaptureMode.illustrativeFixture => 'ILLUSTRATIVE_FIXTURE',
      },
      'lines': lines
          .map(
            (l) => {
              'occurrence_id': l.occurrenceId,
              'article_number': l.articleNumber,
              'document_quantity': l.documentQuantity,
              'physical_quantity': l.physicalQuantity,
              'physical_origin': l.physicalOrigin.name,
              'physical_quantity_confirmed': l.physicalQuantityConfirmed,
              'physical_count_state': l.physicalCountState.name,
              'counted_article_number': l.countedArticleNumber,
              'unit': l.unit,
              'variance': l.variance,
              'variance_reason': l.varianceReason,
              'source_page': l.sourcePage,
              'product_context': l.productContext,
              'review_confirmed': l.reviewConfirmed,
            },
          )
          .toList(),
      'contexts': contexts
          .map(
            (c) => {
              'context_id': c.contextId,
              'article_number': c.articleNumber,
              'heading': c.heading,
              'document_quantity': null,
              'role': 'SET_HEADER_NO_PRINTED_QUANTITY',
              'source_page': c.sourcePage,
            },
          )
          .toList(),
      'page_captures': activePages
          .map(
            (p) => {
              'page_capture_id': p.pageCaptureId,
              'printed_page': p.printedPage,
              'capture_revision': p.captureRevision,
              'observed_delivery_note_number': p.observedDeliveryNoteNumber,
              'verified_delivery_note_number': p.verifiedDeliveryNoteNumber,
              'observed_piece_count': p.observedPieceCount,
              'verified_piece_count': p.verifiedPieceCount,
              'page_review_confirmed': p.pageReviewConfirmed,
              'piece_count_variance_reviewed': p.pieceCountVarianceReviewed,
              'verified_declared_page_count': p.verifiedDeclaredPageCount,
              'source_image_ref': p.sourceImagePath,
            },
          )
          .toList(),
    };
  }

  /// Returns blocking reasons; empty means ready to submit.
  List<String> validateForSubmit({
    required ScanSession session,
    required List<DocumentLine> lines,
    required List<PageCapture> activePages,
    required List<String> blockingIssues,
    required bool rejectIllustrativeFixture,
  }) {
    final errors = <String>[...blockingIssues];
    errors.addAll(
      validatePieceSummary(
        activePages: activePages,
        lines: lines,
        declaredPageCount: session.declaredPageCount,
      ),
    );

    if (session.deliveryNoteNumber == null ||
        session.deliveryNoteNumber!.isEmpty) {
      errors.add('Delivery note identity is not verified');
    }
    if (session.declaredPageCount == null || session.declaredPageCount! < 1) {
      errors.add('Declared page count is missing');
    } else {
      final pages = activePages.map((p) => p.printedPage).toSet();
      for (var i = 1; i <= session.declaredPageCount!; i++) {
        if (!pages.contains(i)) {
          errors.add('Missing page $i of ${session.declaredPageCount}');
        }
      }
      if (pages.length != activePages.length) {
        errors.add('Duplicate printed page assignments');
      }
    }

    for (final p in activePages) {
      if (!p.pageReviewConfirmed) {
        errors.add(
          'Page ${p.printedPage} review and coverage are not confirmed',
        );
      }
      if (p.ocrStatus != PageOcrStatus.succeeded) {
        errors.add('Page ${p.printedPage} OCR not complete');
      }
      if (p.verifiedDeliveryNoteNumber == null ||
          p.verifiedDeliveryNoteNumber != session.deliveryNoteNumber) {
        errors.add('Page ${p.printedPage} document identity is unresolved');
      }
      if (!p.pageIdentityConfirmed) {
        errors.add('Page ${p.printedPage} identity is not confirmed');
      }
      if (session.declaredPageCount != null &&
          (p.printedPage < 1 || p.printedPage > session.declaredPageCount!)) {
        errors.add('Page ${p.printedPage} is outside declared page range');
      }
      if (session.declaredPageCount != null &&
          ((p.verifiedDeclaredPageCount != null &&
                  p.verifiedDeclaredPageCount != session.declaredPageCount) ||
              (p.verifiedDeclaredPageCount == null &&
                  p.suggestedDeclaredPageCount != null &&
                  p.suggestedDeclaredPageCount != session.declaredPageCount))) {
        errors.add('Page ${p.printedPage} total page count is unresolved');
      }
    }

    if (session.reviewConfirmedRevision != session.formRevision) {
      errors.add('Review confirmation is stale; re-confirm the form');
    }

    if (rejectIllustrativeFixture &&
        session.mode == CaptureMode.illustrativeFixture) {
      errors.add(
        'Illustrative fixture mode cannot be submitted as camera evidence',
      );
    }

    for (final line in lines) {
      if (!PpgValidation.isValidArticle(line.articleNumber)) {
        errors.add('Invalid article ${line.articleNumber}');
      }
      if (!PpgValidation.isValidQuantity(line.documentQuantity) ||
          !PpgValidation.isValidQuantity(line.physicalQuantity)) {
        errors.add('Invalid quantity for ${line.articleNumber}');
      }
      if (!line.reviewConfirmed) {
        errors.add('Line ${line.articleNumber} is not review-confirmed');
      }
      if (!line.isPhysicalVerified) {
        errors.add(
          'Physical quantity for ${line.articleNumber} is not confirmed',
        );
      }
      if (line.variance !=
          PpgValidation.variance(
            line.physicalQuantity,
            line.documentQuantity,
          )) {
        errors.add('Variance mismatch for ${line.articleNumber}');
      }
      if (PpgValidation.requiresVarianceReason(
            line.physicalQuantity,
            line.documentQuantity,
          ) &&
          (line.varianceReason == null ||
              line.varianceReason!.trim().isEmpty)) {
        errors.add('Variance reason required for ${line.articleNumber}');
      }
    }

    return errors.toSet().toList();
  }

  List<String> validatePieceSummary({
    required List<PageCapture> activePages,
    required List<DocumentLine> lines,
    required int? declaredPageCount,
  }) {
    if (!hasPieceCountSummaryMismatch(
      activePages: activePages,
      lines: lines,
      declaredPageCount: declaredPageCount,
    )) {
      return const [];
    }
    final pageOnes = activePages.where((p) => p.printedPage == 1).toList();
    final pageOne = pageOnes.single;
    final pieceCount = pageOne.effectivePieceCount;
    final documentTotal = lines.fold<int>(
      0,
      (sum, line) => sum + line.documentQuantity,
    );
    if (pageOne.pieceCountVarianceReviewed) {
      return const [];
    }
    return [
      'Printed Piece count $pieceCount PC does not match document line total $documentTotal PC; review the source and acknowledge the discrepancy',
    ];
  }

  bool hasPieceCountSummaryMismatch({
    required List<PageCapture> activePages,
    required List<DocumentLine> lines,
    required int? declaredPageCount,
  }) {
    final pageOnes = activePages.where((p) => p.printedPage == 1).toList();
    if (pageOnes.length != 1) return false;
    final pageOne = pageOnes.single;
    final pieceCount = pageOne.effectivePieceCount;
    if (pieceCount == null ||
        pageOne.ocrStatus != PageOcrStatus.succeeded ||
        !pageOne.pageIdentityConfirmed) {
      return false;
    }
    final complete =
        declaredPageCount != null &&
        activePages.length == declaredPageCount &&
        activePages.every(
          (p) =>
              p.printedPage >= 1 &&
              p.printedPage <= declaredPageCount &&
              p.ocrStatus == PageOcrStatus.succeeded &&
              p.pageIdentityConfirmed,
        ) &&
        activePages.map((p) => p.printedPage).toSet().length ==
            declaredPageCount;
    if (!complete) return false;
    final documentTotal = lines.fold<int>(
      0,
      (sum, line) => sum + line.documentQuantity,
    );
    return pieceCount != documentTotal;
  }

  String encode(Map<String, dynamic> snapshot) =>
      const JsonEncoder.withIndent('  ').convert(snapshot);
}
