import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:label_reader/features/ppg_delivery_note/domain/local_submission.dart';
import 'package:label_reader/features/ppg_delivery_note/domain/models.dart';
import 'package:label_reader/features/ppg_delivery_note/parser/consolidator.dart';
import 'package:label_reader/features/ppg_delivery_note/parser/ppg_template_parser.dart';

void main() {
  final reference =
      jsonDecode(
            File(
              '../ppg_handoff/fixtures/dn_5319358250.expected.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final parser = PpgTemplateParser();

  OcrElement element(String text, double left, double top, double right) =>
      OcrElement(
        text: text,
        left: left,
        top: top,
        right: right,
        bottom: top + 25,
      );

  OcrObservation syntheticPage(int page) {
    final elements = <OcrElement>[
      element('Delivery Note', 600, 30, 790),
      element(reference['delivery_note_number'] as String, 800, 30, 970),
      element('Page : $page / 6', 1000, 30, 1140),
    ];
    if (page == 1) {
      elements.add(element('Piece:100', 80, 200, 210));
    } else {
      elements.addAll([
        // These address lines are printed above the table on every product
        // page of the PDF. Both postcode tokens used to look like articles.
        element('1400 COLOMBO', 200, 60, 380),
        element('0000 COLOMBO', 520, 80, 700),
        element('Item', 40, 100, 90),
        element('Description', 120, 100, 300),
        element('Total Qty', 900, 100, 1020),
        element('Qty per Batch', 700, 130, 850),
      ]);
    }

    final rows = (reference['quantity_bearing_occurrences'] as List)
        .cast<Map<String, dynamic>>()
        .where((row) => row['page'] == page)
        .toList();
    final headings = (reference['quantity_less_headings'] as List)
        .cast<Map<String, dynamic>>()
        .where((row) => row['page'] == page)
        .toList();

    final positions = <int, List<double>>{
      2: [280, 470],
      3: [160, 340, 700],
      4: [160, 550, 750],
      5: [160, 350, 540],
      6: [160, 350, 540],
    };
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final y = positions[page]![i];
      elements.addAll([
        element(row['context'] as String, 120, y, 520),
        element('${row['total_qty']} PC', 920, y, 990),
        element(row['article_number'] as String, 200, y + 40, 290),
        element('871624299825', 500, y + 40, 680),
      ]);
      if (page == 2 && row['article_number'] == '445276') {
        // Printed material and colour fields share the description baseline.
        elements.addAll([
          element('517705ID2176', 540, y, 650),
          element('GREY / SIGMA', 670, y, 800),
        ]);
      }
      if (page == 3 && row['article_number'] == '475210') {
        elements.addAll([
          element('Batch', 300, y + 95, 360),
          element('13 PC', 920, y + 95, 990),
          element('2 PC', 920, y + 125, 990),
        ]);
      }
    }
    final headingPositions = <int, List<double>>{
      2: [160, 700],
      3: [550],
      4: [400],
    };
    for (var i = 0; i < headings.length; i++) {
      final heading = headings[i];
      final y = headingPositions[page]![i];
      elements.addAll([
        element(heading['context'] as String, 120, y, 520),
        element(heading['article_number'] as String, 200, y + 40, 290),
      ]);
    }
    return OcrObservation(
      ocrRunId: 'synthetic_$page',
      pageCaptureId: 'capture_$page',
      captureRevision: 1,
      engineName: 'synthetic_manual_reference',
      engineVersion: '1',
      imageWidth: 1224,
      imageHeight: 1584,
      elements: elements,
      createdAt: DateTime.utc(2026, 9, 24),
    );
  }

  test(
    'six-page Delivery Note keeps all printed occurrences and set context',
    () {
      final parsed = [6, 3, 1, 4, 2, 5].map((page) {
        return parser.parse(
          observation: syntheticPage(page),
          printedPageHint: page,
        );
      }).toList();
      expect(parsed.every((p) => p.printedPageDetected), isTrue);
      expect(parsed.every((p) => p.declaredPageCount == 6), isTrue);
      expect(parsed.firstWhere((p) => p.printedPage == 1).pageRole, 'header');
      expect(
        parsed.firstWhere((p) => p.printedPage == 1).pieceCount,
        reference['page_1_piece_summary'],
      );

      final document = PpgConsolidator().consolidate(
        sessionId: 'six_page_note',
        pages: parsed,
      );
      final expectedRows = (reference['quantity_bearing_occurrences'] as List)
          .cast<Map<String, dynamic>>();
      expect(document.blockingIssues, isEmpty);
      expect(document.lines.length, expectedRows.length);
      expect(document.lines.map((l) => l.articleNumber).toSet().length, 13);
      expect(
        document.lines.fold<int>(0, (sum, l) => sum + l.documentQuantity),
        100,
      );
      expect(document.contexts.length, 4);
      for (final expected in expectedRows) {
        expect(
          document.lines
              .where(
                (line) =>
                    line.sourcePage == expected['page'] &&
                    line.articleNumber == expected['article_number'] &&
                    line.documentQuantity == expected['total_qty'],
              )
              .length,
          1,
          reason: 'Missing or duplicated source row $expected',
        );
      }
      expect(
        document.lines
            .where((l) => l.articleNumber == '475210')
            .map((l) => l.documentQuantity)
            .toList(),
        [15, 5],
      );
      final again = parser.parse(
        observation: syntheticPage(3),
        printedPageHint: 3,
      );
      expect(
        again.occurrences.map((o) => o.occurrenceId),
        parsed
            .firstWhere((p) => p.printedPage == 3)
            .occurrences
            .map((o) => o.occurrenceId),
      );
    },
  );

  test(
    'page count conflict and out-of-range captures block local submission',
    () {
      final session = ScanSession(
        id: 's',
        status: ScanSessionStatus.reviewing,
        formRevision: 2,
        reviewConfirmedRevision: 2,
        deliveryNoteNumber: '5319358250',
        declaredPageCount: 1,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      final capture = PageCapture(
        pageCaptureId: 'c',
        sessionId: 's',
        printedPage: 2,
        captureRevision: 1,
        isActive: true,
        createdAt: DateTime.utc(2026),
        ocrStatus: PageOcrStatus.succeeded,
        pageIdentityConfirmed: true,
        suggestedDeclaredPageCount: 6,
        observedDeliveryNoteNumber: '5319358250',
      );
      final errors = LocalSubmissionService().validateForSubmit(
        session: session,
        lines: const [],
        activePages: [capture],
        blockingIssues: const [],
        rejectIllustrativeFixture: false,
      );
      expect(
        errors.any((e) => e.contains('outside declared page range')),
        isTrue,
      );
      expect(
        errors.any((e) => e.contains('total page count is unresolved')),
        isTrue,
      );
    },
  );

  test('implausible OCR page counter is left for operator confirmation', () {
    final page = syntheticPage(2);
    final elements = page.elements
        .map(
          (e) => e.text.startsWith('Page :')
              ? element('Page : 2 / 999999', e.left, e.top, e.right)
              : e,
        )
        .toList();
    final observation = OcrObservation(
      ocrRunId: 'bad_counter',
      pageCaptureId: 'bad_counter_capture',
      captureRevision: 1,
      engineName: 'synthetic',
      engineVersion: 'test',
      imageWidth: page.imageWidth,
      imageHeight: page.imageHeight,
      elements: elements,
      createdAt: DateTime.utc(2026, 9, 24),
    );
    final parsed = parser.parse(observation: observation, printedPageHint: 2);
    expect(parsed.printedPageDetected, isFalse);
    expect(parsed.declaredPageCount, isNull);
  });
}
