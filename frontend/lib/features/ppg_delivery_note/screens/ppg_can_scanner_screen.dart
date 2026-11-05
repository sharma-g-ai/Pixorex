import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../seastock/ui/seastock_widgets.dart';
import '../domain/can_article_reader.dart';
import '../domain/models.dart';
import '../services/ppg_session_controller.dart';
import '../ui/ppg_format.dart';
import '../ui/ppg_tokens.dart';
import '../ui/ppg_widgets.dart';

class PpgCanScannerScreen extends StatefulWidget {
  const PpgCanScannerScreen({
    super.key,
    required this.controller,
    this.occurrenceId,
  });
  final PpgSessionController controller;
  final String? occurrenceId;

  @override
  State<PpgCanScannerScreen> createState() => _PpgCanScannerScreenState();
}

class _PpgCanScannerScreenState extends State<PpgCanScannerScreen>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('com.amzur.equiptrack/ppg_can_ocr');
  final _reader = CanArticleReader();
  final _consensus = CanArticleConsensus();
  CameraController? _camera;
  Future<void> _cameraWork = Future.value();
  int _generation = 0;
  bool _active = true;
  bool _busy = false;
  bool _saving = false;
  bool _accepted = false;
  String? _cameraError;
  String? _saveError;
  String? _article;
  String? _target;
  String? _eventId;
  int? _revision;
  late final String? _sessionId;
  String _guidance = 'Show the printed Article no. field on the can.';
  DateTime? _lastFrame;
  List<int>? _previousLuma;
  int _misses = 0;
  int _rotationOffset = 0;

  @override
  void initState() {
    super.initState();
    _sessionId = widget.controller.session?.id;
    WidgetsBinding.instance.addObserver(this);
    _configureCamera(true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (!_accepted) _clearScan();
    _configureCamera(_active);
  }

  void _configureCamera(bool open) {
    final generation = ++_generation;
    _cameraWork = _cameraWork
        .then((_) async {
          final previous = _camera;
          _camera = null;
          if (mounted) setState(() {});
          await previous?.dispose();
          if (!open || !mounted || generation != _generation) return;
          if (!Platform.isAndroid) {
            throw UnsupportedError('Can scanning is available on Android.');
          }
          final cameras = await availableCameras();
          if (cameras.isEmpty) throw StateError('No camera available.');
          final description = cameras.firstWhere(
            (camera) => camera.lensDirection == CameraLensDirection.back,
            orElse: () => cameras.first,
          );
          final camera = CameraController(
            description,
            ResolutionPreset.high,
            enableAudio: false,
            imageFormatGroup: ImageFormatGroup.nv21,
          );
          try {
            await camera.initialize();
            if (!mounted || generation != _generation) {
              await camera.dispose();
              return;
            }
            _camera = camera;
            await camera.startImageStream(_onFrame);
            if (mounted && generation == _generation) {
              setState(() => _cameraError = null);
            }
          } catch (_) {
            if (identical(_camera, camera)) _camera = null;
            await camera.dispose();
            rethrow;
          }
        })
        .catchError((Object error) {
          debugPrint('PPG can scanner camera failed: $error');
          if (mounted && generation == _generation) {
            setState(
              () => _cameraError = error is UnsupportedError
                  ? 'Can scanning works on Android devices only. Count this item by hand on the count list.'
                  : 'The camera could not start. Try again.',
            );
          }
        });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _active = false;
    _configureCamera(false);
    super.dispose();
  }

  void _clearScan() {
    _article = null;
    _target = null;
    _eventId = null;
    _revision = null;
    _consensus.reset();
    _previousLuma = null;
    _lastFrame = null;
    _misses = 0;
    _rotationOffset = 0;
    _saveError = null;
    _guidance = 'Show the printed Article no. field on the can.';
  }

  void _nextCan() {
    setState(() {
      _accepted = false;
      _clearScan();
    });
  }

  /// A coarse motion/exposure gate. Field geometry, OCR confidence and fresh
  /// temporal agreement supply the remaining checks; real-can testing is still
  /// necessary to measure operating limits.
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
    final camera = _camera;
    final ctrl = widget.controller;
    if (!mounted ||
        !_active ||
        _busy ||
        _saving ||
        _article != null ||
        _accepted ||
        camera == null ||
        !ctrl.sourceReviewReady ||
        ctrl.session?.id != _sessionId ||
        ctrl.session?.isSubmitted == true) {
      return;
    }
    final now = DateTime.now();
    if (_lastFrame != null &&
        now.difference(_lastFrame!).inMilliseconds < 650) {
      return;
    }
    _lastFrame = now;
    if (frame.planes.length != 1 ||
        frame.planes.single.bytes.length !=
            frame.width * frame.height * 3 ~/ 2) {
      setState(
        () => _cameraError =
            'The camera picture could not be read. Close the scanner and open it again.',
      );
      return;
    }
    final quality = _quality(frame);
    if (quality != null) {
      _consensus.reset();
      setState(() => _guidance = quality);
      return;
    }
    final generation = _generation;
    final revision = ctrl.session!.formRevision;
    _busy = true;
    try {
      final deviceRotation = switch (camera.value.deviceOrientation) {
        DeviceOrientation.portraitUp => 0,
        DeviceOrientation.landscapeLeft => 90,
        DeviceOrientation.portraitDown => 180,
        DeviceOrientation.landscapeRight => 270,
      };
      final sensor = camera.description.sensorOrientation;
      final rotation =
          (sensor +
              (camera.description.lensDirection == CameraLensDirection.front
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
      if (!mounted || !_active || generation != _generation) return;
      if (ctrl.session?.id != _sessionId ||
          ctrl.session?.formRevision != revision ||
          !ctrl.sourceReviewReady) {
        setState(_clearScan);
        return;
      }
      if (result == null) throw StateError('No camera OCR result.');
      final lines = (result['lines'] as List)
          .map(
            (line) =>
                OcrElement.fromJson(Map<String, dynamic>.from(line as Map)),
          )
          .toList();
      final candidates = _reader.candidates(
        lines: lines,
        dnArticles: ctrl.lines.map((line) => line.articleNumber).toSet(),
        width: result['width'] as int,
        height: result['height'] as int,
      );
      final confirmed = _consensus.observe(candidates, now);
      if (candidates.isEmpty) {
        _misses++;
        // Try another orientation on a later usable frame, not four OCR passes
        // on every frame. Stay at a useful orientation while confirming it.
        if (_misses % 3 == 0) _rotationOffset = (_rotationOffset + 90) % 360;
      } else {
        _misses = 0;
      }
      setState(() {
        _cameraError = null;
        if (confirmed != null) {
          _article = confirmed;
          _revision = revision;
          _eventId = const Uuid().v4();
          final matches = ctrl.lines
              .where((line) => line.articleNumber == confirmed)
              .toList();
          _target = widget.occurrenceId != null
              ? matches
                    .where((line) => line.occurrenceId == widget.occurrenceId)
                    .firstOrNull
                    ?.occurrenceId
              : matches.length == 1
              ? matches.single.occurrenceId
              : null;
          _guidance = matches.isEmpty
              ? 'Not on this DN. No can has been counted.'
              : widget.occurrenceId != null && _target == null
              ? 'This can does not match the selected article. No count added.'
              : 'Article confirmed.';
        } else {
          _guidance = _consensus.conflict
              ? 'Conflicting article readings. Keep scanning.'
              : _consensus.candidate != null
              ? 'Reading ${_consensus.candidate} · Hold steady (${_consensus.observations}/3).'
              : 'Article not readable yet. Rotate the can slightly or move closer.';
        }
      });
      // A confirmed read counts the can, as on every can scanner.
      if (confirmed != null && _canAccept(ctrl)) unawaited(_accept());
    } catch (error) {
      debugPrint('PPG can article reader failed: $error');
      if (mounted && generation == _generation) {
        _consensus.reset();
        setState(() => _cameraError = 'The article reader stopped. Try again.');
      }
    } finally {
      _busy = false;
    }
  }

  bool _canAccept(PpgSessionController ctrl) {
    final target = ctrl.lines
        .where((line) => line.occurrenceId == _target)
        .firstOrNull;
    return ctrl.sourceReviewReady &&
        ctrl.session?.id == _sessionId &&
        ctrl.session?.isSubmitted != true &&
        target != null &&
        !target.isPhysicalVerified &&
        !target.needsArticleReconciliation &&
        target.unit.toUpperCase() == 'PC' &&
        _article != null &&
        _revision == ctrl.session?.formRevision &&
        !_accepted &&
        !_saving &&
        _active;
  }

  /// Fixes the count of the row just added to: +1 / −1, or a typed total.
  Future<void> _fix(DocumentLine line, int value) async {
    if (_saving) return;
    final current = line.hasPhysicalCount ? line.physicalQuantity : 0;
    if (value == current || value < 0) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final delta = value - current;
      if (delta == 1 || delta == -1) {
        await widget.controller.adjustPhysicalCount(
          occurrenceId: line.occurrenceId,
          delta: delta,
        );
      } else {
        await widget.controller.setCountedTotal(
          occurrenceId: line.occurrenceId,
          quantity: value,
        );
      }
    } catch (error) {
      if (mounted) setState(() => _saveError = ppgErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Takes back the can this read added, then scans again.
  Future<void> _undo(DocumentLine line) async {
    final current = line.hasPhysicalCount ? line.physicalQuantity : 0;
    if (current > 0) await _fix(line, current - 1);
    if (mounted && _saveError == null) _nextCan();
  }

  Future<void> _accept() async {
    if (_saving ||
        _accepted ||
        _article == null ||
        _target == null ||
        _sessionId == null) {
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await widget.controller.addScannedCan(
        articleNumber: _article!,
        occurrenceId: _target!,
        eventId: _eventId!,
        expectedSessionId: _sessionId,
        expectedRevision: _revision!,
      );
      if (mounted) {
        setState(() {
          _accepted = true;
          _guidance =
              'One can saved. Move it aside before scanning the next can.';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _saveError = ppgErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final ctrl = widget.controller;
      final target = ctrl.lines
          .where((line) => line.occurrenceId == _target)
          .firstOrNull;
      final matches = ctrl.lines
          .where((line) => line.articleNumber == _article)
          .toList();
      final camera = _camera;
      final sourceReady =
          ctrl.sourceReviewReady &&
          ctrl.session?.id == _sessionId &&
          ctrl.session?.isSubmitted != true;
      final canAccept = _canAccept(ctrl);
      final expected = widget.occurrenceId == null
          ? null
          : ctrl.lines
                .where((l) => l.occurrenceId == widget.occurrenceId)
                .firstOrNull;
      return PpgThemed(
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.light,
          child: PopScope(
            canPop: !_saving,
            child: Scaffold(
              backgroundColor: PpgColors.camera,
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (_cameraError != null)
                          _cameraProblem()
                        else if (camera != null && camera.value.isInitialized)
                          ClipRect(
                            child: FittedBox(
                              fit: BoxFit.cover,
                              child: SizedBox(
                                width: 1000,
                                height: 1000 * camera.value.aspectRatio,
                                child: CameraPreview(camera),
                              ),
                            ),
                          )
                        else
                          const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              semanticsLabel: 'Starting camera',
                            ),
                          ),
                        _topBar(ctrl, camera),
                        if (_cameraError == null)
                          Positioned(
                            left: 16,
                            right: 16,
                            bottom: 16,
                            child: Center(
                              child: Semantics(
                                liveRegion: true,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: PpgColors.cameraChrome,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    _guidance,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  _resultSheet(
                    ctrl,
                    target: target,
                    matches: matches,
                    expected: expected,
                    sourceReady: sourceReady,
                    canAccept: canAccept,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _chrome(Widget child) => DecoratedBox(
    decoration: BoxDecoration(
      color: PpgColors.cameraChrome,
      borderRadius: BorderRadius.circular(999),
    ),
    child: child,
  );

  Widget _topBar(PpgSessionController ctrl, CameraController? camera) {
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
                IconButton(
                  tooltip: 'Close scanner',
                  color: Colors.white,
                  onPressed: _saving ? null : () => Navigator.maybePop(context),
                  icon: const Icon(Icons.close),
                ),
              ),
              const SizedBox(width: PpgSpace.s),
              Expanded(
                child: _chrome(
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          const TextSpan(
                            text: 'DN ',
                            style: TextStyle(color: PpgColors.onNavyMuted),
                          ),
                          TextSpan(
                            text: ctrl.session?.deliveryNoteNumber ?? '—',
                            style: PpgText.mono(size: 14, color: Colors.white),
                          ),
                        ],
                      ),
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ),
              ),
              if (camera != null && camera.value.isInitialized) ...[
                const SizedBox(width: PpgSpace.s),
                _chrome(
                  IconButton(
                    tooltip: camera.value.flashMode == FlashMode.torch
                        ? 'Turn off torch'
                        : 'Turn on torch',
                    color: Colors.white,
                    icon: Icon(
                      camera.value.flashMode == FlashMode.torch
                          ? Icons.flashlight_off_outlined
                          : Icons.flashlight_on_outlined,
                    ),
                    onPressed: () async {
                      try {
                        await camera.setFlashMode(
                          camera.value.flashMode == FlashMode.torch
                              ? FlashMode.off
                              : FlashMode.torch,
                        );
                        if (mounted) setState(() {});
                      } catch (_) {
                        if (mounted) {
                          showPpgMessage(context, 'This camera has no torch.');
                        }
                      }
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _cameraProblem() => Center(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 96, 24, 24),
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
            _cameraError!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 15),
          ),
          if (Platform.isAndroid) ...[
            const SizedBox(height: PpgSpace.l),
            FilledButton.icon(
              onPressed: () {
                setState(() => _cameraError = null);
                _configureCamera(true);
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _resultSheet(
    PpgSessionController ctrl, {
    required DocumentLine? target,
    required List<DocumentLine> matches,
    required DocumentLine? expected,
    required bool sourceReady,
    required bool canAccept,
  }) {
    final stale =
        _article != null &&
        !_accepted &&
        !_saving &&
        _revision != ctrl.session?.formRevision;
    final shown = target ?? expected;
    final counted = shown == null
        ? 0
        : shown.hasPhysicalCount
        ? shown.physicalQuantity
        : 0;
    final (IconData icon, PpgTone tone, String headline) = _accepted
        ? (Icons.check, PpgTone.success, 'Added 1 can · on this delivery note')
        : _article == null
        ? (
            Icons.qr_code_scanner,
            PpgTone.info,
            expected == null
                ? 'Point at the Article no. on the can'
                : 'Scanning for ${expected.articleNumber}',
          )
        : matches.isEmpty
        ? (Icons.block, PpgTone.danger, 'Not on this delivery note')
        : widget.occurrenceId != null && target == null
        ? (Icons.block, PpgTone.danger, 'Not the item you are counting')
        : (Icons.check, PpgTone.success, 'On this delivery note');
    final blocked = target == null
        ? null
        : target.isPhysicalVerified && !_accepted
        ? 'This item\'s count is finished. Reopen it on the count list to add more.'
        : target.needsArticleReconciliation
        ? 'Recheck this item\'s count on the count list first.'
        : target.unit.toUpperCase() != 'PC'
        ? 'This item is not counted in cans. Count it on the count list.'
        : null;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
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
            children: [
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: tone.background,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 16, color: tone.foreground),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      headline,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: tone == PpgTone.info
                            ? PpgColors.navy
                            : tone.foreground,
                      ),
                    ),
                  ),
                ],
              ),
              if (_article != null) ...[
                const SizedBox(height: PpgSpace.m),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_article!, style: PpgText.mono(size: 26)),
                          if (shown != null)
                            Text(
                              [
                                if (shown.productContext != null)
                                  shown.productContext!,
                                'DN page ${shown.sourcePage}',
                              ].join(' · '),
                              style: const TextStyle(
                                fontSize: 14,
                                color: PpgColors.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (shown != null) _countFigure(shown, counted),
                  ],
                ),
              ] else if (expected != null) ...[
                const SizedBox(height: PpgSpace.s),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        expected.productContext ?? expected.articleNumber,
                        style: const TextStyle(
                          fontSize: 14,
                          color: PpgColors.textSecondary,
                        ),
                      ),
                    ),
                    _countFigure(expected, counted),
                  ],
                ),
              ],
              if (shown != null) ...[
                const SizedBox(height: PpgSpace.m),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: shown.documentQuantity == 0
                        ? 0
                        : (counted / shown.documentQuantity).clamp(0.0, 1.0),
                    minHeight: 8,
                    backgroundColor: PpgColors.divider,
                    color: PpgColors.blue,
                    semanticsLabel:
                        'Counted $counted of ${shown.documentQuantity} ${shown.unit}',
                  ),
                ),
              ],
              if (matches.length > 1 &&
                  widget.occurrenceId == null &&
                  !_accepted) ...[
                const SizedBox(height: PpgSpace.m),
                const Text(
                  'This article is on more than one DN line. Choose which one this can belongs to:',
                  style: TextStyle(fontSize: 14),
                ),
                RadioGroup<String>(
                  groupValue: _target,
                  onChanged: (value) {
                    if (_saving) return;
                    setState(() => _target = value);
                    if (_canAccept(ctrl)) _accept();
                  },
                  child: Column(
                    children: [
                      for (final line in matches)
                        RadioListTile<String>(
                          contentPadding: EdgeInsets.zero,
                          value: line.occurrenceId,
                          title: Text(
                            'Page ${line.sourcePage} · ${line.productContext ?? line.articleNumber}',
                          ),
                          subtitle: Text(
                            'On DN ${line.documentQuantity} ${line.unit} · counted ${line.hasPhysicalCount ? line.physicalQuantity : 0}',
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              for (final note in [
                if (!sourceReady)
                  'Finish the document checks before adding cans.',
                if (stale) 'The DN or count changed. Scan this can again.',
                if (_article != null && matches.isEmpty)
                  'Nothing was counted. Set this can aside.',
                ?blocked,
                ?_saveError,
              ]) ...[
                const SizedBox(height: PpgSpace.s),
                PpgBanner(tone: PpgTone.warning, message: note),
              ],
              const SizedBox(height: PpgSpace.m),
              if (_accepted && target != null) ...[
                SeastockCounter(
                  key: const ValueKey('ppg-scan-counter'),
                  label: 'Counted',
                  trailingLabel: counted >= target.documentQuantity
                      ? 'All ${target.documentQuantity} on the DN'
                      : '${target.documentQuantity - counted} to go',
                  value: counted,
                  onChanged: _saving || target.isPhysicalVerified
                      ? null
                      : (value) => _fix(target, value),
                ),
                const SizedBox(height: PpgSpace.m),
                Row(
                  children: [
                    TextButton(
                      key: const ValueKey('ppg-scan-undo'),
                      onPressed: _saving ? null : () => _undo(target),
                      child: const Text('Wrong can? Undo'),
                    ),
                    const SizedBox(width: PpgSpace.s),
                    Expanded(
                      child: FilledButton.icon(
                        key: const ValueKey('ppg-scan-next'),
                        style: FilledButton.styleFrom(
                          backgroundColor: PpgColors.navy,
                          minimumSize: const Size.fromHeight(52),
                        ),
                        onPressed: _saving ? null : _nextCan,
                        icon: const Icon(Icons.qr_code_scanner),
                        label: const Text('Scan next can'),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    textStyle: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onPressed: canAccept ? _accept : null,
                  icon: const Icon(Icons.add),
                  label: Text(
                    _saving
                        ? 'Saving…'
                        : _saveError != null
                        ? 'Try adding this can again'
                        : matches.length > 1 && widget.occurrenceId == null
                        ? 'Choose the DN line above'
                        : 'Add this can',
                  ),
                ),
                if (_article != null)
                  TextButton(
                    onPressed: _saving ? null : _nextCan,
                    child: const Text('Not this can, scan again'),
                  ),
                if (_article == null)
                  const Padding(
                    padding: EdgeInsets.only(top: PpgSpace.s),
                    child: PpgHint(
                      'Each scanned can counts as one. Counts are saved on this device.',
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _countFigure(DocumentLine line, int counted) => Column(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      const Text(
        'Counted',
        style: TextStyle(fontSize: 12, color: PpgColors.textSecondary),
      ),
      Text.rich(
        TextSpan(
          style: PpgText.figures(size: 20),
          children: [
            TextSpan(text: '$counted'),
            TextSpan(
              text: ' / ${line.documentQuantity} ${line.unit}',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w400,
                color: PpgColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
