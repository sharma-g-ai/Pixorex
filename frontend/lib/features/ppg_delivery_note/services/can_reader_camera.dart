import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/can_article_reader.dart';
import '../domain/models.dart';

/// Live camera that reads the printed Article no. on a paint can. An article
/// is confirmed only after three fresh, agreeing frames, the same rule as the
/// check-in scanner. Reading stops after a confirmation until [scanAgain].
class CanReaderCamera extends ChangeNotifier {
  CanReaderCamera({required this.knownArticles, required this.onConfirmed});

  static const _channel = MethodChannel('com.amzur.equiptrack/ppg_can_ocr');
  static const idleGuidance = 'Show the printed Article no. field on the can.';

  /// Article numbers a split reading may be joined into, e.g. stock on board.
  final Set<String> Function() knownArticles;
  final void Function(String article) onConfirmed;

  final _reader = CanArticleReader();
  final _consensus = CanArticleConsensus();
  CameraController? camera;
  String? cameraError;
  String guidance = idleGuidance;

  /// True after a confirmation, until [scanAgain].
  bool paused = false;

  /// The device cannot scan at all, e.g. not Android.
  bool unsupported = false;

  Future<void> _work = Future.value();
  int _generation = 0;
  bool _active = false;
  bool _busy = false;
  bool _disposed = false;
  DateTime? _lastFrame;
  List<int>? _previousLuma;
  int _misses = 0;
  int _rotationOffset = 0;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void open() => _configure(true);
  void close() => _configure(false);

  /// Stops reading, e.g. while an article chosen by hand is shown.
  void hold() {
    paused = true;
    _consensus.reset();
    _notify();
  }

  void scanAgain() {
    paused = false;
    _consensus.reset();
    _previousLuma = null;
    _lastFrame = null;
    _misses = 0;
    _rotationOffset = 0;
    guidance = idleGuidance;
    _notify();
  }

  Future<void> toggleTorch() async {
    final current = camera;
    if (current == null) return;
    await current.setFlashMode(
      current.value.flashMode == FlashMode.torch
          ? FlashMode.off
          : FlashMode.torch,
    );
    _notify();
  }

