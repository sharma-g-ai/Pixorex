import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/models.dart';
import '../services/ppg_session_controller.dart';
import '../ui/ppg_format.dart';
import '../ui/ppg_navigation.dart';
import '../ui/ppg_page_status.dart';
import '../ui/ppg_tokens.dart';
import '../ui/ppg_widgets.dart';
import '../widgets/ppg_physical_quantity_control.dart';
import 'ppg_can_scanner_screen.dart';
import 'ppg_final_review_screen.dart';
import 'ppg_session_screen.dart';

enum _CountFilter { all, toCount, counting, verified, differences }

/// Stage 2 · Count: count the stock that arrived against the checked DN.
class PpgReviewScreen extends StatefulWidget {
  const PpgReviewScreen({super.key});

  @override
  State<PpgReviewScreen> createState() => _PpgReviewScreenState();
}

class _PpgReviewScreenState extends State<PpgReviewScreen> {
  final _search = TextEditingController();
  bool _searching = false;
  _CountFilter _filter = _CountFilter.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(_CountFilter filter, DocumentLine line) => switch (filter) {
    _CountFilter.all => true,
    _CountFilter.toCount =>
      line.physicalCountState == PhysicalCountState.notChecked ||
          line.physicalCountState == PhysicalCountState.recheck ||
          line.needsArticleReconciliation,
    _CountFilter.counting =>
      line.physicalCountState == PhysicalCountState.counting &&
          !line.needsArticleReconciliation,
    _CountFilter.verified => line.isPhysicalVerified,
    _CountFilter.differences => line.isPhysicalVerified && line.variance != 0,
  };

  String _filterLabel(_CountFilter filter) => switch (filter) {
    _CountFilter.all => 'All',
    _CountFilter.toCount => 'To count',
    _CountFilter.counting => 'Counting',
    _CountFilter.verified => 'Verified',
    _CountFilter.differences => 'Differences',
  };

