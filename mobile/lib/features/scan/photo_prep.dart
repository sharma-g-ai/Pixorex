import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'scan_repository.dart';

/// Longest side kept: enough for small nameplate text, well under the 2 MB limit.
const maxSide = 2400;

class PhotoPrepException implements Exception {
  const PhotoPrepException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Any photo the phone gives us → a JPEG the API accepts (contract 2.22: JPEG, ≤ 2 MB).
/// Runs off the UI thread; decoding a 12 MP photo takes a moment.
Future<Uint8List> prepareJpeg(Uint8List bytes) => Isolate.run(() => prepareJpegSync(bytes));

Uint8List prepareJpegSync(Uint8List bytes, {int limit = ScanRepository.maxPhotoBytes}) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const PhotoPrepException("This photo can't be read. Take it again or pick another one.");
  }
  // Camera JPEGs are often stored sideways with an EXIF turn; bake the turn in.
  final ifd = decoded.exif.imageIfd;
  final turned = ifd.hasOrientation && ifd.orientation != 1;
  var image = turned ? img.bakeOrientation(decoded) : decoded;
  final longest = image.width > image.height ? image.width : image.height;
  if (longest > maxSide) {
    image = image.width >= image.height ? img.copyResize(image, width: maxSide) : img.copyResize(image, height: maxSide);
  }
  // Already a small, upright JPEG: send it untouched (no second compression).
  if (identical(image, decoded) && _isJpeg(bytes) && bytes.length <= limit) return bytes;

  for (final quality in const [88, 80, 70, 60, 50]) {
    final out = img.encodeJpg(image, quality: quality);
    if (out.length <= limit) return out;
  }
  // Very busy detail: shrink a quarter at a time rather than fail, down to 1000 px wide.
  while (image.width * 3 ~/ 4 >= 1000) {
    image = img.copyResize(image, width: image.width * 3 ~/ 4);
    final out = img.encodeJpg(image, quality: 60);
    if (out.length <= limit) return out;
  }
  throw const PhotoPrepException('This photo is too large to send. Take it again a little further away.');
}

bool _isJpeg(Uint8List b) => b.length > 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF;
