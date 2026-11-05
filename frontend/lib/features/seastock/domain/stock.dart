/// One article's stock on a vessel, added up from the records: verified counts
/// on submitted delivery notes, minus confirmed check-outs, plus differences
/// from audit reports the vessel manager approved.
class StockItem {
  const StockItem({
    required this.articleNumber,
    required this.checkedIn,
    required this.checkedOut,
    this.audited = 0,
    this.product,
  });

  final String articleNumber;
  final String? product;
  final int checkedIn;
  final int checkedOut;

  /// Net change from approved audits (counted − expected), may be negative.
  final int audited;

  int get onBoard => checkedIn - checkedOut + audited;
}

class StockSnapshot {
  const StockSnapshot({this.items = const [], this.lastChange});

  static const empty = StockSnapshot();

  /// Articles ever checked in on the vessel, most cans on board first.
  final List<StockItem> items;

  /// When stock on the vessel last changed.
  final DateTime? lastChange;

  int get total => items.fold(0, (sum, item) => sum + item.onBoard);
  int get articlesOnBoard => items.where((item) => item.onBoard > 0).length;

  /// Articles with at least one can on board, most cans first.
  List<StockItem> get onBoardItems =>
      items.where((item) => item.onBoard > 0).toList();

  StockItem? item(String articleNumber) =>
      items.where((item) => item.articleNumber == articleNumber).firstOrNull;
  int onBoard(String articleNumber) => item(articleNumber)?.onBoard ?? 0;
}

class CheckoutLine {
  const CheckoutLine({
    required this.articleNumber,
    required this.quantity,
    required this.onBoardBefore,
    this.product,
  });

  final String articleNumber;
  final String? product;
  final int quantity;

  /// Stock on board just before this check-out was confirmed.
  final int onBoardBefore;

  int get onBoardAfter => onBoardBefore - quantity;
}

/// A confirmed check-out. Saved once and never changed.
class CheckoutRecord {
  const CheckoutRecord({
    required this.id,
    required this.vesselId,
    required this.reference,
    required this.deviceId,
    required this.createdAt,
    required this.lines,
    this.operatorEmail,
  });

  final String id;
  final String vesselId;

  /// Short reference shown to operators, e.g. CO-0002.
  final String reference;
  final String deviceId;
  final String? operatorEmail;
  final DateTime createdAt;
  final List<CheckoutLine> lines;

  int get total => lines.fold(0, (sum, line) => sum + line.quantity);
}

class CheckInLine {
  const CheckInLine({
    required this.articleNumber,
    required this.quantity,
    this.product,
  });

  final String articleNumber;
  final String? product;
  final int quantity;
}

/// A submitted delivery note, as it added stock to the vessel.
class CheckInRecord {
  const CheckInRecord({
    required this.sessionId,
    required this.submittedAt,
    required this.lines,
    this.deliveryNoteNumber,
    this.operatorEmail,
  });

  final String sessionId;
  final String? deliveryNoteNumber;
  final String? operatorEmail;
  final DateTime submittedAt;
  final List<CheckInLine> lines;

  int get total => lines.fold(0, (sum, line) => sum + line.quantity);
}

enum AuditStatus { waiting, approved, rejected }

class AuditLine {
  const AuditLine({
    required this.articleNumber,
    required this.expected,
    this.counted,
    this.product,
  });

  final String articleNumber;
  final String? product;

  /// Cans counted on board, or null when the article was not counted.
  final int? counted;

  /// What the inventory said when the report was sent.
  final int expected;

  bool get isCounted => counted != null;
  int get difference => isCounted ? counted! - expected : 0;

  /// Counted, but never on this vessel's inventory.
  bool get isFound => isCounted && expected == 0 && counted! > 0;
}

/// A blind count sent to the vessel manager. It changes stock only once an
/// approving decision is recorded for it.
class AuditRecord {
  const AuditRecord({
    required this.id,
    required this.vesselId,
    required this.reference,
    required this.deviceId,
    required this.createdAt,
    required this.lines,
    this.operatorEmail,
    this.status = AuditStatus.waiting,
    this.decidedAt,
  });

  final String id;
  final String vesselId;

  /// Short reference shown to operators, e.g. AU-0002.
  final String reference;
  final String deviceId;
  final String? operatorEmail;
  final DateTime createdAt;
  final List<AuditLine> lines;
  final AuditStatus status;
  final DateTime? decidedAt;

  List<AuditLine> get differences =>
      lines.where((line) => line.difference != 0).toList();
  List<AuditLine> get matches =>
      lines.where((line) => line.isCounted && line.difference == 0).toList();
  List<AuditLine> get notCounted =>
      lines.where((line) => !line.isCounted).toList();
  int get netDifference => lines.fold(0, (sum, line) => sum + line.difference);
}
