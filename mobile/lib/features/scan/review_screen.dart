import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/api_exception.dart';
import '../../core/theme.dart';
import '../../widgets/auth_widgets.dart';
import 'review_model.dart';
import 'scan_details_screen.dart' show ScanHistoryScreen;
import 'scan_models.dart';
import 'scan_repository.dart';
import 'scan_thumb.dart' show NetworkPhoto;

const _green = Color(0xFF3C9F40);
const _amber = Color(0xFFE8A02C);
const _red = Color(0xFFC0392B);
/// Read values: the app font with fixed-width digits, so 0/O and 1/I line up to compare.
const _mono = TextStyle(fontFamily: kFontFamily, fontFeatures: [FontFeature.tabularFigures()]);

/// Check what the AI read and send the scan to a reviewer (design 57-62).
/// Pops with `true` once the revision is accepted by the API, `false` when discarded.
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key, required this.scans, required this.scanId, this.pollEvery = const Duration(seconds: 3)});
  final ScanRepository scans;
  final String scanId;

  /// While the worker is still reading the label (no push: docs/mobile-api.md section 5).
  final Duration pollEvery;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  ReviewDraft? _draft;
  String? _loadError;
  String? _sendError;
  bool _sending = false;
  Timer? _poll;

  /// One Idempotency-Key per revision body: pressing Submit again after a lost
  /// answer reuses it, so the API doesn't record two revisions.
  String? _key;
  String? _keyBody;

  /// The type-mismatch question is asked once per visit (design 54).
  bool _askedMismatch = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    _poll?.cancel();
    try {
      final scan = await widget.scans.scan(widget.scanId);
      if (!mounted) return;
      setState(() {
        _loadError = null;
        _draft = ReviewDraft(scan);
      });
      if (!scan.isSettled) _poll = Timer(widget.pollEvery, _load);
      if (scan.hasTypeMismatch && scan.reviewStatus == 'draft' && !_askedMismatch) {
        _askedMismatch = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _mismatch(scan));
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _loadError = e.message);
    }
  }

  /// Design 54: the photo looks like another type than the one chosen.
  Future<void> _mismatch(Scan scan) async {
    final suggestedId = scan.latestAttempt!.suggestedTypeId!;
    String? suggested;
    try {
      suggested = (await widget.scans.equipmentTypes(scan.buId)).where((t) => t.typeId == suggestedId).firstOrNull?.name;
    } on ApiException {
      // Asked without the name: the choice still works.
    }
    if (!mounted) return;
    final detected = scan.latestAttempt!.detectedLabel;
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _MismatchDialog(
        detected: detected,
        selected: scan.equipmentTypeName,
        suggested: suggested,
        canReExtract: scan.attemptsUsed < Scan.maxAttempts,
      ),
    );
    if (!mounted) return;
    if (choice == 'discard') return _discard();
    if (choice != 'reextract') return;
    try {
      await widget.scans.reExtract(scan.scanId, suggestedId);
      await _load(); // now extracting as the new type: this page waits for it
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Design 55: only before submitting (contract 2.27).
  Future<void> _discard() async {
    final s = _draft!.scan;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Discard ${s.equipmentTypeName}?'),
        content: const Text("It's removed from My Scans and can't be recovered. Nothing is sent to the reviewer."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Brand.error),
            child: const Text('Discard scan'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    try {
      await widget.scans.discard(s.scanId);
      if (mounted) Navigator.of(context).pop(false);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  bool get _reviewable {
    final s = _draft?.scan;
    return s != null && s.processingStatus == 'ready_to_review' && (s.reviewStatus == 'draft' || s.reviewStatus == 'rejected');
  }

  Future<void> _submit() async {
    final d = _draft!;
    if (d.emptyRequired.isNotEmpty) {
      final choice = await _requiredModal(d.emptyRequired);
      if (choice == null || !mounted) return;
      if (choice == 'anyway') return _send(submitAnyway: true);
      return; // "Fill it in": back to the form
    }
    await _send();
  }

  Future<void> _send({bool submitAnyway = false}) async {
    final d = _draft!;
    final body = d.body(submitAnyway: submitAnyway);
    final bodyText = jsonEncode(body);
    if (bodyText != _keyBody) {
      _key = const Uuid().v4();
      _keyBody = bodyText;
    }
    setState(() {
      _sending = true;
      _sendError = null;
    });
    try {
      await widget.scans.submitRevision(
        d.scan.scanId,
        fields: (body['fields'] as List).cast<Map<String, dynamic>>(),
        submitAnyway: submitAnyway,
        idempotencyKey: _key!,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _sendError = switch (e.code) {
            'network' => "Couldn't send. Check your connection and tap Submit for review again.",
            'invalid-state' => 'This scan changed since you opened it. Go back and open it again.',
            _ => e.message,
          });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Design 60: 'fill' or 'anyway'; marking one unreadable from here submits too.
  Future<String?> _requiredModal(List<AiField> empty) => showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('${empty.length} required field${empty.length == 1 ? ' is' : 's are'} empty'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final f in empty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(f.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(f.isFlagged ? flagText(f) : 'Required', style: const TextStyle(fontSize: 12, color: Brand.muted)),
                ]),
              ),
            const Text("Fill it in, or tell the reviewer it can't be read on the equipment.",
                style: TextStyle(fontSize: 12.5, color: Brand.body)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, 'fill'), child: const Text('Fill it in')),
            if (empty.length == 1)
              TextButton(
                onPressed: () async {
                  final marked = await _markUnreadable(empty.single, andSubmit: true);
                  if (marked && ctx.mounted) Navigator.pop(ctx, 'marked');
                },
                child: const Text('Mark unreadable'),
              ),
            TextButton(onPressed: () => Navigator.pop(ctx, 'anyway'), child: const Text('Submit anyway')),
          ],
        ),
      );

  /// Design 58 / 61. Returns whether the field was marked.
  Future<bool> _markUnreadable(AiField f, {bool andSubmit = false}) async {
    final answer = await showModalBottomSheet<FieldAnswer>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _UnreadableSheet(field: f, andSubmit: andSubmit),
    );
    if (answer == null || !mounted) return false;
    setState(() => _draft!.answer(f, answer));
    if (andSubmit) unawaited(_submit());
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final d = _draft;
    final s = d?.scan;
    return Scaffold(
      backgroundColor: Brand.surfaceAlt,
      appBar: AppBar(
        backgroundColor: Brand.navy,
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: s == null
            ? const Text('Scan')
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.equipmentTypeName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                Text('${formatScanId(s.recordNo)} · ${shortPlace(s.locationPath)} · ${_statusLabel(s)}',
                    style: const TextStyle(fontSize: 11, color: Colors.white70)),
              ]),
        actions: [
          if (s != null)
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (v) => v == 'history'
                  ? Navigator.of(context).push<void>(MaterialPageRoute(
                      builder: (_) => ScanHistoryScreen(
                        scans: widget.scans,
                        scanId: s.scanId,
                        title: '${formatScanId(s.recordNo)} · ${s.equipmentTypeName}',
                      ),
                    ))
                  : _discard(),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'history', child: Text('History')),
                if (s.reviewStatus == 'draft' && s.isSettled) const PopupMenuItem(value: 'discard', child: Text('Discard scan')),
              ],
            ),
          if (d != null && _reviewable && d.flagged.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: d.canSubmit ? const Color(0xFFE4F5E5) : Brand.warnBg,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text('${d.checked} of ${d.flagged.length} checked',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: d.canSubmit ? const Color(0xFF1F5E23) : const Color(0xFF8B3E0C),
                  )),
            ),
        ],
      ),
      body: _loadError != null
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                InfoBanner(text: _loadError!, error: true),
                const SizedBox(height: 12),
                PillButton(label: 'Try again', outlined: true, onPressed: _load),
              ]),
            )
          : d == null
              ? const Center(child: CircularProgressIndicator())
              : _reviewable
                  ? _form(d)
                  : _Status(scan: d.scan),
      bottomNavigationBar: d != null && _reviewable ? _footer(d) : null,
    );
  }

  String _statusLabel(Scan s) => switch ((s.processingStatus, s.reviewStatus)) {
        (_, 'waiting_for_approval') => 'Submitted',
        (_, 'approved') => 'Approved',
        (_, 'rejected') => 'Rejected',
        ('ready_to_review', _) => 'Ready to Review',
        ('failed', _) => 'Extraction failed',
        ('retake_required', _) => 'Retake needed',
        _ => 'Extracting',
      };

  Widget _form(ReviewDraft d) {
    final fields = [...d.scan.fields.where((f) => f.isFlagged), ...d.scan.fields.where((f) => !f.isFlagged)];
    return Column(children: [
      Container(
        width: double.infinity,
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: const Wrap(spacing: 14, runSpacing: 6, children: [
          _Legend(_green, 'Looks right'),
          _Legend(_amber, 'Check this'),
          _Legend(_red, 'Likely wrong'),
          _Legend(Brand.navy, 'Done'),
        ]),
      ),
      Expanded(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (d.scan.photoUrls.isNotEmpty) _Photos(urls: d.scan.photoUrls),
          for (final f in fields)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: _FieldCard(
                key: ValueKey(f.fieldKey),
                field: f,
                answer: d.answerFor(f),
                onAnswer: (a) => setState(() => d.answer(f, a)),
                onUnreadable: () => _markUnreadable(f),
              ),
            ),
        ]),
      ),
    ]);
  }

  Widget _footer(ReviewDraft d) {
    final left = d.leftToCheck;
    final empty = d.emptyRequired.length;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_sendError != null)
            Padding(padding: const EdgeInsets.only(bottom: 10), child: InfoBanner(text: _sendError!, error: true)),
          PillButton(
            label: left > 0 ? 'Submit for review · $left left to check' : 'Submit for review',
            loading: _sending,
            onPressed: d.canSubmit ? _submit : null,
          ),
          const SizedBox(height: 8),
          Text(
            left > 0 || empty == 0
                ? 'Each flagged field shows why it was flagged'
                : '$empty required field${empty == 1 ? ' is' : 's are'} still empty',
            style: const TextStyle(fontSize: 11.5, color: Brand.hint),
          ),
        ]),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend(this.color, this.label);
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 14, height: 8, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 11, color: Brand.body)),
      ]);
}

