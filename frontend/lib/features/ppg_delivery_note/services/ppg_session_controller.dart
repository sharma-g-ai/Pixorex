import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../domain/local_submission.dart';
import '../domain/models.dart';
import '../domain/source_correction.dart';
import '../domain/validation.dart';
import '../ocr/ppg_ocr_adapter.dart';
import '../ocr/total_qty_field_reader.dart';
import '../parser/consolidator.dart';
import '../parser/ppg_template_parser.dart';
import '../persistence/ppg_repository.dart';

class PpgSessionController extends ChangeNotifier {
  PpgSessionController({
    PpgRepository? repository,
    PpgOcrAdapter? ocrAdapter,
    PpgTemplateParser? parser,
    PpgConsolidator? consolidator,
    LocalSubmissionService? submissionService,
    Uuid? uuid,
  }) : _repo = repository ?? PpgRepository(),
       _ocr = ocrAdapter ?? PpgOcrAdapter(),
       _parser = parser ?? PpgTemplateParser(),
       _consolidator = consolidator ?? PpgConsolidator(),
       _submission = submissionService ?? LocalSubmissionService(),
       _uuid = uuid ?? const Uuid();

  final PpgRepository _repo;
  final PpgOcrAdapter _ocr;
  final PpgTemplateParser _parser;
  final PpgConsolidator _consolidator;
  final LocalSubmissionService _submission;
  final Uuid _uuid;

  bool ready = false;
  String? error;

  /// The vessel new delivery notes are started on.
  String vesselId = ppgDefaultVesselId;
  List<ScanSession> sessions = [];
  ScanSession? session;
  List<PageCapture> pages = [];
  List<PageCapture> pendingPages = [];
  List<DocumentLine> lines = [];
  List<DocumentContext> contexts = [];
  List<String> blockingIssues = [];
  List<String> _parsedBlockingIssues = [];
  SubmittedForm? submission;
  bool processing = false;
  Future<void> _countWrites = Future<void>.value();
  int _pendingCountWrites = 0;

  bool get savingPhysicalCounts => _pendingCountWrites > 0;
  Future<void> waitForPhysicalCounts() => _countWrites;

  List<String> get sourceReviewIssues => {
    ...blockingIssues,
    if (session?.deliveryNoteNumber == null)
      'Verify the delivery note identity',
    if (pages.isEmpty) 'Scan the delivery note pages',
    for (final page in pages)
      if (!page.pageReviewConfirmed)
        'Page ${page.printedPage}: check DN values and full-page coverage',
  }.toList();

  bool get sourceReviewReady => sourceReviewIssues.isEmpty;
  bool pageHasPhysicalCounts(String captureId) => lines.any(
    (line) => line.pageCaptureId == captureId && line.hasPhysicalCount,
  );

  void _requireUncountedPage(String captureId) {
    if (pageHasPhysicalCounts(captureId)) {
      throw StateError(
        'This page has saved physical counts. Correct its DN values directly to preserve those counts.',
      );
    }
  }

  int get verifiedPhysicalCount =>
      lines.where((line) => line.isPhysicalVerified).length;
  int get countedPhysicalTotal => lines
      .where((line) => line.hasPhysicalCount)
      .fold<int>(0, (sum, line) => sum + line.physicalQuantity);
  int get verifiedPhysicalTotal => lines
      .where((line) => line.isPhysicalVerified)
      .fold<int>(0, (sum, line) => sum + line.physicalQuantity);
  bool get readyForFinalReview =>
      sourceReviewReady &&
      !savingPhysicalCounts &&
      lines.isNotEmpty &&
      lines.every(
        (line) =>
            line.isPhysicalVerified &&
            (line.variance == 0 ||
                (line.varianceReason?.trim().isNotEmpty ?? false)),
      );

  /// Progress figures for every saved delivery note, newest first.
  List<SessionProgress> progress = [];

  /// Whole-document checks that are not tied to one page slot.
  List<String> get documentIssues {
    final s = session;
    if (s == null) return const [];
    return {
      ..._parsedBlockingIssues,
      ..._submission.validatePieceSummary(
        activePages: pages,
        lines: lines,
        declaredPageCount: s.declaredPageCount,
      ),
    }.toList();
  }

  Future<void> init() async {
    try {
      error = null;
      await _repo.init();
      await _loadSessionLists();
      ready = true;
    } catch (failure) {
      ready = false;
      error = 'Saved delivery notes could not be opened on this device.';
      debugPrint('PPG repository init failed: $failure');
    }
    notifyListeners();
  }

  Future<void> refreshSessions() async {
    await _loadSessionLists();
    notifyListeners();
  }

  Future<void> _loadSessionLists() async {
    progress = await _repo.listSessionProgress();
    sessions = progress.map((item) => item.session).toList();
  }

  /// Leaves the active delivery note, e.g. before starting a new one. Nothing
  /// is saved until the first page of the new note is accepted.
  void closeSession() {
    session = null;
    pages = [];
    pendingPages = [];
    lines = [];
    contexts = [];
    blockingIssues = [];
    _parsedBlockingIssues = [];
    submission = null;
    error = null;
    _lastParsed.clear();
    notifyListeners();
  }

  /// Deletes an unsubmitted draft that has no physical counts.
  Future<void> deleteDraft(String sessionId) async {
    await waitForPhysicalCounts();
    await _repo.deleteDraftSession(sessionId);
    if (session?.id == sessionId) closeSession();
    await refreshSessions();
  }

  Future<ScanSession> startSession({
    String? operatorEmail,
    CaptureMode mode = CaptureMode.camera,
  }) async {
    final created = await _repo.createSession(
      operatorEmail: operatorEmail,
      mode: mode,
      vesselId: vesselId,
    );
    await loadSession(created.id);
    await refreshSessions();
    return created;
  }

  Future<void> loadSession(String id) async {
    await waitForPhysicalCounts();
    error = null;
    session = await _repo.getSession(id);
    pages = await _repo.getActivePages(id);
    pendingPages = await _repo.getPendingReplacements(id);
    lines = await _repo.getLines(id);
    contexts = await _repo.getContexts(id);
    submission = await _repo.getSubmissionForSession(id);
    _lastParsed.clear();
    for (final page in pages.where(
      (p) => p.ocrStatus == PageOcrStatus.succeeded,
    )) {
      final obs = await _repo.getLatestOcrObservation(page);
      if (obs != null) {
        _lastParsed[page.pageCaptureId] = _assignPage(
          _parser.parse(observation: obs, printedPageHint: page.printedPage),
          page.printedPage,
        );
        if (page.observedDeliveryNoteNumber == null &&
            _lastParsed[page.pageCaptureId]!.deliveryNoteNumber != null) {
          page.observedDeliveryNoteNumber =
              _lastParsed[page.pageCaptureId]!.deliveryNoteNumber;
          await _repo.updatePageCapture(page);
        }
        if (page.observedPieceCount == null &&
            _lastParsed[page.pageCaptureId]!.pieceCount != null) {
          page.observedPieceCount = _lastParsed[page.pageCaptureId]!.pieceCount;
          await _repo.updatePageCapture(page);
        }
      }
    }
    for (final page in pendingPages.where(
      (p) => p.ocrStatus == PageOcrStatus.succeeded,
    )) {
      final obs = await _repo.getLatestOcrObservation(page);
      if (obs != null) {
        _lastParsed[page.pageCaptureId] = _assignPage(
          _parser.parse(observation: obs, printedPageHint: page.printedPage),
          page.printedPage,
        );
      }
    }
    _parsedBlockingIssues = _consolidator
        .consolidate(
          sessionId: id,
          pages: pages
              .where((p) => p.pageIdentityConfirmed)
              .map((p) => _lastParsed[p.pageCaptureId])
              .whereType<ParsedPageResult>()
              .where((p) => p.deliveryNoteNumber != null)
              .map((p) => applySavedTotalCorrections(p, lines))
              .toList(),
        )
        .blockingIssues;
    _refreshBlockingIssues();
    notifyListeners();
  }

