import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pixorex_mobile/features/scan/capture_models.dart';
import 'package:pixorex_mobile/features/scan/photo_prep.dart';
import 'package:pixorex_mobile/features/scan/photo_set_screen.dart';
import 'package:pixorex_mobile/features/scan/photo_source.dart';

Uint8List jpeg(int shade) => img.encodeJpg(img.Image(width: 8, height: 8)..clear(img.ColorRgb8(shade, shade, shade)));

/// Hands out photos from a list; null means the technician backed out.
class FakePhotoSource implements PhotoSource {
  FakePhotoSource([List<Uint8List?>? shots]) : shots = shots ?? [];
  final List<Uint8List?> shots;
  Object? fail;
  var disposed = false;

  Future<Uint8List?> _next() async {
    if (fail != null) throw fail!;
    return shots.isEmpty ? null : shots.removeAt(0);
  }

  @override
  Widget viewfinder({required String hint}) => Center(child: Text(hint));
  @override
  Future<Uint8List?> shutter() => _next();
  @override
  Future<Uint8List?> gallery() => _next();
  @override
  Future<Uint8List?> systemCamera() => _next();
  @override
  Future<void> dispose() async => disposed = true;
}

CaptureDraft draftWith(int photos) {
  final d = CaptureDraft(
    type: const EquipmentType(typeId: 't1', name: 'AC Generator Nameplate'),
    clientCaptureId: 'cap-1',
    capturedAt: DateTime.utc(2026, 11, 3),
    first: jpeg(10),
  );
  for (var i = 1; i < photos; i++) {
    d.photos.add(jpeg(10 + i));
  }
  return d;
}

class Pushed {
  CaptureDraft? next;
  var poppedBack = false;
}

Future<Pushed> pumpSet(WidgetTester t, CaptureDraft draft, FakePhotoSource source,
    {PreparePhoto? prepare}) async {
  t.view.physicalSize = const Size(1170, 2532);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  final result = Pushed();
  await t.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            child: const Text('open'),
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => PhotoSetScreen(
                  draft: draft,
                  source: source,
                  prepare: prepare ?? (raw) async => raw,
                  onNext: (d) => result.next = d,
                ),
              ));
              result.poppedBack = true;
            },
          ),
        ),
      ),
    ),
  ));
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('GIVEN one photo WHEN the set opens THEN it offers photo 2 and Next', (t) async {
    final r = await pumpSet(t, draftWith(1), FakePhotoSource());
    expect(find.text('Photo 1 of 1'), findsOneWidget);
    expect(find.text('1 photo in this scan · tap × to remove one'), findsOneWidget);
    expect(find.text('2 of 4 · another angle or label'), findsOneWidget);
    await t.tap(find.text('Next · 1 photo'));
    expect(r.next?.photos, hasLength(1));
  });

  testWidgets('GIVEN Add photo WHEN a photo is taken THEN the scan holds 2', (t) async {
    final shot = jpeg(200);
    final r = await pumpSet(t, draftWith(1), FakePhotoSource([shot]));
    await t.tap(find.text('Add photo'));
    await t.pumpAndSettle();
    expect(find.text('Photo 2 of 4'), findsOneWidget);
    expect(find.text('Align the next part of the label'), findsOneWidget);
    expect(find.text('1 photo taken'), findsOneWidget);
    expect(find.text('Take photo 2'), findsOneWidget);

    await t.tap(find.byKey(const Key('shutter')));
    await t.pumpAndSettle();
    expect(find.text('Photo 2 of 2'), findsOneWidget);
    expect(find.text('Next · 2 photos'), findsOneWidget);
    await t.tap(find.text('Next · 2 photos'));
    expect(r.next!.photos.last, same(shot));
  });

  testWidgets('GIVEN Add photo WHEN Cancel is tapped THEN nothing is added', (t) async {
    await pumpSet(t, draftWith(1), FakePhotoSource([jpeg(1)]));
    await t.tap(find.text('Add photo'));
    await t.pumpAndSettle();
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(find.text('1 photo in this scan · tap × to remove one'), findsOneWidget);
  });

  testWidgets('GIVEN 4 photos WHEN shown THEN the limit is explained and Add photo is gone', (t) async {
    await pumpSet(t, draftWith(4), FakePhotoSource());
    expect(find.text("That's the most a scan can hold. Remove a photo to swap in a better one."), findsOneWidget);
    expect(find.text('4 photos in this scan · limit reached · tap × to remove one'), findsOneWidget);
    expect(find.text('Add photo'), findsNothing);

    await t.tap(find.byKey(const Key('remove-2')));
    await t.pumpAndSettle();
    expect(find.text('3 photos in this scan · tap × to remove one'), findsOneWidget);
    expect(find.text('Add photo'), findsOneWidget);
  });

  testWidgets('GIVEN a photo that cannot be read WHEN added THEN a message, the set is unchanged', (t) async {
    await pumpSet(t, draftWith(1), FakePhotoSource([Uint8List.fromList([1, 2, 3])]),
        prepare: (raw) async => throw const PhotoPrepException("This photo can't be read. Take it again or pick another one."));
    await t.tap(find.text('Add photo'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('shutter')));
    await t.pumpAndSettle();
    expect(find.text("This photo can't be read. Take it again or pick another one."), findsOneWidget);
    expect(find.text('1 photo in this scan · tap × to remove one'), findsOneWidget);
  });

  testWidgets('GIVEN Discard scan WHEN confirmed THEN back to the camera; WHEN kept THEN stays', (t) async {
    final r = await pumpSet(t, draftWith(2), FakePhotoSource());
    await t.tap(find.text('Discard scan').last);
    await t.pumpAndSettle();
    expect(find.text('Discard this scan?'), findsOneWidget);
    await t.tap(find.text('Keep editing'));
    await t.pumpAndSettle();
    expect(r.poppedBack, isFalse);

    await t.tap(find.text('Discard scan').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Discard'));
    await t.pumpAndSettle();
    expect(r.poppedBack, isTrue);
    expect(r.next, isNull);
  });

  testWidgets('GIVEN the only photo WHEN removed THEN it asks to discard the scan', (t) async {
    await pumpSet(t, draftWith(1), FakePhotoSource());
    await t.tap(find.byKey(const Key('remove-1')));
    await t.pumpAndSettle();
    expect(find.text('Discard this scan?'), findsOneWidget);
  });

  testWidgets('GIVEN the camera fails WHEN the shutter is tapped THEN a message, no photo', (t) async {
    final source = FakePhotoSource()..fail = const PhotoSourceException("The photo wasn't taken. Hold steady and try again.");
    await pumpSet(t, draftWith(1), source);
    await t.tap(find.text('Add photo'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('shutter')));
    await t.pumpAndSettle();
    expect(find.text("The photo wasn't taken. Hold steady and try again."), findsOneWidget);
    expect(find.text('Photo 2 of 4'), findsOneWidget); // still on Add photo
  });
}
