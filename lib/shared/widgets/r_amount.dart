import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../../core/theme/tokens/color_tokens.dart';
import '../../core/theme/tokens/domain_aliases.dart';
import '../../core/theme/tokens/typography_tokens.dart';

/// Color tone variants for [RAmount].
///
/// `auto` (default) defers to [RAmount.sign]: positive → sage, negative → rust,
/// zero → ink. The explicit tones override regardless of value sign.
enum AmountTone { auto, sage, rust, ink }

/// Money amount rendered in Geist Mono with the wireframe's tiered sizing.
///
/// - Currency code prefix at 0.42× size, 0.78 opacity.
/// - Whole part at full [size].
/// - Decimal part at 0.55× size, 0.7 opacity.
/// - Optional sign: `+` for positive (sage), `−` (U+2212) for negative (rust).
/// - OMR shows 3 decimals (baisa); other currencies show 2.
///
/// Tabular figures and slashed zero are applied via [AppTypography.mono] so
/// columns of amounts align across rows.
///
/// ```dart
/// RAmount(
///   value: Decimal.parse('184.200'),
///   currency: 'OMR',
///   size: 44,
///   sign: true,
///   tone: AmountTone.sage,
/// )
/// ```
class RAmount extends StatelessWidget {
  const RAmount({
    super.key,
    required this.value,
    this.currency = 'OMR',
    this.showCurrency = true,
    this.size = 16,
    this.sign = false,
    this.tone = AmountTone.auto,
    this.weight = FontWeight.w500,
  });

  /// Amount to render. [Decimal] avoids float drift on baisa boundaries.
  final Decimal value;

  /// ISO 4217 currency code. OMR triggers 3-decimal rendering even when
  /// [showCurrency] is false — the code controls precision, not just display.
  final String currency;

  /// When false, the small currency-code prefix is omitted. Useful when the
  /// amount sits next to a separate currency label (e.g. the home hero card).
  /// Decimal precision still follows [currency].
  final bool showCurrency;

  /// Base font size — the whole-number part renders at this size; currency
  /// code and decimal fragments are scaled down from it.
  final double size;

  /// When true, prefix `+` for positive and `−` for negative; color tracks
  /// sign (sage / rust). When false, the absolute value is rendered with
  /// neutral [tone].
  final bool sign;

  /// Explicit color override. Wins over sign-based auto-coloring.
  final AmountTone tone;

  /// Font weight applied to all glyphs. Default `w500` matches the wireframe.
  final FontWeight weight;

  /// Negative sign character — typographic minus (U+2212), not hyphen-minus.
  static const String _minus = '−';

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final v = value;
    final isPositive = v > Decimal.zero;
    final isNegative = v < Decimal.zero;

    final color = _resolveColor(colors, isPositive, isNegative);
    final decimalPlaces = currency == 'OMR' ? 3 : 2;

    final abs = v.abs();
    final formatted = abs.toStringAsFixed(decimalPlaces);
    final dotIndex = formatted.indexOf('.');
    final wholePart = dotIndex == -1 ? formatted : formatted.substring(0, dotIndex);
    final decimalPart = dotIndex == -1 ? '' : formatted.substring(dotIndex);

    final prefix = sign
        ? (isPositive ? '+' : (isNegative ? _minus : ''))
        : '';

    final codeStyle = AppTypography.mono(
      fontSize: size * 0.42,
      fontWeight: weight,
      color: color.withValues(alpha: 0.78),
      letterSpacing: 0.5,
    );
    final wholeStyle = AppTypography.mono(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: -0.2,
      height: 1.0,
    );
    final decimalStyle = AppTypography.mono(
      fontSize: size * 0.55,
      fontWeight: weight,
      color: color.withValues(alpha: 0.7),
      height: 1.0,
    );

    final codeText = showCurrency
        ? '$prefix$currency '
        : (prefix.isEmpty ? '' : '$prefix ');

    return Text.rich(
      TextSpan(
        children: [
          if (codeText.isNotEmpty) TextSpan(text: codeText, style: codeStyle),
          TextSpan(text: wholePart, style: wholeStyle),
          if (decimalPart.isNotEmpty) TextSpan(text: decimalPart, style: decimalStyle),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.visible,
      softWrap: false,
    );
  }

  Color _resolveColor(AppColorTokens colors, bool isPositive, bool isNegative) {
    return switch (tone) {
      AmountTone.sage => colors.success,
      AmountTone.rust => colors.error,
      AmountTone.ink => colors.textPrimary,
      AmountTone.auto when sign && isPositive => colors.success,
      AmountTone.auto when sign && isNegative => colors.error,
      AmountTone.auto => colors.textPrimary,
    };
  }
}
