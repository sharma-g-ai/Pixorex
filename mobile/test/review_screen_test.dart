import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pixorex_mobile/features/scan/review_screen.dart';
import 'package:pixorex_mobile/features/scan/scan_repository.dart';
import 'package:pixorex_mobile/features/scan/scan_thumb.dart' show NetworkPhoto;
import 'package:pixorex_mobile/widgets/auth_widgets.dart';

import 'auth_flow_test.dart' show json, problem;
import 'new_scan_screen_test.dart' show signedIn;

Map<String, dynamic> fieldJson(String key, String label, String? value,
        {List<String> flags = const [], double? confidence, bool required = false}) =>
    {
      'field_key': key,
      'label': label,
      'data_type': 'text',
      'is_required': required,
      'is_critical': false,
      'ai_value': value,
      'confidence': confidence,
      'flag_reasons': flags,
    };

/// Design 57, with no photos (signed links don't load in tests).
Map<String, dynamic> valve({String processing = 'ready_to_review', String review = 'draft'}) => {
      'scan_id': 's1',
      'record_no': 'REC-71',
      'bu_id': 'b1',
      'equipment_type_id': 't1',
      'equipment_type_name': 'Control Valve V-071',
      'contract_id': 'c1',
      'location_node_id': 'n1',
      'location_path': 'Plant 04 › Building C › Bin 05',
      'processing_status': processing,
      'review_status': review,
      'retake_of_scan_id': null,
      'photos': [],
      'attempts_used': 1,
      'latest_attempt': null,
      'fields': [
        fieldJson('model', 'Model number', 'CR 32-4-1 A-G-A-E-HQQE', flags: ['low_confidence'], confidence: 0.42),
        fieldJson('serial', 'Serial number', '98274-A3', flags: ['no_confidence']),
        fieldJson('barcode', 'Barcode', null, flags: ['missing_required'], required: true),
        fieldJson('manufacturer', 'Manufacturer', 'Grundfos', confidence: 0.97),
      ],
      'captured_at': '2026-11-03T09:30:00Z',
    };

class ReviewApi {
  Map<String, dynamic> scan = valve();
  final revisions = <Map<String, dynamic>>[];
  final keys = <String>[];
  http.Response? Function(http.BaseRequest r)? override;

  Future<http.Response> call(http.BaseRequest r) async {
    if (r.url.path.endsWith('/revisions')) {
      keys.add(r.headers['Idempotency-Key']!);
      revisions.add(jsonDecode((r as http.Request).body) as Map<String, dynamic>);
    }
    final o = override?.call(r);
    if (o != null) return o;
    if (r.url.path.endsWith('/revisions')) {
      return json({'revision_id': 'r1', 'revision_no': 1, 'origin': 'technician_review', 'empty_required_fields': [], 'review_status': 'waiting_for_approval'}, 201);
    }
    return json(scan);
  }
}

Future<(ReviewApi, List<bool?>)> pumpReview(WidgetTester t, {ReviewApi? api, bool settle = true}) async {
  t.view.physicalSize = const Size(1170, 2532);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  final a = api ?? ReviewApi();
  final rig = await signedIn(a.call);
  final popped = <bool?>[];
  await t.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => TextButton(
        child: const Text('open'),
        onPressed: () async => popped.add(await Navigator.of(context).push<bool>(MaterialPageRoute(
          builder: (_) => ReviewScreen(scans: ScanRepository(rig.api), scanId: 's1', pollEvery: const Duration(seconds: 1)),
        ))),
      ),
    ),
  ));
  await t.tap(find.text('open'));
  // A spinner never settles; step time instead while the label is being read.
  if (settle) {
    await t.pumpAndSettle();
  } else {
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
  }
  return (a, popped);
}

bool submitOn(WidgetTester t) =>
    t.widget<PillButton>(find.byWidgetPredicate((w) => w is PillButton && w.label.startsWith('Submit for review'))).onPressed != null;

/// Scrolls the review list (text fields have scrollables of their own).
Future<void> scrollTo(WidgetTester t, Finder f) async {
  await t.scrollUntilVisible(f, 200,
      scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first);
  await t.ensureVisible(f); // built is not the same as on screen: the footer covers the bottom
  await t.pumpAndSettle();
}

