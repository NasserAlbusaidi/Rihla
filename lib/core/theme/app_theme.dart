import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'tokens/color_tokens.dart';
import 'tokens/shadow_tokens.dart';
import 'tokens/spacing_tokens.dart';

/// App theme configuration
class AppTheme {
  static const String fontFamily = 'Plus Jakarta Sans';

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColorTokens.light.scaffoldBackground,
      colorScheme: ColorScheme.light(
        primary: AppColorTokens.light.primary,
        secondary: AppColorTokens.light.textSecondary,
        surface: AppColorTokens.light.cardSurface,
        error: AppColorTokens.light.error,
        onPrimary: AppColorTokens.light.textOnPrimary,
        onSecondary: AppColorTokens.light.textOnPrimary,
        onSurface: AppColorTokens.light.textPrimary,
        onError: AppColorTokens.light.textOnPrimary,
      ),
      textTheme: _buildTextTheme(Brightness.light),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColorTokens.light.textPrimary,
        elevation: 0,
        centerTitle: true,
        scrolledUnderElevation: 0,
        titleTextStyle: GoogleFonts.getFont(
          fontFamily,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColorTokens.light.textPrimary,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColorTokens.light.cardSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColorTokens.light.primary,
          foregroundColor: AppColorTokens.light.textOnPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.getFont(
            fontFamily,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColorTokens.light.textPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          side: BorderSide(color: AppColorTokens.light.border, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.getFont(
            fontFamily,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColorTokens.light.primary,
          textStyle: GoogleFonts.getFont(
            fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColorTokens.light.inputFillWarm,
        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColorTokens.light.borderWarm, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColorTokens.light.focusBorderWarm, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColorTokens.light.error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColorTokens.light.error, width: 2),
        ),
        labelStyle: GoogleFonts.getFont(
          AppTheme.fontFamily,
          // design-token-justified: warm input label color paired with inputFillWarm; candidate for textOnWarm token in W4
          color: const Color(0xFF2C1A0E),
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: GoogleFonts.getFont(
          AppTheme.fontFamily,
          // design-token-justified: warm input hint color paired with inputFillWarm; candidate for hintOnWarm token in W4
          color: const Color(0xFFA89888),
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        floatingLabelStyle: GoogleFonts.getFont(
          AppTheme.fontFamily,
          color: AppColorTokens.light.focusBorderWarm,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColorTokens.light.primary,
        foregroundColor: AppColorTokens.light.textOnPrimary,
        elevation: 8,
        shape: const CircleBorder(),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColorTokens.light.textPrimary,
        contentTextStyle: GoogleFonts.getFont(
          fontFamily,
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColorTokens.light.inputFill,
        selectedColor: AppColorTokens.light.selectionFill,
        labelStyle: GoogleFonts.getFont(
          fontFamily,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppColorTokens.light.textSecondary,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      dividerTheme: DividerThemeData(
        color: AppColorTokens.light.border,
        thickness: 1,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColorTokens.light.cardSurface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColorTokens.light.cardSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      extensions: <ThemeExtension>[
        AppColorTokens.light,
        AppSpacingTokens.standard,
        AppShadowTokens.standard,
      ],
    );
  }

  /// Dark theme — foundation in place via AppColorTokens.dark (DARK-01).
  /// Widget-level migration from direct AppColorTokens.light to context.colors
  /// is a separate effort (DARK-02, review #17).
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColorTokens.dark.scaffoldBackground,
      colorScheme: ColorScheme.dark(
        primary: AppColorTokens.dark.primary,
        secondary: AppColorTokens.dark.textSecondary,
        surface: AppColorTokens.dark.cardSurface,
        error: AppColorTokens.dark.error,
        onPrimary: AppColorTokens.dark.textOnPrimary,
        onSecondary: AppColorTokens.dark.textOnPrimary,
        onSurface: AppColorTokens.dark.textPrimary,
        onError: AppColorTokens.dark.textOnPrimary,
      ),
      textTheme: _buildTextTheme(Brightness.dark),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColorTokens.dark.textPrimary,
        elevation: 0,
        centerTitle: true,
        scrolledUnderElevation: 0,
        titleTextStyle: GoogleFonts.getFont(
          fontFamily,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColorTokens.dark.textPrimary,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColorTokens.dark.cardSurface,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColorTokens.dark.primary,
          foregroundColor: AppColorTokens.dark.textOnPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.getFont(
            fontFamily,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColorTokens.dark.cardSurface.withValues(alpha: 0.8),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 24,
          vertical: 20,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: AppColorTokens.dark.border,
            width: 1.5,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppColorTokens.dark.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppColorTokens.dark.error, width: 1.5),
        ),
        hintStyle: GoogleFonts.getFont(
          fontFamily,
          color: AppColorTokens.dark.textMuted,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        labelStyle: GoogleFonts.getFont(
          fontFamily,
          color: AppColorTokens.dark.textSecondary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        floatingLabelStyle: GoogleFonts.getFont(
          fontFamily,
          color: AppColorTokens.dark.primary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      extensions: <ThemeExtension>[
        AppColorTokens.dark,
        AppSpacingTokens.standard,
        AppShadowTokens.dark,
      ],
    );
  }

  static TextTheme _buildTextTheme(Brightness brightness) {
    final tokens = brightness == Brightness.dark
        ? AppColorTokens.dark
        : AppColorTokens.light;
    final color = tokens.textPrimary;
    final secondaryColor = tokens.textSecondary;
    // B4 correction: bodySmall and labelSmall MUST use textSecondary (WCAG AA).
    // textMuted (#9CA3AF light / #94A3B8 dark, both <4.5:1 contrast) is
    // intentionally sub-AA per D-11 — decorative-only; never on functional roles.

    return TextTheme(
      displayLarge: GoogleFonts.getFont(
        fontFamily,
        fontSize: 44,
        fontWeight: FontWeight.w800,
        color: color,
        letterSpacing: -1.0,
      ),
      displayMedium: GoogleFonts.getFont(
        fontFamily,
        fontSize: 36,
        fontWeight: FontWeight.w700,
        color: color,
        letterSpacing: -0.5,
      ),
      displaySmall: GoogleFonts.getFont(
        fontFamily,
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: color,
        letterSpacing: -0.3,
      ),
      headlineLarge: GoogleFonts.getFont(
        fontFamily,
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: color,
        letterSpacing: -0.3,
      ),
      headlineMedium: GoogleFonts.getFont(
        fontFamily,
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: color,
      ),
      headlineSmall: GoogleFonts.getFont(
        fontFamily,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: color,
      ),
      titleLarge: GoogleFonts.getFont(
        fontFamily,
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: color,
      ),
      titleMedium: GoogleFonts.getFont(
        fontFamily,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: color,
      ),
      titleSmall: GoogleFonts.getFont(
        fontFamily,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: color,
      ),
      bodyLarge: GoogleFonts.getFont(
        fontFamily,
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: secondaryColor,
      ),
      bodyMedium: GoogleFonts.getFont(
        fontFamily,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: secondaryColor,
      ),
      bodySmall: GoogleFonts.getFont(
        fontFamily,
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: tokens.textSecondary,
      ),
      labelLarge: GoogleFonts.getFont(
        fontFamily,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: color,
      ),
      labelMedium: GoogleFonts.getFont(
        fontFamily,
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: secondaryColor,
      ),
      labelSmall: GoogleFonts.getFont(
        fontFamily,
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: tokens.textSecondary,
        letterSpacing: 0.3,
      ),
    );
  }
}
