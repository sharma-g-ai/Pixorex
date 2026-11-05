import 'dart:math' as math;

import '../domain/models.dart';
import '../parser/ocr_line_builder.dart';

/// A conservative second read of the printed Total Qty cell. Its crop ends
/// above the article and batch rows, so batch quantities cannot be borrowed.
class TotalQtyFieldReader {
  static final RegExp _fieldPattern = RegExp(
    r'^\s*(\d{1,5})\s*P\s*C\s*$',
    caseSensitive: false,
  );

  static ({int left, int top, int right, int bottom})? cropFor(
    ParsedOccurrence occurrence,
    OcrObservation page,
  ) => cropForDimensions(occurrence, page.imageWidth, page.imageHeight);

  static ({int left, int top, int right, int bottom})? cropForDimensions(
    ParsedOccurrence occurrence,
    int imageWidth,
    int imageHeight,
  ) {
    final x = occurrence.quantityColumnLeft;
    final y = occurrence.rowCenterY;
    if (x == null || y == null || imageWidth < 100 || imageHeight < 100) {
      return null;
    }
    final xScale = math.max(1.0, imageWidth / 1224);
    final yScale = math.max(1.0, imageHeight / 1584);
    // Start at the column boundary. Padding must be smaller than the printed
    // colour/quantity gap on this template, even at larger scan resolutions.
    final left = math.max(0, (x - 3 * xScale).floor());
    final top = math.max(0, (y - 23 * yScale).floor());
    final right = math.min(imageWidth, (x + 135 * xScale).ceil());
    final bottom = math.min(imageHeight, (y + 23 * yScale).ceil());
    if (right - left < 24 || bottom - top < 12) return null;
    return (left: left, top: top, right: right, bottom: bottom);
  }

  static int? uniqueQuantity(
    OcrObservation field, {
    int? suspectedFusedQuantity,
  }) {
    final lineTexts = field.lines.isNotEmpty
        ? field.lines.map((line) => line.text)
        : OcrLineBuilder.buildLines(field.elements).map((line) => line.text);
    final found = <int>{};
    for (final text in lineTexts) {
      final match = _fieldPattern.firstMatch(text.trim());
      if (match != null) found.add(int.parse(match.group(1)!));
    }
    if (found.length != 1) return null;
    final value = found.single;
    if (value == suspectedFusedQuantity) return null;
    return value;
  }
}
