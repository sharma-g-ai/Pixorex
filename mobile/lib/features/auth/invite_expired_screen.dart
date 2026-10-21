import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../widgets/auth_widgets.dart';

/// Invite link expired (design 04). Also used for used / cancelled / unreadable links.
/// The design has no button here; the system back gesture leaves the screen.
class InviteExpiredScreen extends StatelessWidget {
  const InviteExpiredScreen({super.key, this.problem = 'invite-expired'});

  /// `invite-expired`, `invite-used`, `invite-cancelled` or `invite-invalid`.
  final String problem;

  String get _title => switch (problem) {
        'invite-used' => 'This invite was already used',
        'invite-cancelled' => 'This invite was cancelled',
        'invite-invalid' => "This invite link isn't valid",
        _ => 'This invite link has expired',
      };

  String get _body => switch (problem) {
        'invite-used' => 'Your account may already be active. Try signing in with your mobile number or email.',
        'invite-cancelled' => "Your administrator cancelled this invite, so you can't activate your account with it.",
        'invite-invalid' => "The link couldn't be read. Open the newest invite email on this phone and tap the link again.",
        _ => "Invite links work for 24 hours. Your account isn't active yet, so you can't sign in or receive a code.",
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const BrandHeader(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(color: Brand.warnBg, borderRadius: BorderRadius.circular(20)),
                    child: const Icon(Icons.schedule, size: 32, color: Brand.warn),
                  ),
                  const SizedBox(height: 14),
                  Text(_title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 14),
                  Text(_body, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: Brand.body, height: 1.55)),
                  const SizedBox(height: 18),
                  // The design names the inviter here ("R. Kowalski · Process Manager", unit).
                  // The 409 problem from /invites/preview carries no inviter, so this stays generic
                  // until the API returns it.
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: Brand.surface, borderRadius: BorderRadius.circular(12)),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('To get a new invite, contact', style: TextStyle(fontSize: 11, color: Brand.hint)),
                        SizedBox(height: 4),
                        Text('Your administrator', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Once they send a new invite, open the newest email on this phone.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Brand.hint, height: 1.5),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
