import 'package:flutter/material.dart';

import '../../core/theme/tokens/color_tokens.dart';

/// A circular avatar displaying the initials of the given [name].
///
/// Used at 64dp on the profile screen and 32dp elsewhere (e.g. home header).
///
/// Initials extraction rules:
/// - Empty/blank name → displays '?'
/// - Single word → first character (uppercased)
/// - Two or more words → first char of first word + first char of last word
class InitialsCircle extends StatelessWidget {
  const InitialsCircle({
    super.key,
    required this.size,
    required this.name,
    this.backgroundColor,
    this.textColor,
  });

  /// Diameter of the circle in logical pixels.
  final double size;

  /// Name to extract initials from.
  final String name;

  /// Background fill color. Defaults to [AppColorTokens.light.focusBorderWarm]
  /// (terracotta #CC6B49).
  final Color? backgroundColor;

  /// Text color. Defaults to [AppColorTokens.light.textOnPrimary] (#FFFFFF).
  final Color? textColor;

  /// Extract up to 2 initials from a display name.
  static String _extractInitials(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';

    final words = trimmed.split(RegExp(r'\s+'));
    if (words.length == 1) {
      return words.first[0].toUpperCase();
    }
    final first = words.first[0].toUpperCase();
    final last = words.last[0].toUpperCase();
    return '$first$last';
  }

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? AppColorTokens.light.focusBorderWarm;
    final fg = textColor ?? AppColorTokens.light.textOnPrimary;
    final fontSize = size * 0.38;
    final initials = _extractInitials(name);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            color: fg,
            height: 1.0,
          ),
        ),
      ),
    );
  }
}
