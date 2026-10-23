import 'package:flutter/material.dart';

/// Pixorex's supplied brand assets and palette.
class AppBrand {
  AppBrand._();

  static const name = 'Pixorex';
  static const description =
      'Pixorex industrial asset and delivery note digitization.';
  static const icon = 'assets/app_icon.png';
  static const wordmarkOnDark = 'assets/branding/pixorex-wordmark-dark.png';
  static const wordmarkOnLight = 'assets/branding/pixorex-wordmark-light.png';

  static const navy = Color(0xFF0B1F44);
  static const navyOverlay = Color(0xDD0B1F44);
  static const blue = Color(0xFF2563EB);
  static const accentBlue = Color(0xFF3B82F6);
  static const lightBlue = Color(0xFF60A5FA);
  static const neutral = Color(0xFF94A3B8);
  static const background = Color(0xFFE2E8F0);
  static const headerGradient = [navy, Color(0xFF0F2A5C), Color(0xFF081733)];
}
