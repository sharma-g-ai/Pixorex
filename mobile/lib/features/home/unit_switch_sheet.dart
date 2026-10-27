import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/theme.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/auth_widgets.dart';
import '../auth/me.dart';
import '../auth/session_controller.dart';

/// Choose a unit (design 19), confirm (design 20), switch with no new sign-in (contract 1.2).
/// Returns the new unit's name, or null when cancelled.
Future<String?> showUnitSwitch(BuildContext context) => showAppSheet<String>(context, const _UnitSwitchSheet());

/// "PPG Plant 07 — Industrial" -> "PPG Plant 07" (button label, design 19).
String shortUnitName(String name) => name.split(' — ').first.trim();

class _UnitSwitchSheet extends StatefulWidget {
  const _UnitSwitchSheet();

  @override
  State<_UnitSwitchSheet> createState() => _UnitSwitchSheetState();
}

class _UnitSwitchSheetState extends State<_UnitSwitchSheet> {
  String? _chosen;
  bool _confirming = false;
  bool _busy = false;
  String? _error;

  Future<void> _switch(SessionController session, UnitRole unit) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await session.switchUnit(unit.buId!);
      if (mounted) Navigator.pop(context, unit.name ?? '');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _confirming = false;
        _chosen = null;
        _error = e.isForbidden ? "You're no longer assigned to that unit." : e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final me = session.me;
    if (me == null) return const SizedBox.shrink();
    final units = me.technicianUnits;
    final chosen = units.where((u) => u.buId == _chosen).firstOrNull;

    if (_confirming && chosen != null) {
      final name = chosen.name ?? '';
      return SheetFrame(
        title: 'Switch to $name?',
        children: [
          _Bullet('New scans will be saved to ', name, '.'),
          const _Bullet('You stay signed in — no code needed.'),
          const SizedBox(height: 18),
          PillButton(label: 'Switch', loading: _busy, onPressed: () => _switch(session, chosen)),
          const SizedBox(height: 8),
          PillButton(
            label: 'Cancel',
            outlined: true,
            onPressed: _busy ? null : () => setState(() => _confirming = false),
          ),
        ],
      );
    }

    return SheetFrame(
      title: 'Switch business unit',
      children: [
        const Text("Only units you're assigned to are shown.", style: TextStyle(fontSize: 13, color: Brand.body)),
        const SizedBox(height: 14),
        for (final u in units) ...[
          _UnitRow(
            unit: u,
            current: u.buId == me.activeBuId,
            selected: u.buId == _chosen,
            onTap: u.buId == me.activeBuId ? null : () => setState(() => _chosen = u.buId),
          ),
          const SizedBox(height: 10),
        ],
        if (_error != null) ...[
          InfoBanner(text: _error!, icon: Icons.error_outline, error: true),
          const SizedBox(height: 10),
        ],
        const InfoBanner(text: 'No new sign-in needed.'),
        const SizedBox(height: 18),
        PillButton(
          label: chosen == null ? 'Switch' : 'Switch to ${shortUnitName(chosen.name ?? '')}',
          onPressed: chosen == null ? null : () => setState(() => _confirming = true),
        ),
        const SizedBox(height: 8),
        PillButton(label: 'Cancel', outlined: true, onPressed: () => Navigator.pop(context)),
      ],
    );
  }
}

class _UnitRow extends StatelessWidget {
  const _UnitRow({required this.unit, required this.current, required this.selected, this.onTap});
  final UnitRole unit;
  final bool current;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final subtitle = current
        ? 'Signed in now'
        : (unit.assignedByName == null ? null : 'Added by ${unit.assignedByName}');
    return Material(
      color: current ? Brand.surface : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: selected ? Brand.navy : Brand.lineSoft, width: selected ? 2 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Icon(
                current ? Icons.check_circle : (selected ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                size: 20,
                color: current ? Brand.hint : (selected ? Brand.navy : Brand.line),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      unit.name ?? '',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: current ? Brand.hint : Brand.ink,
                      ),
                    ),
                    if (subtitle != null)
                      Text(subtitle, style: const TextStyle(fontSize: 11.5, color: Brand.hint)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.before, [this.bold, this.after = '']);
  final String before;
  final String? bold;
  final String after;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text.rich(
        TextSpan(
          style: const TextStyle(fontSize: 13.5, color: Brand.body, height: 1.45),
          children: [
            TextSpan(text: '•  $before'),
            if (bold != null) TextSpan(text: bold, style: const TextStyle(fontWeight: FontWeight.w700, color: Brand.ink)),
            TextSpan(text: after),
          ],
        ),
      ),
    );
  }
}
