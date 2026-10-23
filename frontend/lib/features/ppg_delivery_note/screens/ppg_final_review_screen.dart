import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/models.dart';
import '../services/ppg_session_controller.dart';
import '../ui/ppg_format.dart';
import '../ui/ppg_navigation.dart';
import '../ui/ppg_page_status.dart';
import '../ui/ppg_tokens.dart';
import '../ui/ppg_widgets.dart';
import 'ppg_confirmation_screen.dart';
import 'ppg_session_screen.dart';

/// Stage 3 · Submit: totals, differences and the checks behind them.
class PpgFinalReviewScreen extends StatefulWidget {
  const PpgFinalReviewScreen({super.key});
  @override
  State<PpgFinalReviewScreen> createState() => _PpgFinalReviewScreenState();
}

class _PpgFinalReviewScreenState extends State<PpgFinalReviewScreen> {
  bool _submitting = false;

  @override
  Widget build(BuildContext context) => Consumer<PpgSessionController>(
    builder: (context, ctrl, _) {
      final s = ctrl.session;
      final readOnly = s?.isSubmitted == true;
      final lines = ppgOrderedLines(ctrl);
      final differences = lines
          .where((line) => line.isPhysicalVerified && line.variance != 0)
          .toList();
      final matched = lines
          .where((line) => line.isPhysicalVerified && line.variance == 0)
          .length;
      final docTotal = ctrl.documentQuantityTotal;
      final counted = ctrl.verifiedPhysicalTotal;
      final declared = s?.declaredPageCount ?? ctrl.pages.length;
      final checkedPages = ctrl.pages
          .where((p) => p.pageReviewConfirmed)
          .length;
      final allVerified =
          lines.isNotEmpty && lines.every((line) => line.isPhysicalVerified);
      final reasonsGiven = differences.every(
        (line) => line.varianceReason?.trim().isNotEmpty ?? false,
      );
      final (PpgTone tone, String message) = !allVerified
          ? (
              PpgTone.warning,
              '${ppgPlural(lines.length - ctrl.verifiedPhysicalCount, 'item')} still need a verified count.',
            )
          : counted != docTotal
          ? (
              PpgTone.warning,
              'Counted ${(counted - docTotal).abs()} PC ${counted < docTotal ? 'less' : 'more'} than the DN. Check the reasons below.',
            )
          : differences.isNotEmpty
          ? (
              PpgTone.warning,
              'Totals match, but ${ppgPlural(differences.length, 'item')} ${differences.length == 1 ? 'differs' : 'differ'}. Check the reasons below.',
            )
          : (PpgTone.success, 'Everything counted matches the DN.');
      return PpgThemed(
        child: PopScope(
          canPop: !_submitting,
          child: Scaffold(
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PpgHeader(
                  eyebrow: 'Delivery note',
                  title: s?.deliveryNoteNumber ?? '—',
                  monoTitle: true,
                  stage: 2,
                  completedStages: {
                    if (ctrl.sourceReviewReady) 0,
                    if (allVerified) 1,
                    if (readOnly) 2,
                  },
                  backTooltip: 'Back to count list',
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    children: [
                      PpgPanel(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                _total('On delivery note', docTotal),
                                _total('Counted', counted),
                              ],
                            ),
                            const SizedBox(height: PpgSpace.m),
                            PpgBanner(tone: tone, message: message),
                          ],
                        ),
                      ),
                      const SizedBox(height: PpgSpace.l),
                      PpgSectionLabel('Differences · ${differences.length}'),
                      const SizedBox(height: PpgSpace.s),
                      if (differences.isNotEmpty)
                        PpgPanel(
                          child: Column(
                            children: ppgDivided(
                              differences.map(_differenceRow),
                            ),
                          ),
                        )
                      else
                        const PpgHint(
                          'No differences recorded.',
                          center: false,
                        ),
                      if (matched > 0) ...[
                        const SizedBox(height: PpgSpace.s),
                        PpgHint(
                          '${ppgPlural(matched, 'other item')} ${matched == 1 ? 'matches' : 'match'} the DN exactly.',
                          center: false,
                        ),
                      ],
                      const SizedBox(height: PpgSpace.l),
                      const PpgSectionLabel('Checks'),
                      const SizedBox(height: PpgSpace.xs),
                      PpgCheckLine(
                        done: ctrl.sourceReviewReady,
                        text: ctrl.sourceReviewReady
                            ? 'All $declared DN pages checked'
                            : '$checkedPages of $declared DN pages checked',
                        onTap: ctrl.sourceReviewReady || readOnly || s == null
                            ? null
                            : () => ppgPush<void>(
                                context,
                                ctrl,
                                PpgSessionScreen(
                                  sessionId: s.id,
                                  openedFromCount: true,
                                ),
                              ),
                      ),
                      PpgCheckLine(
                        done: allVerified,
                        text: allVerified
                            ? 'All ${lines.length} items counted and verified'
                            : '${ctrl.verifiedPhysicalCount} of ${lines.length} items verified',
                        onTap: allVerified || readOnly
                            ? null
                            : () => Navigator.pop(context),
                      ),
                      PpgCheckLine(
                        done: reasonsGiven,
                        text: differences.isEmpty
                            ? 'No differences need a reason'
                            : 'Every difference has a reason',
                      ),
                    ],
                  ),
                ),
              ],
            ),
            bottomNavigationBar: PpgBottomBar(
              children: [
                FilledButton(
                  onPressed: readOnly
                      ? () => _openReceipt(ctrl)
                      : _submitting || !ctrl.readyForFinalReview
                      ? null
                      : () => _submit(ctrl),
                  child: Text(
                    readOnly
                        ? 'View receipt'
                        : _submitting
                        ? 'Saving…'
                        : 'Submit receiving form',
                  ),
                ),
                if (!readOnly)
                  const PpgHint(
                    'Saved on this device. It is not sent to a server, and it can\'t be edited after you submit.',
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _total(String label, int value) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: PpgColors.textSecondary),
        ),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: '$value', style: PpgText.figures(size: 32)),
              const TextSpan(
                text: ' PC',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: PpgColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _differenceRow(DocumentLine line) => PpgRow(
    title: line.articleNumber,
    monoTitle: true,
    subtitle:
        '${line.physicalQuantity} of ${line.documentQuantity} ${line.unit} · ${line.varianceReason ?? 'No reason given'}',
    trailing: Text(
      '${ppgSigned(line.variance)} ${line.unit}',
      style: PpgText.figures(
        size: 15,
        color: line.variance < 0
            ? PpgTone.danger.foreground
            : PpgTone.info.foreground,
      ),
    ),
  );

  Future<void> _submit(PpgSessionController ctrl) async {
    final dn = ctrl.session?.deliveryNoteNumber ?? '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => PpgThemed(
        child: AlertDialog(
          title: const Text('Submit this receiving form?'),
          content: Text(
            'DN $dn will be saved on this device and can\'t be changed afterwards.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Not yet'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _submitting = true);
    final ok = await ppgRun(context, () async {
      await ctrl.confirmReview();
      await ctrl.submit();
    }, failurePrefix: 'Not submitted.');
    if (!mounted) return;
    setState(() => _submitting = false);
    if (ok) _openReceipt(ctrl);
  }

  void _openReceipt(PpgSessionController ctrl) {
    ppgPush<void>(context, ctrl, const PpgConfirmationScreen(), replace: true);
  }
}
