import 'package:flutter/material.dart';

import 'tokens/color_tokens.dart';
import 'tokens/motion_tokens.dart';
import 'tokens/shadow_tokens.dart';
import 'tokens/spacing_tokens.dart';
import 'tokens/typography_tokens.dart';

/// App theme configuration.
///
/// Three font families:
/// - Display (Bricolage Grotesque, upright) — display* and headlineLarge sizes
/// - Sans (Zain, dual-script) — body, title, label, button text
/// - Mono (Spline Sans Mono, tabular figures) — accessed via
///   [AppTypography.mono] when needed inline (money widgets, timestamps);
///   not part of [TextTheme].
class AppTheme {
  // Built once and cached: themes derive only from compile-time tokens (no
  // runtime/context inputs), so a `get` accessor needlessly rebuilt the full
  // ThemeData tree on every root rebuild (#622).
  static final ThemeData lightTheme = _buildLightTheme();

  static ThemeData _buildLightTheme() {
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
        titleTextStyle: AppTypography.display(
          fontSize: 22,
          color: AppColorTokens.light.textPrimary,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColorTokens.light.cardSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColorTokens.light.primary,
          foregroundColor: AppColorTokens.light.textOnPrimary,
          elevation: 0,
          minimumSize: _prominentButtonMinimumSize,
          padding: _prominentButtonPadding,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9999),
          ),
          textStyle: _buttonLabelStyle(),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColorTokens.light.primary,
          foregroundColor: AppColorTokens.light.textOnPrimary,
          minimumSize: _prominentButtonMinimumSize,
          padding: _prominentButtonPadding,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9999),
          ),
          textStyle: _buttonLabelStyle(),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColorTokens.light.textPrimary,
          minimumSize: _prominentButtonMinimumSize,
          padding: _prominentButtonPadding,
          side: BorderSide(color: AppColorTokens.light.textPrimary, width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9999),
          ),
          textStyle: _buttonLabelStyle(),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColorTokens.light.primaryDark,
          minimumSize: _textButtonMinimumSize,
          padding: _textButtonPadding,
          textStyle: _buttonLabelStyle(fontSize: 13),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColorTokens.light.inputFill,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColorTokens.light.border, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: AppColorTokens.light.focusRing,
            width: 1.5,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColorTokens.light.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColorTokens.light.error, width: 1.5),
        ),
        labelStyle: AppTypography.sans(
          color: AppColorTokens.light.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        hintStyle: AppTypography.sans(
          color: AppColorTokens.light.textMuted,
          fontSize: 15,
          fontWeight: FontWeight.w400,
        ),
        floatingLabelStyle: AppTypography.sans(
          color: AppColorTokens.light.focusRing,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColorTokens.light.primary,
        foregroundColor: AppColorTokens.light.textOnPrimary,
        elevation: 4,
        shape: const CircleBorder(),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColorTokens.light.textPrimary,
        contentTextStyle: AppTypography.sans(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.transparent,
        selectedColor: AppColorTokens.light.textPrimary,
        labelStyle: AppTypography.sans(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppColorTokens.light.textSecondary,
        ),
        secondaryLabelStyle: AppTypography.sans(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppColorTokens.light.textOnPrimary,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(9999),
          side: BorderSide(color: AppColorTokens.light.rule2, width: 1),
        ),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      dividerTheme: DividerThemeData(
        color: AppColorTokens.light.rule,
        thickness: 0.5,
        space: 1,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColorTokens.light.cardSurface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColorTokens.light.cardSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      extensions: <ThemeExtension>[
        AppColorTokens.light,
        AppSpacingTokens.standard,
        AppShadowTokens.light,
        AppMotionTokens.base,
      ],
    );
  }

  /// Dark theme — saffron-direction stub. Visual quality target deferred per
  /// plan; values come from [AppColorTokens.dark] which compile and don't
  /// produce illegible text but have not been tuned.
  static final ThemeData darkTheme = _buildDarkTheme();

  static ThemeData _buildDarkTheme() {
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
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColorTokens.dark.textPrimary,
        contentTextStyle: AppTypography.sans(
          color: AppColorTokens.dark.scaffoldBackground,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColorTokens.dark.textPrimary,
        elevation: 0,
        centerTitle: true,
        scrolledUnderElevation: 0,
        titleTextStyle: AppTypography.display(
          fontSize: 22,
          color: AppColorTokens.dark.textPrimary,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColorTokens.dark.cardSurface,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColorTokens.dark.primary,
          foregroundColor: AppColorTokens.dark.textOnPrimary,
          elevation: 0,
          minimumSize: _prominentButtonMinimumSize,
          padding: _prominentButtonPadding,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9999),
          ),
          textStyle: _buttonLabelStyle(),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColorTokens.dark.primary,
          foregroundColor: AppColorTokens.dark.textOnPrimary,
          minimumSize: _prominentButtonMinimumSize,
          padding: _prominentButtonPadding,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9999),
          ),
          textStyle: _buttonLabelStyle(),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColorTokens.dark.textPrimary,
          minimumSize: _prominentButtonMinimumSize,
          padding: _prominentButtonPadding,
          side: BorderSide(color: AppColorTokens.dark.textPrimary, width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9999),
          ),
          textStyle: _buttonLabelStyle(),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColorTokens.dark.primary,
          minimumSize: _textButtonMinimumSize,
          padding: _textButtonPadding,
          textStyle: _buttonLabelStyle(fontSize: 13),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColorTokens.dark.inputFill,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColorTokens.dark.border, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: AppColorTokens.dark.focusRing,
            width: 1.5,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColorTokens.dark.error, width: 1),
        ),
        hintStyle: AppTypography.sans(
          color: AppColorTokens.dark.textMuted,
          fontSize: 15,
          fontWeight: FontWeight.w400,
        ),
        labelStyle: AppTypography.sans(
          color: AppColorTokens.dark.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        floatingLabelStyle: AppTypography.sans(
          color: AppColorTokens.dark.focusRing,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
      ),
      extensions: <ThemeExtension>[
        AppColorTokens.dark,
        AppSpacingTokens.standard,
        AppShadowTokens.dark,
        AppMotionTokens.base,
      ],
    );
  }

  static const Size _prominentButtonMinimumSize = Size(64, 52);
  static const Size _textButtonMinimumSize = Size(48, 44);
  static const EdgeInsetsGeometry _prominentButtonPadding =
      EdgeInsetsDirectional.fromSTEB(24, 14, 24, 16);
  static const EdgeInsetsGeometry _textButtonPadding =
      EdgeInsetsDirectional.fromSTEB(12, 10, 12, 12);

  static TextStyle _buttonLabelStyle({double fontSize = 15}) {
    return AppTypography.sans(
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
      height: 1.22,
    ).copyWith(leadingDistribution: TextLeadingDistribution.even);
  }

  /// Builds the [TextTheme] for the given brightness.
  ///
  /// Display sizes use upright Bricolage Grotesque. Everything else uses Zain.
  /// All body/title/label sizes carry tabular figures so inline numbers
  /// render with consistent column widths.
  static TextTheme _buildTextTheme(Brightness brightness) {
    final tokens = brightness == Brightness.dark
        ? AppColorTokens.dark
        : AppColorTokens.light;
    final color = tokens.textPrimary;
    final secondary = tokens.textSecondary;

    return TextTheme(
      // Display — upright Bricolage Grotesque. Hero numerals, big titles.
      displayLarge: AppTypography.display(
        fontSize: 44,
        fontWeight: FontWeight.w800,
        color: color,
        letterSpacing: -1.0,
        height: 1.02,
      ),
      displayMedium: AppTypography.display(
        fontSize: 36,
        fontWeight: FontWeight.w800,
        color: color,
        letterSpacing: -0.6,
        height: 1.05,
      ),
      displaySmall: AppTypography.display(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: color,
        letterSpacing: -0.4,
        height: 1.1,
      ),
      // Headline — upright Bricolage Grotesque for the largest, then Zain.
      headlineLarge: AppTypography.display(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: color,
        letterSpacing: -0.3,
        height: 1.15,
      ),
      headlineMedium: AppTypography.sans(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: color,
        tabularNums: true,
      ),
      headlineSmall: AppTypography.sans(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: color,
        tabularNums: true,
      ),
      // Title — Zain.
      titleLarge: AppTypography.sans(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: color,
        tabularNums: true,
      ),
      titleMedium: AppTypography.sans(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: color,
        tabularNums: true,
      ),
      titleSmall: AppTypography.sans(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: color,
        tabularNums: true,
      ),
      // Body — Zain with tabular figures.
      bodyLarge: AppTypography.sans(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: secondary,
        tabularNums: true,
      ),
      bodyMedium: AppTypography.sans(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: secondary,
        tabularNums: true,
      ),
      bodySmall: AppTypography.sans(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: secondary,
        tabularNums: true,
      ),
      // Labels — Zain.
      labelLarge: AppTypography.sans(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: color,
        tabularNums: true,
      ),
      labelMedium: AppTypography.sans(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: secondary,
        tabularNums: true,
      ),
      labelSmall: AppTypography.sans(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: secondary,
        letterSpacing: 0.3,
        tabularNums: true,
      ),
    );
  }
}