  /// Accept a captured/imported page. [sourceImagePath] is the untouched original;
  /// [rectifiedImagePath] is the perspective-corrected image used for OCR.
  Future<PageCapture> acceptPage({
    required int printedPage,
    required String sourceImagePath,
    String? rectifiedImagePath,
    int rotationDegrees = 0,
    bool runOcr = true,
    bool useSyntheticOcr = false,
  }) async {
    await waitForPhysicalCounts();
    final s = session;
    if (s == null || s.isSubmitted) {
      throw StateError('No editable session');
    }
    if (printedPage < 1 ||
        printedPage > 1000 ||
        (s.declaredPageCount != null && printedPage > s.declaredPageCount!)) {
      throw ArgumentError(
        'Printed page must be within the declared page range',
      );
    }
    error = null;

    for (final existing in pages.where(
      (page) => page.printedPage == printedPage,
    )) {
      _requireUncountedPage(existing.pageCaptureId);
    }
    final sourceBytes = await File(sourceImagePath).readAsBytes();
    final replacing = pages.any((p) => p.printedPage == printedPage);
    for (final oldPending in pendingPages.where(
      (p) => p.printedPage == printedPage,
    )) {
      await _repo.discardReplacement(oldPending);
      _lastParsed.remove(oldPending.pageCaptureId);
    }
    final capture = await _repo.addPageCapture(
      sessionId: s.id,
      printedPage: printedPage,
      pendingReplacement: replacing,
    );
    final storedSource = await _repo.persistImageBytes(
      sessionId: s.id,
      pageCaptureId: capture.pageCaptureId,
      bytes: sourceBytes,
      kind: 'source',
    );
    capture.sourceImagePath = storedSource;
    capture.rotationDegrees = rotationDegrees;
    capture.pageIdentityConfirmed = false;

    final rectPath = rectifiedImagePath ?? sourceImagePath;
    final rectBytes = await File(rectPath).readAsBytes();
    final storedRect = await _repo.persistImageBytes(
      sessionId: s.id,
      pageCaptureId: capture.pageCaptureId,
      bytes: rectBytes,
      kind: 'rectified',
    );
    capture.rectifiedImagePath = storedRect;
    await _repo.updatePageCapture(capture);

    pages = await _repo.getActivePages(s.id);
    pendingPages = await _repo.getPendingReplacements(s.id);
    _refreshBlockingIssues();
    notifyListeners();

    if (runOcr) {
      await processPageOcr(capture, useSynthetic: useSyntheticOcr);
    }
    return capture;
  }

  Future<void> processPageOcr(
    PageCapture capture, {
    bool useSynthetic = false,
  }) async {
    await waitForPhysicalCounts();
    final s = session;
    if (s == null || s.isSubmitted) throw StateError('No editable session');
    _requireUncountedPage(capture.pageCaptureId);

    capture.pageReviewConfirmed = false;
    capture.ocrStatus = PageOcrStatus.running;
    capture.ocrError = null;
    await _repo.updatePageCapture(capture);
    pages = await _repo.getActivePages(s.id);
    pendingPages = await _repo.getPendingReplacements(s.id);
    notifyListeners();

    try {
      final active = await _repo.getPageCapture(capture.pageCaptureId);
      if (active == null || !active.isActive) {
        return;
      }

      late final OcrObservation obs;
      if (useSynthetic || s.mode == CaptureMode.illustrativeFixture) {
        obs = await _ocr.loadSyntheticFixture(
          assetPath: 'assets/ppg/dn_5319364114_synthetic_ocr.json',
          printedPage: capture.printedPage,
          pageCaptureId: capture.pageCaptureId,
          captureRevision: capture.captureRevision,
        );
      } else {
        final path = capture.rectifiedImagePath ?? capture.sourceImagePath;
        if (path == null) throw StateError('Missing image path');
        obs = await _ocr.recognizeFile(
          imagePath: path,
          pageCaptureId: capture.pageCaptureId,
          captureRevision: capture.captureRevision,
        );
      }

      final stillActive = await _repo.getPageCapture(capture.pageCaptureId);
      if (stillActive == null ||
          !stillActive.isActive ||
          stillActive.captureRevision != capture.captureRevision) {
        return;
      }

      final initial = _parser.parse(
        observation: obs,
        printedPageHint: capture.printedPage,
      );
      final enrichedObs = await _readUnresolvedTotalFields(
        capture: capture,
        observation: obs,
        parsed: initial,
        useSynthetic: useSynthetic,
      );
      await _repo.saveOcrObservation(enrichedObs);
      final parsed = _parser.parse(
        observation: enrichedObs,
        printedPageHint: capture.printedPage,
      );
      capture.observedDeliveryNoteNumber = parsed.deliveryNoteNumber;
      capture.observedPieceCount = parsed.pieceCount;

      if (parsed.pageRole == 'rejected_non_ppg' ||
          parsed.pageRole == 'unverified_layout') {
        capture.ocrStatus = PageOcrStatus.failed;
        capture.ocrError = parsed.issues.isNotEmpty
            ? parsed.issues.first
            : 'Unknown document layout';
        error = capture.ocrError;
        await _repo.updatePageCapture(capture);
        pages = await _repo.getActivePages(s.id);
        pendingPages = await _repo.getPendingReplacements(s.id);
        _refreshBlockingIssues();
        notifyListeners();
        return;
      }

      var identityMismatch = false;
      if (parsed.deliveryNoteNumber != null) {
        if (s.deliveryNoteNumber == null) {
          s.deliveryNoteNumber = parsed.deliveryNoteNumber;
        } else if (s.deliveryNoteNumber != parsed.deliveryNoteNumber) {
          // Keep the source available for operator verification. Never merge
          // rows from a page whose delivery identity has not been confirmed.
          identityMismatch = true;
        }
      }

      // Suggest page identity — do NOT overwrite operator printed page silently.
      capture.suggestedPrintedPage = parsed.printedPageDetected
          ? parsed.printedPage
          : null;
      capture.suggestedDeclaredPageCount = parsed.declaredPageCount;

      s.declaredPageCount ??= parsed.declaredPageCount;
      if (identityMismatch) {
        capture.pageIdentityConfirmed = false;
        capture.ocrError =
            'OCR reads delivery ${parsed.deliveryNoteNumber}; this session currently reads ${s.deliveryNoteNumber}. Verify the printed delivery number against the source page. If the printed number is different, start a new delivery-note scan.';
        error = capture.ocrError;
      } else if (capture.suggestedPrintedPage != null &&
          capture.suggestedPrintedPage != capture.printedPage) {
        capture.pageIdentityConfirmed = false;
      } else if (capture.suggestedPrintedPage != null) {
        capture.pageIdentityConfirmed = true;
      }

      capture.ocrStatus = PageOcrStatus.succeeded;
      if (!identityMismatch) capture.ocrError = null;
      await _repo.updatePageCapture(capture);
      if (capture.pageIdentityConfirmed && !capture.pendingReplacement) {
        await _repo.activateReplacement(capture);
      }
      await _repo.saveSession(s);
      _lastParsed[capture.pageCaptureId] = parsed;
      if (capture.pendingReplacement) {
        pendingPages = await _repo.getPendingReplacements(s.id);
        _refreshBlockingIssues();
        notifyListeners();
      } else {
        await reconsolidate(extraParsed: {capture.pageCaptureId: parsed});
      }
    } catch (e) {
      capture.ocrStatus = PageOcrStatus.failed;
      capture.ocrError = e.toString();
      await _repo.updatePageCapture(capture);
      pages = await _repo.getActivePages(s.id);
      pendingPages = await _repo.getPendingReplacements(s.id);
      error = e.toString();
      notifyListeners();
    }
  }

