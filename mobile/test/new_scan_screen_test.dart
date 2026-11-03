import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pixorex_mobile/features/scan/capture_models.dart';
import 'package:pixorex_mobile/features/scan/new_scan_screen.dart';
import 'package:pixorex_mobile/features/scan/scan_repository.dart';

import 'photo_set_screen_test.dart' show FakePhotoSource;
import 'auth_flow_test.dart' show Rig, json, meJson, problem, pumpApp;

Map<String, dynamic> typesPage(List<String> names, {String? next}) => {
      'items': [
        for (final n in names)
          {
            'type_id': 't-$n',
            'name': n,
            'fields': [
              {'field_key': 'serial', 'label': 'Serial', 'data_type': 'text', 'is_required': true, 'is_critical': true},
            ],
          },
      ],
      'page': {'next_cursor': next},
    };

/// A signed-in [Rig]: `/me` answers for sign-in, everything else goes to [api].
Future<Rig> signedIn(Future<http.Response> Function(http.BaseRequest) api) async {
  final rig = Rig((r) async => r.url.path.endsWith('/me') ? json(meJson()) : api(r));
  await rig.session.signIn(loginHint: 'j@x.co');
  return rig;
}

Future<List<String>> pumpNewScan(
  WidgetTester t,
  Future<http.Response> Function(http.BaseRequest) api, {
  EquipmentType? initialType,
}) async {
  final shutters = <String>[];
  final rig = await signedIn(api);
  await t.pumpWidget(MaterialApp(
    home: NewScanScreen(
      scans: ScanRepository(rig.api),
      buId: 'b1',
      unitName: 'PPG Plant 04 — Coatings',
      initialType: initialType,
      onShutter: (type) => shutters.add(type.name),
      onGallery: (type) => shutters.add('gallery:${type.name}'),
    ),
  ));
  await t.pumpAndSettle();
  return shutters;
}

