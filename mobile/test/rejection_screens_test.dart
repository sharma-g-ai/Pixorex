import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pixorex_mobile/features/scan/capture_models.dart';
import 'package:pixorex_mobile/features/scan/my_scans_screen.dart';
import 'package:pixorex_mobile/features/scan/rejection_screens.dart';
import 'package:pixorex_mobile/features/scan/review_model.dart';
import 'package:pixorex_mobile/features/scan/scan_models.dart';
import 'package:pixorex_mobile/features/scan/scan_repository.dart';

import 'auth_flow_test.dart' show json, meJson;
import 'home_screen_test.dart' show now, row;
import 'new_scan_screen_test.dart' show signedIn;
import 'photo_set_screen_test.dart' show FakePhotoSource, jpeg;
import 'review_screen_test.dart' show fieldJson, valve;
import 'scan_uploader_test.dart' show FakeCaptureApi;

Map<String, dynamic> sent(String state, {String? value, String? reason, String? note}) =>
    {'verification_state': state, 'value': value, 'unreadable_reason': reason, 'note': note};

/// Design 68-69: the valve, rejected by Bo with a note, as the technician last sent it.
Map<String, dynamic> rejected({String? note = "Serial number doesn't match tag pattern"}) => valve(review: 'rejected')
  ..['photos'] = []
  ..['fields'] = [
    fieldJson('model', 'Model number', 'CR 32-4-1', flags: ['low_confidence'], confidence: 0.42)..['submitted'] = sent('accepted', value: 'CR 32-4-1'),
    fieldJson('serial', 'Serial number', '98274-A3', flags: ['no_confidence'])..['submitted'] = sent('corrected', value: 'SN-4471-8'),
    fieldJson('barcode', 'Barcode', null, flags: ['missing_required'], required: true)
      ..['submitted'] = sent('unreadable', reason: 'label_worn'),
    fieldJson('manufacturer', 'Manufacturer', 'Brady', confidence: 0.97)..['submitted'] = sent('accepted', value: 'Brady'),
  ]
  ..['rejection'] = {
    'category': 'data_correction_needed',
    'note': note,
    'reviewer_name': 'Bo Plant04',
    'decided_at': now.subtract(const Duration(days: 1)).toUtc().toIso8601String(),
  };

/// My Scans, the rejected scan, its revisions, and the calls of a retake.
class RejectApi extends FakeCaptureApi {
  RejectApi() {
    rows = [
      row('Control Valve V-071', 'ready_to_review', 'rejected')
        ..['scan_id'] = 's1'
        ..['reviewer_name'] = 'Bo Plant04',
    ];
  }
  late List<Map<String, dynamic>> rows;
  Map<String, dynamic> scan = rejected();
  final revisions = <Map<String, dynamic>>[];

  @override
  Future<http.Response> call(http.BaseRequest r) async {
    final p = r.url.path;
    if (p.endsWith('/me')) return json(meJson());
    if (p.endsWith('/me/scans')) return json({'items': rows, 'page': {'next_cursor': null}});
    if (p.endsWith('/revisions')) {
      revisions.add(jsonDecode((r as http.Request).body) as Map<String, dynamic>);
      return json({'revision_id': 'r2', 'revision_no': 2, 'origin': 'rejection_fix', 'empty_required_fields': [], 'review_status': 'waiting_for_approval'}, 201);
    }
    if (r.method == 'GET' && p.endsWith('/scans/s1')) return json(scan);
    return super.call(r);
  }
}

Future<(RejectApi, List<String>)> pumpMyScans(WidgetTester t, {RejectApi? api}) async {
  t.view.physicalSize = const Size(1170, 4200);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  final a = api ?? RejectApi();
  final rig = await signedIn(a.call);
  final retakes = <String>[];
  await t.pumpWidget(MaterialApp(
    home: MyScansScreen(
      scans: ScanRepository(rig.api),
      unitName: 'PPG Plant 04',
      clock: () => now,
      onRetake: (old) async {
        retakes.add(old.scanId);
        return true;
      },
    ),
  ));
  await t.pumpAndSettle();
  return (a, retakes);
}

Future<void> openNotice(WidgetTester t) async {
  await t.tap(find.text('Control Valve V-071'));
  await t.pumpAndSettle();
}

