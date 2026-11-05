import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../ppg_delivery_note/persistence/ppg_repository.dart';
import '../domain/stock.dart';

/// Stock, check-ins, check-outs, audit reports and settings for Seastock.
/// Stock is never stored as a total: it is added up from append-only records
/// (submitted delivery notes, check-outs, approved audits), so records from
/// other devices and the dashboard can be merged later.
abstract class SeastockStore {
  Future<void> init();
  Future<String?> readSetting(String key);
  Future<void> writeSetting(String key, String value);
  Future<void> deleteSetting(String key);
  Future<StockSnapshot> stock(String vesselId);

  /// Submitted delivery notes on the vessel, newest first.
  Future<List<CheckInRecord>> checkIns(String vesselId);

  /// Check-outs on the vessel, newest first.
  Future<List<CheckoutRecord>> checkouts(String vesselId);

  /// Audit reports on the vessel, newest first.
  Future<List<AuditRecord>> audits(String vesselId);

  /// Saves a check-out after checking, in the same transaction, that every
  /// quantity is still on board. Throws [StateError] otherwise.
  Future<CheckoutRecord> saveCheckout({
    required String vesselId,
    required Map<String, int> items,
    required String deviceId,
    String? operatorEmail,
  });

  /// Saves a blind count as a report for the vessel manager. Every article on
  /// board is in the report; those missing from [counted] are "not counted".
  /// Stock does not change.
  Future<AuditRecord> saveAudit({
    required String vesselId,
    required Map<String, int> counted,
    required String deviceId,
    String? operatorEmail,
  });

  /// Records the vessel manager's decision on a report. Only an approval
  /// changes stock. Decisions will arrive from the dashboard once it syncs.
  Future<void> decideAudit({
    required String auditId,
    required bool approved,
    String? decidedBy,
  });
}

class SqliteSeastockStore implements SeastockStore {
  SqliteSeastockStore({PpgRepository? repository, Uuid? uuid})
    : _repo = repository ?? PpgRepository(),
      _uuid = uuid ?? const Uuid();

  final PpgRepository _repo;
  final Uuid _uuid;

  Database get _db => _repo.db;

  @override
  Future<void> init() => _repo.init();

  @override
  Future<String?> readSetting(String key) async {
    final rows = await _db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['value'] as String;
  }

