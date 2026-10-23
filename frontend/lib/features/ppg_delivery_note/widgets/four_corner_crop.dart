import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../ui/ppg_tokens.dart';
import '../ui/ppg_widgets.dart';
import 'perspective_warp.dart';

/// Two steps after a photo: fit the page (corners and rotation), then check
/// the straightened scan and choose how it is enhanced for reading.
/// Returns both retained original path and rectified crop path.
class FourCornerCropScreen extends StatefulWidget {
  const FourCornerCropScreen({
    super.key,
    required this.imagePath,
    required this.onAccept,
    required this.onCancel,
    this.documentScannerProcessed = false,
  });

  final String imagePath;
  final bool documentScannerProcessed;

  /// (originalSourcePath, rectifiedPath, appliedRotationDegrees)
  final void Function(
    String originalPath,
    String rectifiedPath,
    int rotationDegrees,
  )
  onAccept;
  final VoidCallback onCancel;

  @override
  State<FourCornerCropScreen> createState() => _FourCornerCropScreenState();
}

class _FourCornerCropScreenState extends State<FourCornerCropScreen> {
  late List<Offset> _corners; // TL, TR, BR, BL in image coords
  ui.Image? _image;
  ui.Image? _displayImage;
  ui.Image? _scanPreview;
  Uint8List? _preparedScan;