  Future<void> retryPageOcr(String pageCaptureId) async {
    final page = [
      ...pages,
      ...pendingPages,
    ].where((item) => item.pageCaptureId == pageCaptureId).firstOrNull;
    if (page == null) throw StateError('Capture is no longer available');
    _requireUncountedPage(page.pageCaptureId);
    await processPageOcr(page);
  }

  Future<void> updateCropAndRetry({
    required String pageCaptureId,
    required String rectifiedImagePath,
    required int rotationDegrees,
  }) async {
    await waitForPhysicalCounts();
    final s = session;
    if (s == null || s.isSubmitted) throw StateError('No editable session');
    final page = [
      ...pages,
      ...pendingPages,
    ].where((item) => item.pageCaptureId == pageCaptureId).firstOrNull;
    if (page == null) throw StateError('Capture is no longer available');
    final bytes = await File(rectifiedImagePath).readAsBytes();
    page.rectifiedImagePath = await _repo.persistImageBytes(
      sessionId: s.id,
      pageCaptureId: pageCaptureId,
      bytes: bytes,
      kind: 'rectified',
    );
    page.rotationDegrees = rotationDegrees;
    page.pageIdentityConfirmed = false;
    page.pageReviewConfirmed = false;
    page.ocrStatus = PageOcrStatus.pending;
    await _repo.updatePageCapture(page);
    await processPageOcr(page);
  }

  Future<void> acceptReplacement(String pageCaptureId) async {
    await waitForPhysicalCounts();
    final s = session;
    if (s == null || s.isSubmitted) throw StateError('No editable session');
    final page = pendingPages
        .where((item) => item.pageCaptureId == pageCaptureId)
        .firstOrNull;
    if (page == null) throw StateError('Replacement is no longer pending');
    for (final existing in pages.where(
      (existing) => existing.printedPage == page.printedPage,
    )) {
      _requireUncountedPage(existing.pageCaptureId);
    }
    if (page.ocrStatus != PageOcrStatus.succeeded ||
        !page.pageIdentityConfirmed ||
        page.verifiedDeliveryNoteNumber != s.deliveryNoteNumber) {
      throw StateError(
        'Verify this replacement’s delivery and page identity first',
      );
    }
    await _repo.commitReplacement(page);
    page.pendingReplacement = false;
    pendingPages = await _repo.getPendingReplacements(s.id);
    await reconsolidate(
      extraParsed: {
        if (_lastParsed[pageCaptureId] != null)
          pageCaptureId: _lastParsed[pageCaptureId]!,
      },
    );
  }

  Future<void> discardReplacement(String pageCaptureId) async {
    await waitForPhysicalCounts();
    final s = session;
    if (s == null || s.isSubmitted) return;
    final page = pendingPages
        .where((item) => item.pageCaptureId == pageCaptureId)
        .firstOrNull;
    if (page == null) return;
    await _repo.discardReplacement(page);
    _lastParsed.remove(pageCaptureId);
    pendingPages = await _repo.getPendingReplacements(s.id);
    _refreshBlockingIssues();
    notifyListeners();
  }

  Future<OcrObservation> _readUnresolvedTotalFields({
    required PageCapture capture,
    required OcrObservation observation,
    required ParsedPageResult parsed,
    required bool useSynthetic,
  }) async {
    if (useSynthetic || session?.mode != CaptureMode.camera) return observation;
    final imagePath = capture.rectifiedImagePath;
    if (imagePath == null ||
        !RegExp(r'total\W*qty', caseSensitive: false).hasMatch(
          observation.elements.map((element) => element.text).join(' '),
        )) {
      return observation;
    }
    final reads = <String, int>{};
    final evidence = <String, dynamic>{};
    for (final occurrence in parsed.occurrences.where(
      (item) => item.role == OccurrenceRole.unresolved,
    )) {
      final crop = TotalQtyFieldReader.cropFor(occurrence, observation);
      if (crop == null) continue;
      try {
        final field = await _ocr.recognizeCrop(
          imagePath: imagePath,
          pageCaptureId: capture.pageCaptureId,
          captureRevision: capture.captureRevision,
          left: crop.left,
          top: crop.top,
          right: crop.right,
          bottom: crop.bottom,
        );
        final value = TotalQtyFieldReader.uniqueQuantity(
          field,
          suspectedFusedQuantity: occurrence.suspectedQuantity,
        );
        evidence[occurrence.occurrenceId] = {
          'crop': [crop.left, crop.top, crop.right, crop.bottom],
          'lines': field.lines.map((line) => line.toJson()).toList(),
          'elements': field.elements.map((word) => word.toJson()).toList(),
          'symbols': field.symbols.map((symbol) => symbol.toJson()).toList(),
          'resolvedQuantity': value,
        };
        if (value != null) reads[occurrence.occurrenceId] = value;
      } catch (error) {
        evidence[occurrence.occurrenceId] = {
          'crop': [crop.left, crop.top, crop.right, crop.bottom],
          'error': error.toString(),
        };
      }
    }
    if (evidence.isEmpty) return observation;
    return OcrObservation(
      ocrRunId: observation.ocrRunId,
      pageCaptureId: observation.pageCaptureId,
      captureRevision: observation.captureRevision,
      engineName: observation.engineName,
      engineVersion: observation.engineVersion,
      imageWidth: observation.imageWidth,
      imageHeight: observation.imageHeight,
      elapsedMs: observation.elapsedMs,
      elements: observation.elements,
      lines: observation.lines,
      symbols: observation.symbols,
      fieldQuantityReads: reads,
      fieldEvidence: evidence,
      createdAt: observation.createdAt,
    );
  }

