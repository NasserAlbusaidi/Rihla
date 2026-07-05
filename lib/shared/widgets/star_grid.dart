import 'package:flutter/material.dart';

import '../../core/theme/tokens/star_grid_tokens.dart';

/// A deterministic grid of tiny dots — the "night star-grid" motif for
/// dark hero surfaces (spec §Signature system).
///
/// No randomness/jitter: a regular grid keeps this painter's output
/// pixel-stable across runs, which matters for goldens.
class StarGridPainter extends CustomPainter {
  const StarGridPainter({required this.color, this.opacity = kStarGridOpacity});

  final Color color;
  final double opacity;

  static const double _cell = 22;
  static const double _r = 0.6;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color.withValues(alpha: opacity);
    for (double y = _cell / 2; y < size.height; y += _cell) {
      for (double x = _cell / 2; x < size.width; x += _cell) {
        canvas.drawCircle(Offset(x, y), _r, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant StarGridPainter old) =>
      old.color != color || old.opacity != opacity;
}
