import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:label_reader/features/ppg_delivery_note/domain/models.dart';
import 'package:label_reader/features/ppg_delivery_note/persistence/ppg_repository.dart';
import 'package:label_reader/features/seastock/domain/stock.dart';
import 'package:label_reader/features/seastock/persistence/seastock_store.dart';
import 'package:label_reader/features/seastock/services/seastock_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Real SQLite (in memory) so the stock arithmetic and the transaction checks
/// are exercised as they run on the device.
Future<(PpgRepository, SqliteSeastockStore)> _open() async {
  sqfliteFfiInit();
  final docs = await Directory.systemTemp.createTemp('seastock_test');
  addTearDown(() => docs.delete(recursive: true));
  final repo = PpgRepository(
    databaseFactory: databaseFactoryFfiNoIsolate,
    databasePath: inMemoryDatabasePath,
    documentsDirectory: docs,
  );
  final store = SqliteSeastockStore(repository: repo);
  await store.init();
  addTearDown(() => repo.db.close());
  return (repo, store);
}

/// Saves a delivery note with verified counts, submitted unless [submit] is
/// false.
Future<void> _deliveryNote(
  PpgRepository repo, {
  required String vesselId,
  required Map<String, int> counted,
  bool submit = true,
  bool verified = true,
}) async {
  final session = await repo.createSession(vesselId: vesselId);
  var i = 0;
  for (final entry in counted.entries) {
    await repo.insertLine(
      DocumentLine(
        occurrenceId: '${session.id}-${i++}',
        sessionId: session.id,
        articleNumber: entry.key,
        documentQuantity: entry.value,
        physicalQuantity: entry.value,
        physicalOrigin: PhysicalQuantityOrigin.userEntered,
        sourcePage: 1,
        pageCaptureId: 'page',
        productContext: 'Product ${entry.key}',
        physicalQuantityConfirmed: verified,
      ),
    );
  }
  if (submit) {
    await repo.submitLocal(
      sessionId: session.id,
      submissionId: 'sub-${session.id}',
      snapshotJson: '{}',
    );
  }
}

