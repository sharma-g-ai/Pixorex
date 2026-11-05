import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/api_exception.dart';
import '../../core/theme.dart';
import '../../widgets/auth_widgets.dart';
import '../home/home_screen.dart' show ago;
import 'capture_models.dart';
import 'photo_prep.dart';
import 'photo_set_screen.dart' show PreparePhoto;
import 'photo_source.dart';
import 'review_model.dart';
import 'review_screen.dart' show PhotoZoom;
import 'scan_details_screen.dart' show ScanHistoryScreen;
import 'scan_models.dart';
import 'scan_repository.dart';
import 'scan_uploader.dart';

const _green = Color(0xFF3C9F40);
const _greenInk = Color(0xFF2C7A30);
const _mono = TextStyle(fontFamily: 'IBM Plex Mono', fontFamilyFallback: [kFontFamily]);

/// "yesterday" as on design 68, otherwise as on the lists.
String _when(DateTime t, DateTime now) => now.difference(t).inDays == 1 ? 'yesterday' : ago(t, now);

/// How the technician resolved a rejection.
enum RejectionOutcome { resubmitted, retaken }

/// "Record rejected" (design 68): the reviewer's reason and note, then fix the fields
/// or retake the photo. Only the technician who captured the scan gets here.
class RejectionNoticeScreen extends StatefulWidget {
  const RejectionNoticeScreen({super.key, required this.scans, required this.scanId, this.onRetake, this.clock = DateTime.now});
  final ScanRepository scans;
  final String scanId;

  /// Starts the retake of this scan (design 71-72); completes with true once it was sent.
  final Future<bool> Function()? onRetake;
  final DateTime Function() clock;

  @override
  State<RejectionNoticeScreen> createState() => _RejectionNoticeScreenState();
}

class _RejectionNoticeScreenState extends State<RejectionNoticeScreen> {
  Scan? _scan;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final scan = await widget.scans.scan(widget.scanId);
      if (mounted) {
        setState(() {
          _scan = scan;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _correct(Scan scan) async {
    final result = await Navigator.of(context).push<RejectionOutcome?>(MaterialPageRoute(
      builder: (_) => RejectedReviewScreen(scans: widget.scans, scan: scan, onRetake: widget.onRetake),
    ));
    if (result != null && mounted) Navigator.of(context).pop(result);
  }

  Future<void> _retake() async {
    if (await widget.onRetake!() && mounted) Navigator.of(context).pop(RejectionOutcome.retaken);
  }

  @override
  Widget build(BuildContext context) {
    final s = _scan;
    final r = s?.rejection;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Brand.navy,
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: const Text('Record rejected', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
        actions: [
          if (s != null)
            TextButton(
              onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute(
                builder: (_) => ScanHistoryScreen(
                  scans: widget.scans,
                  scanId: s.scanId,
                  title: '${formatScanId(s.recordNo)} · ${s.equipmentTypeName}',
                ),
              )),
              child: const Text('History', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
      body: _error != null
          ? _Problem(_error!, _load)
          : s == null
              ? const Center(child: CircularProgressIndicator())
              : r == null
                  // Decided or fixed in the meantime: nothing left to resolve here.
                  ? const _Problem('This scan is no longer rejected. Go back to see where it is now.', null)
                  : Column(children: [
                      Expanded(
                        child: ListView(padding: const EdgeInsets.fromLTRB(22, 22, 22, 0), children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              width: 54,
                              height: 54,
                              decoration: BoxDecoration(color: Brand.errorBg, borderRadius: BorderRadius.circular(14)),
                              child: const Icon(Icons.cancel_outlined, color: Brand.error, size: 28),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text('${s.equipmentTypeName} was rejected', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text('${shortPlace(s.locationPath)} · reviewed by ${r.reviewerName} · ${_when(r.decidedAt.toLocal(), widget.clock())}',
                              style: _mono.copyWith(fontSize: 11.5, color: Brand.hint)),
                          const SizedBox(height: 18),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(color: Brand.errorBg, borderRadius: BorderRadius.circular(999)),
                              child: Text('Category: ${r.categoryLabel}',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Brand.error)),
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (r.note != null && r.note!.trim().isNotEmpty) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              decoration: BoxDecoration(color: Brand.errorBg, borderRadius: BorderRadius.circular(10)),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                const Text('Reviewer note',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Brand.errorInk)),
                                const SizedBox(height: 4),
                                Text('"${r.note!.trim()}"', style: const TextStyle(fontSize: 13.5, color: Brand.errorInk, height: 1.5)),
                              ]),
                            ),
                            const SizedBox(height: 20),
                          ] else
                            const SizedBox(height: 10),
                          const Text('Choose how to resolve this',
                              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Brand.body)),
                          const SizedBox(height: 10),
                          _Choice(
                            icon: Icons.edit_outlined,
                            title: 'Correct the fields',
                            text: 'Fix the field using the existing stored image — no recapture needed',
                            primary: true,
                            onTap: () => _correct(s),
                          ),
                          const SizedBox(height: 10),
                          _Choice(
                            icon: Icons.photo_camera_outlined,
                            title: 'Retake required',
                            text: 'Reviewer flagged the source image itself — retake it as a new scan; this one is closed and kept',
                            onTap: widget.onRetake == null ? null : _retake,
                          ),
                        ]),
                      ),
                      const SafeArea(
                        top: false,
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(22, 16, 22, 26),
                          child: Text(
                            'Rejected scans stay in My Scans. Only you can revise this scan because you captured it. '
                            'Correcting keeps this scan; retaking starts a new one.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11, color: Brand.hint),
                          ),
                        ),
                      ),
                    ]),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({required this.icon, required this.title, required this.text, required this.onTap, this.primary = false});
  final IconData icon;
  final String title;
  final String text;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: primary ? Brand.navy : Brand.line, width: 1.5),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              Icon(icon, size: 22, color: primary ? Brand.navy : Brand.ink),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title,
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: primary ? Brand.navy : Brand.ink)),
                  Text(text, style: const TextStyle(fontSize: 11.5, color: Brand.muted)),
                ]),
              ),
            ]),
          ),
        ),
      );
}

