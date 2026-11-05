import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../domain/models.dart';
import '../services/ppg_session_controller.dart';
import '../ui/ppg_page_status.dart';
import '../ui/ppg_tokens.dart';
import '../ui/ppg_widgets.dart';
import '../widgets/four_corner_crop.dart';

/// Photographs one DN page. The page is saved into [initialPage] (or the next
/// free slot); its printed page number is read afterwards and confirmed on
/// the page identity screen. Pops with the saved capture id.
class PpgCaptureScreen extends StatefulWidget {
  const PpgCaptureScreen({
    super.key,
    this.initialPage,
    this.newDelivery = false,
    this.operatorEmail,
  });

  final int? initialPage;

  /// Creates the delivery note only when the first page is accepted, so an
  /// abandoned camera leaves nothing behind.
  final bool newDelivery;
  final String? operatorEmail;

  @override
  State<PpgCaptureScreen> createState() => _PpgCaptureScreenState();
}

class _PpgCaptureScreenState extends State<PpgCaptureScreen> {
  CameraController? _camera;
  String? _capturedPath;
  bool _busy = false;
  bool _reading = false;
  String? _error;
  bool _autoMode = false;
  Timer? _autoTimer;
  DateTime? _lastAnalysis;
  DateTime? _steadySince;
  List<int>? _previousLuma;
  bool _pageReady = false;
  bool _documentScannerOutput = false;
  String _autoStatus = 'Place one page inside the guide';

