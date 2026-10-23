import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:label_reader/features/seastock/domain/stock.dart';
import 'package:label_reader/features/seastock/persistence/seastock_store.dart';
import 'package:label_reader/features/seastock/screens/stock_home_screen.dart';
import 'package:label_reader/features/seastock/services/seastock_controller.dart';

/// In-memory store with the same rules as the SQLite one.
class _FakeStore implements SeastockStore {
  _FakeStore(this.checkedIn);

  /// vessel id → article → cans checked in on submitted delivery notes.
  final Map<String, Map<String, int>> checkedIn;
  final settings = <String, String>{};
  final saved = <CheckoutRecord>[];
  final reports = <AuditRecord>[];

  @override
  Future<void> init() async {}
  @override
  Future<String?> readSetting(String key) async => settings[key];
  @override
  Future<void> writeSetting(String key, String value) async =>
      settings[key] = value;
  @override
  Future<void> deleteSetting(String key) async => settings.remove(key);

  @override
  Future<StockSnapshot> stock(String vesselId) async {
    final ins = checkedIn[vesselId] ?? {};
    final outs = <String, int>{};
    for (final record in saved.where((r) => r.vesselId == vesselId)) {
      for (final line in record.lines) {
        outs[line.articleNumber] =
            (outs[line.articleNumber] ?? 0) + line.quantity;
      }
    }
    final items = [
      for (final article in ins.keys)
        StockItem(
          articleNumber: article,
          product: 'Product $article',
          checkedIn: ins[article]!,
          checkedOut: outs[article] ?? 0,
        ),
    ]..sort((a, b) => b.onBoard.compareTo(a.onBoard));
    return StockSnapshot(
      items: items,
      lastChange: ins.isEmpty ? null : DateTime(2026, 10, 10, 16, 15),
    );
  }

  @override
  Future<List<CheckInRecord>> checkIns(String vesselId) async {
    final ins = checkedIn[vesselId] ?? {};
    if (ins.isEmpty) return const [];
    return [
      CheckInRecord(
        sessionId: 'dn-$vesselId',
        deliveryNoteNumber: '5319364114',
        submittedAt: DateTime.now().subtract(const Duration(days: 2)),
        lines: [
          for (final entry in ins.entries)
            CheckInLine(articleNumber: entry.key, quantity: entry.value),
        ],
      ),
    ];
  }

  @override
  Future<List<CheckoutRecord>> checkouts(String vesselId) async =>
      saved.where((r) => r.vesselId == vesselId).toList().reversed.toList();

  @override
  Future<List<AuditRecord>> audits(String vesselId) async =>
      reports.where((r) => r.vesselId == vesselId).toList().reversed.toList();

  @override
  Future<CheckoutRecord> saveCheckout({
    required String vesselId,
    required Map<String, int> items,
    required String deviceId,
    String? operatorEmail,
  }) async {
    final current = await stock(vesselId);
    final lines = [
      for (final entry in items.entries)
        if (entry.value > current.onBoard(entry.key))
          throw StateError('Not enough on board')
        else
          CheckoutLine(
            articleNumber: entry.key,
            product: 'Product ${entry.key}',
            quantity: entry.value,
            onBoardBefore: current.onBoard(entry.key),
          ),
    ];
    final record = CheckoutRecord(
      id: 'co-${saved.length + 1}',
      vesselId: vesselId,
      reference: 'CO-${(saved.length + 1).toString().padLeft(4, '0')}',
      deviceId: deviceId,
      createdAt: DateTime.now().toUtc(),
      lines: lines,
    );
    saved.add(record);
    return record;
  }

  @override
  Future<AuditRecord> saveAudit({
    required String vesselId,
    required Map<String, int> counted,
    required String deviceId,
    String? operatorEmail,
  }) async {
    final current = await stock(vesselId);
    final listed = current.onBoardItems;
    final record = AuditRecord(
      id: 'au-${reports.length + 1}',
      vesselId: vesselId,
      reference: 'AU-${(reports.length + 1).toString().padLeft(4, '0')}',
      deviceId: deviceId,
      createdAt: DateTime.now().toUtc(),
      lines: [
        for (final item in listed)
          AuditLine(
            articleNumber: item.articleNumber,
            product: item.product,
            counted: counted[item.articleNumber],
            expected: item.onBoard,
          ),
        for (final entry in counted.entries)
          if (!listed.any((item) => item.articleNumber == entry.key))
            AuditLine(
              articleNumber: entry.key,
              counted: entry.value,
              expected: 0,
            ),
      ],
    );
    reports.add(record);
    return record;
  }

  @override
  Future<void> decideAudit({
    required String auditId,
    required bool approved,
    String? decidedBy,
  }) async {}
}

Future<SeastockController> _pumpHome(
  WidgetTester tester,
  _FakeStore store,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final ctrl = SeastockController(store: store);
  await ctrl.init();
  await tester.pumpWidget(MaterialApp(home: StockHomeScreen(controller: ctrl)));
  await tester.pumpAndSettle();
  return ctrl;
}

