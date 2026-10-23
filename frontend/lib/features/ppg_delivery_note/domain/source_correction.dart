import 'models.dart';

/// OCR may miss Total Qty or join a colour-code digit to the quantity.
/// Both cases need the same source-image verification and audit path.
bool isSourceCorrectableTotalQty(ParsedOccurrence occurrence) =>
    occurrence.role == OccurrenceRole.unresolved &&
    (occurrence.issues.contains('UNRESOLVED_MISSING_TOTAL_QTY') ||
        occurrence.issues.contains('AMBIGUOUS_COLOUR_QTY_BOUNDARY'));

/// Applies persisted source-backed Total Qty repairs to parser output.
/// The original OCR observation remains unchanged in persistence.
ParsedPageResult applySavedTotalCorrections(
  ParsedPageResult parsed,
  Iterable<DocumentLine> savedLines,
) {
  final corrections = {
    for (final line in savedLines)
      if (line.pageCaptureId == parsed.pageCaptureId &&
          line.rawOcrArticle != null &&
          line.rawOcrQuantity == null)
        line.occurrenceId: line,
  };
  if (corrections.isEmpty) return parsed;
  final repaired = <String>{};
  final occurrences = parsed.occurrences.map((occurrence) {
    final line = corrections[occurrence.occurrenceId];
    if (line == null || !isSourceCorrectableTotalQty(occurrence)) {
      return occurrence;
    }
    repaired.add(occurrence.occurrenceId);
    return ParsedOccurrence(
      occurrenceId: occurrence.occurrenceId,
      pageCaptureId: occurrence.pageCaptureId,
      sourcePage: occurrence.sourcePage,
      articleNumber: line.articleNumber,
      role: OccurrenceRole.quantityBearing,
      documentQuantity: line.documentQuantity,
      unit: occurrence.unit,
      productContext: occurrence.productContext,
      blockTop: occurrence.blockTop,
      blockBottom: occurrence.blockBottom,
      rowCenterY: occurrence.rowCenterY,
      quantityColumnLeft: occurrence.quantityColumnLeft,
      suspectedQuantity: occurrence.suspectedQuantity,
    );
  }).toList();
  if (repaired.isEmpty) return parsed;
  final remainingIssueMessages = <String>{
    for (final occurrence in occurrences.where(isSourceCorrectableTotalQty))
      if (occurrence.issues.contains('UNRESOLVED_MISSING_TOTAL_QTY'))
        'Missing Total Qty for article ${occurrence.articleNumber}'
      else
        'Ambiguous quantity near colour text for ${occurrence.articleNumber}',
  };
  final issues = parsed.issues.where((issue) {
    if (issue.startsWith('Missing Total Qty for article ') ||
        issue.startsWith('Ambiguous quantity near colour text for ')) {
      return remainingIssueMessages.contains(issue);
    }
    return true;
  }).toList();
  return ParsedPageResult(
    pageCaptureId: parsed.pageCaptureId,
    printedPage: parsed.printedPage,
    deliveryNoteNumber: parsed.deliveryNoteNumber,
    pieceCount: parsed.pieceCount,
    declaredPageCount: parsed.declaredPageCount,
    printedPageDetected: parsed.printedPageDetected,
    pageRole: parsed.pageRole,
    occurrences: occurrences,
    issues: issues,
  );
}
