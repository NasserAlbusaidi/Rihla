import 'package:flutter/material.dart';

import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';

/// Square marker tile used as the leading element on a group row.
///
/// Color is derived from the group's name hash, picking one of six muted
/// journal-stamp pairs. The first character of the name is rendered in
/// italic Instrument Serif over the matching soft background.
class GroupGlyph extends StatelessWidget {
  const GroupGlyph({super.key, required this.name, this.size = 40});

  /// Display name — first character becomes the glyph.
  final String name;

  /// Diameter (square).
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final palette = [
      _Pair(colors.saffronSoft, colors.primaryDark),
      _Pair(colors.cardSoft, colors.success),
      _Pair(colors.cardSoft, colors.cat2),
      _Pair(colors.paperDeep, colors.cat3),
      _Pair(colors.cardSoft, colors.cat5),
      _Pair(colors.cardSoft, colors.cat6),
    ];
    final pair = palette[_hash(name) % palette.length];
    final char = name.trim().isEmpty
        ? '·'
        : name.trim().characters.first.toUpperCase();

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: pair.bg,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Text(
        char,
        style: AppTypography.display(
          fontSize: size * 0.55,
          color: pair.fg,
          height: 1.0,
        ),
      ),
    );
  }

  static int _hash(String s) {
    var h = 0;
    for (final c in s.codeUnits) {
      h = (h * 31 + c) & 0xffffffff;
    }
    return h;
  }
}

class _Pair {
  const _Pair(this.bg, this.fg);
  final Color bg;
  final Color fg;
}
