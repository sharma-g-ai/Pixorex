import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pixorex_mobile/core/api_exception.dart';
import 'package:pixorex_mobile/features/scan/capture_models.dart';
import 'package:pixorex_mobile/features/scan/scan_repository.dart';
import 'package:pixorex_mobile/features/scan/scan_uploader.dart';

import 'auth_flow_test.dart' show json, problem;
import 'new_scan_screen_test.dart' show signedIn;
import 'photo_set_screen_test.dart' show draftWith;
import 'scan_repository_test.dart' show scanJson;

/// The capture API as the phone sees it; records each call.
class FakeCaptureApi {
  final calls = <String>[];
  final keys = <String>[];
  final bodies = <Map<String, dynamic>>[];
  http.Response? Function(http.BaseRequest r)? override;

  Future<http.Response> call(http.BaseRequest r) async {
    final req = r as http.Request;
    final o = override?.call(r);
    calls.add('${r.method} ${r.url.path.replaceFirst('/api/v1', '')}');
    if (o != null) return o;
    if (r.method == 'POST' && r.url.path.endsWith('/scans')) {
      keys.add(r.headers['Idempotency-Key']!);
      bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
      return json(scanJson(processing: 'uploading')..['scan_id'] = 'scan-${keys.length}', 201);
    }
    if (r.method == 'PUT') return http.Response('', 204);
    if (r.url.path.endsWith('/upload-complete')) {
      return json({'scan_id': 's1', 'record_no': 'REC-12', 'attempt_no': 1, 'processing_status': 'extracting'}, 202);
    }
    if (r.url.path.endsWith('/discard')) return http.Response('', 204);
    return json({});
  }
}

Future<(ScanUploader, FakeCaptureApi)> uploader() async {
  final api = FakeCaptureApi();
  final rig = await signedIn(api.call);
  var n = 0;
  return (ScanUploader(ScanRepository(rig.api), newId: () => 'new-${++n}'), api);
}

void main() {
  test('GIVEN 2 photos WHEN sent THEN create, photo 1, photo 2, confirm, in that order', () async {
    final (up, api) = await uploader();
    final draft = draftWith(2);
    final scan = await up.send(draft, buId: 'b1', locationNodeId: 'bin-05');
    expect(api.calls, [
      'POST /business-units/b1/scans',
      'PUT /scans/scan-1/photos/1',
      'PUT /scans/scan-1/photos/2',
      'POST /scans/scan-1/upload-complete',
    ]);
    expect(api.keys, ['cap-1']);
    expect(api.bodies.single, containsPair('photo_count', 2));
    expect(api.bodies.single, containsPair('location_node_id', 'bin-05'));
    expect(api.bodies.single, containsPair('equipment_type_id', 't1'));
    expect(scan.scanId, 'scan-1');
  });

  test('GIVEN a photo upload fails WHEN sent again THEN the same capture id is reused (no duplicate)', () async {
    final (up, api) = await uploader();
    var fail = true;
    api.override = (r) => r.method == 'PUT' && fail ? problem(503, 'service-unavailable') : null;
    final draft = draftWith(2);
    await expectLater(up.send(draft, buId: 'b1', locationNodeId: 'bin-05'), throwsA(isA<ApiException>()));
    expect(api.calls.where((c) => c.endsWith('/upload-complete')), isEmpty); // no outbox event yet

    fail = false;
    await up.send(draft, buId: 'b1', locationNodeId: 'bin-05');
    expect(api.keys, ['cap-1', 'cap-1']);
    expect(api.calls.last, 'POST /scans/scan-2/upload-complete');
    expect(api.calls.where((c) => c.contains('/discard')), isEmpty);
  });

  test('GIVEN a half-sent scan WHEN the location changes THEN it is discarded and a new id is used', () async {
    final (up, api) = await uploader();
    api.override = (r) => r.method == 'PUT' ? problem(503, 'service-unavailable') : null;
    final draft = draftWith(1);
    await expectLater(up.send(draft, buId: 'b1', locationNodeId: 'bin-05'), throwsA(isA<ApiException>()));

    api.override = null;
    await up.send(draft, buId: 'b1', locationNodeId: 'bin-07');
    expect(api.calls, contains('POST /scans/scan-1/discard'));
    expect(api.keys, ['cap-1', 'new-1']);
    expect(draft.clientCaptureId, 'new-1');
    expect(api.bodies.last, containsPair('location_node_id', 'bin-07'));
  });

  test('GIVEN a half-sent scan WHEN a photo is added THEN it starts fresh with the new count', () async {
    final (up, api) = await uploader();
    api.override = (r) => r.method == 'PUT' ? problem(503, 'service-unavailable') : null;
    final draft = draftWith(1);
    await expectLater(up.send(draft, buId: 'b1', locationNodeId: 'bin-05'), throwsA(isA<ApiException>()));

    api.override = null;
    draft.photos.add(draftWith(1).photos.single);
    await up.send(draft, buId: 'b1', locationNodeId: 'bin-05');
    expect(api.keys.last, 'new-1');
    expect(api.bodies.last, containsPair('photo_count', 2));
  });

  test('GIVEN the confirm answer was lost WHEN sent again THEN no photo is re-sent and it counts as sent', () async {
    final (up, api) = await uploader();
    final draft = draftWith(2);
    var lost = true;
    api.override = (r) => r.url.path.endsWith('/upload-complete') && lost ? throw http.ClientException('lost') : null;
    await expectLater(up.send(draft, buId: 'b1', locationNodeId: 'bin-05'), throwsA(isA<ApiException>()));

    // The API did confirm it: the same capture now comes back as extracting.
    lost = false;
    api.override = (r) => r.method == 'POST' && r.url.path.endsWith('/scans')
        ? json(scanJson(processing: 'extracting')..['scan_id'] = 'scan-1', 200)
        : null;
    api.calls.clear();
    final scan = await up.send(draft, buId: 'b1', locationNodeId: 'bin-05');
    expect(scan.scanId, 'scan-1');
    expect(api.calls, ['POST /business-units/b1/scans']);
  });

  test('GIVEN the type was unpublished WHEN sent THEN the 409 reaches the screen, nothing uploaded', () async {
    final (up, api) = await uploader();
    api.override = (r) => r.url.path.endsWith('/scans') ? problem(409, 'type-not-published') : null;
    await expectLater(
      up.send(draftWith(1), buId: 'b1', locationNodeId: 'bin-05'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'type-not-published')),
    );
    expect(api.calls.where((c) => c.startsWith('PUT')), isEmpty);
  });

  test('GIVEN the capture time WHEN sent THEN it goes as UTC with an offset', () async {
    final (up, api) = await uploader();
    await up.send(draftWith(1), buId: 'b1', locationNodeId: 'bin-05');
    expect(api.bodies.single['captured_at'], '2026-11-03T00:00:00.000Z');
    expect(CaptureDraft.maxPhotos, 4);
  });
}
