import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../domain/models.dart';

/// On-device OCR via Android bundled ML Kit. No cloud fallback.
class PpgOcrAdapter {
  PpgOcrAdapter({MethodChannel? channel, Uuid? uuid})
    : _channel = channel ?? const MethodChannel('com.amzur.equiptrack/ppg_ocr'),
      _uuid = uuid ?? const Uuid();

  final MethodChannel _channel;
  final Uuid _uuid;

  Future<OcrObservation> recognizeFile({
    required String imagePath,
    required String pageCaptureId,
    required int captureRevision,
  }) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError(
        'Bundled ML Kit OCR is Android-only in this POC. '
        'Use developer image import with synthetic geometry on other platforms.',
      );
    }

    final started = DateTime.now();
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'recognize',
      {'imagePath': imagePath},
    );
    if (result == null) {
      throw StateError('OCR returned null');
    }

    final elements = (result['elements'] as List? ?? [])
        .map((e) => OcrElement.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    final lines = (result['lines'] as List? ?? [])
        .map((e) => OcrElement.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    final symbols = (result['symbols'] as List? ?? [])
        .map((e) => OcrElement.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();

    return OcrObservation(
      ocrRunId: _uuid.v4(),
      pageCaptureId: pageCaptureId,
      captureRevision: captureRevision,
      engineName: result['engineName'] as String? ?? 'mlkit_latin_bundled',
      engineVersion: result['engineVersion'] as String? ?? 'unknown',
      imageWidth: result['imageWidth'] as int? ?? 0,
      imageHeight: result['imageHeight'] as int? ?? 0,
      elements: elements,
      lines: lines,
      symbols: symbols,
      elapsedMs: DateTime.now().difference(started).inMilliseconds,
      createdAt: DateTime.now().toUtc(),
    );
  }

  /// Read a small field in its own OCR pass. Coordinates are source-image
  /// pixels; the Android bridge scales the crop for small printed text.
  Future<OcrObservation> recognizeCrop({
    required String imagePath,
    required String pageCaptureId,
    required int captureRevision,
    required int left,
    required int top,
    required int right,
    required int bottom,
  }) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'recognize',
      {
        'imagePath': imagePath,
        'crop': {'left': left, 'top': top, 'right': right, 'bottom': bottom},
      },
    );
    if (result == null) throw StateError('Field OCR returned null');
    List<OcrElement> read(String key) => (result[key] as List? ?? [])
        .map((e) => OcrElement.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    return OcrObservation(
      ocrRunId: _uuid.v4(),
      pageCaptureId: pageCaptureId,
      captureRevision: captureRevision,
      engineName: result['engineName'] as String? ?? 'mlkit_latin_bundled',
      engineVersion: result['engineVersion'] as String? ?? 'unknown',
      imageWidth: result['imageWidth'] as int? ?? 0,
      imageHeight: result['imageHeight'] as int? ?? 0,
      elements: read('elements'),
      lines: read('lines'),
      symbols: read('symbols'),
      createdAt: DateTime.now().toUtc(),
    );
  }

  /// Developer/test helper: load synthetic OCR JSON for a printed page.
  Future<OcrObservation> loadSyntheticFixture({
    required String assetPath,
    required int printedPage,
    required String pageCaptureId,
    required int captureRevision,
  }) async {
    final raw = await rootBundle.loadString(assetPath);
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final page = (json['pages'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((p) => p['printed_page'] == printedPage);
    final elements = (page['elements'] as List)
        .map((e) => OcrElement.fromJson(e as Map<String, dynamic>))
        .toList();
    return OcrObservation(
      ocrRunId: _uuid.v4(),
      pageCaptureId: pageCaptureId,
      captureRevision: captureRevision,
      engineName: 'synthetic_fixture',
      engineVersion: '1.0',
      imageWidth: page['image_width'] as int,
      imageHeight: page['image_height'] as int,
      elements: elements,
      createdAt: DateTime.now().toUtc(),
    );
  }
}
