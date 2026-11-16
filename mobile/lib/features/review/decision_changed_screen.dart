import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../widgets/auth_widgets.dart';
import '../scan/scan_repository.dart';
import 'delegated_models.dart';

/// Design T 77: the BU Admin changed one of my decisions. Nothing to do; "Got it" marks the
/// decision_overridden notification read (contract 3.21), so the batch stops calling it out.
/// Pops true when it was marked.
class DecisionChangedScreen extends StatefulWidget {
  const DecisionChangedScreen({super.key, required this.scans, required this.row, required this.batchNo});
  final ScanRepository scans;
  final Assignment row;
  final String batchNo;

  @override
  State<DecisionChangedScreen> createState() => _DecisionChangedScreenState();
}

class _DecisionChangedScreenState extends State<DecisionChangedScreen> {
  bool _saving = false;

  Future<void> _gotIt() async {
    final o = widget.row.myDecision!.override!;
    if (o.seen || o.notificationId == null) {
      Navigator.of(context).pop(false);
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.scans.markNotificationRead(o.notificationId!);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      // Not marked (offline): close anyway; the batch shows the change again next time.
      if (mounted) Navigator.of(context).pop(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final mine = row.myDecision!;
    final o = mine.override!;
    final nowRejected = o.decision == 'rejected';
    return Scaffold(
      backgroundColor: Brand.surfaceAlt,
      appBar: AppBar(
        backgroundColor: Brand.navy,
        foregroundColor: Colors.white,
        title: const Text('Decision changed', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(row.equipmentTypeName.isEmpty ? row.recordNo : row.equipmentTypeName,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text('Captured by ${row.capturedByName} · batch ${widget.batchNo}',
            style: const TextStyle(fontSize: 12.5, color: Brand.body)),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Brand.lineSoft),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _Line('You decided', _Tag(mine.approved ? 'Approved' : 'Rejected', approved: mine.approved)),
            const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1, color: Brand.lineSoft)),
            _Line('${o.decidedByName} changed it to', _Tag(nowRejected ? 'Rejected' : 'Approved', approved: !nowRejected)),
            if (o.rejectCategory != null) ...[
              const SizedBox(height: 12),
              const Text('Category', style: TextStyle(fontSize: 11.5, color: Brand.hint)),
              Text(rejectCategoryLabel(o.rejectCategory),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ],
            if (o.note != null && o.note!.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text("${o.decidedByName}'s note", style: const TextStyle(fontSize: 11.5, color: Brand.hint)),
              Text('"${o.note!.trim()}"', style: const TextStyle(fontSize: 14)),
            ],
          ]),
        ),
        const SizedBox(height: 12),
        InfoBanner(
          text: nowRejected
              ? 'Nothing for you to do — ${row.capturedByName} gets the scan back to fix. This is just so you know for next time.'
              : 'Nothing for you to do — the scan is approved now. This is just so you know for next time.',
        ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: PillButton(label: 'Got it', loading: _saving, onPressed: _gotIt),
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.tag);
  final String label;
  final Widget tag;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 13, color: Brand.body))),
        tag,
      ]);
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {required this.approved});
  final String text;
  final bool approved;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: approved ? const Color(0xFFE4F5E5) : Brand.errorBg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(text,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: approved ? const Color(0xFF2C7A30) : Brand.error)),
      );
}
