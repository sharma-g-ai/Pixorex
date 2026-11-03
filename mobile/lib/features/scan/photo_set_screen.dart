import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'capture_models.dart';
import 'new_scan_screen.dart' show CaptureColors;
import 'photo_prep.dart';
import 'photo_source.dart';

typedef PreparePhoto = Future<Uint8List> Function(Uint8List raw);

const _blue = Color(0xFF7FA3EA);

/// The photos of one scan (design 39, 40): look, remove, add up to 4, then Next.
class PhotoSetScreen extends StatefulWidget {
  const PhotoSetScreen({
    super.key,
    required this.draft,
    required this.source,
    required this.onNext,
    this.prepare = prepareJpeg,
  });
  final CaptureDraft draft;
  final PhotoSource source;
  final ValueChanged<CaptureDraft> onNext;
  final PreparePhoto prepare;

  @override
  State<PhotoSetScreen> createState() => _PhotoSetScreenState();
}

class _PhotoSetScreenState extends State<PhotoSetScreen> {
  late int _shown = widget.draft.photos.length - 1;
  bool _adding = false;

  List<Uint8List> get _photos => widget.draft.photos;

  Future<void> _add() async {
    final raw = await Navigator.of(context).push<Uint8List>(MaterialPageRoute(
      builder: (_) => AddPhotoScreen(source: widget.source, draft: widget.draft),
    ));
    if (raw == null || !mounted) return;
    setState(() => _adding = true);
    try {
      final jpeg = await widget.prepare(raw);
      setState(() {
        _photos.add(jpeg);
        _shown = _photos.length - 1;
      });
    } on PhotoPrepException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  void _remove(int i) {
    if (_photos.length == 1) {
      _discard();
      return;
    }
    setState(() {
      _photos.removeAt(i);
      _shown = _shown.clamp(0, _photos.length - 1);
    });
  }

  Future<void> _discard() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard this scan?'),
        content: const Text(
            "The photos won't be saved and nothing is sent. You'll go back to the camera with the same equipment type."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep editing')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFC0392B)),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (yes == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final n = _photos.length;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _discard();
      },
      child: Scaffold(
        backgroundColor: CaptureColors.background,
        body: SafeArea(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: Stack(children: [
                Positioned.fill(
                  top: 60,
                  left: 24,
                  right: 24,
                  bottom: 16,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(_photos[_shown], fit: BoxFit.contain, gaplessPlayback: true),
                  ),
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  child: IconButton.filled(
                    tooltip: 'Discard scan',
                    onPressed: _discard,
                    style: IconButton.styleFrom(backgroundColor: Colors.black54),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ),
                Positioned(
                  top: 18,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(999)),
                      child: Text('Photo ${_shown + 1} of $n',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                  ),
                ),
              ]),
            ),
            if (widget.draft.isFull)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text("That's the most a scan can hold. Remove a photo to swap in a better one.",
                    style: TextStyle(fontSize: 12.5, color: CaptureColors.text)),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                '$n photo${n == 1 ? '' : 's'} in this scan${widget.draft.isFull ? ' · limit reached' : ''} · tap × to remove one',
                style: const TextStyle(fontSize: 12, color: CaptureColors.muted),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: Row(children: [
                for (var i = 0; i < n; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: _Thumb(
                      bytes: _photos[i],
                      number: i + 1,
                      selected: i == _shown,
                      onTap: () => setState(() => _shown = i),
                      onRemove: () => _remove(i),
                    ),
                  ),
                if (!widget.draft.isFull)
                  Expanded(
                    child: InkWell(
                      onTap: _adding ? null : _add,
                      child: Row(children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: const Color(0xFF1B3A5C),
                          child: _adding
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.add_a_photo_outlined, color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const Text('Add photo',
                                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white)),
                            Text('${n + 1} of ${CaptureDraft.maxPhotos} · another angle or label',
                                style: const TextStyle(fontSize: 11, color: CaptureColors.muted)),
                          ]),
                        ),
                      ]),
                    ),
                  ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _discard,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFF4A4D55), width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: const StadiumBorder(),
                    ),
                    child: const Text('Discard scan', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _adding ? null : () => widget.onNext(widget.draft),
                    style: FilledButton.styleFrom(
                      backgroundColor: _blue,
                      foregroundColor: CaptureColors.background,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: const StadiumBorder(),
                    ),
                    child: Text('Next · $n photo${n == 1 ? '' : 's'}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.bytes, required this.number, required this.selected, required this.onTap, required this.onRemove});
  final Uint8List bytes;
  final int number;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 58,
        height: 74,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(
            right: 6,
            top: 6,
            child: GestureDetector(
              onTap: onTap,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: selected ? _blue : CaptureColors.line, width: 2),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: GestureDetector(
              key: Key('remove-$number'),
              onTap: onRemove,
              child: const CircleAvatar(
                radius: 9,
                backgroundColor: Color(0xFFC0392B),
                child: Icon(Icons.close, size: 12, color: Colors.white),
              ),
            ),
          ),
          Positioned(
            bottom: -6,
            left: 0,
            right: 6,
            child: Center(
              child: Container(
                width: 18,
                height: 16,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: selected ? _blue : CaptureColors.line, borderRadius: BorderRadius.circular(8)),
                child: Text('$number',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: selected ? CaptureColors.background : Colors.white,
                    )),
              ),
            ),
          ),
        ]),
      );
}

