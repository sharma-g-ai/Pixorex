import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../../core/api_client.dart';
import 'capture_models.dart';
import 'scan_models.dart';

/// The scan endpoints the app calls (docs/mobile-api.md sections 5-6).
/// Online only: the offline queue is a separate piece of work.
class ScanRepository {
  ScanRepository(this._api);
  final ApiClient _api;
  static const _uuid = Uuid();

  /// Max photo size the API accepts (contract 2.22).
  static const maxPhotoBytes = 2 * 1024 * 1024;

  // ---- what the technician picks before capturing -------------------------------------

  /// Published types only, with their fields (contract 2.10), every page.
  Future<List<EquipmentType>> equipmentTypes(String buId) async {
    final types = <EquipmentType>[];
    String? cursor;
    do {
      final page = Page.fromJson(
        await _api.get('/business-units/$buId/equipment-types',
            query: {'status': 'published', 'include': 'fields', 'limit': '100', 'cursor': cursor}),
        EquipmentType.fromJson,
      );
      types.addAll(page.items);
      cursor = page.nextCursor;
    } while (cursor != null);
    return types;
  }

  /// Contract 2.9: the tree frozen at publish.
  Future<LocationTree> publishedLocations(String buId) async =>
      LocationTree.fromJson(await _api.get('/business-units/$buId/locations/published'));

  // ---- capture -------------------------------------------------------------------------

  /// Contract 2.21. [clientCaptureId] is made when the photos are taken and doubles as the
  /// Idempotency-Key, so sending it again after a lost connection returns the same scan.
  Future<Scan> createScan({
    required String buId,
    required String clientCaptureId,
    required String equipmentTypeId,
    required String locationNodeId,
    required int photoCount,
    required DateTime capturedAt,
    String? retakeOfScanId,
  }) async =>
      Scan.fromJson(await _api.post(
        '/business-units/$buId/scans',
        idempotencyKey: clientCaptureId,
        body: {
          'client_capture_id': clientCaptureId,
          'equipment_type_id': equipmentTypeId,
          'location_node_id': locationNodeId,
          'photo_count': photoCount,
          'captured_at': capturedAt.toUtc().toIso8601String(),
          'retake_of_scan_id': ?retakeOfScanId,
        },
      ));

  /// Contract 2.22: raw JPEG with an RFC 9530 digest. Sending a number again replaces it.
  Future<void> uploadPhoto(String scanId, int photoNo, List<int> jpeg) => _api.putBytes(
        '/scans/$scanId/photos/$photoNo',
        jpeg,
        headers: {'Content-Type': 'image/jpeg', 'Content-Digest': contentDigest(jpeg)},
      );

  /// Contract 2.23: queues the AI extraction (the API writes the outbox event). Safe to repeat.
  Future<void> confirmUpload(String scanId) => _api.post('/scans/$scanId/upload-complete');

  /// Contract 2.24. Poll until [Scan.isSettled]: there is no push.
  Future<Scan> scan(String scanId) async => Scan.fromJson(await _api.get('/scans/$scanId'));

  // ---- after extraction ----------------------------------------------------------------

  /// Contract 2.25, only when `failed`.
  Future<void> retry(String scanId) =>
      _api.post('/scans/$scanId/retry-extraction', idempotencyKey: _uuid.v4());

  /// Contract 2.26, only when `ready_to_review`: read again as another type (type mismatch).
  Future<void> reExtract(String scanId, String equipmentTypeId) => _api.post(
        '/scans/$scanId/re-extract',
        idempotencyKey: _uuid.v4(),
        body: {'equipment_type_id': equipmentTypeId},
      );

  /// Contract 2.27, only before submitting.
  Future<void> discard(String scanId) => _api.post('/scans/$scanId/discard');

  /// Contract 3.2. [fields] are the `FieldVerdict` maps (section 6). Keep [idempotencyKey]
  /// for one press of Submit so a retry after a lost answer isn't a second revision.
  Future<Map<String, dynamic>> submitRevision(
    String scanId, {
    required List<Map<String, dynamic>> fields,
    required String idempotencyKey,
    bool submitAnyway = false,
  }) =>
      _api.post(
        '/scans/$scanId/revisions',
        idempotencyKey: idempotencyKey,
        body: {'fields': fields, 'submit_anyway': submitAnyway},
      );

  // ---- My Scans ------------------------------------------------------------------------

  /// Contract 3.1, newest change first. [tab]: `needs_action`, `in_progress`, `approved`,
  /// or null for all. [from] filters on the capture date.
  Future<Page<MyScan>> myScans({String? tab, DateTime? from, String? q, String? cursor, int limit = 25}) async =>
      Page.fromJson(
        await _api.get('/me/scans', query: {
          'tab': tab,
          'from': from == null ? null : _date(from),
          'q': q,
          'cursor': cursor,
          'limit': '$limit',
        }),
        MyScan.fromJson,
      );
}

String _date(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// `sha-256=:<base64>:` (RFC 9530), checked by the API against the body.
String contentDigest(List<int> bytes) => 'sha-256=:${base64.encode(sha256.convert(bytes).bytes)}:';
