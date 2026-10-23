import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:label_reader/features/ppg_delivery_note/widgets/perspective_warp.dart';

void main() {
  test('black and white scan keeps dark text and cleans the paper field', () {
    const width = 32;
    const height = 32;
    final rgba = Uint8List(width * height * 4);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final i = (y * width + x) * 4;
        final shade = x < 16 ? 205 : 245;
        final isText = x >= 14 && x <= 17 && y >= 8 && y <= 23;
        final value = isText ? 35 : shade;
        rgba[i] = value;
        rgba[i + 1] = value;
        rgba[i + 2] = value;
        rgba[i + 3] = 255;
      }
    }

    final output = enhanceDocumentRgba({
      'rgba': rgba,
      'width': width,
      'height': height,
      'mode': DocumentEnhancement.blackAndWhite.name,
    });

    expect(output[(16 * width + 15) * 4], 0);
    expect(output[(2 * width + 2) * 4], 255);
    expect(output[(2 * width + 29) * 4], 255);
  });

  test('sharpness check distinguishes clear strokes from a flat page', () {
    const width = 64;
    const height = 64;
    Uint8List pixels(bool withStrokes) {
      final rgba = Uint8List(width * height * 4);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final i = (y * width + x) * 4;
          final stroke = withStrokes && x % 8 < 2 && y > 8 && y < 56;
          final value = stroke ? 30 : 240;
          rgba[i] = value;
          rgba[i + 1] = value;
          rgba[i + 2] = value;
          rgba[i + 3] = 255;
        }
      }
      return rgba;
    }

    final clear = estimateTextSharpnessRgba({
      'rgba': pixels(true),
      'width': width,
      'height': height,
    });
    final flat = estimateTextSharpnessRgba({
      'rgba': pixels(false),
      'width': width,
      'height': height,
    });
    expect(clear, greaterThan(4));
    expect(flat, lessThan(4));
  });
}
