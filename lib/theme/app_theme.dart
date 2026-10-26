import 'package:flutter/material.dart';

abstract final class BellColors {
  static const background = Color(0xFF0A1020);
  static const surface = Color(0xFF131D32);
  static const surfaceRaised = Color(0xFF1A2942);
  static const surfaceSoft = Color(0xFF202F4B);
  static const gold = Color(0xFFFFC857);
  static const mint = Color(0xFF65E0B5);
  static const sky = Color(0xFF76B7FF);
  static const rose = Color(0xFFFF8295);
  static const lavender = Color(0xFFB69BFF);
  static const textMuted = Color(0xFF9AA8C0);
}

ThemeData buildBellTheme() => ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: BellColors.background,
      colorScheme: ColorScheme.fromSeed(seedColor: BellColors.gold, brightness: Brightness.dark, surface: BellColors.surface),
      appBarTheme: const AppBarTheme(backgroundColor: BellColors.background, foregroundColor: Colors.white, elevation: 0, centerTitle: false),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: BellColors.surfaceRaised,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(17), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(17), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(17), borderSide: const BorderSide(color: BellColors.gold, width: 1.3)),
        labelStyle: const TextStyle(color: BellColors.textMuted),
      ),
      snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, backgroundColor: BellColors.surfaceSoft, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: BellColors.surface,
        indicatorColor: BellColors.gold.withOpacity(.17),
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(fontSize: 11, fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500, color: states.contains(WidgetState.selected) ? BellColors.gold : BellColors.textMuted)),
      ),
    );
