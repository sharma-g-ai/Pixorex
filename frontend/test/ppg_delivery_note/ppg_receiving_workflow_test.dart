import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:label_reader/features/ppg_delivery_note/domain/models.dart';
import 'package:label_reader/features/ppg_delivery_note/parser/ppg_template_parser.dart';
import 'package:label_reader/features/ppg_delivery_note/persistence/ppg_repository.dart';
import 'package:label_reader/features/ppg_delivery_note/screens/ppg_hub_screen.dart';
import 'package:label_reader/features/ppg_delivery_note/screens/ppg_page_identity_screen.dart';
import 'package:label_reader/features/ppg_delivery_note/screens/ppg_page_review_screen.dart';
import 'package:label_reader/features/ppg_delivery_note/screens/ppg_review_screen.dart';
import 'package:label_reader/features/ppg_delivery_note/screens/ppg_session_screen.dart';
import 'package:label_reader/features/ppg_delivery_note/services/ppg_session_controller.dart';

class _MemoryRepository extends PpgRepository {
  _MemoryRepository(this.savedSession, this.page, this.savedLines);
  ScanSession savedSession;
  final PageCapture page;
  List<DocumentLine> savedLines;
  final adjustments = <PhysicalAdjustment>[];
  SubmittedForm? savedSubmission;
  bool failNextWrite = false;
  Completer<void>? nextWriteGate;
  List<SessionProgress> progress = [];
  final deletedSessions = <String>[];

  @override
  Future<List<SessionProgress>> listSessionProgress() async => progress;
  @override
  Future<void> deleteDraftSession(String sessionId) async {
    deletedSessions.add(sessionId);
    progress.removeWhere((item) => item.session.id == sessionId);
  }

  @override
  Future<void> activateReplacement(PageCapture page) async {}

  @override
  Future<ScanSession?> getSession(String id) async => savedSession;
  @override
  Future<List<PageCapture>> getActivePages(String sessionId) async => [page];
  @override
  Future<List<PageCapture>> getPendingReplacements(String sessionId) async =>
      [];
  @override
  Future<List<DocumentLine>> getLines(String sessionId) async =>
      savedLines.map((line) => line.copy()).toList();
  @override
  Future<List<DocumentContext>> getContexts(String sessionId) async => [];
  @override
  Future<SubmittedForm?> getSubmissionForSession(String sessionId) async =>
      savedSubmission;
  @override
  Future<void> saveSession(ScanSession session) async {
    savedSession = session;
  }

  @override
  Future<void> updatePageCapture(PageCapture page) async {}
  @override
  Future<void> addCorrection(CorrectionRecord record) async {}
  @override
  Future<void> saveLine(DocumentLine line) async {
    savedLines[savedLines.indexWhere(
      (old) => old.occurrenceId == line.occurrenceId,
    )] = line
        .copy();
  }

  @override
  Future<bool> hasPhysicalAdjustment(
    String id, {
    required String sessionId,
    required String occurrenceId,
  }) async => adjustments.any(
    (event) =>
        event.id == id &&
        event.sessionId == sessionId &&
        event.occurrenceId == occurrenceId,
  );
  @override
  Future<void> savePhysicalCount({
    required ScanSession session,
    required DocumentLine line,
    required PhysicalAdjustment adjustment,
  }) async {
    final gate = nextWriteGate;
    nextWriteGate = null;
    if (gate != null) await gate.future;
    if (failNextWrite) {
      failNextWrite = false;
      throw StateError('disk full');
    }
    await saveLine(line);
    savedSession = session;
    adjustments.add(adjustment);
  }

  @override
  Future<void> commitConsolidation({
    required ScanSession session,
    required List<DocumentLine> lines,
    required List<DocumentContext> contexts,
    List<PageCapture> changedPages = const [],
  }) async {
    savedSession = session;
    savedLines = lines.map((line) => line.copy()).toList();
  }

