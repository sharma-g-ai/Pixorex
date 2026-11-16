import 'package:flutter/material.dart';

import '../../core/api_exception.dart';
import '../../core/theme.dart';
import '../../widgets/auth_widgets.dart';
import '../scan/scan_models.dart' show formatScanId;
import '../scan/scan_repository.dart';
import 'delegated_models.dart';
import 'delegated_review_screen.dart';

/// A batch of scans a BU Admin gave me to review (screen T 74; contract 3.11). Only scans
/// still assigned to me open; decided ones show as done, removed ones say why.
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

  /// Opens the scan; whatever happened there (decided, or no longer mine) is said and the
  /// batch is read again.
  Future<void> _open(Assignment a) async {
    final said = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => DelegatedReviewScreen(scans: widget.scans, scanId: a.scanId)),
    );
    if (!mounted) return;
    if (said != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(said)));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final b = _batch;
    return Scaffold(
      backgroundColor: Brand.surfaceAlt,
      appBar: AppBar(
        backgroundColor: Brand.navy,
        foregroundColor: Colors.white,
        title: Text(widget.batchNo, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
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
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                Text('From ${b.createdByName} · ${b.progress}',
                    style: const TextStyle(fontSize: 13, color: Brand.body)),
                const SizedBox(height: 12),
                for (final a in _rows) _Row(a, onTap: a.canOpen ? () => _open(a) : null),
              ]),
            ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.a, {this.onTap});
  final Assignment a;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final open = a.canOpen;
    final (fg, bg) = switch (a.status) {
      'assigned' => (Brand.warn, Brand.warnBg),
      'decided' => (const Color(0xFF2C7A30), const Color(0xFFE4F5E5)),
      _ => (Brand.muted, Brand.segment),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: open ? Colors.white : Brand.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: open ? Brand.warn : Brand.lineSoft, width: open ? 1.5 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(children: [
            Expanded(
              child: Text(formatScanId(a.recordNo),
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: open ? Brand.ink : Brand.body,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
              child: Text(a.statusText, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
            ),
            if (open) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.chevron_right, color: Brand.hint)),
          ]),
        ),
      ),
    );
  }
}
