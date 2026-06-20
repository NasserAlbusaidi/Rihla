import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/features/groups/widgets/group_stamp_icon.dart';

/// Minimal themed pump — [GroupStampIcon] reads no `context.colors`/l10n, so a
/// bare `MaterialApp` is sufficient (no ProviderScope/localization needed).
Future<void> pumpStamp(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    MaterialApp(home: Scaffold(body: Center(child: child))),
  );
}

void main() {
  group('kGroupGlyphIds + isKnownGlyph', () {
    test('kGroupGlyphIds has the 12 canonical ids in order', () {
      expect(kGroupGlyphIds.length, 12);
      expect(kGroupGlyphIds, const <String>[
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
      ]);
    });

    test('isKnownGlyph is true for a known id, false for an unknown id', () {
      expect(isKnownGlyph('tent'), isTrue);
      expect(isKnownGlyph('pwned'), isFalse);
    });
  });

  group('GroupStampIcon', () {
    testWidgets('renders the glyph asset tinted to the ink colour', (
      tester,
    ) async {
      await pumpStamp(
        tester,
        const GroupStampIcon(
          glyph: 'tent',
          ink: Color(0xFFC2693B),
          size: 40,
        ),
      );

      expect(find.byType(SvgPicture), findsOneWidget);

      final svg = tester.widget<SvgPicture>(find.byType(SvgPicture));
      expect(
        svg.colorFilter,
        const ColorFilter.mode(Color(0xFFC2693B), BlendMode.srcIn),
      );

      // The asset name is exposed via the SvgAssetLoader that SvgPicture.asset
      // builds for its bytesLoader.
      final loader = svg.bytesLoader as SvgAssetLoader;
      expect(loader.assetName, 'assets/glyphs/tent.svg');
    });

    testWidgets('unknown id degrades to SizedBox.shrink (no SvgPicture)', (
      tester,
    ) async {
      await pumpStamp(
        tester,
        const GroupStampIcon(glyph: 'pwned', ink: Color(0xFFC2693B)),
      );

      expect(find.byType(SvgPicture), findsNothing);
      expect(find.byType(SizedBox), findsOneWidget);
    });
  });
}