/// Signed photo links (valid 15 minutes); tap to zoom.
class _Photos extends StatelessWidget {
  const _Photos({required this.urls});
  final List<String> urls;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 116,
        child: Row(children: [
          Expanded(child: _photo(context, 0, label: 'Photo 1 of ${urls.length} · tap to zoom')),
          for (var i = 1; i < urls.length && i < 3; i++) ...[
            const SizedBox(width: 8),
            SizedBox(width: 64, child: _photo(context, i)),
          ],
        ]),
      );

  Widget _photo(BuildContext context, int i, {String? label}) => GestureDetector(
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PhotoZoom(urls: urls, first: i))),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(fit: StackFit.expand, children: [
            NetworkPhoto(url: urls[i], compact: label == null),
            if (label != null)
              Positioned(
                right: 10,
                bottom: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(999)),
                  child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
                ),
              ),
          ]),
        ),
      );
}

class PhotoZoom extends StatelessWidget {
  const PhotoZoom({super.key, required this.urls, required this.first});
  final List<String> urls;
  final int first;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
        body: PageView(
          controller: PageController(initialPage: first),
          children: [for (final u in urls) InteractiveViewer(maxScale: 5, child: Center(child: NetworkPhoto(url: u, fit: BoxFit.contain)))],
        ),
      );
}