void main() {
  group('RejectionFix', () {
    final scan = Scan.fromJson(rejected());

    test('GIVEN nothing changed WHEN sent THEN every field goes back as it was', () {
      final fix = RejectionFix(scan);
      expect(fix.fields.map((f) => f.fieldKey), ['model', 'serial', 'barcode', 'manufacturer']);
      expect(fix.body(), {
        'fields': [
          {'field_key': 'model', 'verification_state': 'accepted'},
          {'field_key': 'serial', 'verification_state': 'corrected', 'value': 'SN-4471-8'},
          {'field_key': 'barcode', 'verification_state': 'unreadable', 'unreadable_reason': 'label_worn'},
          {'field_key': 'manufacturer', 'verification_state': 'accepted'},
        ],
        'submit_anyway': false,
      });
    });

    test('GIVEN a field fixed WHEN sent THEN it goes as corrected; the same value again undoes it', () {
      final fix = RejectionFix(scan);
      final serial = scan.fields[1];
      fix.fix(serial, ' SN-44718-B ');
      expect(fix.corrected, 1);
      expect((fix.body()['fields'] as List)[1], {'field_key': 'serial', 'verification_state': 'corrected', 'value': 'SN-44718-B'});
      fix.fix(serial, 'SN-4471-8');
      expect(fix.corrected, 0);
    });

    test('GIVEN a required field left empty before WHEN sent unchanged THEN submit_anyway again', () {
      final json = rejected();
      (json['fields'] as List)[2]['submitted'] = sent('left_empty');
      final fix = RejectionFix(Scan.fromJson(json));
      expect(fix.body()['submit_anyway'], isTrue);
      fix.fix(fix.fields[2], '0 4567 89012 3');
      expect(fix.body()['submit_anyway'], isFalse);
    });
  });

  testWidgets('GIVEN a rejected scan WHEN opened THEN the notice shows who, why and the two ways (design 68)', (t) async {
    await pumpMyScans(t);
    expect(find.text('Sent back · tap to fix'), findsOneWidget);
    expect(find.text('REC-1 · Bin 07'), findsOneWidget);
    await openNotice(t);
    expect(find.text('Record rejected'), findsOneWidget);
    expect(find.text('Control Valve V-071 was rejected'), findsOneWidget);
    expect(find.text('Bin 05 · reviewed by Bo Plant04 · yesterday'), findsOneWidget);
    expect(find.text('Category: Data correction needed'), findsOneWidget);
    expect(find.text('Reviewer note'), findsOneWidget);
    expect(find.text('"Serial number doesn\'t match tag pattern"'), findsOneWidget);
    expect(find.text('Correct the fields'), findsOneWidget);
    expect(find.text('Retake required'), findsOneWidget);
    expect(find.textContaining('Only you can revise this scan'), findsOneWidget);
  });

  testWidgets('GIVEN no note WHEN the notice opens THEN only the category shows', (t) async {
    final api = RejectApi()..scan = rejected(note: null);
    await pumpMyScans(t, api: api);
    await openNotice(t);
    expect(find.text('Reviewer note'), findsNothing);
    expect(find.text('Category: Data correction needed'), findsOneWidget);
  });

  testWidgets('GIVEN Correct the fields WHEN a value is fixed and resubmitted THEN it goes back to Bo (design 69-70)',
      (t) async {
    final (api, _) = await pumpMyScans(t);
    await openNotice(t);
    await t.tap(find.text('Correct the fields'));
    await t.pumpAndSettle();

    expect(find.text('Bin 05 · Rejected by Bo Plant04'), findsOneWidget);
    expect(find.textContaining("Serial number doesn't match tag pattern"), findsOneWidget);
    expect(find.text('Checked'), findsNWidgets(3));
    expect(find.text('Unreadable · Label worn or damaged'), findsOneWidget);
    expect(find.text('Resubmit to Bo Plant04'), findsOneWidget);
    expect(find.text('Photo is the problem? Retake instead'), findsOneWidget);

    await t.tap(find.text('SN-4471-8'));
    await t.pumpAndSettle();
    expect(find.textContaining('Was: '), findsOneWidget);
    await t.enterText(find.byKey(const Key('fix-serial')), 'SN-44718-B');
    await t.pumpAndSettle();
    expect(find.text('Corrected by you'), findsOneWidget);

    await t.tap(find.text('Resubmit to Bo Plant04'));
    await t.pumpAndSettle();
    expect((api.revisions.single['fields'] as List)[1], {'field_key': 'serial', 'verification_state': 'corrected', 'value': 'SN-44718-B'});
    expect(find.text('My Scans'), findsOneWidget);
    expect(find.text('Control Valve V-071 resubmitted to Bo Plant04'), findsOneWidget);
  });

  testWidgets('GIVEN Retake required WHEN the retake is sent THEN back on My Scans, rejected scan closed', (t) async {
    final (_, retakes) = await pumpMyScans(t);
    await openNotice(t);
    await t.tap(find.text('Retake required'));
    await t.pumpAndSettle();
    expect(retakes, ['s1']);
    expect(find.text('New scan submitted · rejected scan closed'), findsOneWidget);
  });

  testWidgets('GIVEN fixing WHEN Retake instead is tapped THEN the retake starts from there too', (t) async {
    final (_, retakes) = await pumpMyScans(t);
    await openNotice(t);
    await t.tap(find.text('Correct the fields'));
    await t.pumpAndSettle();
    await t.tap(find.text('Photo is the problem? Retake instead'));
    await t.pumpAndSettle();
    expect(retakes, ['s1']);
    expect(find.text('New scan submitted · rejected scan closed'), findsOneWidget);
  });

  testWidgets('GIVEN a fix sent back, a retake and its closed original THEN My Scans reads as design 70 and 73', (t) async {
    final api = RejectApi()
      ..rows = [
        row('Equipment Label', 'extracting', 'draft', minAgo: 1, place: 'Bin 02')
          ..['scan_id'] = 'new'
          ..['retake_of_scan_id'] = 'old'
          ..['reviewer_name'] = 'S. Alvi',
        row('Equipment Label', 'ready_to_review', 'closed', minAgo: 1, place: 'Bin 02')
          ..['scan_id'] = 'old'
          ..['reviewer_name'] = 'S. Alvi',
        row('Control Valve V-071', 'ready_to_review', 'waiting_for_approval', minAgo: 30)
          ..['resubmitted'] = true
          ..['reviewer_name'] = 'S. Alvi',
      ];
    await pumpMyScans(t, api: api);
    expect(find.text('JUST NOW'), findsOneWidget);
    expect(find.text('Equipment Label · original'), findsOneWidget);
    expect(find.text('Retaken as a new scan'), findsOneWidget);
    expect(find.text('Closed'), findsOneWidget);
    expect(find.text('Extracting'), findsOneWidget);
    expect(find.text('Resubmitted'), findsOneWidget);
    expect(find.textContaining('back with'), findsNothing); // that is on Scan details
    expect(isRetakePair(MyScan.fromJson(api.rows[0])), isTrue);
  });

  testWidgets('GIVEN the retake screen WHEN a photo is taken and submitted THEN a new scan replaces the old (design 71-72)',
      (t) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final api = RejectApi();
    final rig = await signedIn(api.call);
    final popped = <bool?>[];
    final old = Scan.fromJson(rejected());
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => popped.add(await Navigator.of(context).push<bool>(MaterialPageRoute(
            builder: (_) => RejectedRetakeScreen(
              scans: ScanRepository(rig.api),
              old: old,
              type: const EquipmentType(typeId: 't1', name: 'Control Valve V-071'),
              photoSource: () => FakePhotoSource([jpeg(40), jpeg(80)]),
              clock: () => now,
            ),
          ))),
          child: const Text('go'),
        ),
      ),
    ));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();

    expect(find.text('New scan · retake'), findsOneWidget);
    expect(find.textContaining('The rejected Control Valve V-071 is closed and kept with its history'), findsOneWidget);
    expect(find.text('Location (from old scan)'), findsOneWidget);
    expect(find.text('Photograph the same equipment again'), findsOneWidget);

    await t.tap(find.byKey(const Key('shutter')));
    await t.pumpAndSettle();
    expect(find.text('Submit new scan'), findsNWidgets(2)); // title and button
    expect(find.text('Rejected · will be closed'), findsOneWidget);
    expect(find.text('New scan · Control Valve V-071'), findsOneWidget);
    expect(find.text('Control Valve V-071 (rejected)'), findsOneWidget);
    expect(find.text('Building C › Bin 05'), findsOneWidget);

    await t.tap(find.text('Retake again'));
    await t.pumpAndSettle();
    expect(find.text('New scan · retake'), findsOneWidget);
    expect(api.calls.where((c) => !c.startsWith('GET')), isEmpty); // nothing sent yet

    await t.tap(find.byKey(const Key('shutter')));
    await t.pumpAndSettle();
    await t.tap(find.text('Submit new scan').last);
    await t.pumpAndSettle();
    expect(api.calls.where((c) => !c.startsWith('GET')), [
      'POST /business-units/b1/scans',
      'PUT /scans/scan-1/photos/1',
      'POST /scans/scan-1/upload-complete',
    ]);
    expect(api.bodies.single['retake_of_scan_id'], 's1');
    expect(api.bodies.single['location_node_id'], 'n1');
    expect(popped, [true]);
  });
}
