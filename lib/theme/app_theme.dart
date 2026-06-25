import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Design token system for AP Companion.
///
/// Palette built around a deep-space dark with teal accent — evokes
/// industrial power monitoring without generic "dashboard" vibes.
/// Single signature element: the battery ring uses a gradient arc that
/// shifts from amber → teal as charge increases, encoding state in color
/// rather than just percentage text.
abstract final class AppColors {
  // ── Backgrounds ────────────────────────────────────────────────────────────
  static const background = Color(0xFF0D0F14);
  static const surface = Color(0xFF161A23);
  static const surfaceElevated = Color(0xFF1C2130);
  static const surfaceHighlight = Color(0xFF222840);

  // ── Borders ────────────────────────────────────────────────────────────────
  static const border = Color(0xFF252B3B);
  static const borderSubtle = Color(0xFF1E2435);
  static const borderFocus = Color(0xFF3DD6C0);

  // ── Brand / Accent ─────────────────────────────────────────────────────────
  static const teal = Color(0xFF3DD6C0);
  static const tealDim = Color(0xFF1E8A7A);
  static const tealSurface = Color(0xFF0D2A26);

  // ── Semantic ───────────────────────────────────────────────────────────────
  static const success = Color(0xFF34C78A);
  static const successSurface = Color(0xFF0D2A1E);
  static const warning = Color(0xFFE8A838);
  static const warningSurface = Color(0xFF2A1E0D);
  static const error = Color(0xFFE85C5C);
  static const errorSurface = Color(0xFF2A0D0D);
  static const info = Color(0xFF5B9CF6);
  static const infoSurface = Color(0xFF0D1A2A);

  // ── Text ───────────────────────────────────────────────────────────────────
  static const textPrimary = Color(0xFFEDF0F7);
  static const textSecondary = Color(0xFF8892AA);
  static const textTertiary = Color(0xFF545F7A);
  static const textDisabled = Color(0xFF3A4258);

  // ── Outlet colors ──────────────────────────────────────────────────────────
  static const usb = Color(0xFF5B9CF6);
  static const usbSurface = Color(0xFF0D1A2A);
  static const ac = Color(0xFFE8A838);
  static const acSurface = Color(0xFF2A1E0D);
  static const dc = Color(0xFF34C78A);
  static const dcSurface = Color(0xFF0D2A1E);

  // ── Battery gradient stops ─────────────────────────────────────────────────
  static const batteryLow = Color(0xFFE85C5C);
  static const batteryMid = Color(0xFFE8A838);
  static const batteryHigh = Color(0xFF3DD6C0);

  static Color batteryColor(int level) {
    if (level <= 20) return batteryLow;
    if (level <= 50) return batteryMid;
    return batteryHigh;
  }
}

abstract final class AppRadius {
  static const double xs = 6;
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 18;
  static const double xl = 24;
  static const double full = 999;

  static BorderRadius get xsBR => BorderRadius.circular(xs);
  static BorderRadius get smBR => BorderRadius.circular(sm);
  static BorderRadius get mdBR => BorderRadius.circular(md);
  static BorderRadius get lgBR => BorderRadius.circular(lg);
  static BorderRadius get xlBR => BorderRadius.circular(xl);
}

abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
}

abstract final class AppTypography {
  static const _base = TextStyle(
    fontFamily: 'Inter',
    color: AppColors.textPrimary,
    letterSpacing: -0.1,
  );

  static final displayLg = _base.copyWith(fontSize: 36, fontWeight: FontWeight.w700, letterSpacing: -1.0);
  static final displayMd = _base.copyWith(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.6);
  static final displaySm = _base.copyWith(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.4);

  static final headingLg = _base.copyWith(fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: -0.3);
  static final headingMd = _base.copyWith(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.2);
  static final headingSm = _base.copyWith(fontSize: 14, fontWeight: FontWeight.w600);

  static final bodyLg = _base.copyWith(fontSize: 15, fontWeight: FontWeight.w400);
  static final bodyMd = _base.copyWith(fontSize: 13, fontWeight: FontWeight.w400, color: AppColors.textSecondary);
  static final bodySm = _base.copyWith(fontSize: 12, fontWeight: FontWeight.w400, color: AppColors.textSecondary);

  static final labelLg = _base.copyWith(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.6);
  static final labelMd = _base.copyWith(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: AppColors.textSecondary);
  static final labelSm = _base.copyWith(fontSize: 10, fontWeight: FontWeight.w500, letterSpacing: 0.4, color: AppColors.textTertiary);

  static final mono = _base.copyWith(fontFamily: 'JetBrainsMono', fontSize: 13);
  static final monoLg = _base.copyWith(fontFamily: 'JetBrainsMono', fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -1.0);
}

