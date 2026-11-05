import 'package:flutter_test/flutter_test.dart';
import 'package:label_reader/features/ppg_delivery_note/domain/models.dart';
import 'package:label_reader/features/ppg_delivery_note/parser/ppg_template_parser.dart';
import 'package:label_reader/features/ppg_delivery_note/persistence/ppg_repository.dart';
import 'package:label_reader/features/ppg_delivery_note/services/ppg_session_controller.dart';

class _SavedReviewRepository extends PpgRepository {
  _SavedReviewRepository(this.session, this.page, this.correctedLine, this.ocr);

  final ScanSession session;
  final PageCapture page;
  final DocumentLine correctedLine;
  final OcrObservation ocr;

  @override
  Future<ScanSession?> getSession(String id) async => session;

  @override
  Future<List<PageCapture>> getActivePages(String sessionId) async => [page];

  @override
  Future<List<PageCapture>> getPendingReplacements(String sessionId) async =>
      [];

  @override
  Future<List<DocumentLine>> getLines(String sessionId) async => [
    correctedLine,
  ];

  @override
  Future<List<DocumentContext>> getContexts(String sessionId) async => [];

  @override
  Future<SubmittedForm?> getSubmissionForSession(String sessionId) async =>
      null;

  @override
  Future<OcrObservation?> getLatestOcrObservation(PageCapture page) async =>
      ocr;
}

class _AmbiguousPageParser extends PpgTemplateParser {
  _AmbiguousPageParser(this.rawPage);

  final ParsedPageResult rawPage;

  @override
  ParsedPageResult parse({
    required OcrObservation observation,
    required int printedPageHint,
  }) => rawPage;
}

void main() {
  test(
    'reopening a page keeps a saved 445386 Total Qty correction resolved',
    () async {
      final now = DateTime.utc(2026, 9, 25);
      final session = ScanSession(
        id: 'session',
        status: ScanSessionStatus.reviewing,
        deliveryNoteNumber: '5319364114',
        declaredPageCount: 4,
        formRevision: 3,
        createdAt: now,
        updatedAt: now,
      );
      final page = PageCapture(
        pageCaptureId: 'page3',
        sessionId: session.id,
        printedPage: 3,
        captureRevision: 1,
        isActive: true,
        createdAt: now,
        ocrStatus: PageOcrStatus.succeeded,
        observedDeliveryNoteNumber: '5319364114',
        verifiedDeliveryNoteNumber: '5319364114',
        pageIdentityConfirmed: true,
      );
      final correctedLine = DocumentLine(
        occurrenceId: 'page3:445386',
        sessionId: session.id,
        articleNumber: '445386',
        documentQuantity: 8,
        physicalQuantity: 8,
        physicalOrigin: PhysicalQuantityOrigin.defaultedFromDocument,
        sourcePage: 3,
        pageCaptureId: page.pageCaptureId,
        rawOcrArticle: '445386',
        rawOcrQuantity: null,
      );
      final rawPage = ParsedPageResult(
        pageCaptureId: page.pageCaptureId,
        printedPage: 3,
        deliveryNoteNumber: '5319364114',
        declaredPageCount: 4,
        pageRole: 'product_table',
        issues: const ['Ambiguous quantity near colour text for 445386'],
        occurrences: [
          ParsedOccurrence(
            occurrenceId: correctedLine.occurrenceId,
            pageCaptureId: page.pageCaptureId,
            sourcePage: 3,
            articleNumber: '445386',
            role: OccurrenceRole.unresolved,
            issues: const ['AMBIGUOUS_COLOUR_QTY_BOUNDARY'],
          ),
        ],
      );
      final ocr = OcrObservation(
        ocrRunId: 'saved',
        pageCaptureId: page.pageCaptureId,
        captureRevision: 1,
        engineName: 'synthetic',
        engineVersion: 'test',
        imageWidth: 1224,
        imageHeight: 1584,
        elements: const [],
        createdAt: now,
      );
      final controller = PpgSessionController(
        repository: _SavedReviewRepository(session, page, correctedLine, ocr),
        parser: _AmbiguousPageParser(rawPage),
      );

      await controller.loadSession(session.id);

      expect(
        controller.blockingIssues.any((issue) => issue.contains('445386')),
        isFalse,
      );
      expect(
        controller
            .parsedOccurrencesForPage(page.pageCaptureId)
            .single
            .documentQuantity,
        8,
      );
    },
  );
}