  /// The straightened page before enhancement, reused when the look changes.
  Uint8List? _warped;
  int _rotation = 0;
  late DocumentEnhancement _enhancement = widget.documentScannerProcessed
      ? DocumentEnhancement.original
      : DocumentEnhancement.color;
  bool _busy = false;
  bool _blurWarning = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bytes = await File(widget.imagePath).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    if (!mounted) return;
    setState(() {
      _image = frame.image;
      _displayImage = frame.image;
      _resetCorners(frame.image);
    });
    final previewCodec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: 768,
    );
    final previewFrame = await previewCodec.getNextFrame();
    final previewPixels = await previewFrame.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    if (previewPixels != null) {
      final score = await compute(estimateTextSharpnessRgba, <String, Object>{
        'rgba': previewPixels.buffer.asUint8List(),
        'width': previewFrame.image.width,
        'height': previewFrame.image.height,
      });
      if (mounted) setState(() => _blurWarning = score < 4);
    }
  }

  void _resetCorners(ui.Image image) {
    // Start near the image edge: a deeper default inset cut off the printed
    // "Page x / y" header, which the page number is now read from.
    final inset = widget.documentScannerProcessed ? 0.0 : 0.02;
    _corners = [
      Offset(image.width * inset, image.height * inset),
      Offset(image.width * (1 - inset), image.height * inset),
      Offset(image.width * (1 - inset), image.height * (1 - inset)),
      Offset(image.width * inset, image.height * (1 - inset)),
    ];
  }

  Future<void> _rotate(int delta) async {
    final base = _image;
    if (base == null || _busy) return;
    setState(() => _busy = true);
    try {
      _rotation = (_rotation + delta) % 360;
      if (_rotation < 0) _rotation += 360;
      final rotated = await PerspectiveWarp.rotateImage(base, _rotation);
      setState(() {
        _displayImage = rotated;
        _clearScan();
        _resetCorners(rotated);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _accept() async {
    final image = _displayImage;
    if (_busy || image == null) return;
    setState(() => _busy = true);
    try {
      final processed = _preparedScan ?? await _prepareScan(image);
      final dir = await getTemporaryDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final rectifiedPath = p.join(dir.path, 'ppg_rectified_$ts.png');
      await File(rectifiedPath).writeAsBytes(processed);

      // Keep the untouched camera/import file as original evidence.
      final originalPath = widget.imagePath;
      widget.onAccept(originalPath, rectifiedPath, _rotation);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<Uint8List> _prepareScan(ui.Image image) async {
    _warped ??= await PerspectiveWarp.warpToPng(
      image: image,
      corners: _corners.map((c) => OffsetXY(c.dx, c.dy)).toList(),
    );
    return PerspectiveWarp.enhancePng(_warped!, _enhancement);
  }

  void _clearScan() {
    _scanPreview = null;
    _preparedScan = null;
    _warped = null;
  }

  /// Step 1 → 2: straighten the page and show the enhanced result.
  Future<void> _showScan() async {
    final image = _displayImage;
    if (_busy || image == null) return;
    setState(() => _busy = true);
    try {
      final png = await _prepareScan(image);
      final codec = await ui.instantiateImageCodec(png);
      final frame = await codec.getNextFrame();
      if (!mounted) return;
      setState(() {
        _preparedScan = png;
        _scanPreview = frame.image;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _selectEnhancement(DocumentEnhancement value) async {
    if (_busy || value == _enhancement) return;
    setState(() {
      _enhancement = value;
      _preparedScan = null;
    });
    await _showScan();
  }

  void _backToCorners() => setState(_clearScan);

  bool get _checking => _scanPreview != null;

  @override
  Widget build(BuildContext context) {
    final image = _scanPreview ?? _displayImage;
    return PpgThemed(
      child: PopScope(
        canPop: !_checking,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && !_busy) _backToCorners();
        },
        child: Scaffold(
          backgroundColor: PpgColors.camera,
          appBar: AppBar(
            backgroundColor: PpgColors.camera,
            foregroundColor: Colors.white,
            leading: _checking
                ? IconButton(
                    tooltip: 'Back to the corners',
                    onPressed: _busy ? null : _backToCorners,
                    icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                  )
                : IconButton(
                    tooltip: 'Retake photo',
                    onPressed: _busy ? null : widget.onCancel,
                    icon: const Icon(Icons.close),
                  ),
            title: Text(_checking ? 'Check the scan' : 'Fit the page'),
            actions: [
              if (!_checking) ...[
                IconButton(
                  tooltip: 'Rotate left',
                  onPressed: _busy || image == null ? null : () => _rotate(-90),
                  icon: const Icon(Icons.rotate_left),
                ),
                IconButton(
                  tooltip: 'Rotate right',
                  onPressed: _busy || image == null ? null : () => _rotate(90),
                  icon: const Icon(Icons.rotate_right),
                ),
                const SizedBox(width: 4),
              ],
            ],
          ),
          bottomNavigationBar: image == null ? null : _bottomPanel(),
          body: image == null
              ? const Center(
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    semanticsLabel: 'Loading photo',
                  ),
                )
              : Padding(
                  // Room for corner handles that sit on the photo's edge.
                  padding: const EdgeInsets.all(24),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(child: _imageArea(image)),
                      if (_busy)
                        const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _bottomPanel() {
    return Material(
      color: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(PpgRadii.sheet),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _checking ? _checkControls() : _fitControls(),
          ),
        ),
      ),
    );
  }

  List<Widget> _fitControls() => [
    if (_blurWarning) ...[
      const PpgBanner(
        tone: PpgTone.warning,
        message:
            'This photo may be blurry. If the smallest numbers are hard to read, retake it.',
      ),
      const SizedBox(height: PpgSpace.m),
    ],
    const PpgHint('Drag the four corners to the edges of the page.'),
    const SizedBox(height: PpgSpace.m),
    FilledButton(
      onPressed: _busy ? null : _showScan,
      child: Text(_busy ? 'Straightening…' : 'Next'),
    ),
  ];

  List<Widget> _checkControls() => [
    const Text(
      'Scan look',
      style: TextStyle(fontSize: 13, color: PpgColors.textSecondary),
    ),
    const SizedBox(height: 6),
    _lookPicker(),
    const SizedBox(height: PpgSpace.m),
    const PpgHint(
      'Choose the look where the numbers are sharpest. Your original photo is kept as well.',
    ),
    const SizedBox(height: PpgSpace.m),
    FilledButton(
      onPressed: _busy ? null : _accept,
      child: Text(_busy ? 'Saving…' : 'Use this scan'),
    ),
  ];

  Widget _lookPicker() {
    const looks = [
      ('Color', DocumentEnhancement.color),
      ('Grayscale', DocumentEnhancement.grayscale),
      ('B&W', DocumentEnhancement.blackAndWhite),
      ('Original', DocumentEnhancement.original),
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: PpgColors.ground,
        borderRadius: BorderRadius.circular(PpgRadii.medium),
      ),
      child: Row(
        children: [
          for (final (label, value) in looks)
            Expanded(
              child: Semantics(
                selected: _enhancement == value,
                button: true,
                label: value == DocumentEnhancement.blackAndWhite
                    ? 'Black and white'
                    : label,
                excludeSemantics: true,
                child: InkWell(
                  borderRadius: BorderRadius.circular(PpgRadii.small),
                  onTap: _busy ? null : () => _selectEnhancement(value),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    height: PpgSizes.touch,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _enhancement == value
                          ? Colors.white
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(PpgRadii.small),
                      boxShadow: _enhancement == value
                          ? const [
                              BoxShadow(
                                color: Color(0x1A0B1F44),
                                blurRadius: 4,
                                offset: Offset(0, 1),
                              ),
                            ]
                          : null,
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: _enhancement == value
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: _enhancement == value
                            ? PpgColors.navy
                            : PpgColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _imageArea(ui.Image image) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = math.min(
          constraints.maxWidth / image.width,
          constraints.maxHeight / image.height,
        );
        final displaySize = Size(image.width * scale, image.height * scale);
        return Center(
          child: SizedBox(
            width: displaySize.width,
            height: displaySize.height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: RawImage(image: image, fit: BoxFit.fill),
                ),
                if (_scanPreview == null)
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _QuadPainter(
                        corners: _corners
                            .map((c) => Offset(c.dx * scale, c.dy * scale))
                            .toList(),
                      ),
                    ),
                  ),
                if (_scanPreview == null)
                  for (var i = 0; i < 4; i++)
                    Positioned(
                      // A 48 px touch target around a 24 px handle.
                      left: _corners[i].dx * scale - 24,
                      top: _corners[i].dy * scale - 24,
                      child: Semantics(
                        label: const [
                          'Top left corner',
                          'Top right corner',
                          'Bottom right corner',
                          'Bottom left corner',
                        ][i],
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanUpdate: (d) {
                            setState(() {
                              final nx = (_corners[i].dx + d.delta.dx / scale)
                                  .clamp(0.0, image.width.toDouble())
                                  .toDouble();
                              final ny = (_corners[i].dy + d.delta.dy / scale)
                                  .clamp(0.0, image.height.toDouble())
                                  .toDouble();
                              _corners[i] = Offset(nx, ny);
                            });
                          },
                          child: SizedBox.square(
                            dimension: 48,
                            child: Center(
                              child: Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: PpgColors.blue,
                                    width: 3,
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x66000000),
                                      blurRadius: 6,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _QuadPainter extends CustomPainter {
  _QuadPainter({required this.corners});

  final List<Offset> corners;

  @override
  void paint(Canvas canvas, Size size) {
    if (corners.length != 4) return;
    final path = Path()
      ..moveTo(corners[0].dx, corners[0].dy)
      ..lineTo(corners[1].dx, corners[1].dy)
      ..lineTo(corners[2].dx, corners[2].dy)
      ..lineTo(corners[3].dx, corners[3].dy)
      ..close();
    // Dim what will be cut away so the kept page stands out.
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        path,
      ),
      Paint()..color = const Color(0x99000000),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = PpgColors.blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(covariant _QuadPainter oldDelegate) => true;
}
