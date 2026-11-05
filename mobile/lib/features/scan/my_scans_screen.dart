import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api_exception.dart';
import '../../core/theme.dart';
import '../../widgets/auth_widgets.dart';
import 'rejection_screens.dart';
import 'review_screen.dart';
import 'scan_details_screen.dart';
import 'scan_models.dart';
import 'scan_repository.dart';
import 'scan_status.dart';

/// My Scans (design 47-49, 62-67): search, tabs, and what to do with each scan.
class MyScansScreen extends StatefulWidget {
  const MyScansScreen({
    super.key,
    required this.scans,
    required this.unitName,
    this.onRetake,
    this.initialTab,
    this.clock = DateTime.now,
    this.searchDelay = const Duration(milliseconds: 350),
    this.pollEvery = const Duration(seconds: 4),
  });
  final ScanRepository scans;
  final String unitName;

  /// Starts a new scan that replaces [old] (design 65); completes with true when it was sent.
  final Future<bool> Function(MyScan old)? onRetake;

  /// `needs_action`, `in_progress` or `approved`; null opens All.
  final String? initialTab;
  final DateTime Function() clock;
  final Duration searchDelay;

  /// While a scan is uploading or being read the list asks again by itself (there is no
  /// push), so "Extracting" turns into "Ready to Review" or "Extraction failed" on screen.
  final Duration pollEvery;

  @override
  State<MyScansScreen> createState() => _MyScansScreenState();
}

class _MyScansScreenState extends State<MyScansScreen> {
  static const _tabs = [('All', null), ('Needs action', 'needs_action'), ('In progress', 'in_progress'), ('Approved', 'approved')];