/// Scanner test path: tests have no camera, so the article is chosen by
/// hand, which adds one can just like a scan.
Future<void> _chooseByHand(
  WidgetTester tester,
  String key,
  String article,
) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('pick-$article')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('home shows stock and the three records for the vessel', (
    tester,
  ) async {
    final store = _FakeStore({
      'vessel-1': {'445374': 20, '445182': 3},
      'vessel-2': {'475210': 7},
    });
    await _pumpHome(tester, store);
    expect(find.text('STOCK ON BOARD'), findsOneWidget);
    expect(find.text('2 articles'), findsOneWidget);
    expect(find.text('Inventory'), findsOneWidget);
    expect(find.text('Transactions'), findsOneWidget);
    expect(find.text('Audit'), findsOneWidget);
    expect(find.text('Count what is on board'), findsOneWidget);
    expect(find.text('Check in'), findsOneWidget);
    expect(find.text('Check out'), findsOneWidget);
    expect(find.text('Vessel 1'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('seastock-vessel')));
    await tester.pumpAndSettle();
    expect(find.text('Choose vessel'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('vessel-vessel-2')));
    await tester.pumpAndSettle();
    expect(find.text('Vessel 2'), findsOneWidget);
    expect(find.text('1 article'), findsOneWidget);
    expect(store.settings['selected_vessel_id'], 'vessel-2');

    await tester.tap(find.byKey(const ValueKey('seastock-vessel')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('vessel-vessel-3')));
    await tester.pumpAndSettle();
    expect(find.textContaining('No stock on Vessel 3 yet'), findsOneWidget);
    expect(find.text('Nothing on board'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('inventory lists label names and searches name or number', (
    tester,
  ) async {
    final store = _FakeStore({
      'vessel-1': {'445374': 20, '445182': 3},
    });
    await _pumpHome(tester, store);
    await tester.tap(find.byKey(const ValueKey('seastock-inventory')));
    await tester.pumpAndSettle();
    expect(find.text('2 ARTICLES'), findsOneWidget);
    expect(find.text('Product 445374'), findsOneWidget);
    expect(find.text('445374'), findsOneWidget);
    expect(find.byTooltip('Colour not on the master list'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('inventory-search')),
      'product 4451',
    );
    await tester.pumpAndSettle();
    expect(find.text('1 ARTICLE MATCH'), findsOneWidget);
    expect(find.text('Product 445182'), findsOneWidget);
    expect(find.text('Product 445374'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('inventory-search')),
      '445374',
    );
    await tester.pumpAndSettle();
    expect(find.text('Product 445374'), findsOneWidget);

    await tester.tap(find.text('Product 445374'));
    await tester.pumpAndSettle();
    expect(find.text('Inventory'), findsOneWidget, reason: 'rows do nothing');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'check out opens the scanner, a pick adds one, deducts on confirm',
    (tester) async {
      final store = _FakeStore({
        'vessel-1': {'445374': 20, '445182': 3},
      });
      final ctrl = await _pumpHome(tester, store);

      await tester.tap(find.byKey(const ValueKey('seastock-check-out')));
      await tester.pumpAndSettle();
      expect(find.text('Checking out · Vessel 1'), findsOneWidget);
      expect(
        find.textContaining('Can scanning works on Android devices only'),
        findsOneWidget,
      );

      await _chooseByHand(tester, 'seastock-choose-by-hand', '445374');
      expect(find.text('Added 1 can · in stock'), findsOneWidget);
      expect(ctrl.basket, {'445374': 1});
      expect(find.text('19 left after'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('counter-plus')));
      await tester.pumpAndSettle();
      expect(ctrl.basket, {'445374': 2});
      expect(ctrl.stock.onBoard('445374'), 20, reason: 'nothing deducted yet');
      await tester.tap(find.byKey(const ValueKey('seastock-scan-next')));
      await tester.pumpAndSettle();
      expect(
        find.text('2 × 445374 on this check-out. Scan the next can.'),
        findsOneWidget,
      );

      // A wrong pick is undone.
      await _chooseByHand(tester, 'seastock-choose-by-hand', '445182');
      expect(ctrl.basket['445182'], 1);
      await tester.tap(find.byKey(const ValueKey('seastock-undo')));
      await tester.pumpAndSettle();
      expect(ctrl.basket.containsKey('445182'), isFalse);

      // Typing a number.
      await _chooseByHand(tester, 'seastock-choose-by-hand', '445182');
      await tester.tap(find.byKey(const ValueKey('counter-value')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('counter-field')), '3');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(ctrl.basket, {'445374': 2, '445182': 3});
      expect(find.text('0 left after'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('seastock-scan-next')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('seastock-review')));
      await tester.pumpAndSettle();
      expect(find.text('Review this check-out'), findsOneWidget);
      expect(find.text('Check out 5 PC'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('seastock-confirm-checkout')));
      await tester.pumpAndSettle();
      expect(find.text('5 PC checked out'), findsOneWidget);
      expect(ctrl.stock.onBoard('445374'), 18);
      expect(ctrl.stock.onBoard('445182'), 0);
      expect(store.saved.single.reference, 'CO-0001');

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('STOCK ON BOARD'), findsOneWidget);
      expect(find.textContaining('Latest: check-out CO-0001'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('seastock-transactions')));
      await tester.pumpAndSettle();
      expect(find.text('1 CHECK-IN'), findsOneWidget);
      expect(find.text('+23 PC'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tab-checkOuts')));
      await tester.pumpAndSettle();
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('−5 PC in total'), findsOneWidget);
      await tester.tap(find.text('Check-out CO-0001'));
      await tester.pumpAndSettle();
      expect(find.textContaining('on board 20 → 18'), findsOneWidget);
      await tester.tap(find.byTooltip('Back to Transactions'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('transactions-dates')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('dates-today')));
      await tester.pumpAndSettle();
      expect(find.text('Check-out CO-0001'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tab-checkIns')));
      await tester.pumpAndSettle();
      expect(find.text('No check-ins in these dates'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('leaving the scanner with a list asks first', (tester) async {
    final store = _FakeStore({
      'vessel-1': {'445374': 2},
    });
    final ctrl = await _pumpHome(tester, store);
    await tester.tap(find.byKey(const ValueKey('seastock-check-out')));
    await tester.pumpAndSettle();
    await _chooseByHand(tester, 'seastock-choose-by-hand', '445374');

    await tester.tap(find.byTooltip('Close check-out'));
    await tester.pumpAndSettle();
    expect(find.text('Discard this check-out?'), findsOneWidget);
    await tester.tap(find.text('Keep scanning'));
    await tester.pumpAndSettle();
    expect(ctrl.basketTotal, 1);
    await tester.tap(find.byTooltip('Close check-out'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(ctrl.basket, isEmpty);
    expect(find.text('STOCK ON BOARD'), findsOneWidget, reason: 'back home');
    expect(store.saved, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('audit is a blind count sent for approval, stock unchanged', (
    tester,
  ) async {
    final store = _FakeStore({
      'vessel-1': {'445374': 20, '445182': 3, '445377': 2},
    });
    final ctrl = await _pumpHome(tester, store);
    await tester.tap(find.byKey(const ValueKey('seastock-audit')));
    await tester.pumpAndSettle();
    expect(find.text('No audits yet on this vessel.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('audit-start')));
    await tester.pumpAndSettle();
    expect(find.text('Count list'), findsOneWidget);
    expect(
      find.text('0 of 3 articles counted · 3 to go', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('20'), findsNothing, reason: 'expected stays hidden');

    // By hand, from the list.
    await tester.tap(find.byKey(const ValueKey('audit-count-445374')));
    await tester.pumpAndSettle();
    expect(find.text('Count this article'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('counter-value')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('counter-field')), '18');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('audit-count-save')));
    await tester.pumpAndSettle();
    expect(ctrl.audit, {'445374': 18});

    // With the scanner: a pick adds one.
    await tester.tap(find.byKey(const ValueKey('audit-scan')));
    await tester.pumpAndSettle();
    expect(find.text('Auditing · Vessel 1'), findsOneWidget);
    await _chooseByHand(tester, 'audit-choose-by-hand', '445182');
    expect(find.text('Added 1 can · on the count list'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('counter-plus')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('counter-plus')));
    await tester.pumpAndSettle();
    expect(ctrl.audit!['445182'], 3);
    expect(find.text('3'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('audit-scan-next')));
    await tester.pumpAndSettle();
    expect(find.text('2/3'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('audit-tray')));
    await tester.pumpAndSettle();
    expect(
      find.text('2 of 3 articles counted · 1 to go', findRichText: true),
      findsOneWidget,
    );

    // The count is kept if the crew leaves.
    await tester.tap(find.byTooltip('Leave audit. Your count is kept'));
    await tester.pumpAndSettle();
    expect(find.text('Resume audit'), findsOneWidget);
    expect(store.settings.keys, contains('audit_draft_vessel-1'));
    await tester.tap(find.byKey(const ValueKey('audit-start')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('audit-finish')));
    await tester.pumpAndSettle();
    expect(find.text('Compare with inventory'), findsOneWidget);
    expect(find.text('DIFFERENCES · 1'), findsOneWidget);
    expect(find.textContaining('inventory 20 → counted 18'), findsOneWidget);
    expect(find.text('NOT COUNTED · 1'), findsOneWidget);
    expect(find.textContaining('1 article match'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('audit-send')));
    await tester.pumpAndSettle();
    expect(find.text('Sent to the vessel manager'), findsOneWidget);
    expect(find.text('Waiting for approval'), findsOneWidget);
    expect(find.text('Inventory not changed yet'), findsOneWidget);
    expect(store.reports.single.reference, 'AU-0001');
    expect(ctrl.stock.onBoard('445374'), 20, reason: 'stock unchanged');
    expect(ctrl.audit, isNull);

    await tester.tap(find.byKey(const ValueKey('audit-done')));
    await tester.pumpAndSettle();
    expect(find.text('1 report waiting for approval'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
