import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pixorex_mobile/features/scan/location_pick.dart';
import 'package:pixorex_mobile/features/scan/my_scans_screen.dart';
import 'package:pixorex_mobile/features/scan/scan_models.dart';
import 'package:pixorex_mobile/features/scan/scan_repository.dart';

import 'auth_flow_test.dart' show Rig, json, meJson, pumpApp;
import 'home_screen_test.dart' show now, row;
import 'location_pick_test.dart' show tree;
import 'location_screen_test.dart' show treeJson;
import 'new_scan_screen_test.dart' show signedIn, typesPage;
import 'photo_set_screen_test.dart' show FakePhotoSource, jpeg;
import 'review_screen_test.dart' show valve;
import 'scan_repository_test.dart' show scanJson;

Map<String, dynamic> scanRow(String type, String processing, String review, {int attempts = 1}) =>
    row(type, processing, review)..['attempts_used'] = attempts;

/// My Scans and the calls made from it.
class ScansApi {
  List<Map<String, dynamic>> items = [
    scanRow('Paint Label', 'failed', 'draft'),
    scanRow('Chemical Label', 'retake_required', 'draft', attempts: 3),
    scanRow('Control Valve', 'ready_to_review', 'draft'),
    scanRow('AC Generator', 'extracting', 'draft', attempts: 2),
    scanRow('HVAC Chiller', 'ready_to_review', 'approved'),
  ];
  final queries = <Map<String, String>>[];
  final posts = <String>[];

  Future<http.Response> call(http.BaseRequest r) async {
    final p = r.url.path;
    if (p.endsWith('/me')) return json(meJson());
    if (p.endsWith('/me/scans')) {
      queries.add(r.url.queryParameters);
      return json({'items': items, 'page': {'next_cursor': null}});
    }
    if (r.method == 'POST') {
      posts.add(p.replaceFirst('/api/v1', ''));
      if (p.endsWith('/retry-extraction')) {
        return json({'attempt_no': 2, 'trigger': 'retry', 'status': 'queued', 'detected_label': null, 'suggested_type_id': null, 'suggestion_confidence': null}, 202);
      }
    }
    return json({});
  }
}

Future<(ScansApi, List<String>)> pumpMyScans(WidgetTester t, {ScansApi? api, String? tab}) async {
  t.view.physicalSize = const Size(1170, 2532);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  final a = api ?? ScansApi();
  final rig = await signedIn(a.call);
  final retakes = <String>[];
  await t.pumpWidget(MaterialApp(
    home: MyScansScreen(
      scans: ScanRepository(rig.api),
      unitName: 'PPG Plant 04',
      initialTab: tab,
      clock: () => now,
      searchDelay: const Duration(milliseconds: 10),
      onRetake: (old) async {
        retakes.add(old.equipmentTypeName);
        return true;
      },
    ),
  ));
  await t.pumpAndSettle();
  return (a, retakes);
}