class _FieldCard extends StatefulWidget {
  const _FieldCard({super.key, required this.field, required this.answer, required this.onAnswer, required this.onUnreadable});
  final AiField field;
  final FieldAnswer answer;
  final ValueChanged<FieldAnswer> onAnswer;
  final VoidCallback onUnreadable;

  @override
  State<_FieldCard> createState() => _FieldCardState();
}

class _FieldCardState extends State<_FieldCard> {
  late final _text = TextEditingController(text: widget.field.aiValue ?? '');
  late bool _editing = flagLevel(widget.field) == FlagLevel.likelyWrong;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  AiField get f => widget.field;
  bool get _empty => f.aiValue == null || f.aiValue!.trim().isEmpty;

  void _save() {
    final v = _text.text.trim();
    if (v.isEmpty) return;
    widget.onAnswer(v == f.aiValue ? const FieldAnswer.accepted() : FieldAnswer.corrected(v));
  }

  void _reopen() {
    _text.text = widget.answer.value ?? f.aiValue ?? '';
    setState(() => _editing = true);
    widget.onAnswer(const FieldAnswer.pending());
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.answer;
    if (!f.isFlagged) {
      return _Card(bar: _green, label: f.label, status: 'Looks right', statusColor: const Color(0xFF2C7A30), children: [
        Text(f.aiValue ?? '—', style: _mono.copyWith(fontSize: 15, fontWeight: FontWeight.w600)),
      ]);
    }
    final was = 'Was flagged: ${flagText(f)[0].toLowerCase()}${flagText(f).substring(1)}';
    switch (a.verdict) {
      case Verdict.corrected:
        return _Card(bar: Brand.navy, label: f.label, status: 'Corrected', statusColor: Brand.navy, children: [
          _Chip(was),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(color: Brand.surfaceAlt, borderRadius: BorderRadius.circular(8)),
            child: Column(children: [
              if (!_empty)
                _Row('AI read', Text(f.aiValue!,
                    style: _mono.copyWith(fontSize: 13, color: Brand.hint, decoration: TextDecoration.lineThrough))),
              _Row('You', Text(a.value!, style: _mono.copyWith(fontSize: 14, fontWeight: FontWeight.w600)), you: true),
            ]),
          ),
          _Link('Change', _reopen),
        ]);
      case Verdict.accepted:
        return _Card(bar: Brand.navy, label: f.label, status: 'Kept as read', statusColor: Brand.navy, children: [
          _Chip(was),
          Text(f.aiValue ?? '—', style: _mono.copyWith(fontSize: 15, fontWeight: FontWeight.w600)),
          const Text('You confirmed the AI value matches the plate', style: TextStyle(fontSize: 11, color: Brand.muted)),
          _Link('Change', _reopen),
        ]);
      case Verdict.unreadable:
        return _Card(bar: Brand.body, label: f.label, status: 'Marked unreadable', statusColor: Brand.body, children: [
          _Chip(was),
          Text.rich(TextSpan(style: const TextStyle(fontSize: 13), children: [
            const TextSpan(text: 'Reason: '),
            TextSpan(text: a.reason!.label.replaceAll(' — add a note', ''), style: const TextStyle(fontWeight: FontWeight.w700)),
            if (a.note != null && a.note!.isNotEmpty) TextSpan(text: ' · ${a.note}'),
          ])),
          const Text('The reviewer sees this was checked, not skipped', style: TextStyle(fontSize: 11, color: Brand.muted)),
          _Link('Undo', () => widget.onAnswer(const FieldAnswer.pending())),
        ]);
      case Verdict.pending:
        return _empty ? _emptyCard() : _flaggedCard();
    }
  }

  Widget _flaggedCard() {
    final wrong = flagLevel(f) == FlagLevel.likelyWrong;
    return _Card(
      bar: wrong ? _red : _amber,
      label: f.label,
      status: wrong ? 'Likely wrong' : 'Check this',
      statusColor: wrong ? _red : const Color(0xFFB4540A),
      children: [
        _Chip(flagText(f)),
        if (_editing)
          _Input(controller: _text, field: f, border: wrong ? _red : _amber, onSubmitted: _save)
        else
          Text(f.aiValue!, style: _mono.copyWith(fontSize: 16, fontWeight: FontWeight.w600)),
        Row(children: [
          Expanded(child: _Pill('Keep as is', () => widget.onAnswer(const FieldAnswer.accepted()))),
          const SizedBox(width: 8),
          Expanded(
            child: _editing
                ? _Pill('Save fix', _save, primary: true)
                : _Pill('Edit', () => setState(() => _editing = true), primary: true),
          ),
        ]),
        Align(
          alignment: Alignment.centerRight,
          child: _Link('Mark unreadable', widget.onUnreadable, key: Key('unreadable-${f.fieldKey}')),
        ),
      ],
    );
  }

  Widget _emptyCard() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Brand.errorBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE8A79E), width: 1.5),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(f.label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Brand.errorInk)),
            if (f.isRequired) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFFF5C3BA), borderRadius: BorderRadius.circular(5)),
                child: const Text('REQUIRED', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: Brand.errorInk)),
              ),
            ],
          ]),
          const SizedBox(height: 7),
          _Chip(flagText(f), error: true),
          const SizedBox(height: 7),
          _Input(
            controller: _text,
            field: f,
            border: const Color(0xFFE8A79E),
            hint: 'Add ${f.label[0].toLowerCase()}${f.label.substring(1)}',
            onSubmitted: _save,
            trailing: ValueListenableBuilder(
              valueListenable: _text,
              builder: (_, v, _) => v.text.trim().isEmpty ? const SizedBox.shrink() : TextButton(onPressed: _save, child: const Text('Save')),
            ),
          ),
          const SizedBox(height: 7),
          Row(children: [
            const Expanded(child: Text('Type it in, or mark it unreadable', style: TextStyle(fontSize: 11.5, color: Brand.errorInk))),
            _Link('Mark unreadable', widget.onUnreadable, key: Key('unreadable-${f.fieldKey}')),
          ]),
        ]),
      );
}

