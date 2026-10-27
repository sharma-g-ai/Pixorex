import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/auth_widgets.dart';
import '../auth/session_controller.dart';

/// Home (design 13; after a unit switch, design 25). Today's counts and latest scans
/// (design 14) come with My Scans.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, this.switchedTo});

  /// Unit name when the user just switched to it.
  final String? switchedTo;

  @override
  Widget build(BuildContext context) {
    final me = context.watch<SessionController>().me;
    if (me == null) return const SizedBox.shrink();
    final unit = me.activeUnit?.name ?? '';
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(22, MediaQuery.paddingOf(context).top + 18, 22, 20),
          decoration: const BoxDecoration(gradient: Brand.headerGradient),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Image.asset('assets/pixorex_wordmark_white.png', height: 26, semanticLabel: 'Pixorex'),
              const SizedBox(height: 18),
              Row(
                children: [
                  Initials(me.initials, size: 40, onNavy: true),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(me.shortName,
                            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(
                          'Field Technician · $unit',
                          key: const Key('home-unit'),
                          style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
            children: [
              if (switchedTo != null) ...[
                InfoBanner(
                  text: 'Now scanning for $switchedTo',
                  richBold: switchedTo,
                  icon: Icons.check_circle_outline,
                ),
                const SizedBox(height: 14),
              ],
              Text('Welcome, ${me.firstName}', style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text("Here's how a scan works:", style: TextStyle(fontSize: 13.5, color: Brand.body)),
              const SizedBox(height: 14),
              const _Step(1, 'Pick the equipment type',
                  "Choose what you're scanning — only types set up for your unit are listed."),
              const _Step(2, 'Photograph the nameplate', 'Fill the frame and hold steady. Add a second photo for worn text.'),
              const _Step(3, 'Confirm the location',
                  'Pick the shop, bin and sub-bin, then submit. We remember it for next time.'),
              const _Step(4, 'Check it in My Scans',
                  'Text is read in the background. Review anything flagged before it goes to a reviewer.'),
              const SizedBox(height: 6),
              const InfoBanner(
                text: 'No signal on the floor? Keep scanning — scans save on your phone and upload when you\'re back online.',
                icon: Icons.wifi_off,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step(this.number, this.title, this.text);
  final int number;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: Brand.info, shape: BoxShape.circle),
            child: Text('$number', style: const TextStyle(color: Brand.navy, fontWeight: FontWeight.w700, fontSize: 13)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(text, style: const TextStyle(fontSize: 12.5, color: Brand.body, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
