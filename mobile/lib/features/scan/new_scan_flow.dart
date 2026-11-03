import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/api_exception.dart';
import 'capture_models.dart';
import 'location_pick.dart';
import 'location_screen.dart';
import 'new_scan_screen.dart';
import 'photo_prep.dart';
import 'photo_set_screen.dart';
import 'photo_source.dart';
import 'scan_repository.dart';
import 'scan_uploader.dart';

/// The online capture flow (design 30-46): New scan → photos → location → Submit scan,
/// then back to New scan with the type kept, ready for the next item. The scan is read
/// by the worker in the background; results come back through Home and My Scans.
class NewScanFlow extends StatefulWidget {
  const NewScanFlow({
    super.key,
    required this.scans,
    required this.lastLocations,
    required this.photoSource,
    required this.buId,
    required this.unitName,
    required this.tenantName,
    this.onMyScans,
    this.prepare = prepareJpeg,
    this.clock = DateTime.now,
  });
  final ScanRepository scans;
  final LastLocationStore lastLocations;
  final PhotoSource Function() photoSource;
  final String buId;
  final String unitName;
  final String tenantName;
  final VoidCallback? onMyScans;
  final PreparePhoto prepare;
  final DateTime Function() clock;

  @override
  State<NewScanFlow> createState() => _NewScanFlowState();
}

class _NewScanFlowState extends State<NewScanFlow> {
  late final PhotoSource _source = widget.photoSource();
  late final ScanUploader _uploader = ScanUploader(widget.scans);
  bool _busy = false;

  @override
  void dispose() {
    _source.dispose();
    super.dispose();
  }

  /// Floats above the camera controls so the shutter stays usable (design 46).
  void _say(String text, {SnackBarAction? action}) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(text),
        action: action,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 150),
      ));

  /// First photo from any of the three buttons; opens the photo set.
  Future<void> _start(EquipmentType type, Future<Uint8List?> Function() take) async {
    if (_busy) return;
    setState(() => _busy = true);
    Uint8List? jpeg;
    try {
      final raw = await take();
      if (raw != null) jpeg = await widget.prepare(raw);
    } on PhotoSourceException catch (e) {
      _say(e.message);
    } on PhotoPrepException catch (e) {
      _say(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (jpeg == null || !mounted) return;

    final draft = CaptureDraft(
      type: type,
      clientCaptureId: const Uuid().v4(),
      capturedAt: widget.clock(),
      first: jpeg,
    );
    final route = ModalRoute.of(context)!;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PhotoSetScreen(
        draft: draft,
        source: _source,
        prepare: widget.prepare,
        onNext: (d) => _confirmLocation(d, route),
      ),
    ));
  }

  void _confirmLocation(CaptureDraft draft, ModalRoute<dynamic> newScan) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => LocationScreen(
        scans: widget.scans,
        lastLocations: widget.lastLocations,
        buId: widget.buId,
        unitName: widget.unitName,
        tenantName: widget.tenantName,
        typeName: draft.type.name,
        photoCount: draft.photos.length,
        thumbnail: Image.memory(draft.photos.first, fit: BoxFit.cover),
        clock: widget.clock,
        onSubmit: (pick) => _submit(draft, pick, newScan),
      ),
    ));
  }

  /// Returns what went wrong, shown on Confirm location; pressing Submit again resends safely.
  Future<String?> _submit(CaptureDraft draft, LocationPick pick, ModalRoute<dynamic> newScan) async {
    try {
      await _uploader.send(draft, buId: widget.buId, locationNodeId: pick.chain.last.nodeId);
    } on ApiException catch (e) {
      return e.isNetwork ? "Couldn't send the scan. Check your connection and tap Submit scan again." : e.message;
    }
    await widget.lastLocations.save(widget.buId, pick.nodeIds, widget.clock());
    if (!mounted) return null;
    Navigator.of(context).popUntil((r) => r == newScan);
    _say(
      'Scan queued — extracting in background',
      action: widget.onMyScans == null ? null : SnackBarAction(label: 'VIEW', onPressed: widget.onMyScans!),
    );
    return null;
  }

  @override
  Widget build(BuildContext context) => Stack(children: [
        NewScanScreen(
          scans: widget.scans,
          buId: widget.buId,
          unitName: widget.unitName,
          viewfinder: (hint) => _source.viewfinder(hint: hint),
          onShutter: (type) => _start(type, _source.shutter),
          onGallery: (type) => _start(type, _source.gallery),
          onCamera: (type) => _start(type, _source.systemCamera),
          onMyScans: widget.onMyScans,
        ),
        if (_busy) const Positioned.fill(child: ColoredBox(color: Colors.black38, child: Center(child: CircularProgressIndicator()))),
      ]);
}
