import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/models.dart';
import '../domain/validation.dart';
import '../services/ppg_session_controller.dart';
import '../ui/ppg_format.dart';
import '../ui/ppg_tokens.dart';
import '../ui/ppg_widgets.dart';

/// Operator-facing state of one receiving line's physical count.
({String label, PpgTone tone}) ppgCountStatus(DocumentLine line) {
  if (line.needsArticleReconciliation ||
      line.physicalCountState == PhysicalCountState.recheck) {
    return (label: 'Recheck', tone: PpgTone.warning);
  }
  return switch (line.physicalCountState) {
    PhysicalCountState.notChecked => (label: 'To count', tone: PpgTone.neutral),
    PhysicalCountState.counting => (label: 'Counting', tone: PpgTone.info),
    PhysicalCountState.verified =>
      line.variance == 0
          ? (label: 'Verified', tone: PpgTone.success)
          : (
              label: line.variance < 0
                  ? 'Short ${-line.variance}'
                  : 'Extra ${line.variance}',
              tone: PpgTone.warning,
            ),
    PhysicalCountState.recheck => (label: 'Recheck', tone: PpgTone.warning),
  };
}

/// Count controls for one item, shown in a bottom sheet from the count list.
/// Every count starts at zero; the DN quantity is never copied into it.
class PpgCountSheet extends StatelessWidget {
  const PpgCountSheet({
    super.key,
    required this.controller,
    required this.occurrenceId,
    required this.onScan,
  });

  final PpgSessionController controller;
  final String occurrenceId;