class _Problem extends StatelessWidget {
  const _Problem(this.text, this.onRetry);
  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          InfoBanner(text: text, error: onRetry != null),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            PillButton(label: 'Try again', outlined: true, onPressed: onRetry),
          ],
        ]),
      );
}

/// Correct a rejected scan and resubmit it to the reviewer who rejected it (design 69).
/// Pops with [RejectionOutcome.resubmitted], or [RejectionOutcome.retaken] after a retake.
class RejectedReviewScreen extends StatefulWidget {
  const RejectedReviewScreen({super.key, required this.scans, required this.scan, this.onRetake});
  final ScanRepository scans;
  final Scan scan;
  final Future<bool> Function()? onRetake;

  @override
  State<RejectedReviewScreen> createState() => _RejectedReviewScreenState();
}

class _RejectedReviewScreenState extends State<RejectedReviewScreen> {
  late final _fix = RejectionFix(widget.scan);
  String? _editing;
  bool _sending = false;
  String? _error;

  /// One Idempotency-Key per body, as on design 57: a repeated tap never sends twice.
  String? _key;
  String? _keyBody;

  Rejection get _r => widget.scan.rejection!;

  Future<void> _resubmit() async {
    FocusScope.of(context).unfocus();
    final body = _fix.body();
    final text = jsonEncode(body);
    if (text != _keyBody) {
      _key = const Uuid().v4();
      _keyBody = text;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.scans.submitRevision(
        widget.scan.scanId,
        fields: (body['fields'] as List).cast<Map<String, dynamic>>(),
        submitAnyway: body['submit_anyway'] as bool,
        idempotencyKey: _key!,
      );
      if (mounted) Navigator.of(context).pop(RejectionOutcome.resubmitted);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = switch (e.code) {
            'network' => "Couldn't send. Check your connection and tap Resubmit again.",
            'invalid-state' => 'This scan changed since you opened it. Go back and open it again.',
            _ => e.message,
          });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _retake() async {
    if (await widget.onRetake!() && mounted) Navigator.of(context).pop(RejectionOutcome.retaken);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scan;
    return Scaffold(
      backgroundColor: Brand.surfaceAlt,
      appBar: AppBar(
        backgroundColor: Brand.navy,
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s.equipmentTypeName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          Text('${shortPlace(s.locationPath)} · Rejected by ${_r.reviewerName}',
              style: const TextStyle(fontSize: 11, color: Colors.white70)),
        ]),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(color: Brand.errorBg, borderRadius: BorderRadius.circular(999)),
            child: const Text('Rejected', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Brand.error)),
          ),
        ],
      ),
      body: Column(children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: Brand.errorBg,
            border: Border(bottom: BorderSide(color: Color(0xFFF5C3BA))),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.chat_bubble_outline, size: 16, color: Brand.errorInk),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(style: const TextStyle(fontSize: 12, color: Brand.errorInk, height: 1.45), children: [
                  if (_r.note != null && _r.note!.trim().isNotEmpty) ...[
                    const TextSpan(text: 'Reviewer note: ', style: TextStyle(fontWeight: FontWeight.w700)),
                    TextSpan(text: '"${_r.note!.trim()}"'),
                  ] else ...[
                    const TextSpan(text: 'Category: ', style: TextStyle(fontWeight: FontWeight.w700)),
                    TextSpan(text: _r.categoryLabel),
                  ],
                ]),
              ),
            ),
          ]),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 14), children: [
            if (s.photoUrls.isNotEmpty) _Photo(urls: s.photoUrls),
            for (final f in _fix.fields)
              Padding(padding: const EdgeInsets.only(top: 10), child: _fieldCard(f)),
          ]),
        ),
      ]),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Brand.lineSoft))),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 22),
        child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_error != null)
              Padding(padding: const EdgeInsets.only(bottom: 10), child: InfoBanner(text: _error!, error: true)),
            SizedBox(
              height: 50,
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _sending ? null : _resubmit,
                style: FilledButton.styleFrom(
                  backgroundColor: Brand.navy,
                  shape: const StadiumBorder(),
                  textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, fontFamily: kFontFamily),
                ),
                icon: _sending
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded, size: 18),
                label: Text('Resubmit to ${_r.reviewerName}'),
              ),
            ),
            if (widget.onRetake != null)
              InkWell(
                onTap: _sending ? null : _retake,
                child: const Padding(
                  padding: EdgeInsets.only(top: 10, bottom: 2),
                  child: Text('Photo is the problem? Retake instead',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Brand.navy)),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _fieldCard(AiField f) {
    final fixed = _fix.fixOf(f);
    if (_editing == f.fieldKey || fixed != null) {
      return _EditCard(
        key: ValueKey('edit-${f.fieldKey}'),
        field: f,
        was: _fix.sentValue(f),
        value: fixed ?? _fix.sentValue(f) ?? '',
        onChanged: (v) => setState(() => _fix.fix(f, v)),
        onUndo: () => setState(() {
          _fix.undo(f);
          _editing = null;
        }),
      );
    }
    final sub = f.submitted!;
    final unreadable = sub.verificationState == 'unreadable';
    final empty = sub.verificationState == 'left_empty';
    final value = _fix.sentValue(f);
    return Material(
      key: ValueKey('field-${f.fieldKey}'),
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: Brand.lineSoft)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() => _editing = f.fieldKey),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 6, color: unreadable || empty ? Brand.body : _green),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(f.label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Brand.body)),
                      const SizedBox(height: 2),
                      Text(
                        unreadable
                            ? 'Unreadable · ${_reason(sub.unreadableReason)}'
                            : empty
                                ? 'Left empty'
                                : value ?? '—',
                        style: unreadable || empty
                            ? const TextStyle(fontSize: 13, color: Brand.muted)
                            : _valueStyle(value).copyWith(fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  if (unreadable || empty)
                    const Text('Tap to fix', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Brand.navy))
                  else
                    const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.check, size: 14, color: _greenInk),
                      SizedBox(width: 4),
                      Text('Checked', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _greenInk)),
                    ]),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

