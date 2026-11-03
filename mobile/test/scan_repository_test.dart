import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pixorex_mobile/core/api_client.dart';
import 'package:pixorex_mobile/core/api_exception.dart';
import 'package:pixorex_mobile/core/device_id.dart';
import 'package:pixorex_mobile/core/secure_store.dart';
import 'package:pixorex_mobile/features/scan/scan_repository.dart';

ApiClient clientFor(MockClient m) => ApiClient(
      http: m,
      deviceId: DeviceIdStore(MemorySecureStore()),
      accessToken: () async => 'tok',
      baseUrl: 'http://api.test/api/v1',
    );

ScanRepository repoFor(MockClient m) => ScanRepository(clientFor(m));

http.Response json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

Map<String, dynamic> scanJson({
  String processing = 'ready_to_review',
  String typeId = 't1',
  String? suggested,
}) =>
    {
      'scan_id': 's1',
      'record_no': 'REC-12',
      'bu_id': 'b1',
      'equipment_type_id': typeId,
      'equipment_type_name': 'Motor',
      'contract_id': 'c1',
      'location_node_id': 'n1',
      'location_path': 'Plant 04 / Line 2',
      'processing_status': processing,
      'review_status': 'draft',
      'retake_of_scan_id': null,
      'photos': [
        {'photo_no': 2, 'view_url': 'https://minio/2'},
        {'photo_no': 1, 'view_url': 'https://minio/1'},
      ],
      'attempts_used': 1,
      'latest_attempt': {
        'attempt_no': 1,
        'trigger': 'first',
        'status': 'succeeded',
        'detected_label': 'Transformer nameplate',
        'suggested_type_id': suggested,
        'suggestion_confidence': 0.9,
      },
      'fields': [
        {
          'field_key': 'serial',
          'label': 'Serial number',
          'data_type': 'text',
          'is_required': true,
          'is_critical': true,
          'ai_value': 'SN-1O77',
          'confidence': 0.42,
          'flag_reasons': ['low_confidence'],
        },
      ],
      'captured_at': '2026-11-03T09:30:00Z',
    };

void main() {
  group('ApiClient additions', () {
    test('GIVEN query values WHEN get THEN nulls and empties are left out', () async {
      late Uri seen;
      final c = clientFor(MockClient((r) async {
        seen = r.url;
        return json({});
      }));
      await c.get('/me/scans', query: {'tab': 'needs_action', 'q': '', 'cursor': null});
      expect(seen.path, '/api/v1/me/scans');
      expect(seen.queryParameters, {'tab': 'needs_action'});
    });

    test('GIVEN a 409 with fields WHEN parsed THEN the labels are kept', () {
      final e = ApiException.fromProblem(409, {
        'type': '/problems/required-fields-empty',
        'title': 'Required fields empty',
        'fields': ['Serial number', 'Voltage'],
      });
      expect(e.code, 'required-fields-empty');
      expect(e.fields, ['Serial number', 'Voltage']);
    });
  });

  group('ScanRepository', () {
    test('GIVEN a capture WHEN createScan THEN client_capture_id is the idempotency key', () async {
      late http.Request seen;
      final repo = repoFor(MockClient((r) async {
        seen = r;
        return json(scanJson(processing: 'uploading'), 201);
      }));
      final scan = await repo.createScan(
        buId: 'b1',
        clientCaptureId: 'cap-1',
        equipmentTypeId: 't1',
        locationNodeId: 'n1',
        photoCount: 2,
        capturedAt: DateTime.utc(2026, 11, 3, 9, 30),
      );
      final body = jsonDecode(seen.body) as Map<String, dynamic>;
      expect(seen.url.path, '/api/v1/business-units/b1/scans');
      expect(seen.headers['Idempotency-Key'], 'cap-1');
      expect(body['client_capture_id'], 'cap-1');
      expect(body['captured_at'], '2026-11-03T09:30:00.000Z');
      expect(body.containsKey('retake_of_scan_id'), isFalse);
      expect(scan.recordNo, 'REC-12');
    });

    test('GIVEN JPEG bytes WHEN uploadPhoto THEN it PUTs raw bytes with a SHA-256 digest', () async {
      late http.Request seen;
      final repo = repoFor(MockClient((r) async {
        seen = r;
        return http.Response('', 204);
      }));
      await repo.uploadPhoto('s1', 1, utf8.encode('abc'));
      expect(seen.method, 'PUT');
      expect(seen.url.path, '/api/v1/scans/s1/photos/1');
      expect(seen.headers['Content-Type'], startsWith('image/jpeg'));
      // SHA-256("abc"), base64
      expect(seen.headers['Content-Digest'], 'sha-256=:ungWv48Bz+pBQUDeXa4iI7ADYaOWF3qctBD/YfIAFa0=:');
      expect(seen.bodyBytes, utf8.encode('abc'));
    });

    test('GIVEN a finished scan WHEN read THEN photos are in order and flags are parsed', () async {
      final repo = repoFor(MockClient((r) async => json(scanJson())));
      final scan = await repo.scan('s1');
      expect(scan.isSettled, isTrue);
      expect(scan.photoUrls, ['https://minio/1', 'https://minio/2']);
      expect(scan.fields.single.isFlagged, isTrue);
      expect(scan.fields.single.confidence, 0.42);
      expect(scan.hasTypeMismatch, isFalse);
    });

    test('GIVEN the AI suggests another type WHEN read THEN it is a type mismatch', () async {
      final repo = repoFor(MockClient((r) async => json(scanJson(suggested: 't2'))));
      expect((await repo.scan('s1')).hasTypeMismatch, isTrue);
    });

    test('GIVEN a scan still extracting WHEN read THEN keep polling', () async {
      final repo = repoFor(MockClient((r) async => json(scanJson(processing: 'extracting'))));
      expect((await repo.scan('s1')).isSettled, isFalse);
    });

    test('GIVEN a submit WHEN submitRevision THEN verdicts, flag and the caller key are sent', () async {
      late http.Request seen;
      final repo = repoFor(MockClient((r) async {
        seen = r;
        return json({'revision_no': 1, 'review_status': 'waiting_for_approval'}, 201);
      }));
      await repo.submitRevision('s1',
          idempotencyKey: 'press-1',
          submitAnyway: true,
          fields: [
            {'field_key': 'serial', 'verification_state': 'corrected', 'value': 'SN-1077'},
          ]);
      expect(seen.url.path, '/api/v1/scans/s1/revisions');
      expect(seen.headers['Idempotency-Key'], 'press-1');
      expect(jsonDecode(seen.body), {
        'fields': [
          {'field_key': 'serial', 'verification_state': 'corrected', 'value': 'SN-1077'},
        ],
        'submit_anyway': true,
      });
    });

    test('GIVEN photos missing WHEN confirmUpload THEN the 409 code reaches the caller', () async {
      final repo = repoFor(MockClient((r) async => json(
          {'type': '/problems/photos-missing', 'title': 'Photos missing', 'status': 409}, 409)));
      await expectLater(
        repo.confirmUpload('s1'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'photos-missing')),
      );
    });

    test('GIVEN a type mismatch WHEN reExtract THEN it sends the new type with a fresh key', () async {
      late http.Request seen;
      final repo = repoFor(MockClient((r) async {
        seen = r;
        return json({}, 202);
      }));
      await repo.reExtract('s1', 't2');
      expect(seen.url.path, '/api/v1/scans/s1/re-extract');
      expect(seen.headers['Idempotency-Key'], isNotEmpty);
      expect(jsonDecode(seen.body), {'equipment_type_id': 't2'});
    });
  });
}