  /// Operator confirms or corrects printed page / declared count after OCR.
  Future<void> confirmPageIdentity({
    required String pageCaptureId,
    required String deliveryNoteNumber,
    required int printedPage,
    int? declaredPageCount,
  }) async {
    await waitForPhysicalCounts();
    final s = session;
    if (s == null || s.isSubmitted) return;
    if (printedPage < 1 ||
        printedPage > 1000 ||
        declaredPageCount != null &&
            (declaredPageCount < 1 ||
                declaredPageCount > 1000 ||
                printedPage > declaredPageCount)) {
      throw ArgumentError('Invalid printed page or total page count');
    }
    if (declaredPageCount == null &&
        s.declaredPageCount != null &&
        printedPage > s.declaredPageCount!) {
      throw ArgumentError('Printed page exceeds the declared page count');
    }
    final verifiedNote = deliveryNoteNumber.trim();
    if (verifiedNote.isEmpty ||
        verifiedNote.length > 32 ||
        !RegExp(r'^\d+$').hasMatch(verifiedNote)) {
      throw ArgumentError('Enter the delivery number printed on the source');
    }
    final page = [
      ...pages,
      ...pendingPages,
    ].firstWhere((p) => p.pageCaptureId == pageCaptureId);
    final oldPage = page.printedPage;
    final oldCount = s.declaredPageCount;
    final oldNote = s.deliveryNoteNumber;
    final oldVerifiedNote = page.verifiedDeliveryNoteNumber;
    final wasConfirmed = page.pageIdentityConfirmed;
    final wasPending = page.pendingReplacement;
    for (final other in pages.where(
      (other) =>
          other.pageCaptureId != pageCaptureId &&
          other.printedPage == printedPage,
    )) {
      _requireUncountedPage(other.pageCaptureId);
      _requireUncountedPage(pageCaptureId);
    }
    if (oldNote != verifiedNote) {
      final otherPages = pages.where(
        (p) => p.pageCaptureId != pageCaptureId && p.isActive,
      );
      if (otherPages.isNotEmpty) {
        throw StateError(
          'This page reads a different delivery number. Start a separate delivery scan to keep the pages separate.',
        );
      }
    }
    s.deliveryNoteNumber = verifiedNote;
    page.verifiedDeliveryNoteNumber = verifiedNote;
    page.printedPage = printedPage;
    if (pages.any(
      (other) =>
          other.pageCaptureId != pageCaptureId &&
          other.printedPage == printedPage,
    )) {
      page.pendingReplacement = true;
      page.pageReviewConfirmed = false;
    }
    page.pageIdentityConfirmed = true;
    if (oldNote != verifiedNote) page.pageReviewConfirmed = false;
    if (page.ocrStatus == PageOcrStatus.succeeded) page.ocrError = null;
    if (error?.contains('Verify the printed delivery number') == true) {
      error = null;
    }
    if (declaredPageCount != null) {
      s.declaredPageCount = declaredPageCount;
      page.verifiedDeclaredPageCount = declaredPageCount;
    }
    if (oldPage != printedPage) {
      await _repo.addCorrection(
        CorrectionRecord(
          id: _uuid.v4(),
          sessionId: s.id,
          field: 'printed_page',
          beforeValue: '$oldPage',
          afterValue: '$printedPage',
          reason: 'Operator verified against source page',
          createdAt: DateTime.now().toUtc(),
        ),
      );
    }
    if (oldNote != verifiedNote) {
      await _repo.addCorrection(
        CorrectionRecord(
          id: _uuid.v4(),
          sessionId: s.id,
          field: 'delivery_note_number',
          beforeValue: oldNote ?? '',
          afterValue: verifiedNote,
          reason:
              'Operator verified the printed delivery number against the source page',
          createdAt: DateTime.now().toUtc(),
        ),
      );
    }
    if (oldCount != s.declaredPageCount) {
      await _repo.addCorrection(
        CorrectionRecord(
          id: _uuid.v4(),
          sessionId: s.id,
          field: 'declared_page_count',
          beforeValue: '${oldCount ?? ''}',
          afterValue: '${s.declaredPageCount}',
          reason: 'Operator verified against source page',
          createdAt: DateTime.now().toUtc(),
        ),
      );
    }
    await _repo.updatePageCapture(page);
    if (page.ocrStatus == PageOcrStatus.succeeded && !page.pendingReplacement) {
      await _repo.activateReplacement(page);
    }
    await _repo.saveSession(s);

    // Rebuild the associated rows when metadata changes or a held page is accepted.
    if (_lastParsed.containsKey(pageCaptureId)) {
      _lastParsed[pageCaptureId] = _assignPage(
        _lastParsed[pageCaptureId]!,
        printedPage,
        deliveryNoteNumber: verifiedNote,
      );
    }
    if (page.pendingReplacement) {
      pages = await _repo.getActivePages(s.id);
      pendingPages = await _repo.getPendingReplacements(s.id);
      if (!wasPending) {
        await reconsolidate();
      } else {
        _refreshBlockingIssues();
        notifyListeners();
      }
      return;
    }
    if (oldPage != printedPage ||
        oldNote != verifiedNote ||
        oldVerifiedNote != verifiedNote ||
        !wasConfirmed ||
        oldCount != s.declaredPageCount) {
      await reconsolidate();
    } else {
      pages = await _repo.getActivePages(s.id);
      _refreshBlockingIssues();
      notifyListeners();
    }
  }

  void _refreshBlockingIssues() {
    final s = session;
    if (s == null) return;
    final cleaned = <String>[..._parsedBlockingIssues];
    for (final pending in pendingPages) {
      cleaned.add(
        'Page ${pending.printedPage}: choose whether to use the replacement capture',
      );
    }
    if (s.declaredPageCount == null) {
      cleaned.add('Total printed page count has not been confirmed');
    }
    if (s.declaredPageCount != null) {
      final pagesSet = pages.map((p) => p.printedPage).toSet();
      for (var i = 1; i <= s.declaredPageCount!; i++) {
        if (!pagesSet.contains(i)) {
          cleaned.add('Missing page $i of ${s.declaredPageCount}');
        }
      }
      if (pagesSet.length != pages.length) {
        cleaned.add('Duplicate printed page assignments');
      }
    }
    for (final p in pages) {
      if (s.declaredPageCount != null &&
          (p.printedPage < 1 || p.printedPage > s.declaredPageCount!)) {
        cleaned.add(
          'Page ${p.printedPage} is outside 1…${s.declaredPageCount}',
        );
      }
      if (!p.pageIdentityConfirmed) {
        cleaned.add(
          'Page slot ${p.printedPage}: confirm printed page identity',
        );
      }
      if (p.verifiedDeliveryNoteNumber != s.deliveryNoteNumber) {
        cleaned.add(
          'Page ${p.printedPage}: verify its printed delivery number',
        );
      }
      if (s.declaredPageCount != null &&
          ((p.verifiedDeclaredPageCount != null &&
                  p.verifiedDeclaredPageCount != s.declaredPageCount) ||
              (p.verifiedDeclaredPageCount == null &&
                  p.suggestedDeclaredPageCount != null &&
                  p.suggestedDeclaredPageCount != s.declaredPageCount))) {
        cleaned.add(
          'Page ${p.printedPage}: confirm conflicting total page count',
        );
      }
      if (p.ocrStatus != PageOcrStatus.succeeded) {
        cleaned.add('Page ${p.printedPage}: OCR is ${p.ocrStatus.name}');
      }
      if (p.observedDeliveryNoteNumber == null &&
          p.verifiedDeliveryNoteNumber == null &&
          p.ocrStatus == PageOcrStatus.succeeded) {
        cleaned.add('Page ${p.printedPage}: document identity unreadable');
      }
    }
    cleaned.addAll(
      _submission.validatePieceSummary(
        activePages: pages,
        lines: lines,
        declaredPageCount: s.declaredPageCount,
      ),
    );
    blockingIssues = cleaned.toSet().toList();
  }

  final Map<String, ParsedPageResult> _lastParsed = {};

  ParsedPageResult _assignPage(
    ParsedPageResult parsed,
    int printedPage, {
    String? deliveryNoteNumber,
  }) {
    if (parsed.printedPage == printedPage &&
        (deliveryNoteNumber == null ||
            parsed.deliveryNoteNumber == deliveryNoteNumber)) {
      return parsed;
    }
    return ParsedPageResult(
      pageCaptureId: parsed.pageCaptureId,
      printedPage: printedPage,
      deliveryNoteNumber: deliveryNoteNumber ?? parsed.deliveryNoteNumber,
      pieceCount: parsed.pieceCount,
      declaredPageCount: parsed.declaredPageCount,
      printedPageDetected: parsed.printedPageDetected,
      pageRole: parsed.pageRole,
      issues: parsed.issues,
      occurrences: parsed.occurrences
          .map(
            (o) => ParsedOccurrence(
              occurrenceId: o.occurrenceId,
              pageCaptureId: o.pageCaptureId,
              sourcePage: printedPage,
              articleNumber: o.articleNumber,
              role: o.role,
              documentQuantity: o.documentQuantity,
              unit: o.unit,
              productContext: o.productContext,
              issues: o.issues,
              blockTop: o.blockTop,
              blockBottom: o.blockBottom,
              rowCenterY: o.rowCenterY,
              quantityColumnLeft: o.quantityColumnLeft,
              suspectedQuantity: o.suspectedQuantity,
            ),
          )
          .toList(),
    );
  }

