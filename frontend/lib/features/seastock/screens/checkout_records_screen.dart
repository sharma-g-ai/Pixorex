import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../ppg_delivery_note/ui/ppg_format.dart';
import '../../ppg_delivery_note/ui/ppg_tokens.dart';
import '../../ppg_delivery_note/ui/ppg_widgets.dart';
import '../domain/stock.dart';
import '../services/seastock_controller.dart';
import '../ui/seastock_widgets.dart';
import 'checkout_scanner_screen.dart';

/// Opens the scanner on an empty check-out list.
Future<void> startCheckout(BuildContext context, SeastockController ctrl) =>
    _startCheckout(Navigator.of(context), ctrl);

Future<void> _startCheckout(NavigatorState navigator, SeastockController ctrl) {
  ctrl.clearBasket();
  return navigator.push<void>(
    seastockRoute<void>(
      ctrl,
      const CheckoutScannerScreen(),
      name: seastockCheckoutRouteName,
    ),
  );
}

/// One confirmed check-out, with stock as it was at the time. Opened from
/// Transactions.
class CheckoutDetailScreen extends StatelessWidget {
  const CheckoutDetailScreen({super.key, required this.record});

  final CheckoutRecord record;

  @override
  Widget build(BuildContext context) {
    final vessel = context.read<SeastockController>().vessel;
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PpgHeader(
            eyebrow: 'Check-out · ${vessel.name}',
            title: record.reference,
            monoTitle: true,
            subtitle:
                '${ppgDateTime(record.createdAt)} · ${record.total} PC checked out',
            backTooltip: 'Back to Transactions',
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
              children: [
                PpgSectionLabel('Articles · ${record.lines.length}'),
                const SizedBox(height: PpgSpace.s),
                PpgPanel(
                  child: Column(
                    children: ppgDivided(
                      record.lines.map(
                        (line) => PpgRow(
                          title: line.articleNumber,
                          monoTitle: true,
                          subtitle: [
                            ?line.product,
                            'on board ${line.onBoardBefore} → ${line.onBoardAfter}',
                          ].join(' · '),
                          trailing: SeastockQuantity(line.quantity),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: PpgSpace.m),
                const PpgHint(
                  'On-board figures are as they were at the time of this check-out. Check-outs can\'t be edited.',
                  center: false,
                ),
                if (record.operatorEmail != null) ...[
                  const SizedBox(height: PpgSpace.s),
                  PpgHint(
                    'Checked out by ${record.operatorEmail}.',
                    center: false,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown after a check-out is confirmed.
class CheckoutDoneScreen extends StatelessWidget {
  const CheckoutDoneScreen({super.key, required this.record});

  final CheckoutRecord record;

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<SeastockController>();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).popUntil((r) => r.isFirst);
      },
      child: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: PpgColors.navy,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 28, 20, 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const CircleAvatar(
                        radius: 24,
                        backgroundColor: PpgColors.stepDone,
                        foregroundColor: PpgColors.navy,
                        child: Icon(Icons.check, size: 28),
                      ),
                      const SizedBox(height: PpgSpace.m),
                      Text(
                        '${record.total} PC checked out',
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        '${ppgDateTime(record.createdAt)} · ${ppgPlural(record.lines.length, 'article')}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: PpgColors.onNavyMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                children: [
                  const PpgSectionLabel('Now on board'),
                  const SizedBox(height: PpgSpace.s),
                  PpgPanel(
                    child: Column(
                      children: ppgDivided(
                        record.lines.map(
                          (line) => PpgRow(
                            title: line.articleNumber,
                            monoTitle: true,
                            subtitle: [
                              ?line.product,
                              '−${line.quantity}',
                            ].join(' · '),
                            trailing: SeastockQuantity(
                              ctrl.stock.onBoard(line.articleNumber),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: PpgSpace.m),
                  PpgHint(
                    'Saved on this device as check-out ${record.reference}. Stock on ${ctrl.vessel.name} is now ${ctrl.stock.total} PC. It is listed in Transactions under Check-outs.',
                    center: false,
                  ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: PpgBottomBar(
          children: [
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
              ),
              onPressed: () =>
                  Navigator.of(context).popUntil((route) => route.isFirst),
              child: const Text('Done'),
            ),
            TextButton(
              onPressed: ctrl.stock.total == 0
                  ? null
                  : () {
                      final navigator = Navigator.of(context);
                      navigator.popUntil((route) => route.isFirst);
                      _startCheckout(navigator, ctrl);
                    },
              child: const Text('Start another check-out'),
            ),
          ],
        ),
      ),
    );
  }
}