void main() {
  group('repository', () {
    test('GIVEN two pages of types WHEN equipmentTypes THEN both pages are read, published only', () async {
      final seen = <Uri>[];
      final rig = await signedIn((r) async {
        seen.add(r.url);
        final first = r.url.queryParameters['cursor'] == null;
        return json(typesPage([first ? 'Motor' : 'Pump'], next: first ? 'c2' : null));
      });
      final types = await ScanRepository(rig.api).equipmentTypes('b1');
      expect(types.map((t) => t.name), ['Motor', 'Pump']);
      expect(types.first.fields.single.isRequired, isTrue);
      expect(seen.first.path, '/api/v1/business-units/b1/equipment-types');
      expect(seen.first.queryParameters, containsPair('status', 'published'));
      expect(seen.first.queryParameters, containsPair('include', 'fields'));
      expect(seen.last.queryParameters['cursor'], 'c2');
    });

    test('GIVEN a published tree WHEN read THEN levels are ordered, off levels dropped, nodes nested', () async {
      final rig = await signedIn((r) async => json({
            'levels': [
              {'level_id': 'l3', 'level_name': 'Bin', 'level_order': 3, 'requirement': 'required'},
              {'level_id': 'l1', 'level_name': 'Facility', 'level_order': 1, 'requirement': 'required'},
              {'level_id': 'l2', 'level_name': 'Shop', 'level_order': 2, 'requirement': 'optional'},
              {'level_id': 'l4', 'level_name': 'Rack', 'level_order': 4, 'requirement': 'off'},
            ],
            'tree_snapshot': {
              'nodes': [
                {
                  'node_id': 'f',
                  'level_id': 'l1',
                  'name': 'Plant 04',
                  'children': [
                    {'node_id': 'b', 'level_id': 'l3', 'name': 'Bin 05', 'children': []},
                  ],
                },
              ],
            },
            'published_at': '2026-11-01T10:00:00Z',
          }));
      final tree = await ScanRepository(rig.api).publishedLocations('b1');
      expect(tree.levels.map((l) => l.name), ['Facility', 'Shop', 'Bin']);
      expect(tree.levels[1].isOptional, isTrue);
      expect(tree.roots.single.children.single.name, 'Bin 05');
    });
  });

  group('New scan', () {
    testWidgets('GIVEN no type yet WHEN the screen opens THEN capture is blocked', (t) async {
      final taken = await pumpNewScan(t, (r) async => json(typesPage(['Motor Nameplate'])));
      expect(find.text('Scanning for '), findsNothing); // rich text, checked below
      expect(find.textContaining('PPG Plant 04 — Coatings', findRichText: true), findsOneWidget);
      expect(find.text('Select equipment type'), findsOneWidget);
      expect(find.text('Choose the equipment type to start'), findsOneWidget);
      expect(find.text('Pick a type first'), findsOneWidget);
      await t.tap(find.byKey(const Key('shutter')));
      await t.tap(find.text('Gallery'));
      expect(taken, isEmpty);
    });

    testWidgets('GIVEN the unit types WHEN one is picked from the sheet THEN capture uses it', (t) async {
      final taken = await pumpNewScan(t, (r) async => json(typesPage(['Paint / Chemical Label', 'Motor Nameplate'])));
      await t.tap(find.text('Select equipment type'));
      await t.pumpAndSettle();
      expect(find.text('Types set up for your business unit'), findsOneWidget);
      expect(find.text("Don't see the type you need? Ask your BU Admin to add it for this unit."), findsOneWidget);

      await t.tap(find.text('Motor Nameplate'));
      await t.pumpAndSettle();
      expect(find.text('Align the nameplate within the frame'), findsOneWidget);
      expect(find.text('Take photo'), findsOneWidget);

      await t.tap(find.byKey(const Key('shutter')));
      await t.tap(find.text('Gallery'));
      expect(taken, ['Motor Nameplate', 'gallery:Motor Nameplate']);
    });

    testWidgets('GIVEN the type from the last scan WHEN the screen opens THEN it is kept', (t) async {
      final taken = await pumpNewScan(t, (r) async => json(typesPage(['Motor Nameplate'])),
          initialType: const EquipmentType(typeId: 't-Motor Nameplate', name: 'Motor Nameplate'));
      expect(find.text('Motor Nameplate'), findsOneWidget);
      await t.tap(find.byKey(const Key('shutter')));
      expect(taken, ['Motor Nameplate']);
    });

    testWidgets('GIVEN no published types WHEN the screen opens THEN it says to ask the BU Admin', (t) async {
      await pumpNewScan(t, (r) async => json(typesPage([])));
      expect(find.text('No equipment types are set up for this unit yet. Ask your BU Admin to add one.'), findsOneWidget);
    });

    testWidgets('GIVEN a signed-in technician WHEN New scan is tapped on Home THEN it opens for their unit', (t) async {
      final rig = Rig((r) async {
        final p = r.url.path;
        if (p.endsWith('/me/scans')) return json({'items': [], 'page': {'next_cursor': null}});
        if (p.endsWith('/equipment-types')) return json(typesPage(['Motor Nameplate']));
        return json(meJson());
      });
      await rig.session.signIn(loginHint: 'j@x.co');
      await pumpApp(t, rig, photoSource: FakePhotoSource.new);
      await t.tap(find.byTooltip('New scan'));
      await t.pumpAndSettle();
      expect(find.text('New scan'), findsOneWidget);
      expect(find.textContaining('PPG Plant 04 — Coatings', findRichText: true), findsOneWidget);
      expect(rig.calls, contains('GET /api/v1/business-units/b1/equipment-types'));
    });

    testWidgets('GIVEN the types fail to load WHEN Retry is tapped THEN they load', (t) async {
      var fail = true;
      await pumpNewScan(t, (r) async => fail ? problem(503, 'service-unavailable') : json(typesPage(['Motor Nameplate'])));
      expect(find.text('detail for service-unavailable'), findsOneWidget);
      fail = false;
      await t.tap(find.text('Retry'));
      await t.pumpAndSettle();
      expect(find.text('Select equipment type'), findsOneWidget);
    });
  });
}