  Future<void> reconsolidate({
    Map<String, ParsedPageResult>? extraParsed,
  }) async {
    await waitForPhysicalCounts();
    final s = session;
    if (s == null) return;
    if (extraParsed != null) _lastParsed.addAll(extraParsed);

    pages = await _repo.getActivePages(s.id);
    final previous = {
      for (final l in await _repo.getLines(s.id)) l.occurrenceId: l,
    };
    final parsedPages = <ParsedPageResult>[];
    for (final page in pages) {
      var cached = _lastParsed[page.pageCaptureId];
      if (cached == null && page.ocrStatus == PageOcrStatus.succeeded) {
        final observation = await _repo.getLatestOcrObservation(page);
        if (observation != null) {
          cached = _assignPage(
            _parser.parse(
              observation: observation,
              printedPageHint: page.printedPage,
            ),
            page.printedPage,
          );
          _lastParsed[page.pageCaptureId] = cached;
        }
      }
      if (cached != null &&
          page.pageIdentityConfirmed &&
          page.verifiedDeliveryNoteNumber != null &&
          cached.deliveryNoteNumber != null) {
        parsedPages.add(
          _assignPage(
            applySavedTotalCorrections(cached, previous.values),
            page.printedPage,
            deliveryNoteNumber: page.verifiedDeliveryNoteNumber,
          ),
        );
      }
    }

    // Preserve existing lines' physical edits when rederiving from same occurrence ids
    final doc = _consolidator.consolidate(sessionId: s.id, pages: parsedPages);
    if (doc.deliveryNoteNumber != null) {
      s.deliveryNoteNumber ??= doc.deliveryNoteNumber;
    }
    if (doc.declaredPageCount != null) {
      s.declaredPageCount ??= doc.declaredPageCount;
    }

    final mergedLines = <DocumentLine>[];
    final matchedPreviousIds = <String>{};
    for (final line in doc.lines) {
      final prev = previous[line.occurrenceId];
      // Match older drafts created before occurrence IDs became stable.
      final byKey = previous.values.cast<DocumentLine?>().firstWhere(
        (p) =>
            p != null &&
            !matchedPreviousIds.contains(p.occurrenceId) &&
            p.sourcePage == line.sourcePage &&
            (p.rawOcrArticle ?? p.articleNumber) == line.articleNumber &&
            p.pageCaptureId == line.pageCaptureId,
        orElse: () => null,
      );
      final keep = prev ?? byKey;
      if (keep != null) {
        matchedPreviousIds.add(keep.occurrenceId);
        final sameObservation =
            keep.rawOcrArticle == line.rawOcrArticle &&
            keep.rawOcrQuantity == line.rawOcrQuantity;
        final repairedTotalQty =
            keep.rawOcrArticle != null && keep.rawOcrQuantity == null;
        if (repairedTotalQty) {
          line.articleNumber = keep.articleNumber;
          line.documentQuantity = keep.documentQuantity;
          line.rawOcrArticle = keep.rawOcrArticle;
          line.rawOcrQuantity = null;
          if (!keep.hasPhysicalCount) {
            line.physicalQuantity = keep.documentQuantity;
          }
        }
        if ((keep.rawOcrArticle != null &&
                keep.articleNumber != keep.rawOcrArticle) ||
            (keep.rawOcrQuantity != null &&
                keep.documentQuantity != keep.rawOcrQuantity)) {
          line.articleNumber = keep.articleNumber;
          line.documentQuantity = keep.documentQuantity;
          if (!keep.hasPhysicalCount) {
            line.physicalQuantity = line.documentQuantity;
          }
        }
        if (keep.hasPhysicalCount) {
          line.physicalQuantity = keep.physicalQuantity;
          line.physicalOrigin = keep.physicalOrigin;
          line.physicalQuantityConfirmed = keep.physicalQuantityConfirmed;
          line.physicalCountState = keep.physicalCountState;
          line.countedArticleNumber = keep.countedArticleNumber;
          line.varianceReason = keep.varianceReason;
          if (line.articleNumber != keep.articleNumber ||
              line.documentQuantity != keep.documentQuantity) {
            line.physicalCountState = PhysicalCountState.recheck;
            line.physicalQuantityConfirmed = false;
            line.varianceReason = null;
          }
        }
        line.reviewConfirmed = sameObservation && keep.reviewConfirmed;
      }
      mergedLines.add(line);
    }

    final activeCaptureIds = pages.map((p) => p.pageCaptureId).toSet();
    for (final oldLine in previous.values) {
      final unresolvedSource =
          _lastParsed[oldLine.pageCaptureId]?.occurrences.any(
            (occurrence) =>
                occurrence.occurrenceId == oldLine.occurrenceId &&
                isSourceCorrectableTotalQty(occurrence),
          ) ??
          false;
      if (!matchedPreviousIds.contains(oldLine.occurrenceId) &&
          (oldLine.rawOcrArticle == null || unresolvedSource) &&
          activeCaptureIds.contains(oldLine.pageCaptureId)) {
        // Preserve manual additions and source-verified Total Qty repairs.
        mergedLines.add(oldLine);
      }
    }

    final priorDocumentTotal = previous.values.fold<int>(
      0,
      (sum, line) => sum + line.documentQuantity,
    );
    final nextDocumentTotal = mergedLines.fold<int>(
      0,
      (sum, line) => sum + line.documentQuantity,
    );
    final changedPages = <PageCapture>[];
    if (priorDocumentTotal != nextDocumentTotal) {
      final pageOne = pages.where((p) => p.printedPage == 1).firstOrNull;
      if (pageOne?.pieceCountVarianceReviewed == true) {
        pageOne!.pieceCountVarianceReviewed = false;
        changedPages.add(pageOne);
      }
    }

    s.formRevision += 1;
    s.reviewConfirmedRevision = null;
    s.status = ScanSessionStatus.reviewing;
    await _repo.commitConsolidation(
      session: s,
      lines: mergedLines,
      contexts: doc.contexts,
      changedPages: changedPages,
    );

    lines = mergedLines;
    contexts = doc.contexts;
    _parsedBlockingIssues = [...doc.blockingIssues];
    _refreshBlockingIssues();
    notifyListeners();
  }

  Future<void> loadFixtureSession() async {
    final created = await startSession(mode: CaptureMode.illustrativeFixture);
    // Seed with synthetic pages 1-4 without real images
    for (var page = 1; page <= 4; page++) {
      final capture = await _repo.addPageCapture(
        sessionId: created.id,
        printedPage: page,
      );
      await processPageOcr(capture, useSynthetic: true);
    }
    await loadSession(created.id);
  }

