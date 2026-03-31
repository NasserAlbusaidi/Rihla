import 'package:flutter/material.dart';

/// Applies a subtle paper grain texture overlay to its child.
///
/// Uses a tileable 32x32 noise PNG repeated across the surface.
/// Default opacity is 3.5% (hero cards/scaffold). Use 2% for dark headers (per D-11).
///
/// Example usage:
/// ```dart
/// GrainOverlay(
///   child: Container(color: Colors.white, child: content),
/// )
/// ```
class GrainOverlay extends StatelessWidget {
  final Widget child;

  /// Opacity of the grain texture (0.0–1.0). Default 3.5%.
  final double opacity;

  const GrainOverlay({
    super.key,
    required this.child,
    this.opacity = 0.035,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        image: DecorationImage(
          image: const AssetImage('assets/textures/grain.png'),
          repeat: ImageRepeat.repeat,
          opacity: opacity,
          fit: BoxFit.none,
          alignment: Alignment.topLeft,
        ),
      ),
      child: child,
    );
  }
}
