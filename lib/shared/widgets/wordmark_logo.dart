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

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final ink = color ?? colors.textPrimary;
    final saffron = accentColor ?? colors.primary;

    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final wordmarkText = isArabic ? 'رحلة' : 'Rihla';

    final wordmarkStyle = isArabic
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

    return Semantics(
      label: 'Rihla',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(wordmarkText, style: wordmarkStyle),
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