/// Add photo N of 4 to the same scan (design 38). Pops with the raw photo.
class AddPhotoScreen extends StatelessWidget {
  const AddPhotoScreen({super.key, required this.source, required this.draft});
  final PhotoSource source;
  final CaptureDraft draft;

  @override
  Widget build(BuildContext context) {
    final next = draft.photos.length + 1;
    final taken = draft.photos.length;
    return Scaffold(
      backgroundColor: CaptureColors.background,
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            height: 56,
            child: Row(children: [
              const BackButton(color: Colors.white),
              const Expanded(
                child: Text('Add photo', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
              ),
              Container(
                margin: const EdgeInsets.only(right: 16),
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                decoration: BoxDecoration(color: const Color(0xFF1B3A5C), borderRadius: BorderRadius.circular(999)),
                child: Text('Photo $next of ${CaptureDraft.maxPhotos}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFCFE0FF))),
              ),
            ]),
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: _blue.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: _blue.withValues(alpha: 0.45)),
            ),
            child: const Text(
              'Same equipment, same scan — try another angle, a worn area up close, or a second label. Up to 4 photos.',
              style: TextStyle(fontSize: 12, height: 1.45, color: Color(0xFFD6E1FA)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(children: [
              Expanded(child: Text(draft.type.name, style: const TextStyle(fontSize: 12, color: CaptureColors.muted))),
              Text('$taken photo${taken == 1 ? '' : 's'} taken', style: const TextStyle(fontSize: 12, color: CaptureColors.muted)),
            ]),
          ),
          Expanded(child: source.viewfinder(hint: 'Align the next part of the label')),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 26),
            child: Row(children: [
              SizedBox(
                width: 72,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel', style: TextStyle(color: Color(0xFFB8BCC4), fontWeight: FontWeight.w600)),
                ),
              ),
              Expanded(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  GestureDetector(
                    key: const Key('shutter'),
                    onTap: () async {
                      try {
                        final raw = await source.shutter();
                        if (raw != null && context.mounted) Navigator.pop(context, raw);
                      } on PhotoSourceException catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
                        }
                      }
                    },
                    child: const CircleAvatar(
                      radius: 32,
                      backgroundColor: Color(0xFF2E3192),
                      child: Icon(Icons.photo_camera, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('Take photo $next',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
                ]),
              ),
              const SizedBox(width: 72),
            ]),
          ),
        ]),
      ),
    );
  }
}
