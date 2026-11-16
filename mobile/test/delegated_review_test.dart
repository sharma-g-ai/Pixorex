import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pixorex_mobile/features/auth/session_controller.dart';
import 'package:pixorex_mobile/features/home/home_screen.dart';
import 'package:pixorex_mobile/features/review/batch_screen.dart';
import 'package:pixorex_mobile/features/review/decision_changed_screen.dart';
import 'package:pixorex_mobile/features/review/delegated_models.dart';
import 'package:pixorex_mobile/features/review/delegated_review_screen.dart';
import 'package:pixorex_mobile/features/scan/scan_repository.dart';
import 'package:provider/provider.dart';

import 'auth_flow_test.dart' show json, problem;
import 'new_scan_screen_test.dart' show signedIn;

Map<String, dynamic> batchJson({int scans = 3, int decided = 1, int open = 1, int unseen = 0, String status = 'active'}) => {
      'batch_id': 'b2',
      'batch_no': 'B-2',
      'assigned_to_name': 'Dana Dual',
      'created_by_name': 'Bo Plant04',
      'scan_count': scans,
      'decided_count': decided,
      'open_count': open,
      'overridden_count': unseen,
      'overridden_unseen_count': unseen,
      'created_at': '2026-11-13T09:00:00Z',
      'reminded_at': null,
      'status': status,
    };

Map<String, dynamic> assignment(String id, String status,
        {String? reason, String type = 'Motor Nameplate', int flags = 1, Map<String, dynamic>? mine}) =>
    {
      'scan_id': id,
      'record_no': '100000${id}0',
      'status': status,
      'removed_reason': reason,
      'equipment_type_name': type,
      'captured_by_name': 'Tara Tech',
      'location_path': 'Plant 04 › Building C › Bin 0$id',
      'flag_count': flags,
      'submitted_at': '2026-11-13T08:00:00Z',
      'thumbnail_url': null,
      'my_decision': mine,
    };

Map<String, dynamic> approvedByMe({Map<String, dynamic>? override}) =>
    {'decision': 'approved', 'reject_category': null, 'decided_at': '2026-11-13T10:00:00Z', 'override': override};

