import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/api_exception.dart';
import '../../core/theme.dart';
import '../../widgets/auth_widgets.dart';
import '../scan/review_model.dart' show flagReasonText;
import '../scan/review_screen.dart' show PhotoZoom;
import '../scan/scan_models.dart' show formatScanId, shortPlace;
import '../scan/scan_repository.dart';
import '../scan/scan_thumb.dart' show NetworkPhoto;
import 'delegated_models.dart';

/// Approve or reject a scan someone else captured (screens T 75-76; contracts 3.4, 3.5).
/// Read only: the reviewer cannot change values. Pops with a sentence for the batch screen
/// to show (decided, or why the scan is no longer theirs), which then reloads.
class DelegatedReviewScreen extends StatefulWidget {
  const DelegatedReviewScreen({super.key, required this.scans, required this.scanId});
  final ScanRepository scans;
  final String scanId;

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
      if (mounted) Navigator.of(context).pop('${approve ? 'Approved' : 'Rejected'} · ${formatScanId(s.recordNo)}');
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
      builder: (_) => const _RejectSheet(),
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
        titleSpacing: 0,
        title: s == null
            ? const Text('Review')
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.equipmentTypeName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                Text('${formatScanId(s.recordNo)} · ${shortPlace(s.locationPath)}',
                    style: const TextStyle(fontSize: 11, color: Colors.white70)),
              ]),
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
              Text('Captured by ${s.capturedByName}', style: const TextStyle(fontSize: 13, color: Brand.body)),
              if (s.emptyRequiredFields.isNotEmpty) ...[
                const SizedBox(height: 10),
                InfoBanner(text: 'Sent with required fields empty: ${s.emptyRequiredFields.join(', ')}.', error: true),
              ],
              if (s.photoUrls.isNotEmpty) ...[const SizedBox(height: 12), _Photos(urls: s.photoUrls)],
              for (final f in s.fields) Padding(padding: const EdgeInsets.only(top: 10), child: _FieldCard(f)),
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
                          backgroundColor: Brand.navy,
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

/// One field as submitted: what the AI read, what the technician sent, their verdict and
/// why it was flagged. Nothing to edit.
class _FieldCard extends StatelessWidget {
  const _FieldCard(this.f);
  final ReviewedField f;

  static const _mono = TextStyle(fontFamily: 'IBM Plex Mono', fontSize: 14, fontWeight: FontWeight.w600);

  @override
  Widget build(BuildContext context) {
    final corrected = f.verificationState == 'corrected';
    final (fg, bg) = switch (f.verificationState) {
      'corrected' => (Brand.navy, Brand.info),
      'unreadable' || 'left_empty' => (Brand.errorInk, Brand.errorBg),
      _ => (const Color(0xFF2C7A30), const Color(0xFFE4F5E5)),
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
          Expanded(child: Text(f.label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Brand.body))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
            child: Text(f.verdict, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: fg)),
          ),
        ]),
        const SizedBox(height: 8),
        _line('AI read', f.aiValue, struck: corrected),
        _line('Technician', f.technicianValue),
        if (f.note != null && f.note!.isNotEmpty) _line('Note', f.note),
        for (final r in f.flagReasons)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(flagReasonText(r, f.confidence), style: const TextStyle(fontSize: 11, color: Brand.warn)),
          ),
      ]),
    );
  }

  Widget _line(String label, String? value, {bool struck = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 78, child: Text(label, style: const TextStyle(fontSize: 11, color: Brand.hint))),
          Expanded(
            child: Text(value ?? '—',
                style: _mono.copyWith(
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
        height: 140,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: urls.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, i) => GestureDetector(
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PhotoZoom(urls: urls, first: i))),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(width: urls.length == 1 ? 320 : 180, child: NetworkPhoto(url: urls[i])),
            ),
          ),
        ),
      );
}

/// Design 76: a reason is required; the note is sent as typed (whether it is required is
/// the API's call, O-21). Pops (category, note or null).
class _RejectSheet extends StatefulWidget {
  const _RejectSheet();

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
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Reject this scan', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              const Text('The technician who captured it sees the reason and your note.',
                  style: TextStyle(fontSize: 12.5, color: Brand.body)),
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
                decoration: const InputDecoration(labelText: 'Note for the technician', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _category == null
                    ? null
                    : () => Navigator.of(context).pop((_category!, _note.text.trim().isEmpty ? null : _note.text.trim())),
                style: FilledButton.styleFrom(backgroundColor: Brand.error, minimumSize: const Size.fromHeight(48), shape: const StadiumBorder()),
                child: const Text('Reject scan', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
        ),
      );
}