  /// Opens the can scanner for this item.
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final line = controller.lines
            .where((item) => item.occurrenceId == occurrenceId)
            .firstOrNull;
        if (line == null) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Text('This item is no longer on the delivery note.'),
          );
        }
        final readOnly = controller.session?.isSubmitted == true;
        final enabled =
            controller.sourceReviewReady &&
            !readOnly &&
            !controller.savingPhysicalCounts;
        final status = ppgCountStatus(line);
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            line.articleNumber,
                            style: PpgText.mono(size: 22),
                          ),
                          Text(
                            [
                              if (line.productContext != null)
                                line.productContext!,
                              'DN page ${line.sourcePage}',
                            ].join(' · '),
                            style: const TextStyle(
                              fontSize: 14,
                              color: PpgColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PpgStatusBadge(label: status.label, tone: status.tone),
                  ],
                ),
                const SizedBox(height: PpgSpace.l),
                _figures(line),
                const SizedBox(height: PpgSpace.l),
                if (!controller.sourceReviewReady && !readOnly) ...[
                  const PpgBanner(
                    tone: PpgTone.warning,
                    message:
                        'Finish the document checks before counting. Counts already saved are kept.',
                  ),
                  const SizedBox(height: PpgSpace.l),
                ],
                ..._controls(context, line, enabled, readOnly),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _figures(DocumentLine line) {
    final remaining = line.documentQuantity - line.physicalQuantity;
    final second = !line.hasPhysicalCount
        ? ('Counted', '0 ${line.unit}')
        : line.isPhysicalVerified
        ? (
            'Difference',
            line.variance == 0
                ? 'None'
                : '${ppgSigned(line.variance)} ${line.unit}',
          )
        : remaining >= 0
        ? ('Still to match', '$remaining ${line.unit}')
        : ('Above DN', '${-remaining} ${line.unit}');
    Widget tile(String label, String value) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: PpgColors.ground,
          borderRadius: BorderRadius.circular(PpgRadii.medium),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: PpgColors.textSecondary,
              ),
            ),
            Text(
              value,
              style: PpgText.figures(size: 20, weight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
    return Row(
      children: [
        tile('On DN', '${line.documentQuantity} ${line.unit}'),
        const SizedBox(width: PpgSpace.s),
        tile(second.$1, second.$2),
      ],
    );
  }

  List<Widget> _controls(
    BuildContext context,
    DocumentLine line,
    bool enabled,
    bool readOnly,
  ) {
    if (readOnly || line.isPhysicalVerified) {
      return [
        Container(
          height: PpgSizes.counter,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PpgRadii.large),
            border: Border.all(color: PpgColors.line),
          ),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${line.physicalQuantity}',
                  style: PpgText.figures(size: 32),
                ),
                TextSpan(
                  text: ' ${line.unit} counted',
                  style: const TextStyle(
                    fontSize: 15,
                    color: PpgColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: PpgSpace.m),
        PpgBanner(
          tone: line.variance == 0 ? PpgTone.success : PpgTone.warning,
          title: line.isPhysicalVerified ? 'Count verified' : null,
          message: line.variance == 0
              ? 'Matches the DN.'
              : '${line.variance < 0 ? 'Short' : 'Extra'} ${line.variance.abs()} ${line.unit}. ${line.varianceReason ?? ''}'
                    .trim(),
        ),
        if (!readOnly) ...[
          const SizedBox(height: PpgSpace.m),
          OutlinedButton(
            onPressed: enabled
                ? () => ppgRun(
                    context,
                    () => controller.reopenPhysicalCount(line.occurrenceId),
                  )
                : null,
            child: const Text('Reopen count'),
          ),
        ],
      ];
    }
    if (line.needsArticleReconciliation) {
      return [
        PpgBanner(
          tone: PpgTone.warning,
          title: 'Recheck this count',
          message:
              'The saved count of ${line.physicalQuantity} ${line.unit} was made for article ${line.countedArticleNumber ?? 'unknown'}. The DN now reads ${line.articleNumber}.',
        ),
        const SizedBox(height: PpgSpace.m),
        FilledButton(
          onPressed: enabled ? () => _reconcileArticle(context, line) : null,
          child: const Text('Recheck the count'),
        ),
      ];
    }
    if (!line.hasPhysicalCount) {
      return [
        _counter(context, line, enabled: false),
        const SizedBox(height: PpgSpace.m),
        FilledButton(
          onPressed: enabled
              ? () => ppgRun(
                  context,
                  () => controller.startPhysicalCount(line.occurrenceId),
                  failurePrefix: 'Count not saved.',
                )
              : null,
          child: const Text('Start count'),
        ),
        const SizedBox(height: PpgSpace.s),
        Row(
          children: [
            Expanded(child: _scanButton(enabled)),
            const SizedBox(width: PpgSpace.s),
            Expanded(
              child: OutlinedButton(
                onPressed: enabled
                    ? () => _editQuantity(context, line, batch: false)
                    : null,
                child: const Text('Type a total'),
              ),
            ),
          ],
        ),
      ];
    }
    final remaining = line.documentQuantity - line.physicalQuantity;
    return [
      _counter(context, line, enabled: enabled),
      const SizedBox(height: PpgSpace.m),
      Row(
        children: [
          Expanded(child: _scanButton(enabled)),
          const SizedBox(width: PpgSpace.s),
          Expanded(
            child: OutlinedButton(
              onPressed: enabled
                  ? () => _editQuantity(context, line, batch: true)
                  : null,
              child: const Text('Add a batch'),
            ),
          ),
        ],
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: enabled
              ? () => _editQuantity(context, line, batch: false)
              : null,
          child: const Text('Type the counted total'),
        ),
      ),
      FilledButton(
        style: FilledButton.styleFrom(backgroundColor: PpgColors.navy),
        onPressed: enabled ? () => _finish(context, line) : null,
        child: Text('Finish count at ${line.physicalQuantity} ${line.unit}'),
      ),
      const SizedBox(height: PpgSpace.s),
      PpgHint(
        remaining == 0
            ? 'Matches the DN quantity'
            : remaining > 0
            ? 'Finishing below ${line.documentQuantity} ${line.unit} asks for a reason'
            : 'Finishing above ${line.documentQuantity} ${line.unit} asks for a reason',
      ),
    ];
  }

  Widget _scanButton(bool enabled) => OutlinedButton.icon(
    onPressed: enabled ? onScan : null,
    icon: const Icon(Icons.qr_code_scanner, size: 20),
    label: const Text('Scan this item'),
  );

  Widget _counter(
    BuildContext context,
    DocumentLine line, {
    required bool enabled,
  }) {
    final count = line.hasPhysicalCount ? line.physicalQuantity : 0;
    return Row(
      children: [
        SizedBox.square(
          dimension: PpgSizes.counter,
          child: IconButton.outlined(
            tooltip: 'Remove one can',
            style: IconButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(PpgRadii.large),
              ),
              side: const BorderSide(color: PpgColors.control),
            ),
            onPressed: enabled && count > 0
                ? () => ppgRun(
                    context,
                    () => controller.adjustPhysicalCount(
                      occurrenceId: line.occurrenceId,
                      delta: -1,
                    ),
                    failurePrefix: 'Count not saved.',
                  )
                : null,
            icon: const Icon(Icons.remove, size: 26),
          ),
        ),
        const SizedBox(width: PpgSpace.m),
        Expanded(
          child: Semantics(
            button: enabled,
            label:
                '$count ${line.unit} counted${enabled ? '. Tap to type a total' : ''}',
            excludeSemantics: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(PpgRadii.large),
              onTap: enabled
                  ? () => _editQuantity(context, line, batch: false)
                  : null,
              onLongPress: enabled
                  ? () => _editQuantity(context, line, batch: false)
                  : null,
              child: Container(
                height: PpgSizes.counter,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(PpgRadii.large),
                  border: Border.all(
                    color: enabled ? PpgColors.blue : PpgColors.line,
                    width: 2,
                  ),
                ),
                alignment: Alignment.center,
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '$count',
                        style: PpgText.figures(size: 32),
                      ),
                      TextSpan(
                        text: ' ${line.unit} counted',
                        style: const TextStyle(
                          fontSize: 15,
                          color: PpgColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: PpgSpace.m),
        SizedBox.square(
          dimension: PpgSizes.counter,
          child: IconButton.filled(
            tooltip: 'Add one can',
            style: IconButton.styleFrom(
              backgroundColor: PpgColors.blue,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(PpgRadii.large),
              ),
            ),
            onPressed: enabled
                ? () => ppgRun(
                    context,
                    () => controller.adjustPhysicalCount(
                      occurrenceId: line.occurrenceId,
                      delta: 1,
                    ),
                    failurePrefix: 'Count not saved.',
                  )
                : null,
            icon: const Icon(Icons.add, size: 26),
          ),
        ),
      ],
    );
  }

  Future<void> _editQuantity(
    BuildContext context,
    DocumentLine line, {
    required bool batch,
  }) async {
    await controller.waitForPhysicalCounts();
    if (!context.mounted) return;
    final current = controller.lines.firstWhere(
      (item) => item.occurrenceId == line.occurrenceId,
    );
    final quantity = await showDialog<int>(
      context: context,
      builder: (_) => PpgThemed(
        child: _QuantityEntryDialog(line: current, batch: batch),
      ),
    );
    if (quantity == null || !context.mounted) return;
    await ppgRun(
      context,
      () => batch
          ? controller.addPhysicalBatch(
              occurrenceId: line.occurrenceId,
              quantity: quantity,
            )
          : controller.setCountedTotal(
              occurrenceId: line.occurrenceId,
              quantity: quantity,
            ),
      failurePrefix: 'Count not saved.',
    );
  }

  Future<void> _finish(BuildContext context, DocumentLine line) async {
    await controller.waitForPhysicalCounts();
    if (!context.mounted) return;
    final current = controller.lines.firstWhere(
      (item) => item.occurrenceId == line.occurrenceId,
    );
    String? reason = '';
    if (current.variance != 0) {
      reason = await showDialog<String>(
        context: context,
        builder: (_) => PpgThemed(child: _VarianceReasonDialog(line: current)),
      );
    }
    if (reason == null || !context.mounted) return;
    await ppgRun(
      context,
      () => controller.finishPhysicalCount(
        occurrenceId: current.occurrenceId,
        reason: reason!,
        expectedQuantity: current.physicalQuantity,
      ),
      failurePrefix: 'Count not saved.',
    );
  }

  Future<void> _reconcileArticle(
    BuildContext context,
    DocumentLine line,
  ) async {
    final restart = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => PpgThemed(
        child: AlertDialog(
          title: const Text('Recheck the count'),
          content: Text(
            'The saved count of ${line.physicalQuantity} ${line.unit} was made for article ${line.countedArticleNumber}. Check the cans of article ${line.articleNumber}, then keep the count or start again from 0.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Start again from 0'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Checked, keep it'),
            ),
          ],
        ),
      ),
    );
    if (restart == null || !context.mounted) return;
    await ppgRun(
      context,
      () => controller.reconcilePhysicalCount(
        occurrenceId: line.occurrenceId,
        restart: restart,
      ),
    );
  }
}

