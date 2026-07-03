import 'package:flutter/material.dart';

import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../groups/widgets/group_stamp_icon.dart';

/// Square trip-stamp tile used as the leading element on a group row.
///
/// The tile's ink is one of six muted category colors, chosen by the group's
/// persisted [inkIndex] when set, otherwise derived (render-only) from the
/// name hash. The child is the chosen [glyph] symbol when it is a known id,
/// otherwise the first character of the name as a monogram — both tinted in the
/// same ink over a soft ink-tinted background.
class GroupGlyph extends StatelessWidget {
  const GroupGlyph({
    super.key,
    required this.name,
    this.glyph,
    this.inkIndex,
    this.size = 40,
  });

  /// Display name — first character becomes the monogram when no symbol shows.
  final String name;

  /// Optional persisted glyph id (one of [kGroupGlyphIds]). Unknown/null →
  /// monogram fallback.
  final String? glyph;

  /// Optional persisted ink index 0..5. Null OR out of range → name-hash
  /// fallback (never persisted).
  final int? inkIndex;

  /// Side length (square tile).
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final inks = <Color>[
      colors.cat1,
      colors.cat2,
      colors.cat3,
      colors.cat4,
      colors.cat5,
      colors.cat6,
    ];
    // inkIndex is total-parsed from Firestore (any int, no clamp) — an
    // out-of-range value must defer to the derived ink, never throw a
    // RangeError and blank the always-mounted group row (#532). Symmetric with
    // an unknown glyph degrading to the monogram.
    final fallback = _hash(name) % inks.length;
    final chosen = inkIndex;
    final idx = (chosen != null && chosen >= 0 && chosen < inks.length)
        ? chosen
        : fallback;
    final ink = inks[idx];
    final bg = Color.alphaBlend(
      ink.withValues(alpha: 0.13),
      colors.scaffoldBackground,
    );

    final glyphId = glyph;
    final Widget child = (glyphId != null && isKnownGlyph(glyphId))
        ? GroupStampIcon(glyph: glyphId, ink: ink, size: size * 0.56)
        : Text(
            name.trim().isEmpty
                ? '·'
                : name.trim().characters.first.toUpperCase(),
            style: AppTypography.displayOf(
              context,
              fontSize: size * 0.56,
              color: ink,
              height: 1.0,
            ),
          );

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(size * 0.30),
        border: Border.all(color: ink.withValues(alpha: 0.28)),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }

  static int _hash(String s) {
    var h = 0;
    for (final c in s.codeUnits) {
      h = (h * 31 + c) & 0xffffffff;
    }
    return h;
  }

  @visibleForTesting
  static int debugHash(String name) => _hash(name);

  @visibleForTesting
  static int debugResolvedInkIndex(String name, int? inkIndex) =>
      (inkIndex != null && inkIndex >= 0 && inkIndex < 6)
      ? inkIndex
      : _hash(name) % 6;
}