class _Card extends StatelessWidget {
  const _Card({required this.bar, required this.label, required this.status, required this.statusColor, required this.children});
  final Color bar;
  final String label;
  final String status;
  final Color statusColor;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Brand.lineSoft),
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 6, color: bar),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Brand.body))),
                    Text(status, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: statusColor)),
                  ]),
                  for (final c in children) Padding(padding: const EdgeInsets.only(top: 7), child: c),
                ]),
              ),
            ),
          ]),
        ),
      );
}

class _Chip extends StatelessWidget {
  const _Chip(this.text, {this.error = false});
  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: error ? const Color(0xFFF9D9D3) : const Color(0xFFF1F3F6),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.info_outline, size: 12, color: error ? Brand.errorInk : Brand.body),
          const SizedBox(width: 5),
          Flexible(
            child: Text(text,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: error ? Brand.errorInk : Brand.body)),
          ),
        ]),
      );
}

class _Input extends StatelessWidget {
  const _Input({required this.controller, required this.field, required this.border, required this.onSubmitted, this.hint, this.trailing});
  final TextEditingController controller;
  final AiField field;
  final Color border;
  final VoidCallback onSubmitted;
  final String? hint;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        keyboardType: field.dataType == 'number' ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
        style: _mono.copyWith(fontSize: 14),
        onSubmitted: (_) => onSubmitted(),
        decoration: InputDecoration(
          hintText: hint,
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          suffixIcon: trailing,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: border, width: 1.5)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Brand.navy, width: 2)),
        ),
      );
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.you = false});
  final String label;
  final Widget value;
  final bool you;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 56,
            child: Text(label,
                style: TextStyle(fontSize: 10.5, fontWeight: you ? FontWeight.w700 : FontWeight.w600, color: you ? Brand.navy : Brand.hint)),
          ),
          Expanded(child: value),
        ]),
      );
}

