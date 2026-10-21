import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';

/// Launch screen (design 02) while stored tokens are checked.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: splashSystemBars,
      child: Scaffold(
        backgroundColor: Brand.navyDeep,
        body: Container(
          decoration: const BoxDecoration(gradient: Brand.headerGradient),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: const [
                          BoxShadow(color: Color(0x59000000), blurRadius: 40, offset: Offset(0, 16)),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: Image.asset('assets/pixorex_icon.png', width: 96, height: 96, semanticLabel: 'Pixorex'),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Image.asset('assets/pixorex_wordmark_white.png', height: 34, excludeFromSemantics: true),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 48 + MediaQuery.paddingOf(context).bottom,
                child: const Column(
                  children: [
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: Colors.white,
                        backgroundColor: Color(0x40FFFFFF),
                      ),
                    ),
                    SizedBox(height: 10),
                    Text('Loading…', style: TextStyle(fontSize: 11.5, color: Color(0x99FFFFFF))),
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
