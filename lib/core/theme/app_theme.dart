import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// App color palette - Clean light theme with green accents
class AppColors {
  // Safar "Neo-Outdoor" Palette
  static const Color mint = Color(0xFF13EC92); // Neon Mint
  static const Color rose = Color(0xFFEF4444); // Red for debt/warning
  static const Color emerald = Color(0xFF10B981); // Success/Income
  static const Color amber = Color(0xFFF59E0B); // Priority Gear
  static const Color indigo = Color(0xFF6366F1); // Vault/Docs
  static const Color sky = Color(0xFF0EA5E9); // Logistics/Blue

  // Primary - Safar Mint
  static const Color primary = mint;
  static const Color primaryLight = Color(0xFFD1FAE5);
  static const Color primaryDark = Color(0xFF0BAE6B);

  // Accent colors
  static const Color accent = mint;
  static const Color accentSecondary = Color(0xFF14B8A6); // Teal
  static const Color warning = amber;
  static const Color error = rose;
  static const Color info = indigo;
  static const Color success = emerald;

  // Backgrounds - Neo-Outdoor (Light & Dark compatible)
  static const Color background = Color(0xFFEFF2F7); // Slate 100/200 blend
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceLight = Color(0xFFF1F5F9); // Slate 100
  static const Color surfaceCard = Color(0xFFFFFFFF);
  static const Color surfaceDark = Color(0xFF0F172A); // Slate 900

  // Text colors
  static const Color textPrimary = Color(0xFF0F172A); // Slate 900
  static const Color textSecondary = Color(0xFF475569); // Slate 600
  static const Color textMuted = Color(0xFF94A3B8); // Slate 400
  static const Color textOnPrimary = Color(
    0xFF000000,
  ); // Black text on neon mint

  // Borders
  static const Color border = Color(0xFFE2E8F0); // Slate 200
  static const Color borderLight = Color(0xFFF1F5F9); // Slate 100

  // Spacing scale
  static const double space4 = 4;
  static const double space8 = 8;
  static const double space12 = 12;
  static const double space16 = 16;
  static const double space20 = 20;
  static const double space24 = 24;
  static const double space32 = 32;

  // Border radius scale
  static const double radiusSmall = 12;
  static const double radiusMedium = 16;
  static const double radiusLarge = 20;

  // Elevation levels
  static List<BoxShadow> get shadowFlat => [];

  static List<BoxShadow> get shadowRaised => [
    BoxShadow(
      color: const Color(0xFF0F172A).withValues(alpha: 0.03),
      blurRadius: 10,
      offset: const Offset(0, 4),
    ),
    BoxShadow(
      color: const Color(0xFF0F172A).withValues(alpha: 0.02),
      blurRadius: 4,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> get shadowFloating => [
    BoxShadow(
      color: const Color(0xFF0F172A).withValues(alpha: 0.06),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
    BoxShadow(
      color: const Color(0xFF0F172A).withValues(alpha: 0.03),
      blurRadius: 10,
      offset: const Offset(0, 4),
    ),
  ];

  // Shadows - Refined for premium feel (delegates to elevation levels)
  static List<BoxShadow> get cardShadow => shadowRaised;

  static List<BoxShadow> get cardShadowLarge => shadowFloating;

  // Muted mint for surfaces
  static const Color mintSurface = Color(0xFFECFDF5);
  static const Color mintSurfaceDark = Color(0xFF064E3B);

  // Standard button height
  static const double buttonHeight = 52;

  // Dark header gradient
  static const LinearGradient darkHeaderGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
  );

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [mint, Color(0xFF0BAE6B)],
  );

  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFFFFF), Color(0xFFF8FAFC)],
  );

  // Glassmorphism Utilities
  static BoxDecoration glassDecoration({
    required Color color,
    double opacity = 0.1,
    double blur = 12.0,
    double borderRadius = 20.0,
    Border? border,
  }) {
    return BoxDecoration(
      color: color.withValues(alpha: opacity),
      borderRadius: BorderRadius.circular(borderRadius),
      border: border ?? Border.all(color: Colors.white.withValues(alpha: 0.2)),
    );
  }
}

