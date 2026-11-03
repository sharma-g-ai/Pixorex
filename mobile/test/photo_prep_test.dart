import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pixorex_mobile/features/scan/photo_prep.dart';

/// Random-ish pixels compress badly, like a busy nameplate.
img.Image noisy(int w, int h) {
  final image = img.Image(width: w, height: h);
  var seed = 7;
  for (final p in image) {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    p.setRgb(seed & 0xff, (seed >> 8) & 0xff, (seed >> 16) & 0xff);
  }
  return image;
}

bool isJpeg(Uint8List b) => b[0] == 0xFF && b[1] == 0xD8;

void main() {
  test('GIVEN a small JPEG WHEN prepared THEN it is sent as is', () {
    final jpeg = img.encodeJpg(img.Image(width: 800, height: 600), quality: 90);
    expect(identical(prepareJpegSync(jpeg), jpeg), isTrue);
  });

  test('GIVEN a PNG (e.g. a screenshot from the gallery) WHEN prepared THEN it becomes a JPEG', () {
    final png = img.encodePng(img.Image(width: 640, height: 480));
    final out = prepareJpegSync(png);
    expect(isJpeg(out), isTrue);
    expect(img.decodeJpg(out)!.width, 640);
  });

  test('GIVEN a 4000 px photo WHEN prepared THEN the longest side is 2400 and it is under the limit', () {
    final big = img.encodeJpg(img.Image(width: 3000, height: 4000), quality: 95);
    final out = prepareJpegSync(big);
    final back = img.decodeJpg(out)!;
    expect(back.height, maxSide);
    expect(back.width, 1800);
    expect(out.length, lessThanOrEqualTo(2 * 1024 * 1024));
  });

  test('GIVEN busy detail over the limit WHEN prepared THEN quality, then size, steps down until it fits', () {
    final busy = img.encodeJpg(noisy(2000, 1500), quality: 100);
    const limit = 1024 * 1024;
    expect(busy.length, greaterThan(limit));
    final out = prepareJpegSync(busy, limit: limit);
    expect(isJpeg(out), isTrue);
    expect(out.length, lessThanOrEqualTo(limit));
    expect(img.decodeJpg(out)!.width, greaterThanOrEqualTo(1000));
  });

  test('GIVEN bytes that are not a photo WHEN prepared THEN a readable error', () {
    expect(
      () => prepareJpegSync(Uint8List.fromList([1, 2, 3, 4])),
      throwsA(isA<PhotoPrepException>().having((e) => e.message, 'message', contains("can't be read"))),
    );
  });

  test('GIVEN a sideways camera JPEG WHEN prepared THEN the turn is baked in', () {
    final sideways = img.Image(width: 400, height: 300)..exif.imageIfd.orientation = 6; // 90° clockwise
    final out = prepareJpegSync(img.encodeJpg(sideways));
    final back = img.decodeJpg(out)!;
    expect([back.width, back.height], [300, 400]);
  });
}
