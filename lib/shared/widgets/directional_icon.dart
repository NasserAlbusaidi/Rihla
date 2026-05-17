import 'package:flutter/material.dart';

/// Mirrors [icon] horizontally when the ambient [Directionality] is RTL.
///
/// Third-party glyph sets (Iconsax in our case) ship [IconData] without
/// `matchTextDirection: true`, so Flutter's `Icon` widget cannot auto-flip
/// them in Arabic. This wrapper takes over that responsibility per call-site.
/// Use it for navigational arrows and chevrons; leave non-directional icons
/// (gear, heart, etc.) on plain `Icon`.
class DirectionalIcon extends StatelessWidget {
  const DirectionalIcon(
    this.icon, {
    super.key,
    this.size,
    this.color,
  });

  final IconData icon;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final iconWidget = Icon(icon, size: size, color: color);
    if (Directionality.of(context) != TextDirection.rtl) return iconWidget;
    return Transform.scale(
      scaleX: -1,
      child: iconWidget,
    );
  }
}
