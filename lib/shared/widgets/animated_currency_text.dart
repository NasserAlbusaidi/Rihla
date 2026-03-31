import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:safar/core/theme/tokens/color_tokens.dart';
import 'package:safar/core/utils/formatters.dart';

/// Animated currency text that smoothly interpolates between Decimal values.
///
/// The number lerps frame-by-frame using [TweenAnimationBuilder] with a
/// 600ms easeOutCubic curve (per D-13). The text color snaps based on the
/// animated value sign: positive=successText, negative=errorText,
/// zero=textSecondary (per D-15).
///
/// Value tracking: [didUpdateWidget] records the previous value so each
/// animation starts from the old number, not from zero.
///
/// Example usage:
/// ```dart
/// AnimatedCurrencyText(
///   value: balance,
///   currency: 'OMR',
///   style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
/// )
/// ```
class AnimatedCurrencyText extends StatefulWidget {
  /// The target value to display and animate toward.
  final Decimal value;

  /// The ISO 4217 currency code (e.g. 'OMR', 'USD').
  final String currency;

  /// Optional text style. Color will be overridden by sign-based token.
  final TextStyle? style;

  /// Animation duration. Defaults to 600ms (per D-13).
  final Duration duration;

  const AnimatedCurrencyText({
    super.key,
    required this.value,
    required this.currency,
    this.style,
    this.duration = const Duration(milliseconds: 600),
  });

  @override
  State<AnimatedCurrencyText> createState() => _AnimatedCurrencyTextState();
}

class _AnimatedCurrencyTextState extends State<AnimatedCurrencyText> {
  /// The previous value used as the animation start point.
  late double _previousValue;

  @override
  void initState() {
    super.initState();
    _previousValue = widget.value.toDouble();
  }

  @override
  void didUpdateWidget(AnimatedCurrencyText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _previousValue = oldWidget.value.toDouble();
    }
  }

  /// Resolve sign-based color from the animated double value.
  Color _colorForValue(double value) {
    final tokens = AppColorTokens.light;
    return switch (value.compareTo(0.0)) {
      > 0 => tokens.successText,
      < 0 => tokens.errorText,
      _ => tokens.textSecondary,
    };
  }

  /// Format an animated double as a currency string.
  ///
  /// Takes the absolute value and formats to the correct decimal places.
  /// The sign (negative) is preserved by passing the raw double to _colorForValue.
  String _formatValue(double value, String currency) {
    // Use 3 decimal places as safe default; AppFormatters.formatCurrency
    // picks the right precision per currency.
    final absDecimal = Decimal.parse(value.abs().toStringAsFixed(3));
    return AppFormatters.formatCurrency(absDecimal, currency);
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(
        begin: _previousValue,
        end: widget.value.toDouble(),
      ),
      duration: widget.duration,
      curve: Curves.easeOutCubic,
      builder: (context, animatedValue, _) {
        final color = _colorForValue(animatedValue);
        final formattedText = _formatValue(animatedValue, widget.currency);
        final effectiveStyle =
            (widget.style ?? const TextStyle()).copyWith(color: color);

        return Text(formattedText, style: effectiveStyle);
      },
    );
  }
}