  Future<void> _changePhysicalCount({
    required String occurrenceId,
    required String action,
    required void Function(DocumentLine) change,
    String? auditReason,
    String? eventId,
  }) {
    final requestedSessionId = session?.id;
    _pendingCountWrites += 1;
    notifyListeners();
    final operation = _countWrites
        .then((_) async {
          if (eventId != null &&
              await _repo.hasPhysicalAdjustment(
                eventId,
                sessionId: requestedSessionId ?? '',
                occurrenceId: occurrenceId,
              )) {
            return;
          }
          final current = session;
          if (current == null ||
              current.isSubmitted ||
              current.id != requestedSessionId) {
            throw StateError('No editable receiving session');
          }
          if (!sourceReviewReady) {
            throw StateError(
              'Complete the DN source checks before physical verification',
            );
          }
          final index = lines.indexWhere(
            (line) => line.occurrenceId == occurrenceId,
          );
          if (index < 0) {
            throw StateError('The receiving line is no longer available');
          }
          final before = lines[index];
          final changed = before.copy();
          change(changed);
          if (!PpgValidation.isValidQuantity(changed.physicalQuantity)) {
            throw ArgumentError(
              'Physical counts must be whole numbers of zero or more',
            );
          }
          changed.reviewConfirmed = false;
          final updatedSession = ScanSession(
            id: current.id,
            status: current.status,
            formRevision: current.formRevision + 1,
            createdAt: current.createdAt,
            updatedAt: current.updatedAt,
            deliveryNoteNumber: current.deliveryNoteNumber,
            declaredPageCount: current.declaredPageCount,
            operatorEmail: current.operatorEmail,
            mode: current.mode,
            reviewConfirmedRevision: null,
          );
          await _repo.savePhysicalCount(
            session: updatedSession,
            line: changed,
            adjustment: PhysicalAdjustment(
              id: eventId ?? _uuid.v4(),
              sessionId: current.id,
              occurrenceId: occurrenceId,
              beforeQuantity:
                  action == 'scanArticle' && !before.hasPhysicalCount
                  ? 0
                  : before.physicalQuantity,
              afterQuantity: changed.physicalQuantity,
              action: action,
              reason:
                  auditReason ??
                  changed.varianceReason ??
                  'Physical count: $action',
              createdAt: DateTime.now().toUtc(),
            ),
          );
          lines[index] = changed;
          session = updatedSession;
        })
        .whenComplete(() {
          _pendingCountWrites -= 1;
          notifyListeners();
        });
    // A failed write is reported to its caller without poisoning later edits.
    _countWrites = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return operation;
  }

  void _markCounting(DocumentLine line) {
    line.physicalCountState = PhysicalCountState.counting;
    line.physicalQuantityConfirmed = false;
    line.physicalOrigin = PhysicalQuantityOrigin.userEntered;
    line.countedArticleNumber = line.articleNumber;
    line.varianceReason = null;
  }

  Future<void> addScannedCan({
    required String articleNumber,
    required String occurrenceId,
    required String eventId,
    required String expectedSessionId,
    required int expectedRevision,
  }) => _changePhysicalCount(
    occurrenceId: occurrenceId,
    action: 'scanArticle',
    eventId: eventId,
    auditReason: jsonEncode({
      'article_number': articleNumber,
      'method': 'live_camera_article',
      'confirmed_frames': 3,
      'delivery_note_number': session?.deliveryNoteNumber,
      'form_revision': expectedRevision,
    }),
    change: (line) {
      if (eventId.trim().isEmpty ||
          session?.id != expectedSessionId ||
          session?.formRevision != expectedRevision) {
        throw StateError('The delivery changed. Scan the can again.');
      }
      if (line.articleNumber != articleNumber ||
          !RegExp(r'^\d+$').hasMatch(articleNumber)) {
        throw StateError('This article does not match the selected DN row.');
      }
      if (line.unit.toUpperCase() != 'PC') {
        throw StateError('This DN row is not counted in cans / PC.');
      }
      if (line.hasPhysicalCount) _requireRunningCount(line);
      line.physicalQuantity =
          (line.hasPhysicalCount ? line.physicalQuantity : 0) + 1;
      _markCounting(line);
    },
  );

  void _requireRunningCount(DocumentLine line) {
    if (!line.hasPhysicalCount) {
      throw StateError('Start a physical count first');
    }
    if (line.isPhysicalVerified) {
      throw StateError('Reopen this verified count first');
    }
    if (line.needsArticleReconciliation) {
      throw StateError('Reconcile the count with the corrected article first');
    }
  }

  Future<void> startPhysicalCount(String occurrenceId) => _changePhysicalCount(
    occurrenceId: occurrenceId,
    action: 'start',
    change: (line) {
      if (line.hasPhysicalCount) {
        throw StateError('A physical count already exists');
      }
      line.physicalQuantity = 0;
      _markCounting(line);
    },
  );

  Future<void> adjustPhysicalCount({
    required String occurrenceId,
    required int delta,
  }) => _changePhysicalCount(
    occurrenceId: occurrenceId,
    action: delta < 0 ? 'decrement' : 'increment',
    change: (line) {
      if (delta != 1 && delta != -1) throw ArgumentError('Use +1 or -1');
      _requireRunningCount(line);
      line.physicalQuantity += delta;
      _markCounting(line);
    },
  );

  Future<void> addPhysicalBatch({
    required String occurrenceId,
    required int quantity,
  }) => _changePhysicalCount(
    occurrenceId: occurrenceId,
    action: 'addBatch',
    change: (line) {
      if (quantity <= 0) throw ArgumentError('Enter a positive batch quantity');
      _requireRunningCount(line);
      line.physicalQuantity += quantity;
      _markCounting(line);
    },
  );

  Future<void> setCountedTotal({
    required String occurrenceId,
    required int quantity,
  }) => _changePhysicalCount(
    occurrenceId: occurrenceId,
    action: 'setTotal',
    change: (line) {
      if (line.hasPhysicalCount) _requireRunningCount(line);
      line.physicalQuantity = quantity;
      _markCounting(line);
    },
  );

  Future<void> confirmPhysicalMatchesDocument(String occurrenceId) =>
      _changePhysicalCount(
        occurrenceId: occurrenceId,
        action: 'matchDocument',
        change: (line) {
          if (line.hasPhysicalCount) {
            throw StateError('Finish or edit the existing count');
          }
          line.physicalQuantity = line.documentQuantity;
          line.physicalOrigin = PhysicalQuantityOrigin.operatorConfirmed;
          line.physicalCountState = PhysicalCountState.verified;
          line.physicalQuantityConfirmed = true;
          line.countedArticleNumber = line.articleNumber;
          line.varianceReason = null;
        },
      );

  Future<void> finishPhysicalCount({
    required String occurrenceId,
    String reason = '',
    int? expectedQuantity,
  }) => _changePhysicalCount(
    occurrenceId: occurrenceId,
    action: 'finish',
    auditReason: reason.trim().isEmpty
        ? 'Operator finished physical verification'
        : reason.trim(),
    change: (line) {
      _requireRunningCount(line);
      if (expectedQuantity != null &&
          expectedQuantity != line.physicalQuantity) {
        throw StateError('The count changed; review it before finishing');
      }
      if (line.variance != 0 && reason.trim().isEmpty) {
        throw ArgumentError('Variance reason is required');
      }
      line.physicalCountState = PhysicalCountState.verified;
      line.physicalQuantityConfirmed = true;
      line.varianceReason = line.variance == 0 ? null : reason.trim();
    },
  );

  Future<void> reopenPhysicalCount(String occurrenceId) => _changePhysicalCount(
    occurrenceId: occurrenceId,
    action: 'reopen',
    change: (line) {
      if (!line.isPhysicalVerified) {
        throw StateError('This count is not verified');
      }
      _markCounting(line);
    },
  );

  Future<void> reconcilePhysicalCount({
    required String occurrenceId,
    required bool restart,
  }) => _changePhysicalCount(
    occurrenceId: occurrenceId,
    action: restart ? 'restartForCorrectedArticle' : 'confirmCorrectedArticle',
    change: (line) {
      if (!line.needsArticleReconciliation) {
        throw StateError('Article reconciliation is not needed');
      }
      if (restart) line.physicalQuantity = 0;
      _markCounting(line);
    },
  );