  @override
  Widget build(BuildContext context) {
    return Consumer<PpgSessionController>(
      builder: (context, ctrl, _) {
        final s = ctrl.session;
        final readOnly = s?.isSubmitted == true;
        final query = _search.text.trim().toLowerCase();
        final rows = ppgOrderedLines(
          ctrl,
          ctrl.lines.where(
            (line) =>
                _matches(_filter, line) &&
                (query.isEmpty ||
                    line.articleNumber.contains(query) ||
                    (line.productContext?.toLowerCase().contains(query) ??
                        false)),
          ),
        );
        return PpgThemed(
          child: PopScope(
            canPop: !ctrl.savingPhysicalCounts,
            child: Scaffold(
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PpgHeader(
                    eyebrow: 'Delivery note',
                    title: s?.deliveryNoteNumber ?? '—',
                    monoTitle: true,
                    stage: 1,
                    completedStages: {
                      if (ctrl.sourceReviewReady) 0,
                      if (readOnly) 1,
                    },
                    backTooltip: 'Back to Delivery notes',
                    onStageTap: (stage) => _openStage(ctrl, stage),
                  ),
                  _summary(ctrl, readOnly),
                  _filters(ctrl),
                  if (_searching)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: TextField(
                        controller: _search,
                        autofocus: true,
                        onChanged: (_) => setState(() {}),
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          hintText: 'Article number or product',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: IconButton(
                            tooltip: 'Close search',
                            onPressed: () => setState(() {
                              _search.clear();
                              _searching = false;
                            }),
                            icon: const Icon(Icons.close),
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      children: [
                        if (rows.isEmpty)
                          PpgEmptyState(
                            icon: Icons.inventory_2_outlined,
                            title: 'No items in this view',
                            message: query.isNotEmpty
                                ? 'No article matches "$query".'
                                : 'Choose another filter to see more items.',
                            action: TextButton(
                              onPressed: () => setState(() {
                                _filter = _CountFilter.all;
                                _search.clear();
                                _searching = false;
                              }),
                              child: const Text('Show all items'),
                            ),
                          )
                        else
                          PpgPanel(
                            child: Column(
                              children: ppgDivided(
                                rows.map((line) => _lineRow(ctrl, line)),
                              ),
                            ),
                          ),
                        if (ctrl.contexts.isNotEmpty) ...[
                          const SizedBox(height: PpgSpace.m),
                          PpgHint(
                            '${ppgPlural(ctrl.contexts.length, 'heading')} on the DN have no printed quantity and are not counted.',
                            center: false,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              bottomNavigationBar: PpgBottomBar(
                children: [_bottomAction(ctrl, readOnly)],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Every item has a finished count, so the next step is the final review.
  bool _allCounted(PpgSessionController ctrl) =>
      ctrl.lines.isNotEmpty && ctrl.verifiedPhysicalCount == ctrl.lines.length;

  void _openStage(PpgSessionController ctrl, int stage) {
    final id = ctrl.session?.id;
    if (id == null || ctrl.savingPhysicalCounts) return;
    if (stage == 0) {
      ppgPush<void>(
        context,
        ctrl,
        PpgSessionScreen(sessionId: id, openedFromCount: true),
      );
    } else if (stage == 2) {
      ppgPush<void>(context, ctrl, const PpgFinalReviewScreen());
    }
  }

  Widget _bottomAction(PpgSessionController ctrl, bool readOnly) {
    const height = 56.0;
    if (readOnly) {
      return FilledButton(
        onPressed: () =>
            ppgPush<void>(context, ctrl, const PpgFinalReviewScreen()),
        child: const Text('View submitted form'),
      );
    }
    final canScan = ctrl.sourceReviewReady && !ctrl.savingPhysicalCounts;
    if (ctrl.sourceReviewReady && _allCounted(ctrl)) {
      return Row(
        children: [
          IconButton.outlined(
            key: const ValueKey('ppg-scan-can-button'),
            tooltip: 'Scan another can',
            style: IconButton.styleFrom(
              fixedSize: const Size.square(height),
              foregroundColor: PpgColors.link,
              side: const BorderSide(color: PpgColors.blue, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: canScan ? () => _scanCan(ctrl) : null,
            icon: const Icon(Icons.qr_code_scanner),
          ),
          const SizedBox(width: PpgSpace.m),
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(height),
                textStyle: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              iconAlignment: IconAlignment.end,
              onPressed: ctrl.readyForFinalReview
                  ? () => ppgPush<void>(
                      context,
                      ctrl,
                      const PpgFinalReviewScreen(),
                    )
                  : null,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Review and submit'),
            ),
          ),
        ],
      );
    }
    return FilledButton.icon(
      key: const ValueKey('ppg-scan-can-button'),
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(height),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      ),
      onPressed: canScan ? () => _scanCan(ctrl) : null,
      icon: const Icon(Icons.qr_code_scanner),
      label: const Text('Scan a can'),
    );
  }

  Widget _summary(PpgSessionController ctrl, bool readOnly) {
    final docTotal = ctrl.documentQuantityTotal;
    final counted = ctrl.countedPhysicalTotal;
    final allCounted = _allCounted(ctrl);
    final toGo = docTotal - counted;
    final openItems = ctrl.lines.length - ctrl.verifiedPhysicalCount;
    final Widget status = allCounted
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check, size: 16, color: PpgTone.success.foreground),
              const SizedBox(width: PpgSpace.xs),
              Text(
                'All counted',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: PpgTone.success.foreground,
                ),
              ),
            ],
          )
        : Text(
            toGo > 0
                ? '$toGo to go'
                : '${ppgPlural(openItems, 'item')} to finish',
            style: PpgText.figures(size: 14, color: PpgTone.info.foreground),
          );
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: PpgColors.line)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: const TextStyle(
                      fontSize: 15,
                      color: PpgColors.textSecondary,
                    ),
                    children: [
                      TextSpan(
                        text: '$counted',
                        style: PpgText.figures(size: 20, color: PpgColors.navy),
                      ),
                      TextSpan(text: ' of $docTotal PC counted'),
                    ],
                  ),
                ),
              ),
              status,
            ],
          ),
          const SizedBox(height: PpgSpace.s),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: docTotal == 0 ? 0 : (counted / docTotal).clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: PpgColors.divider,
              color: allCounted ? PpgColors.progressDone : PpgColors.blue,
              semanticsLabel: 'Pieces counted: $counted of $docTotal',
            ),
          ),
          if (!readOnly && !ctrl.sourceReviewReady) ...[
            const SizedBox(height: PpgSpace.m),
            PpgBanner(
              tone: PpgTone.warning,
              title: 'Finish the document checks first',
              message: [
                ...ctrl.sourceReviewIssues.take(3),
                if (ctrl.sourceReviewIssues.length > 3)
                  'and ${ctrl.sourceReviewIssues.length - 3} more',
              ].join('\n'),
              action: TextButton(
                onPressed: () {
                  final id = ctrl.session?.id;
                  if (id == null) return;
                  ppgPush<void>(
                    context,
                    ctrl,
                    PpgSessionScreen(sessionId: id, openedFromCount: true),
                  );
                },
                child: const Text('Go to pages'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _filters(PpgSessionController ctrl) {
    final counts = {
      for (final filter in _CountFilter.values)
        filter: ctrl.lines.where((line) => _matches(filter, line)).length,
    };
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        children: [
          IconButton.outlined(
            tooltip: 'Search articles',
            style: IconButton.styleFrom(
              backgroundColor: Colors.white,
              side: const BorderSide(color: PpgColors.control),
            ),
            onPressed: () => setState(() => _searching = !_searching),
            icon: const Icon(Icons.search, size: 18),
          ),
          for (final filter in _CountFilter.values)
            if (filter != _CountFilter.differences || counts[filter]! > 0) ...[
              const SizedBox(width: PpgSpace.s),
              ChoiceChip(
                label: Text('${_filterLabel(filter)} ${counts[filter]}'),
                selected: _filter == filter,
                showCheckmark: false,
                selectedColor: PpgColors.navy,
                backgroundColor: Colors.white,
                side: const BorderSide(color: PpgColors.control),
                labelStyle: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _filter == filter ? Colors.white : PpgColors.navy,
                ),
                shape: const StadiumBorder(),
                onSelected: (_) => setState(() => _filter = filter),
              ),
            ],
        ],
      ),
    );
  }

  Widget _lineRow(PpgSessionController ctrl, DocumentLine line) {
    final status = ppgCountStatus(line);
    final counted = line.hasPhysicalCount ? line.physicalQuantity : 0;
    return PpgRow(
      key: ValueKey(line.occurrenceId),
      title: line.articleNumber,
      monoTitle: true,
      subtitle: [
        if (line.productContext != null) line.productContext!,
        'page ${line.sourcePage}',
      ].join(' · '),
      highlight: line.physicalCountState == PhysicalCountState.counting
          ? const Color(0xFFF5F9FF)
          : null,
      showChevron: false,
      semanticLabel:
          'Article ${line.articleNumber}, $counted of ${line.documentQuantity} ${line.unit}, ${status.label}',
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text.rich(
            TextSpan(
              style: PpgText.figures(size: 15),
              children: [
                TextSpan(text: '$counted'),
                TextSpan(
                  text: ' / ${line.documentQuantity} ${line.unit}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w400,
                    color: PpgColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          PpgStatusBadge(label: status.label, tone: status.tone, compact: true),
        ],
      ),
      onTap: ctrl.savingPhysicalCounts && !line.hasPhysicalCount
          ? null
          : () => _openCount(ctrl, line),
    );
  }

  Future<void> _openCount(PpgSessionController ctrl, DocumentLine line) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (sheetContext) => PpgThemed(
        child: PpgCountSheet(
          controller: ctrl,
          occurrenceId: line.occurrenceId,
          onScan: () {
            Navigator.pop(sheetContext);
            _scanCan(ctrl, occurrenceId: line.occurrenceId);
          },
        ),
      ),
    );
  }

  Future<void> _scanCan(
    PpgSessionController ctrl, {
    String? occurrenceId,
  }) async {
    await ctrl.waitForPhysicalCounts();
    if (!mounted ||
        !ctrl.sourceReviewReady ||
        ctrl.session?.isSubmitted == true) {
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            PpgCanScannerScreen(controller: ctrl, occurrenceId: occurrenceId),
      ),
    );
  }
}
