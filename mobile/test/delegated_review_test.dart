import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pixorex_mobile/features/auth/session_controller.dart';
import 'package:pixorex_mobile/features/home/home_screen.dart';
import 'package:pixorex_mobile/features/review/batch_screen.dart';
import 'package:pixorex_mobile/features/review/delegated_models.dart';
import 'package:pixorex_mobile/features/review/delegated_review_screen.dart';
import 'package:pixorex_mobile/features/scan/scan_repository.dart';
import 'package:provider/provider.dart';

import 'auth_flow_test.dart' show json, problem;
import 'new_scan_screen_test.dart' show signedIn;

Map<String, dynamic> batchJson({int scans = 2, int decided = 0}) => {
      'batch_id': 'b2',
      'batch_no': 'B-2',
      'assigned_to_name': 'Dana Dual',
      'created_by_name': 'Bo Plant04',
      'scan_count': scans,
      'decided_count': decided,
      'created_at': '2026-11-13T09:00:00Z',
      'reminded_at': null,
      'status': 'active',
    };

Map<String, dynamic> assignment(String id, String status, [String? reason]) =>
    {'scan_id': id, 'record_no': '100000${id}0', 'status': status, 'removed_reason': reason};

Map<String, dynamic> reviewJson({List<String> emptyRequired = const []}) => {
      'scan_id': 's1',
      'record_no': '1000000180',
      'equipment_type_name': 'Motor Nameplate',
      'location_path': 'Plant 04 › Building C › Bin 07',
      'captured_by_name': 'Tara Tech',
      'photos': [],
      'current_revision': {
        'revision_id': 'r1',
        'revision_no': 1,
        'origin': 'technician_review',
        'empty_required_fields': emptyRequired,
        'review_status': 'waiting_for_approval',
      },
      'fields': [
        {
          'field_key': 'model',
          'label': 'Model number',
          'ai_value': 'ECP8442T',
          'confidence': 0.62,
          'flag_reasons': ['low_confidence'],
          'technician_value': 'ECP8442',
          'verification_state': 'corrected',
          'unreadable_reason': null,
          'note': null,
        },
        {
          'field_key': 'serial',
          'label': 'Serial number',
          'ai_value': null,
          'confidence': null,
          'flag_reasons': ['missing_required'],
          'technician_value': null,
          'verification_state': 'unreadable',
          'unreadable_reason': 'label_worn',
          'note': null,
        },
        {
          'field_key': 'voltage',
          'label': 'Rated voltage',
          'ai_value': '230',
          'confidence': 0.98,
          'flag_reasons': [],
          'technician_value': '230',
          'verification_state': 'accepted',
          'unreadable_reason': null,
          'note': null,
        },
      ],
      'decisions': [],
    };

/// The delegated-review endpoints, with what was posted.
class ReviewerApi {
  List<Map<String, dynamic>> batches = [batchJson()];
  List<Map<String, dynamic>> assignments = [
    assignment('1', 'assigned'),
    assignment('2', 'decided'),
    assignment('3', 'removed', 'taken_back'),
  ];
  Map<String, dynamic> review = reviewJson();
  http.Response? decideReply;
  http.Response? reviewReply;
  final decisions = <Map<String, dynamic>>[];
  final keys = <String?>[];
  int batchLoads = 0;

  Future<http.Response> call(http.BaseRequest r) async {
    final p = r.url.path;
    if (p.endsWith('/me/review-batches')) return json({'items': batches, 'page': {'next_cursor': null}});
    if (p.endsWith('/review-batches/b2')) {
      batchLoads++;
      return json({'batch': batches.first, 'assignments': assignments});
    }
    if (p.endsWith('/review')) return reviewReply ?? json(review);
    if (p.endsWith('/decisions')) {
      keys.add(r.headers['Idempotency-Key']);
      decisions.add(jsonDecode((r as http.Request).body) as Map<String, dynamic>);
      return decideReply ?? json({'decision_id': 'd1', 'review_status': 'approved'}, 201);
    }
    return json({});
  }
}

Future<ReviewerApi> pumpBatch(WidgetTester t, {ReviewerApi? api}) async {
  t.view.physicalSize = const Size(1170, 2532);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  final a = api ?? ReviewerApi();
  final rig = await signedIn(a.call);
  await t.pumpWidget(MaterialApp(home: BatchScreen(scans: ScanRepository(rig.api), batchId: 'b2', batchNo: 'B-2')));
  await t.pumpAndSettle();
  return a;
}

