import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/ppg_session_controller.dart';
import '../ui/ppg_tokens.dart';
import '../ui/ppg_widgets.dart';

/// DN reconciliation belongs to source checking, never to physical counting.
class PpgSourceSummary extends StatelessWidget {
  const PpgSourceSummary({super.key, required this.controller});

  final PpgSessionController controller;

  @override
  Widget build(BuildContext context) {
    final ctrl = controller;
    final readOnly = ctrl.session?.isSubmitted == true;
    final pageOne = ctrl.pages
        .where((page) => page.printedPage == 1)
        .firstOrNull;
    final printed = ctrl.printedPieceCount;
    final mismatch = ctrl.pieceCountSummaryMismatch && pageOne != null;
    final total = ctrl.documentQuantityTotal;
    final matches = !mismatch && printed != null && printed == total;
    final tone = mismatch
        ? PpgTone.danger
        : matches
        ? PpgTone.success
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PpgSectionLabel('DN totals'),
        const SizedBox(height: PpgSpace.s),
        PpgPanel(
          tone: tone,
          fill: tone?.background,
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (tone != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8, bottom: 8),
                  child: Row(
                    children: [
                      Icon(
                        mismatch
                            ? Icons.warning_amber_rounded
                            : Icons.check_circle_outline,
                        size: 18,
                        color: tone.foreground,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          mismatch
                              ? 'Does not match: ${_differenceText(total - printed!)}'
                              : 'Matches the printed piece count',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: tone.foreground,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              _figure('Items read from the DN', '$total PC'),
              _figure(
                'Printed piece count on page 1',
                printed == null ? 'Not readable' : '$printed PC',
              ),
              if (printed == null)
                const Padding(
                  padding: EdgeInsets.only(top: 4, right: 8),
                  child: PpgHint(
                    'The printed total is optional. Check each item row instead.',
                    center: false,
                  ),
                ),
              if (mismatch)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: pageOne.pieceCountVarianceReviewed,
                  onChanged: readOnly
                      ? null
                      : (value) => ppgRun(
                          context,
                          () => ctrl.confirmPieceCountDiscrepancy(
                            reviewed: value ?? false,
                          ),
                        ),
                  title: const Text(
                    'I checked this difference against the paper',
                    style: TextStyle(fontSize: 14),
                  ),
                  subtitle: const Text(
                    'Item quantities stay as read. Only the summary differs.',
                    style: TextStyle(fontSize: 13),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              if (!readOnly && pageOne != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => _correctPiece(context, ctrl),
                    child: const Text('Correct the printed piece count'),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  static String _differenceText(int diff) => diff > 0
      ? '$diff PC more than printed'
      : '${-diff} PC fewer than printed';

  Widget _figure(String label, String value) => Padding(
    padding: const EdgeInsets.only(right: 8, bottom: 6),
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
        Text(value, style: PpgText.figures(size: 15)),
      ],
    ),
  );

  Future<void> _correctPiece(
    BuildContext context,
    PpgSessionController ctrl,
  ) async {
    final value = TextEditingController(
      text: ctrl.printedPieceCount?.toString() ?? '',
    );
    final reason = TextEditingController();
    final form = GlobalKey<FormState>();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => PpgThemed(
        child: AlertDialog(
          scrollable: true,
          title: const Text('Correct the printed piece count'),
          content: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Type the total piece count printed in the summary on page 1.',
                ),
                const SizedBox(height: PpgSpace.m),
                TextFormField(
                  controller: value,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Printed piece count',
                    suffixText: 'PC',
                  ),
                  validator: (text) => int.tryParse(text?.trim() ?? '') == null
                      ? 'Type a whole number'
                      : null,
                ),
                const SizedBox(height: PpgSpace.m),
                TextFormField(
                  controller: reason,
                  decoration: const InputDecoration(
                    labelText: 'Why is it being corrected?',
                  ),
                  validator: (text) => text?.trim().isNotEmpty == true
                      ? null
                      : 'Give a short reason',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (form.currentState?.validate() == true) {
                  Navigator.pop(dialogContext, true);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true || !context.mounted) return;
    await ppgRun(
      context,
      () => ctrl.correctPrintedPieceCount(
        pieceCount: int.parse(value.text.trim()),
        reason: reason.text.trim(),
      ),
    );
  }
}
