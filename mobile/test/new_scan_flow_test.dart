import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pixorex_mobile/features/scan/location_pick.dart';

import 'auth_flow_test.dart' show Rig, json, meJson, pumpApp;
import 'location_screen_test.dart' show treeJson;
import 'new_scan_screen_test.dart' show typesPage;
import 'photo_set_screen_test.dart' show FakePhotoSource, jpeg;
import 'scan_uploader_test.dart' show FakeCaptureApi;

/// Everything the technician app calls in this flow.
class FlowApi extends FakeCaptureApi {
  @override
  Future<http.Response> call(http.BaseRequest r) async {
    final p = r.url.path;
    if (p.endsWith('/me')) return json(meJson());
    if (p.endsWith('/me/scans')) return json({'items': [], 'page': {'next_cursor': null}});
    if (p.endsWith('/equipment-types')) return json(typesPage(['Motor Nameplate', 'AC Generator Nameplate']));
    if (p.endsWith('/locations/published')) return json(treeJson);
    return super.call(r);
  }

  List<String> get capture => calls.where((c) => c.contains('/scans')).where((c) => !c.contains('/me/')).toList();
}

Future<(Rig, FlowApi, FakePhotoSource)> openNewScan(WidgetTester t) async {
  t.view.physicalSize = const Size(1170, 2532);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  final api = FlowApi();
  final source = FakePhotoSource([jpeg(40), jpeg(80), jpeg(120)]);
  final rig = Rig(api.call);
  await rig.session.signIn(loginHint: 'j@x.co');
  await pumpApp(t, rig, photoSource: () => source);
  await t.tap(find.byTooltip('New scan'));
  await t.pumpAndSettle();
  return (rig, api, source);
}

Future<void> takeTwoPhotosAndChooseBin05A(WidgetTester t) async {
  await t.tap(find.text('Select equipment type'));
  await t.pumpAndSettle();
  await t.tap(find.text('AC Generator Nameplate'));
  await t.pumpAndSettle();
  await t.tap(find.byKey(const Key('shutter')));
  await t.pumpAndSettle();
  expect(find.text('Photo 1 of 1'), findsOneWidget);

  await t.tap(find.text('Add photo'));
  await t.pumpAndSettle();
  await t.tap(find.byKey(const Key('shutter')));
  await t.pumpAndSettle();
  await t.tap(find.text('Next · 2 photos'));
  await t.pumpAndSettle();

  expect(find.text('Choose location'), findsOneWidget); // first scan in this unit
  expect(find.text('2 photos · ready to submit'), findsOneWidget);
  await t.tap(find.text('Choose').first);
  await t.pumpAndSettle();
  for (final pick in ['Building C', 'Paint Shop', 'Bin 05', 'A']) {
    await t.tap(find.text(pick));
    await t.pumpAndSettle();
  }
}

void main() {
  testWidgets('GIVEN a technician WHEN they capture, choose a location and submit '
      'THEN the scan is created, photos uploaded, extraction queued, and New scan is ready again', (t) async {
    final (rig, api, _) = await openNewScan(t);
    await takeTwoPhotosAndChooseBin05A(t);
    expect(api.capture, isEmpty); // nothing is sent before Submit

    await t.tap(find.text('Submit scan'));
    await t.pumpAndSettle();

    expect(api.capture, [
      'POST /business-units/b1/scans',
      'PUT /scans/scan-1/photos/1',
      'PUT /scans/scan-1/photos/2',
      'POST /scans/scan-1/upload-complete',
    ]);
    expect(api.bodies.single['client_capture_id'], api.keys.single);
    expect(api.bodies.single['location_node_id'], 'A');
    expect(api.bodies.single['equipment_type_id'], 't-AC Generator Nameplate');

    expect(find.text('Scan queued — extracting in background'), findsOneWidget);
    expect(find.text('New scan'), findsOneWidget);
    expect(find.text('AC Generator Nameplate'), findsOneWidget); // type kept for the next item

    final saved = await LastLocationStore(rig.mem).read('b1');
    expect(saved?.nodeIds, ['Plant 04', 'Building C', 'Paint Shop', 'Bin 05', 'A']);
  });

  testWidgets('GIVEN the connection drops WHEN Submit is pressed THEN a message, and pressing again sends once',
      (t) async {
    final (_, api, _) = await openNewScan(t);
    await takeTwoPhotosAndChooseBin05A(t);
    var down = true;
    api.override = (r) => down && r.method == 'PUT' ? throw http.ClientException('down') : null;

    await t.tap(find.text('Submit scan'));
    await t.pumpAndSettle();
    expect(find.text("Couldn't send the scan. Check your connection and tap Submit scan again."), findsOneWidget);
    expect(find.text('Choose location'), findsOneWidget); // still here, nothing lost

    down = false;
    await t.tap(find.text('Submit scan'));
    await t.pumpAndSettle();
    expect(api.keys.toSet(), hasLength(1)); // same client_capture_id both times
    expect(api.calls.where((c) => c.endsWith('/upload-complete')), hasLength(1));
    expect(find.text('Scan queued — extracting in background'), findsOneWidget);
  });

  testWidgets('GIVEN a second scan WHEN it reaches the location THEN the last one is pre-selected', (t) async {
    final (_, _, source) = await openNewScan(t);
    await takeTwoPhotosAndChooseBin05A(t);
    await t.tap(find.text('Submit scan'));
    await t.pumpAndSettle();

    source.shots.add(jpeg(160));
    await t.tap(find.byKey(const Key('shutter')));
    await t.pumpAndSettle();
    await t.tap(find.text('Next · 1 photo'));
    await t.pumpAndSettle();
    expect(find.text('Confirm location'), findsOneWidget);
    expect(find.text('Bin 05 · A'), findsOneWidget);
    expect(find.text('Used for your last scan, just now'), findsOneWidget);
  });

  testWidgets('GIVEN the camera is closed without a photo WHEN back on New scan THEN nothing happens', (t) async {
    final (_, api, source) = await openNewScan(t);
    source.shots.clear();
    await t.tap(find.text('Select equipment type'));
    await t.pumpAndSettle();
    await t.tap(find.text('Motor Nameplate'));
    await t.pumpAndSettle();
    await t.tap(find.text('Gallery'));
    await t.pumpAndSettle();
    expect(find.text('New scan'), findsOneWidget);
    expect(api.capture, isEmpty);
  });
}
