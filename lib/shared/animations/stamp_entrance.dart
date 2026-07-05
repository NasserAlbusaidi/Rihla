import 'package:flutter/material.dart';

import '../../core/theme/tokens/domain_aliases.dart';

/// Seal-settle entrance wrapper (see `StampMotion`, `motion_tokens.dart`).
///
/// Plays once on mount: scales [child] in from `stamp.beginScale` to `1.0`
/// while unrotating from `stamp.beginTurns` to `0`, over `stamp.duration`
/// with `stamp.curve`. All values are read from `context.motion.stamp` —
/// nothing here is hardcoded.
///
/// Honors `MediaQuery.disableAnimations`: reduced motion degrades to an
/// opacity-only fade over the same duration/curve, with no scale or
/// rotation transform in the tree.
class StampEntrance extends StatefulWidget {
  const StampEntrance({super.key, required this.child});

  final Widget child;

  @override
  State<StampEntrance> createState() => _StampEntranceState();
}

class _StampEntranceState extends State<StampEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Animation<double>? _scale;
  Animation<double>? _turns;
  Animation<double>? _fade;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    final stamp = context.motion.stamp;
    _controller.duration = stamp.duration;
    final curved = CurvedAnimation(parent: _controller, curve: stamp.curve);

    if (MediaQuery.of(context).disableAnimations) {
      _fade = Tween<double>(begin: 0.0, end: 1.0).animate(curved);
    } else {
      _scale = Tween<double>(begin: stamp.beginScale, end: 1.0).animate(curved);
      _turns = Tween<double>(begin: stamp.beginTurns, end: 0.0).animate(curved);
    }
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_fade != null) {
      return FadeTransition(opacity: _fade!, child: widget.child);
    }
    return ScaleTransition(
      scale: _scale!,
      child: RotationTransition(turns: _turns!, child: widget.child),
    );
  }
}
