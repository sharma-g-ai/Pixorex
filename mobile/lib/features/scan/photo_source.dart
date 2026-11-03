import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Where photos come from: the in-app camera (viewfinder + shutter), the gallery or the
/// phone's own camera app. A seam so screens can be tested without a camera.
/// Each call returns the raw bytes, or null when the technician backs out.
abstract class PhotoSource {
  Widget viewfinder({required String hint});
  Future<Uint8List?> shutter();
  Future<Uint8List?> gallery();
  Future<Uint8List?> systemCamera();
  Future<void> dispose();
}

class PhotoSourceException implements Exception {
  const PhotoSourceException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The phone's back camera through the `camera` plugin, plus `image_picker`.
class DevicePhotoSource implements PhotoSource {
  DevicePhotoSource({ImagePicker? picker}) : _picker = picker ?? ImagePicker();
  final ImagePicker _picker;
  final _ready = ValueNotifier<CameraController?>(null);
  final _problem = ValueNotifier<String?>(null);
  Future<void>? _starting;

  Future<void> _start() => _starting ??= () async {
        try {
          final cameras = await availableCameras();
          final back = cameras.where((c) => c.lensDirection == CameraLensDirection.back).firstOrNull ??
              cameras.firstOrNull;
          if (back == null) {
            _problem.value = 'No camera found. Use Gallery instead.';
            return;
          }
          final c = CameraController(back, ResolutionPreset.veryHigh,
              enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
          await c.initialize();
          _ready.value = c;
        } on CameraException catch (e) {
          _problem.value = e.code.contains('AccessDenied')
              ? 'Camera access is off. Allow it in Settings, or use Gallery.'
              : "The camera didn't start. Close and reopen New scan, or use Gallery.";
        }
      }();

  @override
  Widget viewfinder({required String hint}) {
    _start();
    return ValueListenableBuilder<String?>(
      valueListenable: _problem,
      builder: (context, problem, _) => ValueListenableBuilder<CameraController?>(
        valueListenable: _ready,
        builder: (context, c, _) => Stack(fit: StackFit.expand, children: [
          if (c != null)
            ClipRect(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  // Preview size is landscape; the phone is held upright.
                  width: c.value.previewSize?.height ?? 1,
                  height: c.value.previewSize?.width ?? 1,
                  child: CameraPreview(c),
                ),
              ),
            )
          else if (problem == null)
            const Center(child: CircularProgressIndicator(color: Colors.white54)),
          const FrameOverlay(),
          Center(child: _Hint(problem ?? hint)),
        ]),
      ),
    );
  }

  @override
  Future<Uint8List?> shutter() async {
    final c = _ready.value;
    if (c == null || c.value.isTakingPicture) return null;
    try {
      return await (await c.takePicture()).readAsBytes();
    } on CameraException {
      throw const PhotoSourceException("The photo wasn't taken. Hold steady and try again.");
    }
  }

  @override
  Future<Uint8List?> gallery() => _pick(ImageSource.gallery);

  @override
  Future<Uint8List?> systemCamera() => _pick(ImageSource.camera);

  /// `imageQuality` makes iOS hand back a JPEG instead of HEIC.
  Future<Uint8List?> _pick(ImageSource source) async =>
      (await _picker.pickImage(source: source, imageQuality: 92, requestFullMetadata: false))?.readAsBytes();

  @override
  Future<void> dispose() async {
    await _starting;
    await _ready.value?.dispose();
    _ready.value = null;
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
        child: Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Colors.white)),
      );
}

/// Dims everything outside a centred frame and marks its corners (from the POC app).
class FrameOverlay extends StatelessWidget {
  const FrameOverlay({super.key});

  @override
  Widget build(BuildContext context) => IgnorePointer(child: CustomPaint(painter: _FramePainter(), size: Size.infinite));
}

class _FramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTRB(size.width * 0.08, size.height * 0.2, size.width * 0.92, size.height * 0.8);
    final dim = Paint()..color = Colors.black.withValues(alpha: 0.4);
    canvas
      ..drawRect(Rect.fromLTRB(0, 0, size.width, rect.top), dim)
      ..drawRect(Rect.fromLTRB(0, rect.bottom, size.width, size.height), dim)
      ..drawRect(Rect.fromLTRB(0, rect.top, rect.left, rect.bottom), dim)
      ..drawRect(Rect.fromLTRB(rect.right, rect.top, size.width, rect.bottom), dim);

    final corner = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const len = 28.0;
    for (final (p, dx, dy) in [
      (rect.topLeft, 1.0, 1.0),
      (rect.topRight, -1.0, 1.0),
      (rect.bottomLeft, 1.0, -1.0),
      (rect.bottomRight, -1.0, -1.0),
    ]) {
      canvas
        ..drawLine(p, p.translate(len * dx, 0), corner)
        ..drawLine(p, p.translate(0, len * dy), corner);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
