import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Staggered fade-in list animation.
///
/// D-04: 350ms duration, easeOutCubic, 50ms stagger, slide up 12dp + fade.
/// Honors [MediaQuery.disableAnimations] for reduced motion accessibility.
///
/// When [children] is empty or animations are disabled, wraps children in a
/// plain [Column] without any [Animate] wrappers.
class FadeInList extends StatelessWidget {
  final List<Widget> children;
  final Duration duration;
  final Duration interval;
  final Curve curve;

  const FadeInList({
    super.key,
    required this.children,
    this.duration = const Duration(milliseconds: 350),
    this.interval = const Duration(milliseconds: 50),
    this.curve = Curves.easeOutCubic,
  });

  @override
  Widget build(BuildContext context) {
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (disableAnimations || children.isEmpty) {
      return Column(children: children);
    }
    return Column(
      children: AnimateList(
        interval: interval,
        effects: [
          FadeEffect(duration: duration, curve: curve),
          MoveEffect(
            begin: const Offset(0, 12),
            end: Offset.zero,
            duration: duration,
            curve: curve,
          ),
        ],
        children: children,
      ),
    );
  }
}