void main() {
  group('Home: Scans to review (3.15)', () {
    Future<ReviewerApi> pumpHomeWith(WidgetTester t, ReviewerApi api) async {
      // My own scans: none (Home then shows its first-time view, the card must still be there).
      Future<http.Response> handler(http.BaseRequest r) =>
          r.url.path.endsWith('/me/scans') ? Future.value(json({'items': [], 'page': {'next_cursor': null}})) : api.call(r);
      final rig = await signedIn(handler);
      await t.pumpWidget(ChangeNotifierProvider<SessionController>.value(
        value: rig.session,
        child: MaterialApp(home: Scaffold(body: HomeTab(scans: ScanRepository(rig.api)))),
      ));
      await t.pumpAndSettle();
      return api;
    }

    testWidgets('GIVEN a batch for me THEN Home shows it with progress and who gave it; tap opens it', (t) async {
      await pumpHomeWith(t, ReviewerApi()..batches = [batchJson(scans: 2, decided: 1)]);
      expect(find.text('Scans to review'), findsOneWidget);
      expect(find.text('B-2 · from Bo Plant04'), findsOneWidget);
      expect(find.text('1 of 2 reviewed'), findsOneWidget);
      await t.tap(find.text('B-2 · from Bo Plant04'));
      await t.pumpAndSettle();
      expect(find.byType(BatchScreen), findsOneWidget);
    });

    testWidgets('GIVEN no batches THEN no card', (t) async {
      await pumpHomeWith(t, ReviewerApi()..batches = []);
      expect(find.text('Scans to review'), findsNothing);
    });
  });

  group('models (contracts 3.11, 3.15, 3.4)', () {
    test('GIVEN a batch THEN progress reads decided of total', () {
      final b = ReviewBatch.fromJson(batchJson(scans: 2, decided: 1));
      expect(b.progress, '1 of 2 reviewed');
      expect(b.open, 1);
    });

    test('GIVEN assignments THEN only assigned ones can be opened, removed ones say why', () {
      final a = [for (final j in [assignment('1', 'assigned'), assignment('2', 'decided'), assignment('3', 'removed', 'reassigned')]) Assignment.fromJson(j)];
      expect(a.map((x) => x.canOpen), [true, false, false]);
      expect(a[1].statusText, 'Done');
      expect(a[2].statusText, 'Reassigned to someone else');
      expect(Assignment.fromJson(assignment('4', 'removed', 'admin_decided')).statusText, 'Decided by the admin');
      expect(Assignment.fromJson(assignment('5', 'removed', 'taken_back')).statusText, 'Taken back by the admin');
      expect(Assignment.fromJson(assignment('6', 'removed', 'user_removed')).statusText, 'Removed from the batch');
    });

    test('GIVEN problems THEN the reviewer gets the words the task asks for', () {
      expect(decisionProblemText('own-scan', 403), "You can't review your own scan.");
      expect(decisionProblemText('already-decided', 409), 'Someone already decided this scan.');
      expect(decisionProblemText('not-found', 404), contains('took it back or reassigned it'));
    });
  });

  group('batch screen (T 74)', () {
    testWidgets('GIVEN a batch THEN it lists scans; only an assigned one opens', (t) async {
      await pumpBatch(t);
      expect(find.text('B-2'), findsWidgets);
      expect(find.text('From Bo Plant04 · 0 of 2 reviewed'), findsOneWidget);
      expect(find.text('To review'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      expect(find.text('Taken back by the admin'), findsOneWidget);

      await t.tap(find.text('10000030')); // the taken-back scan
      await t.pumpAndSettle();
      expect(find.byType(DelegatedReviewScreen), findsNothing); // removed: not openable

      await t.tap(find.text('To review'));
      await t.pumpAndSettle();
      expect(find.byType(DelegatedReviewScreen), findsOneWidget);
    });
  });

  group('review and decide (T 75, 76)', () {
    Future<ReviewerApi> openReview(WidgetTester t, {ReviewerApi? api}) async {
      final a = await pumpBatch(t, api: api);
      await t.tap(find.text('To review'));
      await t.pumpAndSettle();
      return a;
    }

    testWidgets('GIVEN a scan THEN AI value, technician value and verdict, flags; nothing editable', (t) async {
      await openReview(t);
      expect(find.text('Motor Nameplate'), findsOneWidget);
      expect(find.text('Captured by Tara Tech'), findsOneWidget);
      expect(find.text('ECP8442T'), findsOneWidget); // AI
      expect(find.text('ECP8442'), findsOneWidget); // technician
      expect(find.text('Corrected'), findsOneWidget);
      expect(find.text('Low confidence · 62%'), findsOneWidget);
      expect(find.text('Unreadable · label worn'), findsOneWidget);
      expect(find.text('Kept as read'), findsOneWidget);
      expect(find.byType(TextField), findsNothing); // the reviewer cannot edit values
    });

    testWidgets('GIVEN Approve WHEN it succeeds THEN 3.5 gets approved with a key and the batch reloads', (t) async {
      final api = await openReview(t);
      final loads = api.batchLoads;
      await t.tap(find.text('Approve'));
      await t.pumpAndSettle();
      expect(api.decisions.single, {'decision': 'approved'});
      expect(api.keys.single, isNotNull);
      expect(find.byType(DelegatedReviewScreen), findsNothing);
      expect(api.batchLoads, greaterThan(loads));
    });

    testWidgets('GIVEN Reject THEN a category is required; the note is sent as typed', (t) async {
      final api = await openReview(t);
      await t.tap(find.text('Reject'));
      await t.pumpAndSettle();
      final send = find.widgetWithText(FilledButton, 'Reject scan');
      expect(t.widget<FilledButton>(send).onPressed, isNull); // no category yet

      await t.tap(find.text('Data correction needed'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'Serial is on the back plate');
      await t.tap(send);
      await t.pumpAndSettle();
      expect(api.decisions.single, {
        'decision': 'rejected',
        'reject_category': 'data_correction_needed',
        'note': 'Serial is on the back plate',
      });
      expect(find.byType(DelegatedReviewScreen), findsNothing);
    });

    testWidgets('GIVEN Reject without a note THEN the note is null; any rule about it is the API\'s', (t) async {
      final api = await openReview(t)..decideReply = problem(400, 'validation');
      await t.tap(find.text('Reject'));
      await t.pumpAndSettle();
      await t.tap(find.text('Image unclear'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Reject scan'));
      await t.pumpAndSettle();
      expect(api.decisions.single, {'decision': 'rejected', 'reject_category': 'image_unclear', 'note': null});
      expect(find.text('detail for validation'), findsOneWidget); // shown as the API words it
      expect(find.byType(DelegatedReviewScreen), findsOneWidget);
    });

    for (final (code, status, text) in [
      ('own-scan', 403, "You can't review your own scan."),
      ('already-decided', 409, 'Someone already decided this scan.'),
      ('not-found', 404, 'The admin took it back or reassigned it.'),
    ]) {
      testWidgets('GIVEN $status $code on deciding THEN it says so, goes back and refreshes the batch', (t) async {
        final api = await openReview(t)..decideReply = problem(status, code);
        final loads = api.batchLoads;
        await t.tap(find.text('Approve'));
        await t.pumpAndSettle();
        expect(find.byType(DelegatedReviewScreen), findsNothing);
        expect(find.textContaining(text), findsOneWidget);
        expect(api.batchLoads, greaterThan(loads));
      });
    }

    testWidgets('GIVEN the assignment was closed (409 invalid-state) THEN it says taken back and refreshes', (t) async {
      final api = await openReview(t)..decideReply = problem(409, 'invalid-state');
      await t.tap(find.text('Approve'));
      await t.pumpAndSettle();
      expect(find.byType(DelegatedReviewScreen), findsNothing);
      expect(find.textContaining('took it back or reassigned it'), findsOneWidget);
      expect(api.batchLoads, greaterThan(1));
    });

    testWidgets('GIVEN required fields sent empty WHEN Approve is refused THEN it stays, so it can be rejected', (t) async {
      final api = ReviewerApi()
        ..review = reviewJson(emptyRequired: ['Serial number'])
        ..decideReply = json({
          'type': '/problems/invalid-state',
          'title': 'invalid-state',
          'status': 409,
          'detail': 'Required fields are empty: reject it for rework.',
        }, 409);
      await openReview(t, api: api);
      expect(find.text('Sent with required fields empty: Serial number.'), findsOneWidget);
      await t.tap(find.text('Approve'));
      await t.pumpAndSettle();
      expect(find.byType(DelegatedReviewScreen), findsOneWidget);
      expect(find.text('Required fields are empty: reject it for rework.'), findsOneWidget);
    });

    testWidgets('GIVEN the scan is no longer assigned WHEN opened (404) THEN it says so and goes back', (t) async {
      final api = ReviewerApi()..reviewReply = problem(404, 'not-found');
      await openReview(t, api: api);
      expect(find.byType(DelegatedReviewScreen), findsNothing);
      expect(find.textContaining('took it back or reassigned it'), findsOneWidget);
    });
  });
}
