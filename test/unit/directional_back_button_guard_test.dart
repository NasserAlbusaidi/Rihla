import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// #1167/#1173 — guard: no hand-rolled RTL-conditional pair between
/// `Iconsax.arrow_left` and `Iconsax.arrow_right` anywhere in `lib/`, in
/// EITHER argument ordering, and whether the RTL check is inlined into the
/// ternary or first bound to a local bool.
///
/// `Iconsax.arrow_left` and `Iconsax.arrow_right` are NOT a mirrored pair —
/// `arrow_left` is a bare line-arrow, `arrow_right` is a chevron inside a
/// rounded-square box — so a conditional between them renders two visually
/// different glyphs between LTR and RTL, whichever side of the `?:` each
/// constant sits on (pixel-verified in the 2026-07-12 full-surface UI/RTL
/// sweep). #1167 fixed the 8 back-button sites using the inline
/// `Directionality.of(context) == TextDirection.rtl ? arrow_right :
/// arrow_left` ordering. #1173 fixed the one remaining site — the
/// payer→payee flow arrow in `expense_audit_detail.dart` — which used the
/// REVERSED ordering (`... ? arrow_left : arrow_right`) *and* extracted the
/// check into a local `final rtl = Directionality.of(context) ==
/// TextDirection.rtl;` before ternary-ing on the bare `rtl` variable; #1167's
/// original regex (inline-only, single ordering) caught neither difference.
/// The fix is always `DirectionalIcon(Iconsax.<either-glyph>)`
/// (`lib/shared/widgets/directional_icon.dart`) — one glyph, flipped via
/// `Transform.scale(scaleX: -1)` under RTL.
///
/// This test FAILS if the hand-rolled idiom reappears anywhere in `lib/`,
/// in either ordering, inline or via an extracted bool.
void main() {
  test(
    'no hand-rolled rtl-conditional arrow_left/arrow_right pair '
    '(either ordering, inline or extracted-bool) in lib/ (#1167, #1173)',
    () {
      // Either ordering of the two non-mirrored glyphs across a ternary's
      // branches, with a small allowed gap for whitespace/formatting.
      const eitherOrderingTernary =
          r'(?:Iconsax\.arrow_right\b[\s\S]{0,60}?:\s*Iconsax\.arrow_left\b'
          r'|Iconsax\.arrow_left\b[\s\S]{0,60}?:\s*Iconsax\.arrow_right\b)';

      // Inline form: the RTL check sits directly in the ternary condition,
      // e.g. `Directionality.of(context) == TextDirection.rtl ?
      // Iconsax.arrow_right : Iconsax.arrow_left` (#1167's original shape).
      final inlinePattern = RegExp(
        r'Directionality\.of\(context\)\s*==\s*TextDirection\.rtl\s*\?\s*'
        '$eitherOrderingTernary',
      );

      // Extracted-bool form: the RTL check is first bound to a local
      // variable (`final <id> = Directionality.of(context) ==
      // TextDirection.rtl;`), then that bare identifier is ternary-ed later
      // (#1173's shape — `final rtl = ...; ... rtl ? arrow_left :
      // arrow_right`).
      final boolAssignPattern = RegExp(
        r'\b(?:final|var|bool)\s+(\w+)\s*=\s*Directionality\.of\(context\)\s*'
        r'==\s*TextDirection\.rtl\s*;',
      );

      final offenders = <String>[];

      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final content = entity.readAsStringSync();

        var isOffender = inlinePattern.hasMatch(content);

        if (!isOffender) {
          for (final assign in boolAssignPattern.allMatches(content)) {
            final ident = RegExp.escape(assign.group(1)!);
            final ternaryPattern = RegExp(
              '\\b$ident\\s*\\?\\s*$eitherOrderingTernary',
            );
            if (ternaryPattern.hasMatch(content)) {
              isOffender = true;
              break;
            }
          }
        }

        if (isOffender) offenders.add(entity.path);
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'Found the hand-rolled RTL-conditional Iconsax.arrow_left/'
            'arrow_right pair (inline or via an extracted bool, either '
            'ordering) in: ${offenders.join(', ')}. '
            'Iconsax.arrow_left and Iconsax.arrow_right are NOT a mirrored '
            'pair (#1167, #1173) — use DirectionalIcon(Iconsax.arrow_left) '
            'from lib/shared/widgets/directional_icon.dart instead.',
      );
    },
  );
}