  late int _tab = _tabs.indexWhere((t) => t.$2 == widget.initialTab).clamp(0, _tabs.length - 1);
  String _q = '';
  Timer? _debounce;
  Timer? _poll;
  final _items = <MyScan>[];
  String? _next;
  bool _loading = true;
  bool _more = false;
  String? _error;
  final _busy = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    setState(() {
      if (more) {
        _more = true;
      } else {
        _loading = true;
      }
      _error = null;
    });
    try {
      final page = await widget.scans.myScans(tab: _tabs[_tab].$2, q: _q.trim(), cursor: more ? _next : null);
      if (!mounted) return;
      setState(() {
        if (!more) _items.clear();
        _items.addAll(page.items);
        _next = page.nextCursor;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _more = false;
        });
        _schedulePoll();
      }
    }
  }

  bool get _working => _items.any((s) => s.reviewStatus == 'draft' && const {'uploading', 'extracting'}.contains(s.processingStatus));

  /// Quietly re-reads the first page: no spinner, and the list stays as it is on a failure.
  Future<void> _refreshQuietly() async {
    if (_loading || _more) return;
    try {
      final page = await widget.scans.myScans(tab: _tabs[_tab].$2, q: _q.trim());
      if (!mounted || _loading) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _next = page.nextCursor;
      });
    } on ApiException {
      // Keep what is on screen; the next tick tries again.
    }
  }

  void _schedulePoll() {
    _poll?.cancel();
    if (!_working) return;
    _poll = Timer(widget.pollEvery, () async {
      await _refreshQuietly();
      if (mounted) _schedulePoll();
    });
  }

  void _search(String q) {
    _q = q;
    _debounce?.cancel();
    _debounce = Timer(widget.searchDelay, _load);
  }

  void _say(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _open(MyScan s) async {
    if (s.reviewStatus == 'rejected') return _openRejected(s);
    if (s.opensDetails) {
      await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => ScanDetailsScreen(scans: widget.scans, scan: s)));
      return;
    }
    final sent = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => ReviewScreen(scans: widget.scans, scanId: s.scanId),
    ));
    if (!mounted) return;
    if (sent == true) _say('${s.equipmentTypeName} sent to reviewer');
    if (sent == false) _say('${s.equipmentTypeName} discarded');
    await _load();
  }

  /// Design 68-73: fix the fields and send them back, or retake it as a new scan.
  Future<void> _openRejected(MyScan s) async {
    final done = await Navigator.of(context).push<RejectionOutcome>(MaterialPageRoute(
      builder: (_) => RejectionNoticeScreen(
        scans: widget.scans,
        scanId: s.scanId,
        onRetake: widget.onRetake == null ? null : () => widget.onRetake!(s),
        clock: widget.clock,
      ),
    ));
    if (!mounted) return;
    switch (done) {
      case RejectionOutcome.resubmitted:
        _say('${s.equipmentTypeName} resubmitted to ${s.reviewerName ?? 'the reviewer'}');
      case RejectionOutcome.retaken:
        _say('New scan submitted · rejected scan closed');
      case null:
        break;
    }
    await _load();
  }

  /// Design 63: the worker reads the same photos again.
  Future<void> _retry(MyScan s) async {
    setState(() => _busy.add(s.scanId));
    try {
      await widget.scans.retry(s.scanId);
      _say('Retrying extraction — attempt ${s.attemptsUsed + 1} of ${Scan.maxAttempts}');
      await _load();
    } on ApiException catch (e) {
      _say(e.message);
    } finally {
      if (mounted) setState(() => _busy.remove(s.scanId));
    }
  }

  Future<void> _retake(MyScan s) async {
    final sent = await widget.onRetake!(s);
    if (!mounted) return;
    if (sent) _say('New scan created · old one closed');
    await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Brand.surface,
        appBar: AppBar(
          backgroundColor: Brand.navy,
          foregroundColor: Colors.white,
          title: const Text('My Scans', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(child: Text(widget.unitName, style: const TextStyle(fontSize: 11.5, color: Colors.white70))),
            ),
          ],
        ),
        body: Column(children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Column(children: [
              TextField(
                onChanged: _search,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search name, serial or bin',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  filled: true,
                  fillColor: Brand.surface,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final (i, (label, _)) in _tabs.indexed)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(label),
                        selected: _tab == i,
                        showCheckmark: false,
                        selectedColor: Brand.navy,
                        backgroundColor: Brand.surface,
                        side: BorderSide.none,
                        shape: const StadiumBorder(),
                        labelStyle: TextStyle(
                          fontSize: 12,
                          fontWeight: _tab == i ? FontWeight.w700 : FontWeight.w600,
                          color: _tab == i ? Colors.white : Brand.ink,
                        ),
                        onSelected: (_) {
                          setState(() => _tab = i);
                          _load();
                        },
                      ),
                    ),
                ]),
              ),
            ]),
          ),
          Expanded(child: _list()),
        ]),
      );

  Widget _list() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          InfoBanner(text: _error!, error: true),
          const SizedBox(height: 12),
          PillButton(label: 'Try again', outlined: true, onPressed: _load),
        ]),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Text(_q.isNotEmpty ? 'No scans match "$_q".' : 'No scans here yet.', style: const TextStyle(color: Brand.muted)),
      );
    }
    final now = widget.clock();
    // "All": what needs the technician first, as on design 47.
    final grouped = _tabs[_tab].$2 == null;
    // Design 73: a retake and the scan it closed sit together at the top for a while.
    final justNow = grouped ? _items.where((s) => isRetakePair(s) && now.difference(s.updatedAt.toLocal()).inMinutes < 15).toList() : const <MyScan>[];
    final needs = grouped ? _items.where((s) => needsAction(s) && !justNow.contains(s)).toList() : const <MyScan>[];
    final rest = grouped ? _items.where((s) => !needsAction(s) && !justNow.contains(s)).toList() : _items;
    return RefreshIndicator(
      onRefresh: _load,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (_next != null && !_more && n.metrics.extentAfter < 300) _load(more: true);
          return false;
        },
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
          if (justNow.isNotEmpty) ...[const _Section('Just now'), for (final s in justNow) _tile(s, now)],
          if (needs.isNotEmpty) ...[const _Section('Needs your action'), for (final s in needs) _tile(s, now)],
          if (grouped && (needs.isNotEmpty || justNow.isNotEmpty) && rest.isNotEmpty) const _Section('In progress & done'),
          if (!grouped) const SizedBox(height: 8),
          for (final s in rest) _tile(s, now),
          if (_more) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
        ]),
      ),
    );
  }

  Widget _tile(MyScan s, DateTime now) => MyScanTile(
        scan: s,
        now: now,
        busy: _busy.contains(s.scanId),
        onTap: () => _open(s),
        onRetry: () => _retry(s),
        onRetake: widget.onRetake == null ? null : () => _retake(s),
      );
}

/// A scan closed by a retake, or a retake still being read (design 73).
bool isRetakePair(MyScan s) =>
    s.reviewStatus == 'closed' ||
    (s.retakeOfScanId != null && s.reviewStatus == 'draft' && const {'uploading', 'extracting'}.contains(s.processingStatus));

/// Same split as the API's `needs_action` tab.
bool needsAction(MyScan s) =>
    s.reviewStatus == 'rejected' ||
    (s.reviewStatus == 'draft' && const {'ready_to_review', 'failed', 'retake_required'}.contains(s.processingStatus));

class _Section extends StatelessWidget {
  const _Section(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 8),
        child: Text(text.toUpperCase(),
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: Brand.muted)),
      );
}

