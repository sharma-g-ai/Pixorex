import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pixorex_mobile/features/auth/session_controller.dart';
import 'package:pixorex_mobile/features/home/home_screen.dart';
import 'package:pixorex_mobile/features/scan/scan_models.dart' show shortPlace;
import 'package:pixorex_mobile/features/scan/scan_repository.dart';
import 'package:pixorex_mobile/features/scan/scan_status.dart';
import 'package:provider/provider.dart';

import 'auth_flow_test.dart' show Rig, json, meJson, problem;

final now = DateTime(2026, 10, 1, 12); // a Thursday

Map<String, dynamic> row(String type, String processing, String review, {int minAgo = 5, String place = 'Bin 07'}) => {
      'scan_id': 's-$type',
      'record_no': 'REC-1',
      'equipment_type_name': type,
      'location_path': 'Plant 04 › Building A › $place',
      'processing_status': processing,
      'review_status': review,
      'attempts_used': 1,
      'reject_category': null,
      'updated_at': now.subtract(Duration(minutes: minAgo)).toUtc().toIso8601String(),
    };

Map<String, dynamic> page(List<Map<String, dynamic>> items) => {'items': items, 'page': {'next_cursor': null}};

/// Answers /me, sign-out and the three Home lists by their query.
Future<http.Response> Function(http.BaseRequest) homeApi({
  List<Map<String, dynamic>> needs = const [],
  List<Map<String, dynamic>> today = const [],
  List<Map<String, dynamic>> latest = const [],
}) =>
    (r) async {
      final q = r.url.queryParameters;
      if (!r.url.path.endsWith('/me/scans')) return json(r.url.path.endsWith('/me') ? meJson() : {});
      if (q['tab'] == 'needs_action') return json(page(needs));
      if (q.containsKey('from')) return json(page(today));
      return json(page(latest));
    };

Future<Rig> pumpHome(WidgetTester t, Future<http.Response> Function(http.BaseRequest) api,
    {VoidCallback? onNewScan}) async {
  final rig = Rig(api);
  await rig.session.signIn(loginHint: 'j.martinez@ppg-plant04.com');
  await t.pumpWidget(ChangeNotifierProvider<SessionController>.value(
    value: rig.session,
    child: MaterialApp(
      home: Scaffold(body: HomeTab(scans: ScanRepository(rig.api), onNewScan: onNewScan, clock: () => now)),
    ),
  ));
  await t.pumpAndSettle();
  return rig;
}

