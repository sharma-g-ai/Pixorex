import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../domain/models.dart';
import '../domain/source_correction.dart';
import '../ocr/total_qty_field_reader.dart';
import '../services/ppg_session_controller.dart';
import '../ui/ppg_format.dart';
import '../ui/ppg_navigation.dart';
import '../ui/ppg_page_status.dart';
import '../ui/ppg_tokens.dart';
import '../ui/ppg_widgets.dart';
import '../widgets/four_corner_crop.dart';
import 'ppg_page_identity_screen.dart';

/// Returned when the operator asks to photograph this page again; the
/// opener runs the capture so the new photo goes through the usual checks.
const ppgRetakePage = 'retake';

/// Reviews one captured page before its occurrences join delivery review.
class PpgPageReviewScreen extends StatefulWidget {
  const PpgPageReviewScreen({super.key, required this.pageCaptureId});

  final String pageCaptureId;

  @override
  State<PpgPageReviewScreen> createState() => _PpgPageReviewScreenState();
}

class _PpgPageReviewScreenState extends State<PpgPageReviewScreen> {
  bool? _coverageConfirmed;
  bool _confirming = false;
  final Map<String, Future<Uint8List?>> _fieldCropCache = {};

  void _resetCoverage() {
    if (mounted) setState(() => _coverageConfirmed = false);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PpgSessionController>(
      builder: (context, ctrl, _) {
        final page = [
          ...ctrl.pages,
          ...ctrl.pendingPages,
        ].where((p) => p.pageCaptureId == widget.pageCaptureId).firstOrNull;
        if (page == null) {
          return const PpgThemed(
            child: Scaffold(
              body: PpgEmptyState(
                icon: Icons.image_not_supported_outlined,
                title: 'This photo is no longer available',
                message: 'Go back to the page list.',
              ),
            ),
          );
        }
        if (page.pendingReplacement) {
          return _pendingReplacementReview(context, ctrl, page);
        }
        return _pageCheck(context, ctrl, page);
      },
    );
  }

