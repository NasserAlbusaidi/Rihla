import 'package:flutter/material.dart';

/// Brand typography system for the saffron travel-journal direction.
///
/// - [display] — Instrument Serif italic. Hero numerals, screen titles, the
///   "Rihla" wordmark. Use sparingly; this is the emotional voice.
/// - [sans] — Geist. Default UI text, labels, buttons.
/// - [mono] — Geist Mono with tabular figures. ALL money amounts, dates,
///   uppercase mono captions ("ACTIVE JOURNEYS", "EST. 2025").
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
  /// Use for money amounts, currency codes, dates, version strings, and
  /// any small uppercase caption ("EST. 2025", "ACTIVE JOURNEYS").
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
}
