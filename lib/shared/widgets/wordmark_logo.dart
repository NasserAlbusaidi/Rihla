import 'package:flutter/material.dart';

import '../../core/theme/tokens/domain_aliases.dart';
import '../../core/theme/tokens/typography_tokens.dart';
import 'falaj_fork.dart';

/// "Rihla" wordmark in upright Bricolage Grotesque with a brass Falaj
/// fork underscore — the app's signature mark.
///
/// Use at small sizes for top bars and at large sizes for splash/onboarding.
/// The underscore width tracks 1.6× the type [size] so the proportion stays
/// constant across scales.
class WordmarkLogo extends StatelessWidget {
  const WordmarkLogo({
    super.key,
    this.size = 22,
    this.color,
    this.accentColor,
    this.flourish = true,
  });

  /// Type size for "Rihla".
  final double size;

  /// Override for the wordmark color. Defaults to ink.
  final Color? color;

  /// Override for the fork underscore color. Defaults to saffron.
  final Color? accentColor;

  /// Whether to render the underscore. Set false for inline usage.
  final bool flourish;

  static String _textFor(bool isArabic) => isArabic ? 'رحلة' : 'Rihla';

  static TextStyle _styleFor(bool isArabic, double size, Color ink) =>
      isArabic
      ? AppTypography.arabicDisplay(
          fontSize: size,
          color: ink,
          letterSpacing: size > 60 ? -3 : -1.5,
          height: 1.0,
        )
      : AppTypography.display(
          fontSize: size,
          color: ink,
          letterSpacing: size > 60 ? -3 : -1.5,
          height: 1.0,
        );

  /// Laid-out width of the mark's text for the current locale, so layouts
  /// flanking a centered wordmark can budget against its REAL footprint
  /// (test fonts render much wider than production glyphs — a constant
  /// guard is wrong in one of the two worlds, #1064).
  static double measuredTextWidth(BuildContext context, {double size = 22}) {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final painter = TextPainter(
      text: TextSpan(
        text: _textFor(isArabic),
        // design-token-justified: measurement-only style — the color never
        // paints, it only satisfies the style constructor.
        style: _styleFor(isArabic, size, const Color(0xFF000000)),
      ),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final ink = color ?? colors.textPrimary;
    final saffron = accentColor ?? colors.primary;

    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final wordmarkText = _textFor(isArabic);
    final wordmarkStyle = _styleFor(isArabic, size, ink);

    return Semantics(
      label: 'Rihla',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Brand mark, not informational text: it keeps its designed size
          // regardless of the OS text scale, so the #1064 header budgets
          // (set-name chip vs centered wordmark) hold at the 1.5x policy max.
          Text(
            wordmarkText,
            style: wordmarkStyle,
            textScaler: TextScaler.noScaling,
          ),
          if (flourish)
            Padding(
              padding: EdgeInsets.only(top: size * 0.08),
              child: FalajFork(
                size: Size(size * 1.6, size * 0.32),
                color: saffron,
              ),
            ),
        ],
      ),
    );
  }
}
