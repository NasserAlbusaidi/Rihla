import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../../core/theme/tokens/color_tokens.dart';
import '../../core/theme/tokens/domain_aliases.dart';
import '../../core/theme/tokens/typography_tokens.dart';
import '../../core/utils/formatters.dart';

/// Color tone variants for [RAmount].
///
/// `auto` (default) defers to [RAmount.sign]: positive → sage, negative → rust,
/// zero → ink. The explicit tones override regardless of value sign.
///
/// `sageText` / `rustText` are the WCAG-safe text siblings of `sage` / `rust`
/// (`colors.successText` / `colors.errorText`) — reach for them when the
/// amount renders as small text over a success/error-tinted fill, where the
/// surface tones fall below AA contrast (e.g. the roster balance chip).
///
/// `muted` renders in `colors.textSecondary` — for de-emphasized amounts on
/// secondary rows (per-event breakdowns, zero balances) where ink would
/// over-weight the row (#1201).
enum AmountTone { auto, sage, rust, ink, sageText, rustText, muted }

/// Money amount rendered in Spline Sans Mono with the wireframe's tiered sizing.
///
/// - Currency code prefix at 0.42× size, 0.78 opacity.
/// - Whole part at full [size].
/// - Decimal part at 0.55× size, 0.7 opacity.
/// - Optional sign: `+` for positive (sage), `−` (U+2212) for negative (rust).
/// - OMR shows 3 decimals (baisa); other currencies show 2.
///
/// Tabular figures are applied via [AppTypography.mono] so columns of amounts
/// align across rows (the zero is plain/un-slashed — #148).
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
    this.polarityCaret = false,
    this.tone = AmountTone.auto,
    this.weight = FontWeight.w500,
    this.dimDecimals = true,
    this.fullSizeSign = false,
    this.semanticsLabel,
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

  /// When true, a leading ▲ (positive/owed) or ▼ (negative/owe) caret encodes
  /// polarity by SHAPE so owed/owe is legible without color (colorblind-safe).
  /// HERO surfaces only — leave false on dense rows. Directionally NEUTRAL
  /// (vertical glyph) — never mirrors under RTL. No-op when the value is zero.
  /// When a caret renders, it becomes the SOLE visual polarity mark: the
  /// `+`/`−` prefix from [sign] is suppressed (two polarity marks would
  /// stack redundantly). The spoken label carries the ASCII sign only when
  /// [sign] is also true — pass `sign: true` alongside this flag so screen
  /// readers hear the polarity the caret shows (the hero site does).
  final bool polarityCaret;

  /// Explicit color override. Wins over sign-based auto-coloring.
  final AmountTone tone;

  /// Font weight applied to all glyphs. Default `w500` matches the wireframe.
  final FontWeight weight;

  /// When true (default), the decimal fragment renders at 0.7 alpha — the
  /// widget's dimmed-decimals signature. Pass false where the fraction is
  /// FUNCTIONAL small text over a tinted fill and the fade would drop it
  /// below the DESIGN.md §2 4.5:1 AA floor (e.g. the roster balance chip) —
  /// the a11y floor governs over the aesthetic signature at those sizes.
  /// Tiered sizing (whole 1.0× · decimals 0.55×) is unaffected.
  final bool dimDecimals;

  /// When true, the `+`/`−` from [sign] renders as its own span in the
  /// whole-part style — full [size], full-strength color, hugging what
  /// follows — instead of riding the 0.42×/0.78-alpha currency-code prefix.
  /// The sign is the only NON-COLOR polarity cue (owe vs owed for colorblind
  /// users), so on dense small-size chips the default prefix styling shrinks
  /// it below legibility (e.g. ~4px on the 9.5px roster chip). No-op when
  /// [sign] is false, the value is zero, or a [polarityCaret] renders
  /// (the caret is then the sole polarity mark).
  final bool fullSizeSign;

  /// Screen-reader override. When null, a default label is derived from the
  /// rendered value: unfragmented, ASCII `+`/`-` (the visual U+2212 minus is
  /// not announced by TalkBack/VoiceOver), currency code only when
  /// [showCurrency] is true — so what's heard matches what's seen.
  final String? semanticsLabel;

  /// Negative sign character — typographic minus (U+2212), not hyphen-minus.
  static const String _minus = '−';

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final v = value;
    final isPositive = v > Decimal.zero;
    final isNegative = v < Decimal.zero;

    final color = _resolveColor(colors, isPositive, isNegative);
    final decimalPlaces = AppFormatters.currencyConfig[currency]?.decimals ?? 2;

    final abs = v.abs();
    final formatted = abs.toStringAsFixed(decimalPlaces);
    final dotIndex = formatted.indexOf('.');
    final wholePart = dotIndex == -1
        ? formatted
        : formatted.substring(0, dotIndex);
    final decimalPart = dotIndex == -1 ? '' : formatted.substring(dotIndex);

    // #900 comp 6: a rendered caret is the sole visual polarity mark — the
    // +/− prefix is suppressed so the two marks don't stack redundantly.
    final showCaret = polarityCaret && (isPositive || isNegative);
    final prefix = showCaret
        ? ''
        : (sign ? (isPositive ? '+' : (isNegative ? _minus : '')) : '');

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
      color: dimDecimals ? color.withValues(alpha: 0.7) : color,
      height: 1.0,
    );
    final caretStyle = AppTypography.mono(
      fontSize: size * 0.42,
      fontWeight: weight,
      color: color,
      height: 1.0,
    );

    // A full-size sign leaves the code span and becomes its own whole-style
    // span below; the code span then carries only the currency (if shown).
    final signIsFullSize = fullSizeSign && prefix.isNotEmpty;
    final codePrefix = signIsFullSize ? '' : prefix;
    final codeText = showCurrency
        ? '$codePrefix$currency '
        : (codePrefix.isEmpty ? '' : '$codePrefix ');

    // Spoken label keeps the ASCII sign regardless of caret suppression above
    // — semanticsLabel replaces the visual text for screen readers, so the
    // caret glyph is never announced and the sign must still be spoken.
    final asciiPrefix = sign
        ? (isPositive ? '+' : (isNegative ? '-' : ''))
        : '';
    final spokenLabel =
        semanticsLabel ??
        '$asciiPrefix${showCurrency ? '$currency ' : ''}$formatted';

    return Text.rich(
      TextSpan(
        children: [
          if (showCaret)
            TextSpan(text: '${isPositive ? '▲' : '▼'} ', style: caretStyle),
          if (signIsFullSize) TextSpan(text: prefix, style: wholeStyle),
          if (codeText.isNotEmpty) TextSpan(text: codeText, style: codeStyle),
          TextSpan(text: wholePart, style: wholeStyle),
          if (decimalPart.isNotEmpty)
            TextSpan(text: decimalPart, style: decimalStyle),
        ],
      ),
      semanticsLabel: spokenLabel,
      textDirection: TextDirection.ltr,
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
      AmountTone.sageText => colors.successText,
      AmountTone.rustText => colors.errorText,
      AmountTone.muted => colors.textSecondary,
      AmountTone.auto when sign && isPositive => colors.success,
      AmountTone.auto when sign && isNegative => colors.error,
      AmountTone.auto => colors.textPrimary,
    };
  }
}