  int? get printedPieceCount {
    final pageOne = pages.where((p) => p.printedPage == 1).firstOrNull;
    return pageOne?.effectivePieceCount;
  }

  int? get rawPrintedPieceCount {
    final pageOne = pages.where((p) => p.printedPage == 1).firstOrNull;
    return pageOne?.observedPieceCount;
  }

  int get documentQuantityTotal =>
      lines.fold<int>(0, (sum, line) => sum + line.documentQuantity);

  int get physicalQuantityTotal =>
      lines.fold<int>(0, (sum, line) => sum + line.physicalQuantity);

  Future<void> correctPrintedPieceCount({
    required int pieceCount,
    required String reason,
  }) async {
    await waitForPhysicalCounts();
    final s = session;
    if (s == null || s.isSubmitted) return;
    if (!PpgValidation.isValidQuantity(pieceCount) || reason.trim().isEmpty) {
      throw ArgumentError(
        'Enter the printed Piece count and a correction reason',
      );
    }
    final pageOne = pages.where((p) => p.printedPage == 1).firstOrNull;
    if (pageOne == null || pageOne.ocrStatus != PageOcrStatus.succeeded) {
      throw StateError('Capture page 1 before correcting its Piece count');
    }
    await _repo.addCorrection(
      CorrectionRecord(
        id: _uuid.v4(),
        sessionId: s.id,
        field: 'printed_piece_count',
        beforeValue: '${pageOne.effectivePieceCount ?? ''}',
        afterValue: '$pieceCount',
        reason: reason.trim(),
        createdAt: DateTime.now().toUtc(),
      ),
    );
    pageOne.verifiedPieceCount = pieceCount;
    pageOne.pageReviewConfirmed = false;
    pageOne.pieceCountVarianceReviewed = false;
    await _repo.updatePageCapture(pageOne);
    s.formRevision += 1;
    s.reviewConfirmedRevision = null;
    await _repo.saveSession(s);
    _refreshBlockingIssues();
    notifyListeners();
  }

  bool get pieceCountSummaryMismatch =>
      _submission.hasPieceCountSummaryMismatch(
        activePages: pages,
        lines: lines,
        declaredPageCount: session?.declaredPageCount,
      );

  Future<void> confirmPieceCountDiscrepancy({required bool reviewed}) async {
    await waitForPhysicalCounts();
    final s = session;
    if (s == null || s.isSubmitted) return;
    if (!pieceCountSummaryMismatch) {
      throw StateError('There is no complete-document Piece count mismatch');
    }
    final pageOne = pages.firstWhere((p) => p.printedPage == 1);
    if (pageOne.pieceCountVarianceReviewed == reviewed) return;
    pageOne.pieceCountVarianceReviewed = reviewed;
    await _repo.updatePageCapture(pageOne);
    await _repo.addCorrection(
      CorrectionRecord(
        id: _uuid.v4(),
        sessionId: s.id,
        field: 'piece_count_discrepancy_review',
        beforeValue: reviewed ? 'unreviewed' : 'reviewed',
        afterValue: reviewed ? 'reviewed' : 'unreviewed',
        reason: reviewed
            ? 'Operator reviewed the printed summary mismatch; item quantities were left unchanged'
            : 'Operator cleared the summary mismatch review acknowledgment',
        createdAt: DateTime.now().toUtc(),
      ),
    );
    s.formRevision += 1;
    s.reviewConfirmedRevision = null;
    await _repo.saveSession(s);
    _refreshBlockingIssues();
    notifyListeners();
  }

  Future<void> correctScanResult({
    required String occurrenceId,
    required String articleNumber,
    required int documentQuantity,
    required String reason,
  }) async {
    await waitForPhysicalCounts();
    final s = session;
    if (s == null || s.isSubmitted) return;
    if (!PpgValidation.isValidArticle(articleNumber)) {
      throw ArgumentError('Invalid article number');
    }
    if (!PpgValidation.isValidQuantity(documentQuantity) ||
        reason.trim().isEmpty) {
      throw ArgumentError(
        'Enter a valid document quantity and correction reason',
      );
    }
    final line = lines.firstWhere((l) => l.occurrenceId == occurrenceId);
    await _repo.addCorrection(
      CorrectionRecord(
        id: _uuid.v4(),
        sessionId: s.id,
        occurrenceId: occurrenceId,
        field: 'article_and_document_qty',
        beforeValue: '${line.articleNumber}:${line.documentQuantity}',
        afterValue: '$articleNumber:$documentQuantity',
        reason: reason,
        createdAt: DateTime.now().toUtc(),
      ),
    );
    final valuesChanged =
        line.articleNumber != articleNumber ||
        line.documentQuantity != documentQuantity;
    line.articleNumber = articleNumber;
    line.documentQuantity = documentQuantity;
    if (!line.hasPhysicalCount) {
      line.physicalQuantity = documentQuantity;
      line.varianceReason = null;
    } else if (valuesChanged) {
      line.physicalCountState = PhysicalCountState.recheck;
      line.physicalQuantityConfirmed = false;
      line.varianceReason = null;
    }
    line.reviewConfirmed = false;
    final sourcePage = pages.firstWhere(
      (p) => p.pageCaptureId == line.pageCaptureId,
    );
    sourcePage.pageReviewConfirmed = false;
    await _repo.updatePageCapture(sourcePage);
    final pageOne = pages.where((p) => p.printedPage == 1).firstOrNull;
    if (pageOne != null && pageOne.pieceCountVarianceReviewed) {
      pageOne.pieceCountVarianceReviewed = false;
      await _repo.updatePageCapture(pageOne);
    }
    await _repo.saveLine(line);
    s.formRevision += 1;
    s.reviewConfirmedRevision = null;
    await _repo.saveSession(s);
    _refreshBlockingIssues();
    notifyListeners();
  }

  List<ParsedOccurrence> parsedOccurrencesForPage(String pageCaptureId) {
    final parsed = _lastParsed[pageCaptureId];
    if (parsed == null) return const [];
    return applySavedTotalCorrections(parsed, lines).occurrences;
  }

  Future<void> correctUnresolvedOccurrence({
    required String pageCaptureId,
    required String occurrenceId,
    required String articleNumber,
    required int documentQuantity,
    required String reason,
  }) async {
    await waitForPhysicalCounts();
    final s = session;
    if (s == null || s.isSubmitted) throw StateError('No editable session');
    if (!PpgValidation.isValidArticle(articleNumber) ||
        !PpgValidation.isValidQuantity(documentQuantity) ||
        reason.trim().isEmpty) {
      throw ArgumentError(
        'Enter the printed article, Total Qty, and correction reason',
      );
    }
    final page = pages.firstWhere((p) => p.pageCaptureId == pageCaptureId);
    final occurrence = _lastParsed[pageCaptureId]?.occurrences
        .where((o) => o.occurrenceId == occurrenceId)
        .firstOrNull;
    if (occurrence == null || !isSourceCorrectableTotalQty(occurrence)) {
      throw StateError('This occurrence has no Total Qty to verify');
    }
    final existing = lines
        .where((l) => l.occurrenceId == occurrenceId)
        .firstOrNull;
    final correctedLine =
        existing ??
        DocumentLine(
          occurrenceId: occurrenceId,
          sessionId: s.id,
          articleNumber: articleNumber.trim(),
          documentQuantity: documentQuantity,
          physicalQuantity: documentQuantity,
          physicalOrigin: PhysicalQuantityOrigin.defaultedFromDocument,
          sourcePage: page.printedPage,
          pageCaptureId: pageCaptureId,
          productContext: occurrence.productContext,
          rawOcrArticle: occurrence.articleNumber,
          rawOcrQuantity: null,
        );
    if (existing != null) {
      existing.articleNumber = articleNumber.trim();
      existing.documentQuantity = documentQuantity;
      if (!existing.hasPhysicalCount) {
        existing.physicalQuantity = documentQuantity;
      } else {
        existing.physicalCountState = PhysicalCountState.recheck;
        existing.physicalQuantityConfirmed = false;
        existing.varianceReason = null;
      }
    }
    page.pageReviewConfirmed = false;
    s.formRevision += 1;
    s.reviewConfirmedRevision = null;
    await _repo.saveSourceCorrection(
      session: s,
      page: page,
      line: correctedLine,
      correction: CorrectionRecord(
        id: _uuid.v4(),
        sessionId: s.id,
        occurrenceId: occurrenceId,
        field: 'article_and_document_qty',
        beforeValue: '${occurrence.articleNumber}:unresolved',
        afterValue: '${articleNumber.trim()}:$documentQuantity',
        reason: reason.trim(),
        createdAt: DateTime.now().toUtc(),
      ),
    );
    await reconsolidate();
  }

