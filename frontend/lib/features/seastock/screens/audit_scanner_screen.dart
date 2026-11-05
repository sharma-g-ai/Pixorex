import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../ppg_delivery_note/services/can_reader_camera.dart';
import '../../ppg_delivery_note/ui/ppg_tokens.dart';
import '../../ppg_delivery_note/ui/ppg_widgets.dart';
import '../services/seastock_controller.dart';
import '../ui/seastock_widgets.dart';

/// Counts cans for an audit. Each confirmed read adds one; the sheet shows
/// how many of the article are counted, never what the inventory expects.
class AuditScannerScreen extends StatefulWidget {
  const AuditScannerScreen({super.key, this.camera});

  /// Injected in tests.
  final CanReaderCamera? camera;

  @override
  State<AuditScannerScreen> createState() => _AuditScannerScreenState();
}

class _AuditScannerScreenState extends State<AuditScannerScreen>
    with WidgetsBindingObserver {
  late final SeastockController _ctrl;
  late final CanReaderCamera _reader;
  String? _article;
  String? _added;

  /// The count before the current read added one, so Undo can restore it
  /// (null: the article had not been counted).
  int? _before;
  bool _addedByScan = false;

  @override
  void initState() {
    super.initState();
    _ctrl = context.read<SeastockController>();
    _reader =
        widget.camera ??
        CanReaderCamera(
          knownArticles: () =>
              _ctrl.stock.items.map((item) => item.articleNumber).toSet(),
          onConfirmed: (article) {
            if (mounted) _found(article);
          },
        );
    WidgetsBinding.instance.addObserver(this);
    _reader.open();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reader.open();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _reader.close();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reader.dispose();
    super.dispose();
  }

  Future<void> _found(String article) async {
    final before = _ctrl.audit?[article];
    final ok = await ppgRun(context, () => _ctrl.addAuditCan(article));
    if (!mounted) return;
    setState(() {
      _article = article;
      _before = before;
      _addedByScan = ok;
    });
  }

  void _scanAgain({String? added}) {
    setState(() {
      _article = null;
      _added = added;
      _addedByScan = false;
      _before = null;
    });
    _reader.scanAgain();
  }

  void _next() {
    final article = _article!;
    _scanAgain(
      added:
          '${_ctrl.audit?[article] ?? 0} × $article counted. Scan the next can.',
    );
  }

  Future<void> _undo() async {
    final article = _article!;
    final before = _before;
    await ppgRun(
      context,
      () => before == null
          ? _ctrl.clearAuditCount(article)
          : _ctrl.setAuditCount(article, before),
    );
    if (mounted) _scanAgain(added: _added);
  }

  Future<void> _chooseByHand() async {
    _reader.hold();
    final article = await showSeastockSheet<String>(
      context,
      _AuditArticlePicker(controller: _ctrl),
    );
    if (!mounted) return;
    if (article == null) {
      _scanAgain(added: _added);
    } else {
      await _found(article);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_ctrl, _reader]),
    builder: (context, _) => AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: PpgColors.camera,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _preview(),
                  _topBar(),
                  if (_reader.cameraError == null && _article == null)
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 16,
                      child: Center(
                        child: Semantics(
                          liveRegion: true,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: PpgColors.cameraChrome,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              _reader.guidance,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            _sheet(),
            _tray(),
          ],
        ),
      ),
    ),
  );

  Widget _preview() {
    final camera = _reader.camera;
    if (_reader.cameraError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 88, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.no_photography_outlined,
                size: 48,
                color: PpgColors.onNavyMuted,
              ),
              const SizedBox(height: PpgSpace.m),
              Text(
                _reader.unsupported
                    ? '${_reader.cameraError} Choose each article by hand below.'
                    : _reader.cameraError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
              if (!_reader.unsupported) ...[
                const SizedBox(height: PpgSpace.l),
                FilledButton.icon(
                  onPressed: _reader.open,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              ],
            ],
          ),
        ),
      );
    }
    if (camera != null && camera.value.isInitialized) {
      return ClipRect(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: 1000,
            height: 1000 * camera.value.aspectRatio,
            child: CameraPreview(camera),
          ),
        ),
      );
    }
    return const Center(
      child: CircularProgressIndicator(
        color: Colors.white,
        semanticsLabel: 'Starting camera',
      ),
    );
  }

  Widget _chrome(Widget child) => DecoratedBox(
    decoration: BoxDecoration(
      color: PpgColors.cameraChrome,
      borderRadius: BorderRadius.circular(999),
    ),
    child: child,
  );

  Widget _topBar() {
    final camera = _reader.camera;
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.all(PpgSpace.m),
          child: Row(
            children: [
              _chrome(
                IconButton(
                  tooltip: 'Close scanner',
                  color: Colors.white,
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Icons.close),
                ),
              ),
              const SizedBox(width: PpgSpace.s),
              Expanded(
                child: _chrome(
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.fact_check_outlined,
                          size: 18,
                          color: Color(0xFFFDBA74),
                        ),
                        const SizedBox(width: PpgSpace.s),
                        Expanded(
                          child: Text(
                            'Auditing · ${_ctrl.vessel.name}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (camera != null && camera.value.isInitialized) ...[
                const SizedBox(width: PpgSpace.s),
                _chrome(
                  IconButton(
                    tooltip: camera.value.flashMode == FlashMode.torch
                        ? 'Turn off torch'
                        : 'Turn on torch',
                    color: Colors.white,
                    icon: Icon(
                      camera.value.flashMode == FlashMode.torch
                          ? Icons.flashlight_off_outlined
                          : Icons.flashlight_on_outlined,
                    ),
                    onPressed: () async {
                      try {
                        await _reader.toggleTorch();
                      } catch (_) {
                        if (mounted) {
                          showPpgMessage(context, 'This camera has no torch.');
                        }
                      }
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheet() {
    final article = _article;
    final children = <Widget>[];
    if (article == null) {
      children.addAll([
        _headline(
          _added == null ? Icons.qr_code_scanner : Icons.check,
          _added == null ? PpgTone.info : PpgTone.success,
          _added ?? 'Point at the Article no. on the can',
        ),
        const SizedBox(height: PpgSpace.s),
        TextButton.icon(
          key: const ValueKey('audit-choose-by-hand'),
          onPressed: _chooseByHand,
          icon: const Icon(Icons.keyboard_outlined),
          label: const Text('Can\'t scan? Choose the article'),
        ),
      ]);
    } else {
      final onList = _ctrl.auditList.any(
        (item) => item.articleNumber == article,
      );
      final product = _ctrl.productOf(article);
      final count = _ctrl.audit?[article] ?? 0;
      children.addAll([
        _headline(
          onList ? Icons.check : Icons.add_circle_outline,
          onList ? PpgTone.success : PpgTone.warning,
          _addedByScan
              ? (onList
                    ? 'Added 1 can · on the count list'
                    : 'Added 1 can · not in inventory')
              : (onList ? 'On the count list' : 'Not in inventory'),
        ),
        const SizedBox(height: PpgSpace.m),
        Text(article, style: PpgText.mono(size: 24)),
        if (product != null)
          Text(
            product,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              color: PpgColors.textSecondary,
            ),
          ),
        if (!onList) ...[
          const SizedBox(height: PpgSpace.s),
          const PpgBanner(
            tone: PpgTone.warning,
            message:
                'This article is not on the inventory. It goes in the report as found, for the vessel manager to decide.',
          ),
        ],
        const SizedBox(height: PpgSpace.m),
        SeastockCounter(
          key: const ValueKey('audit-counter'),
          label: 'Counted on board',
          value: count,
          onChanged: (value) =>
              ppgRun(context, () => _ctrl.setAuditCount(article, value)),
        ),
        const SizedBox(height: PpgSpace.m),
        Row(
          children: [
            if (_addedByScan) ...[
              TextButton(
                key: const ValueKey('audit-undo'),
                onPressed: _undo,
                child: const Text('Wrong can? Undo'),
              ),
              const SizedBox(width: PpgSpace.s),
            ],
            Expanded(
              child: FilledButton.icon(
                key: const ValueKey('audit-scan-next'),
                style: FilledButton.styleFrom(
                  backgroundColor: PpgColors.navy,
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: _next,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scan next can'),
              ),
            ),
          ],
        ),
      ]);
    }
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(PpgRadii.sheet),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _headline(IconData icon, PpgTone tone, String text) => Row(
    children: [
      Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: tone.background,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 16, color: tone.foreground),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          text,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: tone == PpgTone.info ? PpgColors.navy : tone.foreground,
          ),
        ),
      ),
    ],
  );

  Widget _tray() {
    final counted = _ctrl.auditCountedArticles;
    final total = _ctrl.auditList.length;
    final found = _ctrl.auditFound.length;
    return Material(
      color: PpgColors.navy,
      child: InkWell(
        key: const ValueKey('audit-tray'),
        onTap: () => Navigator.maybePop(context),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Row(
              children: [
                Container(
                  constraints: const BoxConstraints(minWidth: 44),
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFDBA74),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$counted/$total',
                    style: PpgText.figures(size: 15, color: PpgColors.navy),
                  ),
                ),
                const SizedBox(width: PpgSpace.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Articles counted',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        found == 0
                            ? 'Nothing is sent until you finish'
                            : 'Plus $found found, not in inventory',
                        style: const TextStyle(
                          color: PpgColors.onNavyMuted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const Text(
                  'Count list',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Picks an article on the count list by hand, for when a label can't be
/// scanned. Shows no expected figures.
class _AuditArticlePicker extends StatefulWidget {
  const _AuditArticlePicker({required this.controller});

  final SeastockController controller;

  @override
  State<_AuditArticlePicker> createState() => _AuditArticlePickerState();
}

class _AuditArticlePickerState extends State<_AuditArticlePicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final items = widget.controller.auditList
        .where(
          (item) =>
              q.isEmpty ||
              item.articleNumber.contains(q) ||
              (item.product?.toLowerCase().contains(q) ?? false),
        )
        .toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Choose the article',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const Text(
              'Use the Article no. printed on the can.',
              style: TextStyle(fontSize: 14, color: PpgColors.textSecondary),
            ),
            const SizedBox(height: PpgSpace.m),
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Article no. or label name',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: PpgSpace.m),
            Flexible(
              child: items.isEmpty
                  ? const PpgHint('No article on the count list matches.')
                  : SingleChildScrollView(
                      child: PpgPanel(
                        child: Column(
                          children: ppgDivided([
                            for (final item in items)
                              PpgRow(
                                key: ValueKey('pick-${item.articleNumber}'),
                                title: item.articleNumber,
                                monoTitle: true,
                                subtitle: item.product,
                                onTap: () =>
                                    Navigator.pop(context, item.articleNumber),
                              ),
                          ]),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
