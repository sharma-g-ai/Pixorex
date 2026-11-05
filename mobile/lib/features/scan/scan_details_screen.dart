import 'package:flutter/material.dart';

import '../../core/api_exception.dart';
import '../../core/theme.dart';
import '../../widgets/auth_widgets.dart';
import 'review_screen.dart' show PhotoZoom;
import 'scan_models.dart';
import 'scan_repository.dart';
import 'scan_status.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "4 Nov 15:15", in the phone's time. Today and yesterday read the same as other days: the
/// history is a record, so it always shows the exact time.
String eventTime(DateTime t) {
  final l = t.toLocal();
  return '${l.day} ${_months[l.month - 1]} ${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

/// Where a scan is and what happened to it (contract 3.16). Opened by tapping a row that has
/// nothing for the technician to fill in: submitted, approved, closed, or out of reads.
class ScanDetailsScreen extends StatefulWidget {
  const ScanDetailsScreen({super.key, required this.scans, required this.scan});
  final ScanRepository scans;
  final MyScan scan;

  @override
  State<ScanDetailsScreen> createState() => _ScanDetailsScreenState();
}

class _ScanDetailsScreenState extends State<ScanDetailsScreen> {
  Scan? _scan;
  ScanHistory? _history;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await Future.wait([widget.scans.scan(widget.scan.scanId), widget.scans.history(widget.scan.scanId)]);
      if (mounted) {
        setState(() {
          _scan = r[0] as Scan;
          _history = r[1] as ScanHistory;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scan;
    final look = ScanStatusLook.of(s.processingStatus, s.reviewStatus);
    final h = _history;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Brand.navy,
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s.equipmentTypeName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          Text('${formatScanId(s.recordNo)} · ${s.place}', style: const TextStyle(fontSize: 11, color: Colors.white70)),
        ]),
      ),
      body: _error != null
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                InfoBanner(text: _error!, error: true),
                const SizedBox(height: 12),
                PillButton(label: 'Try again', outlined: true, onPressed: _load),
              ]),
            )
          : h == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.all(16), children: [
                  Row(children: [
                    ScanStatusPill(s.resubmitted ? const ScanStatusLook('Resubmitted', Color(0xFFEEF1F4), Brand.navy) : look),
                    const SizedBox(width: 10),
                    if (!h.needsTechnician)
                      const Flexible(child: Text('Nothing for you to do', style: TextStyle(fontSize: 11.5, color: Brand.hint))),
                  ]),
                  const SizedBox(height: 12),
                  NowLine(history: h),
                  if (_scan != null && _scan!.photoUrls.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    GestureDetector(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => PhotoZoom(urls: _scan!.photoUrls, first: 0)),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          height: 120,
                          width: double.infinity,
                          child: Image.network(_scan!.photoUrls.first,
                              fit: BoxFit.cover, errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFF2E3640))),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  const Text('History', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  HistoryTimeline(events: h.events),
                ]),
    );
  }
}

/// "Now: with Bo Plant04 for review · since 4 Nov 16:01". Amber when the technician has to act.
class NowLine extends StatelessWidget {
  const NowLine({super.key, required this.history});
  final ScanHistory history;

  @override
  Widget build(BuildContext context) {
    final act = history.needsTechnician;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: act ? Brand.warnBg : Brand.info, borderRadius: BorderRadius.circular(8)),
      child: Text.rich(TextSpan(
        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: act ? const Color(0xFF8B3E0C) : Brand.navyDeep, height: 1.4),
        children: [
          TextSpan(text: 'Now: ${history.nowText}'),
          if (history.since != null)
            TextSpan(text: ' · since ${eventTime(history.since!)}', style: const TextStyle(fontWeight: FontWeight.w400)),
        ],
      )),
    );
  }
}

/// The events as a vertical line, oldest first, each with its exact time.
class HistoryTimeline extends StatelessWidget {
  const HistoryTimeline({super.key, required this.events});
  final List<HistoryEvent> events;

  static Color _dot(String kind) => switch (kind) {
        'rejected' || 'read_failed' => Brand.error,
        'approved' => const Color(0xFF3C9F40),
        'resubmitted' || 'decision_changed' => Brand.warn,
        _ => Brand.navy,
      };

  @override
  Widget build(BuildContext context) => Column(children: [
        for (var i = 0; i < events.length; i++)
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(
                width: 16,
                child: Column(children: [
                  Container(
                    margin: const EdgeInsets.only(top: 3),
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: _dot(events[i].kind), width: 3),
                    ),
                  ),
                  if (i < events.length - 1) Expanded(child: Container(width: 2, color: Brand.lineSoft)),
                ]),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(events[i].title, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                    if (events[i].detail != null)
                      Text(events[i].detail!, style: const TextStyle(fontSize: 11.5, color: Brand.muted, height: 1.35)),
                    Text(eventTime(events[i].at), style: const TextStyle(fontSize: 10.5, color: Brand.hint)),
                  ]),
                ),
              ),
            ]),
          ),
      ]);
}

/// A whole-screen History for the screens that already have their own purpose (Review, the
/// rejection notice): the same Now line and timeline, opened from a menu.
class ScanHistoryScreen extends StatefulWidget {
  const ScanHistoryScreen({super.key, required this.scans, required this.scanId, required this.title});
  final ScanRepository scans;
  final String scanId;
  final String title;

  @override
  State<ScanHistoryScreen> createState() => _ScanHistoryScreenState();
}

class _ScanHistoryScreenState extends State<ScanHistoryScreen> {
  ScanHistory? _history;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final h = await widget.scans.history(widget.scanId);
      if (mounted) setState(() => _history = h);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = _history;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Brand.navy,
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('History', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          Text(widget.title, style: const TextStyle(fontSize: 11, color: Colors.white70)),
        ]),
      ),
      body: _error != null
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                InfoBanner(text: _error!, error: true),
                const SizedBox(height: 12),
                PillButton(label: 'Try again', outlined: true, onPressed: _load),
              ]),
            )
          : h == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.all(16), children: [
                  NowLine(history: h),
                  const SizedBox(height: 16),
                  HistoryTimeline(events: h.events),
                ]),
    );
  }
}
