import '../domain/models.dart';

/// Consolidate parsed pages into document lines + set contexts.
/// Does not deduplicate by article number alone.
class PpgConsolidator {
  ConsolidatedDocument consolidate({
    required String sessionId,
    required List<ParsedPageResult> pages,
  }) {
    final ordered = [...pages]
      ..sort((a, b) => a.printedPage.compareTo(b.printedPage));
    final lines = <DocumentLine>[];
    final contexts = <DocumentContext>[];
    final blocking = <String>[];

    String? note;
    int? declared;
    for (final page in ordered) {
      note ??= page.deliveryNoteNumber;
      declared ??= page.declaredPageCount;
      if (page.deliveryNoteNumber != null &&
          note != null &&
          page.deliveryNoteNumber != note) {
        blocking.add(
          'Wrong document page: expected $note, saw ${page.deliveryNoteNumber}',
        );
      }
      blocking.addAll(page.issues);

      for (final occ in page.occurrences) {
        switch (occ.role) {
          case OccurrenceRole.setHeaderNoPrintedQuantity:
            contexts.add(
              DocumentContext(
                contextId: occ.occurrenceId,
                sessionId: sessionId,
                articleNumber: occ.articleNumber,
                heading: occ.productContext,
                sourcePage: occ.sourcePage,
                pageCaptureId: occ.pageCaptureId,
              ),
            );
          case OccurrenceRole.quantityBearing:
            if (occ.documentQuantity == null) {
              blocking.add(
                'Quantity-bearing row missing total for ${occ.articleNumber}',
              );
              continue;
            }
            lines.add(
              DocumentLine(
                occurrenceId: occ.occurrenceId,
                sessionId: sessionId,
                articleNumber: occ.articleNumber,
                documentQuantity: occ.documentQuantity!,
                physicalQuantity: occ.documentQuantity!,
                physicalOrigin: PhysicalQuantityOrigin.defaultedFromDocument,
                sourcePage: occ.sourcePage,
                pageCaptureId: occ.pageCaptureId,
                productContext: occ.productContext,
                rawOcrArticle: occ.articleNumber,
                rawOcrQuantity: occ.documentQuantity,
              ),
            );
          case OccurrenceRole.unresolved:
            blocking.addAll(
              occ.issues.isEmpty
                  ? ['Unresolved row ${occ.articleNumber}']
                  : occ.issues,
            );
        }
      }
    }

    return ConsolidatedDocument(
      lines: lines,
      contexts: contexts,
      deliveryNoteNumber: note,
      declaredPageCount: declared,
      blockingIssues: blocking,
    );
  }
}

class ConsolidatedDocument {
  ConsolidatedDocument({
    required this.lines,
    required this.contexts,
    required this.blockingIssues,
    this.deliveryNoteNumber,
    this.declaredPageCount,
  });

  final List<DocumentLine> lines;
  final List<DocumentContext> contexts;
  final String? deliveryNoteNumber;
  final int? declaredPageCount;
  final List<String> blockingIssues;
}
