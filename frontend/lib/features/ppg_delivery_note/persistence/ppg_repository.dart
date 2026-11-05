import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../domain/models.dart';

/// Vessel that delivery notes saved before vessels existed belong to.
const ppgDefaultVesselId = 'vessel-1';

class PpgRepository {
  /// [databaseFactory], [databasePath] and [documentsDirectory] are for tests;
  /// the app uses the platform database in its documents folder.
  PpgRepository({
    Uuid? uuid,
    DatabaseFactory? databaseFactory,
    String? databasePath,
    Directory? documentsDirectory,
  }) : _uuid = uuid ?? const Uuid(),
       _databaseFactory = databaseFactory,
       _databasePath = databasePath,
       _documentsDirectory = documentsDirectory;

  final Uuid _uuid;
  final DatabaseFactory? _databaseFactory;
  final String? _databasePath;
  final Directory? _documentsDirectory;
  Database? _db;
  Directory? _evidenceDir;

  Future<void> init() async {
    if (_db != null) return;
    final docs =
        _documentsDirectory ?? await getApplicationDocumentsDirectory();
    _evidenceDir = Directory(p.join(docs.path, 'ppg_evidence'));
    await _evidenceDir!.create(recursive: true);
    final dbPath = _databasePath ?? p.join(docs.path, 'ppg_delivery_note.db');
    _db = await (_databaseFactory ?? databaseFactory).openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 11,
        onCreate: (db, version) async {
          await _createV1(db);
          await _upgradeToV2(db);
          await _upgradeToV3(db);
          await _upgradeToV4(db);
          await _upgradeToV5(db);
          await _upgradeToV6(db);
          await _upgradeToV7(db);
          await _upgradeToV8(db);
          await _upgradeToV9(db);
          await _upgradeToV10(db);
          await _upgradeToV11(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) await _upgradeToV2(db);
          if (oldVersion < 3) await _upgradeToV3(db);
          if (oldVersion < 4) await _upgradeToV4(db);
          if (oldVersion < 5) await _upgradeToV5(db);
          if (oldVersion < 6) await _upgradeToV6(db);
          if (oldVersion < 7) await _upgradeToV7(db);
          if (oldVersion < 8) await _upgradeToV8(db);
          if (oldVersion < 9) await _upgradeToV9(db);
          if (oldVersion < 10) await _upgradeToV10(db);
          if (oldVersion < 11) await _upgradeToV11(db);
        },
      ),
    );
  }

  Future<void> _createV1(Database db) async {
    await db.execute('''
CREATE TABLE scan_sessions (
  id TEXT PRIMARY KEY,
  status TEXT NOT NULL,
  delivery_note_number TEXT,
  declared_page_count INTEGER,
  form_revision INTEGER NOT NULL,
  review_confirmed_revision INTEGER,
  operator_email TEXT,
  mode TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)''');
    await db.execute('''
CREATE TABLE page_captures (
  page_capture_id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL,
  printed_page INTEGER NOT NULL,
  capture_revision INTEGER NOT NULL,
  is_active INTEGER NOT NULL,
  source_image_path TEXT,
  rectified_image_path TEXT,
  ocr_status TEXT NOT NULL,
  ocr_error TEXT,
  created_at TEXT NOT NULL
)''');
    await db.execute('''
CREATE TABLE document_lines (
  occurrence_id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL,
  article_number TEXT NOT NULL,
  document_quantity INTEGER NOT NULL,
  physical_quantity INTEGER NOT NULL,
  physical_origin TEXT NOT NULL,
  unit TEXT NOT NULL,
  source_page INTEGER NOT NULL,
  page_capture_id TEXT NOT NULL,
  product_context TEXT,
  variance_reason TEXT,
  review_confirmed INTEGER NOT NULL,
  raw_ocr_article TEXT,
  raw_ocr_quantity INTEGER
)''');
    await db.execute('''
CREATE TABLE document_contexts (
  context_id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL,
  article_number TEXT NOT NULL,
  heading TEXT,
  source_page INTEGER NOT NULL,
  page_capture_id TEXT NOT NULL
)''');
    await db.execute('''
CREATE TABLE corrections (
  id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL,
  occurrence_id TEXT,
  field TEXT NOT NULL,
  before_value TEXT NOT NULL,
  after_value TEXT NOT NULL,
  reason TEXT NOT NULL,
  created_at TEXT NOT NULL
)''');
    await db.execute('''
CREATE TABLE physical_adjustments (
  id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL,
  occurrence_id TEXT NOT NULL,
  before_quantity INTEGER NOT NULL,
  after_quantity INTEGER NOT NULL,
  reason TEXT NOT NULL,
  created_at TEXT NOT NULL
)''');
    await db.execute('''
CREATE TABLE submitted_forms (
  submission_id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL UNIQUE,
  snapshot_json TEXT NOT NULL,
  submitted_at TEXT NOT NULL
)''');
    await db.execute('''
CREATE TABLE ocr_observations (
  ocr_run_id TEXT PRIMARY KEY,
  page_capture_id TEXT NOT NULL,
  capture_revision INTEGER NOT NULL,
  payload_json TEXT NOT NULL,
  created_at TEXT NOT NULL
)''');
  }

  Future<void> _upgradeToV2(Database db) async {
    Future<void> addCol(String sql) async {
      try {
        await db.execute(sql);
      } catch (_) {}
    }

    await addCol(
      'ALTER TABLE page_captures ADD COLUMN suggested_printed_page INTEGER',
    );
    await addCol(
      'ALTER TABLE page_captures ADD COLUMN suggested_declared_page_count INTEGER',
    );
    await addCol(
      "ALTER TABLE page_captures ADD COLUMN page_identity_confirmed INTEGER NOT NULL DEFAULT 0",
    );
    await addCol(
      'ALTER TABLE page_captures ADD COLUMN rotation_degrees INTEGER NOT NULL DEFAULT 0',
    );
  }

  Future<void> _upgradeToV3(Database db) async {
    await db.execute(
      'ALTER TABLE page_captures ADD COLUMN verified_declared_page_count INTEGER',
    );
    await db.execute(
      'ALTER TABLE page_captures ADD COLUMN observed_delivery_note_number TEXT',
    );
  }

  Future<void> _upgradeToV4(Database db) async {
    await db.execute(
      'ALTER TABLE page_captures ADD COLUMN observed_piece_count INTEGER',
    );
    await db.execute(
      'ALTER TABLE page_captures ADD COLUMN verified_piece_count INTEGER',
    );
  }

  Future<void> _upgradeToV5(Database db) async {
    await db.execute(
      'ALTER TABLE page_captures ADD COLUMN page_review_confirmed INTEGER NOT NULL DEFAULT 0',
    );
    await db.execute(
      'ALTER TABLE document_lines ADD COLUMN physical_quantity_confirmed INTEGER NOT NULL DEFAULT 0',
    );
  }

  Future<void> _upgradeToV6(Database db) async {
    await db.execute(
      'ALTER TABLE page_captures ADD COLUMN verified_delivery_note_number TEXT',
    );
  }

  Future<void> _upgradeToV7(Database db) async {
    await db.execute(
      'ALTER TABLE page_captures ADD COLUMN piece_count_variance_reviewed INTEGER NOT NULL DEFAULT 0',
    );
  }

  Future<void> _upgradeToV8(Database db) async {
    await db.execute(
      'ALTER TABLE page_captures ADD COLUMN pending_replacement INTEGER NOT NULL DEFAULT 0',
    );
  }

  Future<void> _upgradeToV9(Database db) async {
    await db.execute(
      "ALTER TABLE document_lines ADD COLUMN physical_count_state TEXT NOT NULL DEFAULT 'notChecked'",
    );
    await db.execute(
      'ALTER TABLE document_lines ADD COLUMN counted_article_number TEXT',
    );
    await db.execute('''
UPDATE document_lines SET physical_count_state = CASE
  WHEN physical_quantity_confirmed = 1 THEN 'verified'
  WHEN physical_origin != 'defaultedFromDocument' THEN 'counting'
  ELSE 'notChecked' END,
  counted_article_number = CASE
  WHEN physical_quantity_confirmed = 1 OR physical_origin != 'defaultedFromDocument'
  THEN article_number ELSE NULL END
''');
    await db.execute(
      "ALTER TABLE physical_adjustments ADD COLUMN action TEXT NOT NULL DEFAULT 'adjustment'",
    );
  }

  /// Seastock: delivery notes belong to a vessel; check-outs and their lines
  /// are append-only records; settings hold the device id and last vessel.
  Future<void> _upgradeToV10(Database db) async {
    await db.execute('ALTER TABLE scan_sessions ADD COLUMN vessel_id TEXT');
    await db.update('scan_sessions', {'vessel_id': ppgDefaultVesselId});
    await db.execute('''
CREATE TABLE checkouts (
  id TEXT PRIMARY KEY,
  vessel_id TEXT NOT NULL,
  reference TEXT NOT NULL,
  device_id TEXT NOT NULL,
  operator_email TEXT,
  created_at TEXT NOT NULL
)''');
    await db.execute('''
CREATE TABLE checkout_lines (
  id TEXT PRIMARY KEY,
  checkout_id TEXT NOT NULL,
  article_number TEXT NOT NULL,
  product_context TEXT,
  quantity INTEGER NOT NULL,
  on_board_before INTEGER NOT NULL
)''');
    await db.execute(
      'CREATE INDEX checkout_lines_checkout ON checkout_lines (checkout_id)',
    );
    await db.execute('''
CREATE TABLE app_settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
)''');
  }

  /// Audit reports: a blind count sent to the vessel manager. Stock changes
  /// only through an approving decision, which is its own record so it can
  /// arrive later from the dashboard.
  Future<void> _upgradeToV11(Database db) async {
    await db.execute('''
CREATE TABLE audits (
  id TEXT PRIMARY KEY,
  vessel_id TEXT NOT NULL,
  reference TEXT NOT NULL,
  device_id TEXT NOT NULL,
  operator_email TEXT,
  created_at TEXT NOT NULL
)''');
    await db.execute('''
CREATE TABLE audit_lines (
  id TEXT PRIMARY KEY,
  audit_id TEXT NOT NULL,
  article_number TEXT NOT NULL,
  product_context TEXT,
  counted INTEGER,
  expected INTEGER NOT NULL
)''');
    await db.execute(
      'CREATE INDEX audit_lines_audit ON audit_lines (audit_id)',
    );
    await db.execute('''
CREATE TABLE audit_decisions (
  id TEXT PRIMARY KEY,
  audit_id TEXT NOT NULL,
  decision TEXT NOT NULL,
  decided_by TEXT,
  decided_at TEXT NOT NULL
)''');
  }

  Database get db {
    final database = _db;
    if (database == null) {
      throw StateError('PpgRepository not initialized');
    }
    return database;
  }

  Directory get evidenceDir {
    final dir = _evidenceDir;
    if (dir == null) throw StateError('PpgRepository not initialized');
    return dir;
  }

  Future<String> persistImageBytes({
    required String sessionId,
    required String pageCaptureId,
    required List<int> bytes,
    required String kind,
  }) async {
    final dir = Directory(p.join(evidenceDir.path, sessionId));
    await dir.create(recursive: true);
    final isPng =
        bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47;
    final file = File(
      p.join(dir.path, '${pageCaptureId}_$kind.${isPng ? 'png' : 'jpg'}'),
    );
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    if (await file.exists()) await file.delete();
    await tmp.rename(file.path);
    return file.path;
  }

  Future<ScanSession> createSession({
    String? operatorEmail,
    CaptureMode mode = CaptureMode.camera,
    String vesselId = ppgDefaultVesselId,
  }) async {
    final now = DateTime.now().toUtc();
    final session = ScanSession(
      id: _uuid.v4(),
      vesselId: vesselId,
      status: ScanSessionStatus.draft,
      formRevision: 1,
      operatorEmail: operatorEmail,
      mode: mode,
      createdAt: now,
      updatedAt: now,
    );
    await db.insert('scan_sessions', _sessionToMap(session));
    return session;
  }

  Future<List<ScanSession>> listSessions() async {
    final rows = await db.query('scan_sessions', orderBy: 'updated_at DESC');
    return rows.map(_sessionFromMap).toList();
  }

  Future<List<SessionProgress>> listSessionProgress() async {
    final sessions = await listSessions();
    final pageRows = await db.rawQuery('''
SELECT session_id, COUNT(*) AS pages, SUM(page_review_confirmed) AS checked
FROM page_captures WHERE is_active = 1 AND pending_replacement = 0
GROUP BY session_id''');
    final lineRows = await db.rawQuery('''
SELECT session_id, COUNT(*) AS items,
  SUM(document_quantity) AS document_total,
  SUM(CASE WHEN physical_count_state != 'notChecked' THEN 1 ELSE 0 END) AS counted_items,
  SUM(CASE WHEN physical_count_state != 'notChecked' THEN physical_quantity ELSE 0 END) AS counted_total,
  SUM(CASE WHEN physical_quantity_confirmed = 1 AND physical_count_state = 'verified'
    AND counted_article_number = article_number THEN 1 ELSE 0 END) AS verified_items
FROM document_lines GROUP BY session_id''');
    final submittedRows = await db.query(
      'submitted_forms',
      columns: ['session_id', 'submitted_at'],
    );
    final pagesBySession = {for (final row in pageRows) row['session_id']: row};
    final linesBySession = {for (final row in lineRows) row['session_id']: row};
    final submittedBySession = {
      for (final row in submittedRows)
        row['session_id']: DateTime.parse(row['submitted_at'] as String),
    };
    int read(Map<String, Object?>? row, String key) =>
        (row?[key] as num?)?.toInt() ?? 0;
    return [
      for (final session in sessions)
        SessionProgress(
          session: session,
          pageCount: read(pagesBySession[session.id], 'pages'),
          checkedPageCount: read(pagesBySession[session.id], 'checked'),
          itemCount: read(linesBySession[session.id], 'items'),
          documentTotal: read(linesBySession[session.id], 'document_total'),
          countedItemCount: read(linesBySession[session.id], 'counted_items'),
          countedTotal: read(linesBySession[session.id], 'counted_total'),
          verifiedItemCount: read(linesBySession[session.id], 'verified_items'),
          submittedAt: submittedBySession[session.id],
        ),
    ];
  }

  /// Removes an unsubmitted draft that has no physical counts, with its
  /// page photos. Drafts with counts and submitted forms are never deleted.
  Future<void> deleteDraftSession(String sessionId) async {
    await db.transaction((txn) async {
      final submitted = await txn.query(
        'submitted_forms',
        where: 'session_id = ?',
        whereArgs: [sessionId],
        limit: 1,
      );
      final sessions = await txn.query(
        'scan_sessions',
        where: 'id = ?',
        whereArgs: [sessionId],
        limit: 1,
      );
      if (sessions.isEmpty) return;
      if (submitted.isNotEmpty ||
          sessions.single['status'] == ScanSessionStatus.submittedLocal.name) {
        throw StateError('Submitted receiving forms cannot be deleted');
      }
      final counted = await txn.rawQuery(
        "SELECT COUNT(*) AS n FROM document_lines WHERE session_id = ? AND physical_count_state != 'notChecked'",
        [sessionId],
      );
      final adjustments = await txn.rawQuery(
        'SELECT COUNT(*) AS n FROM physical_adjustments WHERE session_id = ?',
        [sessionId],
      );
      if (((counted.single['n'] as num?) ?? 0) > 0 ||
          ((adjustments.single['n'] as num?) ?? 0) > 0) {
        throw StateError(
          'This draft has physical counts. Finish and submit it instead.',
        );
      }
      await txn.rawDelete(
        'DELETE FROM ocr_observations WHERE page_capture_id IN '
        '(SELECT page_capture_id FROM page_captures WHERE session_id = ?)',
        [sessionId],
      );
      for (final table in [
        'page_captures',
        'document_lines',
        'document_contexts',
        'corrections',
      ]) {
        await txn.delete(
          table,
          where: 'session_id = ?',
          whereArgs: [sessionId],
        );
      }
      await txn.delete(
        'scan_sessions',
        where: 'id = ?',
        whereArgs: [sessionId],
      );
    });
    final photos = Directory(p.join(evidenceDir.path, sessionId));
    if (await photos.exists()) await photos.delete(recursive: true);
  }

  Future<ScanSession?> getSession(String id) async {
    final rows = await db.query(
      'scan_sessions',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) return null;
    return _sessionFromMap(rows.first);
  }

  Future<void> saveSession(ScanSession session) async {
    session.updatedAt = DateTime.now().toUtc();
    await db.update(
      'scan_sessions',
      _sessionToMap(session),
      where: 'id = ?',
      whereArgs: [session.id],
    );
  }

  Future<PageCapture> addPageCapture({
    required String sessionId,
    required int printedPage,
    String? sourceImagePath,
    String? rectifiedImagePath,
    bool pendingReplacement = false,
  }) async {
    final revisions = await db.query(
      'page_captures',
      columns: ['capture_revision'],
      where: 'session_id = ? AND printed_page = ?',
      whereArgs: [sessionId, printedPage],
      orderBy: 'capture_revision DESC',
      limit: 1,
    );
    final revision = revisions.isEmpty
        ? 1
        : (revisions.first['capture_revision'] as int) + 1;
    final capture = PageCapture(
      pageCaptureId: _uuid.v4(),
      sessionId: sessionId,
      printedPage: printedPage,
      captureRevision: revision,
      isActive: true,
      pendingReplacement: pendingReplacement,
      sourceImagePath: sourceImagePath,
      rectifiedImagePath: rectifiedImagePath,
      createdAt: DateTime.now().toUtc(),
    );
    await db.insert('page_captures', _pageToMap(capture));
    return capture;
  }

  Future<void> activateReplacement(PageCapture page) async {
    if (page.pendingReplacement) return;
    await db.update(
      'page_captures',
      {'is_active': 0},
      where:
          'session_id = ? AND printed_page = ? AND page_capture_id != ? AND is_active = 1',
      whereArgs: [page.sessionId, page.printedPage, page.pageCaptureId],
    );
  }

  Future<void> commitReplacement(PageCapture page) async {
    await db.transaction((txn) async {
      await txn.update(
        'page_captures',
        {'is_active': 0},
        where:
            'session_id = ? AND printed_page = ? AND page_capture_id != ? AND is_active = 1',
        whereArgs: [page.sessionId, page.printedPage, page.pageCaptureId],
      );
      await txn.update(
        'page_captures',
        {'is_active': 1, 'pending_replacement': 0},
        where: 'page_capture_id = ?',
        whereArgs: [page.pageCaptureId],
      );
    });
  }

  Future<void> discardReplacement(PageCapture page) async {
    await db.update(
      'page_captures',
      {'is_active': 0, 'pending_replacement': 0},
      where: 'page_capture_id = ? AND pending_replacement = 1',
      whereArgs: [page.pageCaptureId],
    );
  }

  Future<PageCapture?> getPageCapture(String pageCaptureId) async {
    final rows = await db.query(
      'page_captures',
      where: 'page_capture_id = ?',
      whereArgs: [pageCaptureId],
      limit: 1,
    );
    return rows.isEmpty ? null : _pageFromMap(rows.single);
  }

  Future<List<PageCapture>> getPendingReplacements(String sessionId) async {
    final rows = await db.query(
      'page_captures',
      where: 'session_id = ? AND is_active = 1 AND pending_replacement = 1',
      whereArgs: [sessionId],
      orderBy: 'created_at DESC',
    );
    return rows.map(_pageFromMap).toList();
  }

  Future<void> updatePageCapture(PageCapture page) async {
    await db.update(
      'page_captures',
      _pageToMap(page),
      where: 'page_capture_id = ?',
      whereArgs: [page.pageCaptureId],
    );
  }

  Future<List<PageCapture>> getActivePages(String sessionId) async {
    final rows = await db.query(
      'page_captures',
      where: 'session_id = ? AND is_active = 1 AND pending_replacement = 0',
      whereArgs: [sessionId],
      orderBy: 'printed_page ASC',
    );
    return rows.map(_pageFromMap).toList();
  }

  Future<void> replaceDocumentLines(
    String sessionId,
    List<DocumentLine> lines,
  ) async {
    await db.delete(
      'document_lines',
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
    for (final line in lines) {
      await db.insert('document_lines', _lineToMap(line));
    }
  }

  Future<void> replaceDocumentContexts(
    String sessionId,
    List<DocumentContext> contexts,
  ) async {
    await db.delete(
      'document_contexts',
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
    for (final ctx in contexts) {
      await db.insert('document_contexts', _contextToMap(ctx));
    }
  }

  /// Keep a derivation and its revision marker together across process death.
  Future<void> commitConsolidation({
    required ScanSession session,
    required List<DocumentLine> lines,
    required List<DocumentContext> contexts,
    List<PageCapture> changedPages = const [],
  }) async {
    session.updatedAt = DateTime.now().toUtc();
    await db.transaction((txn) async {
      for (final page in changedPages) {
        await txn.update(
          'page_captures',
          _pageToMap(page),
          where: 'page_capture_id = ?',
          whereArgs: [page.pageCaptureId],
        );
      }
      await txn.update(
        'scan_sessions',
        _sessionToMap(session),
        where: 'id = ?',
        whereArgs: [session.id],
      );
      await txn.delete(
        'document_lines',
        where: 'session_id = ?',
        whereArgs: [session.id],
      );
      for (final line in lines) {
        await txn.insert('document_lines', _lineToMap(line));
      }
      await txn.delete(
        'document_contexts',
        where: 'session_id = ?',
        whereArgs: [session.id],
      );
      for (final context in contexts) {
        await txn.insert('document_contexts', _contextToMap(context));
      }
    });
  }

  Future<void> saveSourceCorrection({
    required ScanSession session,
    required PageCapture page,
    required DocumentLine line,
    required CorrectionRecord correction,
  }) async {
    session.updatedAt = DateTime.now().toUtc();
    await db.transaction((txn) async {
      await txn.insert(
        'document_lines',
        _lineToMap(line),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.insert('corrections', {
        'id': correction.id,
        'session_id': correction.sessionId,
        'occurrence_id': correction.occurrenceId,
        'field': correction.field,
        'before_value': correction.beforeValue,
        'after_value': correction.afterValue,
        'reason': correction.reason,
        'created_at': correction.createdAt.toIso8601String(),
      });
      await txn.update(
        'page_captures',
        _pageToMap(page),
        where: 'page_capture_id = ?',
        whereArgs: [page.pageCaptureId],
      );
      await txn.update(
        'scan_sessions',
        _sessionToMap(session),
        where: 'id = ?',
        whereArgs: [session.id],
      );
    });
  }

  Future<List<DocumentLine>> getLines(String sessionId) async {
    final rows = await db.query(
      'document_lines',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'source_page ASC',
    );
    return rows.map(_lineFromMap).toList();
  }

  Future<void> insertLine(DocumentLine line) async {
    await db.insert('document_lines', _lineToMap(line));
  }

  Future<void> saveLine(DocumentLine line) async {
    await db.update(
      'document_lines',
      _lineToMap(line),
      where: 'occurrence_id = ?',
      whereArgs: [line.occurrenceId],
    );
  }

  /// A count, its audit event, and final-review invalidation commit together.
  Future<bool> hasPhysicalAdjustment(
    String id, {
    required String sessionId,
    required String occurrenceId,
  }) async => (await db.query(
    'physical_adjustments',
    columns: ['id'],
    where: 'id = ? AND session_id = ? AND occurrence_id = ?',
    whereArgs: [id, sessionId, occurrenceId],
    limit: 1,
  )).isNotEmpty;

  Future<void> savePhysicalCount({
    required ScanSession session,
    required DocumentLine line,
    required PhysicalAdjustment adjustment,
  }) async {
    session.updatedAt = DateTime.now().toUtc();
    await db.transaction((txn) async {
      final updated = await txn.update(
        'document_lines',
        _lineToMap(line),
        where: 'occurrence_id = ? AND session_id = ?',
        whereArgs: [line.occurrenceId, session.id],
      );
      if (updated != 1) {
        throw StateError('The receiving line is no longer available');
      }
      await txn.insert('physical_adjustments', {
        'id': adjustment.id,
        'session_id': adjustment.sessionId,
        'occurrence_id': adjustment.occurrenceId,
        'before_quantity': adjustment.beforeQuantity,
        'after_quantity': adjustment.afterQuantity,
        'reason': adjustment.reason,
        'action': adjustment.action,
        'created_at': adjustment.createdAt.toIso8601String(),
      });
      await txn.update(
        'scan_sessions',
        _sessionToMap(session),
        where: 'id = ?',
        whereArgs: [session.id],
      );
    });
  }

  Future<List<DocumentContext>> getContexts(String sessionId) async {
    final rows = await db.query(
      'document_contexts',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'source_page ASC',
    );
    return rows.map(_contextFromMap).toList();
  }

  Future<void> addCorrection(CorrectionRecord record) async {
    await db.insert('corrections', {
      'id': record.id,
      'session_id': record.sessionId,
      'occurrence_id': record.occurrenceId,
      'field': record.field,
      'before_value': record.beforeValue,
      'after_value': record.afterValue,
      'reason': record.reason,
      'created_at': record.createdAt.toIso8601String(),
    });
  }

  Future<void> addPhysicalAdjustment(PhysicalAdjustment adj) async {
    await db.insert('physical_adjustments', {
      'id': adj.id,
      'session_id': adj.sessionId,
      'occurrence_id': adj.occurrenceId,
      'before_quantity': adj.beforeQuantity,
      'after_quantity': adj.afterQuantity,
      'reason': adj.reason,
      'action': adj.action,
      'created_at': adj.createdAt.toIso8601String(),
    });
  }

  Future<void> saveOcrObservation(OcrObservation obs) async {
    await db.insert('ocr_observations', {
      'ocr_run_id': obs.ocrRunId,
      'page_capture_id': obs.pageCaptureId,
      'capture_revision': obs.captureRevision,
      'payload_json': jsonEncode({
        'engineName': obs.engineName,
        'engineVersion': obs.engineVersion,
        'imageWidth': obs.imageWidth,
        'imageHeight': obs.imageHeight,
        'elapsedMs': obs.elapsedMs,
        'elements': obs.elements.map((e) => e.toJson()).toList(),
        'lines': obs.lines.map((e) => e.toJson()).toList(),
        'symbols': obs.symbols.map((e) => e.toJson()).toList(),
        'fieldQuantityReads': obs.fieldQuantityReads,
        'fieldEvidence': obs.fieldEvidence,
      }),
      'created_at': obs.createdAt.toIso8601String(),
    });
  }

  Future<OcrObservation?> getLatestOcrObservation(PageCapture page) async {
    final rows = await db.query(
      'ocr_observations',
      where: 'page_capture_id = ? AND capture_revision = ?',
      whereArgs: [page.pageCaptureId, page.captureRevision],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final payload =
        jsonDecode(row['payload_json'] as String) as Map<String, dynamic>;
    return OcrObservation(
      ocrRunId: row['ocr_run_id'] as String,
      pageCaptureId: page.pageCaptureId,
      captureRevision: page.captureRevision,
      engineName: payload['engineName'] as String,
      engineVersion: payload['engineVersion'] as String,
      imageWidth: payload['imageWidth'] as int,
      imageHeight: payload['imageHeight'] as int,
      elapsedMs: payload['elapsedMs'] as int?,
      elements: (payload['elements'] as List)
          .map((e) => OcrElement.fromJson(e as Map<String, dynamic>))
          .toList(),
      lines: (payload['lines'] as List? ?? [])
          .map((e) => OcrElement.fromJson(e as Map<String, dynamic>))
          .toList(),
      symbols: (payload['symbols'] as List? ?? [])
          .map((e) => OcrElement.fromJson(e as Map<String, dynamic>))
          .toList(),
      fieldQuantityReads: (payload['fieldQuantityReads'] as Map? ?? {}).map(
        (key, value) => MapEntry(key.toString(), (value as num).toInt()),
      ),
      fieldEvidence: Map<String, dynamic>.from(
        payload['fieldEvidence'] as Map? ?? {},
      ),
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }

  /// Idempotent local submit: returns existing submission if present.
  Future<SubmittedForm> submitLocal({
    required String sessionId,
    required String submissionId,
    required String snapshotJson,
  }) async {
    return db.transaction((txn) async {
      final existing = await txn.query(
        'submitted_forms',
        where: 'session_id = ?',
        whereArgs: [sessionId],
      );
      if (existing.isNotEmpty) {
        final row = existing.first;
        return SubmittedForm(
          submissionId: row['submission_id'] as String,
          sessionId: row['session_id'] as String,
          snapshotJson: row['snapshot_json'] as String,
          submittedAt: DateTime.parse(row['submitted_at'] as String),
        );
      }
      final now = DateTime.now().toUtc();
      await txn.insert('submitted_forms', {
        'submission_id': submissionId,
        'session_id': sessionId,
        'snapshot_json': snapshotJson,
        'submitted_at': now.toIso8601String(),
      });
      await txn.update(
        'scan_sessions',
        {
          'status': ScanSessionStatus.submittedLocal.name,
          'updated_at': now.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [sessionId],
      );
      return SubmittedForm(
        submissionId: submissionId,
        sessionId: sessionId,
        snapshotJson: snapshotJson,
        submittedAt: now,
      );
    });
  }

  Future<SubmittedForm?> getSubmissionForSession(String sessionId) async {
    final rows = await db.query(
      'submitted_forms',
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return SubmittedForm(
      submissionId: row['submission_id'] as String,
      sessionId: row['session_id'] as String,
      snapshotJson: row['snapshot_json'] as String,
      submittedAt: DateTime.parse(row['submitted_at'] as String),
    );
  }

  Map<String, Object?> _sessionToMap(ScanSession s) => {
    'id': s.id,
    'status': s.status.name,
    'delivery_note_number': s.deliveryNoteNumber,
    'declared_page_count': s.declaredPageCount,
    'form_revision': s.formRevision,
    'review_confirmed_revision': s.reviewConfirmedRevision,
    'operator_email': s.operatorEmail,
    'mode': s.mode.name,
    'vessel_id': s.vesselId,
    'created_at': s.createdAt.toIso8601String(),
    'updated_at': s.updatedAt.toIso8601String(),
  };

  ScanSession _sessionFromMap(Map<String, Object?> m) => ScanSession(
    id: m['id'] as String,
    status: ScanSessionStatus.values.byName(m['status'] as String),
    deliveryNoteNumber: m['delivery_note_number'] as String?,
    declaredPageCount: m['declared_page_count'] as int?,
    formRevision: m['form_revision'] as int,
    reviewConfirmedRevision: m['review_confirmed_revision'] as int?,
    operatorEmail: m['operator_email'] as String?,
    mode: CaptureMode.values.byName(m['mode'] as String),
    vesselId: m['vessel_id'] as String? ?? ppgDefaultVesselId,
    createdAt: DateTime.parse(m['created_at'] as String),
    updatedAt: DateTime.parse(m['updated_at'] as String),
  );

  Map<String, Object?> _pageToMap(PageCapture p) => {
    'page_capture_id': p.pageCaptureId,
    'session_id': p.sessionId,
    'printed_page': p.printedPage,
    'capture_revision': p.captureRevision,
    'is_active': p.isActive ? 1 : 0,
    'source_image_path': p.sourceImagePath,
    'rectified_image_path': p.rectifiedImagePath,
    'ocr_status': p.ocrStatus.name,
    'ocr_error': p.ocrError,
    'created_at': p.createdAt.toIso8601String(),
    'suggested_printed_page': p.suggestedPrintedPage,
    'suggested_declared_page_count': p.suggestedDeclaredPageCount,
    'observed_delivery_note_number': p.observedDeliveryNoteNumber,
    'verified_delivery_note_number': p.verifiedDeliveryNoteNumber,
    'observed_piece_count': p.observedPieceCount,
    'verified_piece_count': p.verifiedPieceCount,
    'verified_declared_page_count': p.verifiedDeclaredPageCount,
    'page_identity_confirmed': p.pageIdentityConfirmed ? 1 : 0,
    'rotation_degrees': p.rotationDegrees,
    'page_review_confirmed': p.pageReviewConfirmed ? 1 : 0,
    'piece_count_variance_reviewed': p.pieceCountVarianceReviewed ? 1 : 0,
    'pending_replacement': p.pendingReplacement ? 1 : 0,
  };

  PageCapture _pageFromMap(Map<String, Object?> m) => PageCapture(
    pageCaptureId: m['page_capture_id'] as String,
    sessionId: m['session_id'] as String,
    printedPage: m['printed_page'] as int,
    captureRevision: m['capture_revision'] as int,
    isActive: (m['is_active'] as int) == 1,
    sourceImagePath: m['source_image_path'] as String?,
    rectifiedImagePath: m['rectified_image_path'] as String?,
    ocrStatus: PageOcrStatus.values.byName(m['ocr_status'] as String),
    ocrError: m['ocr_error'] as String?,
    createdAt: DateTime.parse(m['created_at'] as String),
    suggestedPrintedPage: m['suggested_printed_page'] as int?,
    suggestedDeclaredPageCount: m['suggested_declared_page_count'] as int?,
    observedDeliveryNoteNumber: m['observed_delivery_note_number'] as String?,
    verifiedDeliveryNoteNumber: m['verified_delivery_note_number'] as String?,
    observedPieceCount: m['observed_piece_count'] as int?,
    verifiedPieceCount: m['verified_piece_count'] as int?,
    verifiedDeclaredPageCount: m['verified_declared_page_count'] as int?,
    pageIdentityConfirmed: ((m['page_identity_confirmed'] as int?) ?? 0) == 1,
    rotationDegrees: (m['rotation_degrees'] as int?) ?? 0,
    pageReviewConfirmed: ((m['page_review_confirmed'] as int?) ?? 0) == 1,
    pieceCountVarianceReviewed:
        ((m['piece_count_variance_reviewed'] as int?) ?? 0) == 1,
    pendingReplacement: ((m['pending_replacement'] as int?) ?? 0) == 1,
  );

  Map<String, Object?> _lineToMap(DocumentLine l) => {
    'occurrence_id': l.occurrenceId,
    'session_id': l.sessionId,
    'article_number': l.articleNumber,
    'document_quantity': l.documentQuantity,
    'physical_quantity': l.physicalQuantity,
    'physical_origin': l.physicalOrigin.name,
    'unit': l.unit,
    'source_page': l.sourcePage,
    'page_capture_id': l.pageCaptureId,
    'product_context': l.productContext,
    'variance_reason': l.varianceReason,
    'review_confirmed': l.reviewConfirmed ? 1 : 0,
    'physical_quantity_confirmed': l.physicalQuantityConfirmed ? 1 : 0,
    'physical_count_state': l.physicalCountState.name,
    'counted_article_number': l.countedArticleNumber,
    'raw_ocr_article': l.rawOcrArticle,
    'raw_ocr_quantity': l.rawOcrQuantity,
  };

  DocumentLine _lineFromMap(Map<String, Object?> m) => DocumentLine(
    occurrenceId: m['occurrence_id'] as String,
    sessionId: m['session_id'] as String,
    articleNumber: m['article_number'] as String,
    documentQuantity: m['document_quantity'] as int,
    physicalQuantity: m['physical_quantity'] as int,
    physicalOrigin: PhysicalQuantityOrigin.values.byName(
      m['physical_origin'] as String,
    ),
    unit: m['unit'] as String,
    sourcePage: m['source_page'] as int,
    pageCaptureId: m['page_capture_id'] as String,
    productContext: m['product_context'] as String?,
    varianceReason: m['variance_reason'] as String?,
    reviewConfirmed: (m['review_confirmed'] as int) == 1,
    physicalQuantityConfirmed:
        ((m['physical_quantity_confirmed'] as int?) ?? 0) == 1,
    physicalCountState: m['physical_count_state'] == null
        ? null
        : PhysicalCountState.values.byName(m['physical_count_state'] as String),
    countedArticleNumber: m['counted_article_number'] as String?,
    rawOcrArticle: m['raw_ocr_article'] as String?,
    rawOcrQuantity: m['raw_ocr_quantity'] as int?,
  );

  Map<String, Object?> _contextToMap(DocumentContext c) => {
    'context_id': c.contextId,
    'session_id': c.sessionId,
    'article_number': c.articleNumber,
    'heading': c.heading,
    'source_page': c.sourcePage,
    'page_capture_id': c.pageCaptureId,
  };

  DocumentContext _contextFromMap(Map<String, Object?> m) => DocumentContext(
    contextId: m['context_id'] as String,
    sessionId: m['session_id'] as String,
    articleNumber: m['article_number'] as String,
    heading: m['heading'] as String?,
    sourcePage: m['source_page'] as int,
    pageCaptureId: m['page_capture_id'] as String,
  );
}
