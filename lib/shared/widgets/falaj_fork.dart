import 'package:flutter/material.dart';

import '../../core/theme/tokens/domain_aliases.dart';

/// The falaj fork — a single main channel that branches into 3 rounded-cap
/// rivulets fanning toward the trailing (reading-direction) edge.
///
/// This is the brand's signature device: reused by [WordmarkLogo]'s
/// underscore and (once its goldens pass) the settle-up connector. The
/// section-header tick and the [RAmount] polarity caret are the *ambient*
/// cousins — not this device.
///
/// Mirrors via [Directionality], not locale, so a UI forced to RTL
/// independently of an Arabic locale still fans correctly.
class FalajFork extends StatelessWidget {
  const FalajFork({super.key, required this.size, this.color});

  /// Box the device is laid out in. The wordmark passes `Size(type*1.6,
  /// type*0.32)`.
  final Size size;

  /// Override for the stroke color. Defaults to `context.colors.primary`
  /// (brass).
  final Color? color;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: size,
        painter: FalajForkPainter(
          color: color ?? context.colors.primary,
          textDirection: Directionality.of(context),
        ),
      );
}

/// Paints the falaj fork device (see [FalajFork]).
///
/// Geometry, normalized to the given [Size]: `u = size.width / 4.0` (a 2.5u
/// main channel + a 1.5u branch run = 4u total). Center line at
/// `cy = size.height / 2`. Branches spread `±size.height * spreadRatio`
/// around `cy`. Stroke width `size.height * 0.11`, round caps/joins.
///
/// `spreadRatio` default (0.46, tuned up from an initial 0.40) and the
/// stroke-width ratio (0.11, tuned down from an initial 0.16) were picked
/// after eyeballing the 16px/24px wordmark-box goldens — the box is very
/// flat (1.6 x 0.32 of type size), and the initial values collapsed the 3
/// branches into a single blurred blob. Thinner + wider-spread reads as 3
/// distinct rivulets at both sizes; don't revert without re-checking the
/// goldens.
class FalajForkPainter extends CustomPainter {
  const FalajForkPainter({
    required this.color,
    required this.textDirection,
    this.spreadRatio = 0.46,
  });

  final Color color;
  final TextDirection textDirection;

  /// Branch vertical spread as a fraction of `size.height`. The wordmark
  /// underscore box is flat and uses the default; a taller box (e.g. a
  /// future connector) can dial this to control the fan angle.
  final double spreadRatio;

  @override
  void paint(Canvas canvas, Size size) {
    // Mirror decision is driven by TextDirection (any RTL locale), NOT
    // locale == 'ar'.
    if (textDirection == TextDirection.rtl) {
      canvas.save();
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    final u = size.width / 4.0;
    final cy = size.height / 2;
    final sp = size.height * spreadRatio;
    final node = Offset(u * 2.5, cy); // branch point after the 2.5u rule
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.height * 0.11
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    // Main channel: start edge -> node.
    canvas.drawLine(Offset(0, cy), node, paint);
    // Three branches fanning toward the trailing (reading-direction) edge.
    canvas.drawLine(node, Offset(size.width, cy - sp), paint); // upper
    canvas.drawLine(node, Offset(size.width, cy), paint); // middle
    canvas.drawLine(node, Offset(size.width, cy + sp), paint); // lower

    if (textDirection == TextDirection.rtl) canvas.restore();
  }

  @override
  bool shouldRepaint(covariant FalajForkPainter old) =>
      old.color != color ||
      old.textDirection != textDirection ||
      old.spreadRatio != spreadRatio;
}