void main() {
  group('helpers', () {
    test('ago reads like the design', () {
      expect(ago(now.subtract(const Duration(seconds: 20)), now), 'just now');
      expect(ago(now.subtract(const Duration(minutes: 4)), now), '4 min ago');
      expect(ago(now.subtract(const Duration(minutes: 70)), now), '1 hr ago');
      expect(ago(now.subtract(const Duration(days: 3)), now), '3 days ago');
    });
    test('shortPlace keeps the bin when the scan sits in a sub-bin', () {
      expect(shortPlace('Plant 04 › Building C › Bin 05'), 'Bin 05');
      expect(shortPlace('Plant 04 › Building C › Bin 05 › A'), 'Bin 05 · A');
      expect(shortPlace('Plant 04'), 'Plant 04');
    });
    test('dayLabel and initials', () {
      expect(dayLabel(now), 'Thu 1 Oct');
      expect(initials('Jorge  Martinez'), 'JM');
    });
    test('status pills follow review status first, then processing', () {
      expect(ScanStatusLook.of('ready_to_review', 'draft').label, 'Ready to Review');
      expect(ScanStatusLook.of('ready_to_review', 'draft').needsAction, isTrue);
      expect(ScanStatusLook.of('failed', 'draft').label, 'Extraction failed');
      expect(ScanStatusLook.of('retake_required', 'draft').label, 'Retake needed');
      expect(ScanStatusLook.of('extracting', 'draft').label, 'Extracting');
      expect(ScanStatusLook.of('ready_to_review', 'waiting_for_approval').label, 'Submitted');
      expect(ScanStatusLook.of('ready_to_review', 'rejected').label, 'Rejected');
      expect(ScanStatusLook.of('ready_to_review', 'approved').needsAction, isFalse);
    });
  });

  group('Home', () {
    testWidgets('GIVEN no scans WHEN Home opens THEN the first-time guide shows', (t) async {
      var started = 0;
      await pumpHome(t, homeApi(), onNewScan: () => started++);
      expect(find.text('Welcome, Jorge'), findsOneWidget);
      expect(find.text('Pick the equipment type'), findsOneWidget);
      expect(find.text('Check it in My Scans'), findsOneWidget);
      await t.tap(find.text('Start your first scan'));
      expect(started, 1);
    });

    testWidgets('GIVEN New scan is not wired WHEN Home opens THEN no start button', (t) async {
      await pumpHome(t, homeApi());
      expect(find.text('Start your first scan'), findsNothing);
    });

    testWidgets('GIVEN scans WHEN Home opens THEN action card, today and latest match design 14', (t) async {
      final rig = await pumpHome(
        t,
        homeApi(
          needs: [
            row('A', 'ready_to_review', 'draft'),
            row('B', 'ready_to_review', 'draft'),
            row('C', 'ready_to_review', 'rejected'),
            row('D', 'failed', 'draft'),
          ],
          today: [
            row('A', 'extracting', 'draft'),
            row('B', 'ready_to_review', 'waiting_for_approval'),
            row('C', 'ready_to_review', 'approved'),
          ],
          latest: [
            row('AC Generator Nameplate', 'extracting', 'draft', minAgo: 4),
            row('HVAC Chiller Nameplate', 'ready_to_review', 'approved', minAgo: 60, place: 'Bin 09'),
          ],
        ),
      );
      expect(find.text('4 scans need your action'), findsOneWidget);
      expect(find.text('2 to review · 1 rejected · 1 failed'), findsOneWidget);
      expect(find.text('Thu 1 Oct'), findsOneWidget);
      expect(find.text('3'), findsOneWidget); // scanned today
      expect(find.text('2'), findsOneWidget); // submitted (waiting + approved)
      expect(find.text('1'), findsOneWidget); // approved
      expect(find.text('AC Generator Nameplate'), findsOneWidget);
      expect(find.text('REC-1 · Bin 07'), findsOneWidget);
      expect(find.text('REC-1 · Bin 09'), findsOneWidget);
      expect(find.text('Extracting'), findsOneWidget);
      expect(find.text('Approved'), findsWidgets);

      final asked = rig.calls.where((c) => c.endsWith('/me/scans'));
      expect(asked, hasLength(3));
    });

    testWidgets('GIVEN today is 1 Oct WHEN Home loads THEN it asks for scans from that date', (t) async {
      final queries = <Map<String, String>>[];
      await pumpHome(t, (r) async {
        if (r.url.path.endsWith('/me/scans')) queries.add(r.url.queryParameters);
        return homeApi()(r);
      });
      expect(queries, contains(containsPair('from', '2026-10-01')));
      expect(queries, contains(containsPair('tab', 'needs_action')));
      expect(queries, contains(containsPair('limit', '4')));
    });

    testWidgets('GIVEN the API fails WHEN Home loads THEN an error shows and Try again reloads', (t) async {
      var fail = true;
      await pumpHome(t, (r) async {
        if (r.url.path.endsWith('/me/scans') && fail) return problem(503, 'service-unavailable');
        return homeApi()(r);
      });
      expect(find.text('detail for service-unavailable'), findsOneWidget);
      fail = false;
      await t.tap(find.text('Try again'));
      await t.pumpAndSettle();
      expect(find.text('Welcome, Jorge'), findsOneWidget);
    });
  });

  testWidgets('GIVEN a reply off-contract WHEN Home loads THEN a message, not a crash', (t) async {
    await pumpHome(t, (r) async => json(r.url.path.endsWith('/me/scans') ? {'unexpected': true} : meJson()));
    expect(find.text("Couldn't load your scans. Please try again."), findsOneWidget);
  });

  group('HomeShell', () {
    testWidgets('GIVEN signed in WHEN Profile is opened THEN Sign out signs out', (t) async {
      final rig = Rig(homeApi());
      await rig.session.signIn(loginHint: 'j.martinez@ppg-plant04.com');
      await t.pumpWidget(ChangeNotifierProvider<SessionController>.value(
        value: rig.session,
        child: MaterialApp(home: HomeShell(scans: ScanRepository(rig.api), onNewScan: () async {})),
      ));
      await t.pumpAndSettle();
      expect(find.text('Field Technician · PPG Plant 04 — Coatings'), findsOneWidget);
      expect(find.byTooltip('New scan'), findsOneWidget);

      await t.tap(find.text('Profile'));
      await t.pumpAndSettle();
      expect(find.text('j.martinez@ppg-plant04.com'), findsOneWidget);
      await t.tap(find.text('Sign out'));
      await t.pumpAndSettle();
      expect(rig.calls, contains('POST /api/v1/me/sign-out'));
      expect(rig.session.status, SessionStatus.signedOut);
    });
  });
}