class _Pill extends StatelessWidget {
  const _Pill(this.label, this.onTap, {this.primary = false});
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) => Material(
        color: primary ? Brand.navy : const Color(0xFFF3F5F7),
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: Text(label,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: primary ? Colors.white : Brand.body)),
            ),
          ),
        ),
      );
}

class _Link extends StatelessWidget {
  const _Link(this.label, this.onTap, {super.key});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Brand.navy)),
        ),
      );
}

/// Design 58: why the value can't be read; "Other" needs a note.
class _UnreadableSheet extends StatefulWidget {
  const _UnreadableSheet({required this.field, required this.andSubmit});
  final AiField field;
  final bool andSubmit;

  @override
  State<_UnreadableSheet> createState() => _UnreadableSheetState();
}

class _UnreadableSheetState extends State<_UnreadableSheet> {
  UnreadableReason? _reason;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  bool get _ok => _reason != null && (_reason != UnreadableReason.other || _note.text.trim().isNotEmpty);

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Mark ${widget.field.label} as unreadable?', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text("Use this when the value really can't be read on the equipment. The reviewer will see your reason.",
                  style: TextStyle(fontSize: 12.5, color: Brand.body)),
              const SizedBox(height: 8),
              RadioGroup<UnreadableReason>(
                groupValue: _reason,
                onChanged: (r) => setState(() => _reason = r),
                child: Column(children: [
                  for (final r in UnreadableReason.values)
                    RadioListTile<UnreadableReason>(value: r, title: Text(r.label), dense: true, contentPadding: EdgeInsets.zero),
                ]),
              ),
              if (_reason == UnreadableReason.other)
                TextField(
                  controller: _note,
                  maxLength: 2000,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(hintText: 'What is wrong with it?', counterText: ''),
                ),
              const SizedBox(height: 12),
              PillButton(
                label: widget.andSubmit ? 'Mark unreadable and submit' : 'Mark unreadable',
                onPressed: _ok
                    ? () => Navigator.pop(context, FieldAnswer.unreadable(_reason!, note: _note.text.trim()))
                    : null,
              ),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ]),
          ),
        ),
      );
}