  Widget _pageCheck(
    BuildContext context,
    PpgSessionController ctrl,
    PageCapture page,
  ) {
    final session = ctrl.session;
    final readOnly = session?.isSubmitted == true;
    final canRescan =
        !readOnly && !ctrl.pageHasPhysicalCounts(page.pageCaptureId);
    final coverage = _coverageConfirmed ?? page.pageReviewConfirmed;
    final rows = ppgOrderedLines(
      ctrl,
      ctrl.lines.where((line) => line.pageCaptureId == page.pageCaptureId),
    );
    final contexts = ctrl.contexts
        .where((item) => item.pageCaptureId == page.pageCaptureId)
        .toList();
    final unresolved = ppgUnresolvedRows(ctrl, page);
    final identityNeeded = ppgIdentityNeedsCheck(ctrl, page);
    final imagePath = page.rectifiedImagePath ?? page.sourceImagePath;
    final total = rows.fold<int>(0, (sum, l) => sum + l.documentQuantity);
    final declared = session?.declaredPageCount;
    final ocrDone = page.ocrStatus == PageOcrStatus.succeeded;

    return PpgThemed(
      child: Scaffold(
        bottomNavigationBar: readOnly
            ? null
            : _footer(
                context,
                ctrl,
                page,
                coverage: coverage,
                identityNeeded: identityNeeded,
                unresolved: unresolved,
                canConfirm: ocrDone && imagePath != null,
              ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PpgHeader(
              title:
                  'Check page ${page.printedPage}${declared == null ? '' : ' of $declared'}',
              subtitle:
                  'DN ${session?.deliveryNoteNumber ?? 'not confirmed'} · 1 Document',
              backTooltip: 'Back to the page list',
              actions: [
                if (!readOnly)
                  PopupMenuButton<String>(
                    tooltip: 'More page actions',
                    iconColor: Colors.white,
                    onSelected: (value) => switch (value) {
                      'identity' => _verifyIdentity(context, ctrl, page),
                      'crop' => _adjustCrop(context, ctrl, page),
                      'retake' => Navigator.pop(context, ppgRetakePage),
                      'add' => _addMissingOccurrence(context, ctrl, page),
                      _ => null,
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'identity',
                        enabled: ocrDone,
                        child: const Text('Correct page or delivery number'),
                      ),
                      PopupMenuItem(
                        value: 'crop',
                        enabled: canRescan && page.sourceImagePath != null,
                        child: const Text('Adjust crop and read again'),
                      ),
                      PopupMenuItem(
                        value: 'retake',
                        enabled: canRescan,
                        child: const Text('Retake this page'),
                      ),
                      PopupMenuItem(
                        value: 'add',
                        enabled: ocrDone,
                        child: const Text('Add a missing item'),
                      ),
                    ],
                  ),
              ],
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _imageStrip(context, imagePath),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (page.ocrStatus == PageOcrStatus.failed) ...[
                          _readFailure(context, ctrl, page, canRescan),
                          const SizedBox(height: PpgSpace.m),
                        ] else if (!ocrDone) ...[
                          const PpgBanner(
                            tone: PpgTone.info,
                            message: 'Reading the page…',
                          ),
                          const SizedBox(height: PpgSpace.m),
                        ] else if (identityNeeded && !readOnly) ...[
                          PpgBanner(
                            tone: PpgTone.warning,
                            title: 'Confirm the page first',
                            message:
                                'Check that the delivery and page numbers on this photo belong to this DN.',
                            action: TextButton(
                              onPressed: () =>
                                  _verifyIdentity(context, ctrl, page),
                              child: const Text('Confirm numbers'),
                            ),
                          ),
                          const SizedBox(height: PpgSpace.m),
                        ],
                        if (imagePath == null) ...[
                          const PpgBanner(
                            tone: PpgTone.danger,
                            message:
                                'The saved photo of this page is missing, so it can\'t be checked. Retake the page.',
                          ),
                          const SizedBox(height: PpgSpace.m),
                        ],
                        PpgSectionLabel(
                          'Read from this page',
                          trailing: rows.isEmpty
                              ? null
                              : '${ppgPlural(rows.length, 'item')} · $total PC',
                        ),
                        const SizedBox(height: PpgSpace.s),
                        PpgPanel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: ppgDivided([
                              if (rows.isEmpty &&
                                  contexts.isEmpty &&
                                  unresolved.isEmpty)
                                PpgRow(
                                  title: ocrDone
                                      ? 'No items read'
                                      : 'Nothing read yet',
                                  subtitle: page.printedPage == 1
                                      ? 'Page 1 is often a summary. If an item is printed here, add it.'
                                      : 'If an item is printed on this page, add it.',
                                ),
                              for (final line in rows)
                                _lineRow(context, ctrl, line, readOnly),
                              for (final item in unresolved)
                                _unresolvedBlock(
                                  context,
                                  ctrl,
                                  page,
                                  item,
                                  imagePath,
                                  readOnly,
                                ),
                              for (final item in contexts)
                                PpgRow(
                                  title: item.heading ?? item.articleNumber,
                                  subtitle:
                                      'Heading without a printed quantity · not counted',
                                ),
                            ]),
                          ),
                        ),
                        if (!readOnly && ocrDone)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () =>
                                  _addMissingOccurrence(context, ctrl, page),
                              icon: const Icon(Icons.add),
                              label: const Text('Add a missing item'),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _footer(
    BuildContext context,
    PpgSessionController ctrl,
    PageCapture page, {
    required bool coverage,
    required bool identityNeeded,
    required List<ParsedOccurrence> unresolved,
    required bool canConfirm,
  }) {
    final canRetake =
        !ctrl.pageHasPhysicalCounts(page.pageCaptureId) &&
        page.ocrStatus != PageOcrStatus.running &&
        page.ocrStatus != PageOcrStatus.pending;
    final (String label, VoidCallback? action) = !canConfirm
        ? canRetake
              ? (
                  'Retake page ${page.printedPage}',
                  () => Navigator.pop(context, ppgRetakePage),
                )
              : ('Page can\'t be checked yet', null)
        : identityNeeded
        ? (
            'Confirm page number first',
            () => _verifyIdentity(context, ctrl, page),
          )
        : unresolved.isNotEmpty
        ? (
            unresolved.length == 1
                ? 'Check ${unresolved.single.articleNumber} first'
                : 'Check ${unresolved.length} quantities first',
            null,
          )
        : page.pageReviewConfirmed && coverage
        ? ('Done', () => Navigator.pop(context))
        : !coverage
        ? ('Confirm page ${page.printedPage}', null)
        : _confirming
        ? ('Saving…', null)
        : ('Confirm page ${page.printedPage}', () => _confirm(ctrl, page));
    return PpgBottomBar(
      children: [
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: coverage,
          onChanged: canConfirm
              ? (value) => setState(() => _coverageConfirmed = value ?? false)
              : null,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text(
            'I checked the whole page and nothing is missing',
            style: TextStyle(fontSize: 14),
          ),
        ),
        FilledButton(onPressed: action, child: Text(label)),
      ],
    );
  }

  Future<void> _confirm(PpgSessionController ctrl, PageCapture page) async {
    setState(() => _confirming = true);
    final ok = await ppgRun(
      context,
      () => ctrl.confirmPageReview(
        pageCaptureId: page.pageCaptureId,
        coverageConfirmed: true,
      ),
    );
    if (!mounted) return;
    setState(() => _confirming = false);
    if (ok) {
      showPpgMessage(context, 'Page ${page.printedPage} checked');
      Navigator.pop(context);
    }
  }

  Widget _imageStrip(BuildContext context, String? imagePath) {
    if (imagePath == null) {
      return Container(
        height: 120,
        color: PpgColors.divider,
        alignment: Alignment.center,
        child: const Icon(
          Icons.image_not_supported_outlined,
          color: PpgColors.textMuted,
        ),
      );
    }
    return SizedBox(
      height: 250,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            color: PpgColors.divider,
            child: Image.file(
              File(imagePath),
              fit: BoxFit.cover,
              alignment: const Alignment(0, -0.65),
              semanticLabel: 'Photo of this DN page',
              errorBuilder: (_, _, _) =>
                  const Center(child: Text('The photo could not be shown.')),
            ),
          ),
          Positioned(
            right: 12,
            bottom: 12,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: PpgColors.navy,
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => _FullPageView(imagePath: imagePath),
                ),
              ),
              icon: const Icon(Icons.zoom_in, size: 18),
              label: const Text('View full page'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _readFailure(
    BuildContext context,
    PpgSessionController ctrl,
    PageCapture page,
    bool canRescan,
  ) {
    return PpgBanner(
      tone: PpgTone.danger,
      title: 'This page could not be read',
      message: page.ocrError == null
          ? 'Adjust the crop so the whole page is inside, or take the photo again.'
          : ppgErrorMessage(page.ocrError!),
      action: canRescan
          ? Wrap(
              spacing: 4,
              children: [
                TextButton(
                  onPressed: () => _retryOcr(context, ctrl, page),
                  child: const Text('Read again'),
                ),
                if (page.sourceImagePath != null)
                  TextButton(
                    onPressed: () => _adjustCrop(context, ctrl, page),
                    child: const Text('Adjust crop'),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(context, ppgRetakePage),
                  child: const Text('Retake'),
                ),
              ],
            )
          : null,
    );
  }

  Widget _lineRow(
    BuildContext context,
    PpgSessionController ctrl,
    DocumentLine line,
    bool readOnly,
  ) {
    return PpgRow(
      title: line.articleNumber,
      monoTitle: true,
      subtitle: line.productContext,
      trailing: Text(
        '${line.documentQuantity} ${line.unit}',
        style: PpgText.figures(size: 15, weight: FontWeight.w600),
      ),
      showChevron: false,
      semanticLabel:
          'Article ${line.articleNumber}, ${line.documentQuantity} ${line.unit}${readOnly ? '' : '. Tap to correct.'}',
      onTap: readOnly ? null : () => _correctScan(context, ctrl, line),
    );
  }

  Widget _unresolvedBlock(
    BuildContext context,
    PpgSessionController ctrl,
    PageCapture page,
    ParsedOccurrence item,
    String? imagePath,
    bool readOnly,
  ) {
    final joined = item.issues.contains('AMBIGUOUS_COLOUR_QTY_BOUNDARY');
    return Container(
      color: const Color(0xFFFFFBEB),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.articleNumber, style: PpgText.mono()),
                    if (item.productContext != null)
                      Text(
                        item.productContext!,
                        style: const TextStyle(
                          fontSize: 13,
                          color: PpgColors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              PpgStatusBadge(label: 'Check Total Qty', tone: PpgTone.warning),
            ],
          ),
          const SizedBox(height: PpgSpace.s),
          Text(
            joined
                ? 'The colour code may be joined to the Total Qty. Compare with the printed value below.'
                : 'The Total Qty could not be read. Type the printed value.',
            style: TextStyle(fontSize: 13, color: PpgTone.warning.foreground),
          ),
          _sourceRowPreview(imagePath, item),
          if (!readOnly && isSourceCorrectableTotalQty(item)) ...[
            const SizedBox(height: PpgSpace.s),
            OutlinedButton(
              onPressed: () =>
                  _correctUnresolvedOccurrence(context, ctrl, page, item),
              child: const Text('Enter Total Qty'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sourceRowPreview(String? imagePath, ParsedOccurrence occurrence) {
    if (imagePath == null ||
        occurrence.rowCenterY == null ||
        occurrence.quantityColumnLeft == null) {
      return const SizedBox.shrink();
    }
    final file = File(imagePath);
    final key =
        '$imagePath:${occurrence.occurrenceId}:${occurrence.rowCenterY}';
    final future = _fieldCropCache.putIfAbsent(
      key,
      () => _loadRowCrop(file, occurrence),
    );
    return FutureBuilder<Uint8List?>(
      future: future,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: PpgSpace.s),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Printed colour and Total Qty',
                style: TextStyle(fontSize: 12, color: PpgColors.textSecondary),
              ),
              const SizedBox(height: 6),
              Container(
                height: 110,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: PpgColors.line),
                  borderRadius: BorderRadius.circular(PpgRadii.small),
                ),
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 6,
                  child: Image.memory(
                    bytes,
                    fit: BoxFit.contain,
                    semanticLabel: 'Close-up of the printed Total Qty',
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<Uint8List?> _loadRowCrop(
    File file,
    ParsedOccurrence occurrence,
  ) async {
    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final field = TotalQtyFieldReader.cropForDimensions(
        occurrence,
        image.width,
        image.height,
      );
      if (field == null) return null;
      final left = (field.left - 125 * (image.width / 1224).clamp(1.0, 4.0))
          .floor()
          .clamp(0, image.width);
      final width = field.right - left;
      final height = field.bottom - field.top;
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawImage(
        image,
        ui.Offset(-left.toDouble(), -field.top.toDouble()),
        ui.Paint(),
      );
      final cropped = await recorder.endRecording().toImage(width, height);
      final encoded = await cropped.toByteData(format: ui.ImageByteFormat.png);
      return encoded?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Widget _pendingReplacementReview(
    BuildContext context,
    PpgSessionController ctrl,
    PageCapture page,
  ) {
    final imagePath = page.rectifiedImagePath ?? page.sourceImagePath;
    final parsed = ctrl.parsedOccurrencesForPage(page.pageCaptureId);
    final identityNeeded =
        page.ocrStatus == PageOcrStatus.succeeded &&
        (!page.pageIdentityConfirmed ||
            page.verifiedDeliveryNoteNumber !=
                ctrl.session?.deliveryNoteNumber);
    final (
      String label,
      VoidCallback? action,
    ) = page.ocrStatus != PageOcrStatus.succeeded
        ? ('This photo could not be read', null)
        : identityNeeded
        ? (
            'Confirm page number first',
            () => _verifyIdentity(context, ctrl, page),
          )
        : (
            'Use this photo instead',
            () async {
              final ok = await ppgRun(
                context,
                () => ctrl.acceptReplacement(page.pageCaptureId),
              );
              if (ok && context.mounted) {
                showPpgMessage(context, 'Page ${page.printedPage} replaced');
                Navigator.pop(context);
              }
            },
          );
    return PpgThemed(
      child: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PpgHeader(
              title: 'New photo of page ${page.printedPage}',
              subtitle: 'Choose which photo to keep',
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _imageStrip(context, imagePath),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const PpgBanner(
                          tone: PpgTone.info,
                          message:
                              'Your earlier photo of this page is still saved. Use this one only if it is clearer.',
                        ),
                        if (page.ocrStatus == PageOcrStatus.failed) ...[
                          const SizedBox(height: PpgSpace.m),
                          _readFailure(context, ctrl, page, true),
                        ],
                        const SizedBox(height: PpgSpace.l),
                        PpgSectionLabel(
                          'Read from this photo',
                          trailing: ppgPlural(parsed.length, 'item'),
                        ),
                        const SizedBox(height: PpgSpace.s),
                        if (parsed.isNotEmpty)
                          PpgPanel(
                            child: Column(
                              children: ppgDivided([
                                for (final item in parsed)
                                  PpgRow(
                                    title: item.articleNumber,
                                    monoTitle: true,
                                    subtitle: item.productContext,
                                    trailing: Text(
                                      item.documentQuantity == null
                                          ? 'Check'
                                          : '${item.documentQuantity} ${item.unit}',
                                      style: PpgText.figures(
                                        weight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                              ]),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            PpgBottomBar(
              children: [
                FilledButton(onPressed: action, child: Text(label)),
                OutlinedButton(
                  onPressed: () async {
                    await ctrl.discardReplacement(page.pageCaptureId);
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text('Keep the earlier photo'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _retryOcr(
    BuildContext context,
    PpgSessionController ctrl,
    PageCapture page,
  ) => ppgRun(context, () => ctrl.retryPageOcr(page.pageCaptureId));

  Future<void> _adjustCrop(
    BuildContext context,
    PpgSessionController ctrl,
    PageCapture page,
  ) async {
    final source = page.sourceImagePath;
    if (source == null || !File(source).existsSync()) {
      showPpgMessage(
        context,
        'The original photo is missing. Retake the page.',
      );
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => FourCornerCropScreen(
          imagePath: source,
          onCancel: () => Navigator.pop(context),
          onAccept: (_, rectified, rotation) async {
            Navigator.pop(context);
            _resetCoverage();
            await ppgRun(
              context,
              () => ctrl.updateCropAndRetry(
                pageCaptureId: page.pageCaptureId,
                rectifiedImagePath: rectified,
                rotationDegrees: rotation,
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _verifyIdentity(
    BuildContext context,
    PpgSessionController ctrl,
    PageCapture page,
  ) async {
    final outcome = await ppgPush<PpgIdentityOutcome>(
      context,
      ctrl,
      PpgPageIdentityScreen(
        pageCaptureId: page.pageCaptureId,
        startEditing: !ppgIdentityNeedsCheck(ctrl, page),
      ),
    );
    if (!context.mounted) return;
    if (outcome == PpgIdentityOutcome.retake) {
      Navigator.pop(context, ppgRetakePage);
    } else if (outcome == PpgIdentityOutcome.confirmed) {
      _resetCoverage();
    }
  }

  Future<void> _addMissingOccurrence(
    BuildContext context,
    PpgSessionController ctrl,
    PageCapture page,
  ) async {
    final result = await showDialog<_SourceValues>(
      context: context,
      builder: (_) => PpgThemed(
        child: _SourceValuesDialog(
          title: 'Add an item from this page',
          intro:
              'Type the article and Total Qty exactly as printed on page ${page.printedPage}.',
          reasonLabel: 'Description or reference on the page',
          reasonError: 'Type the description printed with the item',
          saveLabel: 'Add item',
        ),
      ),
    );
    if (result == null || !context.mounted) return;
    final ok = await ppgRun(
      context,
      () => ctrl.addManualOccurrence(
        pageCaptureId: page.pageCaptureId,
        articleNumber: result.article,
        documentQuantity: result.quantity,
        sourceContext: result.reason,
      ),
    );
    if (ok) _resetCoverage();
  }

  Future<void> _correctUnresolvedOccurrence(
    BuildContext context,
    PpgSessionController ctrl,
    PageCapture page,
    ParsedOccurrence occurrence,
  ) async {
    final joined = occurrence.issues.contains('AMBIGUOUS_COLOUR_QTY_BOUNDARY');
    final result = await showDialog<_SourceValues>(
      context: context,
      builder: (_) => PpgThemed(
        child: _SourceValuesDialog(
          title: 'Enter the printed Total Qty',
          intro: joined
              ? 'The colour code may be joined to the Total Qty for ${occurrence.articleNumber}. Type the Total Qty only, not the Qty per Batch.'
              : 'The Total Qty for ${occurrence.articleNumber} could not be read. Type it from the paper.',
          preview: _sourceRowPreview(
            page.rectifiedImagePath ?? page.sourceImagePath,
            occurrence,
          ),
          initialArticle: occurrence.articleNumber,
          reasonLabel: 'Why the value was entered',
          initialReason: 'Read from the paper',
          reasonError: 'Give a short reason',
          saveLabel: 'Save',
        ),
      ),
    );
    if (result == null || !context.mounted) return;
    _resetCoverage();
    await ppgRun(
      context,
      () => ctrl.correctUnresolvedOccurrence(
        pageCaptureId: page.pageCaptureId,
        occurrenceId: occurrence.occurrenceId,
        articleNumber: result.article,
        documentQuantity: result.quantity,
        reason: result.reason,
      ),
    );
  }

  Future<void> _correctScan(
    BuildContext context,
    PpgSessionController ctrl,
    DocumentLine line,
  ) async {
    final result = await showDialog<_SourceValues>(
      context: context,
      builder: (_) => PpgThemed(
        child: _SourceValuesDialog(
          title: 'Correct what was read',
          intro: 'Change a value only if the paper says something different.',
          initialArticle: line.articleNumber,
          initialQuantity: '${line.documentQuantity}',
          reasonLabel: 'Why is it being corrected?',
          reasonError: 'Give a short reason',
          saveLabel: 'Save correction',
        ),
      ),
    );
    if (result == null || !context.mounted) return;
    _resetCoverage();
    await ppgRun(
      context,
      () => ctrl.correctScanResult(
        occurrenceId: line.occurrenceId,
        articleNumber: result.article,
        documentQuantity: result.quantity,
        reason: result.reason,
      ),
    );
  }
}

class _SourceValues {
  const _SourceValues(this.article, this.quantity, this.reason);
  final String article;
  final int quantity;
  final String reason;
}

/// Article, Total Qty and a reason, validated in place before closing.
class _SourceValuesDialog extends StatefulWidget {
  const _SourceValuesDialog({
    required this.title,
    required this.intro,
    required this.reasonLabel,
    required this.reasonError,
    required this.saveLabel,
    this.preview,
    this.initialArticle = '',
    this.initialQuantity = '',
    this.initialReason = '',
  });

  final String title;
  final String intro;
  final String reasonLabel;
  final String reasonError;
  final String saveLabel;
  final Widget? preview;
  final String initialArticle;
  final String initialQuantity;
  final String initialReason;

  @override
  State<_SourceValuesDialog> createState() => _SourceValuesDialogState();
}

class _SourceValuesDialogState extends State<_SourceValuesDialog> {
  final _form = GlobalKey<FormState>();
  late final _article = TextEditingController(text: widget.initialArticle);
  late final _quantity = TextEditingController(text: widget.initialQuantity);
  late final _reason = TextEditingController(text: widget.initialReason);

  @override
  void dispose() {
    _article.dispose();
    _quantity.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _save() {
    if (_form.currentState?.validate() != true) return;
    Navigator.pop(
      context,
      _SourceValues(
        _article.text.trim(),
        int.parse(_quantity.text.trim()),
        _reason.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text(widget.title),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.intro),
            ?widget.preview,
            const SizedBox(height: PpgSpace.m),
            TextFormField(
              controller: _article,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: PpgText.mono(size: 16),
              decoration: const InputDecoration(labelText: 'Article number'),
              validator: (value) =>
                  RegExp(r'^\d{1,32}$').hasMatch(value?.trim() ?? '')
                  ? null
                  : 'Type the printed article number',
            ),
            const SizedBox(height: PpgSpace.m),
            TextFormField(
              controller: _quantity,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Total Qty',
                suffixText: 'PC',
              ),
              validator: (value) => int.tryParse(value?.trim() ?? '') == null
                  ? 'Type a whole number'
                  : null,
            ),
            const SizedBox(height: PpgSpace.m),
            TextFormField(
              controller: _reason,
              decoration: InputDecoration(labelText: widget.reasonLabel),
              validator: (value) =>
                  (value?.trim().isEmpty ?? true) ? widget.reasonError : null,
              onFieldSubmitted: (_) => _save(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: Text(widget.saveLabel)),
      ],
    );
  }
}

class _FullPageView extends StatelessWidget {
  const _FullPageView({required this.imagePath});

  final String imagePath;

  @override
  Widget build(BuildContext context) {
    return PpgThemed(
      child: Scaffold(
        backgroundColor: PpgColors.camera,
        appBar: AppBar(
          backgroundColor: PpgColors.camera,
          title: const Text('Full page'),
        ),
        body: InteractiveViewer(
          maxScale: 6,
          child: Center(
            child: Image.file(
              File(imagePath),
              semanticLabel: 'Full photo of this DN page',
            ),
          ),
        ),
      ),
    );
  }
}
