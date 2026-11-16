import 'package:flutter/material.dart';

import '../../core/api_exception.dart';
import '../../core/theme.dart';
import '../../widgets/auth_widgets.dart';
import '../scan/scan_models.dart' show shortPlace;
import '../scan/scan_repository.dart';
import '../scan/scan_thumb.dart' show ScanThumb;
import 'decision_changed_screen.dart';
import 'delegated_models.dart';
import 'delegated_review_screen.dart';

/// A batch of scans a BU Admin gave me to review (screen T 74; contract 3.11): what is left
/// to review, what I decided, and the scans that left the batch (greyed, at the bottom of
/// Done, so nothing disappears silently). A decision the admin changed opens T 77.
class BatchScreen extends StatefulWidget {
  const BatchScreen({super.key, required this.scans, required this.batchId, required this.batchNo});
  final ScanRepository scans;
  final String batchId;
  final String batchNo;

  @override
  State<BatchScreen> createState() => _BatchScreenState();
}

class _BatchScreenState extends State<BatchScreen> {
  ReviewBatch? _batch;
  List<Assignment> _rows = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final (batch, rows) = await widget.scans.reviewBatch(widget.batchId);
      if (!mounted) return;
      setState(() {
        _batch = batch;
        _rows = rows;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.status == 404 ? 'This batch is no longer assigned to you.' : e.message);
    }
  }

  /// Opens a scan to review; whatever happened there is said and the batch is read again.
  Future<void> _open(Assignment a, int position, int total) async {
    final said = await Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (_) => DelegatedReviewScreen(scans: widget.scans, scanId: a.scanId, position: '$position of $total'),
    ));
    if (!mounted) return;
    if (said != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(said)));
    await _load();
  }

  Future<void> _changed(Assignment a) async {
    await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => DecisionChangedScreen(scans: widget.scans, row: a, batchNo: widget.batchNo),
    ));
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final b = _batch;
    return Scaffold(
      backgroundColor: Brand.surfaceAlt,
      appBar: AppBar(
        backgroundColor: Brand.navy,
        foregroundColor: Colors.white,
        title: Text('Review batch ${widget.batchNo}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: b == null
          ? (_error == null
              ? const Center(child: CircularProgressIndicator())
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    InfoBanner(text: _error!, error: true),
                    const SizedBox(height: 12),
                    PillButton(label: 'Try again', outlined: true, onPressed: _load),
                  ]),
                ))
          : RefreshIndicator(onRefresh: _load, child: _list(b)),
    );
  }

  Widget _list(ReviewBatch b) {
    final toReview = _rows.where((a) => a.canOpen).toList();
    final decided = _rows.where((a) => a.status == 'decided').toList();
    final removed = _rows.where((a) => a.removed).toList();
    final firstUnseen = decided.where((a) => a.myDecision?.override?.seen == false).firstOrNull;
    return ListView(padding: EdgeInsets.zero, children: [
      _Header(batch: b),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (firstUnseen != null) ...[
            _ChangedBanner(text: b.changedText, onTap: () => _changed(firstUnseen)),
            const SizedBox(height: 12),
          ],
          if (toReview.isNotEmpty) ...[
            _Section('To review · ${toReview.length}'),
            for (final (i, a) in toReview.indexed)
              _Row(a, highlight: i == 0, onTap: () => _open(a, b.decidedCount + i + 1, b.total)),
          ],
          if (decided.isNotEmpty || removed.isNotEmpty) ...[
            _Section('Done · ${decided.length}'),
            for (final a in decided)
              _Row(a, onTap: a.myDecision?.override == null ? null : () => _changed(a)),
            for (final a in removed) _Row(a),
          ],
          const SizedBox(height: 12),
          Text(
            'Your own scans are never in your batch. You can approve or reject, but only the technician who '
            'captured a scan can revise it. ${b.createdByName} can change any decision you make.',
            style: const TextStyle(fontSize: 12, color: Brand.hint, height: 1.45),
          ),
        ]),
      ),
    ]);
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.batch});
  final ReviewBatch batch;

  @override
  Widget build(BuildContext context) => Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Text.rich(TextSpan(style: const TextStyle(fontSize: 13, color: Brand.body), children: [
                const TextSpan(text: 'From '),
                TextSpan(text: batch.createdByName, style: const TextStyle(fontWeight: FontWeight.w700, color: Brand.ink)),
                const TextSpan(text: ' · BU Admin'),
              ])),
            ),
            Text(batch.progress, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: batch.total == 0 ? 0 : batch.decidedCount / batch.total,
              minHeight: 6,
              backgroundColor: Brand.segment,
              color: Brand.navy,
            ),
          ),
        ]),
      );
}

class _ChangedBanner extends StatelessWidget {
  const _ChangedBanner({required this.text, required this.onTap});
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Brand.errorBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: Color(0xFFF2B8AE)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              const Icon(Icons.error_outline, color: Brand.error, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(TextSpan(style: const TextStyle(fontSize: 13.5, color: Brand.errorInk), children: [
                  TextSpan(text: text, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const TextSpan(text: ' See why.'),
                ])),
              ),
            ]),
          ),
        ),
      );
}

class _Section extends StatelessWidget {
  const _Section(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Text(text.toUpperCase(),
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: Brand.muted)),
      );
}

class _Row extends StatelessWidget {
  const _Row(this.a, {this.onTap, this.highlight = false});
  final Assignment a;
  final VoidCallback? onTap;
  final bool highlight;

  String get _subtitle {
    final by = 'Captured by ${a.capturedByName}';
    if (a.removed) return '$by · ${a.statusText}';
    final d = a.myDecision;
    if (a.status == 'decided' && d != null) {
      final you = 'you ${d.approved ? 'approved' : 'rejected'}';
      return d.override == null ? '$by · $you' : '$by · $you · changed by ${d.override!.decidedByName}';
    }
    final flags = a.flagCount == 0 ? '' : ' · ${a.flagCount} flagged';
    return '$by · ${shortPlace(a.locationPath)}$flags';
  }

  @override
  Widget build(BuildContext context) {
    // Coloured by where the scan ended, also when the admin changed my decision.
    final (fg, bg) = a.canOpen
        ? (Brand.navy, Brand.info)
        : switch (a.endedApproved) {
            true => (const Color(0xFF2C7A30), const Color(0xFFE4F5E5)),
            false => (Brand.error, Brand.errorBg),
            null => (Brand.muted, Brand.segment),
          };
    final tag = a.removed ? 'Removed' : a.statusText;
    final row = Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: a.removed ? Brand.surfaceAlt : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: highlight ? Brand.navy : Brand.lineSoft, width: highlight ? 1.5 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(children: [
            ScanThumb(url: a.thumbnailUrl, faded: a.removed),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a.equipmentTypeName.isEmpty ? a.recordNo : a.equipmentTypeName,
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: a.removed ? Brand.body : Brand.ink)),
                const SizedBox(height: 2),
                Text(_subtitle, style: const TextStyle(fontSize: 11.5, color: Brand.hint)),
              ]),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
              child: Text(tag, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
            ),
          ]),
        ),
      ),
    );
    return a.removed ? Opacity(opacity: 0.7, child: row) : row;
  }
}