  @override
  Future<OcrObservation?> getLatestOcrObservation(PageCapture page) async =>
      OcrObservation(
        ocrRunId: 'ocr',
        pageCaptureId: page.pageCaptureId,
        captureRevision: 1,
        engineName: 'test',
        engineVersion: 'test',
        imageWidth: 1,
        imageHeight: 1,
        elements: const [],
        createdAt: DateTime.utc(2026),
      );
  @override
  Future<SubmittedForm> submitLocal({
    required String sessionId,
    required String submissionId,
    required String snapshotJson,
  }) async {
    savedSession.status = ScanSessionStatus.submittedLocal;
    return savedSubmission = SubmittedForm(
      submissionId: submissionId,
      sessionId: sessionId,
      snapshotJson: snapshotJson,
      submittedAt: DateTime.utc(2026),
    );
  }
}

class _PageParser extends PpgTemplateParser {
  _PageParser(this.lines);
  final List<DocumentLine> lines;
  @override
  ParsedPageResult parse({
    required OcrObservation observation,
    required int printedPageHint,
  }) => ParsedPageResult(
    pageCaptureId: 'p1',
    printedPage: 1,
    deliveryNoteNumber: '5319364114',
    declaredPageCount: 1,
    pageRole: 'product_table',
    issues: const [],
    occurrences: lines
        .map(
          (line) => ParsedOccurrence(
            occurrenceId: line.occurrenceId,
            pageCaptureId: 'p1',
            sourcePage: 1,
            articleNumber: line.rawOcrArticle!,
            role: OccurrenceRole.quantityBearing,
            documentQuantity: line.rawOcrQuantity,
          ),
        )
        .toList(),
  );
}

Future<(_MemoryRepository, PpgSessionController)> _fixture({
  bool checked = true,
  bool duplicate = false,
}) async {
  final directory = Directory.systemTemp.createTempSync('ppg-receiving-test-');
  addTearDown(() => directory.deleteSync(recursive: true));
  final image = File('${directory.path}/source.png');
  image.writeAsBytesSync(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
    ),
  );
  final session = ScanSession(
    id: 's',
    status: ScanSessionStatus.reviewing,
    formRevision: 1,
    deliveryNoteNumber: '5319364114',
    declaredPageCount: 1,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
  final page = PageCapture(
    pageCaptureId: 'p1',
    sessionId: 's',
    printedPage: 1,
    captureRevision: 1,
    isActive: true,
    createdAt: DateTime.utc(2026),
    sourceImagePath: image.path,
    ocrStatus: PageOcrStatus.succeeded,
    pageIdentityConfirmed: true,
    pageReviewConfirmed: checked,
    verifiedDeliveryNoteNumber: '5319364114',
    observedDeliveryNoteNumber: '5319364114',
  );
  final lines = [
    for (var i = 0; i < (duplicate ? 2 : 1); i++)
      DocumentLine(
        occurrenceId: 'line$i',
        sessionId: 's',
        articleNumber: '445386',
        documentQuantity: 8,
        physicalQuantity: 8,
        physicalOrigin: PhysicalQuantityOrigin.defaultedFromDocument,
        sourcePage: 1,
        pageCaptureId: 'p1',
        rawOcrArticle: '445386',
        rawOcrQuantity: 8,
      ),
  ];
  final repo = _MemoryRepository(session, page, lines);
  final ctrl = PpgSessionController(
    repository: repo,
    parser: _PageParser(lines.map((line) => line.copy()).toList()),
  );
  await ctrl.loadSession('s');
  addTearDown(ctrl.dispose);
  return (repo, ctrl);
}

