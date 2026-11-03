import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api_exception.dart';
import '../../core/theme.dart';
import '../../widgets/auth_widgets.dart';
import '../home/home_screen.dart' show ago;
import 'review_screen.dart';
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
  });
  final ScanRepository scans;
  final String unitName;

  /// Starts a new scan that replaces [old] (design 65); completes with true when it was sent.
  final Future<bool> Function(MyScan old)? onRetake;

  /// `needs_action`, `in_progress` or `approved`; null opens All.
  final String? initialTab;
  final DateTime Function() clock;
  final Duration searchDelay;

  @override
  State<MyScansScreen> createState() => _MyScansScreenState();
}

class _MyScansScreenState extends State<MyScansScreen> {
  static const _tabs = [('All', null), ('Needs action', 'needs_action'), ('In progress', 'in_progress'), ('Approved', 'approved')];

  late int _tab = _tabs.indexWhere((t) => t.$2 == widget.initialTab).clamp(0, _tabs.length - 1);
  String _q = '';
  Timer? _debounce;
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
      }
    }
  }

  void _search(String q) {
    _q = q;
    _debounce?.cancel();
    _debounce = Timer(widget.searchDelay, _load);
  }

  void _say(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _open(MyScan s) async {
    final sent = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => ReviewScreen(scans: widget.scans, scanId: s.scanId),
    ));
    if (!mounted) return;
    if (sent == true) _say('${s.equipmentTypeName} sent to reviewer');
    if (sent == false) _say('${s.equipmentTypeName} discarded');
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
    final needs = grouped ? _items.where(needsAction).toList() : const <MyScan>[];
    final rest = grouped ? _items.where((s) => !needsAction(s)).toList() : _items;
    return RefreshIndicator(
      onRefresh: _load,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (_next != null && !_more && n.metrics.extentAfter < 300) _load(more: true);
          return false;
        },
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
          if (needs.isNotEmpty) ...[const _Section('Needs your action'), for (final s in needs) _tile(s, now)],
          if (grouped && needs.isNotEmpty && rest.isNotEmpty) const _Section('In progress & done'),
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
    final look = ScanStatusLook.of(s.processingStatus, s.reviewStatus);
    final draft = s.reviewStatus == 'draft';
    final failed = draft && s.processingStatus == 'failed';
    // Design 47, 63, 64: a failed scan can be retried while tries are left, or retaken at any time.
    final retake = (draft && (failed || s.processingStatus == 'retake_required')) || s.reviewStatus == 'rejected';
    final left = Scan.maxAttempts - s.attemptsUsed;
    final (subtitle, red) = switch ((s.processingStatus, s.reviewStatus)) {
      (_, 'rejected') => ('${s.place} · reviewer sent it back', false),
      ('failed', 'draft') => ("Couldn't read this image · try ${s.attemptsUsed} of ${Scan.maxAttempts}", true),
      ('retake_required', 'draft') => ('Failed ${Scan.maxAttempts} times — retake the photo', true),
      ('ready_to_review', 'draft') => ('${s.place} · ready to check', false),
      ('extracting', 'draft') when s.attemptsUsed > 1 =>
        ('Attempt ${s.attemptsUsed} of ${Scan.maxAttempts} · ${ago(s.updatedAt, now)}', false),
      _ => ('${s.place} · ${ago(s.updatedAt, now)}', false),
    };
    final edge = s.reviewStatus == 'rejected' || failed || retake ? Brand.error : (look.needsAction ? Brand.warn : null);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: edge ?? Brand.lineSoft, width: edge == null ? 1 : 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(children: [
            Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: const Color(0xFF1F1F23), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.qr_code_scanner, size: 18, color: Colors.white54),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.equipmentTypeName, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                  Text(subtitle, style: TextStyle(fontSize: 11, color: red ? Brand.error : Brand.hint)),
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
  }
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
