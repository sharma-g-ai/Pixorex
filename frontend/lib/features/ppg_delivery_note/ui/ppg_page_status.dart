import '../domain/models.dart';
import '../services/ppg_session_controller.dart';
import 'ppg_format.dart';
import 'ppg_tokens.dart';

/// What the operator should do next for one page slot.
enum PpgPageStep {
  capture,
  reading,
  fixReading,
  confirmIdentity,
  chooseReplacement,
  resolveRows,
  review,
  done,
}

/// The state of one printed page slot, described in operator words.
class PpgPageStatus {
  PpgPageStatus({
    required this.slot,
    required this.step,
    required this.badge,
    required this.tone,
    required this.title,
    required this.detail,
    this.page,
    this.pending,
  });

  final int slot;
  final PpgPageStep step;
  final String badge;
  final PpgTone tone;

  /// Issue headline, e.g. "Page 3: check one Total Qty".
  final String title;
  final String detail;
  final PageCapture? page;
  final PageCapture? pending;

  bool get needsAction => step != PpgPageStep.done;

  /// The capture a tap on this status should open.
  PageCapture? get target =>
      step == PpgPageStep.chooseReplacement ? pending : page;
}

int? ppgDeclaredPages(PpgSessionController ctrl) {
  final declared = ctrl.session?.declaredPageCount;
  if (declared != null) return declared;
  if (ctrl.pages.isEmpty) return null;
  return ctrl.pages
      .map((page) => page.printedPage)
      .reduce((a, b) => a > b ? a : b);
}

/// The first printed page that has no saved photo yet.
int ppgNextMissingPage(PpgSessionController ctrl) {
  final declared = ctrl.session?.declaredPageCount;
  final have = ctrl.pages.map((page) => page.printedPage).toSet();
  if (declared != null) {
    for (var i = 1; i <= declared; i++) {
      if (!have.contains(i)) return i;
    }
    return 1;
  }
  var next = 1;
  while (have.contains(next)) {
    next++;
  }
  return next;
}

bool ppgIdentityNeedsCheck(PpgSessionController ctrl, PageCapture page) {
  final declared = ctrl.session?.declaredPageCount;
  return !page.pageIdentityConfirmed ||
      page.verifiedDeliveryNoteNumber == null ||
      page.verifiedDeliveryNoteNumber != ctrl.session?.deliveryNoteNumber ||
      (declared != null &&
          ((page.verifiedDeclaredPageCount != null &&
                  page.verifiedDeclaredPageCount != declared) ||
              (page.verifiedDeclaredPageCount == null &&
                  page.suggestedDeclaredPageCount != null &&
                  page.suggestedDeclaredPageCount != declared)));
}

List<ParsedOccurrence> ppgUnresolvedRows(
  PpgSessionController ctrl,
  PageCapture page,
) => ctrl
    .parsedOccurrencesForPage(page.pageCaptureId)
    .where((item) => item.role == OccurrenceRole.unresolved)
    .toList();

