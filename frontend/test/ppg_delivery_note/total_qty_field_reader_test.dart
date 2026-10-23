import 'package:flutter_test/flutter_test.dart';
import 'package:label_reader/features/ppg_delivery_note/domain/models.dart';
import 'package:label_reader/features/ppg_delivery_note/ocr/total_qty_field_reader.dart';
import 'package:label_reader/features/ppg_delivery_note/parser/ppg_template_parser.dart';

void main() {
  OcrElement word(String text, double left, double top, double right) =>
      OcrElement(
        text: text,
        left: left,
        top: top,
        right: right,
        bottom: top + 25,
      );

  OcrObservation page({Map<String, int> fieldReads = const {}}) =>
      OcrObservation(
        ocrRunId: 'ocr',
        pageCaptureId: 'page3',
        captureRevision: 1,
        engineName: 'test',
        engineVersion: '1',
        imageWidth: 1224,
        imageHeight: 1584,
        elements: [
          word('Delivery Note', 600, 20, 790),
          word('5319364114', 800, 20, 970),
          word('3 / 4', 1040, 20, 1110),
          word('Item', 120, 450, 180),
          word('Description', 280, 450, 420),
          word('Total Qty', 720, 450, 810),
          word('S RINE 48 RED', 150, 1350, 300),
          word('RED / SIGMA 6', 590, 1350, 715),
          word('68 PC', 590, 1350, 775),
          word('445386', 150, 1390, 225),
          word('5 PC', 720, 1460, 775),
          word('3 PC', 720, 1500, 775),
        ],
        fieldQuantityReads: fieldReads,
        createdAt: DateTime.utc(2026),
      );

  test('field crop starts after colour code and above batch quantities', () {
    final parsed = PpgTemplateParser().parse(
      observation: page(),
      printedPageHint: 3,
    );
    final occurrence = parsed.occurrences.single;
    final crop = TotalQtyFieldReader.cropFor(occurrence, page());
    expect(crop, isNotNull);
    expect(crop!.left, greaterThan(713));
    expect(crop.left, lessThanOrEqualTo(720));
    expect(crop.bottom, lessThan(1390));
  });

  test('field retry accepts separate 8 PC but not the same fused 68 PC', () {
    OcrObservation field(String value) => OcrObservation(
      ocrRunId: 'crop',
      pageCaptureId: 'page3',
      captureRevision: 1,
      engineName: 'test',
      engineVersion: '1',
      imageWidth: 250,
      imageHeight: 90,
      elements: [word(value, 10, 10, 90)],
      createdAt: DateTime.utc(2026),
    );
    expect(
      TotalQtyFieldReader.uniqueQuantity(
        field('8 PC'),
        suspectedFusedQuantity: 68,
      ),
      8,
    );
    expect(
      TotalQtyFieldReader.uniqueQuantity(
        field('68 PC'),
        suspectedFusedQuantity: 68,
      ),
      isNull,
    );
  });

  test('saved field read resolves only the matching Total Qty on reopen', () {
    final parser = PpgTemplateParser();
    final raw = parser.parse(observation: page(), printedPageHint: 3);
    expect(raw.occurrences.single.role, OccurrenceRole.unresolved);
    final resolved = parser.parse(
      observation: page(fieldReads: {raw.occurrences.single.occurrenceId: 8}),
      printedPageHint: 3,
    );
    expect(resolved.issues, isEmpty);
    expect(resolved.occurrences.single.documentQuantity, 8);
  });
}