Map<String, dynamic> changedToRejected({bool seen = false}) => {
      'decision': 'rejected',
      'reject_category': 'data_correction_needed',
      'note': 'Rated voltage on the plate is 460 V, not 415 V.',
      'decided_by_name': 'Bo Plant04',
      'decided_at': '2026-11-13T11:00:00Z',
      'notification_id': 'n1',
      'seen': seen,
    };

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
          'field_key': 'voltage',
          'label': 'Rated voltage',
          'ai_value': '4I5 V',
          'confidence': 0.62,
          'flag_reasons': ['format_failed'],
          'technician_value': '415 V',
          'verification_state': 'corrected',
          'unreadable_reason': null,
          'note': null,
        },
        {
          'field_key': 'power',
          'label': 'Power',
          'ai_value': null,
          'confidence': null,
          'flag_reasons': ['missing_required'],
          'technician_value': null,
          'verification_state': 'unreadable',
          'unreadable_reason': 'label_worn',
          'note': null,
        },
        {
          'field_key': 'model',
          'label': 'Model number',
          'ai_value': '1LE1001-1CB2',
          'confidence': 0.98,
          'flag_reasons': [],
          'technician_value': '1LE1001-1CB2',
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
  Map<String, dynamic> batch = batchJson();
  List<Map<String, dynamic>> assignments = [
    assignment('1', 'assigned'),
    assignment('2', 'decided', mine: approvedByMe()),
    assignment('3', 'removed', reason: 'taken_back'),
  ];
  Map<String, dynamic> review = reviewJson();
  http.Response? decideReply;
  http.Response? reviewReply;
  final decisions = <Map<String, dynamic>>[];
  final keys = <String?>[];
  final read = <String>[];
  int batchLoads = 0;

  Future<http.Response> call(http.BaseRequest r) async {
    final p = r.url.path;
    if (p.endsWith('/me/review-batches')) return json({'items': batches, 'page': {'next_cursor': null}});
    if (p.endsWith('/review-batches/b2')) {
      batchLoads++;
      return json({'batch': batch, 'assignments': assignments});
    }
    if (p.endsWith('/review')) return reviewReply ?? json(review);
    if (p.endsWith('/decisions')) {
      keys.add(r.headers['Idempotency-Key']);
      decisions.add(jsonDecode((r as http.Request).body) as Map<String, dynamic>);
      return decideReply ?? json({'decision_id': 'd1', 'review_status': 'approved'}, 201);
    }
    if (p.contains('/me/notifications/') && p.endsWith('/read')) {
      read.add(p.split('/').reversed.elementAt(1));
      return http.Response('', 204);
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
  group('Home: entry to the batch (T 14, contract 3.15)', () {
    Future<void> pumpHomeWith(WidgetTester t, ReviewerApi api) async {
      // No scans of my own: Home shows its first-time view, the card must still be there.
      Future<http.Response> handler(http.BaseRequest r) =>
          r.url.path.endsWith('/me/scans') ? Future.value(json({'items': [], 'page': {'next_cursor': null}})) : api.call(r);
      final rig = await signedIn(handler);
      await t.pumpWidget(ChangeNotifierProvider<SessionController>.value(
        value: rig.session,
        child: MaterialApp(home: Scaffold(body: HomeTab(scans: ScanRepository(rig.api)))),
      ));
      await t.pumpAndSettle();
    }

    testWidgets('GIVEN a batch THEN "N scans to review for <admin>", tap opens it', (t) async {
      await pumpHomeWith(t, ReviewerApi()..batches = [batchJson(open: 12, decided: 18, scans: 30)]);
      expect(find.text('12 scans to review for Bo Plant04'), findsOneWidget);
      expect(find.text('Batch B-2 · from other technicians'), findsOneWidget);
      await t.tap(find.text('12 scans to review for Bo Plant04'));
      await t.pumpAndSettle();
      expect(find.byType(BatchScreen), findsOneWidget);
    });

    testWidgets('GIVEN a finished batch with a change not seen THEN Home says so', (t) async {
      await pumpHomeWith(t, ReviewerApi()..batches = [batchJson(open: 0, decided: 2, unseen: 1, status: 'completed')]);
      expect(find.text('Bo Plant04 changed 1 of your decisions.'), findsOneWidget);
      expect(find.text('Batch B-2 · tap to see why'), findsOneWidget);
    });

    testWidgets('GIVEN no batches THEN no card', (t) async {
      await pumpHomeWith(t, ReviewerApi()..batches = []);
      expect(find.textContaining('to review for'), findsNothing);
    });
  });

  group('models', () {
    test('GIVEN a batch THEN progress counts what stays in it, not taken-back scans', () {
      final b = ReviewBatch.fromJson(batchJson(scans: 30, decided: 18, open: 10));
      expect(b.progress, '18 of 28 done');
      expect(b.toReviewText, '10 scans to review for Bo Plant04');
    });

    test('GIVEN assignments THEN only assigned ones open; decided says my decision; removed says why', () {
      final a = Assignment.fromJson(assignment('1', 'assigned'));
      final d = Assignment.fromJson(assignment('2', 'decided', mine: approvedByMe()));
      final r = Assignment.fromJson(assignment('3', 'removed', reason: 'reassigned'));
      expect([a.canOpen, d.canOpen, r.canOpen], [true, false, false]);
      expect(d.statusText, 'Approved');
      final changed = Assignment.fromJson(assignment('5', 'decided', mine: approvedByMe(override: changedToRejected())));
      expect((changed.statusText, changed.endedApproved), ('Changed → Rejected', false));
      expect(r.statusText, 'Reassigned to someone else');
      expect(Assignment.fromJson(assignment('4', 'removed', reason: 'admin_decided')).statusText, 'Decided by the admin');
    });

    test('GIVEN a reject reason THEN Other needs a note (O-21), the others do not', () {
      expect(rejectReady(null, ''), isFalse);
      expect(rejectReady('other', '  '), isFalse);
      expect(rejectReady('other', 'Wrong plate'), isTrue);
      expect(rejectReady('image_unclear', ''), isTrue);
    });

    test('GIVEN problems THEN the reviewer gets plain words', () {
      expect(decisionProblemText('own-scan', 403), "You can't review your own scan.");
      expect(decisionProblemText('already-decided', 409), 'Someone already decided this scan.');
      expect(decisionProblemText('not-found', 404), contains('took it back or reassigned it'));
    });
  });

  group('batch screen (T 74, contract 3.11)', () {
    testWidgets('GIVEN a batch THEN header, To review / Done, removed greyed at the bottom, footer', (t) async {
      await pumpBatch(t);
      expect(find.text('Review batch B-2'), findsOneWidget);
      expect(find.textContaining('From Bo Plant04 · BU Admin', findRichText: true), findsOneWidget);
      expect(find.text('1 of 2 done'), findsOneWidget); // the taken-back scan doesn't count
      expect(find.text('TO REVIEW · 1'), findsOneWidget);
      expect(find.text('DONE · 1'), findsOneWidget);
      expect(find.text('Captured by Tara Tech · Bin 01 · 1 flagged'), findsOneWidget);
      expect(find.text('Captured by Tara Tech · you approved'), findsOneWidget);
      expect(find.text('Captured by Tara Tech · Taken back by the admin'), findsOneWidget);
      expect(find.text('Removed'), findsOneWidget);
      expect(find.textContaining('Your own scans are never in your batch.'), findsOneWidget);
      expect(
        t.getTopLeft(find.text('Captured by Tara Tech · you approved')).dy,
        lessThan(t.getTopLeft(find.text('Captured by Tara Tech · Taken back by the admin')).dy),
      );

      await t.tap(find.text('Captured by Tara Tech · Taken back by the admin'));
      await t.pumpAndSettle();
      expect(find.byType(DelegatedReviewScreen), findsNothing); // removed: can't be opened

      await t.tap(find.text('To review'));
      await t.pumpAndSettle();
      expect(find.byType(DelegatedReviewScreen), findsOneWidget);
      expect(find.text('2 of 2'), findsOneWidget); // its place in the batch
    });

    testWidgets('GIVEN a decision the admin changed THEN the banner opens T 77; Got it marks it read', (t) async {
      final api = ReviewerApi()
        ..batch = batchJson(open: 0, decided: 1, unseen: 1, status: 'completed')
        ..assignments = [assignment('2', 'decided', mine: approvedByMe(override: changedToRejected()))];
      await pumpBatch(t, api: api);
      expect(find.textContaining('Bo Plant04 changed 1 of your decisions. See why.', findRichText: true), findsOneWidget);
      expect(find.text('Captured by Tara Tech · you approved · changed by Bo Plant04'), findsOneWidget);
      // The tag shows where the scan ended, not a green "Approved" on a rejected scan.
      expect(find.text('Changed → Rejected'), findsOneWidget);
      expect(find.text('Approved'), findsNothing);

      await t.tap(find.textContaining('changed 1 of your decisions', findRichText: true));
      await t.pumpAndSettle();
      expect(find.byType(DecisionChangedScreen), findsOneWidget);
      expect(find.text('You decided'), findsOneWidget);
      expect(find.text('Bo Plant04 changed it to'), findsOneWidget);
      expect(find.text('Data correction needed'), findsOneWidget);
      expect(find.text('"Rated voltage on the plate is 460 V, not 415 V."'), findsOneWidget);
      expect(find.textContaining('Nothing for you to do'), findsOneWidget);

      final loads = api.batchLoads;
      await t.tap(find.text('Got it'));
      await t.pumpAndSettle();
      expect(api.read, ['n1']);
      expect(find.byType(DecisionChangedScreen), findsNothing);
      expect(api.batchLoads, greaterThan(loads));
    });
  });

  group('review and decide (T 75, T 76)', () {
    Future<ReviewerApi> openReview(WidgetTester t, {ReviewerApi? api}) async {
      final a = await pumpBatch(t, api: api);
      await t.tap(find.text('To review'));
      await t.pumpAndSettle();
      return a;
    }

    testWidgets('GIVEN a scan THEN read-only, technician value only when corrected, flag lines', (t) async {
      await openReview(t);
      expect(find.text('Motor Nameplate'), findsOneWidget);
      expect(find.textContaining('Read-only. You approve or reject', findRichText: true), findsOneWidget);
      expect(find.text('4I5 V'), findsOneWidget); // AI read, struck through
      expect(find.text('415 V'), findsOneWidget); // Technician
      expect(find.text('Technician'), findsOneWidget); // only on the corrected field
      expect(find.text('Flagged: format check failed'), findsOneWidget);
      expect(find.text('Flagged: missing · marked unreadable by Tara Tech (label worn)'), findsOneWidget);
      expect(find.text('Looks right'), findsOneWidget);
      expect(find.text('Unreadable'), findsOneWidget);
      expect(find.byType(TextField), findsNothing); // nothing to edit
    });

    testWidgets('GIVEN Approve THEN 3.5 gets approved with a key and the batch reloads', (t) async {
      final api = await openReview(t);
      final loads = api.batchLoads;
      await t.tap(find.text('Approve'));
      await t.pumpAndSettle();
      expect(api.decisions.single, {'decision': 'approved'});
      expect(api.keys.single, isNotNull);
      expect(find.byType(DelegatedReviewScreen), findsNothing);
      expect(api.batchLoads, greaterThan(loads));
    });

    testWidgets('GIVEN Reject THEN "Why are you rejecting it?", Other needs a note, Cancel closes', (t) async {
      final api = await openReview(t);
      await t.tap(find.text('Reject'));
      await t.pumpAndSettle();
      expect(find.text('Why are you rejecting it?'), findsOneWidget);
      final send = find.widgetWithText(FilledButton, 'Reject scan');
      expect(t.widget<FilledButton>(send).onPressed, isNull); // no reason yet

      await t.tap(find.text('Other'));
      await t.pumpAndSettle();
      expect(find.text('Add a note for Tara Tech (required for Other)'), findsOneWidget);
      expect(t.widget<FilledButton>(send).onPressed, isNull); // Other without a note

      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(find.text('Why are you rejecting it?'), findsNothing);
      expect(api.decisions, isEmpty);

      await t.tap(find.text('Reject'));
      await t.pumpAndSettle();
      await t.tap(find.text('Other'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'Plate is for another motor');
      await t.pumpAndSettle();
      await t.tap(send);
      await t.pumpAndSettle();
      expect(api.decisions.single, {'decision': 'rejected', 'reject_category': 'other', 'note': 'Plate is for another motor'});
    });

    testWidgets('GIVEN a listed reason THEN no note is needed; the note is null', (t) async {
      final api = await openReview(t);
      await t.tap(find.text('Reject'));
      await t.pumpAndSettle();
      expect(find.text('Add a note for Tara Tech (optional)'), findsOneWidget);
      await t.tap(find.text('Image unclear'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Reject scan'));
      await t.pumpAndSettle();
      expect(api.decisions.single, {'decision': 'rejected', 'reject_category': 'image_unclear', 'note': null});
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
      await openReview(t, api: ReviewerApi()..reviewReply = problem(404, 'not-found'));
      expect(find.byType(DelegatedReviewScreen), findsNothing);
      expect(find.textContaining('took it back or reassigned it'), findsOneWidget);
    });
  });
}