  @override
  Future<void> writeSetting(String key, String value) async {
    await _db.insert('app_settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> deleteSetting(String key) async {
    await _db.delete('app_settings', where: 'key = ?', whereArgs: [key]);
  }

  @override
  Future<StockSnapshot> stock(String vesselId) => _stock(_db, vesselId);

  static const _verifiedLines = '''
FROM document_lines dl
JOIN scan_sessions s ON s.id = dl.session_id
JOIN submitted_forms sf ON sf.session_id = s.id
WHERE s.vessel_id = ? AND dl.physical_count_state = 'verified'
  AND dl.physical_quantity_confirmed = 1''';

  Future<StockSnapshot> _stock(DatabaseExecutor db, String vesselId) async {
    final inRows = await db.rawQuery(
      '''
SELECT dl.article_number AS article, SUM(dl.physical_quantity) AS qty,
  MAX(dl.product_context) AS product, MAX(sf.submitted_at) AS last_at
$_verifiedLines
GROUP BY dl.article_number''',
      [vesselId],
    );
    final outRows = await db.rawQuery(
      '''
SELECT cl.article_number AS article, SUM(cl.quantity) AS qty,
  MAX(cl.product_context) AS product, MAX(c.created_at) AS last_at
FROM checkout_lines cl
JOIN checkouts c ON c.id = cl.checkout_id
WHERE c.vessel_id = ?
GROUP BY cl.article_number''',
      [vesselId],
    );
    final auditRows = await db.rawQuery(
      '''
SELECT al.article_number AS article, SUM(al.counted - al.expected) AS qty,
  MAX(al.product_context) AS product, MAX(d.decided_at) AS last_at
FROM audit_lines al
JOIN audits a ON a.id = al.audit_id
JOIN audit_decisions d ON d.audit_id = a.id AND d.decision = 'approved'
WHERE a.vessel_id = ? AND al.counted IS NOT NULL
GROUP BY al.article_number''',
      [vesselId],
    );
    final checkedIn = <String, int>{};
    final checkedOut = <String, int>{};
    final audited = <String, int>{};
    final products = <String, String>{};
    DateTime? last;
    void collect(List<Map<String, Object?>> rows, Map<String, int> into) {
      for (final row in rows) {
        final article = row['article'] as String;
        into[article] = (row['qty'] as num?)?.toInt() ?? 0;
        final product = row['product'] as String?;
        if (product != null) products.putIfAbsent(article, () => product);
        final at = row['last_at'] as String?;
        if (at != null) {
          final time = DateTime.parse(at);
          if (last == null || time.isAfter(last!)) last = time;
        }
      }
    }

    collect(inRows, checkedIn);
    collect(outRows, checkedOut);
    collect(auditRows, audited);
    final items =
        [
          for (final article in {
            ...checkedIn.keys,
            ...checkedOut.keys,
            ...audited.keys,
          })
            StockItem(
              articleNumber: article,
              product: products[article],
              checkedIn: checkedIn[article] ?? 0,
              checkedOut: checkedOut[article] ?? 0,
              audited: audited[article] ?? 0,
            ),
        ]..sort((a, b) {
          final byStock = b.onBoard.compareTo(a.onBoard);
          return byStock != 0
              ? byStock
              : a.articleNumber.compareTo(b.articleNumber);
        });
    return StockSnapshot(items: items, lastChange: last);
  }

  @override
  Future<List<CheckInRecord>> checkIns(String vesselId) async {
    final heads = await _db.rawQuery(
      '''
SELECT s.id, s.delivery_note_number, s.operator_email, sf.submitted_at
FROM scan_sessions s
JOIN submitted_forms sf ON sf.session_id = s.id
WHERE s.vessel_id = ?
ORDER BY sf.submitted_at DESC''',
      [vesselId],
    );
    if (heads.isEmpty) return const [];
    final lines = await _db.rawQuery(
      '''
SELECT dl.session_id AS session, dl.article_number AS article,
  SUM(dl.physical_quantity) AS qty, MAX(dl.product_context) AS product
$_verifiedLines
GROUP BY dl.session_id, dl.article_number
ORDER BY MIN(dl.rowid)''',
      [vesselId],
    );
    final bySession = <String, List<CheckInLine>>{};
    for (final row in lines) {
      bySession
          .putIfAbsent(row['session'] as String, () => [])
          .add(
            CheckInLine(
              articleNumber: row['article'] as String,
              product: row['product'] as String?,
              quantity: (row['qty'] as num?)?.toInt() ?? 0,
            ),
          );
    }
    return [
      for (final row in heads)
        CheckInRecord(
          sessionId: row['id'] as String,
          deliveryNoteNumber: row['delivery_note_number'] as String?,
          operatorEmail: row['operator_email'] as String?,
          submittedAt: DateTime.parse(row['submitted_at'] as String),
          lines: bySession[row['id']] ?? const [],
        ),
    ];
  }

  @override
  Future<List<CheckoutRecord>> checkouts(String vesselId) async {
    final heads = await _db.query(
      'checkouts',
      where: 'vessel_id = ?',
      whereArgs: [vesselId],
      orderBy: 'created_at DESC',
    );
    if (heads.isEmpty) return const [];
    final lines = await _db.rawQuery(
      '''
SELECT cl.* FROM checkout_lines cl
JOIN checkouts c ON c.id = cl.checkout_id
WHERE c.vessel_id = ?
ORDER BY cl.rowid''',
      [vesselId],
    );
    final byCheckout = <String, List<CheckoutLine>>{};
    for (final row in lines) {
      byCheckout
          .putIfAbsent(row['checkout_id'] as String, () => [])
          .add(
            CheckoutLine(
              articleNumber: row['article_number'] as String,
              product: row['product_context'] as String?,
              quantity: row['quantity'] as int,
              onBoardBefore: row['on_board_before'] as int,
            ),
          );
    }
    return [
      for (final row in heads)
        CheckoutRecord(
          id: row['id'] as String,
          vesselId: row['vessel_id'] as String,
          reference: row['reference'] as String,
          deviceId: row['device_id'] as String,
          operatorEmail: row['operator_email'] as String?,
          createdAt: DateTime.parse(row['created_at'] as String),
          lines: byCheckout[row['id']] ?? const [],
        ),
    ];
  }

  @override
  Future<List<AuditRecord>> audits(String vesselId) async {
    final heads = await _db.rawQuery(
      '''
SELECT a.*, d.decision, d.decided_at FROM audits a
LEFT JOIN audit_decisions d ON d.audit_id = a.id
WHERE a.vessel_id = ?
ORDER BY a.created_at DESC''',
      [vesselId],
    );
    if (heads.isEmpty) return const [];
    final lines = await _db.rawQuery(
      '''
SELECT al.* FROM audit_lines al
JOIN audits a ON a.id = al.audit_id
WHERE a.vessel_id = ?
ORDER BY al.rowid''',
      [vesselId],
    );
    final byAudit = <String, List<AuditLine>>{};
    for (final row in lines) {
      byAudit
          .putIfAbsent(row['audit_id'] as String, () => [])
          .add(
            AuditLine(
              articleNumber: row['article_number'] as String,
              product: row['product_context'] as String?,
              counted: row['counted'] as int?,
              expected: row['expected'] as int,
            ),
          );
    }
    return [
      for (final row in heads)
        AuditRecord(
          id: row['id'] as String,
          vesselId: row['vessel_id'] as String,
          reference: row['reference'] as String,
          deviceId: row['device_id'] as String,
          operatorEmail: row['operator_email'] as String?,
          createdAt: DateTime.parse(row['created_at'] as String),
          lines: byAudit[row['id']] ?? const [],
          status: switch (row['decision']) {
            'approved' => AuditStatus.approved,
            'rejected' => AuditStatus.rejected,
            _ => AuditStatus.waiting,
          },
          decidedAt: row['decided_at'] == null
              ? null
              : DateTime.parse(row['decided_at'] as String),
        ),
    ];
  }

  @override
  Future<CheckoutRecord> saveCheckout({
    required String vesselId,
    required Map<String, int> items,
    required String deviceId,
    String? operatorEmail,
  }) {
    final wanted = {
      for (final entry in items.entries)
        if (entry.value != 0) entry.key: entry.value,
    };
    if (wanted.isEmpty) {
      throw StateError('Add at least one can to the check-out.');
    }
    if (wanted.values.any((quantity) => quantity < 0)) {
      throw ArgumentError('A check-out quantity cannot be negative.');
    }
    return _db.transaction((txn) async {
      final stock = await _stock(txn, vesselId);
      final lines = <CheckoutLine>[];
      for (final entry in wanted.entries) {
        final item = stock.item(entry.key);
        final onBoard = item?.onBoard ?? 0;
        if (entry.value > onBoard) {
          throw StateError(
            onBoard <= 0
                ? 'Article ${entry.key} has none left on board.'
                : 'Only $onBoard PC of article ${entry.key} are on board.',
          );
        }
        lines.add(
          CheckoutLine(
            articleNumber: entry.key,
            product: item?.product,
            quantity: entry.value,
            onBoardBefore: onBoard,
          ),
        );
      }
      final record = CheckoutRecord(
        id: _uuid.v4(),
        vesselId: vesselId,
        reference: await _nextReference(txn, 'checkouts', 'CO', vesselId),
        deviceId: deviceId,
        operatorEmail: operatorEmail,
        createdAt: DateTime.now().toUtc(),
        lines: lines,
      );
      await txn.insert('checkouts', {
        'id': record.id,
        'vessel_id': record.vesselId,
        'reference': record.reference,
        'device_id': record.deviceId,
        'operator_email': record.operatorEmail,
        'created_at': record.createdAt.toIso8601String(),
      });
      for (final line in lines) {
        await txn.insert('checkout_lines', {
          'id': _uuid.v4(),
          'checkout_id': record.id,
          'article_number': line.articleNumber,
          'product_context': line.product,
          'quantity': line.quantity,
          'on_board_before': line.onBoardBefore,
        });
      }
      return record;
    });
  }

  @override
  Future<AuditRecord> saveAudit({
    required String vesselId,
    required Map<String, int> counted,
    required String deviceId,
    String? operatorEmail,
  }) {
    if (counted.isEmpty) {
      throw StateError('Count at least one article before sending.');
    }
    if (counted.values.any((quantity) => quantity < 0)) {
      throw ArgumentError('A count cannot be negative.');
    }
    return _db.transaction((txn) async {
      final stock = await _stock(txn, vesselId);
      final onList = stock.onBoardItems;
      final listed = onList.map((item) => item.articleNumber).toSet();
      final lines = [
        for (final item in onList)
          AuditLine(
            articleNumber: item.articleNumber,
            product: item.product,
            counted: counted[item.articleNumber],
            expected: item.onBoard,
          ),
        for (final entry in counted.entries)
          if (!listed.contains(entry.key))
            AuditLine(
              articleNumber: entry.key,
              product: stock.item(entry.key)?.product,
              counted: entry.value,
              expected: 0,
            ),
      ];
      final record = AuditRecord(
        id: _uuid.v4(),
        vesselId: vesselId,
        reference: await _nextReference(txn, 'audits', 'AU', vesselId),
        deviceId: deviceId,
        operatorEmail: operatorEmail,
        createdAt: DateTime.now().toUtc(),
        lines: lines,
      );
      await txn.insert('audits', {
        'id': record.id,
        'vessel_id': record.vesselId,
        'reference': record.reference,
        'device_id': record.deviceId,
        'operator_email': record.operatorEmail,
        'created_at': record.createdAt.toIso8601String(),
      });
      for (final line in lines) {
        await txn.insert('audit_lines', {
          'id': _uuid.v4(),
          'audit_id': record.id,
          'article_number': line.articleNumber,
          'product_context': line.product,
          'counted': line.counted,
          'expected': line.expected,
        });
      }
      return record;
    });
  }

  @override
  Future<void> decideAudit({
    required String auditId,
    required bool approved,
    String? decidedBy,
  }) => _db.transaction((txn) async {
    final audit = await txn.query(
      'audits',
      where: 'id = ?',
      whereArgs: [auditId],
      limit: 1,
    );
    if (audit.isEmpty) throw StateError('This audit report does not exist.');
    final decided = await txn.query(
      'audit_decisions',
      where: 'audit_id = ?',
      whereArgs: [auditId],
      limit: 1,
    );
    if (decided.isNotEmpty) {
      throw StateError('This audit report has already been decided.');
    }
    await txn.insert('audit_decisions', {
      'id': _uuid.v4(),
      'audit_id': auditId,
      'decision': approved ? 'approved' : 'rejected',
      'decided_by': decidedBy,
      'decided_at': DateTime.now().toUtc().toIso8601String(),
    });
  });

  /// Per-vessel running reference, e.g. CO-0002 or AU-0001.
  Future<String> _nextReference(
    DatabaseExecutor txn,
    String table,
    String prefix,
    String vesselId,
  ) async {
    final count = await txn.rawQuery(
      'SELECT COUNT(*) AS n FROM $table WHERE vessel_id = ?',
      [vesselId],
    );
    final number = ((count.single['n'] as num?)?.toInt() ?? 0) + 1;
    return '$prefix-${number.toString().padLeft(4, '0')}';
  }
}
