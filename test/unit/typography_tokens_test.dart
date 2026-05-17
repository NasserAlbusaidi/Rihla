import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/theme/tokens/typography_tokens.dart';

/// `arabicDisplay()` calls `GoogleFonts.getFont`, which schedules an async
/// font load. Under `flutter_test_config.dart` runtime fetching is disabled,
/// so the load throws AFTER the test completes and pollutes the run with
/// "test failed after it had already completed". Using `testWidgets` +
/// `tester.runAsync` lets us await the failure inside the test zone instead
/// of leaking it out (and the asserts still validate the synchronous
/// TextStyle shape, which is what we actually care about — render is the
/// production app's concern, not this static-helper test).
void main() {
  group('AppTypography.arabicDisplay', () {
    testWidgets('returns a TextStyle backed by Reem Kufi', (tester) async {
      late TextStyle style;
      await tester.runAsync(() async {
        style = AppTypography.arabicDisplay(fontSize: 22);
      });
      expect(style.fontSize, 22);
      // GoogleFonts assigns a synthetic family name; just confirm it set one.
      expect(style.fontFamily, isNotNull);
      // Reem Kufi has no italic; the helper must NOT default italic on.
      expect(style.fontStyle, isNot(FontStyle.italic));
    });

    testWidgets('honors color, weight, letterSpacing overrides',
        (tester) async {
      late TextStyle style;
      await tester.runAsync(() async {
        style = AppTypography.arabicDisplay(
          fontSize: 60,
          color: const Color(0xFF112233),
          fontWeight: FontWeight.w600,
          letterSpacing: -2,
        );
      });
      expect(style.color, const Color(0xFF112233));
      expect(style.fontWeight, FontWeight.w600);
      expect(style.letterSpacing, -2);
    });
  });
}
