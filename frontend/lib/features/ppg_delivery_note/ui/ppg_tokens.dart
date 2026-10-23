import 'package:flutter/material.dart';

import '../../../branding/app_brand.dart';

/// Visual tokens for the PPG receiving flow. Brand colours come from
/// [AppBrand]; everything else is defined once here so screens never use raw
/// colour or size literals.
abstract final class PpgColors {
  static const navy = AppBrand.navy;
  static const blue = AppBrand.blue;
  static const link = Color(0xFF1D4ED8);
  static const ground = Color(0xFFF1F4F9);
  static const surface = Colors.white;
  static const line = Color(0xFFD9E0EA);
  static const divider = Color(0xFFE3E9F2);
  static const control = Color(0xFFC3CEDD);
  static const textSecondary = Color(0xFF475569);
  static const textMuted = Color(0xFF5B6B82);
  static const disabledFill = Color(0xFFE3E9F2);

  static const onNavyMuted = Color(0xFFB8C4D9);
  static const stepDone = Color(0xFF4ADE80);
  static const stepDoneText = Color(0xFFC7F0D4);
  static const stepCurrent = Color(0xFF60A5FA);
  static const stepTodo = Color(0xFF2A3D63);
  static const stepTodoText = Color(0xFF93A3BF);
  static const stepTapFill = Color(0x0FFFFFFF);
  static const stepCurrentFill = Color(0x3860A5FA);
  static const stepCurrentOutline = Color(0x8C93C5FD);
  static const progressDone = Color(0xFF16A34A);

  static const camera = Color(0xFF121A2B);
  static const cameraChrome = Color(0xBF0B1F44);
  static const destructive = Color(0xFFB91C1C);
}

/// Semantic status tones. Every tone is always paired with a word.
enum PpgTone { neutral, info, success, warning, danger }

extension PpgToneColors on PpgTone {
  Color get foreground => switch (this) {
    PpgTone.neutral => const Color(0xFF334155),
    PpgTone.info => const Color(0xFF1E40AF),
    PpgTone.success => const Color(0xFF166534),
    PpgTone.warning => const Color(0xFF92400E),
    PpgTone.danger => const Color(0xFF991B1B),
  };

  Color get background => switch (this) {
    PpgTone.neutral => const Color(0xFFEEF2F7),
    PpgTone.info => const Color(0xFFDBEAFE),
    PpgTone.success => const Color(0xFFDCFCE7),
    PpgTone.warning => const Color(0xFFFEF3C7),
    PpgTone.danger => const Color(0xFFFEE2E2),
  };

  Color get border => switch (this) {
    PpgTone.neutral => PpgColors.line,
    PpgTone.info => const Color(0xFFBFD3F6),
    PpgTone.success => const Color(0xFFB7E4C7),
    PpgTone.warning => const Color(0xFFF3D9A4),
    PpgTone.danger => const Color(0xFFF5C2C2),
  };
}

abstract final class PpgRadii {
  static const small = 8.0;
  static const medium = 12.0;
  static const large = 16.0;
  static const sheet = 20.0;
}

abstract final class PpgSpace {
  static const xs = 4.0;
  static const s = 8.0;
  static const m = 12.0;
  static const l = 16.0;
  static const xl = 24.0;
}

abstract final class PpgSizes {
  static const touch = 44.0;
  static const button = 52.0;
  static const counter = 64.0;
}

/// Article and delivery numbers use a monospaced face so leading zeros and
/// look-alike digits stay distinct.
abstract final class PpgText {
  static const _tabular = [FontFeature.tabularFigures()];
  static const monoFamily = 'monospace';

  static const sectionLabel = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.8,
    color: PpgColors.textMuted,
  );

  static TextStyle mono({
    double size = 15,
    FontWeight weight = FontWeight.w600,
    Color? color,
  }) => TextStyle(
    fontFamily: monoFamily,
    fontSize: size,
    fontWeight: weight,
    color: color,
    fontFeatures: _tabular,
  );

  static TextStyle figures({
    double size = 15,
    FontWeight weight = FontWeight.w700,
    Color? color,
  }) => TextStyle(
    fontSize: size,
    fontWeight: weight,
    color: color,
    fontFeatures: _tabular,
  );
}

ThemeData buildPpgTheme(ThemeData base) {
  final scheme = ColorScheme.fromSeed(
    seedColor: PpgColors.blue,
    primary: PpgColors.blue,
    onPrimary: Colors.white,
    surface: PpgColors.surface,
    onSurface: PpgColors.navy,
    error: PpgTone.danger.foreground,
  );
  final rounded = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(PpgRadii.medium),
  );
  const buttonText = TextStyle(fontSize: 16, fontWeight: FontWeight.w600);
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: PpgColors.ground,
    dividerColor: PpgColors.divider,
    textTheme: base.textTheme.apply(
      bodyColor: PpgColors.navy,
      displayColor: PpgColors.navy,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: PpgColors.navy,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(PpgSizes.touch, PpgSizes.button),
        shape: rounded,
        textStyle: buttonText,
        backgroundColor: PpgColors.blue,
        foregroundColor: Colors.white,
        disabledBackgroundColor: PpgColors.disabledFill,
        disabledForegroundColor: PpgColors.textSecondary,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(PpgSizes.touch, 48),
        shape: rounded,
        side: const BorderSide(color: PpgColors.control),
        foregroundColor: PpgColors.navy,
        backgroundColor: Colors.white,
        textStyle: buttonText.copyWith(fontSize: 15),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(PpgSizes.touch, PpgSizes.touch),
        foregroundColor: PpgColors.link,
        textStyle: buttonText.copyWith(fontSize: 15),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(PpgRadii.medium),
        borderSide: const BorderSide(color: PpgColors.control),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(PpgRadii.medium),
        borderSide: const BorderSide(color: PpgColors.control),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(PpgRadii.medium),
        borderSide: const BorderSide(color: PpgColors.blue, width: 2),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PpgRadii.large),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      showDragHandle: true,
      dragHandleColor: PpgColors.control,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(PpgRadii.sheet),
        ),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
  );
}
