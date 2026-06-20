import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const background = Color(0xFF121212);
  static const surface = Color(0xFF1E1E1E);
  static const border = Color(0xFF2E2E2E);
  static const borderSubtle = Color(0xFF2C2C2C);
  static const track = Color(0xFF333333);
}

class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    return ThemeData.dark().copyWith(
      scaffoldBackgroundColor: AppColors.background,
      cardColor: AppColors.surface,
      colorScheme: const ColorScheme.dark(
        primary: Colors.teal,
        secondary: Colors.tealAccent,
        surface: AppColors.surface,
      ),
    );
  }

  /// Theme override used for the native time picker dialog so it matches
  /// the rest of the app instead of falling back to the default theme.
  static ThemeData get timePickerTheme {
    return ThemeData.dark().copyWith(
      colorScheme: const ColorScheme.dark(
        primary: Colors.teal,
        onPrimary: Colors.white,
        surface: AppColors.surface,
        onSurface: Colors.white,
      ),
    );
  }
}