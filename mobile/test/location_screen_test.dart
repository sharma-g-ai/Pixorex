import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pixorex_mobile/core/secure_store.dart';
import 'package:pixorex_mobile/features/scan/location_pick.dart';
import 'package:pixorex_mobile/features/scan/location_screen.dart';
import 'package:pixorex_mobile/features/scan/scan_repository.dart';
import 'package:pixorex_mobile/widgets/auth_widgets.dart';

import 'auth_flow_test.dart' show json, problem;
import 'new_scan_screen_test.dart' show signedIn;

final now = DateTime.utc(2026, 11, 3, 10);

Map<String, dynamic> node(String id, String level, [List<Map<String, dynamic>> children = const []]) =>
    {'node_id': id, 'level_id': level, 'name': id, 'children': children};

/// Plant 04 › Building C › Paint Shop › Bin 05 (A, B) / Bin 07 ; Building C › Bin 09
final treeJson = {
  'levels': [
    {'level_id': 'L1', 'level_name': 'Facility', 'level_order': 1, 'requirement': 'required'},
    {'level_id': 'L2', 'level_name': 'Building', 'level_order': 2, 'requirement': 'required'},
    {'level_id': 'L3', 'level_name': 'Shop', 'level_order': 3, 'requirement': 'optional'},
    {'level_id': 'L4', 'level_name': 'Bin', 'level_order': 4, 'requirement': 'required'},
    {'level_id': 'L5', 'level_name': 'Sub-bin', 'level_order': 5, 'requirement': 'optional'},
  ],
  'tree_snapshot': {
    'nodes': [
      node('Plant 04', 'L1', [
        node('Building C', 'L2', [
          node('Paint Shop', 'L3', [
            node('Bin 05', 'L4', [node('A', 'L5'), node('B', 'L5')]),
            node('Bin 07', 'L4'),
          ]),
          node('Bin 09', 'L4'),
        ]),
      ]),
    ],
  },
  'published_at': '2026-11-01T10:00:00Z',
};

class Harness {
  final store = MemorySecureStore();
  late final LastLocationStore last = LastLocationStore(store);
  final submitted = <List<String>>[];
}

Future<Harness> pumpLocation(
  WidgetTester t, {
  List<String>? remembered,
  Future<http.Response> Function(http.BaseRequest)? api,
}) async {
  // A 390 × 844 phone, as in the design, so lower rows are on screen.
  t.view.physicalSize = const Size(1170, 2532);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  final h = Harness();
  if (remembered != null) await h.last.save('b1', remembered, now.subtract(const Duration(minutes: 8)));
  final rig = await signedIn(api ?? (r) async => json(treeJson));
  await t.pumpWidget(MaterialApp(
    home: LocationScreen(
      scans: ScanRepository(rig.api),
      lastLocations: h.last,
      buId: 'b1',
      unitName: 'PPG Plant 04 — Coatings',
      tenantName: 'PPG Industries',
      typeName: 'AC Generator Nameplate',
      photoCount: 2,
      clock: () => now,
      onSubmit: (pick) async => h.submitted.add(pick.nodeIds),
    ),
  ));
  await t.pumpAndSettle();
  return h;
}

bool submitEnabled(WidgetTester t) =>
    t.widget<PillButton>(find.widgetWithText(PillButton, 'Submit scan')).onPressed != null;

