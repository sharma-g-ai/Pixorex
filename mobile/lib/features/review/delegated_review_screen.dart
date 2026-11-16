import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/api_exception.dart';
import '../../core/theme.dart';
import '../../widgets/auth_widgets.dart';
import '../scan/review_model.dart' show flagReasonText;
import '../scan/review_screen.dart' show PhotoZoom;
import '../scan/scan_repository.dart';
import '../scan/scan_thumb.dart' show NetworkPhoto;
import 'delegated_models.dart';

const _green = Color(0xFF2C7A30);
const _approve = Color(0xFF3A9E3E);

/// Approve or reject a scan someone else captured (screens T 75-76; contracts 3.4, 3.5).
/// Read only: the reviewer cannot change values. Pops with a sentence for the batch screen
/// to show (decided, or why the scan is no longer theirs), which then reloads.
class DelegatedReviewScreen extends StatefulWidget {
  const DelegatedReviewScreen({super.key, required this.scans, required this.scanId, this.position});
  final ScanRepository scans;
  final String scanId;

  /// Where this scan sits in the batch, e.g. "19 of 30" (design T 75 header).
  final String? position;

  @override
  State<DelegatedReviewScreen> createState() => _DelegatedReviewScreenState();
}

class _DelegatedReviewScreenState extends State<DelegatedReviewScreen> {
  static const _uuid = Uuid();
  DelegatedScan? _scan;
  String? _loadError;
  String? _error;
  bool _sending = false;

  /// One Idempotency-Key per decision body, so pressing again after a lost answer repeats
  /// it, while choosing differently is a new request.
  final _keys = <String, String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final scan = await widget.scans.scanReview(widget.scanId);
      if (mounted) setState(() => _scan = scan);
    } on ApiException catch (e) {
      if (!mounted) return;
      final gone = decisionProblemText(e.code, e.status) ?? (e.code == 'invalid-state' ? takenBackText : null);
      if (gone != null) {
        Navigator.of(context).pop(gone);
      } else {
        setState(() => _loadError = e.message);
      }
    }
  }

  Future<void> _decide({required bool approve, String? category, String? note}) async {
    final s = _scan!;
    final body = jsonEncode([approve, category, note]);
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.scans.decide(
        s.scanId,
        approve: approve,
        rejectCategory: category,
        note: note,
        idempotencyKey: _keys.putIfAbsent(body, _uuid.v4),
      );
      if (mounted) Navigator.of(context).pop('${approve ? 'Approved' : 'Rejected'} · ${s.equipmentTypeName}');
    } on ApiException catch (e) {
      if (!mounted) return;
      final gone = decisionProblemText(e.code, e.status);
      // A revision sent with required fields empty can't be approved (the API says so with
      // invalid-state): stay, so it can be rejected. Any other invalid-state: no longer mine.
      final refusedApproval = e.code == 'invalid-state' && approve && s.emptyRequiredFields.isNotEmpty;
      if (gone != null || (e.code == 'invalid-state' && !refusedApproval)) {
        Navigator.of(context).pop(gone ?? takenBackText);
      } else {
        setState(() => _error = e.message);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _reject() async {
    final picked = await showModalBottomSheet<(String, String?)>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RejectSheet(capturedBy: _scan!.capturedByName),
    );
    if (picked != null) await _decide(approve: false, category: picked.$1, note: picked.$2);
  }

  @override
  Widget build(BuildContext context) {
    final s = _scan;
    return Scaffold(
      backgroundColor: Brand.surfaceAlt,
      appBar: AppBar(
        backgroundColor: Brand.navy,
        foregroundColor: Colors.white,
        title: Text(s?.equipmentTypeName ?? 'Review', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        actions: [
          if (widget.position != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(child: Text(widget.position!, style: const TextStyle(fontSize: 13, color: Colors.white70))),
            ),
        ],
      ),
      body: s == null
          ? (_loadError == null
              ? const Center(child: CircularProgressIndicator())
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    InfoBanner(text: _loadError!, error: true),
                    const SizedBox(height: 12),
                    PillButton(label: 'Try again', outlined: true, onPressed: () {
                      setState(() => _loadError = null);
                      _load();
                    }),
                  ]),
                ))
          : ListView(padding: const EdgeInsets.all(16), children: [
              if (s.photoUrls.isNotEmpty) ...[_Photos(urls: s.photoUrls), const SizedBox(height: 10)],
              Text.rich(TextSpan(style: const TextStyle(fontSize: 13, color: Brand.body), children: [
                const TextSpan(text: 'Captured by '),
                TextSpan(text: s.capturedByName, style: const TextStyle(fontWeight: FontWeight.w700, color: Brand.ink)),
                TextSpan(text: ' · ${s.locationPath}'),
              ])),
              const SizedBox(height: 10),
              _ReadOnly(capturedBy: s.capturedByName),
              if (s.emptyRequiredFields.isNotEmpty) ...[
                const SizedBox(height: 10),
                InfoBanner(text: 'Sent with required fields empty: ${s.emptyRequiredFields.join(', ')}.', error: true),
              ],
              for (final f in s.fields)
                Padding(padding: const EdgeInsets.only(top: 10), child: _FieldCard(f, capturedBy: s.capturedByName)),
            ]),
      bottomNavigationBar: s == null
          ? null
          : Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: SafeArea(
                top: false,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (_error != null)
                    Padding(padding: const EdgeInsets.only(bottom: 10), child: InfoBanner(text: _error!, error: true)),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _sending ? null : _reject,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Brand.error,
                          side: const BorderSide(color: Brand.error, width: 1.5),
                          minimumSize: const Size.fromHeight(48),
                          shape: const StadiumBorder(),
                        ),
                        child: const Text('Reject', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: _sending ? null : () => _decide(approve: true),
                        style: FilledButton.styleFrom(
                          backgroundColor: _approve,
                          minimumSize: const Size.fromHeight(48),
                          shape: const StadiumBorder(),
                        ),
                        child: _sending
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Approve', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ]),
                ]),
              ),
            ),
    );
  }
}

