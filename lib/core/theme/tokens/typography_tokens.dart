import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Brand typography system for the saffron travel-journal direction.
///
/// - [display] — Instrument Serif italic. Hero numerals, screen titles, the
///   "Rihla" wordmark. Use sparingly; this is the emotional voice.
///   Locale-visible text goes through [displayOf] instead (#841).
/// - [sans] — Geist. Default UI text, labels, buttons.
/// - [mono] — Geist Mono with tabular figures. Numerals/codes only: money
///   amounts, currency codes, invite codes, dates-as-figures. Translatable
///   captions go through [caption] instead (#841).
///
/// Use the helper methods (`AppTypography.display(...)`) when you need a
/// one-off style outside the [TextTheme] hierarchy. For ambient text styles,
/// pull from `Theme.of(context).textTheme.*` — those are wired to the same
/// families in `AppTheme._buildTextTheme`.
class AppTypography {
  const AppTypography._();

  /// Geist family name. Matches the `family:` declared in `pubspec.yaml`
  /// `flutter: fonts:` for the bundled `Geist[wght].ttf` variable face.
  static const String sansFamily = 'Geist';

  /// Instrument Serif family name (italic by default in display helpers).
  static const String displayFamily = 'Instrument Serif';

  /// Geist Mono family name.
  static const String monoFamily = 'Geist Mono';

  /// Arabic display family name. Backed by a tiny Reem Kufi subset containing
  /// only the current Arabic wordmark glyphs (#636).
  static const String arabicDisplayFamily = 'Rihla Arabic Display';

  /// Tabular-numeric feature set — keeps money columns aligned.
  ///
  /// Deliberately omits `slashedZero()`: a slashed `0` reads as Ø/null on
  /// monetary figures and invite codes (#148).
  static const List<FontFeature> tabularNumberFeatures = [
    FontFeature.tabularFigures(),
  ];

  /// Italic display style — Instrument Serif.
  ///
  /// Italic is the default because the wireframe uses italic display
  /// almost exclusively. Pass `italic: false` to opt out.
  static TextStyle display({
    required double fontSize,
    Color? color,
    FontWeight fontWeight = FontWeight.w400,
    double? letterSpacing,
    double? height,
    bool italic = true,
  }) {
    return TextStyle(
      fontFamily: displayFamily,
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  /// Arabic display style — Reem Kufi wordmark subset.
  ///
  /// Mirrors [display] for Latin script. Reem Kufi has no italic style and
  /// Arabic typography doesn't mark emphasis this way, so this helper
  /// intentionally does NOT expose an `italic` parameter.
  ///
  /// Use only for the Arabic wordmark. The bundled font is intentionally
  /// subsetted and is not a general Arabic UI text face.
  static TextStyle arabicDisplay({
    required double fontSize,
    Color? color,
    FontWeight fontWeight = FontWeight.w400,
    double? letterSpacing,
    double? height,
  }) {
    return TextStyle(
      fontFamily: arabicDisplayFamily,
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  /// Sans style — Geist. Body, labels, buttons.
  static TextStyle sans({
    required double fontSize,
    Color? color,
    FontWeight fontWeight = FontWeight.w400,
    double? letterSpacing,
    double? height,
    bool tabularNums = false,
  }) {
    return TextStyle(
      fontFamily: sansFamily,
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
      fontFeatures: tabularNums ? tabularNumberFeatures : null,
    );
  }

  /// Mono style — Geist Mono with tabular figures (plain, un-slashed zero).
  ///
  /// Numerals and codes ONLY: money amounts, currency codes, invite codes,
  /// dates-as-figures, version strings. Never translatable copy — that's
  /// [caption] — and never user free-text — that's [sans].
  static TextStyle mono({
    required double fontSize,
    Color? color,
    FontWeight fontWeight = FontWeight.w500,
    double? letterSpacing,
    double? height,
  }) {
    return TextStyle(
      fontFamily: monoFamily,
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
      fontFeatures: tabularNumberFeatures,
    );
  }

  /// Small caps-style caption for TRANSLATABLE copy (section headers,
  /// eyebrows, action links, meta lines). Latin: the classic mono recipe,
  /// unchanged. Arabic: mono tracking visually disconnects joined letters,
  /// so the caption re-expresses its role as sans w700, letterSpacing 0,
  /// floor 11px. Callers keep `.toUpperCase()` — it is a no-op on Arabic
  /// script.
  static TextStyle caption(
    BuildContext context, {
    required double fontSize,
    Color? color,
    FontWeight fontWeight = FontWeight.w500,
    double? letterSpacing,
    double? height,
  }) {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    if (!isArabic) {
      return mono(
        fontSize: fontSize,
        color: color,
        fontWeight: fontWeight,
        letterSpacing: letterSpacing,
        height: height,
      );
    }
    return sans(
      fontSize: math.max(fontSize, 11),
      color: color,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
      height: height,
    );
  }

  /// Locale-aware display. Latin: italic Instrument Serif (unchanged).
  /// Arabic: Instrument Serif carries no Arabic glyphs — the renderer falls
  /// back to the system face; upright w500 replaces the synthetic slant.
  static TextStyle displayOf(
    BuildContext context, {
    required double fontSize,
    Color? color,
    FontWeight? fontWeight,
    double? letterSpacing,
    double? height,
    bool italic = true,
  }) {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    if (!isArabic) {
      return display(
        fontSize: fontSize,
        color: color,
        fontWeight: fontWeight ?? FontWeight.w400,
        letterSpacing: letterSpacing,
        height: height,
        italic: italic,
      );
    }
    return display(
      fontSize: fontSize,
      color: color,
      fontWeight: fontWeight ?? FontWeight.w500,
      letterSpacing: 0,
      height: height,
      italic: false,
    );
  }
}