String _reason(String? code) =>
    UnreadableReason.values.where((r) => r.code == code).firstOrNull?.label.replaceAll(' — add a note', '') ?? 'no reason';

/// Codes, serials and tags read best fixed-width; names stay in the app font.
TextStyle _valueStyle(String? v) =>
    v != null && RegExp(r'\d').hasMatch(v) ? _mono : const TextStyle(fontFamily: kFontFamily);

/// A field being corrected: what was sent, struck through, and the new value (design 69).
class _EditCard extends StatefulWidget {
  const _EditCard({super.key, required this.field, required this.was, required this.value, required this.onChanged, required this.onUndo});
  final AiField field;
  final String? was;
  final String value;
  final ValueChanged<String> onChanged;
  final VoidCallback onUndo;

  @override
  State<_EditCard> createState() => _EditCardState();
}

class _EditCardState extends State<_EditCard> {
  late final _text = TextEditingController(text: widget.value);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final changed = _text.text.trim().isNotEmpty && _text.text.trim() != widget.was;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Brand.navy, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 6, color: Brand.navy),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(widget.field.label,
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Brand.body)),
                  ),
                  InkWell(
                    onTap: widget.onUndo,
                    child: const Text('Undo', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Brand.navy)),
                  ),
                ]),
                if (widget.was != null) ...[
                  const SizedBox(height: 6),
                  Text.rich(TextSpan(style: const TextStyle(fontSize: 11.5, color: Brand.hint), children: [
                    const TextSpan(text: 'Was: '),
                    TextSpan(text: widget.was, style: _mono.copyWith(decoration: TextDecoration.lineThrough)),
                  ])),
                ],
                const SizedBox(height: 6),
                TextField(
                  key: Key('fix-${widget.field.fieldKey}'),
                  controller: _text,
                  autofocus: true,
                  style: _mono.copyWith(fontSize: 14, color: const Color(0xFF12181F)),
                  keyboardType: widget.field.dataType == 'number' ? TextInputType.number : TextInputType.text,
                  onChanged: (v) {
                    widget.onChanged(v);
                    setState(() {});
                  },
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Brand.navy, width: 1.5),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Brand.navy, width: 1.5),
                    ),
                  ),
                ),
                if (changed) ...[
                  const SizedBox(height: 6),
                  const Row(children: [
                    Icon(Icons.check, size: 14, color: Brand.navy),
                    SizedBox(width: 4),
                    Text('Corrected by you', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Brand.navy)),
                  ]),
                ],
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Photo extends StatelessWidget {
  const _Photo({required this.urls});
  final List<String> urls;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PhotoZoom(urls: urls, first: 0))),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            height: 110,
            child: Stack(fit: StackFit.expand, children: [
              Image.network(urls.first, fit: BoxFit.cover, errorBuilder: (_, _, _) => const _Placeholder()),
              Positioned(
                right: 10,
                bottom: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(999)),
                  child: const Text('Tap to zoom', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
                ),
              ),
            ]),
          ),
        ),
      );
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({this.colors = const [Color(0xFF3A4552), Color(0xFF232B34)]});
  final List<Color> colors;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight)),
      );
}