Future<void> _pumpReceiving(
  WidgetTester tester,
  PpgSessionController ctrl,
) async {
  tester.view.physicalSize = const Size(320, 950);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: ctrl,
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: const PpgReviewScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openCountSheet(WidgetTester tester) async {
  await tester.tap(find.text('445386').first);
  await tester.pumpAndSettle();
}

void main() {
  test(
    'scanned can starts at one, saves atomically, and ignores the same event twice',
    () async {
      final (repo, ctrl) = await _fixture();
      final revision = ctrl.session!.formRevision;
      Future<void> accept() => ctrl.addScannedCan(
        articleNumber: '445386',
        occurrenceId: 'line0',
        eventId: 'scan-1',
        expectedSessionId: 's',
        expectedRevision: revision,
      );
      await Future.wait([accept(), accept()]);
      expect(ctrl.lines.single.physicalQuantity, 1);
      expect(ctrl.lines.single.isPhysicalVerified, isFalse);
      expect(repo.adjustments, hasLength(1));
      expect(repo.adjustments.single.action, 'scanArticle');
      expect(repo.adjustments.single.beforeQuantity, 0);
      expect(repo.adjustments.single.afterQuantity, 1);
      await ctrl.loadSession('s');
      await accept();
      expect(ctrl.lines.single.physicalQuantity, 1);
      expect(repo.adjustments, hasLength(1));
    },
  );

  test(
    'scan rejection preserves quantity for wrong article, DN, stale revision and unchecked source',
    () async {
      final (repo, ctrl) = await _fixture();
      for (final args in [
        ('0445386', 's', ctrl.session!.formRevision),
        ('445386', 'other-dn', ctrl.session!.formRevision),
        ('445386', 's', ctrl.session!.formRevision - 1),
      ]) {
        await expectLater(
          ctrl.addScannedCan(
            articleNumber: args.$1,
            occurrenceId: 'line0',
            eventId: 'bad-${args.$1}-${args.$2}-${args.$3}',
            expectedSessionId: args.$2,
            expectedRevision: args.$3,
          ),
          throwsStateError,
        );
      }
      repo.page.pageReviewConfirmed = false;
      await expectLater(
        ctrl.addScannedCan(
          articleNumber: '445386',
          occurrenceId: 'line0',
          eventId: 'unchecked',
          expectedSessionId: 's',
          expectedRevision: ctrl.session!.formRevision,
        ),
        throwsStateError,
      );
      expect(repo.adjustments, isEmpty);
      expect(ctrl.lines.single.hasPhysicalCount, isFalse);
    },
  );

  test(
    'scan allocates once to selected duplicate and failed saves can be retried',
    () async {
      final (repo, ctrl) = await _fixture(duplicate: true);
      final revision = ctrl.session!.formRevision;
      Future<void> accept() => ctrl.addScannedCan(
        articleNumber: '445386',
        occurrenceId: 'line1',
        eventId: 'scan-duplicate',
        expectedSessionId: 's',
        expectedRevision: revision,
      );
      repo.failNextWrite = true;
      await expectLater(accept(), throwsStateError);
      expect(ctrl.lines[1].hasPhysicalCount, isFalse);
      await accept();
      expect(ctrl.lines[0].hasPhysicalCount, isFalse);
      expect(ctrl.lines[1].physicalQuantity, 1);
      await ctrl.finishPhysicalCount(
        occurrenceId: 'line1',
        reason: 'Short received',
      );
      await expectLater(
        ctrl.addScannedCan(
          articleNumber: '445386',
          occurrenceId: 'line1',
          eventId: 'finished',
          expectedSessionId: 's',
          expectedRevision: ctrl.session!.formRevision,
        ),
        throwsStateError,
      );
    },
  );

  testWidgets(
    'count list offers Review and submit only once every item is counted',
    (tester) async {
      final (_, ctrl) = await _fixture();
      await _pumpReceiving(tester, ctrl);
      expect(find.text('0 of 8 PC counted'), findsOneWidget);
      expect(find.text('8 to go'), findsOneWidget);
      expect(find.text('Scan a can'), findsOneWidget);
      expect(find.text('Review and submit'), findsNothing);
      expect(find.text('Pages'), findsNothing);
      await ctrl.setCountedTotal(occurrenceId: 'line0', quantity: 8);
      await ctrl.finishPhysicalCount(
        occurrenceId: 'line0',
        reason: '',
        expectedQuantity: 8,
      );
      await tester.pumpAndSettle();
      expect(find.text('All counted'), findsOneWidget);
      expect(find.text('Scan a can'), findsNothing);
      expect(find.byTooltip('Scan another can'), findsOneWidget);
      await tester.tap(find.text('Review and submit'));
      await tester.pumpAndSettle();
      expect(find.text('Submit receiving form'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('count list stage labels open the other stages', (tester) async {
    final (_, ctrl) = await _fixture();
    await _pumpReceiving(tester, ctrl);
    await tester.tap(find.byKey(const ValueKey('ppg-stage-2')));
    await tester.pumpAndSettle();
    expect(find.text('Submit receiving form'), findsOneWidget);
    await tester.tap(find.byTooltip('Back to count list'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ppg-stage-0')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(PpgSessionScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('receiving scan button opens the can reader', (tester) async {
    final (_, ctrl) = await _fixture();
    await _pumpReceiving(tester, ctrl);
    final scan = find.byKey(const ValueKey('ppg-scan-can-button'));
    expect(scan, findsOneWidget);
    await tester.tap(scan);
    await tester.pumpAndSettle();
    expect(find.textContaining('5319364114'), findsOneWidget);
    expect(find.text('Add this can'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test(
    'page source confirmation does not confirm physical quantities',
    () async {
      final (_, ctrl) = await _fixture(checked: false);
      await ctrl.confirmPageReview(
        pageCaptureId: 'p1',
        coverageConfirmed: true,
      );
      expect(ctrl.sourceReviewReady, isTrue);
      expect(
        ctrl.lines.single.physicalCountState,
        PhysicalCountState.notChecked,
      );
      expect(ctrl.lines.single.physicalQuantityConfirmed, isFalse);
      expect(ctrl.readyForFinalReview, isFalse);
    },
  );

  test(
    'rapid taps commit in order and a counting draft survives reopening',
    () async {
      final (repo, ctrl) = await _fixture();
      await ctrl.startPhysicalCount('line0');
      final gate = Completer<void>();
      repo.nextWriteGate = gate;
      final operations = List.generate(
        20,
        (_) => ctrl.adjustPhysicalCount(occurrenceId: 'line0', delta: 1),
      );
      expect(ctrl.savingPhysicalCounts, isTrue);
      expect(ctrl.lines.single.physicalQuantity, 0);
      gate.complete();
      await Future.wait(operations);
      expect(ctrl.lines.single.physicalQuantity, 20);
      expect(ctrl.lines.single.physicalQuantityConfirmed, isFalse);
      expect(repo.page.pageReviewConfirmed, isTrue);
      expect(ctrl.session!.reviewConfirmedRevision, isNull);
      await ctrl.loadSession('s');
      expect(ctrl.lines.single.physicalQuantity, 20);
      expect(ctrl.lines.single.physicalCountState, PhysicalCountState.counting);
      await ctrl.reconsolidate();
      expect(ctrl.lines.single.physicalQuantity, 20);
      expect(ctrl.lines.single.physicalCountState, PhysicalCountState.counting);
    },
  );

  test(
    'batch adds, set replaces, and only finishing requires a variance reason',
    () async {
      final (_, ctrl) = await _fixture();
      await ctrl.startPhysicalCount('line0');
      await ctrl.addPhysicalBatch(occurrenceId: 'line0', quantity: 3);
      await ctrl.addPhysicalBatch(occurrenceId: 'line0', quantity: 2);
      expect(ctrl.lines.single.physicalQuantity, 5);
      await ctrl.setCountedTotal(occurrenceId: 'line0', quantity: 6);
      expect(ctrl.lines.single.physicalQuantity, 6);
      await expectLater(
        ctrl.finishPhysicalCount(occurrenceId: 'line0'),
        throwsArgumentError,
      );
      expect(ctrl.lines.single.physicalCountState, PhysicalCountState.counting);
      await ctrl.finishPhysicalCount(
        occurrenceId: 'line0',
        reason: 'Short received',
      );
      expect(ctrl.readyForFinalReview, isTrue);
      await ctrl.confirmReview();
      expect(ctrl.session!.reviewConfirmedRevision, ctrl.session!.formRevision);
      await ctrl.reopenPhysicalCount('line0');
      expect(ctrl.lines.single.physicalQuantity, 6);
      expect(ctrl.readyForFinalReview, isFalse);
      expect(ctrl.session!.reviewConfirmedRevision, isNull);
      await expectLater(ctrl.submit(), throwsStateError);
    },
  );

  test(
    'zero is explicit, negatives rejected, and failed writes do not change saved state',
    () async {
      final (repo, ctrl) = await _fixture();
      await ctrl.startPhysicalCount('line0');
      await expectLater(
        ctrl.adjustPhysicalCount(occurrenceId: 'line0', delta: -1),
        throwsArgumentError,
      );
      expect(ctrl.lines.single.physicalQuantity, 0);
      final revision = ctrl.session!.formRevision;
      repo.failNextWrite = true;
      await expectLater(
        ctrl.adjustPhysicalCount(occurrenceId: 'line0', delta: 1),
        throwsStateError,
      );
      expect(ctrl.lines.single.physicalQuantity, 0);
      expect(ctrl.session!.formRevision, revision);
      expect(repo.savedLines.single.physicalQuantity, 0);
      await ctrl.adjustPhysicalCount(occurrenceId: 'line0', delta: 1);
      expect(ctrl.lines.single.physicalQuantity, 1);
      await ctrl.setCountedTotal(occurrenceId: 'line0', quantity: 0);
      await ctrl.finishPhysicalCount(
        occurrenceId: 'line0',
        reason: 'Not received',
      );
      expect(ctrl.lines.single.isPhysicalVerified, isTrue);
      expect(ctrl.lines.single.physicalQuantity, 0);
    },
  );

  test(
    'DN corrections retain the count and article changes require reconciliation',
    () async {
      final (_, ctrl) = await _fixture();
      await ctrl.confirmPhysicalMatchesDocument('line0');
      await ctrl.correctScanResult(
        occurrenceId: 'line0',
        articleNumber: '445386',
        documentQuantity: 10,
        reason: 'Checked printed quantity',
      );
      expect(ctrl.lines.single.physicalQuantity, 8);
      expect(ctrl.lines.single.physicalCountState, PhysicalCountState.recheck);
      expect(ctrl.sourceReviewReady, isFalse);
      await expectLater(
        ctrl.finishPhysicalCount(
          occurrenceId: 'line0',
          reason: 'Short received',
        ),
        throwsStateError,
      );
      await ctrl.confirmPageReview(
        pageCaptureId: 'p1',
        coverageConfirmed: true,
      );
      expect(ctrl.lines.single.physicalQuantity, 8);
      await ctrl.finishPhysicalCount(
        occurrenceId: 'line0',
        reason: 'Short received',
      );
      await ctrl.correctScanResult(
        occurrenceId: 'line0',
        articleNumber: '445999',
        documentQuantity: 10,
        reason: 'Checked printed article',
      );
      await ctrl.confirmPageReview(
        pageCaptureId: 'p1',
        coverageConfirmed: true,
      );
      expect(ctrl.lines.single.needsArticleReconciliation, isTrue);
      await expectLater(
        ctrl.finishPhysicalCount(
          occurrenceId: 'line0',
          reason: 'Short received',
        ),
        throwsStateError,
      );
      await ctrl.reconcilePhysicalCount(occurrenceId: 'line0', restart: false);
      expect(ctrl.lines.single.physicalQuantity, 8);
      expect(ctrl.lines.single.countedArticleNumber, '445999');
      await ctrl.finishPhysicalCount(
        occurrenceId: 'line0',
        reason: 'Short received',
      );
      expect(ctrl.readyForFinalReview, isTrue);
    },
  );

  test('duplicate article occurrences receive independent counts', () async {
    final (_, ctrl) = await _fixture(duplicate: true);
    await ctrl.startPhysicalCount('line0');
    await ctrl.adjustPhysicalCount(occurrenceId: 'line0', delta: 1);
    expect(ctrl.lines.first.physicalQuantity, 1);
    expect(ctrl.lines.last.physicalCountState, PhysicalCountState.notChecked);
    expect(ctrl.countedPhysicalTotal, 1);
    expect(ctrl.documentQuantityTotal, 16);
  });

  test(
    'rescanning or replacing a counted page cannot discard its counts',
    () async {
      final (repo, ctrl) = await _fixture();
      await ctrl.setCountedTotal(occurrenceId: 'line0', quantity: 3);
      await expectLater(ctrl.retryPageOcr('p1'), throwsStateError);
      await expectLater(
        ctrl.updateCropAndRetry(
          pageCaptureId: 'p1',
          rectifiedImagePath: repo.page.sourceImagePath!,
          rotationDegrees: 0,
        ),
        throwsStateError,
      );
      await expectLater(
        ctrl.acceptPage(
          printedPage: 1,
          sourceImagePath: repo.page.sourceImagePath!,
        ),
        throwsStateError,
      );
      expect(ctrl.lines.single.physicalQuantity, 3);
      expect(repo.page.pageReviewConfirmed, isTrue);
      expect(repo.page.ocrStatus, PageOcrStatus.succeeded);
    },
  );

  test(
    'final confirmation requires physical verification and submission locks edits',
    () async {
      final (_, ctrl) = await _fixture();
      await expectLater(ctrl.confirmReview(), throwsStateError);
      await ctrl.confirmPhysicalMatchesDocument('line0');
      await ctrl.confirmReview();
      final submitted = await ctrl.submit();
      final snapshot =
          jsonDecode(submitted.snapshotJson) as Map<String, dynamic>;
      expect(snapshot['physical_quantity_total'], 8);
      expect(
        (snapshot['lines'] as List).single['physical_count_state'],
        'verified',
      );
      expect(ctrl.session!.isSubmitted, isTrue);
      await expectLater(ctrl.reopenPhysicalCount('line0'), throwsStateError);
      expect(ctrl.lines.single.physicalQuantity, 8);
      expect((await ctrl.submit()).submissionId, submitted.submissionId);
    },
  );

  testWidgets(
    'narrow count sheet counts from zero and the counter opens total entry',
    (tester) async {
      final (_, ctrl) = await _fixture();
      await _pumpReceiving(tester, ctrl);
      expect(find.text('0 / 8 PC'), findsOneWidget);
      await _openCountSheet(tester);
      expect(find.text('Matches DN'), findsNothing);
      await tester.tap(find.text('Start count'));
      await tester.pumpAndSettle();
      expect(find.text('0 PC counted'), findsOneWidget);
      final minus = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.remove),
      );
      expect(minus.onPressed, isNull);
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byTooltip('Add one can'));
        await tester.pumpAndSettle();
      }
      expect(ctrl.lines.single.physicalQuantity, 3);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.longPress(find.text('3 PC counted'));
      await tester.pumpAndSettle();
      expect(find.text('Set counted total'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), '8');
      await tester.tap(find.text('Save total'));
      await tester.pumpAndSettle();
      expect(ctrl.lines.single.physicalCountState, PhysicalCountState.counting);
      await tester.ensureVisible(find.text('Finish count at 8 PC'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Finish count at 8 PC'));
      await tester.pumpAndSettle();
      expect(ctrl.lines.single.isPhysicalVerified, isTrue);
      expect(find.text('Reopen count'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'variance reason is requested on finish and Other needs details',
    (tester) async {
      final (_, ctrl) = await _fixture();
      await ctrl.setCountedTotal(occurrenceId: 'line0', quantity: 3);
      await _pumpReceiving(tester, ctrl);
      await _openCountSheet(tester);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.ensureVisible(find.text('Finish count at 3 PC'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Finish count at 3 PC'));
      await tester.pumpAndSettle();
      expect(find.text('Variance reason'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(ctrl.lines.single.physicalCountState, PhysicalCountState.counting);
      await tester.tap(find.text('Finish count at 3 PC'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Other').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Verify count'));
      await tester.pumpAndSettle();
      expect(find.text('Explain the variance'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'Count checked twice');
      await tester.ensureVisible(find.text('Verify count'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Verify count'));
      await tester.pumpAndSettle();
      expect(ctrl.lines.single.varianceReason, 'Other: Count checked twice');
      expect(ctrl.lines.single.isPhysicalVerified, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Matches DN is not offered and submitted count controls are read only',
    (tester) async {
      final (_, ctrl) = await _fixture();
      await _pumpReceiving(tester, ctrl);
      await _openCountSheet(tester);
      expect(find.text('Matches DN'), findsNothing);
      expect(ctrl.verifiedPhysicalCount, 0);
      await ctrl.setCountedTotal(occurrenceId: 'line0', quantity: 8);
      await ctrl.finishPhysicalCount(
        occurrenceId: 'line0',
        reason: '',
        expectedQuantity: 8,
      );
      expect(ctrl.verifiedPhysicalCount, 1);
      await ctrl.confirmReview();
      await ctrl.submit();
      await tester.pumpAndSettle();
      expect(find.text('Reopen count'), findsNothing);
      expect(find.text('Start count'), findsNothing);
      expect(find.byTooltip('Add one can'), findsNothing);
      expect(find.byKey(const ValueKey('ppg-scan-can-button')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'page identity offers the printed page and warns when the entry differs',
    (tester) async {
      final (repo, ctrl) = await _fixture(checked: false);
      repo.page
        ..suggestedPrintedPage = 1
        ..suggestedDeclaredPageCount = 1;
      PpgIdentityOutcome? outcome;
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: ctrl,
          child: MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  outcome = await Navigator.push<PpgIdentityOutcome>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChangeNotifierProvider.value(
                        value: ctrl,
                        child: const PpgPageIdentityScreen(pageCaptureId: 'p1'),
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('This is page 1 of 1'), findsOneWidget);
      expect(find.text('Save as page 1'), findsOneWidget);
      await tester.tap(find.text('Wrong number?'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Page'), '2');
      await tester.enterText(find.widgetWithText(TextField, 'of'), '2');
      await tester.pumpAndSettle();
      expect(find.textContaining('but you entered 2'), findsOneWidget);
      await tester.ensureVisible(find.text('Use page 1, as printed'));
      await tester.tap(find.text('Use page 1, as printed'));
      await tester.pumpAndSettle();
      expect(outcome, PpgIdentityOutcome.confirmed);
      expect(repo.page.printedPage, 1);
      expect(repo.page.verifiedDeliveryNoteNumber, '5319364114');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('hub offers delete only for drafts without counts', (
    tester,
  ) async {
    final (repo, ctrl) = await _fixture();
    DateTime at(int minute) => DateTime.utc(2026, 10, 9, 10, minute);
    ScanSession draft(String id, String? dn) => ScanSession(
      id: id,
      status: ScanSessionStatus.draft,
      formRevision: 1,
      deliveryNoteNumber: dn,
      createdAt: at(0),
      updatedAt: at(1),
    );
    repo.progress = [
      SessionProgress(
        session: draft('counted', '5319364114'),
        pageCount: 1,
        checkedPageCount: 1,
        itemCount: 1,
        countedItemCount: 1,
        countedTotal: 3,
        documentTotal: 8,
      ),
      SessionProgress(session: draft('empty', null)),
    ];
    await ctrl.refreshSessions();
    ctrl.ready = true;
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: PpgHubScreen(controller: ctrl)));
    await tester.pumpAndSettle();
    expect(find.text('Continue counting'), findsOneWidget);
    expect(find.text('Delivery number not read yet'), findsOneWidget);
    expect(find.byTooltip('Delete this draft'), findsOneWidget);
    await tester.tap(find.byTooltip('Delete this draft'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this draft?'), findsOneWidget);
    await tester.tap(find.text('Delete draft'));
    await tester.pumpAndSettle();
    expect(repo.deletedSessions, ['empty']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('DN page review contains only source checks', (tester) async {
    final (_, ctrl) = await _fixture(checked: false);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: ctrl,
        child: const MaterialApp(
          home: PpgPageReviewScreen(pageCaptureId: 'p1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Edit physical count'), findsNothing);
    expect(
      find.text('I physically checked every count on this page'),
      findsNothing,
    );
    expect(find.text('Confirm page 1'), findsOneWidget);
    expect(ctrl.lines.single.physicalQuantityConfirmed, isFalse);
    expect(tester.takeException(), isNull);
  });
}