void main() {
  test('stock adds submitted, verified counts per vessel only', () async {
    final (repo, store) = await _open();
    await _deliveryNote(
      repo,
      vesselId: 'vessel-1',
      counted: {'445374': 20, '445182': 3},
    );
    await _deliveryNote(repo, vesselId: 'vessel-1', counted: {'445374': 5});
    await _deliveryNote(repo, vesselId: 'vessel-2', counted: {'475210': 7});
    await _deliveryNote(
      repo,
      vesselId: 'vessel-1',
      counted: {'445235': 15},
      submit: false,
    );
    await _deliveryNote(
      repo,
      vesselId: 'vessel-1',
      counted: {'445386': 8},
      verified: false,
    );

    final stock = await store.stock('vessel-1');
    expect(stock.total, 28);
    expect(stock.onBoard('445374'), 25);
    expect(stock.onBoard('445182'), 3);
    expect(stock.item('445235'), isNull, reason: 'draft adds nothing');
    expect(stock.item('445386'), isNull, reason: 'unverified adds nothing');
    expect(stock.items.first.articleNumber, '445374');
    expect(stock.items.first.product, 'Product 445374');
    expect(stock.lastChange, isNotNull);
    expect((await store.stock('vessel-2')).total, 7);
    expect((await store.stock('vessel-3')).items, isEmpty);
  });

  test(
    'check-outs deduct, keep before figures and number per vessel',
    () async {
      final (repo, store) = await _open();
      await _deliveryNote(
        repo,
        vesselId: 'vessel-1',
        counted: {'445374': 20, '445182': 3},
      );
      final first = await store.saveCheckout(
        vesselId: 'vessel-1',
        items: {'445374': 6, '445182': 2},
        deviceId: 'device-a',
        operatorEmail: 'op@example.com',
      );
      expect(first.reference, 'CO-0001');
      expect(first.total, 8);
      final second = await store.saveCheckout(
        vesselId: 'vessel-1',
        items: {'445182': 1},
        deviceId: 'device-a',
      );
      expect(second.reference, 'CO-0002');
      expect(second.lines.single.onBoardBefore, 1);
      expect(second.lines.single.onBoardAfter, 0);

      final stock = await store.stock('vessel-1');
      expect(stock.onBoard('445374'), 14);
      expect(stock.onBoard('445182'), 0);
      expect(stock.item('445182'), isNotNull, reason: 'shown as none left');
      expect(stock.total, 14);
      expect(stock.articlesOnBoard, 1);

      final history = await store.checkouts('vessel-1');
      expect(history.map((c) => c.reference), ['CO-0002', 'CO-0001']);
      expect(history.last.lines.map((l) => l.articleNumber), [
        '445374',
        '445182',
      ]);
      expect(history.last.lines.first.onBoardBefore, 20);
      expect(history.last.operatorEmail, 'op@example.com');
      expect(await store.checkouts('vessel-2'), isEmpty);
    },
  );

  test('a check-out above stock or of unknown cans saves nothing', () async {
    final (repo, store) = await _open();
    await _deliveryNote(repo, vesselId: 'vessel-1', counted: {'445374': 2});
    await expectLater(
      store.saveCheckout(
        vesselId: 'vessel-1',
        items: {'445374': 1, '999999': 1},
        deviceId: 'd',
      ),
      throwsStateError,
    );
    await expectLater(
      store.saveCheckout(
        vesselId: 'vessel-1',
        items: {'445374': 3},
        deviceId: 'd',
      ),
      throwsStateError,
    );
    await expectLater(
      store.saveCheckout(
        vesselId: 'vessel-2',
        items: {'445374': 1},
        deviceId: 'd',
      ),
      throwsStateError,
    );
    expect(await store.checkouts('vessel-1'), isEmpty);
    expect((await store.stock('vessel-1')).total, 2);
  });

  test('controller keeps device id and vessel, and limits the list', () async {
    final (repo, store) = await _open();
    await _deliveryNote(repo, vesselId: 'vessel-2', counted: {'445374': 3});
    final ctrl = SeastockController(store: store);
    await ctrl.init();
    expect(ctrl.ready, isTrue);
    expect(ctrl.vessel.id, 'vessel-1');
    expect(ctrl.stock.total, 0);

    await ctrl.selectVessel(ctrl.vessels[1]);
    expect(ctrl.stock.total, 3);
    ctrl.addToBasket('445374');
    ctrl.addToBasket('445374', 2);
    expect(() => ctrl.addToBasket('445374'), throwsStateError);
    expect(ctrl.available('445374'), 0);
    ctrl.setBasketQuantity('445374', 2);
    expect(ctrl.basketTotal, 2);
    final record = await ctrl.confirmCheckout();
    expect(record.total, 2);
    expect(ctrl.basket, isEmpty);
    expect(ctrl.stock.onBoard('445374'), 1);
    expect(ctrl.checkouts.single.reference, 'CO-0001');

    final again = SeastockController(store: store);
    await again.init();
    expect(again.vessel.id, 'vessel-2', reason: 'last vessel is remembered');
    expect(record.deviceId, isNotEmpty);
    expect(await store.readSetting('device_id'), record.deviceId);
  });

  test('changing vessel empties the check-out list', () async {
    final (repo, store) = await _open();
    await _deliveryNote(repo, vesselId: 'vessel-1', counted: {'445374': 3});
    final ctrl = SeastockController(store: store);
    await ctrl.init();
    ctrl.addToBasket('445374');
    await ctrl.selectVessel(ctrl.vessels[2]);
    expect(ctrl.basket, isEmpty);
  });

  test('check-ins list submitted delivery notes with their counts', () async {
    final (repo, store) = await _open();
    await _deliveryNote(
      repo,
      vesselId: 'vessel-1',
      counted: {'445374': 20, '445182': 3},
    );
    await _deliveryNote(
      repo,
      vesselId: 'vessel-1',
      counted: {'445235': 15},
      submit: false,
    );
    await _deliveryNote(repo, vesselId: 'vessel-2', counted: {'475210': 7});
    final checkIns = await store.checkIns('vessel-1');
    expect(checkIns, hasLength(1), reason: 'drafts are not check-ins');
    expect(checkIns.single.total, 23);
    expect(checkIns.single.lines.map((l) => l.articleNumber), [
      '445374',
      '445182',
    ]);
    expect((await store.checkIns('vessel-2')).single.total, 7);
  });

  test(
    'an audit report changes stock only once the manager approves it',
    () async {
      final (repo, store) = await _open();
      await _deliveryNote(
        repo,
        vesselId: 'vessel-1',
        counted: {'445374': 20, '445182': 3, '445377': 2},
      );
      final report = await store.saveAudit(
        vesselId: 'vessel-1',
        counted: {'445374': 18, '445182': 3, '445390': 2},
        deviceId: 'device-a',
      );
      expect(report.reference, 'AU-0001');
      expect(report.status, AuditStatus.waiting);
      expect(report.differences.map((l) => l.articleNumber), [
        '445374',
        '445390',
      ]);
      expect(report.matches.single.articleNumber, '445182');
      expect(report.notCounted.single.articleNumber, '445377');
      expect(report.lines.last.isFound, isTrue);
      expect(report.netDifference, 0);
      expect(
        (await store.stock('vessel-1')).total,
        25,
        reason: 'waiting for approval: stock unchanged',
      );

      await store.decideAudit(auditId: report.id, approved: true);
      final stock = await store.stock('vessel-1');
      expect(stock.onBoard('445374'), 18);
      expect(stock.onBoard('445390'), 2, reason: 'found cans added');
      expect(stock.onBoard('445377'), 2, reason: 'not counted stays');
      expect(stock.total, 25);
      expect(
        (await store.audits('vessel-1')).single.status,
        AuditStatus.approved,
      );
      await expectLater(
        store.decideAudit(auditId: report.id, approved: false),
        throwsStateError,
      );

      final second = await store.saveAudit(
        vesselId: 'vessel-1',
        counted: {'445374': 0},
        deviceId: 'device-a',
      );
      expect(second.reference, 'AU-0002');
      expect(second.lines.first.expected, 18, reason: 'from approved stock');
      await store.decideAudit(auditId: second.id, approved: false);
      expect((await store.stock('vessel-1')).onBoard('445374'), 18);
      expect((await store.audits('vessel-1')).map((a) => a.status), [
        AuditStatus.rejected,
        AuditStatus.approved,
      ]);
    },
  );

  test('an audit in progress is kept on the device per vessel', () async {
    final (repo, store) = await _open();
    await _deliveryNote(repo, vesselId: 'vessel-1', counted: {'445374': 4});
    final ctrl = SeastockController(store: store);
    await ctrl.init();
    await ctrl.startAudit();
    await ctrl.addAuditCan('445374');
    await ctrl.addAuditCan('445374');
    await ctrl.addAuditCan('999999');
    expect(ctrl.auditCountedArticles, 1);
    expect(ctrl.auditFound, ['999999']);

    final again = SeastockController(store: store);
    await again.init();
    expect(again.audit, {'445374': 2, '999999': 1});
    await again.selectVessel(again.vessels[1]);
    expect(again.audit, isNull, reason: 'other vessel has no audit');
    await again.selectVessel(again.vessels[0]);
    final report = await again.sendAudit();
    expect(report.lines.first.counted, 2);
    expect(again.audit, isNull);
    expect(again.waitingAudits, 1);
    expect(again.stock.onBoard('445374'), 4);
  });
}