/// "New scan · retake" (design 71): one photo of the same equipment, with the old scan's
/// type and place. Pops with true once the new scan was sent (design 72).
class RejectedRetakeScreen extends StatefulWidget {
  const RejectedRetakeScreen({
    super.key,
    required this.scans,
    required this.old,
    required this.type,
    required this.photoSource,
    this.prepare = prepareJpeg,
    this.clock = DateTime.now,
  });
  final ScanRepository scans;
  final Scan old;
  final EquipmentType type;
  final PhotoSource Function() photoSource;
  final PreparePhoto prepare;
  final DateTime Function() clock;

  @override
  State<RejectedRetakeScreen> createState() => _RejectedRetakeScreenState();
}

class _RejectedRetakeScreenState extends State<RejectedRetakeScreen> {
  late final PhotoSource _source = widget.photoSource();
  bool _busy = false;

  @override
  void dispose() {
    _source.dispose();
    super.dispose();
  }

  void _say(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _take() async {
    if (_busy) return;
    setState(() => _busy = true);
    Uint8List? jpeg;
    try {
      final raw = await _source.shutter();
      if (raw != null) jpeg = await widget.prepare(raw);
    } on PhotoSourceException catch (e) {
      _say(e.message);
    } on PhotoPrepException catch (e) {
      _say(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (jpeg == null || !mounted) return;
    final sent = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => RetakeConfirmScreen(
        scans: widget.scans,
        old: widget.old,
        type: widget.type,
        photo: jpeg!,
        capturedAt: widget.clock(),
      ),
    ));
    if (sent == true && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final old = widget.old;
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D10),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D10),
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: const Text('New scan · retake', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
      body: Column(children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0x297FA3EA),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: const Color(0x737FA3EA)),
          ),
          child: Text.rich(TextSpan(style: const TextStyle(fontSize: 12, color: Color(0xFFD6E1FA), height: 1.45), children: [
            const TextSpan(text: 'This starts a new scan. ', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
            TextSpan(text: 'The rejected ${old.equipmentTypeName} is closed and kept with its history, linked to the new one.'),
          ])),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Row(children: [
            Expanded(child: _Fixed('Equipment type', old.equipmentTypeName)),
            const SizedBox(width: 8),
            Expanded(child: _Fixed('Location (from old scan)', shortPlace(old.locationPath))),
          ]),
        ),
        Expanded(child: _source.viewfinder(hint: 'Photograph the same equipment again')),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 26),
            child: GestureDetector(
              key: const Key('shutter'),
              onTap: _busy ? null : _take,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(color: Brand.navy, shape: BoxShape.circle),
                  child: _busy
                      ? const Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.photo_camera, color: Colors.white, size: 28),
                ),
                const SizedBox(height: 6),
                const Text('Take photo', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

/// The old scan's type or place, kept for the retake (design 71).
class _Fixed extends StatelessWidget {
  const _Fixed(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Brand.hint)),
        const SizedBox(height: 6),
        Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF17181C),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: const Color(0xFF2A2D33)),
          ),
          alignment: Alignment.centerLeft,
          child: Text(value,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: Color(0xFFB8BCC4))),
        ),
      ]);
}