abstract final class AppTheme {
  static ThemeData get dark {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,

      // Bind typography tokens to global Material 3 widgets
      textTheme: TextTheme(
        displayLarge: AppTypography.displayLg,
        displayMedium: AppTypography.displayMd,
        displaySmall: AppTypography.displaySm,
        headlineLarge: AppTypography.headingLg,
        headlineMedium: AppTypography.headingMd,
        headlineSmall: AppTypography.headingSm,
        bodyLarge: AppTypography.bodyLg,
        bodyMedium: AppTypography.bodyMd,
        bodySmall: AppTypography.bodySm,
        labelLarge: AppTypography.labelLg,
        labelMedium: AppTypography.labelMd,
        labelSmall: AppTypography.labelSm,
      ),

      // Alignment with M3 Tone-Based Surface roles (Android 15 & 16 compatible)
      colorScheme: const ColorScheme.dark(
        primary: AppColors.teal,
        onPrimary: AppColors.background,
        primaryContainer: AppColors.tealSurface,
        onPrimaryContainer: AppColors.teal,
        secondary: AppColors.teal,
        onSecondary: AppColors.background,
        
        // New Surface Tones (replacing deprecated elevation-based overlays)
        surface: AppColors.background,
        surfaceDim: AppColors.background,
        surfaceBright: AppColors.surfaceElevated,
        surfaceContainerLowest: AppColors.background,
        surfaceContainerLow: AppColors.surface,
        surfaceContainer: AppColors.surfaceElevated,
        surfaceContainerHigh: AppColors.surfaceHighlight,
        surfaceContainerHighest: AppColors.border,
        
        onSurface: AppColors.textPrimary,
        onSurfaceVariant: AppColors.textSecondary,
        outline: AppColors.border,
        outlineVariant: AppColors.borderSubtle,
        
        error: AppColors.error,
        onError: AppColors.background,
        errorContainer: AppColors.errorSurface,
        onErrorContainer: AppColors.error,
      ),

      // Explicit styles for native Top AppBars
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: AppColors.textPrimary),
        actionsIconTheme: IconThemeData(color: AppColors.textPrimary),
        centerTitle: false,
      ),

      cardTheme: CardThemeData(
        color: AppColors.surface, // Matches surfaceContainerLow
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.lgBR,
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),

      // Explicit style for standard Dialog components
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surfaceElevated, // Matches surfaceContainer
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.lgBR,
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
      ),

      // Explicit style for Bottom Sheets
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surfaceElevated,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
        ),
        clipBehavior: Clip.antiAliasWithSaveLayer,
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.background;
          if (states.contains(WidgetState.disabled)) return AppColors.textDisabled;
          return AppColors.textTertiary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.teal;
          if (states.contains(WidgetState.disabled)) return AppColors.surface;
          return AppColors.surfaceElevated;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.transparent;
          return AppColors.border;
        }),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface, // Using surfaceContainerLow for contrasting fields
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        labelStyle: AppTypography.bodyMd,
        hintStyle: AppTypography.bodyMd.copyWith(color: AppColors.textDisabled),
        border: OutlineInputBorder(
          borderRadius: AppRadius.mdBR,
          borderSide: const BorderSide(color: AppColors.border, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdBR,
          borderSide: const BorderSide(color: AppColors.border, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdBR,
          borderSide: const BorderSide(color: AppColors.borderFocus, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdBR,
          borderSide: const BorderSide(color: AppColors.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdBR,
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface, 
        indicatorColor: AppColors.tealSurface,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: AppColors.teal, size: 22);
          }
          return const IconThemeData(color: AppColors.textTertiary, size: 22);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppTypography.labelMd.copyWith(color: AppColors.teal);
          }
          return AppTypography.labelMd;
        }),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
      ),

      // M3 Prominent Actions Theme
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.teal,
          foregroundColor: AppColors.background,
          textStyle: AppTypography.headingSm,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.mdBR),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          elevation: 0,
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.teal,
          foregroundColor: AppColors.background,
          textStyle: AppTypography.headingSm,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.mdBR),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          elevation: 0,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.teal,
          side: const BorderSide(color: AppColors.border, width: 1),
          textStyle: AppTypography.headingSm,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.mdBR),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceElevated,
        contentTextStyle: AppTypography.bodyLg,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdBR),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
      ),

      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 0,
      ),
      
      iconTheme: const IconThemeData(color: AppColors.textSecondary, size: 20),
    );
  }

  /// Time picker theme matching app design.
  static ThemeData get timePickerTheme {
    return ThemeData.dark().copyWith(
      colorScheme: const ColorScheme.dark(
        primary: AppColors.teal,
        onPrimary: AppColors.background,
        surface: AppColors.surfaceElevated,
        onSurface: AppColors.textPrimary,
      ),
    );
  }

  /// Configures transparent system overlay for edge-to-edge drawing.
  static void applySystemOverlay() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      
      // Kept transparent so the OS permits window-underneath drawing
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
    ));
  }
}