class _QuantityEntryDialog extends StatefulWidget {
  const _QuantityEntryDialog({required this.line, required this.batch});
  final DocumentLine line;
  final bool batch;
  @override
  State<_QuantityEntryDialog> createState() => _QuantityEntryDialogState();
}

class _QuantityEntryDialogState extends State<_QuantityEntryDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _quantity = TextEditingController(
    text: widget.batch || !widget.line.hasPhysicalCount
        ? ''
        : '${widget.line.physicalQuantity}',
  );
  @override
  void dispose() {
    _quantity.dispose();
    super.dispose();
  }

  void _save() {
    if (_form.currentState?.validate() == true) {
      Navigator.pop(context, int.parse(_quantity.text.trim()));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(widget.batch ? 'Add a batch' : 'Set counted total'),
    content: Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.line.articleNumber} · On DN ${widget.line.documentQuantity} ${widget.line.unit}',
            style: PpgText.mono(size: 14, weight: FontWeight.w500),
          ),
          if (widget.batch)
            Text(
              'Counted so far: ${widget.line.physicalQuantity} ${widget.line.unit}',
            ),
          const SizedBox(height: PpgSpace.m),
          TextFormField(
            controller: _quantity,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: widget.batch
                  ? 'How many arrived in this batch?'
                  : 'Total counted',
              suffixText: widget.line.unit,
            ),
            onFieldSubmitted: (_) => _save(),
            validator: (value) {
              final error = PpgValidation.validatePhysicalInput(value ?? '');
              if (error != null) return error;
              if (widget.batch && int.parse(value!.trim()) == 0) {
                return 'A batch needs at least 1';
              }
              return null;
            },
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _save,
        child: Text(widget.batch ? 'Add to count' : 'Save total'),
      ),
    ],
  );
}

