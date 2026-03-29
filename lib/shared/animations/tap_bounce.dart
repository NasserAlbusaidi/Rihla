import 'package:flutter/material.dart';

/// Shared press-scale animation wrapper.
///
/// Replaces duplicated _PressableWrapper / _PressableCard patterns.
/// D-05: 120ms duration, scale 0.97, easeInOut curve.
///
/// When [onTap] is null or [enabled] is false, returns [child] unwrapped.
/// Disposes [AnimationController] before calling super.dispose() to prevent
/// ticker leaks.
class TapBounce extends StatefulWidget {
  final VoidCallback? onTap;
  final Widget child;
  final bool enabled;

  const TapBounce({
    super.key,
    this.onTap,
    required this.child,
    this.enabled = true,
  });

  @override
  State<TapBounce> createState() => _TapBounceState();
}

class _TapBounceState extends State<TapBounce>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || widget.onTap == null) {
      return widget.child;
    }
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap?.call();
      },
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(scale: _scale, child: widget.child),
    );
  }
}
