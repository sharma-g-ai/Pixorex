import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

enum DocumentEnhancement { original, color, grayscale, blackAndWhite }

/// Four-point perspective warp + rotation helpers for PPG page evidence.
class PerspectiveWarp {
  /// [corners] are TL, TR, BR, BL in source image pixel coordinates.
  static Future<Uint8List> warpToPng({
    required ui.Image image,
    required List<OffsetXY> corners,
    int maxEdge = 3000,
  }) async {
    assert(corners.length == 4);
    final tl = corners[0];
    final tr = corners[1];
    final br = corners[2];
    final bl = corners[3];

    final widthA = _dist(br, bl);
    final widthB = _dist(tr, tl);
    final heightA = _dist(tr, br);
    final heightB = _dist(tl, bl);
    final naturalW = math.max(widthA, widthB);
    final naturalH = math.max(heightA, heightB);
    if (naturalW < 32 || naturalH < 32 || maxEdge < 32) {
      throw ArgumentError('Page corners are too close together');
    }
    final scale = math.min(1.0, maxEdge / math.max(naturalW, naturalH));
    final outW = math.max(1, (naturalW * scale).round());
    final outH = math.max(1, (naturalH * scale).round());

    // Map output square coordinates back into the source quadrilateral with a
    // projective transform. Bilinear interpolation bends straight text lines.
    final dx1 = tr.x - br.x;
    final dx2 = bl.x - br.x;
    final dx3 = tl.x - tr.x + br.x - bl.x;
    final dy1 = tr.y - br.y;
    final dy2 = bl.y - br.y;
    final dy3 = tl.y - tr.y + br.y - bl.y;
    double g = 0;
    double h = 0;
    if (dx3.abs() + dy3.abs() > 1e-8) {
      final determinant = dx1 * dy2 - dx2 * dy1;
      if (determinant.abs() < 1e-8) {
        throw ArgumentError('Page corners do not form a usable quadrilateral');
      }
      g = (dx3 * dy2 - dx2 * dy3) / determinant;
      h = (dx1 * dy3 - dx3 * dy1) / determinant;
    }
    final a = tr.x - tl.x + g * tr.x;
    final b = bl.x - tl.x + h * bl.x;
    final c = tl.x;
    final d = tr.y - tl.y + g * tr.y;
    final e = bl.y - tl.y + h * bl.y;
    final f = tl.y;

    // Preserve aspect from the quad without forcing A4.
    final srcBytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (srcBytes == null) {
      throw StateError('Could not read image pixels');
    }
    final src = srcBytes.buffer.asUint8List();
    final srcW = image.width;
    final srcH = image.height;

    final dst = await compute(warpDocumentRgba, <String, Object>{
      'src': src,
      'srcW': srcW,
      'srcH': srcH,
      'outW': outW,
      'outH': outH,
      'g': g,
      'h': h,
      'a': a,
      'b': b,
      'c': c,
      'd': d,
      'e': e,
      'f': f,
    });

    final completerImage = await _encodeRgba(dst, outW, outH);
    final png = await completerImage.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) throw StateError('PNG encode failed');
    return png.buffer.asUint8List();
  }

  /// Applies scanner-style local illumination correction after crop/warp.
  /// Pixel work runs in a background isolate so large camera photos do not
  /// freeze the review screen. The original source image is never modified.
  static Future<Uint8List> enhancePng(
    Uint8List sourcePng,
    DocumentEnhancement mode,
  ) async {
    if (mode == DocumentEnhancement.original) return sourcePng;
    final codec = await ui.instantiateImageCodec(sourcePng);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) throw StateError('Could not read warped image');
    final rgba = byteData.buffer.asUint8List();
    final enhanced = await compute(enhanceDocumentRgba, <String, Object>{
      'rgba': rgba,
      'width': image.width,
      'height': image.height,
      'mode': mode.name,
    });
    final buffer = await ui.ImmutableBuffer.fromUint8List(enhanced);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: image.width,
      height: image.height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final outputCodec = await descriptor.instantiateCodec();
    final output = await outputCodec.getNextFrame();
    final png = await output.image.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) throw StateError('Enhanced image encode failed');
    return png.buffer.asUint8List();
  }

  static Future<ui.Image> rotateImage(ui.Image image, int degrees) async {
    final d = degrees % 360;
    if (d == 0) return image;
    final radians = d * math.pi / 180.0;
    final w = image.width.toDouble();
    final h = image.height.toDouble();
    final outW = (d % 180 == 0) ? image.width : image.height;
    final outH = (d % 180 == 0) ? image.height : image.width;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.translate(outW / 2, outH / 2);
    canvas.rotate(radians);
    canvas.translate(-w / 2, -h / 2);
    canvas.drawImage(image, ui.Offset.zero, ui.Paint());
    final picture = recorder.endRecording();
    return picture.toImage(outW, outH);
  }

  static double _dist(OffsetXY a, OffsetXY b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  static List<int> _sampleBilinear(
    Uint8List src,
    int w,
    int h,
    double x,
    double y,
  ) {
    if (x < 0 || y < 0 || x >= w - 1 || y >= h - 1) {
      final cx = x.clamp(0, w - 1).floor();
      final cy = y.clamp(0, h - 1).floor();
      final i = (cy * w + cx) * 4;
      return [src[i], src[i + 1], src[i + 2], src[i + 3]];
    }
    final x0 = x.floor();
    final y0 = y.floor();
    final x1 = x0 + 1;
    final y1 = y0 + 1;
    final fx = x - x0;
    final fy = y - y0;
    List<int> px(int ix, int iy) {
      final i = (iy * w + ix) * 4;
      return [src[i], src[i + 1], src[i + 2], src[i + 3]];
    }

    final c00 = px(x0, y0);
    final c10 = px(x1, y0);
    final c01 = px(x0, y1);
    final c11 = px(x1, y1);
    final out = List<int>.filled(4, 0);
    for (var k = 0; k < 4; k++) {
      final top = c00[k] * (1 - fx) + c10[k] * fx;
      final bot = c01[k] * (1 - fx) + c11[k] * fx;
      out[k] = (top * (1 - fy) + bot * fy).round().clamp(0, 255);
    }
    return out;
  }

  static Future<ui.Image> _encodeRgba(Uint8List rgba, int w, int h) async {
    final completer = ui.ImmutableBuffer.fromUint8List(rgba);
    final buffer = await completer;
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: w,
      height: h,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();
    return frame.image;
  }
}

