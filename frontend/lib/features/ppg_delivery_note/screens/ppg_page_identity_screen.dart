import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../domain/models.dart';
import '../services/ppg_session_controller.dart';
import '../ui/ppg_format.dart';
import '../ui/ppg_tokens.dart';
import '../ui/ppg_widgets.dart';

enum PpgIdentityOutcome { confirmed, retake }

/// Confirms which printed page a photo shows and which delivery note it
/// belongs to. The printed "Page x / y" read from the photo is the default;
/// the operator only types when it could not be read or looks wrong, and a
/// typed value that differs from the printed one is warned about, not
/// blocked.
class PpgPageIdentityScreen extends StatefulWidget {
  const PpgPageIdentityScreen({
    super.key,
    required this.pageCaptureId,
    this.startEditing = false,
  });

  final String pageCaptureId;
  final bool startEditing;

  @override
  State<PpgPageIdentityScreen> createState() => _PpgPageIdentityScreenState();
}

class _PpgPageIdentityScreenState extends State<PpgPageIdentityScreen> {
  final _dn = TextEditingController();
  final _page = TextEditingController();
  final _total = TextEditingController();
  bool _editing = false;
  bool _saving = false;
  bool _prefilled = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _editing = widget.startEditing;
  }

  void _onFieldChanged() {
    if (mounted) setState(() => _error = null);
  }

  @override
  void dispose() {
    _dn.dispose();
    _page.dispose();
    _total.dispose();
    super.dispose();
  }

  PageCapture? _capture(PpgSessionController ctrl) => [
    ...ctrl.pages,
    ...ctrl.pendingPages,
  ].where((p) => p.pageCaptureId == widget.pageCaptureId).firstOrNull;

  /// The DN read from the photo, unless it conflicts with this delivery note.
  ({
    String? readDn,
    int? readPage,
    int? readTotal,
    String? sessionDn,
    bool dnConflict,
  })
  _reading(PpgSessionController ctrl, PageCapture page) {
    final sessionDn = ctrl.session?.deliveryNoteNumber;
    final readDn = page.observedDeliveryNoteNumber;
    final others = ctrl.pages.where(
      (p) => p.pageCaptureId != page.pageCaptureId,
    );
    return (
      readDn: readDn,
      readPage: page.suggestedPrintedPage,
      readTotal:
          page.suggestedDeclaredPageCount ?? ctrl.session?.declaredPageCount,
      sessionDn: sessionDn,
      dnConflict:
          readDn != null &&
          sessionDn != null &&
          readDn != sessionDn &&
          others.isNotEmpty,
    );
  }

  void _prefill(PpgSessionController ctrl, PageCapture page) {
    if (_prefilled) return;
    _prefilled = true;
    final read = _reading(ctrl, page);
    _dn.text =
        page.verifiedDeliveryNoteNumber ??
        (read.dnConflict ? read.sessionDn : read.readDn) ??
        read.sessionDn ??
        '';
    _page.text = '${read.readPage ?? page.printedPage}';
    _total.text =
        '${page.verifiedDeclaredPageCount ?? read.readTotal ?? ctrl.session?.declaredPageCount ?? ''}';
    // Listen only after prefilling: this runs during build.
    for (final field in [_dn, _page, _total]) {
      field.addListener(_onFieldChanged);
    }
  }

  Future<void> _save(
    PpgSessionController ctrl,
    PageCapture page, {
    required String dn,
    required int printedPage,
    required int? total,
  }) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ctrl.confirmPageIdentity(
        pageCaptureId: page.pageCaptureId,
        deliveryNoteNumber: dn,
        printedPage: printedPage,
        declaredPageCount: total,
      );
      if (mounted) Navigator.pop(context, PpgIdentityOutcome.confirmed);
    } catch (error) {
      if (mounted) setState(() => _error = ppgErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _validate() {
    final dn = _dn.text.trim();
    final page = int.tryParse(_page.text.trim());
    final total = int.tryParse(_total.text.trim());
    if (!RegExp(r'^\d{1,32}$').hasMatch(dn)) {
      return 'Type the delivery number printed on the page, digits only.';
    }
    if (page == null || page < 1) return 'Type the page number, e.g. 2.';
    if (total == null || total < 1) return 'Type the total pages, e.g. 4.';
    if (page > total) return 'Page $page can\'t be more than $total pages.';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PpgSessionController>(
      builder: (context, ctrl, _) {
        final page = _capture(ctrl);
        if (page == null) {
          return const PpgThemed(
            child: Scaffold(
              body: PpgEmptyState(
                icon: Icons.image_not_supported_outlined,
                title: 'This photo is no longer available',
                message: 'Go back and choose another page.',
              ),
            ),
          );
        }
        _prefill(ctrl, page);
        final imagePath = page.rectifiedImagePath ?? page.sourceImagePath;
        return PpgThemed(
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle.light,
            child: PopScope(
              canPop: !_saving,
              child: Scaffold(
                backgroundColor: PpgColors.camera,
                resizeToAvoidBottomInset: true,
                body: SafeArea(
                  bottom: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
                        child: Row(
                          children: [
                            IconButton(
                              tooltip: 'Back',
                              color: Colors.white,
                              onPressed: _saving
                                  ? null
                                  : () => Navigator.maybePop(context),
                              icon: const Icon(
                                Icons.arrow_back_ios_new,
                                size: 20,
                              ),
                            ),
                            const Expanded(
                              child: Text(
                                'Page photo',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                          child:
                              imagePath != null && File(imagePath).existsSync()
                              ? InteractiveViewer(
                                  maxScale: 5,
                                  child: Image.file(
                                    File(imagePath),
                                    alignment: Alignment.topCenter,
                                    semanticLabel:
                                        'Photo of the delivery note page',
                                  ),
                                )
                              : const Center(
                                  child: Text(
                                    'The photo could not be shown.',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                        ),
                      ),
                      _sheet(ctrl, page),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _sheet(PpgSessionController ctrl, PageCapture page) {
    final Widget content;
    if (page.ocrStatus == PageOcrStatus.pending ||
        page.ocrStatus == PageOcrStatus.running) {
      content = const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            SizedBox(width: PpgSpace.m),
            Text('Reading the page…', style: TextStyle(fontSize: 16)),
          ],
        ),
      );
    } else if (page.ocrStatus == PageOcrStatus.failed) {
      content = _unreadable(page);
    } else {
      final read = _reading(ctrl, page);
      final complete =
          read.readPage != null &&
          read.readTotal != null &&
          (read.readDn != null || read.sessionDn != null) &&
          !read.dnConflict;
      content = _editing || !complete
          ? _editForm(ctrl, page)
          : _summary(ctrl, page);
    }
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(PpgRadii.sheet),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: content,
        ),
      ),
    );
  }

  Widget _unreadable(PageCapture page) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      PpgBanner(
        tone: PpgTone.danger,
        title: 'This page could not be read',
        message: page.ocrError == null
            ? 'Take the photo again in good light, with the whole page in the frame.'
            : ppgErrorMessage(page.ocrError!),
      ),
      const SizedBox(height: PpgSpace.l),
      FilledButton(
        onPressed: () => Navigator.pop(context, PpgIdentityOutcome.retake),
        child: const Text('Retake photo'),
      ),
      const SizedBox(height: PpgSpace.s),
      OutlinedButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Keep it and fix it later'),
      ),
    ],
  );

  Widget _summary(PpgSessionController ctrl, PageCapture page) {
    final read = _reading(ctrl, page);
    final dn = read.readDn ?? read.sessionDn!;
    final pageNo = read.readPage!;
    final total = read.readTotal!;
    final saved = {
      ...ctrl.pages
          .where((p) => p.pageCaptureId != page.pageCaptureId)
          .map((p) => p.printedPage),
      pageNo,
    }.toList()..sort();
    final next = [
      for (var i = 1; i <= total; i++)
        if (!saved.contains(i)) i,
    ].firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: PpgTone.success.background,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check, color: PpgTone.success.foreground),
            ),
            const SizedBox(width: PpgSpace.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'This is page $pageNo of $total',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text.rich(
                    TextSpan(
                      style: const TextStyle(
                        fontSize: 14,
                        color: PpgColors.textSecondary,
                      ),
                      children: [
                        const TextSpan(text: 'Read from the page: '),
                        TextSpan(
                          text: 'Page : $pageNo / $total',
                          style: PpgText.mono(
                            size: 14,
                            weight: FontWeight.w500,
                            color: PpgColors.navy,
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
        const SizedBox(height: PpgSpace.m),
        Container(
          padding: const EdgeInsets.all(PpgSpace.m),
          decoration: BoxDecoration(
            color: PpgColors.ground,
            borderRadius: BorderRadius.circular(PpgRadii.medium),
          ),
          child: Column(
            children: [
              _fact('Delivery note', dn, mono: true),
              _fact(
                'Pages saved after this',
                '${saved.join(', ')} of $total${next == null ? '' : ' · next: page $next'}',
              ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: PpgSpace.m),
          PpgBanner(tone: PpgTone.danger, message: _error!),
        ],
        const SizedBox(height: PpgSpace.l),
        FilledButton(
          onPressed: _saving
              ? null
              : () => _save(
                  ctrl,
                  page,
                  dn: dn,
                  printedPage: pageNo,
                  total: total,
                ),
          child: Text(_saving ? 'Saving…' : 'Save as page $pageNo'),
        ),
        const SizedBox(height: PpgSpace.s),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _saving
                    ? null
                    : () => Navigator.pop(context, PpgIdentityOutcome.retake),
                child: const Text('Retake photo'),
              ),
            ),
            const SizedBox(width: PpgSpace.s),
            Expanded(
              child: OutlinedButton(
                onPressed: _saving
                    ? null
                    : () => setState(() => _editing = true),
                child: const Text('Wrong number?'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _editForm(PpgSessionController ctrl, PageCapture page) {
    final read = _reading(ctrl, page);
    final typedPage = int.tryParse(_page.text.trim());
    final typedDn = _dn.text.trim();
    final pageDiffers =
        read.readPage != null &&
        typedPage != null &&
        typedPage != read.readPage;
    final dnDiffers =
        read.readDn != null && typedDn.isNotEmpty && typedDn != read.readDn;
    final heading = read.readPage == null
        ? 'Which page is this?'
        : read.readDn == null && read.sessionDn == null
        ? 'Which delivery note is this?'
        : 'Check the numbers on the page';
    Future<void> saveTyped() async {
      final problem = _validate();
      if (problem != null) {
        setState(() => _error = problem);
        return;
      }
      await _save(
        ctrl,
        page,
        dn: _dn.text.trim(),
        printedPage: int.parse(_page.text.trim()),
        total: int.parse(_total.text.trim()),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          heading,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        const Text(
          'Type the numbers printed on the paper.',
          style: TextStyle(fontSize: 14, color: PpgColors.textSecondary),
        ),
        if (read.dnConflict) ...[
          const SizedBox(height: PpgSpace.m),
          PpgBanner(
            tone: PpgTone.warning,
            message:
                'The photo reads DN ${read.readDn}, but this delivery note is ${read.sessionDn}. If the paper is a different delivery, retake or start a separate delivery note.',
          ),
        ],
        const SizedBox(height: PpgSpace.l),
        TextField(
          controller: _dn,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: PpgText.mono(size: 18),
          decoration: const InputDecoration(
            labelText: 'Delivery number on this page',
          ),
        ),
        const SizedBox(height: PpgSpace.m),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _page,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: PpgText.figures(size: 20),
                decoration: const InputDecoration(labelText: 'Page'),
              ),
            ),
            const SizedBox(width: PpgSpace.m),
            Expanded(
              child: TextField(
                controller: _total,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: PpgText.figures(size: 20),
                decoration: const InputDecoration(labelText: 'of'),
              ),
            ),
          ],
        ),
        if (pageDiffers || dnDiffers) ...[
          const SizedBox(height: PpgSpace.m),
          PpgBanner(
            tone: PpgTone.warning,
            message: [
              if (pageDiffers)
                'The page reads Page : ${read.readPage} / ${read.readTotal ?? '?'}, but you entered $typedPage.',
              if (dnDiffers)
                'The page reads DN ${read.readDn}, but you entered $typedDn.',
              'Check the paper before saving.',
            ].join(' '),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: PpgSpace.m),
          PpgBanner(tone: PpgTone.danger, message: _error!),
        ],
        const SizedBox(height: PpgSpace.l),
        if (pageDiffers && !dnDiffers) ...[
          FilledButton(
            onPressed: _saving
                ? null
                : () {
                    _page.text = '${read.readPage}';
                    if (read.readTotal != null) {
                      _total.text = '${read.readTotal}';
                    }
                    saveTyped();
                  },
            child: Text('Use page ${read.readPage}, as printed'),
          ),
          const SizedBox(height: PpgSpace.s),
          OutlinedButton(
            onPressed: _saving ? null : saveTyped,
            child: Text('Save as page $typedPage anyway'),
          ),
        ] else
          FilledButton(
            onPressed: _saving ? null : saveTyped,
            child: Text(
              _saving
                  ? 'Saving…'
                  : typedPage == null
                  ? 'Save page'
                  : 'Save as page $typedPage',
            ),
          ),
        const SizedBox(height: PpgSpace.s),
        TextButton(
          onPressed: _saving
              ? null
              : () => Navigator.pop(context, PpgIdentityOutcome.retake),
          child: const Text('Retake photo'),
        ),
      ],
    );
  }

  Widget _fact(String label, String value, {bool mono = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: PpgColors.textSecondary,
            ),
          ),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: mono
                ? PpgText.mono(size: 14)
                : PpgText.figures(size: 14, weight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}
