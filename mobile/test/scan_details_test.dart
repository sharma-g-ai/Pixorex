import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pixorex_mobile/features/scan/my_scans_screen.dart';
import 'package:pixorex_mobile/features/scan/scan_models.dart';
import 'package:pixorex_mobile/features/scan/scan_repository.dart';

import 'auth_flow_test.dart' show json, meJson;
import 'home_screen_test.dart' show now, row;
import 'new_scan_screen_test.dart' show signedIn;
import 'rejection_screens_test.dart' show rejected;

Map<String, dynamic> historyJson() => {
      'scan_id': 's-sub',
      'record_no': '1000000040',
      'now': {'text': 'With Bo Plant04 for review.', 'since': '2026-11-04T10:31:00Z', 'needs_technician': false},
      'events': [
        {'kind': 'captured', 'at': '2026-11-03T06:10:00Z', 'title': 'Scanned by you', 'detail': 'Motor Nameplate · Bin 05'},
        {'kind': 'rejected', 'at': '2026-11-04T09:45:00Z', 'title': 'Rejected by Bo Plant04', 'detail': 'Other · “Wrong plate”'},
        {'kind': 'resubmitted', 'at': '2026-11-04T10:31:00Z', 'title': 'Fixed and sent back by you', 'detail': 'Manufacturer: ACME MOTORS INC. → ACME MOTORS'},
      ],
    };

Future<List<String>> pump(WidgetTester t, List<Map<String, dynamic>> rows) async {
  t.view.physicalSize = const Size(1170, 3000);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  final calls = <String>[];
  final rig = await signedIn((http.BaseRequest r) async {
    final p = r.url.path;
    calls.add(p.replaceFirst('/api/v1', ''));
    if (p.endsWith('/me')) return json(meJson());
    if (p.endsWith('/me/scans')) return json({'items': rows, 'page': {'next_cursor': null}});
    if (p.endsWith('/history')) return json(historyJson());
    return json(rejected()..['review_status'] = 'waiting_for_approval'..['rejection'] = null);
  });
  await t.pumpWidget(MaterialApp(
    home: MyScansScreen(scans: ScanRepository(rig.api), unitName: 'PPG Plant 04', clock: () => now),
  ));
  await t.pumpAndSettle();
  return calls;
}

void main() {
  test('formatScanId groups 10 digits as 3 3 3 1 and leaves other numbers alone', () {
    expect(formatScanId('1000000040'), '100 000 004 0');
    expect(formatScanId('REC-12'), 'REC-12');
  });

  test('which rows open Scan details', () {
    MyScan scan(String processing, String review) => MyScan.fromJson(row('X', processing, review));
    expect(scan('ready_to_review', 'waiting_for_approval').opensDetails, isTrue);
    expect(scan('ready_to_review', 'approved').opensDetails, isTrue);
    expect(scan('failed', 'draft').opensDetails, isTrue);
    expect(scan('ready_to_review', 'draft').opensDetails, isFalse); // Review: the technician fills it in
    expect(scan('extracting', 'draft').opensDetails, isFalse); // Review waits for the read
    expect(scan('ready_to_review', 'rejected').opensDetails, isFalse); // the rejection notice
  });

  testWidgets('GIVEN a submitted scan WHEN its row is tapped THEN Scan details shows where it is and the history', (t) async {
    final calls = await pump(t, [row('Motor Nameplate', 'ready_to_review', 'waiting_for_approval')..['record_no'] = '1000000040'..['scan_id'] = 's-sub']);
    expect(find.text('100 000 004 0 · Bin 07'), findsOneWidget);
    expect(find.textContaining('min ago'), findsNothing);

    await t.tap(find.text('Motor Nameplate'));
    await t.pumpAndSettle();
    expect(calls, contains('/scans/s-sub/history'));
    expect(find.text('Nothing for you to do'), findsOneWidget);
    expect(find.textContaining('Now: With Bo Plant04 for review.'), findsOneWidget);
    expect(find.textContaining('since 4 Nov'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Scanned by you'), findsOneWidget);
    expect(find.text('Rejected by Bo Plant04'), findsOneWidget);
    expect(find.text('Other · “Wrong plate”'), findsOneWidget);
    expect(find.text('Fixed and sent back by you'), findsOneWidget);
    expect(find.text('Manufacturer: ACME MOTORS INC. → ACME MOTORS'), findsOneWidget);
    // Oldest first.
    expect(t.getTopLeft(find.text('Scanned by you')).dy, lessThan(t.getTopLeft(find.text('Fixed and sent back by you')).dy));
  });
}