/// "Submit new scan" (design 72): what the retake creates and closes, then send it.
class RetakeConfirmScreen extends StatefulWidget {
  const RetakeConfirmScreen({
    super.key,
    required this.scans,
    required this.old,
    required this.type,
    required this.photo,
    required this.capturedAt,
  });
  final ScanRepository scans;
  final Scan old;
  final EquipmentType type;
  final Uint8List photo;
  final DateTime capturedAt;

  @override
  State<RetakeConfirmScreen> createState() => _RetakeConfirmScreenState();
}

class _RetakeConfirmScreenState extends State<RetakeConfirmScreen> {
  late final ScanUploader _uploader = ScanUploader(widget.scans);
  late final CaptureDraft _draft = CaptureDraft(
    type: widget.type,
    clientCaptureId: const Uuid().v4(),
    capturedAt: widget.capturedAt,
    first: widget.photo,
    retakeOfScanId: widget.old.scanId,
  );
  bool _sending = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await _uploader.send(_draft, buId: widget.old.buId, locationNodeId: widget.old.locationNodeId!);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.code == 'network'
            ? "Couldn't send the scan. Check your connection and tap Submit new scan again."
            : e.message);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final old = widget.old;
    final type = old.equipmentTypeName;
    final path = old.locationPath.split(' › ');
    final reviewer = old.rejection?.reviewerName;
    return Scaffold(
      backgroundColor: Brand.surfaceAlt,
      appBar: AppBar(
        backgroundColor: Brand.navy,
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: const Text('Submit new scan', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: _Shot(
              image: old.photoUrls.isEmpty
                  ? const _Placeholder(colors: [Color(0xFF4A2A2A), Color(0xFF2A1A1A)])
                  : Image.network(old.photoUrls.first,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const _Placeholder(colors: [Color(0xFF4A2A2A), Color(0xFF2A1A1A)])),
              title: 'Old scan',
              text: 'Rejected · will be closed',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: _Shot(image: Image.memory(widget.photo, fit: BoxFit.cover), title: 'New photo', text: 'Just taken')),
        ]),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Brand.lineSoft),
          ),
          child: Column(children: [
            _Line('Creates', 'New scan · $type'),
            _Line('Closes', '$type (rejected)'),
            _Line('Equipment type', type),
            // As on the design, from the building down: the plant is the same for every scan.
            _Line('Location', (path.length > 1 ? path.sublist(1) : path).join(' › '), last: true),
          ]),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(color: Brand.info, borderRadius: BorderRadius.circular(10)),
          child: const Text.rich(TextSpan(style: TextStyle(fontSize: 12, color: Brand.navyDeep, height: 1.5), children: [
            TextSpan(text: "The old scan isn't edited or deleted. It stays in My Scans as "),
            TextSpan(text: 'Closed', style: TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: ' with a link to this new scan, so reviewers can see both.'),
          ])),
        ),
        const SizedBox(height: 14),
        Text(
          'The new photo is read from scratch. You check what was read, then send it'
          '${reviewer == null ? ' for review' : ' to $reviewer'} as a new submission.',
          style: const TextStyle(fontSize: 12, color: Brand.muted, height: 1.5),
        ),
        if (_error != null) ...[const SizedBox(height: 14), InfoBanner(text: _error!, error: true)],
      ]),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Brand.lineSoft))),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 22),
        child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            PillButton(label: 'Submit new scan', loading: _sending, onPressed: _sending ? null : _submit),
            const SizedBox(height: 8),
            SizedBox(
              height: 42,
              width: double.infinity,
              child: TextButton(
                onPressed: _sending ? null : () => Navigator.of(context).pop(false),
                style: TextButton.styleFrom(
                  foregroundColor: Brand.navy,
                  shape: const StadiumBorder(),
                  textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, fontFamily: kFontFamily),
                ),
                child: const Text('Retake again'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Shot extends StatelessWidget {
  const _Shot({required this.image, required this.title, required this.text});
  final Widget image;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(borderRadius: BorderRadius.circular(10), child: SizedBox(height: 150, width: double.infinity, child: image)),
        const SizedBox(height: 6),
        Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        Text(text, style: const TextStyle(fontSize: 11, color: Brand.hint)),
      ]);
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value, {this.last = false});
  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: Color(0xFFEFF1F3)))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 12.5, color: Brand.muted)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(value, textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ]),
      );
}