/// A scan that isn't waiting for the technician (still reading, failed, submitted...).
class _Status extends StatelessWidget {
  const _Status({required this.scan});
  final Scan scan;

  @override
  Widget build(BuildContext context) {
    final (icon, title, text) = switch ((scan.processingStatus, scan.reviewStatus)) {
      (_, 'waiting_for_approval') => (Icons.hourglass_top, 'With the reviewer', 'You sent this scan for review. You will see the decision in My Scans.'),
      (_, 'approved') => (Icons.check_circle_outline, 'Approved', 'This scan was approved.'),
      (_, 'closed' || 'discarded') => (Icons.block, 'Closed', 'This scan is no longer in use.'),
      ('failed', _) => (Icons.error_outline, 'Extraction failed', "The label couldn't be read this time. Retry from My Scans."),
      ('retake_required', _) => (Icons.photo_camera_outlined, 'Retake needed', 'The label was tried 3 times. Take new photos from My Scans.'),
      _ => (Icons.document_scanner_outlined, 'Reading the label…', 'This usually takes a few seconds. This page updates by itself.'),
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 48, color: Brand.navy),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Brand.body)),
          if (!scan.isSettled) ...[const SizedBox(height: 20), const CircularProgressIndicator()],
        ]),
      ),
    );
  }
}

/// Type mismatch (design 54): what the AI saw, then three full-width choices stacked by
/// importance, big enough for gloved hands. Pops 'keep', 'reextract' or 'discard'.
class _MismatchDialog extends StatelessWidget {
  const _MismatchDialog({required this.detected, required this.selected, required this.suggested, required this.canReExtract});
  final String? detected;
  final String selected;
  final String? suggested;
  final bool canReExtract;

  static const _ink = Color(0xFF1B1E7A);

  @override
  Widget build(BuildContext context) {
    final bold = const TextStyle(fontWeight: FontWeight.w700);
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 14),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(color: Color(0xFFFDEBD8), shape: BoxShape.circle),
            child: const Icon(Icons.warning_amber_rounded, color: Brand.warn, size: 28),
          ),
          const SizedBox(height: 10),
          const Text('Type mismatch', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: _ink)),
          const SizedBox(height: 10),
          Text.rich(
            TextSpan(style: const TextStyle(fontSize: 14, color: Color(0xFF3D434B), height: 1.55), children: [
              if (detected != null) ...[
                const TextSpan(text: 'Image appears to be: '),
                TextSpan(text: detected, style: bold),
                const TextSpan(text: '. '),
              ],
              const TextSpan(text: 'You selected: '),
              TextSpan(text: selected, style: bold),
              const TextSpan(text: '.'),
              if (suggested != null) ...[
                const TextSpan(text: ' Suggested type: '),
                TextSpan(text: suggested, style: bold),
                const TextSpan(text: '.'),
              ],
            ]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            canReExtract
                ? 'Re-extract as the suggested type, keep the current results, or discard?'
                : 'All 3 reads are used. Keep the current results, or discard?',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, color: Brand.hint, height: 1.45),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: FilledButton(
              onPressed: () => Navigator.pop(context, 'keep'),
              style: FilledButton.styleFrom(
                backgroundColor: _ink,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, fontFamily: kFontFamily),
              ),
              child: const Text('Keep results'),
            ),
          ),
          if (canReExtract) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.pop(context, 'reextract'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _ink,
                  side: const BorderSide(color: _ink, width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, fontFamily: kFontFamily),
                ),
                icon: const Icon(Icons.refresh, size: 18),
                label: Text('Re-extract as ${suggested ?? 'the suggested type'}', overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
          const SizedBox(height: 4),
          TextButton(
            onPressed: () => Navigator.pop(context, 'discard'),
            style: TextButton.styleFrom(
              foregroundColor: Brand.error,
              minimumSize: const Size(120, 44),
              textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, fontFamily: kFontFamily),
            ),
            child: const Text('Discard'),
          ),
        ]),
      ),
    );
  }
}