class _VarianceReasonDialog extends StatefulWidget {
  const _VarianceReasonDialog({required this.line});
  final DocumentLine line;
  @override
  State<_VarianceReasonDialog> createState() => _VarianceReasonDialogState();
}

class _VarianceReasonDialogState extends State<_VarianceReasonDialog> {
  final _form = GlobalKey<FormState>();
  final _details = TextEditingController();
  String? _reason;
  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final line = widget.line;
    final reasons = line.variance < 0
        ? ['Short received', 'Not received', 'Damaged items excluded', 'Other']
        : ['Extra received', 'Other'];
    return AlertDialog(
      scrollable: true,
      title: Text(
        '${line.variance < 0 ? 'Short' : 'Extra'} ${line.variance.abs()} ${line.unit}',
      ),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You counted ${line.physicalQuantity} ${line.unit} of ${line.articleNumber}; the DN says ${line.documentQuantity}. Choose why.',
            ),
            const SizedBox(height: PpgSpace.l),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'Variance reason'),
              items: reasons
                  .map(
                    (reason) =>
                        DropdownMenuItem(value: reason, child: Text(reason)),
                  )
                  .toList(),
              onChanged: (reason) => setState(() => _reason = reason),
              validator: (reason) => reason == null ? 'Choose a reason' : null,
              isExpanded: true,
            ),
            const SizedBox(height: PpgSpace.m),
            TextFormField(
              controller: _details,
              decoration: const InputDecoration(
                labelText: 'Details (needed for Other)',
              ),
              maxLines: 2,
              validator: (value) =>
                  _reason == 'Other' && (value?.trim().isEmpty ?? true)
                  ? 'Explain the variance'
                  : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_form.currentState?.validate() != true) return;
            Navigator.pop(
              context,
              _details.text.trim().isEmpty
                  ? _reason
                  : '$_reason: ${_details.text.trim()}',
            );
          },
          child: const Text('Verify count'),
        ),
      ],
    );
  }
}
