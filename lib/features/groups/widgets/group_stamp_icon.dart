import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Canonical, ordered list of the 12 valid group-glyph ids — the SINGLE SOURCE
/// OF TRUTH. The tile widget (`GroupGlyph`) and the glyph picker import this;
/// do not duplicate the list elsewhere. Order is load-bearing for the picker.
const List<String> kGroupGlyphIds = <String>[
  'tent',
  'mountain',
  'palm',
  'sun',
  'wave',
  'compass',
  'anchor',
  'house',
  'dining',
  'coffee',
  'gift',
  'camera',
];

/// Whether [id] is one of the [kGroupGlyphIds]. Callers gate on this before
/// rendering; [GroupStampIcon] also re-checks defensively.
bool isKnownGlyph(String id) => kGroupGlyphIds.contains(id);

/// Renders a single bundled stroke glyph ([glyph]) tinted to [ink].
///
/// An unknown [glyph] (stale or forged id) degrades to `SizedBox.shrink()`
/// rather than a flutter_svg "asset not found" error box — belt-and-suspenders
/// over the caller's own gating.
class GroupStampIcon extends StatelessWidget {
  const GroupStampIcon({
    super.key,
    required this.glyph,
    required this.ink,
    this.size = 24,
  });

  final String glyph;
  final Color ink;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (!isKnownGlyph(glyph)) return const SizedBox.shrink();
    return SvgPicture.asset(
      'assets/glyphs/$glyph.svg',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(ink, BlendMode.srcIn),
    );
  }
}
