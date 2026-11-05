import '../branding/app_brand.dart';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../widgets/frame_overlay.dart';
import 'extracting_screen.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  CameraController? _cameraController;
  bool _isCameraReady = false;
  String? _selectedType;
  final List<File> _capturedImages = [];
  static const int _maxImages = 10;

  @override
  void initState() {
    super.initState();
    _initCamera();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<AppState>().loadSchemas();
      }
    });
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;

      _cameraController = CameraController(
        cameras.first,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await _cameraController!.initialize();
      if (mounted) {
        setState(() => _isCameraReady = true);
      }
    } catch (e) {
      debugPrint('Camera init error: $e');
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _capturePhoto() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    if (_capturedImages.length >= _maxImages) return;

    try {
      final xFile = await _cameraController!.takePicture();
      setState(() => _capturedImages.add(File(xFile.path)));
    } catch (e) {
      debugPrint('Capture error: $e');
    }
  }

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final xFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2000,
      maxHeight: 2000,
      imageQuality: 90,
    );
    if (xFile != null && _capturedImages.length < _maxImages) {
      setState(() => _capturedImages.add(File(xFile.path)));
    }
  }

  void _removeImage(int index) {
    setState(() => _capturedImages.removeAt(index));
  }

  void _retakeAll() {
    setState(() => _capturedImages.clear());
  }

  void _proceedToExtract() {
    if (_capturedImages.isEmpty || _selectedType == null) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ExtractingScreen(
          imageFiles: _capturedImages,
          equipmentType: _selectedType!,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Capture Label'),
        backgroundColor: const Color(0xFF0D1117),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Equipment type picker
          _buildTypePicker(),

          // Camera or preview
          Expanded(
            child: _buildCamera(),
          ),

          // Image thumbnails strip
          if (_capturedImages.isNotEmpty) _buildThumbnailStrip(),

          // Bottom controls
          _buildControls(),
        ],
      ),
    );
  }

  Widget _buildTypePicker() {
    return Consumer<AppState>(
      builder: (context, state, _) {
        final schemas = state.schemas;

        // If schemas failed to load, show retry
        if (schemas.isEmpty) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Colors.black,
            child: Row(
              children: [
                const Icon(Icons.warning_amber, color: Colors.orange, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Cannot load label types',
                    style: TextStyle(color: Colors.orange),
                  ),
                ),
                TextButton(
                  onPressed: () => state.loadSchemas(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.black,
          child: Column(
            children: [
              InputDecorator(
                decoration: InputDecoration(
                  filled: false,
                  labelText: 'Label Type',
                  labelStyle: const TextStyle(color: Colors.grey),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.grey),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedType,
                    isExpanded: true,
                    dropdownColor: Colors.grey[900],
                    style: const TextStyle(color: Colors.white),
                    hint: const Text('Select label type',
                        style: TextStyle(color: Colors.grey)),
                    items: schemas.map((s) {
                      return DropdownMenuItem(
                        value: s['equipment_type'] as String,
                        child: Text(s['display_name'] as String),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() => _selectedType = value);
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCamera() {
    if (!_isCameraReady) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        CameraPreview(_cameraController!),
        const FrameOverlay(),
      ],
    );
  }

  Widget _buildThumbnailStrip() {
    return Container(
      height: 100,
      color: Colors.black,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _capturedImages.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    _capturedImages[index],
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: GestureDetector(
                    onTap: () => _removeImage(index),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, color: Colors.white, size: 16),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 2,
                  left: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.black,
      child: _capturedImages.isNotEmpty
          ? _buildPreviewControls()
          : _buildCameraControls(),
    );
  }

  Widget _buildCameraControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Gallery button
        IconButton(
          onPressed: _capturedImages.length < _maxImages ? _pickFromGallery : null,
          icon: Icon(Icons.photo_library, color: _capturedImages.length < _maxImages ? Colors.white : Colors.grey, size: 32),
        ),
        // Capture button
        GestureDetector(
          onTap: _capturedImages.length < _maxImages ? _capturePhoto : null,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: _capturedImages.length < _maxImages ? Colors.white : Colors.grey, width: 4),
            ),
            child: Container(
              margin: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _capturedImages.length < _maxImages ? Colors.white : Colors.grey,
              ),
            ),
          ),
        ),
        // Image count badge
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: _capturedImages.isNotEmpty ? AppBrand.blue : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: _capturedImages.isNotEmpty
              ? Center(
                  child: Text(
                    '${_capturedImages.length}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildPreviewControls() {
    final canProceed = _selectedType != null;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _retakeAll,
            icon: const Icon(Icons.refresh),
            label: const Text('Clear All'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(width: 8),
        if (_capturedImages.length < _maxImages)
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _capturePhoto,
              icon: const Icon(Icons.add_a_photo),
              label: Text('Add (${_capturedImages.length}/$_maxImages)'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        if (_capturedImages.length < _maxImages) const SizedBox(width: 8),
        Expanded(
          child: FilledButton.icon(
            onPressed: canProceed
                ? _proceedToExtract
                : () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please select a label type first'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                  },
            icon: const Icon(Icons.search),
            label: const Text('Extract'),
            style: FilledButton.styleFrom(
              backgroundColor: AppBrand.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }
}
