import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Round avatar with the person's initials.
class Initials extends StatelessWidget {
  const Initials(this.text, {super.key, this.size = 44, this.onNavy = false});
  final String text;
  final double size;

  /// White on the navy header; navy on white elsewhere.
  final bool onNavy;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: onNavy ? const Color(0x33FFFFFF) : Brand.info,
        shape: BoxShape.circle,
      ),
      child: Text(
        text,
        style: TextStyle(
          color: onNavy ? Colors.white : Brand.navy,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.36,
        ),
      ),
    );
  }
}

/// Bottom sheet body in the design's style: grab handle, title, content, actions.
class SheetFrame extends StatelessWidget {
  const SheetFrame({super.key, required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(color: Brand.line, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// Shows [child] as a rounded bottom sheet over a dimmed screen.
Future<T?> showAppSheet<T>(BuildContext context, Widget child) => showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      barrierColor: const Color(0x8014161A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => child,
    );

/// Small grey heading over a group of cards.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 18),
      child: Text(text, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Brand.muted)),
    );
  }
}

/// White rounded card on the grey page.
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Brand.lineSoft),
      ),
      child: child,
    );
  }
}
