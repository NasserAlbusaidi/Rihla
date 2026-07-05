import 'package:flutter/material.dart';

import '../../core/theme/tokens/color_tokens.dart';
import '../../core/theme/tokens/domain_aliases.dart';
import '../../core/theme/tokens/typography_tokens.dart';

/// Foreground/background pair for the journal-stamp avatar palette.
class _AvatarColorPair {
  const _AvatarColorPair(this.fg, this.bg);
  final Color fg;
  final Color bg;
}

/// Eight journal-stamp color pairs used to color person avatars.
///
/// Pairs are chosen for warm-paper backgrounds and read as muted ink stamps
/// rather than saturated badges. The hash → slot mapping is stable across
/// app upgrades because [_stableHash] folds `codeUnits` with a fixed constant.
const List<_AvatarColorPair> _palette = [
  // design-token-justified: deterministic avatar stamps are decorative identity colors.
  _AvatarColorPair(Color(0xFF2F5A74), Color(0xFFDCE6EC)),
  _AvatarColorPair(Color(0xFF4C5A28), Color(0xFFE2E6D4)),
  _AvatarColorPair(Color(0xFF7A3B62), Color(0xFFECDCE6)),
  _AvatarColorPair(Color(0xFF8A4428), Color(0xFFF0DFD5)),
  // design-token-justified: deterministic avatar stamps are decorative identity colors.
  _AvatarColorPair(Color(0xFF3B4270), Color(0xFFDEE0EC)),
  _AvatarColorPair(Color(0xFF1F6B54), Color(0xFFD6E7DF)),
  _AvatarColorPair(Color(0xFF6F4A08), Color(0xFFECE6D4)),
  _AvatarColorPair(Color(0xFF3F4A54), Color(0xFFDEE3E8)),
];

int _stableHash(String s) {
  var h = 0;
  for (final c in s.codeUnits) {
    h = (h * 31 + c) & 0xffffffff;
  }
  return h;
}

String _extractInitials(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '?';
  final words = trimmed.split(RegExp(r'\s+'));
  if (words.length == 1) {
    return words.first.characters.first.toUpperCase();
  }
  final first = words.first.characters.first.toUpperCase();
  final last = words.last.characters.first.toUpperCase();
  return '$first$last';
}

/// Person avatar — initials stamp with a deterministic journal palette.
///
/// Colors are picked from [_palette] by hashing [name], so the same person
/// renders the same color across screens and sessions. Pass [hue] to force
/// a specific palette index (0–7).
///
/// Sizing: font size scales at 0.40× of the diameter to match the wireframe.
class RAvatar extends StatelessWidget {
  const RAvatar({super.key, required this.name, this.size = 32, this.hue});

  /// Display name; first letters of first and last words become initials.
  final String name;

  /// Diameter in logical pixels.
  final double size;

  /// Force a specific palette slot (0–7). When null, [name] hash picks.
  final int? hue;

  @override
  Widget build(BuildContext context) {
    final pair = _palette[(hue ?? _stableHash(name)) % _palette.length];
    final initials = _extractInitials(name);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: pair.bg, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: AppTypography.sans(
          fontSize: size * 0.40,
          fontWeight: FontWeight.w600,
          color: pair.fg,
          letterSpacing: 0.2,
          height: 1.0,
        ),
      ),
    );
  }
}

/// Overlapping stack of [RAvatar]s with a paper-colored ring per avatar and
/// a `+N` overflow chip when [names] exceeds [max].
///
/// Overlap is -30% of [size]; ring is 2px in [AppColorTokens.scaffoldBackground]
/// so the stack reads cleanly on the page background.
class RAvatarStack extends StatelessWidget {
  const RAvatarStack({
    super.key,
    required this.names,
    this.size = 28,
    this.max = 4,
  });

  /// Names to render, in display order.
  final List<String> names;

  /// Diameter of each avatar.
  final double size;

  /// Maximum avatars to show before collapsing the rest into `+N`.
  final int max;

  @override
  Widget build(BuildContext context) {
    if (names.isEmpty) return const SizedBox.shrink();

    final colors = context.colors;
    final visible = names.take(max).toList();
    final extra = names.length - visible.length;
    final step = size * 0.70; // 30% overlap between adjacent items
    final ringColor = colors.scaffoldBackground;
    final slots = visible.length + (extra > 0 ? 1 : 0);
    final stackWidth = step * (slots - 1) + size;

    Widget ringedAvatar(String name) => Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: ringColor, width: 2),
      ),
      child: RAvatar(name: name, size: size),
    );

    Widget overflowChip() => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.textSecondary,
        border: Border.all(color: ringColor, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        '+$extra',
        style: AppTypography.sans(
          fontSize: size * 0.36,
          fontWeight: FontWeight.w600,
          color: colors.scaffoldBackground,
          height: 1.0,
        ),
      ),
    );

    return SizedBox(
      width: stackWidth,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < visible.length; i++)
            Positioned(left: step * i, child: ringedAvatar(visible[i])),
          if (extra > 0)
            Positioned(left: step * visible.length, child: overflowChip()),
        ],
      ),
    );
  }
}