Uint8List warpDocumentRgba(Map<String, Object> request) {
  final src = request['src']! as Uint8List;
  final srcW = request['srcW']! as int;
  final srcH = request['srcH']! as int;
  final outW = request['outW']! as int;
  final outH = request['outH']! as int;
  final g = request['g']! as double;
  final h = request['h']! as double;
  final a = request['a']! as double;
  final b = request['b']! as double;
  final c = request['c']! as double;
  final d = request['d']! as double;
  final e = request['e']! as double;
  final f = request['f']! as double;
  final dst = Uint8List(outW * outH * 4);
  for (var y = 0; y < outH; y++) {
    final v = (y + 0.5) / outH;
    for (var x = 0; x < outW; x++) {
      final u = (x + 0.5) / outW;
      final denominator = g * u + h * v + 1;
      if (denominator.abs() < 1e-8) {
        throw ArgumentError('Page corners produce an invalid perspective');
      }
      final srcX = (a * u + b * v + c) / denominator;
      final srcY = (d * u + e * v + f) / denominator;
      final color = PerspectiveWarp._sampleBilinear(
        src,
        srcW,
        srcH,
        srcX,
        srcY,
      );
      final di = (y * outW + x) * 4;
      dst[di] = color[0];
      dst[di + 1] = color[1];
      dst[di + 2] = color[2];
      dst[di + 3] = color[3];
    }
  }
  return dst;
}

/// High-frequency text edge score for a downscaled capture preview.
/// A very low score warns that small printed characters may be unreadable.
double estimateTextSharpnessRgba(Map<String, Object> request) {
  final pixels = request['rgba']! as Uint8List;
  final width = request['width']! as int;
  final height = request['height']! as int;
  if (width < 5 || height < 5) return 0;
  int luma(int x, int y) {
    final i = (y * width + x) * 4;
    return ((pixels[i] * 77 + pixels[i + 1] * 150 + pixels[i + 2] * 29) >> 8);
  }

  var total = 0;
  var count = 0;
  for (var y = 2; y < height - 2; y += 2) {
    for (var x = 2; x < width - 2; x += 2) {
      total +=
          (4 * luma(x, y) -
                  luma(x - 1, y) -
                  luma(x + 1, y) -
                  luma(x, y - 1) -
                  luma(x, y + 1))
              .abs();
      count++;
    }
  }
  return count == 0 ? 0 : total / count;
}

Uint8List enhanceDocumentRgba(Map<String, Object> request) {
  final rgba = request['rgba']! as Uint8List;
  final width = request['width']! as int;
  final height = request['height']! as int;
  final mode = request['mode']! as String;
  final stride = width + 1;
  final luma = Uint8List(width * height);
  final integral = Uint32List(stride * (height + 1));

  for (var y = 0; y < height; y++) {
    var rowSum = 0;
    for (var x = 0; x < width; x++) {
      final pixel = (y * width + x) * 4;
      final value =
          (rgba[pixel] * 0.299 +
                  rgba[pixel + 1] * 0.587 +
                  rgba[pixel + 2] * 0.114)
              .round();
      luma[y * width + x] = value;
      rowSum += value;
      integral[(y + 1) * stride + x + 1] =
          rowSum + integral[y * stride + x + 1];
    }
  }

  int localMean(int x, int y, int radius) {
    final left = math.max(0, x - radius);
    final top = math.max(0, y - radius);
    final right = math.min(width, x + radius + 1);
    final bottom = math.min(height, y + radius + 1);
    final sum =
        integral[bottom * stride + right] -
        integral[top * stride + right] -
        integral[bottom * stride + left] +
        integral[top * stride + left];
    return sum ~/ ((right - left) * (bottom - top));
  }

  final result = Uint8List.fromList(rgba);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final sourceIndex = y * width + x;
      final pixel = sourceIndex * 4;
      final originalLuma = luma[sourceIndex];
      int correctedLuma;
      if (mode == DocumentEnhancement.blackAndWhite.name) {
        final mean = localMean(x, y, 24);
        correctedLuma = originalLuma < mean - 10 ? 0 : 255;
      } else {
        final mean = localMean(x, y, 64);
        // Raise shaded paper toward white while increasing local text contrast.
        correctedLuma = (232 + (originalLuma - mean) * 1.18).round().clamp(
          0,
          255,
        );
      }
      if (mode == DocumentEnhancement.grayscale.name ||
          mode == DocumentEnhancement.blackAndWhite.name) {
        result[pixel] = correctedLuma;
        result[pixel + 1] = correctedLuma;
        result[pixel + 2] = correctedLuma;
      } else {
        final delta = correctedLuma - originalLuma;
        result[pixel] = (rgba[pixel] + delta).clamp(0, 255);
        result[pixel + 1] = (rgba[pixel + 1] + delta).clamp(0, 255);
        result[pixel + 2] = (rgba[pixel + 2] + delta).clamp(0, 255);
      }
    }
  }
  return result;
}

class OffsetXY {
  const OffsetXY(this.x, this.y);
  final double x;
  final double y;
}