  static const _documentScannerChannel = MethodChannel(
    'com.amzur.equiptrack/document_scanner',
  );

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _error = 'This device has no camera available.');
        return;
      }
      final cam = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        cam,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) return;
      setState(() => _camera = controller);
    } on CameraException catch (e) {
      debugPrint('PPG capture camera failed: ${e.code} ${e.description}');
      if (!mounted) return;
      setState(
        () => _error = e.code.contains('Access')
            ? 'Camera permission is off. Allow camera access in Settings, or choose a photo instead.'
            : 'The camera could not start. Try again, or choose a photo instead.',
      );
    } catch (e) {
      debugPrint('PPG capture camera failed: $e');
      if (!mounted) return;
      setState(
        () => _error =
            'The camera could not start. Try again, or choose a photo instead.',
      );
    }
  }

  Future<void> _retryCamera() async {
    final old = _camera;
    setState(() {
      _error = null;
      _camera = null;
    });
    await old?.dispose();
    await _initCamera();
  }

  Future<void> _pickFromGallery() async {
    if (_busy) return;
    _autoTimer?.cancel();
    _autoTimer = null;
    try {
      if (_camera?.value.isStreamingImages == true) {
        await _camera!.stopImageStream();
      }
    } catch (_) {}
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null || !mounted) {
      if (mounted && _autoMode) _setAutoMode(true);
      return;
    }
    setState(() {
      _autoMode = false;
      _capturedPath = file.path;
      _documentScannerOutput = false;
    });
  }

  void _resetAutoDetection() {
    _autoTimer?.cancel();
    _autoTimer = null;
    _steadySince = null;
    _previousLuma = null;
    _pageReady = false;
  }

  Future<void> _setAutoMode(bool enabled) async {
    if (_busy || _camera == null) return;
    _resetAutoDetection();
    setState(() {
      _autoMode = enabled;
      _autoStatus = 'Place one page inside the guide';
    });
    try {
      if (enabled && !_camera!.value.isStreamingImages) {
        await _camera!.startImageStream(_onCameraImage);
      } else if (!enabled && _camera!.value.isStreamingImages) {
        await _camera!.stopImageStream();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _autoMode = false;
          _autoStatus = 'Auto capture unavailable; use the shutter';
        });
      }
    }
  }

  void _onCameraImage(CameraImage image) {
    if (!_autoMode || _busy || _capturedPath != null || !mounted) return;
    final now = DateTime.now();
    if (_lastAnalysis != null &&
        now.difference(_lastAnalysis!).inMilliseconds < 250) {
      return;
    }
    _lastAnalysis = now;
    final samples = _sampleLuma(image);
    if (samples == null) return;
    final looksLikePage = _looksLikePage(samples, image.width, image.height);
    final previous = _previousLuma;
    _previousLuma = samples;
    var motion = double.infinity;
    if (previous != null && previous.length == samples.length) {
      var total = 0;
      for (var i = 0; i < samples.length; i++) {
        total += (samples[i] - previous[i]).abs();
      }
      motion = total / samples.length;
    }
    if (!looksLikePage || motion > 7) {
      _steadySince = null;
      _pageReady = false;
      _autoTimer?.cancel();
      _autoTimer = null;
      _showAutoStatus(
        looksLikePage
            ? 'Hold the page steady'
            : 'Place one page inside the guide',
      );
      return;
    }
    _steadySince ??= now;
    if (now.difference(_steadySince!).inMilliseconds < 900) {
      _showAutoStatus('Hold the page steady');
      return;
    }
    _pageReady = true;
    if (_autoTimer != null) return;
    _showAutoStatus('Page framed and steady · capturing');
    _autoTimer = Timer(const Duration(milliseconds: 750), () {
      _autoTimer = null;
      if (mounted &&
          _autoMode &&
          _pageReady &&
          !_busy &&
          _capturedPath == null) {
        _shoot();
      }
    });
  }

  void _showAutoStatus(String status) {
    if (_autoStatus != status && mounted) {
      setState(() => _autoStatus = status);
    }
  }

  List<int>? _sampleLuma(CameraImage image) {
    if (image.planes.isEmpty) return null;
    const columns = 32;
    const rows = 24;
    final plane = image.planes.first;
    final bytes = plane.bytes;
    final pixelStride = plane.bytesPerPixel ?? 1;
    final bgra = image.format.group == ImageFormatGroup.bgra8888;
    final samples = <int>[];
    for (var y = 0; y < rows; y++) {
      final sourceY = ((y + 0.5) * image.height / rows).floor();
      for (var x = 0; x < columns; x++) {
        final sourceX = ((x + 0.5) * image.width / columns).floor();
        final index = sourceY * plane.bytesPerRow + sourceX * pixelStride;
        if (index < 0 || index + (bgra ? 2 : 0) >= bytes.length) return null;
        if (bgra) {
          samples.add(
            (bytes[index] * 0.114 +
                    bytes[index + 1] * 0.587 +
                    bytes[index + 2] * 0.299)
                .round(),
          );
        } else {
          samples.add(bytes[index]);
        }
      }
    }
    return samples;
  }

  bool _looksLikePage(List<int> luma, int width, int height) {
    const columns = 32;
    const rows = 24;
    final mean = luma.reduce((a, b) => a + b) / luma.length;
    final threshold = (mean + 20).clamp(150.0, 220.0);
    var minX = columns;
    var minY = rows;
    var maxX = -1;
    var maxY = -1;
    var bright = 0;
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < columns; x++) {
        if (luma[y * columns + x] < threshold) continue;
        bright++;
        minX = math.min(minX, x);
        minY = math.min(minY, y);
        maxX = math.max(maxX, x);
        maxY = math.max(maxY, y);
      }
    }
    if (bright < luma.length * 0.12 ||
        minX < 1 ||
        minY < 1 ||
        maxX >= columns - 1 ||
        maxY >= rows - 1) {
      return false;
    }
    final bboxWidth = maxX - minX + 1;
    final bboxHeight = maxY - minY + 1;
    final area = bboxWidth * bboxHeight / luma.length;
    final aspect = (bboxWidth * width / columns) / (bboxHeight * height / rows);
    final centered =
        ((minX + maxX) / 2 - (columns - 1) / 2).abs() < 5 &&
        ((minY + maxY) / 2 - (rows - 1) / 2).abs() < 4;
    return area >= 0.20 &&
        area <= 0.88 &&
        centered &&
        aspect >= 0.45 &&
        aspect <= 1.9;
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _camera?.dispose();
    super.dispose();
  }

  Future<void> _shoot() async {
    final cam = _camera;
    if (cam == null || !cam.value.isInitialized || _busy) return;
    setState(() => _busy = true);
    _autoTimer?.cancel();
    _autoTimer = null;
    try {
      if (cam.value.isStreamingImages) await cam.stopImageStream();
      final file = await cam.takePicture();
      setState(() => _capturedPath = file.path);
    } catch (e) {
      debugPrint('PPG capture failed: $e');
      if (mounted) {
        showPpgMessage(context, 'The photo was not taken. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      if (mounted && _autoMode && _capturedPath == null) {
        _resetAutoDetection();
        try {
          await _camera?.startImageStream(_onCameraImage);
        } catch (_) {
          if (mounted) {
            setState(() {
              _autoMode = false;
              _autoStatus = 'Auto capture unavailable; use the shutter';
            });
          }
        }
      }
    }
  }

  Future<void> _scanWithDocumentScanner() async {
    if (_busy || _camera == null) return;
    _autoTimer?.cancel();
    _autoTimer = null;
    try {
      if (_camera!.value.isStreamingImages) await _camera!.stopImageStream();
      setState(() {
        _busy = true;
        _autoMode = false;
        _documentScannerOutput = false;
      });
      final path = await _documentScannerChannel.invokeMethod<String>(
        'scanDocument',
      );
      if (path != null && mounted) {
        setState(() {
          _capturedPath = path;
          _documentScannerOutput = true;
        });
      }
    } on PlatformException catch (error) {
      debugPrint('PPG document scanner unavailable: ${error.code}');
      if (mounted) {
        showPpgMessage(
          context,
          'The document scanner is not available on this device. Use the shutter instead.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _accept(
    String originalPath,
    String rectifiedPath,
    int rotationDegrees,
  ) async {
    final ctrl = context.read<PpgSessionController>();
    setState(() => _reading = true);
    try {
      if (widget.newDelivery && ctrl.session == null) {
        await ctrl.startSession(operatorEmail: widget.operatorEmail);
      }
      final slot = widget.initialPage ?? ppgNextMissingPage(ctrl);
      final accepted = await ctrl.acceptPage(
        printedPage: slot,
        sourceImagePath: originalPath,
        rectifiedImagePath: rectifiedPath,
        rotationDegrees: rotationDegrees,
        useSyntheticOcr: ctrl.session?.mode != CaptureMode.camera,
      );
      if (mounted) Navigator.pop(context, accepted.pageCaptureId);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _reading = false;
        _capturedPath = null;
        _documentScannerOutput = false;
      });
      showPpgError(context, e, prefix: 'The page was not saved.');
    }
  }

  String get _title {
    final page = widget.initialPage;
    if (widget.newDelivery) return 'First page';
    return page == null ? 'Next page' : 'Page $page';
  }

  @override
  Widget build(BuildContext context) {
    if (_reading) {
      return const PpgThemed(
        child: Scaffold(
          backgroundColor: PpgColors.camera,
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Colors.white),
                SizedBox(height: PpgSpace.l),
                Text(
                  'Reading the page…',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: PpgSpace.xs),
                Text(
                  'Keep the paper nearby to compare.',
                  style: TextStyle(color: PpgColors.onNavyMuted),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_capturedPath != null) {
      return FourCornerCropScreen(
        imagePath: _capturedPath!,
        documentScannerProcessed: _documentScannerOutput,
        onCancel: () {
          setState(() {
            _capturedPath = null;
            _documentScannerOutput = false;
          });
          if (_autoMode) _setAutoMode(true);
        },
        onAccept: _accept,
      );
    }

    final camera = _camera;
    return PpgThemed(
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: PpgColors.camera,
          body: Stack(
            fit: StackFit.expand,
            children: [
              if (_error != null)
                _cameraProblem()
              else if (camera == null || !camera.value.isInitialized)
                const Center(
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    semanticsLabel: 'Starting camera',
                  ),
                )
              else ...[
                Center(child: CameraPreview(camera)),
                IgnorePointer(
                  child: CustomPaint(painter: _FrameGuidePainter()),
                ),
              ],
              _topBar(),
              if (_error == null &&
                  camera != null &&
                  camera.value.isInitialized)
                _controls(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chrome({required Widget child, EdgeInsets? padding}) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: PpgColors.cameraChrome,
      borderRadius: BorderRadius.circular(999),
    ),
    child: child,
  );

  Widget _topBar() {
    final ready = _error == null && _camera?.value.isInitialized == true;
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.all(PpgSpace.m),
          child: Row(
            children: [
              _chrome(
                child: IconButton(
                  tooltip: 'Close camera',
                  color: Colors.white,
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Icons.close),
                ),
              ),
              const SizedBox(width: PpgSpace.s),
              Expanded(
                child: _chrome(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Text(
                    _title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              if (ready) ...[
                const SizedBox(width: PpgSpace.s),
                _chrome(
                  child: Semantics(
                    toggled: _autoMode,
                    label: 'Automatic capture',
                    child: TextButton.icon(
                      onPressed: _busy ? null : () => _setAutoMode(!_autoMode),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                      ),
                      icon: Icon(
                        _autoMode ? Icons.flash_auto : Icons.touch_app_outlined,
                        size: 18,
                      ),
                      label: Text(_autoMode ? 'Auto' : 'Manual'),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _controls() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                liveRegion: true,
                child: _chrome(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  child: Text(
                    _autoMode
                        ? _autoStatus
                        : 'Fit one whole page in the frame. Avoid glare.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: PpgSpace.xl),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _roundAction(
                    icon: Icons.photo_library_outlined,
                    label: 'Choose a photo',
                    onPressed: _busy ? null : _pickFromGallery,
                  ),
                  Semantics(
                    button: true,
                    label: _busy ? 'Taking photo' : 'Take photo',
                    child: GestureDetector(
                      onTap: _busy ? null : _shoot,
                      child: Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 4),
                        ),
                        padding: const EdgeInsets.all(5),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _busy ? Colors.white54 : Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                  _roundAction(
                    icon: Icons.document_scanner_outlined,
                    label: 'Document scanner',
                    onPressed: _busy ? null : _scanWithDocumentScanner,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _roundAction({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _chrome(
        child: IconButton(
          tooltip: label,
          iconSize: 26,
          padding: const EdgeInsets.all(12),
          color: Colors.white,
          onPressed: onPressed,
          icon: Icon(icon),
        ),
      ),
      const SizedBox(height: 6),
      ExcludeSemantics(
        child: Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ),
    ],
  );

  Widget _cameraProblem() => Center(
    child: Padding(
      padding: const EdgeInsets.all(PpgSpace.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.no_photography_outlined,
            size: 48,
            color: PpgColors.onNavyMuted,
          ),
          const SizedBox(height: PpgSpace.m),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 15),
          ),
          const SizedBox(height: PpgSpace.l),
          FilledButton(
            onPressed: _retryCamera,
            child: const Text('Try the camera again'),
          ),
          const SizedBox(height: PpgSpace.s),
          OutlinedButton.icon(
            onPressed: _pickFromGallery,
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Choose a photo instead'),
          ),
        ],
      ),
    ),
  );
}

class _FrameGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white70
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final rect = Rect.fromLTWH(
      size.width * 0.08,
      size.height * 0.12,
      size.width * 0.84,
      size.height * 0.65,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(12)),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
