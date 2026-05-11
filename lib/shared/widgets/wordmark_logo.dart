import 'package:flutter/material.dart';

import '../../core/theme/tokens/domain_aliases.dart';
import '../../core/theme/tokens/typography_tokens.dart';

/// "Rihla" wordmark in italic Instrument Serif with a hand-drawn saffron
/// underline flourish — the app's signature mark.
///
/// Use at small sizes for top bars and at large sizes for splash/onboarding.
/// The flourish width tracks 1.6× the type [size] so the proportion stays
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

  /// Override for the flourish color. Defaults to saffron.
  final Color? accentColor;

  /// Whether to render the underline. Set false for inline usage.
  final bool flourish;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final ink = color ?? colors.textPrimary;
    final saffron = accentColor ?? colors.primary;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Rihla',
          style: AppTypography.display(
            fontSize: size,
            color: ink,
            letterSpacing: size > 60 ? -3 : -1.5,
            height: 1.0,
          ),
        ),
        if (flourish)
          Padding(
            padding: EdgeInsets.only(top: size * 0.08),
            child: CustomPaint(
              size: Size(size * 1.6, size * 0.32),
              painter: _FlourishPainter(color: saffron),
            ),
          ),
      ],
    );
  }
}

/// Hand-drawn saffron underline arc — single curve, no arrow head.
class _FlourishPainter extends CustomPainter {
  const _FlourishPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.height * 0.18
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final midY = size.height * 0.55;
    final path = Path()
      ..moveTo(w * 0.025, midY * 1.15)
      ..cubicTo(w * 0.225, midY * 0.55, w * 0.450, midY * 1.35, w * 0.650, midY * 0.8)
      ..cubicTo(w * 0.800, midY * 0.55, w * 0.950, midY * 0.55, w * 0.975, midY * 1.0);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _FlourishPainter old) => old.color != color;
}
