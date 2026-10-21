import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../widgets/auth_widgets.dart';
import 'session_controller.dart';

/// TEMPORARY landing screen after a successful sign-in. Replace with Home
/// (design 13/14) when that screen is built.
class SignedInPlaceholder extends StatelessWidget {
  const SignedInPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final me = session.me;
    return Scaffold(
      body: Column(
        children: [
          const BrandHeader(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(26),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Hello, ${me?.fullName ?? ''}', style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(me?.tenantName ?? '', style: const TextStyle(fontSize: 13.5, color: Brand.muted)),
                  const SizedBox(height: 16),
                  if (me != null)
                    for (final u in me.technicianUnits)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(u.name ?? '', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    ),
                  const Spacer(),
                  const Text('You are signed in.', style: TextStyle(fontSize: 12, color: Brand.hint)),
                  const SizedBox(height: 12),
                  PillButton(label: 'Sign out', outlined: true, onPressed: () => session.signOut()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