void main() {
  testWidgets('GIVEN a last-used location WHEN the screen opens THEN it is picked and can be submitted', (t) async {
    final h = await pumpLocation(t, remembered: ['Plant 04', 'Building C', 'Paint Shop', 'Bin 05', 'A']);
    expect(find.text('Confirm location'), findsOneWidget);
    expect(find.text('AC Generator Nameplate'), findsOneWidget);
    expect(find.text('2 photos · ready to submit'), findsOneWidget);
    expect(find.text('LAST USED IN PPG PLANT 04 — COATINGS'), findsOneWidget);
    expect(find.text('Bin 05 · A'), findsOneWidget);
    expect(find.text('PPG Industries › Plant 04 › Building C › Paint Shop'), findsOneWidget);
    expect(find.text('Used for your last scan, 8 min ago'), findsOneWidget);
    expect(submitEnabled(t), isTrue);

    await t.tap(find.text('Submit scan'));
    await t.pumpAndSettle();
    expect(h.submitted.single, ['Plant 04', 'Building C', 'Paint Shop', 'Bin 05', 'A']);
  });

  testWidgets('GIVEN a first scan WHEN walking down the levels THEN each chooser follows the tree', (t) async {
    final h = await pumpLocation(t);
    expect(find.text('Choose location'), findsOneWidget);
    expect(find.textContaining("This is your first scan in this unit"), findsOneWidget);
    expect(submitEnabled(t), isFalse);
    expect(find.text('Choose down to the bin (and sub-bin if it has one) to submit'), findsOneWidget);
    expect(find.text('Plant 04'), findsOneWidget); // facility comes from the unit
    expect(find.text('Choose'), findsNWidgets(4));

    await t.tap(find.text('Choose').first); // Building
    await t.pumpAndSettle();
    expect(find.text('Choose building'), findsOneWidget);
    await t.tap(find.text('Building C'));
    await t.pumpAndSettle();

    expect(find.text('Choose shop'), findsOneWidget); // goes on down by itself
    await t.tap(find.text('Paint Shop'));
    await t.pumpAndSettle();

    expect(find.text('Choose bin'), findsOneWidget);
    expect(find.text('STEP 4 OF 5 · 2 BINS IN PAINT SHOP'), findsOneWidget);
    expect(find.text('2 sub-bins'), findsOneWidget);
    expect(find.text('No sub-bins'), findsOneWidget);
    await t.tap(find.text('Bin 05'));
    await t.pumpAndSettle();

    expect(find.text('Choose sub-bin'), findsOneWidget);
    await t.tap(find.text('A'));
    await t.pumpAndSettle();

    expect(find.text('Choose location'), findsOneWidget);
    expect(submitEnabled(t), isTrue);
    await t.tap(find.text('Submit scan'));
    await t.pumpAndSettle();
    expect(h.submitted.single, ['Plant 04', 'Building C', 'Paint Shop', 'Bin 05', 'A']);
  });

  testWidgets('GIVEN a bin with no shop WHEN picked THEN the shop stays blank and submit is allowed', (t) async {
    await pumpLocation(t);
    await t.tap(find.text('Choose').first);
    await t.pumpAndSettle();
    await t.tap(find.text('Building C'));
    await t.pumpAndSettle();
    await t.pageBack(); // skip the optional shop
    await t.pumpAndSettle();
    await t.tap(find.text('Choose').at(1)); // Bin row
    await t.pumpAndSettle();
    expect(find.text('Bin 09'), findsOneWidget);
    expect(find.text('Bin 05'), findsNothing); // inside the shop, not offered here
    await t.tap(find.text('Bin 09'));
    await t.pumpAndSettle();
    expect(find.text('Not used here'), findsOneWidget); // Bin 09 has no sub-bins
    expect(find.text('Choose'), findsOneWidget); // the shop can still be picked (it would clear the bin)
    expect(submitEnabled(t), isTrue);
  });

  testWidgets('GIVEN a last-used location WHEN changed THEN both show and the old one can be restored', (t) async {
    await pumpLocation(t, remembered: ['Plant 04', 'Building C', 'Paint Shop', 'Bin 05', 'A']);
    await t.tap(find.text('Bin 05'));
    await t.pumpAndSettle();
    await t.tap(find.text('Bin 07'));
    await t.pumpAndSettle();

    expect(find.text('SELECTED LOCATION'), findsOneWidget);
    expect(find.text('New'), findsOneWidget);
    expect(find.text('You changed this just now'), findsOneWidget);
    expect(find.text('Bin 07'), findsWidgets);

    await t.tap(find.text('Tap to go back to this location'));
    await t.pumpAndSettle();
    expect(find.text('LAST USED IN PPG PLANT 04 — COATINGS'), findsOneWidget);
    expect(find.text('Bin 05 · A'), findsOneWidget);
  });

  testWidgets('GIVEN many bins WHEN searching THEN only matches are listed', (t) async {
    await pumpLocation(t, remembered: ['Plant 04', 'Building C', 'Paint Shop', 'Bin 05']);
    await t.tap(find.text('Bin 05').last);
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '07');
    await t.pumpAndSettle();
    expect(find.text('Bin 07'), findsOneWidget);
    expect(find.text('Bin 05'), findsNothing);
  });

  testWidgets('GIVEN a remembered location that is gone WHEN opened THEN it starts fresh', (t) async {
    await pumpLocation(t, remembered: ['Plant 04', 'Building Z', 'Bin 99']);
    expect(find.text('Choose location'), findsOneWidget);
  });

  testWidgets('GIVEN no published locations WHEN opened THEN it says to ask the BU Admin', (t) async {
    await pumpLocation(t, api: (r) async => problem(404, 'not-found'));
    expect(find.text('This unit has no published locations yet. Ask your BU Admin.'), findsOneWidget);
  });
}
