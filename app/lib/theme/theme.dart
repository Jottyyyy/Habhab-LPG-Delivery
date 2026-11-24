import 'package:flutter/material.dart';

/// Brand colours, sampled from the Habhab LPG Trading logo.
abstract final class C {
  static const navy = Color(0xFF003F6A);
  static const navyDark = Color(0xFF002B49);
  static const flame = Color(0xFFE25730);
  static const flameDark = Color(0xFFCC4833);
  static const gold = Color(0xFFC1A363);
  static const cream = Color(0xFFF6F4E7);
  static const bg = Color(0xFFF8F6EE);
  static const ink = Color(0xFF1B2430);
  static const muted = Color(0xFF5E6875);
  static const line = Color(0xFFE6E1CF);
  static const green = Color(0xFF1E7D4F);
  static const greenTint = Color(0xFFE3F3EA);
  static const amber = Color(0xFFB8661A);
  static const amberTint = Color(0xFFFBEEDC);
  static const red = Color(0xFFC0392B);
  static const redTint = Color(0xFFFBE4E1);
  static const navyTint = Color(0xFFE2ECF4);
}

ThemeData appTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: C.navy,
    primary: C.navy,
    onPrimary: Colors.white,
    secondary: C.flame,
    onSecondary: Colors.white,
    surface: Colors.white,
    error: C.red,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, scaffoldBackgroundColor: C.bg);
  final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: C.navy,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: Colors.white),
    ),
    textTheme: base.textTheme.apply(bodyColor: C.ink, displayColor: C.ink),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: C.line)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: C.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: C.line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: C.navy, width: 1.6)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: rounded,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: rounded,
        foregroundColor: C.navy,
        side: const BorderSide(color: C.navy),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: C.navyTint,
      labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    dividerTheme: const DividerThemeData(color: C.line, space: 1),
  );
}
