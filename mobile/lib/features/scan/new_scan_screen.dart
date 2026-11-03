import 'package:flutter/material.dart';

import '../../core/api_exception.dart';
import '../../core/theme.dart';
import 'capture_models.dart';
import 'scan_repository.dart';

/// Colours of the dark capture screens (design 30-32).
class CaptureColors {
  const CaptureColors._();
  static const background = Color(0xFF0D0D10);
  static const sheet = Color(0xFF151517);
  static const line = Color(0xFF3A3D45);
  static const muted = Color(0xFF9AA1AB);
  static const text = Color(0xFFE5E6EA);
  static const selectBorder = Color(0xFF7FA3EA);
}

/// New scan (design 30-32): pick the equipment type first, then capture.
/// The camera itself plugs in through [viewfinder] and the button callbacks.
class NewScanScreen extends StatefulWidget {
  const NewScanScreen({
    super.key,
    required this.scans,
    required this.buId,
    required this.unitName,
    this.initialType,
    this.onShutter,
    this.onGallery,
    this.onCamera,
    this.onMyScans,
    this.viewfinder,
  });
  final ScanRepository scans;
  final String buId;
  final String unitName;

  /// Kept from the last scan (design 46): "change it if the next item is different".
  final EquipmentType? initialType;
  final ValueChanged<EquipmentType>? onShutter;
  final ValueChanged<EquipmentType>? onGallery;

  /// The phone's own camera app; the shutter is the in-app camera.
  final ValueChanged<EquipmentType>? onCamera;
  final VoidCallback? onMyScans;
  final Widget? viewfinder;

  @override
  State<NewScanScreen> createState() => _NewScanScreenState();
}

class _NewScanScreenState extends State<NewScanScreen> {
  List<EquipmentType>? _types;
  String? _error;
  EquipmentType? _type;

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final types = await widget.scans.equipmentTypes(widget.buId);
      if (mounted) setState(() => _types = types);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _pickType() async {
    final types = _types;
    if (types == null) return;
    final picked = await showModalBottomSheet<EquipmentType>(
      context: context,
      backgroundColor: CaptureColors.sheet,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _TypeSheet(types: types, selected: _type),
    );
    if (picked != null) setState(() => _type = picked);
  }

  @override
  Widget build(BuildContext context) {
    final type = _type;
    return Scaffold(
      backgroundColor: CaptureColors.background,
      body: SafeArea(
        child: DefaultTextStyle.merge(
          style: const TextStyle(color: Colors.white),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              height: 56,
              child: Row(children: [
                const BackButton(color: Colors.white),
                const Expanded(child: Text('New scan', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
                if (widget.onMyScans != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: OutlinedButton.icon(
                      onPressed: widget.onMyScans,
                      icon: const Icon(Icons.list_alt, size: 16),
                      label: const Text('My Scans'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: CaptureColors.line),
                        shape: const StadiumBorder(),
                      ),
                    ),
                  ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Text.rich(TextSpan(style: const TextStyle(fontSize: 11.5, color: CaptureColors.muted), children: [
                const TextSpan(text: 'Scanning for '),
                TextSpan(text: widget.unitName, style: const TextStyle(fontWeight: FontWeight.w700, color: CaptureColors.text)),
                const TextSpan(text: ' · types set up for this unit'),
              ])),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('Equipment type', style: TextStyle(fontSize: 11, color: CaptureColors.muted)),
                const SizedBox(height: 6),
                _typeSelector(),
              ]),
            ),
            Expanded(
              child: widget.viewfinder ??
                  _StaticViewfinder(type == null ? 'Choose the equipment type to start' : 'Align the nameplate within the frame'),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Capture tips', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                SizedBox(height: 4),
                Text('• Fill the frame · hold steady · tilt to reduce glare\n• Add a second angle for engraved or worn text',
                    style: TextStyle(fontSize: 11.5, height: 1.5, color: CaptureColors.muted)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _RoundButton(
                  icon: Icons.photo_library_outlined,
                  label: 'Gallery',
                  onTap: type == null || widget.onGallery == null ? null : () => widget.onGallery!(type),
                ),
                _Shutter(onTap: type == null || widget.onShutter == null ? null : () => widget.onShutter!(type)),
                _RoundButton(
                  icon: Icons.photo_camera_outlined,
                  label: 'Camera',
                  onTap: type == null || widget.onCamera == null ? null : () => widget.onCamera!(type),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _typeSelector() {
    if (_error != null) {
      return Row(children: [
        Expanded(child: Text(_error!, style: const TextStyle(fontSize: 12.5, color: Color(0xFFF2A49B)))),
        TextButton(onPressed: _load, child: const Text('Retry')),
      ]);
    }
    final types = _types;
    if (types != null && types.isEmpty) {
      return const Text('No equipment types are set up for this unit yet. Ask your BU Admin to add one.',
          style: TextStyle(fontSize: 12.5, color: CaptureColors.muted));
    }
    return InkWell(
      onTap: types == null ? null : _pickType,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: CaptureColors.selectBorder, width: 1.5),
        ),
        child: Row(children: [
          Expanded(
            child: Text(
              _type?.name ?? 'Select equipment type',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: _type == null ? FontWeight.w400 : FontWeight.w600,
                color: _type == null ? CaptureColors.muted : Colors.white,
              ),
            ),
          ),
          if (types == null)
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          else
            const Icon(Icons.expand_more, color: CaptureColors.muted),
        ]),
      ),
    );
  }
}

class _TypeSheet extends StatelessWidget {
  const _TypeSheet({required this.types, this.selected});
  final List<EquipmentType> types;
  final EquipmentType? selected;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 10, 20, 22), children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: CaptureColors.line, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const Text('Equipment type', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
            const Padding(
              padding: EdgeInsets.only(top: 2, bottom: 10),
              child: Text('Types set up for your business unit', style: TextStyle(fontSize: 11.5, color: CaptureColors.muted)),
            ),
            for (final t in types)
              Material(
                color: t.typeId == selected?.typeId ? Brand.navy.withValues(alpha: 0.3) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => Navigator.pop(context, t),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 13),
                    child: Text(t.name,
                        style: TextStyle(
                          fontSize: 14,
                          color: t.typeId == selected?.typeId ? Colors.white : CaptureColors.text,
                          fontWeight: t.typeId == selected?.typeId ? FontWeight.w600 : FontWeight.w400,
                        )),
                  ),
                ),
              ),
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text("Don't see the type you need? Ask your BU Admin to add it for this unit.",
                  style: TextStyle(fontSize: 11, height: 1.45, color: Brand.muted)),
            ),
          ]),
        ),
      );
}

class _StaticViewfinder extends StatelessWidget {
  const _StaticViewfinder(this.hint);
  final String hint;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(center: Alignment(-0.2, -0.4), colors: [Color(0xFF22262E), CaptureColors.background]),
        ),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
            child: Text(hint, style: const TextStyle(fontSize: 12, color: Colors.white)),
          ),
        ),
      );
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: onTap == null ? 0.4 : 1,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: CaptureColors.line, width: 1.5)),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontSize: 11, color: CaptureColors.muted)),
          ]),
        ),
      );
}

class _Shutter extends StatelessWidget {
  const _Shutter({required this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Take photo',
        child: GestureDetector(
          key: const Key('shutter'),
          onTap: onTap,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: onTap == null ? CaptureColors.line : Colors.white,
                border: onTap == null ? null : Border.all(color: CaptureColors.line, width: 4),
              ),
            ),
            const SizedBox(height: 6),
            Text(onTap == null ? 'Pick a type first' : 'Take photo',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: CaptureColors.muted)),
          ]),
        ),
      );
}
