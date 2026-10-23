import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/models.dart';
import '../services/ppg_session_controller.dart';
import '../ui/ppg_format.dart';
import '../ui/ppg_navigation.dart';
import '../ui/ppg_page_status.dart';
import '../ui/ppg_tokens.dart';
import '../ui/ppg_widgets.dart';
import '../widgets/ppg_source_summary.dart';
import 'ppg_capture_screen.dart';
import 'ppg_confirmation_screen.dart';
import 'ppg_page_identity_screen.dart';
import 'ppg_page_review_screen.dart';
import 'ppg_review_screen.dart';

/// Stage 1 · Document: photograph every DN page and check what was read.
class PpgSessionScreen extends StatefulWidget {
  const PpgSessionScreen({
    super.key,
    required this.sessionId,
    this.reviewCaptureId,
    this.openedFromCount = false,
  });

  final String sessionId;

  /// A capture that was just saved and still needs its page number confirmed.
  final String? reviewCaptureId;

  /// True when the count list opened this checklist; continuing pops back.
  final bool openedFromCount;

  @override
  State<PpgSessionScreen> createState() => _PpgSessionScreenState();
}

class _PpgSessionScreenState extends State<PpgSessionScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ctrl = context.read<PpgSessionController>();
      if (ctrl.session?.id != widget.sessionId) {
        await ctrl.loadSession(widget.sessionId);
      }
      final pending = widget.reviewCaptureId;
      if (pending != null && mounted) await _afterCapture(ctrl, pending);
    });
  }

  Future<void> _capture(PpgSessionController ctrl, {int? slot}) async {
    final captureId = await ppgPush<String>(
      context,
      ctrl,
      PpgCaptureScreen(initialPage: slot),
    );
    if (captureId == null || !mounted) return;
    await _afterCapture(ctrl, captureId);
  }

  /// Confirms the page number of a new photo, then settles replacements.
  Future<void> _afterCapture(
    PpgSessionController ctrl,
    String captureId,
  ) async {
    final outcome = await ppgPush<PpgIdentityOutcome>(
      context,
      ctrl,
      PpgPageIdentityScreen(pageCaptureId: captureId),
    );
    if (!mounted) return;
    final capture = [
      ...ctrl.pages,
      ...ctrl.pendingPages,
    ].where((p) => p.pageCaptureId == captureId).firstOrNull;
    if (outcome == PpgIdentityOutcome.retake) {
      if (capture != null && capture.pendingReplacement) {
        await ctrl.discardReplacement(captureId);
      }
      if (!mounted) return;
      await _capture(ctrl, slot: capture?.printedPage);
      return;
    }
    if (outcome != PpgIdentityOutcome.confirmed || capture == null) return;
    await _settleReplacement(ctrl, capture);
  }

  /// A new photo for a slot that already has one. An earlier photo that was
  /// never checked or counted is replaced directly; otherwise the operator
  /// compares and chooses.
  Future<void> _settleReplacement(
    PpgSessionController ctrl,
    PageCapture capture,
  ) async {
    final pending = ctrl.pendingPages
        .where((p) => p.pageCaptureId == capture.pageCaptureId)
        .firstOrNull;
    if (pending == null) {
      showPpgMessage(context, 'Page ${capture.printedPage} saved');
      return;
    }
    final earlier = ctrl.pages
        .where((p) => p.printedPage == pending.printedPage)
        .firstOrNull;
    if (earlier != null &&
        !earlier.pageReviewConfirmed &&
        !ctrl.pageHasPhysicalCounts(earlier.pageCaptureId)) {
      final ok = await ppgRun(
        context,
        () => ctrl.acceptReplacement(pending.pageCaptureId),
      );
      if (ok && mounted) {
        showPpgMessage(
          context,
          'Page ${pending.printedPage} saved. The earlier photo was replaced.',
        );
      }
      return;
    }
    final result = await ppgPush<String>(
      context,
      ctrl,
      PpgPageReviewScreen(pageCaptureId: pending.pageCaptureId),
    );
    if (result == ppgRetakePage && mounted) {
      await _capture(ctrl, slot: pending.printedPage);
    }
  }

  Future<void> _confirmIdentity(
    PpgSessionController ctrl,
    PageCapture page,
  ) async {
    final outcome = await ppgPush<PpgIdentityOutcome>(
      context,
      ctrl,
      PpgPageIdentityScreen(pageCaptureId: page.pageCaptureId),
    );
    if (!mounted) return;
    if (outcome == PpgIdentityOutcome.retake) {
      await _capture(ctrl, slot: page.printedPage);
    } else if (outcome == PpgIdentityOutcome.confirmed) {
      await _settleReplacement(ctrl, page);
    }
  }

  Future<void> _openPage(PpgSessionController ctrl, PageCapture page) async {
    final result = await ppgPush<String>(
      context,
      ctrl,
      PpgPageReviewScreen(pageCaptureId: page.pageCaptureId),
    );
    if (result == ppgRetakePage && mounted) {
      await _capture(ctrl, slot: page.printedPage);
    }
  }

  Future<void> _act(PpgSessionController ctrl, PpgPageStatus status) async {
    final target = status.target;
    switch (status.step) {
      case PpgPageStep.capture:
        await _capture(ctrl, slot: status.slot);
      case PpgPageStep.reading:
        return;
      case PpgPageStep.confirmIdentity:
        if (target != null) await _confirmIdentity(ctrl, target);
      case PpgPageStep.chooseReplacement:
      case PpgPageStep.fixReading:
      case PpgPageStep.resolveRows:
      case PpgPageStep.review:
      case PpgPageStep.done:
        if (target != null) await _openPage(ctrl, target);
    }
  }

  Future<void> _continueToCount(PpgSessionController ctrl) async {
    if (widget.openedFromCount) {
      Navigator.pop(context);
      return;
    }
    await ppgPush<void>(context, ctrl, const PpgReviewScreen(), replace: true);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PpgSessionController>(
      builder: (context, ctrl, _) {
        final s = ctrl.session;
        if (s == null || s.id != widget.sessionId) {
          return const PpgThemed(
            child: Scaffold(
              body: Center(
                child: CircularProgressIndicator(semanticsLabel: 'Loading'),
              ),
            ),
          );
        }
        final declared = ppgDeclaredPages(ctrl);
        final statuses = [
          for (var slot = 1; slot <= (declared ?? 0); slot++)
            ppgPageStatus(ctrl, slot),
        ];
        final strays = ctrl.pages
            .where(
              (p) =>
                  p.printedPage < 1 ||
                  (declared != null && p.printedPage > declared) ||
                  ctrl.pages
                          .where((o) => o.printedPage == p.printedPage)
                          .length >
                      1,
            )
            .toList();
        final open = statuses.where((st) => st.needsAction).toList();
        final checked = statuses
            .where((st) => st.step == PpgPageStep.done)
            .length;
        // Whole-document checks only mean something once every page has
        // been read and identified; until then they repeat page issues.
        final documentIssues =
            open.any(
              (st) => st.step.index <= PpgPageStep.chooseReplacement.index,
            )
            ? const <String>[]
            : ctrl.documentIssues;
        final readOnly = s.isSubmitted;

        return PpgThemed(
          child: Scaffold(
            bottomNavigationBar: _bottomBar(ctrl, open, readOnly),
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PpgHeader(
                  eyebrow: 'Delivery note',
                  title: s.deliveryNoteNumber ?? 'Number not read yet',
                  monoTitle: s.deliveryNoteNumber != null,
                  stage: 0,
                  completedStages: ctrl.sourceReviewReady ? {0} : const {},
                  backTooltip: widget.openedFromCount
                      ? 'Back to count list'
                      : 'Back to Delivery notes',
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    children: [
                      if (readOnly) ...[
                        const PpgBanner(
                          tone: PpgTone.success,
                          title: 'Submitted',
                          message:
                              'This receiving form is saved and can no longer be changed.',
                        ),
                        const SizedBox(height: PpgSpace.l),
                      ] else if (open.isNotEmpty ||
                          strays.isNotEmpty ||
                          documentIssues.isNotEmpty) ...[
                        _issuePanel(ctrl, open, strays, documentIssues),
                        const SizedBox(height: PpgSpace.l),
                      ] else if (ctrl.sourceReviewReady) ...[
                        const PpgBanner(
                          tone: PpgTone.success,
                          title: 'Document checked',
                          message:
                              'Every page is checked. Continue to count the stock that arrived.',
                        ),
                        const SizedBox(height: PpgSpace.l),
                      ],
                      PpgSectionLabel(
                        'Pages',
                        trailing: declared == null
                            ? null
                            : '$checked of $declared checked',
                      ),
                      const SizedBox(height: PpgSpace.s),
                      if (declared == null)
                        PpgPanel(
                          child: PpgEmptyState(
                            icon: Icons.photo_camera_outlined,
                            title: 'No pages yet',
                            message:
                                'Photograph page 1. The number of pages is read from the paper.',
                            action: readOnly
                                ? null
                                : FilledButton.icon(
                                    onPressed: () => _capture(ctrl, slot: 1),
                                    icon: const Icon(Icons.photo_camera),
                                    label: const Text('Photograph page 1'),
                                  ),
                          ),
                        )
                      else
                        PpgPanel(
                          child: Column(
                            children: ppgDivided([
                              for (final status in statuses)
                                _pageRow(ctrl, status, readOnly),
                            ]),
                          ),
                        ),
                      if (ctrl.pages.any((p) => p.printedPage == 1)) ...[
                        const SizedBox(height: PpgSpace.l),
                        PpgSourceSummary(controller: ctrl),
                      ],
                      if (ctrl.contexts.isNotEmpty) ...[
                        const SizedBox(height: PpgSpace.l),
                        Text(
                          '${ppgPlural(ctrl.contexts.length, 'heading')} without a printed quantity are kept as context, not counted.',
                          style: const TextStyle(
                            fontSize: 13,
                            color: PpgColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _issuePanel(
    PpgSessionController ctrl,
    List<PpgPageStatus> open,
    List<PageCapture> strays,
    List<String> documentIssues,
  ) {
    final count = open.length + strays.length + documentIssues.length;
    return PpgPanel(
      tone: PpgTone.warning,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: PpgTone.warning.background,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: PpgTone.warning.foreground,
                ),
                const SizedBox(width: PpgSpace.s),
                Expanded(
                  child: Text(
                    count == 1
                        ? '1 thing to check before counting'
                        : '$count things to check before counting',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: PpgTone.warning.foreground,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ...ppgDivided([
            for (final status in open)
              PpgRow(
                title: status.title,
                subtitle: status.detail,
                onTap: status.step == PpgPageStep.reading
                    ? null
                    : () => _act(ctrl, status),
              ),
            for (final page in strays)
              PpgRow(
                title: 'A photo is saved as page ${page.printedPage}',
                subtitle:
                    'It is outside the page range or duplicates another page. Check its page number.',
                onTap: () => _confirmIdentity(ctrl, page),
              ),
            for (final issue in documentIssues) PpgRow(title: issue),
          ]),
        ],
      ),
    );
  }

  Widget _pageRow(
    PpgSessionController ctrl,
    PpgPageStatus status,
    bool readOnly,
  ) {
    final page = status.page;
    final isSummary =
        page != null &&
        status.slot == 1 &&
        !ctrl.lines.any((l) => l.pageCaptureId == page.pageCaptureId);
    return PpgRow(
      title: 'Page ${status.slot}${isSummary ? ' · Summary' : ''}',
      subtitle: page == null
          ? 'No photo yet'
          : status.step == PpgPageStep.fixReading
          ? 'Could not be read'
          : isSummary && page.effectivePieceCount != null
          ? '${page.effectivePieceCount} PC printed'
          : ppgPageContentSummary(ctrl, page),
      leading: _Thumbnail(page: page),
      trailing: PpgStatusBadge(label: status.badge, tone: status.tone),
      showChevron: false,
      semanticLabel: 'Page ${status.slot}, ${status.badge}',
      onTap: readOnly && page == null
          ? null
          : status.step == PpgPageStep.reading
          ? null
          : readOnly
          ? () => _openPage(ctrl, page!)
          : () => _act(ctrl, status),
    );
  }

  Widget _bottomBar(
    PpgSessionController ctrl,
    List<PpgPageStatus> open,
    bool readOnly,
  ) {
    if (readOnly) {
      return PpgBottomBar(
        children: [
          FilledButton(
            onPressed: () =>
                ppgPush<void>(context, ctrl, const PpgConfirmationScreen()),
            child: const Text('View receipt'),
          ),
        ],
      );
    }
    if (ctrl.sourceReviewReady && ctrl.lines.isNotEmpty) {
      return PpgBottomBar(
        children: [
          FilledButton(
            onPressed: ctrl.processing ? null : () => _continueToCount(ctrl),
            child: Text(
              widget.openedFromCount
                  ? 'Back to count list'
                  : 'Continue to count',
            ),
          ),
        ],
      );
    }
    // With the paper in hand, photographing every page comes first.
    final next =
        open.where((st) => st.step == PpgPageStep.capture).firstOrNull ??
        open.firstOrNull;
    final declared = ppgDeclaredPages(ctrl);
    final (String label, VoidCallback? action) = switch (next?.step) {
      null when declared == null => (
        'Photograph page 1',
        () => _capture(ctrl, slot: 1),
      ),
      null => ('Resolve the checks above', null),
      PpgPageStep.capture => (
        'Photograph page ${next!.slot}',
        () => _act(ctrl, next),
      ),
      PpgPageStep.reading => ('Reading page ${next!.slot}…', null),
      PpgPageStep.confirmIdentity => (
        'Confirm page ${next!.slot}',
        () => _act(ctrl, next),
      ),
      PpgPageStep.chooseReplacement => (
        'Choose photo for page ${next!.slot}',
        () => _act(ctrl, next),
      ),
      PpgPageStep.fixReading => (
        'Fix page ${next!.slot}',
        () => _act(ctrl, next),
      ),
      _ => ('Check page ${next!.slot}', () => _act(ctrl, next)),
    };
    return PpgBottomBar(
      children: [
        Row(
          children: [
            SizedBox.square(
              dimension: PpgSizes.button,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                onPressed: ctrl.processing
                    ? null
                    : () => _capture(ctrl, slot: ppgNextMissingPage(ctrl)),
                child: const Tooltip(
                  message: 'Add or retake a page',
                  child: Icon(Icons.photo_camera_outlined),
                ),
              ),
            ),
            const SizedBox(width: PpgSpace.s),
            Expanded(
              child: FilledButton(
                onPressed: ctrl.processing ? null : action,
                child: Text(label),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.page});

  final PageCapture? page;

  @override
  Widget build(BuildContext context) {
    final path = page?.rectifiedImagePath ?? page?.sourceImagePath;
    return Container(
      width: 40,
      height: 52,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: PpgColors.ground,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: PpgColors.line),
      ),
      child: path == null
          ? const Icon(
              Icons.description_outlined,
              size: 20,
              color: PpgColors.textMuted,
            )
          : Image.file(
              File(path),
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              cacheWidth: 120,
              excludeFromSemantics: true,
              errorBuilder: (_, _, _) => const Icon(
                Icons.broken_image_outlined,
                size: 20,
                color: PpgColors.textMuted,
              ),
            ),
    );
  }
}
