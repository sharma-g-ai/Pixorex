import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../domain/stock.dart';
import '../domain/vessels.dart';
import '../persistence/seastock_store.dart';

/// Stock on board for the chosen vessel, its check-ins, check-outs and audit
/// reports, the check-out list being built, and the audit being counted.
/// Nothing is deducted until [confirmCheckout]; an audit never changes stock
/// on this device, only the vessel manager's approval does.
class SeastockController extends ChangeNotifier {
  SeastockController({
    SeastockStore? store,
    this.vessels = seastockVessels,
    Uuid? uuid,
  }) : _store = store ?? SqliteSeastockStore(),
       _uuid = uuid ?? const Uuid(),
       vessel = vessels.first;

  static const _deviceKey = 'device_id';
  static const _vesselKey = 'selected_vessel_id';
  static String _auditKey(String vesselId) => 'audit_draft_$vesselId';

  final SeastockStore _store;
  final Uuid _uuid;
  final List<Vessel> vessels;

  bool ready = false;
  String? error;
  Vessel vessel;
  StockSnapshot stock = StockSnapshot.empty;
  List<CheckInRecord> checkIns = const [];
  List<CheckoutRecord> checkouts = const [];
  List<AuditRecord> audits = const [];
  String? operatorEmail;
  String? _deviceId;

  /// Article number → cans on the check-out being built, in the order added.
  final Map<String, int> basket = {};

  /// Article number → cans counted on the audit in progress, or null when no
  /// audit is in progress. Kept on the device so it can be resumed.
  Map<String, int>? audit;

  int get basketTotal => basket.values.fold(0, (sum, value) => sum + value);

  Future<void> init() async {
    try {
      error = null;
      await _store.init();
      _deviceId = await _store.readSetting(_deviceKey);
      if (_deviceId == null) {
        _deviceId = _uuid.v4();
        await _store.writeSetting(_deviceKey, _deviceId!);
      }
      final saved = await _store.readSetting(_vesselKey);
      vessel = vessels.where((v) => v.id == saved).firstOrNull ?? vessels.first;
      await _load();
      ready = true;
    } catch (failure) {
      ready = false;
      error = 'Stock could not be opened on this device.';
      debugPrint('Seastock init failed: $failure');
    }
    notifyListeners();
  }

  Future<void> refresh() async {
    await _load();
    notifyListeners();
  }

  Future<void> _load() async {
    stock = await _store.stock(vessel.id);
    checkIns = await _store.checkIns(vessel.id);
    checkouts = await _store.checkouts(vessel.id);
    audits = await _store.audits(vessel.id);
    final draft = await _store.readSetting(_auditKey(vessel.id));
    audit = draft == null
        ? null
        : (jsonDecode(draft) as Map<String, dynamic>).map(
            (article, count) => MapEntry(article, count as int),
          );
  }

  /// Stock on every vessel, for the vessel picker.
  Future<Map<String, StockSnapshot>> stockByVessel() async => {
    for (final v in vessels) v.id: await _store.stock(v.id),
  };

  Future<void> selectVessel(Vessel next) async {
    if (next.id == vessel.id) return;
    vessel = next;
    basket.clear();
    await _store.writeSetting(_vesselKey, next.id);
    await refresh();
  }

  String? productOf(String articleNumber) => stock.item(articleNumber)?.product;

  int get waitingAudits =>
      audits.where((report) => report.status == AuditStatus.waiting).length;

  // Check-out.

  /// Cans of the article on board that are not already on the check-out.
  int available(String articleNumber) =>
      stock.onBoard(articleNumber) - (basket[articleNumber] ?? 0);

  /// Adds cans to the check-out list. Throws if more than are on board.
  void addToBasket(String articleNumber, [int quantity = 1]) {
    if (quantity < 1) throw ArgumentError('Add at least one can.');
    final left = available(articleNumber);
    if (quantity > left) {
      throw StateError(
        left <= 0
            ? 'None of $articleNumber are left on board.'
            : 'Only $left more PC of $articleNumber are on board.',
      );
    }
    basket[articleNumber] = (basket[articleNumber] ?? 0) + quantity;
    notifyListeners();
  }

  /// Replaces an article's quantity on the list; zero removes it.
  void setBasketQuantity(String articleNumber, int quantity) {
    if (quantity < 0) throw ArgumentError('A quantity cannot be negative.');
    if (quantity > stock.onBoard(articleNumber)) {
      throw StateError(
        'Only ${stock.onBoard(articleNumber)} PC of $articleNumber are on board.',
      );
    }
    if (quantity == 0) {
      basket.remove(articleNumber);
    } else {
      basket[articleNumber] = quantity;
    }
    notifyListeners();
  }

  void clearBasket() {
    basket.clear();
    notifyListeners();
  }

  /// Deducts the whole list at once and records the check-out.
  Future<CheckoutRecord> confirmCheckout() async {
    final record = await _store.saveCheckout(
      vesselId: vessel.id,
      items: Map.of(basket),
      deviceId: _deviceId!,
      operatorEmail: operatorEmail,
    );
    basket.clear();
    await refresh();
    return record;
  }

  // Audit.

  /// The articles to count: everything the inventory has on board.
  List<StockItem> get auditList => stock.onBoardItems;

  /// Counted articles that are not on the inventory.
  List<String> get auditFound {
    final listed = auditList.map((item) => item.articleNumber).toSet();
    return [
      for (final article in (audit ?? const <String, int>{}).keys)
        if (!listed.contains(article)) article,
    ];
  }

  int get auditCountedArticles {
    final counts = audit ?? const <String, int>{};
    return auditList
        .where((item) => counts.containsKey(item.articleNumber))
        .length;
  }

  Future<void> startAudit() async {
    audit = {};
    await _saveAudit();
  }

  /// Adds one can, e.g. for a confirmed scan.
  Future<void> addAuditCan(String articleNumber) =>
      setAuditCount(articleNumber, (audit?[articleNumber] ?? 0) + 1);

  /// Sets the counted figure for an article; counting 0 is a real count.
  Future<void> setAuditCount(String articleNumber, int count) async {
    if (count < 0) throw ArgumentError('A count cannot be negative.');
    final counts = audit;
    if (counts == null) throw StateError('Start an audit first.');
    counts[articleNumber] = count;
    await _saveAudit();
  }

  /// Takes an article back off the count, e.g. a can scanned by mistake.
  Future<void> clearAuditCount(String articleNumber) async {
    audit?.remove(articleNumber);
    await _saveAudit();
  }

  Future<void> discardAudit() async {
    audit = null;
    await _saveAudit();
  }

  /// Sends the count to the vessel manager as a report. Stock is unchanged.
  Future<AuditRecord> sendAudit() async {
    final counts = audit;
    if (counts == null) throw StateError('Start an audit first.');
    final record = await _store.saveAudit(
      vesselId: vessel.id,
      counted: Map.of(counts),
      deviceId: _deviceId!,
      operatorEmail: operatorEmail,
    );
    audit = null;
    await _store.deleteSetting(_auditKey(vessel.id));
    await refresh();
    return record;
  }

  Future<void> _saveAudit() async {
    final counts = audit;
    if (counts == null) {
      await _store.deleteSetting(_auditKey(vessel.id));
    } else {
      await _store.writeSetting(_auditKey(vessel.id), jsonEncode(counts));
    }
    notifyListeners();
  }
}
