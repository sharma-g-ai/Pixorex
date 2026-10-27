import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/phone.dart';
import '../../core/theme.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/auth_widgets.dart';
import '../auth/session_controller.dart';
import 'unit_switch_sheet.dart';

/// Profile (design 15): who is signed in, the active unit and the switch, sign-out.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, required this.onSwitched});

  /// Called with the unit name after a successful switch.
  final ValueChanged<String> onSwitched;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final me = session.me;
    if (me == null) return const SizedBox.shrink();
    final active = me.activeUnit;
    final others = me.technicianUnits.where((u) => u.buId != active?.buId).toList();

    return ColoredBox(
      color: Brand.surface,
      child: Column(
        children: [
          Container(
            height: 56 + MediaQuery.paddingOf(context).top,
            padding: EdgeInsets.only(left: 20, top: MediaQuery.paddingOf(context).top),
            alignment: Alignment.centerLeft,
            color: Brand.navy,
            child: const Text('Profile', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                AppCard(
                  child: Row(
                    children: [
                      Initials(me.initials, size: 52),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(me.fullName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(me.email, style: const TextStyle(fontSize: 12.5, color: Brand.body)),
                            const SizedBox(height: 6),
                            const _Chip('Field Technician'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (me.phoneNumber != null) ...[
                  const SectionLabel('Mobile number'),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(maskPhone(me.phoneNumber!), style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        const Text('Used to sign in', style: TextStyle(fontSize: 12, color: Brand.muted)),
                      ],
                    ),
                  ),
                ],
                const SectionLabel('Business unit'),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Signed in to', style: TextStyle(fontSize: 12, color: Brand.muted)),
                                const SizedBox(height: 2),
                                Text(active?.name ?? '',
                                    key: const Key('profile-unit'),
                                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                          const _Chip('Active', green: true),
                        ],
                      ),
                      if (others.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text('Also assigned: ${others.map((u) => u.name).join(', ')}',
                            style: const TextStyle(fontSize: 12.5, color: Brand.body)),
                        const SizedBox(height: 4),
                        TextButton(
                          style: TextButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: Brand.navy),
                          onPressed: () async {
                            final name = await showUnitSwitch(context);
                            if (name != null) onSwitched(name);
                          },
                          child: const Text('Switch business unit', style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 8, 4, 0),
                  child: Text(
                    'Switch any time — no new sign-in needed. Next time you sign in, the app opens in the unit you used last.',
                    style: TextStyle(fontSize: 12, color: Brand.muted, height: 1.45),
                  ),
                ),
                const SizedBox(height: 28),
                PillButton(
                  label: 'Sign out',
                  outlined: true,
                  onPressed: () => _confirmSignOut(context, session, active?.name),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Design 29.
  Future<void> _confirmSignOut(BuildContext context, SessionController session, String? unit) async {
    final ok = await showAppSheet<bool>(
      context,
      Builder(
        builder: (sheet) => SheetFrame(
          title: unit == null ? 'Sign out?' : 'Sign out of $unit?',
          children: [
            const Text(
              "You'll go back to the sign-in screen. Next time you sign in, the app opens in the last unit you used.",
              style: TextStyle(fontSize: 13, color: Brand.body, height: 1.5),
            ),
            const SizedBox(height: 18),
            PillButton(label: 'Sign out', onPressed: () => Navigator.pop(sheet, true)),
            const SizedBox(height: 8),
            PillButton(label: 'Cancel', outlined: true, onPressed: () => Navigator.pop(sheet, false)),
          ],
        ),
      ),
    );
    if (ok == true) await session.signOut();
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text, {this.green = false});
  final String text;
  final bool green;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: green ? const Color(0xFFE6F4EA) : Brand.info,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: green ? const Color(0xFF1E7B3A) : Brand.navy,
        ),
      ),
    );
  }
}
