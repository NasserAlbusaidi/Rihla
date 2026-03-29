import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Staggered grid reveal animation.
///
/// D-06: 400ms duration, 60ms stagger, easeOutQuart curve.
/// Honors [MediaQuery.disableAnimations] for reduced motion accessibility.
///
/// When [children] is empty or animations are disabled, wraps children in a
/// plain [Wrap] without any [Animate] wrappers.
class StaggeredGrid extends StatelessWidget {
  final List<Widget> children;
  final Duration duration;
  final Duration interval;
  final Curve curve;

  const StaggeredGrid({
    super.key,
    required this.children,
    this.duration = const Duration(milliseconds: 400),
    this.interval = const Duration(milliseconds: 60),
    this.curve = Curves.easeOutQuart,
  });

  @override
  Widget build(BuildContext context) {
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (disableAnimations || children.isEmpty) {
      return Wrap(children: children);
    }
    return Wrap(
      children: AnimateList(
        interval: interval,
        effects: [
          FadeEffect(duration: duration, curve: curve),
          ScaleEffect(
            begin: const Offset(0.95, 0.95),
            end: const Offset(1.0, 1.0),
            duration: duration,
            curve: curve,
          ),
        ],
        children: children,
      ),
    );
  }
}