  Future<DocumentLine> addManualOccurrence({
    required String pageCaptureId,
    required String articleNumber,
    required int documentQuantity,
    required String sourceContext,
  }) async {
    await waitForPhysicalCounts();
    final s = session;
    if (s == null || s.isSubmitted) throw StateError('No editable session');
    if (!PpgValidation.isValidArticle(articleNumber) ||
        !PpgValidation.isValidQuantity(documentQuantity) ||
        sourceContext.trim().isEmpty) {
      throw ArgumentError(
        'Enter a valid identifier, quantity, and source description',
      );
    }
    final page = pages.firstWhere((p) => p.pageCaptureId == pageCaptureId);
    final line = DocumentLine(
      occurrenceId: _uuid.v4(),
      sessionId: s.id,
      articleNumber: articleNumber.trim(),
      documentQuantity: documentQuantity,
      physicalQuantity: documentQuantity,
      physicalOrigin: PhysicalQuantityOrigin.defaultedFromDocument,
      physicalQuantityConfirmed: false,
      sourcePage: page.printedPage,
      pageCaptureId: page.pageCaptureId,
      productContext: sourceContext.trim(),
      rawOcrArticle: null,
      rawOcrQuantity: null,
    );
    await _repo.insertLine(line);
    await _repo.addCorrection(
      CorrectionRecord(
        id: _uuid.v4(),
        sessionId: s.id,
        occurrenceId: line.occurrenceId,
        field: 'manual_occurrence_created',
        beforeValue: '',
        afterValue: '${line.articleNumber}:${line.documentQuantity}',
        reason: sourceContext.trim(),
        createdAt: DateTime.now().toUtc(),
      ),
    );
    page.pageReviewConfirmed = false;
    await _repo.updatePageCapture(page);
    final pageOne = pages.where((p) => p.printedPage == 1).firstOrNull;
    if (pageOne != null && pageOne.pieceCountVarianceReviewed) {
      pageOne.pieceCountVarianceReviewed = false;
      await _repo.updatePageCapture(pageOne);
    }
    s.formRevision += 1;
    s.reviewConfirmedRevision = null;
    await _repo.saveSession(s);
    await reconsolidate();
    return lines.firstWhere((l) => l.occurrenceId == line.occurrenceId);
  }

  Future<void> confirmPageReview({
    required String pageCaptureId,
    required bool coverageConfirmed,
  }) async {
    await waitForPhysicalCounts();
    final s = session;
    if (s == null || s.isSubmitted) return;
    final page = pages.firstWhere((p) => p.pageCaptureId == pageCaptureId);
    final rawParsed = _lastParsed[pageCaptureId];
    final parsed = rawParsed == null
        ? null
        : applySavedTotalCorrections(rawParsed, lines);
    if (page.sourceImagePath == null ||
        !File(page.sourceImagePath!).existsSync()) {
      throw StateError('The saved source page is unavailable for verification');
    }
    if (!coverageConfirmed) {
      throw StateError(
        'Confirm that the full page was checked for occurrences',
      );
    }
    if (page.ocrStatus != PageOcrStatus.succeeded ||
        !page.pageIdentityConfirmed ||
        page.verifiedDeliveryNoteNumber != s.deliveryNoteNumber) {
      throw StateError(
        'Verify the page and delivery identity before confirming',
      );
    }
    if (parsed == null ||
        parsed.issues.isNotEmpty ||
        parsed.occurrences.any((o) => o.role == OccurrenceRole.unresolved)) {
      throw StateError('Resolve unreadable or ambiguous page fields first');
    }
    page.pageReviewConfirmed = true;
    await _repo.updatePageCapture(page);
    await _repo.addCorrection(
      CorrectionRecord(
        id: _uuid.v4(),
        sessionId: s.id,
        field: 'page_review_and_coverage',
        beforeValue: 'unconfirmed',
        afterValue: 'confirmed',
        reason: 'Operator reviewed page source and occurrence coverage',
        createdAt: DateTime.now().toUtc(),
      ),
    );
    s.formRevision += 1;
    s.reviewConfirmedRevision = null;
    s.status = ScanSessionStatus.reviewing;
    await _repo.saveSession(s);
    await reconsolidate();
  }

  Future<void> confirmReview() async {
    await waitForPhysicalCounts();
    if (!readyForFinalReview) {
      throw StateError(
        'Complete DN checks and verify every physical count first',
      );
    }
    final s = session;
    if (s == null || s.isSubmitted) return;
    for (final line in lines) {
      line.reviewConfirmed = true;
      await _repo.saveLine(line);
    }
    s.reviewConfirmedRevision = s.formRevision;
    await _repo.saveSession(s);
    notifyListeners();
  }

  Future<SubmittedForm> submit() async {
    await waitForPhysicalCounts();
    final s = session;
    if (s == null) throw StateError('No session');

    final existing = await _repo.getSubmissionForSession(s.id);
    if (existing != null) {
      submission = existing;
      notifyListeners();
      return existing;
    }

    final activePages = await _repo.getActivePages(s.id);
    final errors = _submission.validateForSubmit(
      session: s,
      lines: lines,
      activePages: activePages,
      blockingIssues: blockingIssues,
      rejectIllustrativeFixture: false,
    );
    // Allow illustrative fixture in developer path but label it.
    final filtered = errors
        .where((e) => !e.contains('Illustrative fixture'))
        .toList();
    if (s.mode == CaptureMode.camera) {
      final cameraErrors = _submission.validateForSubmit(
        session: s,
        lines: lines,
        activePages: activePages,
        blockingIssues: blockingIssues,
        rejectIllustrativeFixture: true,
      );
      if (cameraErrors.isNotEmpty) {
        throw StateError(cameraErrors.join('\n'));
      }
    } else if (filtered.isNotEmpty) {
      throw StateError(filtered.join('\n'));
    }

    final submissionId = _uuid.v4();
    final snapshot = _submission.buildSnapshot(
      submissionId: submissionId,
      session: s,
      lines: lines,
      contexts: contexts,
      activePages: activePages,
      submittedAt: DateTime.now().toUtc(),
    );
    final encoded = _submission.encode(snapshot);
    final saved = await _repo.submitLocal(
      sessionId: s.id,
      submissionId: submissionId,
      snapshotJson: encoded,
    );
    await loadSession(s.id);
    return saved;
  }

  Map<String, dynamic>? get submissionMap {
    final sub = submission;
    if (sub == null) return null;
    return jsonDecode(sub.snapshotJson) as Map<String, dynamic>;
  }
}