PpgPageStatus ppgPageStatus(PpgSessionController ctrl, int slot) {
  final page = ctrl.pages.where((p) => p.printedPage == slot).firstOrNull;
  final pending = ctrl.pendingPages
      .where((p) => p.printedPage == slot)
      .firstOrNull;
  if (page == null) {
    return PpgPageStatus(
      slot: slot,
      step: PpgPageStep.capture,
      badge: 'No photo',
      tone: PpgTone.neutral,
      title: 'Page $slot: take a photo',
      detail: 'This page has not been photographed yet',
      pending: pending,
    );
  }
  if (pending != null) {
    return PpgPageStatus(
      slot: slot,
      step: PpgPageStep.chooseReplacement,
      badge: 'New photo',
      tone: PpgTone.warning,
      title: 'Page $slot: choose which photo to keep',
      detail: 'A newer photo is waiting. The earlier one is still saved.',
      page: page,
      pending: pending,
    );
  }
  switch (page.ocrStatus) {
    case PageOcrStatus.pending:
    case PageOcrStatus.running:
      return PpgPageStatus(
        slot: slot,
        step: PpgPageStep.reading,
        badge: 'Reading…',
        tone: PpgTone.info,
        title: 'Page $slot is being read',
        detail: 'This takes a few seconds',
        page: page,
      );
    case PageOcrStatus.failed:
      return PpgPageStatus(
        slot: slot,
        step: PpgPageStep.fixReading,
        badge: 'Not readable',
        tone: PpgTone.danger,
        title: 'Page $slot could not be read',
        detail: 'Adjust the crop or take the photo again',
        page: page,
      );
    case PageOcrStatus.succeeded:
      break;
  }
  if (ppgIdentityNeedsCheck(ctrl, page)) {
    return PpgPageStatus(
      slot: slot,
      step: PpgPageStep.confirmIdentity,
      badge: 'Confirm number',
      tone: PpgTone.warning,
      title: 'Page $slot: confirm delivery and page number',
      detail: 'Compare the numbers printed on the page with this DN',
      page: page,
    );
  }
  final unresolved = ppgUnresolvedRows(ctrl, page);
  if (unresolved.isNotEmpty) {
    return PpgPageStatus(
      slot: slot,
      step: PpgPageStep.resolveRows,
      badge: '${unresolved.length} to check',
      tone: PpgTone.warning,
      title: unresolved.length == 1
          ? 'Page $slot: check one Total Qty'
          : 'Page $slot: check ${unresolved.length} Total Qty values',
      detail: unresolved.length == 1
          ? 'Article ${unresolved.single.articleNumber} could not be read with certainty'
          : 'Some quantities could not be read with certainty',
      page: page,
    );
  }
  if (!page.pageReviewConfirmed) {
    return PpgPageStatus(
      slot: slot,
      step: PpgPageStep.review,
      badge: 'Not checked',
      tone: PpgTone.info,
      title: 'Page $slot: check the items read',
      detail: 'Compare each item with the paper',
      page: page,
    );
  }
  return PpgPageStatus(
    slot: slot,
    step: PpgPageStep.done,
    badge: 'Checked',
    tone: PpgTone.success,
    title: 'Page $slot checked',
    detail: '',
    page: page,
  );
}

/// Receiving lines in the order they are printed: by page, then by their
/// position on the page. Every screen lists items in this one order.
List<DocumentLine> ppgOrderedLines(
  PpgSessionController ctrl, [
  Iterable<DocumentLine>? subset,
]) {
  final position = <String, int>{};
  for (final page in ctrl.pages) {
    final parsed = ctrl.parsedOccurrencesForPage(page.pageCaptureId);
    for (var i = 0; i < parsed.length; i++) {
      position[parsed[i].occurrenceId] = i;
    }
  }
  final lines = (subset ?? ctrl.lines).toList();
  lines.sort((a, b) {
    final page = a.sourcePage.compareTo(b.sourcePage);
    if (page != 0) return page;
    final pa = position[a.occurrenceId] ?? 1 << 20;
    final pb = position[b.occurrenceId] ?? 1 << 20;
    if (pa != pb) return pa.compareTo(pb);
    return a.occurrenceId.compareTo(b.occurrenceId);
  });
  return lines;
}

/// Items and quantities read from one page, e.g. "4 items · 24 PC".
String ppgPageContentSummary(PpgSessionController ctrl, PageCapture page) {
  final rows = ctrl.lines.where((l) => l.pageCaptureId == page.pageCaptureId);
  if (rows.isEmpty) {
    return page.printedPage == 1 && page.effectivePieceCount != null
        ? 'Summary · ${page.effectivePieceCount} PC printed'
        : 'No items read';
  }
  final total = rows.fold<int>(0, (sum, line) => sum + line.documentQuantity);
  return '${ppgPlural(rows.length, 'item')} · $total PC';
}
