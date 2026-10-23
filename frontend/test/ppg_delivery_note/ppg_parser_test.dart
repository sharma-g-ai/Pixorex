import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:label_reader/features/ppg_delivery_note/domain/local_submission.dart';
import 'package:label_reader/features/ppg_delivery_note/domain/models.dart';
import 'package:label_reader/features/ppg_delivery_note/domain/source_correction.dart';
import 'package:label_reader/features/ppg_delivery_note/domain/validation.dart';
import 'package:label_reader/features/ppg_delivery_note/parser/consolidator.dart';
import 'package:label_reader/features/ppg_delivery_note/parser/ppg_template_parser.dart';

void main() {
  late Map<String, dynamic> expected;
  late Map<String, dynamic> synthetic;
  late PpgTemplateParser parser;
  late PpgConsolidator consolidator;

  setUpAll(() {
    expected =
        jsonDecode(
              File(
                'test/ppg_delivery_note/dn_5319364114.expected.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    synthetic =
        jsonDecode(
              File(
                'test/ppg_delivery_note/dn_5319364114_synthetic_ocr.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
  });

  setUp(() {
    parser = PpgTemplateParser();
    consolidator = PpgConsolidator();
  });

  List<ParsedPageResult> parseAll() {
    final pages = <ParsedPageResult>[];
    for (final page in synthetic['pages'] as List) {
      final p = page as Map<String, dynamic>;
      final elements = (p['elements'] as List)
          .map((e) => OcrElement.fromJson(e as Map<String, dynamic>))
          .toList();
      final obs = OcrObservation(
        ocrRunId: 'run_${p['printed_page']}',
        pageCaptureId: 'cap_${p['printed_page']}',
        captureRevision: 1,
        engineName: 'synthetic',
        engineVersion: 'test',
        imageWidth: p['image_width'] as int,
        imageHeight: p['image_height'] as int,
        elements: elements,
        createdAt: DateTime.utc(2026, 9, 24),
      );
      pages.add(
        parser.parse(
          observation: obs,
          printedPageHint: p['printed_page'] as int,
        ),
      );
    }
    return pages;
  }

  test('T01 parse complete sample product evidence', () {
    final pages = parseAll();
    final doc = consolidator.consolidate(sessionId: 'sess', pages: pages);
    expect(pages.first.pieceCount, expected['header_piece_check']);
    final expectedRows = expected['quantity_bearing_rows'] as List;
    expect(doc.lines.length, 7);
    for (var i = 0; i < 7; i++) {
      final exp = expectedRows[i] as Map<String, dynamic>;
      expect(doc.lines[i].articleNumber, exp['article_number']);
      expect(doc.lines[i].documentQuantity, exp['document_quantity']);
    }
    expect(doc.contexts.length, 2);
    for (final ctx in doc.contexts) {
      expect(ctx.articleNumber, anyOf('179061', '446789'));
    }
    final sum = doc.lines.fold<int>(0, (a, l) => a + l.documentQuantity);
    expect(sum, 62);
  });

  test('T02 page 2 has two qty rows and set headers without quantities', () {
    final page2 = parseAll().firstWhere((p) => p.printedPage == 2);
    final qty = page2.occurrences
        .where((o) => o.role == OccurrenceRole.quantityBearing)
        .toList();
    final sets = page2.occurrences
        .where((o) => o.role == OccurrenceRole.setHeaderNoPrintedQuantity)
        .toList();
    expect(qty.map((o) => o.articleNumber), containsAll(['445235', '445182']));
    expect(qty, hasLength(2));
    expect(qty.map((o) => o.documentQuantity), everyElement(15));
    expect(sets.map((o) => o.articleNumber), containsAll(['179061', '446789']));
    expect(sets, hasLength(2));
    for (final s in sets) {
      expect(s.documentQuantity, isNull);
    }
    expect(page2.occurrences.map((o) => o.articleNumber), [
      '179061',
      '445235',
      '445182',
      '446789',
    ]);
    expect(
      {
        for (final occurrence in page2.occurrences)
          occurrence.articleNumber: occurrence.productContext,
      },
      {
        '179061': "S'COVER 456 SET GREY",
        '445235': 'S COVER 456 BAS GREY',
        '445182': 'S COVER 256/435/456/522 HRD',
        '446789': 'S PRIME 200 SET YEL/GREEN',
      },
    );
    expect(page2.issues, isEmpty);
    expect(
      page2.occurrences.where((o) => o.role == OccurrenceRole.unresolved),
      isEmpty,
    );
  });

  test('page 2 does not borrow a Batch Qty when Total Qty is unreadable', () {
    final result = parser.parse(
      observation: OcrObservation(
        ocrRunId: 'page2_batch_is_not_total',
        pageCaptureId: 'page2_batch_is_not_total',
        captureRevision: 1,
        engineName: 'synthetic',
        engineVersion: 'test',
        imageWidth: 1000,
        imageHeight: 1000,
        createdAt: DateTime.utc(2026),
        elements: [
          OcrElement(
            text: 'Total Qty',
            left: 850,
            top: 10,
            right: 950,
            bottom: 30,
          ),
          OcrElement(
            text: 'Batch Qty per Batch',
            left: 650,
            top: 10,
            right: 820,
            bottom: 30,
          ),
          OcrElement(
            text: 'S COVER 456 BAS GREY',
            left: 120,
            top: 200,
            right: 460,
            bottom: 225,
          ),
          OcrElement(
            text: '445235',
            left: 200,
            top: 240,
            right: 280,
            bottom: 265,
          ),
          OcrElement(
            text: 'Batch 0000336303',
            left: 260,
            top: 285,
            right: 520,
            bottom: 305,
          ),
          OcrElement(
            text: '15 PC',
            left: 870,
            top: 275,
            right: 930,
            bottom: 295,
          ),
          OcrElement(
            text: 'S COVER 256 HRD',
            left: 120,
            top: 400,
            right: 420,
            bottom: 425,
          ),
          OcrElement(
            text: '15 PC',
            left: 870,
            top: 400,
            right: 930,
            bottom: 425,
          ),
          OcrElement(
            text: '445182',
            left: 200,
            top: 440,
            right: 280,
            bottom: 465,
          ),
        ],
      ),
      printedPageHint: 2,
    );
    final missing = result.occurrences.singleWhere(
      (o) => o.articleNumber == '445235',
    );
    final recognized = result.occurrences.singleWhere(
      (o) => o.articleNumber == '445182',
    );
    expect(missing.role, OccurrenceRole.unresolved);
    expect(missing.documentQuantity, isNull);
    expect(recognized.role, OccurrenceRole.quantityBearing);
    expect(recognized.documentQuantity, 15);
  });

  test('T03 article 445386 total 8 not batch 5/3', () {
    final page3 = parseAll().firstWhere((p) => p.printedPage == 3);
    final row = page3.occurrences.firstWhere(
      (o) => o.articleNumber == '445386',
    );
    expect(row.documentQuantity, 8);
    expect(row.role, OccurrenceRole.quantityBearing);
  });

  test('Total Qty above article code survives a wide printed row gap', () {
    final result = parser.parse(
      observation: OcrObservation(
        ocrRunId: 'wide_total_row_gap',
        pageCaptureId: 'wide_total_row_gap_page',
        captureRevision: 1,
        engineName: 'synthetic',
        engineVersion: 'test',
        imageWidth: 1000,
        imageHeight: 1000,
        createdAt: DateTime.utc(2026),
        elements: [
          OcrElement(
            text: 'Total Qty',
            left: 800,
            top: 10,
            right: 920,
            bottom: 30,
          ),
          OcrElement(
            text: 'S RINE 48 RED',
            left: 120,
            top: 100,
            right: 390,
            bottom: 125,
          ),
          OcrElement(
            text: '8 PC',
            left: 820,
            top: 100,
            right: 880,
            bottom: 125,
          ),
          OcrElement(
            text: '445386',
            left: 200,
            top: 250,
            right: 290,
            bottom: 275,
          ),
          OcrElement(
            text: 'Qty per Batch',
            left: 700,
            top: 300,
            right: 860,
            bottom: 320,
          ),
          OcrElement(
            text: '5 PC',
            left: 820,
            top: 330,
            right: 880,
            bottom: 350,
          ),
          OcrElement(
            text: '3 PC',
            left: 820,
            top: 360,
            right: 880,
            bottom: 380,
          ),
        ],
      ),
      printedPageHint: 2,
    );
    final row = result.occurrences.singleWhere(
      (o) => o.articleNumber == '445386',
    );
    expect(row.role, OccurrenceRole.quantityBearing);
    expect(row.documentQuantity, 8);
    expect(result.issues, isEmpty);
  });

  test('T06 header page emits no product rows', () {
    final page1 = parseAll().firstWhere((p) => p.printedPage == 1);
    expect(page1.pageRole, 'header');
    expect(page1.occurrences, isEmpty);
    expect(page1.deliveryNoteNumber, '5319364114');
    expect(page1.declaredPageCount, 4);
  });

  test('Order number cannot replace the labelled Delivery Note number', () {
    final result = parser.parse(
      observation: OcrObservation(
        ocrRunId: 'labelled_identity',
        pageCaptureId: 'labelled_identity',
        captureRevision: 1,
        engineName: 'synthetic',
        engineVersion: 'test',
        imageWidth: 1200,
        imageHeight: 1600,
        createdAt: DateTime.utc(2026),
        elements: [
          OcrElement(
            text: 'Page : 1 / 4',
            left: 900,
            top: 20,
            right: 1080,
            bottom: 45,
          ),
          OcrElement(text: 'Order', left: 600, top: 70, right: 690, bottom: 95),
          OcrElement(
            text: '5319074922',
            left: 760,
            top: 70,
            right: 920,
            bottom: 95,
          ),
          OcrElement(
            text: 'Delivery Note',
            left: 600,
            top: 120,
            right: 750,
            bottom: 145,
          ),
          OcrElement(
            text: '5319364114',
            left: 770,
            top: 120,
            right: 930,
            bottom: 145,
          ),
          OcrElement(
            text: 'Piece:62',
            left: 100,
            top: 400,
            right: 230,
            bottom: 425,
          ),
        ],
      ),
      printedPageHint: 1,
    );
    expect(result.pageRole, 'header');
    expect(result.deliveryNoteNumber, '5319364114');
  });

  test('Delivery Note label wins when OCR joins Order on one line', () {
    final result = parser.parse(
      observation: OcrObservation(
        ocrRunId: 'joined_header_numbers',
        pageCaptureId: 'joined_header_numbers',
        captureRevision: 1,
        engineName: 'synthetic',
        engineVersion: 'test',
        imageWidth: 1200,
        imageHeight: 1600,
        createdAt: DateTime.utc(2026),
        elements: [
          OcrElement(
            text: 'Order : 5319074922 Delivery Note : 5319364114',
            left: 600,
            top: 50,
            right: 1000,
            bottom: 75,
          ),
          OcrElement(
            text: 'Page : 1 / 4',
            left: 1000,
            top: 20,
            right: 1150,
            bottom: 45,
          ),
          OcrElement(
            text: 'Piece:62',
            left: 100,
            top: 400,
            right: 230,
            bottom: 425,
          ),
        ],
      ),
      printedPageHint: 1,
    );
    expect(result.deliveryNoteNumber, '5319364114');
  });

  test('split Order label and number cannot seed delivery identity', () {
    final result = parser.parse(
      observation: OcrObservation(
        ocrRunId: 'split_order_number',
        pageCaptureId: 'split_order_number',
        captureRevision: 1,
        engineName: 'synthetic',
        engineVersion: 'test',
        imageWidth: 1200,
        imageHeight: 1600,
        createdAt: DateTime.utc(2026),
        elements: [
          OcrElement(text: 'Order', left: 600, top: 70, right: 700, bottom: 95),
          OcrElement(
            text: '5319074922',
            left: 760,
            top: 100,
            right: 930,
            bottom: 125,
          ),
          OcrElement(
            text: 'Page : 1 / 4',
            left: 1000,
            top: 20,
            right: 1150,
            bottom: 45,
          ),
        ],
      ),
      printedPageHint: 1,
    );
    expect(result.deliveryNoteNumber, isNull);
  });

  test('address postcodes above the table are not article occurrences', () {
    final result = parser.parse(
      observation: OcrObservation(
        ocrRunId: 'address_not_article',
        pageCaptureId: 'address_not_article',
        captureRevision: 1,
        engineName: 'synthetic',
        engineVersion: 'test',
        imageWidth: 1200,
        imageHeight: 1600,
        createdAt: DateTime.utc(2026),
        elements: [
          OcrElement(
            text: 'Delivery Note : 5319364114',
            left: 600,
            top: 30,
            right: 980,
            bottom: 55,
          ),
          OcrElement(
            text: 'Page : 2 / 4',
            left: 1000,
            top: 30,
            right: 1150,
            bottom: 55,
          ),
          OcrElement(
            text: '1400 COLOMBO',
            left: 200,
            top: 100,
            right: 380,
            bottom: 125,
          ),
          OcrElement(
            text: '0000 COLOMBO',
            left: 520,
            top: 160,
            right: 700,
            bottom: 185,
          ),
          OcrElement(text: 'Item', left: 50, top: 260, right: 100, bottom: 285),
          OcrElement(
            text: 'Description',
            left: 120,
            top: 260,
            right: 280,
            bottom: 285,
          ),
          OcrElement(
            text: 'Total Qty',
            left: 850,
            top: 260,
            right: 970,
            bottom: 285,
          ),
          OcrElement(
            text: 'S COVER 456 BAS GREY',
            left: 120,
            top: 350,
            right: 460,
            bottom: 375,
          ),
          OcrElement(
            text: '15 PC',
            left: 880,
            top: 350,
            right: 950,
            bottom: 375,
          ),
          OcrElement(
            text: '445235',
            left: 200,
            top: 390,
            right: 290,
            bottom: 415,
          ),
        ],
      ),
      printedPageHint: 2,
    );
    expect(result.deliveryNoteNumber, '5319364114');
    expect(result.occurrences.map((o) => o.articleNumber), ['445235']);
    expect(result.occurrences.single.documentQuantity, 15);
    expect(result.issues, isEmpty);
  });

  test('item number and material columns stay out of product description', () {
    final result = parser.parse(
      observation: OcrObservation(
        ocrRunId: 'description_columns',
        pageCaptureId: 'description_columns',
        captureRevision: 1,
        engineName: 'synthetic',
        engineVersion: 'test',
        imageWidth: 1200,
        imageHeight: 1600,
        createdAt: DateTime.utc(2026),
        elements: [
          OcrElement(text: 'Item', left: 50, top: 100, right: 100, bottom: 125),
          OcrElement(
            text: 'Description',
            left: 120,
            top: 100,
            right: 280,
            bottom: 125,
          ),
          OcrElement(
            text: 'Total Qty',
            left: 850,
            top: 100,
            right: 970,
            bottom: 125,
          ),
          OcrElement(text: '10', left: 50, top: 200, right: 70, bottom: 225),
          OcrElement(text: 'S', left: 120, top: 200, right: 140, bottom: 225),
          OcrElement(
            text: 'COVER',
            left: 145,
            top: 200,
            right: 230,
            bottom: 225,
          ),
          OcrElement(text: '456', left: 240, top: 200, right: 290, bottom: 225),
          OcrElement(text: 'BAS', left: 300, top: 200, right: 350, bottom: 225),
          OcrElement(
            text: 'GREY',
            left: 360,
            top: 200,
            right: 420,
            bottom: 225,
          ),
          OcrElement(
            text: '517705ID2164',
            left: 440,
            top: 200,
            right: 610,
            bottom: 225,
          ),
          OcrElement(
            text: 'SIGMA',
            left: 650,
            top: 200,
            right: 730,
            bottom: 225,
          ),
          OcrElement(text: '15', left: 880, top: 200, right: 910, bottom: 225),
          OcrElement(text: 'PC', left: 920, top: 200, right: 960, bottom: 225),
          OcrElement(
            text: '445235',
            left: 200,
            top: 240,
            right: 290,
            bottom: 265,
          ),
        ],
      ),
      printedPageHint: 2,
    );
    expect(result.occurrences.single.productContext, 'S COVER 456 BAS GREY');
    expect(result.occurrences.single.documentQuantity, 15);
  });

  test('T08 ignores EAN and material codes', () {
    final page3 = parseAll().firstWhere((p) => p.printedPage == 3);
    final articles = page3.occurrences.map((o) => o.articleNumber).toSet();
    expect(articles.contains('4006381333931'), isFalse);
    expect(articles.contains('618805ID1500'), isFalse);
  });

  test('T09 retention of duplicate article occurrences', () {
    final elements = [
      OcrElement(text: 'Total Qty', left: 800, top: 10, right: 900, bottom: 30),
      OcrElement(text: 'PROD A', left: 100, top: 50, right: 200, bottom: 70),
      OcrElement(text: '5 PC', left: 820, top: 50, right: 880, bottom: 70),
      OcrElement(text: '111111', left: 180, top: 80, right: 260, bottom: 100),
      OcrElement(
        text: 'PROD A again',
        left: 100,
        top: 200,
        right: 250,
        bottom: 220,
      ),
      OcrElement(text: '3 PC', left: 820, top: 200, right: 880, bottom: 220),
      OcrElement(text: '111111', left: 180, top: 230, right: 260, bottom: 250),
      OcrElement(text: '1 / 1', left: 900, top: 5, right: 960, bottom: 25),
      OcrElement(text: '5319364114', left: 400, top: 5, right: 520, bottom: 25),
    ];
    final result = parser.parse(
      observation: OcrObservation(
        ocrRunId: 'r',
        pageCaptureId: 'c',
        captureRevision: 1,
        engineName: 'synthetic',
        engineVersion: 't',
        imageWidth: 1000,
        imageHeight: 1000,
        elements: elements,
        createdAt: DateTime.utc(2026),
      ),
      printedPageHint: 1,
    );
    final qty = result.occurrences
        .where((o) => o.articleNumber == '111111' && o.isQuantityBearing)
        .toList();
    expect(qty.length, 2);
    expect(qty.map((o) => o.documentQuantity), containsAll([5, 3]));
  });

  test(
    'T10 ordinary missing total stays unresolved without inventing zero',
    () {
      final result = parser.parse(
        observation: OcrObservation(
          ocrRunId: 'r',
          pageCaptureId: 'c',
          captureRevision: 1,
          engineName: 'synthetic',
          engineVersion: 't',
          imageWidth: 1000,
          imageHeight: 1000,
          createdAt: DateTime.utc(2026),
          elements: [
            OcrElement(
              text: 'Total Qty',
              left: 800,
              top: 10,
              right: 900,
              bottom: 30,
            ),
            OcrElement(
              text: 'LONELY PROD',
              left: 100,
              top: 50,
              right: 250,
              bottom: 70,
            ),
            OcrElement(
              text: '222222',
              left: 180,
              top: 80,
              right: 260,
              bottom: 100,
            ),
            OcrElement(
              text: '1 / 1',
              left: 900,
              top: 5,
              right: 960,
              bottom: 25,
            ),
          ],
        ),
        printedPageHint: 1,
      );
      final row = result.occurrences.singleWhere(
        (o) => o.articleNumber == '222222',
      );
      expect(row.role, OccurrenceRole.unresolved);
      expect(row.documentQuantity, isNull);
    },
  );

  test('source-entered Total Qty resolves only its matching occurrence', () {
    final parsed = ParsedPageResult(
      pageCaptureId: 'capture-1',
      printedPage: 2,
      deliveryNoteNumber: '5319364114',
      issues: const ['Missing Total Qty for article 445386'],
      occurrences: [
        ParsedOccurrence(
          occurrenceId: 'capture-1:4:445386',
          pageCaptureId: 'capture-1',
          sourcePage: 2,
          articleNumber: '445386',
          role: OccurrenceRole.unresolved,
          issues: const ['UNRESOLVED_MISSING_TOTAL_QTY'],
        ),
        ParsedOccurrence(
          occurrenceId: 'capture-1:9:445386',
          pageCaptureId: 'capture-1',
          sourcePage: 2,
          articleNumber: '445386',
          role: OccurrenceRole.unresolved,
          issues: const ['UNRESOLVED_MISSING_TOTAL_QTY'],
        ),
      ],
    );
    final sourceCorrection = DocumentLine(
      occurrenceId: 'capture-1:4:445386',
      sessionId: 'session-1',
      articleNumber: '445386',
      documentQuantity: 8,
      physicalQuantity: 8,
      physicalOrigin: PhysicalQuantityOrigin.defaultedFromDocument,
      sourcePage: 2,
      pageCaptureId: 'capture-1',
      rawOcrArticle: '445386',
      rawOcrQuantity: null,
    );

    final resolved = applySavedTotalCorrections(parsed, [sourceCorrection]);
    expect(resolved.occurrences.first.role, OccurrenceRole.quantityBearing);
    expect(resolved.occurrences.first.documentQuantity, 8);
    expect(resolved.occurrences.last.role, OccurrenceRole.unresolved);
    expect(resolved.issues, contains('Missing Total Qty for article 445386'));
    expect(sourceCorrection.rawOcrQuantity, isNull);
  });

  test('T22 variance behavior', () {
    final line = DocumentLine(
      occurrenceId: 'o',
      sessionId: 's',
      articleNumber: '445386',
      documentQuantity: 8,
      physicalQuantity: 6,
      physicalOrigin: PhysicalQuantityOrigin.userEntered,
      sourcePage: 3,
      pageCaptureId: 'c',
      varianceReason: 'Two pieces not physically received',
      reviewConfirmed: true,
    );
    expect(line.variance, -2);
    expect(PpgValidation.requiresVarianceReason(6, 8), isTrue);
  });

  test('T28 submit validation idempotent readiness checks', () {
    final session = ScanSession(
      id: 's',
      status: ScanSessionStatus.reviewing,
      formRevision: 2,
      reviewConfirmedRevision: 2,
      deliveryNoteNumber: '5319364114',
      declaredPageCount: 1,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      mode: CaptureMode.developerImageImport,
    );
    final pages = [
      PageCapture(
        pageCaptureId: 'c1',
        sessionId: 's',
        printedPage: 1,
        captureRevision: 1,
        isActive: true,
        createdAt: DateTime.utc(2026),
        ocrStatus: PageOcrStatus.succeeded,
        pageIdentityConfirmed: true,
        pageReviewConfirmed: true,
        observedDeliveryNoteNumber: null,
        verifiedDeliveryNoteNumber: '5319364114',
        observedPieceCount: 8,
      ),
    ];
    final lines = [
      DocumentLine(
        occurrenceId: 'o1',
        sessionId: 's',
        articleNumber: '445374',
        documentQuantity: 8,
        physicalQuantity: 8,
        physicalOrigin: PhysicalQuantityOrigin.defaultedFromDocument,
        physicalQuantityConfirmed: true,
        sourcePage: 1,
        pageCaptureId: 'c1',
        reviewConfirmed: true,
      ),
    ];
    final svc = LocalSubmissionService();
    final errors = svc.validateForSubmit(
      session: session,
      lines: lines,
      activePages: pages,
      blockingIssues: const [],
      rejectIllustrativeFixture: true,
    );
    expect(errors, isEmpty);

    pages.single.pageReviewConfirmed = false;
    pages.single.verifiedDeliveryNoteNumber = '5319074922';
    lines.single.physicalQuantityConfirmed = false;
    final unverified = svc.validateForSubmit(
      session: session,
      lines: lines,
      activePages: pages,
      blockingIssues: const [],
      rejectIllustrativeFixture: true,
    );
    expect(unverified.any((e) => e.contains('review and coverage')), isTrue);
    expect(unverified.any((e) => e.contains('identity is unresolved')), isTrue);
    expect(unverified.any((e) => e.contains('Physical quantity')), isTrue);

    session.mode = CaptureMode.illustrativeFixture;
    final blocked = svc.validateForSubmit(
      session: session,
      lines: lines,
      activePages: pages,
      blockingIssues: const [],
      rejectIllustrativeFixture: true,
    );
    expect(blocked, isNotEmpty);
  });

  test('printed Piece check compares document total, not physical stock', () {
    final page = PageCapture(
      pageCaptureId: 'p1',
      sessionId: 's',
      printedPage: 1,
      captureRevision: 1,
      isActive: true,
      createdAt: DateTime.utc(2026),
      ocrStatus: PageOcrStatus.succeeded,
      pageIdentityConfirmed: true,
      observedPieceCount: 8,
    );
    final line = DocumentLine(
      occurrenceId: 'l1',
      sessionId: 's',
      articleNumber: '445374',
      documentQuantity: 8,
      physicalQuantity: 6,
      physicalOrigin: PhysicalQuantityOrigin.userEntered,
      sourcePage: 1,
      pageCaptureId: 'p1',
      reviewConfirmed: true,
    );
    final svc = LocalSubmissionService();
    expect(
      svc.validatePieceSummary(
        activePages: [page],
        lines: [line],
        declaredPageCount: 1,
      ),
      isEmpty,
    );
    line.documentQuantity = 7;
    expect(
      svc
          .validatePieceSummary(
            activePages: [page],
            lines: [line],
            declaredPageCount: 1,
          )
          .single,
      contains('8 PC does not match document line total 7 PC'),
    );
    page.verifiedPieceCount = 7;
    expect(
      svc.validatePieceSummary(
        activePages: [page],
        lines: [line],
        declaredPageCount: 1,
      ),
      isEmpty,
    );
    final snapshot = svc.buildSnapshot(
      submissionId: 'sub',
      session: ScanSession(
        id: 's',
        status: ScanSessionStatus.reviewing,
        formRevision: 1,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
      lines: [line],
      contexts: const [],
      activePages: [page],
      submittedAt: DateTime.utc(2026),
    );
    expect(snapshot['printed_piece_count_ocr'], 8);
    expect(snapshot['printed_piece_count'], 7);
    expect(snapshot['document_quantity_total'], 7);
    expect(snapshot['physical_quantity_total'], 6);
    expect(
      (snapshot['lines'] as List).single['physical_origin'],
      'userEntered',
    );
  });

  test(
    'optional Piece count never blocks and mismatch needs acknowledgment',
    () {
      final page = PageCapture(
        pageCaptureId: 'p1',
        sessionId: 's',
        printedPage: 1,
        captureRevision: 1,
        isActive: true,
        createdAt: DateTime.utc(2026),
        ocrStatus: PageOcrStatus.succeeded,
        pageIdentityConfirmed: true,
      );
      final svc = LocalSubmissionService();
      final lines = [
        DocumentLine(
          occurrenceId: 'line',
          sessionId: 's',
          articleNumber: '445374',
          documentQuantity: 7,
          physicalQuantity: 7,
          physicalOrigin: PhysicalQuantityOrigin.defaultedFromDocument,
          sourcePage: 1,
          pageCaptureId: 'p1',
        ),
      ];
      expect(
        svc.validatePieceSummary(
          activePages: [page],
          lines: const [],
          declaredPageCount: 1,
        ),
        isEmpty,
      );
      page.observedPieceCount = 8;
      expect(
        svc.validatePieceSummary(
          activePages: [page],
          lines: lines,
          declaredPageCount: 1,
        ),
        hasLength(1),
      );
      expect(
        svc
            .validatePieceSummary(
              activePages: [page],
              lines: lines,
              declaredPageCount: 1,
            )
            .single,
        contains('review the source and acknowledge'),
      );
      page.pieceCountVarianceReviewed = true;
      expect(
        svc.validatePieceSummary(
          activePages: [page],
          lines: lines,
          declaredPageCount: 1,
        ),
        isEmpty,
      );
    },
  );

  test('capture order does not change consolidation order', () {
    final pages = parseAll();
    final shuffled = [pages[2], pages[0], pages[3], pages[1]];
    final doc = consolidator.consolidate(sessionId: 's', pages: shuffled);
    expect(doc.lines.map((l) => l.articleNumber).toList(), [
      '445235',
      '445182',
      '475212',
      '475210',
      '445377',
      '445386',
      '445374',
    ]);
  });

  test('word-level OCR fixture matches golden seven rows', () {
    final wordSynth =
        jsonDecode(
              File(
                'test/ppg_delivery_note/dn_5319364114_word_level_ocr.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final pages = <ParsedPageResult>[];
    for (final page in wordSynth['pages'] as List) {
      final p = page as Map<String, dynamic>;
      final elements = (p['elements'] as List)
          .map((e) => OcrElement.fromJson(e as Map<String, dynamic>))
          .toList();
      pages.add(
        parser.parse(
          observation: OcrObservation(
            ocrRunId: 'w_${p['printed_page']}',
            pageCaptureId: 'wc_${p['printed_page']}',
            captureRevision: 1,
            engineName: 'word_synthetic',
            engineVersion: 'test',
            imageWidth: p['image_width'] as int,
            imageHeight: p['image_height'] as int,
            elements: elements,
            createdAt: DateTime.utc(2026, 9, 24),
          ),
          printedPageHint: p['printed_page'] as int,
        ),
      );
    }
    expect(pages[0].pageRole, 'header');
    expect(pages[0].pieceCount, 62);
    expect(pages[0].occurrences, isEmpty);
    final page2 = pages.firstWhere((page) => page.printedPage == 2);
    expect(page2.issues, isEmpty);
    expect(page2.occurrences.map((o) => o.articleNumber), [
      '179061',
      '445235',
      '445182',
      '446789',
    ]);
    expect(
      page2.occurrences
          .where((o) => o.role == OccurrenceRole.quantityBearing)
          .map((o) => o.documentQuantity),
      [15, 15],
    );
    final doc = consolidator.consolidate(sessionId: 'sess', pages: pages);
    expect(doc.lines.length, 7);
    expect(doc.contexts.length, 2);
    expect(doc.lines.map((l) => l.articleNumber).toList(), [
      '445235',
      '445182',
      '475212',
      '475210',
      '445377',
      '445386',
      '445374',
    ]);
    expect(
      doc.lines.firstWhere((l) => l.articleNumber == '445386').documentQuantity,
      8,
    );
  });

  test('rejects picking-list style layout', () {
    final result = parser.parse(
      observation: OcrObservation(
        ocrRunId: 'r',
        pageCaptureId: 'c',
        captureRevision: 1,
        engineName: 'synthetic',
        engineVersion: 't',
        imageWidth: 1000,
        imageHeight: 1000,
        createdAt: DateTime.utc(2026),
        elements: [
          OcrElement(
            text: 'SEATRADE',
            left: 10,
            top: 10,
            right: 100,
            bottom: 30,
          ),
          OcrElement(
            text: 'COLOMBIA',
            left: 110,
            top: 10,
            right: 220,
            bottom: 30,
          ),
          OcrElement(text: 'POD', left: 230, top: 10, right: 280, bottom: 30),
          OcrElement(text: 'picking', left: 10, top: 50, right: 90, bottom: 70),
          OcrElement(text: 'list', left: 100, top: 50, right: 150, bottom: 70),
          OcrElement(
            text: 'Material #',
            left: 100,
            top: 80,
            right: 180,
            bottom: 98,
          ),
          OcrElement(
            text: 'Order Qty',
            left: 300,
            top: 80,
            right: 390,
            bottom: 98,
          ),
          OcrElement(
            text: 'Batch Qty',
            left: 700,
            top: 80,
            right: 790,
            bottom: 98,
          ),
          OcrElement(
            text: '5324642228',
            left: 500,
            top: 30,
            right: 650,
            bottom: 48,
          ),
          OcrElement(
            text: '111111',
            left: 10,
            top: 100,
            right: 90,
            bottom: 120,
          ),
          OcrElement(text: '5', left: 200, top: 100, right: 220, bottom: 120),
          OcrElement(text: 'PC', left: 230, top: 100, right: 260, bottom: 120),
        ],
      ),
      printedPageHint: 1,
    );
    expect(result.pageRole, 'rejected_non_ppg');
    expect(result.occurrences, isEmpty);
  });

  test('accepts joined DeliveryNote on summary page', () {
    final result = parser.parse(
      observation: OcrObservation(
        ocrRunId: 'joined_title',
        pageCaptureId: 'joined_title_page',
        captureRevision: 1,
        engineName: 'synthetic',
        engineVersion: 'test',
        imageWidth: 1000,
        imageHeight: 1000,
        createdAt: DateTime.utc(2026),
        elements: [
          OcrElement(
            text: 'DeliveryNote',
            left: 100,
            top: 20,
            right: 280,
            bottom: 40,
          ),
          OcrElement(
            text: '5319364114',
            left: 400,
            top: 20,
            right: 560,
            bottom: 40,
          ),
          OcrElement(text: '1 / 4', left: 900, top: 20, right: 970, bottom: 40),
          OcrElement(
            text: 'Piece:62',
            left: 100,
            top: 200,
            right: 200,
            bottom: 220,
          ),
          OcrElement(
            text: '123456',
            left: 400,
            top: 300,
            right: 480,
            bottom: 320,
          ),
        ],
      ),
      printedPageHint: 1,
    );
    expect(result.pageRole, 'header');
  });

  test('summary details verify a page when its title is missed', () {
    final result = parser.parse(
      observation: OcrObservation(
        ocrRunId: 'missed_title',
        pageCaptureId: 'missed_title_page',
        captureRevision: 1,
        engineName: 'synthetic',
        engineVersion: 'test',
        imageWidth: 1000,
        imageHeight: 1000,
        createdAt: DateTime.utc(2026),
        elements: [
          OcrElement(
            text: '5319364114',
            left: 400,
            top: 20,
            right: 560,
            bottom: 40,
          ),
          OcrElement(text: '1 / 4', left: 900, top: 20, right: 970, bottom: 40),
          OcrElement(
            text: 'Piece:62',
            left: 100,
            top: 200,
            right: 200,
            bottom: 220,
          ),
          OcrElement(
            text: 'Net weight',
            left: 100,
            top: 260,
            right: 220,
            bottom: 280,
          ),
          OcrElement(
            text: '123456',
            left: 400,
            top: 300,
            right: 480,
            bottom: 320,
          ),
        ],
      ),
      printedPageHint: 1,
    );
    expect(result.pageRole, 'header');
  });

  test('summary page remains capturable when Piece label is unreadable', () {
    final result = parser.parse(
      observation: OcrObservation(
        ocrRunId: 'missed_piece',
        pageCaptureId: 'missed_piece_page',
        captureRevision: 1,
        engineName: 'synthetic',
        engineVersion: 'test',
        imageWidth: 1000,
        imageHeight: 1000,
        createdAt: DateTime.utc(2026),
        elements: [
          OcrElement(
            text: '5319364114',
            left: 400,
            top: 20,
            right: 560,
            bottom: 40,
          ),
          OcrElement(text: '1 / 4', left: 900, top: 20, right: 970, bottom: 40),
          OcrElement(
            text: 'Net weight',
            left: 100,
            top: 260,
            right: 220,
            bottom: 280,
          ),
          OcrElement(
            text: 'Gross weight',
            left: 100,
            top: 300,
            right: 230,
            bottom: 320,
          ),
        ],
      ),
      printedPageHint: 1,
    );
    expect(result.pageRole, 'header');
    expect(result.pieceCount, isNull);
  });

  test('accepts TotalQty joined by OCR and extracts its quantity', () {
    final result = parser.parse(
      observation: OcrObservation(
        ocrRunId: 'joined_qty',
        pageCaptureId: 'joined_qty_page',
        captureRevision: 1,
        engineName: 'synthetic',
        engineVersion: 'test',
        imageWidth: 1000,
        imageHeight: 1000,
        createdAt: DateTime.utc(2026),
        elements: [
          OcrElement(
            text: 'TotalQty',
            left: 800,
            top: 10,
            right: 900,
            bottom: 30,
          ),
          OcrElement(
            text: 'BLUE PRODUCT',
            left: 100,
            top: 100,
            right: 300,
            bottom: 120,
          ),
          OcrElement(
            text: '5 PC',
            left: 820,
            top: 100,
            right: 880,
            bottom: 120,
          ),
          OcrElement(
            text: '111111',
            left: 180,
            top: 140,
            right: 260,
            bottom: 160,
          ),
        ],
      ),
      printedPageHint: 2,
    );
    expect(result.pageRole, 'product_table');
    expect(result.occurrences.single.documentQuantity, 5);
  });

  test('table headers verify a page when title and Total Qty are missed', () {
    final result = parser.parse(
      observation: OcrObservation(
        ocrRunId: 'missed_labels',
        pageCaptureId: 'missed_labels_page',
        captureRevision: 1,
        engineName: 'synthetic',
        engineVersion: 'test',
        imageWidth: 1000,
        imageHeight: 1000,
        createdAt: DateTime.utc(2026),
        elements: [
          OcrElement(text: 'Item', left: 50, top: 10, right: 100, bottom: 30),
          OcrElement(
            text: 'Description',
            left: 130,
            top: 10,
            right: 300,
            bottom: 30,
          ),
          OcrElement(
            text: 'BLUE PRODUCT',
            left: 100,
            top: 100,
            right: 300,
            bottom: 120,
          ),
          OcrElement(
            text: '5 PC',
            left: 820,
            top: 100,
            right: 880,
            bottom: 120,
          ),
          OcrElement(
            text: '111111',
            left: 180,
            top: 140,
            right: 260,
            bottom: 160,
          ),
        ],
      ),
      printedPageHint: 2,
    );
    expect(result.pageRole, 'product_table');
    expect(result.occurrences.single.documentQuantity, 5);
  });

  test(
    'insufficient OCR evidence asks for recapture, not unsupported document',
    () {
      final result = parser.parse(
        observation: OcrObservation(
          ocrRunId: 'unreadable',
          pageCaptureId: 'unreadable_page',
          captureRevision: 1,
          engineName: 'synthetic',
          engineVersion: 'test',
          imageWidth: 1000,
          imageHeight: 1000,
          createdAt: DateTime.utc(2026),
          elements: [
            OcrElement(
              text: '5319364114',
              left: 400,
              top: 20,
              right: 560,
              bottom: 40,
            ),
            OcrElement(
              text: '1 / 4',
              left: 900,
              top: 20,
              right: 970,
              bottom: 40,
            ),
          ],
        ),
        printedPageHint: 1,
      );
      expect(result.pageRole, 'unverified_layout');
      expect(result.issues.single, contains('retake'));
    },
  );

  test('page 3 separate colour digit and Total Qty resolves 445386 to 8', () {
    final result = parser.parse(
      observation: OcrObservation(
        ocrRunId: 'page3_separate_total',
        pageCaptureId: 'page3_separate_total',
        captureRevision: 1,
        engineName: 'synthetic',
        engineVersion: 'test',
        imageWidth: 1224,
        imageHeight: 1584,
        createdAt: DateTime.utc(2026),
        elements: [
          OcrElement(
            text: 'Total Qty',
            left: 720,
            top: 450,
            right: 805,
            bottom: 475,
          ),
          OcrElement(
            text: 'S RINE 48 RED',
            left: 150,
            top: 1350,
            right: 300,
            bottom: 1375,
          ),
          OcrElement(
            text: '618805ID1500',
            left: 350,
            top: 1350,
            right: 495,
            bottom: 1375,
          ),
          OcrElement(
            text: 'RED / SIGMA 6',
            left: 590,
            top: 1350,
            right: 715,
            bottom: 1375,
          ),
          OcrElement(
            text: '8 PC',
            left: 720,
            top: 1350,
            right: 775,
            bottom: 1375,
          ),
          OcrElement(
            text: '445386',
            left: 150,
            top: 1390,
            right: 225,
            bottom: 1415,
          ),
          OcrElement(
            text: '5 PC',
            left: 720,
            top: 1460,
            right: 775,
            bottom: 1485,
          ),
          OcrElement(
            text: '3 PC',
            left: 720,
            top: 1500,
            right: 775,
            bottom: 1525,
          ),
        ],
      ),
      printedPageHint: 3,
    );
    expect(result.occurrences.single.articleNumber, '445386');
    expect(result.occurrences.single.documentQuantity, 8);
    expect(result.issues, isEmpty);
  });

  test(
    'fused colour digit and quantity requires source review and can be corrected',
    () {
      final result = parser.parse(
        observation: OcrObservation(
          ocrRunId: 'fused',
          pageCaptureId: 'fused_page',
          captureRevision: 1,
          engineName: 'synthetic',
          engineVersion: 'test',
          imageWidth: 1000,
          imageHeight: 1000,
          createdAt: DateTime.utc(2026),
          elements: [
            OcrElement(
              text: 'Delivery Note',
              left: 500,
              top: 20,
              right: 650,
              bottom: 40,
            ),
            OcrElement(
              text: '5319364114',
              left: 660,
              top: 20,
              right: 790,
              bottom: 40,
            ),
            OcrElement(
              text: '1 / 1',
              left: 850,
              top: 20,
              right: 950,
              bottom: 40,
            ),
            OcrElement(
              text: 'Total Qty',
              left: 800,
              top: 100,
              right: 920,
              bottom: 125,
            ),
            OcrElement(
              text: 'S RINE 48 RED',
              left: 120,
              top: 200,
              right: 390,
              bottom: 225,
            ),
            OcrElement(
              text: '68 PC',
              left: 400,
              top: 200,
              right: 900,
              bottom: 225,
            ),
            OcrElement(
              text: '445386',
              left: 200,
              top: 240,
              right: 290,
              bottom: 265,
            ),
            OcrElement(
              text: '5 PC',
              left: 820,
              top: 300,
              right: 880,
              bottom: 325,
            ),
            OcrElement(
              text: '3 PC',
              left: 820,
              top: 340,
              right: 880,
              bottom: 365,
            ),
          ],
        ),
        printedPageHint: 1,
      );
      expect(result.occurrences.single.role, OccurrenceRole.unresolved);
      expect(result.occurrences.single.documentQuantity, isNull);
      expect(
        result.occurrences.single.issues,
        contains('AMBIGUOUS_COLOUR_QTY_BOUNDARY'),
      );
      expect(isSourceCorrectableTotalQty(result.occurrences.single), isTrue);
      final correction = DocumentLine(
        occurrenceId: result.occurrences.single.occurrenceId,
        sessionId: 'source_review',
        articleNumber: '445386',
        documentQuantity: 8,
        physicalQuantity: 8,
        physicalOrigin: PhysicalQuantityOrigin.defaultedFromDocument,
        sourcePage: 1,
        pageCaptureId: 'fused_page',
        rawOcrArticle: '445386',
        rawOcrQuantity: null,
      );
      final reviewed = applySavedTotalCorrections(result, [correction]);
      expect(reviewed.occurrences.single.role, OccurrenceRole.quantityBearing);
      expect(reviewed.occurrences.single.documentQuantity, 8);
      expect(reviewed.issues, isEmpty);
      final document = consolidator.consolidate(
        sessionId: 'source_review',
        pages: [reviewed],
      );
      expect(document.lines.single.documentQuantity, 8);
      expect(document.blockingIssues, isEmpty);
    },
  );

  test('page-level Batch header does not discard product rows', () {
    final result = parser.parse(
      observation: OcrObservation(
        ocrRunId: 'r',
        pageCaptureId: 'c',
        captureRevision: 1,
        engineName: 'synthetic',
        engineVersion: 't',
        imageWidth: 1000,
        imageHeight: 1000,
        createdAt: DateTime.utc(2026),
        elements: [
          OcrElement(text: 'Total', left: 800, top: 10, right: 860, bottom: 30),
          OcrElement(text: 'Qty', left: 870, top: 10, right: 920, bottom: 30),
          OcrElement(text: 'Qty', left: 600, top: 10, right: 640, bottom: 30),
          OcrElement(text: 'per', left: 650, top: 10, right: 690, bottom: 30),
          OcrElement(text: 'Batch', left: 700, top: 10, right: 780, bottom: 30),
          OcrElement(
            text: 'PROD A',
            left: 100,
            top: 80,
            right: 200,
            bottom: 100,
          ),
          OcrElement(text: '5', left: 820, top: 80, right: 850, bottom: 100),
          OcrElement(text: 'PC', left: 860, top: 80, right: 900, bottom: 100),
          OcrElement(
            text: '111111',
            left: 180,
            top: 110,
            right: 260,
            bottom: 130,
          ),
          OcrElement(text: '1', left: 900, top: 5, right: 920, bottom: 25),
          OcrElement(text: '/', left: 925, top: 5, right: 940, bottom: 25),
          OcrElement(text: '1', left: 945, top: 5, right: 965, bottom: 25),
        ],
      ),
      printedPageHint: 1,
    );
    final qty = result.occurrences
        .where((o) => o.articleNumber == '111111' && o.isQuantityBearing)
        .toList();
    expect(qty.length, 1);
    expect(qty.first.documentQuantity, 5);
  });
}