  void _configure(bool open) {
    _active = open;
    final generation = ++_generation;
    _work = _work
        .then((_) async {
          final previous = camera;
          camera = null;
          _notify();
          await previous?.dispose();
          if (!open || _disposed || generation != _generation) return;
          if (!Platform.isAndroid) {
            throw UnsupportedError('Can scanning is available on Android.');
          }
          final cameras = await availableCameras();
          if (cameras.isEmpty) throw StateError('No camera available.');
          final description = cameras.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.back,
            orElse: () => cameras.first,
          );
          final next = CameraController(
            description,
            ResolutionPreset.high,
            enableAudio: false,
            imageFormatGroup: ImageFormatGroup.nv21,
          );
          try {
            await next.initialize();
            if (_disposed || generation != _generation) {
              await next.dispose();
              return;
            }
            camera = next;
            await next.startImageStream(_onFrame);
            cameraError = null;
            _notify();
          } catch (_) {
            if (identical(camera, next)) camera = null;
            await next.dispose();
            rethrow;
          }
        })
        .catchError((Object error) {
          debugPrint('Can reader camera failed: $error');
          if (!_disposed && generation == _generation) {
            unsupported = error is UnsupportedError;
            cameraError = unsupported
                ? 'Can scanning works on Android devices only.'
                : 'The camera could not start. Try again.';
            _notify();
          }
        });
  }

  /// A coarse motion and exposure gate before spending an OCR pass.
  String? _quality(CameraImage image) {
    final bytes = image.planes.single.bytes;
    final samples = <int>[];
    for (
      var y = image.height ~/ 4;
      y < image.height * 3 ~/ 4;
      y += math.max(1, image.height ~/ 32)
    ) {
      for (
        var x = image.width ~/ 4;
        x < image.width * 3 ~/ 4;
        x += math.max(1, image.width ~/ 32)
      ) {
        samples.add(bytes[y * image.width + x]);
      }
    }
    final mean = samples.reduce((a, b) => a + b) / samples.length;
    final variance =
        samples.fold<double>(0, (sum, v) => sum + (v - mean) * (v - mean)) /
        samples.length;
    final previous = _previousLuma;
    _previousLuma = samples;
    if (mean < 25) {
      return 'More light is needed. Move the can into better light.';
    }
    if (mean > 235 && variance < 250) {
      return 'Reduce glare. Tilt the can or camera slightly.';
    }
    if (variance < 60) {
      return 'Move closer and show the printed Article no. field.';
    }
    if (previous != null && previous.length == samples.length) {
      final motion =
          List.generate(
            samples.length,
            (i) => (samples[i] - previous[i]).abs(),
          ).reduce((a, b) => a + b) /
          samples.length;
      if (motion > 30) {
        return 'Hold the camera steady while reading the article.';
      }
    }
    return null;
  }

  Future<void> _onFrame(CameraImage frame) async {
    final current = camera;
    if (_disposed || !_active || _busy || paused || current == null) return;
    final now = DateTime.now();
    if (_lastFrame != null &&
        now.difference(_lastFrame!).inMilliseconds < 650) {
      return;
    }
    _lastFrame = now;
    if (frame.planes.length != 1 ||
        frame.planes.single.bytes.length !=
            frame.width * frame.height * 3 ~/ 2) {
      cameraError =
          'The camera picture could not be read. Close the scanner and open it again.';
      _notify();
      return;
    }
    final quality = _quality(frame);
    if (quality != null) {
      _consensus.reset();
      guidance = quality;
      _notify();
      return;
    }
    final generation = _generation;
    _busy = true;
    try {
      final deviceRotation = switch (current.value.deviceOrientation) {
        DeviceOrientation.portraitUp => 0,
        DeviceOrientation.landscapeLeft => 90,
        DeviceOrientation.portraitDown => 180,
        DeviceOrientation.landscapeRight => 270,
      };
      final sensor = current.description.sensorOrientation;
      final rotation =
          (sensor +
              (current.description.lensDirection == CameraLensDirection.front
                  ? deviceRotation
                  : -deviceRotation) +
              360 +
              _rotationOffset) %
          360;
      final result = await _channel
          .invokeMapMethod<String, dynamic>('recognizeFrame', {
            'bytes': frame.planes.single.bytes,
            'width': frame.width,
            'height': frame.height,
            'rotation': rotation,
          });
      if (_disposed || !_active || paused || generation != _generation) return;
      if (result == null) throw StateError('No camera OCR result.');
      final lines = (result['lines'] as List)
          .map(
            (line) =>
                OcrElement.fromJson(Map<String, dynamic>.from(line as Map)),
          )
          .toList();
      final candidates = _reader.candidates(
        lines: lines,
        dnArticles: knownArticles(),
        width: result['width'] as int,
        height: result['height'] as int,
      );
      final confirmed = _consensus.observe(candidates, now);
      if (candidates.isEmpty) {
        _misses++;
        // Try another orientation on a later frame, not four passes per frame.
        if (_misses % 3 == 0) _rotationOffset = (_rotationOffset + 90) % 360;
      } else {
        _misses = 0;
      }
      cameraError = null;
      if (confirmed != null) {
        paused = true;
        guidance = 'Article $confirmed read.';
        _notify();
        onConfirmed(confirmed);
        return;
      }
      guidance = _consensus.conflict
          ? 'Conflicting article readings. Keep scanning.'
          : _consensus.candidate != null
          ? 'Reading ${_consensus.candidate} · Hold steady (${_consensus.observations}/3).'
          : 'Article not readable yet. Rotate the can slightly or move closer.';
      _notify();
    } catch (error) {
      debugPrint('Can article reader failed: $error');
      if (!_disposed && generation == _generation) {
        _consensus.reset();
        cameraError = 'The article reader stopped. Try again.';
        _notify();
      }
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _active = false;
    _generation++;
    final current = camera;
    camera = null;
    _work = _work.then((_) => current?.dispose());
    super.dispose();
  }
}
