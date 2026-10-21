import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Tokens taken from the design canvas (Pixorex Technician App).
class Brand {
  const Brand._();

  static const navy = Color(0xFF2E3192);
  static const navyDeep = Color(0xFF1B1E5E);
  static const navyBright = Color(0xFF3A3DB0);

  static const ink = Color(0xFF14161A);
  static const body = Color(0xFF5B6672);
  static const muted = Color(0xFF6B7280);
  static const hint = Color(0xFF9AA1AB);

  static const line = Color(0xFFD7DCE1);
  static const lineSoft = Color(0xFFE5E9EC);
  static const surface = Color(0xFFF4F5F8);
  static const surfaceAlt = Color(0xFFF7F8FA);
  static const segment = Color(0xFFF1F3F5);
  static const info = Color(0xFFEAF0FB);

  static const error = Color(0xFFC0392B);
  static const errorBg = Color(0xFFFDECEA);
  static const errorInk = Color(0xFF8B291D);
  static const warnBg = Color(0xFFFCEFD9);
  static const warn = Color(0xFFD9670F);

  static const headerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [navyBright, navyDeep],
  );
}

/// IBM Plex Sans, bundled under assets/fonts (pubspec.yaml).
const String kFontFamily = 'IBMPlexSans';

/// White status-bar icons over the navy header, white navigation bar below.
const brandSystemBars = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.light, // Android
  statusBarBrightness: Brightness.dark, // iOS
  systemNavigationBarColor: Colors.white,
  systemNavigationBarIconBrightness: Brightness.dark,
);

/// Launch screen: navy all the way down.
const splashSystemBars = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.light,
  statusBarBrightness: Brightness.dark,
  systemNavigationBarColor: Brand.navyDeep,
  systemNavigationBarIconBrightness: Brightness.light,
);

ThemeData buildTheme() {
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Brand.navy,
      primary: Brand.navy,
      error: Brand.error,
      surface: Colors.white,
    ),
    fontFamily: kFontFamily,
    scaffoldBackgroundColor: Colors.white,
    // apply() must set the family too: the stock text theme carries Roboto.
    textTheme: ThemeData.light()
        .textTheme
        .apply(fontFamily: kFontFamily, bodyColor: Brand.ink, displayColor: Brand.ink),
  );
}