/// App theme configuration
class AppTheme {
  static const String fontFamily = 'Plus Jakarta Sans';

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        secondary: AppColors.accentSecondary,
        surface: AppColors.surface,
        error: AppColors.error,
        onPrimary: AppColors.textOnPrimary,
        onSecondary: AppColors.textOnPrimary,
        onSurface: AppColors.textPrimary,
        onError: AppColors.textOnPrimary,
      ),
      textTheme: _buildTextTheme(Brightness.light),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: true,
        scrolledUnderElevation: 0,
        titleTextStyle: GoogleFonts.getFont(
          fontFamily,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppColors.radiusLarge)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textOnPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppColors.radiusMedium),
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
          foregroundColor: AppColors.textPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          side: const BorderSide(color: AppColors.border, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppColors.radiusMedium),
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
          foregroundColor: AppColors.primary,
          textStyle: GoogleFonts.getFont(
            fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceLight,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 24,
          vertical: 20,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusLarge),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusLarge),
          borderSide: const BorderSide(
            color: AppColors.borderLight,
            width: 1.5,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusLarge),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusLarge),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusLarge),
          borderSide: const BorderSide(color: AppColors.error, width: 2),
        ),
        hintStyle: GoogleFonts.getFont(
          fontFamily,
          color: AppColors.textMuted,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        labelStyle: GoogleFonts.getFont(
          fontFamily,
          color: AppColors.textSecondary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        floatingLabelStyle: GoogleFonts.getFont(
          fontFamily,
          color: AppColors.primary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textOnPrimary,
        elevation: 8,
        shape: CircleBorder(),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.textPrimary,
        contentTextStyle: GoogleFonts.getFont(
          fontFamily,
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppColors.radiusMedium)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceLight,
        selectedColor: AppColors.primaryLight,
        labelStyle: GoogleFonts.getFont(
          fontFamily,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppColors.radiusSmall)),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppColors.radiusLarge + 4)),
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF0F172A), // Slate 900
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        secondary: AppColors.accentSecondary,
        surface: Color(0xFF1E293B), // Slate 800
        error: AppColors.error,
        onPrimary: AppColors.textOnPrimary,
        onSecondary: AppColors.textOnPrimary,
        onSurface: Colors.white,
        onError: AppColors.textOnPrimary,
      ),
      textTheme: _buildTextTheme(Brightness.dark),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        scrolledUnderElevation: 0,
        titleTextStyle: GoogleFonts.getFont(
          fontFamily,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF1E293B),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppColors.radiusLarge)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textOnPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppColors.radiusMedium),
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
        fillColor: const Color(0xFF1E293B).withValues(alpha: 0.8),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 24,
          vertical: 20,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusLarge),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusLarge),
          borderSide: BorderSide(
            color: Colors.white.withValues(alpha: 0.1),
            width: 1.5,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusLarge),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusLarge),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
        hintStyle: GoogleFonts.getFont(
          fontFamily,
          color: AppColors.textMuted,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        labelStyle: GoogleFonts.getFont(
          fontFamily,
          color: Colors.white70,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        floatingLabelStyle: GoogleFonts.getFont(
          fontFamily,
          color: AppColors.primary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  static TextTheme _buildTextTheme(Brightness brightness) {
    final color = brightness == Brightness.light
        ? AppColors.textPrimary
        : Colors.white;
    final secondaryColor = brightness == Brightness.light
        ? AppColors.textSecondary
        : const Color(0xFF94A3B8); // Slate 400

    return TextTheme(
      displayLarge: GoogleFonts.getFont(
        fontFamily,
        fontSize: 48,
        fontWeight: FontWeight.w900,
        color: color,
        letterSpacing: -1.5,
      ),
      displayMedium: GoogleFonts.getFont(
        fontFamily,
        fontSize: 40,
        fontWeight: FontWeight.w800,
        color: color,
        letterSpacing: -1,
      ),
      displaySmall: GoogleFonts.getFont(
        fontFamily,
        fontSize: 32,
        fontWeight: FontWeight.w800,
        color: color,
        letterSpacing: -0.5,
      ),
      headlineLarge: GoogleFonts.getFont(
        fontFamily,
        fontSize: 28,
        fontWeight: FontWeight.w800,
        color: color,
        letterSpacing: -0.5,
      ),
      headlineMedium: GoogleFonts.getFont(
        fontFamily,
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: color,
      ),
      headlineSmall: GoogleFonts.getFont(
        fontFamily,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: color,
      ),
      titleLarge: GoogleFonts.getFont(
        fontFamily,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: color,
      ),
      titleMedium: GoogleFonts.getFont(
        fontFamily,
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: color,
      ),
      titleSmall: GoogleFonts.getFont(
        fontFamily,
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: color,
      ),
      bodyLarge: GoogleFonts.getFont(
        fontFamily,
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: secondaryColor,
      ),
      bodyMedium: GoogleFonts.getFont(
        fontFamily,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: secondaryColor,
      ),
      bodySmall: GoogleFonts.getFont(
        fontFamily,
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: AppColors.textMuted,
      ),
      labelLarge: GoogleFonts.getFont(
        fontFamily,
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: color,
      ),
      labelMedium: GoogleFonts.getFont(
        fontFamily,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: secondaryColor,
      ),
      labelSmall: GoogleFonts.getFont(
        fontFamily,
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: AppColors.textMuted,
        letterSpacing: 0.5,
      ),
    );
  }
}
