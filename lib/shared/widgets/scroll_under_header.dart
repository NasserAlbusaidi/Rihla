import 'package:flutter/material.dart';

import '../../core/theme/tokens/domain_aliases.dart';

/// #1011: a shared "fixed header over a scroll view" layout that draws a
/// [AppColorTokens.rule] hairline under the header once content scrolls
/// beneath it — so a fixed header no longer shares the scaffold background
/// seamlessly with the content (the "half-visible row floats under the title"
/// artifact).
///
/// Material 3's `scrolledUnderElevation` is unavailable here: these screens use
/// custom top-bar widgets placed as `Column` siblings above the scroll view
/// (not the `Scaffold.appBar` slot), and the app theme sets
/// `scrolledUnderElevation: 0` globally. So this generalizes the
/// `NotificationListener<ScrollNotification>` idiom already proven in
/// `EventCommandCenter._onScroll`.
///
/// A hairline (`colors.rule`) is used rather than an elevation shadow: the
/// #807 flat-vs-raised discipline reserves raised elevation as the cue for
/// *tappable* surfaces, and a non-actionable header separator should not borrow
/// that semantic.
///
/// Usage: pass the fixed [header] and the scrollable [child] (unwrapped — this
/// widget `Expanded`s it):
/// ```dart
/// ScrollUnderHeader(
///   header: const _TopBar(),
///   child: SingleChildScrollView(...),
/// )
/// ```
class ScrollUnderHeader extends StatefulWidget {
  const ScrollUnderHeader({
    super.key,
    required this.header,
    required this.child,
    this.threshold = 4,
    this.hairlineKey,
  });

  /// The fixed header rendered above the scroll view. The hairline is drawn
  /// directly beneath it.
  final Widget header;

  /// The scrollable content (e.g. [SingleChildScrollView], [ListView],
  /// [CustomScrollView]). Rendered inside an [Expanded].
  final Widget child;

  /// Scroll offset (px) past which the hairline appears. Small by default so
  /// the separator shows as soon as content moves under the header.
  final double threshold;

  /// Optional key for the hairline layer (used by tests / callers that want to
  /// target it).
  final Key? hairlineKey;

  @override
  State<ScrollUnderHeader> createState() => _ScrollUnderHeaderState();
}

class _ScrollUnderHeaderState extends State<ScrollUnderHeader> {
  bool _scrolled = false;

  bool _onScroll(ScrollNotification n) {
    // depth != 0 => a nested scroller (e.g. a horizontal strip inside a row);
    // axis check => ignore horizontal scrolls entirely. Mirrors
    // EventCommandCenter._onScroll.
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    final scrolled = n.metrics.pixels > widget.threshold;
    if (scrolled != _scrolled) {
      setState(() => _scrolled = scrolled);
    }
    return false; // never consume — let the scroll view scroll.
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        widget.header,
        SizedBox(
          height: 0.5,
          width: double.infinity,
          child: AnimatedOpacity(
            key: widget.hairlineKey,
            opacity: _scrolled ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            child: ColoredBox(color: context.colors.rule),
          ),
        ),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: widget.child,
          ),
        ),
      ],
    );
  }
}
