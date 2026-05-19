import 'package:flutter/material.dart';

import '../../core/theme/tokens/domain_aliases.dart';

/// Rihla's chosen brand mark — a dashed S-curve traces a journey from a small
/// origin (filled ink dot inside a thin ring) to a saffron destination pin
/// with a cream center. Reads as "trip" without spelling it out.
///
/// Renders inside a square box of [size]. Defaults pull from the active
/// palette: foreground = ink, pin = saffron, background = paper. Pass any of
/// those to use the mark on a non-paper surface (the pin's cream center must
/// match the surface behind it).
///
/// Set [monochrome] to draw the pin in [foregroundColor] — used for Android
/// themed icons and engraved/etched contexts where a second color isn't
/// available.
class RouteMark extends StatelessWidget {
  const RouteMark({
    super.key,
    this.size = 200,
    this.foregroundColor,
    this.accentColor,
    this.backgroundColor,
    this.monochrome = false,
  });

  final double size;

  final Color? foregroundColor;

  final Color? accentColor;

  final Color? backgroundColor;

  final bool monochrome;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fg = foregroundColor ?? colors.textPrimary;
    final accent = accentColor ?? colors.primary;
    final bg = backgroundColor ?? colors.scaffoldBackground;
    final mirror = Directionality.of(context) == TextDirection.rtl;

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RouteMarkPainter(
          foreground: fg,
          pin: monochrome ? fg : accent,
          background: bg,
          mirror: mirror,
        ),
      ),
    );
  }
}

class _RouteMarkPainter extends CustomPainter {
  const _RouteMarkPainter({
    required this.foreground,
    required this.pin,
    required this.background,
    required this.mirror,
  });

  final Color foreground;
  final Color pin;
  final Color background;
  final bool mirror;

  // Coordinates below mirror the SVG viewBox in design/hifi/logo-marks.jsx
  // (200×200). The canvas is scaled uniformly to the widget's size, so all
  // proportions track automatically.
  static const double _viewBox = 200;
  static const Offset _origin = Offset(54, 146);
  static const Offset _destination = Offset(146, 60);
  static const double _pathStrokeWidth = 7;
  static const double _dotSpacing = 14;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / _viewBox;
    canvas.save();
    canvas.scale(scale);
    if (mirror) {
      canvas.translate(_viewBox, 0);
      canvas.scale(-1, 1);
    }

    canvas.drawCircle(_origin, 5.5, Paint()..color = foreground);
    canvas.drawCircle(
      _origin,
      11,
      Paint()
        ..color = foreground.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );

    final path = Path()
      ..moveTo(_origin.dx, _origin.dy)
      ..cubicTo(102, 124, 100, 84, _destination.dx, _destination.dy);

    final dotPaint = Paint()..color = foreground;
    const dotRadius = _pathStrokeWidth / 2;
    for (final metric in path.computeMetrics()) {
      for (double d = 0; d <= metric.length; d += _dotSpacing) {
        final tangent = metric.getTangentForOffset(d);
        if (tangent == null) continue;
        canvas.drawCircle(tangent.position, dotRadius, dotPaint);
      }
    }

    canvas.drawCircle(_destination, 20, Paint()..color = pin);
    canvas.drawCircle(_destination, 7, Paint()..color = background);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RouteMarkPainter old) =>
      old.foreground != foreground ||
      old.pin != pin ||
      old.background != background ||
      old.mirror != mirror;
}