void main() {
  testWidgets('GIVEN a low-confidence value THEN it is shown (editable) with its score beside it', (t) async {
    await pumpReview(t);
    // 42% is below the threshold: the value is still there to review and correct.
    expect(find.widgetWithText(TextField, 'CR 32-4-1 A-G-A-E-HQQE'), findsOneWidget);
    expect(find.text('Low confidence · 42%'), findsOneWidget);
  });

  testWidgets('GIVEN a photo that cannot be loaded THEN the review says so, with a way to retry', (t) async {
    final api = ReviewApi()..scan = (valve()..['photos'] = [{'photo_no': 1, 'view_url': 'http://127.0.0.1:1/missing.jpg'}]);
    await pumpReview(t, api: api);
    await t.pump(const Duration(seconds: 1));
    expect(find.byType(NetworkPhoto), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('GIVEN a scan ready to review WHEN opened THEN flagged fields show why, submit waits', (t) async {
    await pumpReview(t);
    expect(find.text('Control Valve V-071'), findsOneWidget);
    expect(find.text('REC-71 · Bin 05 · Ready to Review'), findsOneWidget);
    expect(find.text('0 of 3 checked'), findsOneWidget);
    expect(find.text('Likely wrong'), findsWidgets); // legend + model number
    expect(find.text('Low confidence · 42%'), findsOneWidget);
    expect(find.text('No confidence score from the reader'), findsOneWidget);
    expect(find.text('Missing · required for this type'), findsOneWidget);
    expect(find.text('REQUIRED'), findsOneWidget);
    await scrollTo(t, find.text('Grundfos'));
    expect(find.text('Looks right'), findsWidgets);
    expect(find.text('Submit for review · 2 left to check'), findsOneWidget);
    expect(submitOn(t), isFalse);
  });

  testWidgets('GIVEN fixes and an unreadable WHEN submitted THEN the revision is sent and the screen closes',
      (t) async {
    final (api, popped) = await pumpReview(t);

    // Model number: fix the value.
    await t.enterText(find.byType(TextField).first, 'CR 32-4-1 A-F-A-E-HQQE');
    await t.tap(find.text('Save fix'));
    await t.pumpAndSettle();
    expect(find.text('Corrected'), findsOneWidget);
    expect(find.text('Was flagged: low confidence · 42%'), findsOneWidget);
    expect(find.text('CR 32-4-1 A-F-A-E-HQQE'), findsOneWidget);

    // Serial number: keep it.
    await t.tap(find.text('Keep as is'));
    await t.pumpAndSettle();
    expect(find.text('Kept as read'), findsOneWidget);
    expect(find.text('You confirmed the AI value matches the plate'), findsOneWidget);
    expect(submitOn(t), isTrue);
    expect(find.text('1 required field is still empty'), findsOneWidget);

    // Barcode: mark unreadable.
    await scrollTo(t, find.byKey(const Key('unreadable-barcode')));
    await t.tap(find.byKey(const Key('unreadable-barcode')));
    await t.pumpAndSettle();
    expect(find.text('Mark Barcode as unreadable?'), findsOneWidget);
    await t.tap(find.text('Label worn or damaged'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(PillButton, 'Mark unreadable'));
    await t.pumpAndSettle();
    expect(find.text('Marked unreadable'), findsOneWidget);
    expect(find.text('3 of 3 checked'), findsOneWidget);

    await t.tap(find.text('Submit for review'));
    await t.pumpAndSettle();
    expect(api.revisions.single, {
      'fields': [
        {'field_key': 'model', 'verification_state': 'corrected', 'value': 'CR 32-4-1 A-F-A-E-HQQE'},
        {'field_key': 'serial', 'verification_state': 'accepted'},
        {'field_key': 'barcode', 'verification_state': 'unreadable', 'unreadable_reason': 'label_worn'},
      ],
      'submit_anyway': false,
    });
    expect(popped, [true]);
  });

  testWidgets('GIVEN a required field left empty WHEN submitted THEN the modal, and Submit anyway sends left_empty',
      (t) async {
    final (api, popped) = await pumpReview(t);
    await t.tap(find.text('Keep as is').first);
    await t.pumpAndSettle();
    await t.tap(find.text('Keep as is').first);
    await t.pumpAndSettle();

    await t.tap(find.text('Submit for review'));
    await t.pumpAndSettle();
    expect(find.text('1 required field is empty'), findsOneWidget);
    await t.tap(find.text('Fill it in'));
    await t.pumpAndSettle();
    expect(api.revisions, isEmpty);

    await t.tap(find.text('Submit for review'));
    await t.pumpAndSettle();
    await t.tap(find.text('Submit anyway'));
    await t.pumpAndSettle();
    expect((api.revisions.single['fields'] as List).last, {'field_key': 'barcode', 'verification_state': 'left_empty'});
    expect(api.revisions.single['submit_anyway'], true);
    expect(popped, [true]);
  });

  testWidgets('GIVEN the required value is typed in WHEN saved THEN it counts as a correction', (t) async {
    await pumpReview(t);
    await t.enterText(find.widgetWithText(TextField, 'Add barcode'), '4006381333931');
    await t.pumpAndSettle();
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(find.text('Corrected'), findsOneWidget);
    expect(find.text('AI read'), findsNothing); // nothing was read, so nothing to strike through
  });

  testWidgets('GIVEN a correction WHEN Change is tapped THEN it is open again', (t) async {
    await pumpReview(t);
    await t.tap(find.text('Keep as is').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Change'));
    await t.pumpAndSettle();
    expect(find.text('Kept as read'), findsNothing);
    expect(find.text('0 of 3 checked'), findsOneWidget);
  });

  testWidgets('GIVEN "Other" WHEN marking unreadable THEN a note is needed', (t) async {
    await pumpReview(t);
    await scrollTo(t, find.byKey(const Key('unreadable-barcode')));
    await t.tap(find.byKey(const Key('unreadable-barcode')));
    await t.pumpAndSettle();
    await t.tap(find.text('Other — add a note'));
    await t.pumpAndSettle();
    final mark = find.widgetWithText(PillButton, 'Mark unreadable');
    expect(t.widget<PillButton>(mark).onPressed, isNull);
    await t.enterText(find.widgetWithText(TextField, 'What is wrong with it?'), 'Painted over');
    await t.pumpAndSettle();
    expect(t.widget<PillButton>(mark).onPressed, isNotNull);
  });

  testWidgets('GIVEN the answer is lost WHEN Submit is pressed again THEN the same key is reused', (t) async {
    final api = ReviewApi();
    var down = true;
    api.override = (r) => r.url.path.endsWith('/revisions') && down ? throw http.ClientException('down') : null;
    final (_, popped) = await pumpReview(t, api: api);
    await t.tap(find.text('Keep as is').first);
    await t.pumpAndSettle();
    await t.tap(find.text('Keep as is').first);
    await t.pumpAndSettle();
    await t.tap(find.text('Submit for review'));
    await t.pumpAndSettle();
    await t.tap(find.text('Submit anyway'));
    await t.pumpAndSettle();
    expect(find.text("Couldn't send. Check your connection and tap Submit for review again."), findsOneWidget);

    down = false;
    await t.tap(find.text('Submit for review'));
    await t.pumpAndSettle();
    await t.tap(find.text('Submit anyway'));
    await t.pumpAndSettle();
    expect(api.keys, hasLength(2));
    expect(api.keys.toSet(), hasLength(1));
    expect(popped, [true]);
  });

  testWidgets('GIVEN the API says flags are not reviewed WHEN submitting THEN its message shows', (t) async {
    final api = ReviewApi()..override = (r) => r.url.path.endsWith('/revisions') ? problem(409, 'flags-not-reviewed') : null;
    await pumpReview(t, api: api);
    await t.tap(find.text('Keep as is').first);
    await t.pumpAndSettle();
    await t.tap(find.text('Keep as is').first);
    await t.pumpAndSettle();
    await t.tap(find.text('Submit for review'));
    await t.pumpAndSettle();
    await t.tap(find.text('Submit anyway'));
    await t.pumpAndSettle();
    expect(find.text('detail for flags-not-reviewed'), findsOneWidget);
  });

  testWidgets('GIVEN the label is still being read WHEN opened THEN it waits, then shows the fields', (t) async {
    final api = ReviewApi()..scan = valve(processing: 'extracting');
    await pumpReview(t, api: api, settle: false);
    expect(find.text('Reading the label…'), findsOneWidget);
    expect(find.text('REC-71 · Bin 05 · Extracting'), findsOneWidget);

    api.scan = valve();
    await t.pump(const Duration(seconds: 1));
    await t.pumpAndSettle();
    expect(find.text('Low confidence · 42%'), findsOneWidget);
  });

  testWidgets('GIVEN a submitted scan WHEN opened THEN it says it is with the reviewer', (t) async {
    final api = ReviewApi()..scan = valve(review: 'waiting_for_approval');
    await pumpReview(t, api: api);
    expect(find.text('With the reviewer'), findsOneWidget);
    expect(find.textContaining('Submit for review'), findsNothing);
  });
}
