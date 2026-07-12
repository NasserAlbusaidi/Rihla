import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// #1167 — guard: back buttons must not hand-roll
/// `Directionality.of(context) == TextDirection.rtl ? Iconsax.arrow_right
/// : Iconsax.arrow_left`.
///
/// `Iconsax.arrow_left` and `Iconsax.arrow_right` are NOT a mirrored pair —
/// `arrow_left` is a bare line-arrow, `arrow_right` is a chevron inside a
/// rounded-square box — so this conditional renders two visually different
/// back buttons between LTR and RTL (pixel-verified in the 2026-07-12
/// full-surface UI/RTL sweep). The fix is `DirectionalIcon(Iconsax.arrow_left)`
/// (`lib/shared/widgets/directional_icon.dart`) — one glyph, flipped via
/// `Transform.scale(scaleX: -1)` under RTL.
///
/// This test FAILS if the hand-rolled idiom reappears anywhere in `lib/`.
void main() {
  test(
    'no hand-rolled rtl ? arrow_right : arrow_left back-button idiom in lib/ (#1167)',
    () {
      final offenders = <String>[];
      final pattern = RegExp(
        r'Directionality\.of\(context\)\s*==\s*TextDirection\.rtl\s*'
        r'\?\s*Iconsax\.arrow_right\b[\s\S]{0,60}?'
        r':\s*Iconsax\.arrow_left\b',
      );

      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final content = entity.readAsStringSync();
        if (pattern.hasMatch(content)) {
          offenders.add(entity.path);
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'Found the hand-rolled `Directionality.of(context) == '
            'TextDirection.rtl ? Iconsax.arrow_right : Iconsax.arrow_left` '
            'back-button idiom in: ${offenders.join(', ')}. '
            'Iconsax.arrow_left and Iconsax.arrow_right are NOT a mirrored '
            'pair (#1167) — use DirectionalIcon(Iconsax.arrow_left) from '
            'lib/shared/widgets/directional_icon.dart instead.',
      );
    },
  );
}