/// One scan with the next step on it (design 47, 63, 64).
class MyScanTile extends StatelessWidget {
  const MyScanTile({
    super.key,
    required this.scan,
    required this.now,
    required this.onTap,
    required this.onRetry,
    this.onRetake,
    this.busy = false,
  });
  final MyScan scan;
  final DateTime now;
  final VoidCallback onTap;
  final VoidCallback onRetry;
  final VoidCallback? onRetake;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final s = scan;
    final look = s.resubmitted
        ? const ScanStatusLook('Resubmitted', Color(0xFFEEF1F4), Brand.navy)
        : ScanStatusLook.of(s.processingStatus, s.reviewStatus);
    final closed = s.reviewStatus == 'closed';
    final retaking = s.retakeOfScanId != null && isRetakePair(s) && !closed;
    final draft = s.reviewStatus == 'draft';
    final failed = draft && s.processingStatus == 'failed';
    // Design 47, 63, 64: a failed scan can be retried while tries are left, or retaken at any time.
    final retake = (draft && (failed || s.processingStatus == 'retake_required')) || s.reviewStatus == 'rejected';
    final left = Scan.maxAttempts - s.attemptsUsed;
    // The second line only says what the technician has to do. Where a scan is, and when
    // things happened, is on Scan details (tap the row), not on every row.
    final (action, red) = switch ((s.processingStatus, s.reviewStatus)) {
      (_, 'rejected') => ('Sent back · tap to fix', true),
      (_, 'closed') => ('Retaken as a new scan', false),
      ('failed', 'draft') => ("Couldn't read this image · try ${s.attemptsUsed} of ${Scan.maxAttempts}", true),
      ('retake_required', 'draft') => ('Failed ${Scan.maxAttempts} times — retake the photo', true),
      ('ready_to_review', 'draft') => ('Check what was read', false),
      _ => (null, false),
    };
    final edge = s.reviewStatus == 'rejected' || failed || retake
        ? Brand.error
        : look.needsAction
            ? Brand.warn
            : s.resubmitted || retaking
                ? const Color(0xFF7FA3EA)
                : null;
    final tile = Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: closed ? Brand.surfaceAlt : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: closed ? null : Border.all(color: edge ?? Brand.lineSoft, width: edge == null ? 1 : 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(children: [
            Row(children: [
              Opacity(
                opacity: closed ? 0.6 : 1,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: closed ? const Color(0xFF4A2A2A) : const Color(0xFF1F1F23),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.qr_code_scanner, size: 18, color: Colors.white54),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(closed ? '${s.equipmentTypeName} · original' : s.equipmentTypeName,
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: closed ? Brand.body : null)),
                  Text('${formatScanId(s.recordNo)} · ${s.place}',
                      style: const TextStyle(fontSize: 11, color: Brand.hint, fontFeatures: [FontFeature.tabularFigures()])),
                  if (action != null)
                    Text(action, style: TextStyle(fontSize: 11, color: red ? Brand.error : (closed ? Brand.hint : Brand.warn))),
                ]),
              ),
              ScanStatusPill(look),
            ]),
            if ((failed && left > 0) || (retake && onRetake != null && s.reviewStatus != 'rejected')) ...[
              const SizedBox(height: 10),
              Row(children: [
                if (failed && left > 0)
                  Expanded(child: _Action('Retry ($left left)', busy ? null : onRetry))
                else
                  const Expanded(
                    child: Center(child: Text('No retries left', style: TextStyle(fontSize: 12, color: Brand.hint))),
                  ),
                if (retake && onRetake != null) ...[
                  const SizedBox(width: 8),
                  Expanded(child: _Action('Retake photo', onRetake, filled: true)),
                ],
              ]),
            ],
          ]),
        ),
      ),
    );
    // Design 73: the closed original keeps its place, drawn with a dashed outline.
    return closed ? CustomPaint(foregroundPainter: const _Dashed(), child: tile) : tile;
  }
}

class _Dashed extends CustomPainter {
  const _Dashed();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFC5CAD1)
      ..style = PaintingStyle.stroke;
    // The tile's bottom margin is outside the outline.
    final box = RRect.fromRectAndRadius(Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 9), const Radius.circular(10));
    for (final m in (Path()..addRRect(box)).computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 7) {
        canvas.drawPath(m.extractPath(d, d + 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Action extends StatelessWidget {
  const _Action(this.label, this.onTap, {this.filled = false});
  final String label;
  final VoidCallback? onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) => Material(
        color: filled ? Brand.navy : Colors.white,
        shape: StadiumBorder(side: filled ? BorderSide.none : const BorderSide(color: Brand.navy, width: 1.5)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Center(
              child: Text(label,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: filled ? Colors.white : Brand.navy)),
            ),
          ),
        ),
      );
}
