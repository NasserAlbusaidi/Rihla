import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/groups/widgets/group_stamp_icon.dart';
import 'package:safar/features/home/widgets/group_glyph.dart';

/// [GroupGlyph] reads `context.colors`, so the pump wrapper MUST supply the
/// Rihla theme (the extension throws without it). No ProviderScope/l10n needed
/// — the widget reads neither.
Future<void> pumpGlyph(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  group('GroupGlyph — symbol vs monogram', () {
    testWidgets('known glyph renders GroupStampIcon', (tester) async {
      await pumpGlyph(
        tester,
        const GroupGlyph(name: 'Beach Trip', glyph: 'tent', inkIndex: 1),
      );

      expect(find.byType(GroupStampIcon), findsOneWidget);
    });

    testWidgets('null glyph falls back to the monogram, no GroupStampIcon', (
      tester,
    ) async {
      await pumpGlyph(
        tester,
        const GroupGlyph(name: 'salalah', glyph: null, inkIndex: 4),
      );

      expect(find.text('S'), findsOneWidget);
      expect(find.byType(GroupStampIcon), findsNothing);
    });

    testWidgets('unknown/forged glyph degrades to the monogram', (
      tester,
    ) async {
      await pumpGlyph(
        tester,
        const GroupGlyph(name: 'Petra', glyph: 'pwned', inkIndex: 2),
      );

      // 'pwned' is not a known id → no symbol, monogram instead.
      expect(find.byType(GroupStampIcon), findsNothing);
      expect(find.text('P'), findsOneWidget);
    });

    testWidgets('empty name renders the · fallback without crashing', (
      tester,
    ) async {
      await pumpGlyph(tester, const GroupGlyph(name: ''));

      expect(find.text('·'), findsOneWidget);
    });
  });

  group('GroupGlyph — ink-index resolution (pure)', () {
    test('null inkIndex resolves to _hash(name) % 6', () {
      expect(
        GroupGlyph.debugResolvedInkIndex('Muscat', null),
        GroupGlyph.debugHash('Muscat') % 6,
      );
    });

    test('resolution is deterministic for the same name', () {
      expect(
        GroupGlyph.debugResolvedInkIndex('Muscat', null),
        GroupGlyph.debugResolvedInkIndex('Muscat', null),
      );
    });

    test('an explicit inkIndex wins over the hash fallback', () {
      expect(GroupGlyph.debugResolvedInkIndex('Muscat', 2), 2);
    });
  });
}
