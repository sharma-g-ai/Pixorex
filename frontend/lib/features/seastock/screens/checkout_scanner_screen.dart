import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../ppg_delivery_note/services/can_reader_camera.dart';
import '../../ppg_delivery_note/ui/ppg_format.dart';
import '../../ppg_delivery_note/ui/ppg_tokens.dart';
import '../../ppg_delivery_note/ui/ppg_widgets.dart';
import '../services/seastock_controller.dart';
import '../ui/seastock_widgets.dart';
import 'checkout_review_screen.dart';

/// Scans cans onto a check-out list: each confirmed read adds one can, and a
/// counter fixes the number. Nothing is deducted until the list is confirmed
/// on the review screen.
class CheckoutScannerScreen extends StatefulWidget {
  const CheckoutScannerScreen({super.key, this.camera});

  /// Injected in tests.
  final CanReaderCamera? camera;

  @override
  State<CheckoutScannerScreen> createState() => _CheckoutScannerScreenState();
}

class _CheckoutScannerScreenState extends State<CheckoutScannerScreen>
    with WidgetsBindingObserver {
  late final SeastockController _ctrl;
  late final CanReaderCamera _reader;
  String? _article;
  String? _added;

  /// The current read added one can, so Undo can take it back.
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

  void _scanAgain({String? added}) {
    setState(() {
      _article = null;
      _added = added;
      _addedByScan = false;
    });
    _reader.scanAgain();
  }

  /// A confirmed read, or an article chosen by hand: adds one can if any are
  /// left to take.
  void _found(String article) {
    var added = false;
    if (_ctrl.available(article) > 0) {
      _ctrl.addToBasket(article);
      added = true;
    }
    setState(() {
      _article = article;
      _addedByScan = added;
    });
  }

  void _next() {
    final article = _article!;
    final quantity = _ctrl.basket[article] ?? 0;
    _scanAgain(
      added: quantity == 0
          ? null
          : '$quantity × $article on this check-out. Scan the next can.',
    );
  }

  void _undo() {
    final article = _article!;
    _setQuantity(article, (_ctrl.basket[article] ?? 1) - 1);
    _scanAgain(added: _added);
  }

  void _setQuantity(String article, int quantity) {
    try {
      _ctrl.setBasketQuantity(article, quantity);
    } catch (error) {
      showPpgError(context, error);
    }
  }

  Future<void> _chooseByHand() async {
    _reader.hold();
    final article = await showSeastockSheet<String>(
      context,
      SeastockArticlePicker(controller: _ctrl),
    );
    if (!mounted) return;
    if (article == null) {
      _scanAgain(added: _added);
    } else {
      _found(article);
    }
  }

  Future<void> _review() async {
    _reader.hold();
    await seastockPush<void>(context, _ctrl, const CheckoutReviewScreen());
    if (mounted) _scanAgain();
  }

  Future<bool> _confirmLeave() async {
    if (_ctrl.basket.isEmpty) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => PpgThemed(
        child: AlertDialog(
          title: const Text('Discard this check-out?'),
          content: Text(
            '${_ctrl.basketTotal} PC are on the list. Nothing has been deducted yet.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep scanning'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Discard'),
            ),
          ],
        ),
      ),
    );
    if (leave == true) _ctrl.clearBasket();
    return leave == true;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_ctrl, _reader]),
    builder: (context, _) => AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: PopScope(
        canPop: _ctrl.basket.isEmpty,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          if (await _confirmLeave() && context.mounted) {
            Navigator.of(context).pop();
          }
        },
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
                  tooltip: 'Close check-out',
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
                          Icons.upload_outlined,
                          size: 18,
                          color: Color(0xFFFDBA74),
                        ),
                        const SizedBox(width: PpgSpace.s),
                        Expanded(
                          child: Text(
                            'Checking out · ${_ctrl.vessel.name}',
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
          key: const ValueKey('seastock-choose-by-hand'),
          onPressed: _ctrl.stock.total == 0 ? null : _chooseByHand,
          icon: const Icon(Icons.keyboard_outlined),
          label: const Text('Can\'t scan? Choose the article'),
        ),
      ]);
    } else {
      final item = _ctrl.stock.item(article);
      final onBoard = item?.onBoard ?? 0;
      final left = _ctrl.available(article);
      final already = _ctrl.basket[article] ?? 0;
      if (item == null) {
        children.addAll([
          _headline(Icons.block, PpgTone.warning, 'Not in stock'),
          const SizedBox(height: PpgSpace.m),
          Text(article, style: PpgText.mono(size: 26)),
          const SizedBox(height: PpgSpace.s),
          PpgBanner(
            tone: PpgTone.warning,
            message:
                'This article has never been checked in on ${_ctrl.vessel.name}. Check the label, or check the can in on its delivery note first.',
          ),
          const SizedBox(height: PpgSpace.m),
          _primary('Scan another can', _scanAgain),
        ]);
      } else {
        children.addAll([
          _addedByScan
              ? _headline(
                  Icons.check,
                  PpgTone.success,
                  'Added 1 can · in stock',
                )
              : already > 0
              ? _headline(Icons.check, PpgTone.success, 'On this check-out')
              : _headline(Icons.block, PpgTone.warning, 'None left on board'),
          const SizedBox(height: PpgSpace.m),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(article, style: PpgText.mono(size: 24)),
                    if (item.product != null)
                      Text(
                        item.product!,
                        style: const TextStyle(
                          fontSize: 14,
                          color: PpgColors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'On board',
                    style: TextStyle(
                      fontSize: 12,
                      color: PpgColors.textSecondary,
                    ),
                  ),
                  SeastockQuantity(onBoard, size: 20),
                ],
              ),
            ],
          ),
          const SizedBox(height: PpgSpace.m),
          if (already > 0) ...[
            SeastockCounter(
              key: const ValueKey('seastock-counter'),
              label: 'To check out',
              trailingLabel: '$left left after',
              value: already,
              max: onBoard,
              onChanged: (value) => _setQuantity(article, value),
            ),
            const SizedBox(height: PpgSpace.m),
            Row(
              children: [
                if (_addedByScan)
                  TextButton(
                    key: const ValueKey('seastock-undo'),
                    onPressed: _undo,
                    child: const Text('Wrong can? Undo'),
                  ),
                if (_addedByScan) const SizedBox(width: PpgSpace.s),
                Expanded(
                  child: FilledButton.icon(
                    key: const ValueKey('seastock-scan-next'),
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
          ] else ...[
            PpgBanner(
              tone: PpgTone.warning,
              message:
                  'Every can of this article has been checked out. Check the label, or check this can in on its delivery note first.',
            ),
            const SizedBox(height: PpgSpace.m),
            _primary('Scan another can', _scanAgain),
          ],
        ]);
      }
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

  Widget _primary(String label, VoidCallback onPressed) => FilledButton(
    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
    onPressed: onPressed,
    child: Text(label),
  );

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
    final total = _ctrl.basketTotal;
    final articles = _ctrl.basket.length;
    return Material(
      color: PpgColors.navy,
      child: InkWell(
        key: const ValueKey('seastock-review'),
        onTap: total == 0 ? null : _review,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Row(
              children: [
                Container(
                  constraints: const BoxConstraints(minWidth: 32),
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFDBA74),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$total',
                    style: PpgText.figures(size: 15, color: PpgColors.navy),
                  ),
                ),
                const SizedBox(width: PpgSpace.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'PC on this check-out',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        total == 0
                            ? 'Scan a can to start the list'
                            : '${ppgPlural(articles, 'article')} · nothing deducted yet',
                        style: const TextStyle(
                          color: PpgColors.onNavyMuted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                if (total > 0) ...[
                  const Text(
                    'Review',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.white),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