class _ReadOnly extends StatelessWidget {
  const _ReadOnly({required this.capturedBy});
  final String capturedBy;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: Brand.segment, borderRadius: BorderRadius.circular(10)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.lock_outline, size: 16, color: Brand.body),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(TextSpan(style: const TextStyle(fontSize: 12.5, color: Brand.body), children: [
              const TextSpan(text: 'Read-only. You approve or reject — only '),
              TextSpan(text: capturedBy, style: const TextStyle(fontWeight: FontWeight.w700, color: Brand.ink)),
              const TextSpan(text: ', who captured it, can correct or retake it.'),
            ])),
          ),
        ]),
      );
}

/// One field as submitted (design T 75): the verdict, what the AI read (struck through when
/// corrected), the technician's value only when corrected, and why it was flagged.
class _FieldCard extends StatelessWidget {
  const _FieldCard(this.f, {required this.capturedBy});
  final ReviewedField f;
  final String capturedBy;

  static const _mono = TextStyle(fontFamily: 'IBM Plex Mono', fontSize: 14, fontWeight: FontWeight.w600);

  String get _flagLine {
    if (f.verificationState == 'unreadable') {
      final why = f.unreadableText == null ? '' : ' (${f.unreadableText})';
      return 'Flagged: missing · marked unreadable by $capturedBy$why';
    }
    if (f.flagReasons.isEmpty) return 'Looks right';
    final text = f.flagReasons.map((r) => flagReasonText(r, f.confidence)).join(' · ');
    return 'Flagged: ${text[0].toLowerCase()}${text.substring(1)}';
  }

  @override
  Widget build(BuildContext context) {
    final color = switch (f.verificationState) {
      'corrected' => Brand.navy,
      'unreadable' || 'left_empty' => Brand.body,
      _ => _green,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Brand.lineSoft),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(f.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Brand.body))),
          Text(f.verdict, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
        ]),
        const SizedBox(height: 8),
        _line('AI read', f.aiValue, struck: f.corrected),
        if (f.corrected) _line('Technician', f.technicianValue, you: true),
        if (f.note != null && f.note!.isNotEmpty) _line('Note', f.note),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(_flagLine, style: const TextStyle(fontSize: 11.5, color: Brand.hint)),
        ),
      ]),
    );
  }

  Widget _line(String label, String? value, {bool struck = false, bool you = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 82,
            child: Text(label,
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: you ? Brand.navy : Brand.hint)),
          ),
          Expanded(
            child: Text(value ?? '—',
                style: _mono.copyWith(
                  fontSize: you ? 15 : 14,
                  color: struck ? Brand.hint : Brand.ink,
                  decoration: struck ? TextDecoration.lineThrough : null,
                )),
          ),
        ]),
      );
}

class _Photos extends StatelessWidget {
  const _Photos({required this.urls});
  final List<String> urls;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 150,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: urls.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, i) => GestureDetector(
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PhotoZoom(urls: urls, first: i))),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: urls.length == 1 ? 330 : (i == 0 ? 280 : 70),
                child: Stack(fit: StackFit.expand, children: [
                  NetworkPhoto(url: urls[i]),
                  if (i == 0)
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(999)),
                        child: const Text('Tap to zoom',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
                      ),
                    ),
                ]),
              ),
            ),
          ),
        ),
      );
}

/// Design T 76: a reason is required; with "Other" a note is too (O-21). Pops (category,
/// note or null).
class _RejectSheet extends StatefulWidget {
  const _RejectSheet({required this.capturedBy});
  final String capturedBy;

  @override
  State<_RejectSheet> createState() => _RejectSheetState();
}

class _RejectSheetState extends State<_RejectSheet> {
  String? _category;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final noteNeeded = _category == 'other';
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Why are you rejecting it?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            RadioGroup<String>(
              groupValue: _category,
              onChanged: (c) => setState(() => _category = c),
              child: Column(children: [
                for (final (code, label) in rejectCategories)
                  RadioListTile<String>(value: code, title: Text(label), dense: true, contentPadding: EdgeInsets.zero),
              ]),
            ),
            TextField(
              controller: _note,
              maxLines: 3,
              maxLength: 2000,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: noteNeeded
                    ? 'Add a note for ${widget.capturedBy} (required for Other)'
                    : 'Add a note for ${widget.capturedBy} (optional)',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: rejectReady(_category, _note.text)
                  ? () => Navigator.of(context).pop((_category!, _note.text.trim().isEmpty ? null : _note.text.trim()))
                  : null,
              style: FilledButton.styleFrom(backgroundColor: Brand.error, minimumSize: const Size.fromHeight(48), shape: const StadiumBorder()),
              child: const Text('Reject scan', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          ]),
        ),
      ),
    );
  }
}
