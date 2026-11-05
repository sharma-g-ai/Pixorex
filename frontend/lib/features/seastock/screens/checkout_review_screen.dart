import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../ppg_delivery_note/ui/ppg_format.dart';
import '../../ppg_delivery_note/ui/ppg_tokens.dart';
import '../../ppg_delivery_note/ui/ppg_widgets.dart';
import '../domain/stock.dart';
import '../services/seastock_controller.dart';
import '../ui/seastock_widgets.dart';
import 'checkout_records_screen.dart';

/// The check-out list before anything is deducted: change or remove lines,
/// then confirm the whole list at once.
class CheckoutReviewScreen extends StatefulWidget {
  const CheckoutReviewScreen({super.key});

  @override
  State<CheckoutReviewScreen> createState() => _CheckoutReviewScreenState();
}

class _CheckoutReviewScreenState extends State<CheckoutReviewScreen> {
  bool _saving = false;

  Future<void> _edit(SeastockController ctrl, String article) async {
    final quantity = await showSeastockSheet<int>(
      context,
      SeastockQuantitySheet(
        controller: ctrl,
        articleNumber: article,
        editing: true,
      ),
    );
    if (quantity == null || !mounted) return;
    try {
      ctrl.setBasketQuantity(article, quantity);
    } catch (error) {
      showPpgError(context, error);
    }
  }

  Future<void> _confirm(SeastockController ctrl) async {
    setState(() => _saving = true);
    CheckoutRecord? record;
    final ok = await ppgRun(context, () async {
      record = await ctrl.confirmCheckout();
    }, failurePrefix: 'Not checked out.');
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok || record == null) return;
    final navigator = Navigator.of(context);
    navigator.popUntil((route) => route.isFirst);
    navigator.push<void>(
      seastockRoute<void>(ctrl, CheckoutDoneScreen(record: record!)),
    );
  }

  @override
  Widget build(BuildContext context) => Consumer<SeastockController>(
    builder: (context, ctrl, _) {
      final total = ctrl.basketTotal;
      final articles = ctrl.basket.keys.toList();
      return PopScope(
        canPop: !_saving,
        child: Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PpgHeader(
                eyebrow: 'Check out · ${ctrl.vessel.name}',
                title: 'Review this check-out',
                backTooltip: 'Back to scanner',
              ),
              Material(
                color: Colors.white,
                shape: const Border(bottom: BorderSide(color: PpgColors.line)),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
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
                                text: '$total',
                                style: PpgText.figures(
                                  size: 22,
                                  color: PpgColors.navy,
                                ),
                              ),
                              TextSpan(
                                text:
                                    ' PC from ${ppgPlural(articles.length, 'article')}',
                              ),
                            ],
                          ),
                        ),
                      ),
                      const PpgStatusBadge(
                        label: 'Not deducted yet',
                        tone: PpgTone.warning,
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: articles.isEmpty
                    ? const PpgEmptyState(
                        icon: Icons.playlist_add,
                        title: 'The list is empty',
                        message: 'Go back to the scanner and scan a can.',
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                        children: [
                          PpgPanel(
                            child: Column(
                              children: ppgDivided([
                                for (final article in articles)
                                  _line(ctrl, article),
                              ]),
                            ),
                          ),
                          const SizedBox(height: PpgSpace.m),
                          const PpgHint(
                            'Tap the pencil to change a quantity or remove an article. Stock changes only when you confirm.',
                            center: false,
                          ),
                        ],
                      ),
              ),
            ],
          ),
          bottomNavigationBar: PpgBottomBar(
            children: [
              Row(
                children: [
                  IconButton.outlined(
                    tooltip: 'Scan another can',
                    style: IconButton.styleFrom(
                      fixedSize: const Size.square(56),
                      foregroundColor: PpgColors.link,
                      side: const BorderSide(color: PpgColors.blue, width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.qr_code_scanner),
                  ),
                  const SizedBox(width: PpgSpace.m),
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('seastock-confirm-checkout'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                        textStyle: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onPressed: total == 0 || _saving
                          ? null
                          : () => _confirm(ctrl),
                      child: Text(_saving ? 'Saving…' : 'Check out $total PC'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _line(SeastockController ctrl, String article) {
    final quantity = ctrl.basket[article]!;
    final onBoard = ctrl.stock.onBoard(article);
    return PpgRow(
      key: ValueKey('basket-$article'),
      title: article,
      monoTitle: true,
      subtitle: [
        ?ctrl.productOf(article),
        'on board $onBoard → ${onBoard - quantity}',
      ].join(' · '),
      showChevron: false,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SeastockQuantity(quantity),
          IconButton(
            tooltip: 'Change $article',
            color: PpgColors.link,
            onPressed: _saving ? null : () => _edit(ctrl, article),
            icon: const Icon(Icons.edit_outlined, size: 20),
          ),
        ],
      ),
    );
  }
}
