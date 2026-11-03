import 'package:uuid/uuid.dart';

import 'capture_models.dart';
import 'scan_models.dart';
import 'scan_repository.dart';

/// Sends a captured scan (docs/mobile-api.md section 5): create, upload each photo,
/// confirm. Every step is safe to repeat, so a failed send is retried by sending again.
class ScanUploader {
  ScanUploader(this._scans, {String Function()? newId}) : _newId = newId ?? const Uuid().v4;
  final ScanRepository _scans;
  final String Function() _newId;

  /// Returns the scan, now `extracting`: the API has queued the AI extraction (outbox).
  Future<Scan> send(CaptureDraft draft, {required String buId, required String locationNodeId}) async {
    final changed = draft.sentScanId != null &&
        (draft.sentLocationId != locationNodeId || draft.sentPhotoCount != draft.photos.length);
    if (changed) {
      // Created with other details: the same client_capture_id would now be refused
      // (409 idempotency-conflict). Drop the half-sent scan and start a fresh one.
      try {
        await _scans.discard(draft.sentScanId!);
      } catch (_) {
        // Best effort: an unsent draft left behind shows as Uploading in My Scans.
      }
      draft
        ..clientCaptureId = _newId()
        ..sentScanId = null;
    }

    final scan = await _scans.createScan(
      buId: buId,
      clientCaptureId: draft.clientCaptureId,
      equipmentTypeId: draft.type.typeId,
      locationNodeId: locationNodeId,
      photoCount: draft.photos.length,
      capturedAt: draft.capturedAt,
    );
    draft
      ..sentScanId = scan.scanId
      ..sentLocationId = locationNodeId
      ..sentPhotoCount = draft.photos.length;
    // Sent in full before, but the answer was lost: photos are refused once the upload
    // is confirmed (409 "Photos can only be sent while uploading"), and nothing is missing.
    if (scan.processingStatus != 'uploading') return scan;

    for (var i = 0; i < draft.photos.length; i++) {
      await _scans.uploadPhoto(scan.scanId, i + 1, draft.photos[i]);
    }
    await _scans.confirmUpload(scan.scanId);
    return scan;
  }
}