void main() {
  testWidgets('GIVEN scans WHEN All is open THEN what needs action comes first, with its next step', (t) async {
    await pumpMyScans(t);
    expect(find.text('NEEDS YOUR ACTION'), findsOneWidget);
    expect(find.text('IN PROGRESS & DONE'), findsOneWidget);
    expect(find.text("Couldn't read this image · try 1 of 3"), findsOneWidget);
    expect(find.text('Retry (2 left)'), findsOneWidget);
    expect(find.text('Failed 3 times — retake the photo'), findsOneWidget);
    expect(find.text('No retries left'), findsOneWidget);
    expect(find.text('Retake photo'), findsOneWidget);
    expect(find.text('Bin 07 · ready to check'), findsOneWidget);
    expect(find.text('Attempt 2 of 3 · 5 min ago'), findsOneWidget);
    expect(
      t.getTopLeft(find.text('Control Valve')).dy,
      lessThan(t.getTopLeft(find.text('AC Generator')).dy),
    );
  });

  testWidgets('GIVEN a tab or a search WHEN chosen THEN the API is asked with it', (t) async {
    final (api, _) = await pumpMyScans(t);
    await t.tap(find.text('Needs action'));
    await t.pumpAndSettle();
    expect(api.queries.last, containsPair('tab', 'needs_action'));
    expect(find.text('NEEDS YOUR ACTION'), findsNothing); // a single tab isn't split

    await t.enterText(find.byType(TextField), 'SN-1077');
    await t.pump(const Duration(milliseconds: 20));
    await t.pumpAndSettle();
    expect(api.queries.last, {'tab': 'needs_action', 'q': 'SN-1077', 'limit': '25'});
  });

  testWidgets('GIVEN Home asks for Needs action WHEN opened THEN that tab is chosen', (t) async {
    final (api, _) = await pumpMyScans(t, tab: 'needs_action');
    expect(api.queries.single, containsPair('tab', 'needs_action'));
  });

  testWidgets('GIVEN a failed scan WHEN Retry is tapped THEN the worker tries again', (t) async {
    final (api, _) = await pumpMyScans(t);
    await t.tap(find.text('Retry (2 left)'));
    await t.pumpAndSettle();
    expect(api.posts, ['/scans/s-Paint%20Label/retry-extraction']);
    expect(find.text('Retrying extraction — attempt 2 of 3'), findsOneWidget);
  });

  testWidgets('GIVEN a scan out of tries WHEN Retake photo is tapped THEN a new scan starts for it', (t) async {
    final (_, retakes) = await pumpMyScans(t);
    await t.tap(find.text('Retake photo'));
    await t.pumpAndSettle();
    expect(retakes, ['Chemical Label']);
    expect(find.text('New scan created · old one closed'), findsOneWidget);
  });

  testWidgets('GIVEN no scans match WHEN searching THEN it says so', (t) async {
    final api = ScansApi()..items = [];
    await pumpMyScans(t, api: api);
    expect(find.text('No scans here yet.'), findsOneWidget);
  });

  test('GIVEN a node deep in the tree WHEN starting there THEN the whole path is picked', () {
    final p = LocationPick.at(tree, 'A');
    expect(p.nodeIds, ['Plant 04', 'Building C', 'Paint Shop', 'Bin 05', 'A']);
    expect(LocationPick.at(tree, 'gone').nodeIds, ['Plant 04']);
  });

  group('type mismatch and discard (design 54, 55)', () {
    Map<String, dynamic> mismatched() => valve()
      ..['latest_attempt'] = {
        'attempt_no': 1,
        'trigger': 'first',
        'status': 'succeeded',
        'detected_label': 'Air conditioner remote control',
        'suggested_type_id': 't-Other',
        'suggestion_confidence': 0.9,
      };

    Future<List<String>> openMismatch(WidgetTester t) async {
      t.view.physicalSize = const Size(1170, 2532);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final calls = <String>[];
      var scan = mismatched();
      final rig = Rig((r) async {
        final p = r.url.path;
        if (p.endsWith('/me')) return json(meJson());
        if (p.endsWith('/me/scans')) {
          return json({'items': [scanRow('Control Valve V-071', 'ready_to_review', 'draft')..['scan_id'] = 's1'], 'page': {'next_cursor': null}});
        }
        if (p.endsWith('/equipment-types')) return json(typesPage(['Other', 'Control Valve V-071']));
        if (r.method == 'POST') {
          calls.add('${p.replaceFirst('/api/v1', '')} ${(r as http.Request).body}');
          if (p.endsWith('/re-extract')) scan = valve(processing: 'extracting');
          return http.Response('', p.endsWith('/discard') ? 204 : 202);
        }
        return json(scan);
      });
      await rig.session.signIn(loginHint: 'j@x.co');
      await t.pumpWidget(MaterialApp(home: MyScansScreen(scans: ScanRepository(rig.api), unitName: 'PPG Plant 04', clock: () => now)));
      await t.pumpAndSettle();
      await t.tap(find.text('Control Valve V-071'));
      await t.pumpAndSettle();
      return calls;
    }

    testWidgets('GIVEN another type was read WHEN the scan opens THEN the choice is offered', (t) async {
      final calls = await openMismatch(t);
      expect(find.text('Type mismatch'), findsOneWidget);
      expect(find.textContaining('Image appears to be: Air conditioner remote control.'), findsOneWidget);
      expect(find.textContaining('You selected: Control Valve V-071.'), findsOneWidget);
      expect(find.textContaining('Suggested type: Other.'), findsOneWidget);

      await t.tap(find.text('Re-extract as Other'));
      await t.pump(const Duration(milliseconds: 500));
      expect(calls.single, startsWith('/scans/s1/re-extract'));
      expect(jsonDecode(calls.single.split(' ').skip(1).join(' ')), {'equipment_type_id': 't-Other'});
      expect(find.text('Reading the label…'), findsOneWidget);
    });

    testWidgets('GIVEN the mismatch WHEN Keep results THEN the review stays as read', (t) async {
      final calls = await openMismatch(t);
      await t.tap(find.text('Keep results'));
      await t.pumpAndSettle();
      expect(calls, isEmpty);
      expect(find.text('Low confidence · 42%'), findsOneWidget);
    });

    testWidgets('GIVEN the mismatch WHEN Discard is confirmed THEN the scan is discarded and My Scans says so', (t) async {
      final calls = await openMismatch(t);
      await t.tap(find.text('Discard'));
      await t.pumpAndSettle();
      expect(find.text('Discard Control Valve V-071?'), findsOneWidget);
      expect(find.text("It's removed from My Scans and can't be recovered. Nothing is sent to the reviewer."), findsOneWidget);
      await t.tap(find.text('Discard scan'));
      await t.pumpAndSettle();
      expect(calls.single, startsWith('/scans/s1/discard'));
      expect(find.text('Control Valve V-071 discarded'), findsOneWidget);
    });
  });

  testWidgets('GIVEN a scan out of tries WHEN retaken through the app THEN the new scan replaces it', (t) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final created = <Map<String, dynamic>>[];
    final old = scanJson(processing: 'retake_required')
      ..['scan_id'] = 'old-1'
      ..['equipment_type_id'] = 't-Motor Nameplate'
      ..['equipment_type_name'] = 'Motor Nameplate'
      ..['location_node_id'] = 'Bin 07';
    final rig = Rig((r) async {
      final p = r.url.path;
      if (p.endsWith('/me')) return json(meJson());
      if (p.endsWith('/me/scans')) {
        return json({'items': [scanRow('Motor Nameplate', 'retake_required', 'draft', attempts: 3)..['scan_id'] = 'old-1'], 'page': {'next_cursor': null}});
      }
      if (p.endsWith('/equipment-types')) return json(typesPage(['Motor Nameplate']));
      if (p.endsWith('/locations/published')) return json(treeJson);
      if (p.endsWith('/scans/old-1')) return json(old);
      if (r.method == 'POST' && p.endsWith('/scans')) {
        created.add(jsonDecode((r as http.Request).body) as Map<String, dynamic>);
        return json(scanJson(processing: 'uploading')..['scan_id'] = 'new-1', 201);
      }
      if (r.method == 'PUT') return http.Response('', 204);
      return json({}, 202);
    });
    await rig.session.signIn(loginHint: 'j@x.co');
    await pumpApp(t, rig, photoSource: () => FakePhotoSource([jpeg(90)]));

    await t.tap(find.text('My Scans'));
    await t.pumpAndSettle();
    await t.tap(find.text('Retake photo'));
    await t.pumpAndSettle();
    expect(find.text('New scan · retake'), findsOneWidget);
    expect(find.textContaining('The unreadable Motor Nameplate is closed and kept with its history'), findsOneWidget);
    expect(find.text('Motor Nameplate'), findsOneWidget); // type kept from the old scan

    await t.tap(find.byKey(const Key('shutter')));
    await t.pumpAndSettle();
    await t.tap(find.text('Next · 1 photo'));
    await t.pumpAndSettle();
    expect(find.text('LOCATION OF THE OLD SCAN'), findsOneWidget);
    expect(find.text('Bin 07'), findsWidgets);

    await t.tap(find.text('Submit scan'));
    await t.pumpAndSettle();
    expect(created.single['retake_of_scan_id'], 'old-1');
    expect(created.single['location_node_id'], 'Bin 07');
    expect(created.single['equipment_type_id'], 't-Motor Nameplate');
    expect(find.text('New scan created · old one closed'), findsOneWidget);
    expect(find.text('My Scans'), findsWidgets); // back where the retake started
  });

  test('Scan carries its unit and location node for a retake', () {
    final s = Scan.fromJson(scanJson()..['location_node_id'] = 'n9');
    expect(s.buId, 'b1');
    expect(s.locationNodeId, 'n9');
  });
}
