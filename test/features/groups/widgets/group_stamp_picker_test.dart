import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/groups/widgets/group_stamp_icon.dart';
import 'package:safar/features/groups/widgets/group_stamp_picker.dart';
import 'package:safar/features/home/widgets/group_glyph.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// Themed pump — [GroupStampPicker] reads `context.colors`, so it needs the
/// real theme. No ProviderScope/Firestore: the picker is pure (value in,
/// onChanged out). Mirrors `create_join_group_test.dart`'s themed MaterialApp
/// + localization delegates, but with a plain Scaffold body.
Future<void> pumpPicker(
  WidgetTester tester, {
  required String name,
  required GroupStampSelection value,
  required ValueChanged<GroupStampSelection> onChanged,
  bool showHero = true,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: GroupStampPicker(
            name: name,
            value: value,
            onChanged: onChanged,
            showHero: showHero,
          ),
        ),
      ),
    ),
  );
}

/// Saffron primary, the selection-ring colour (`AppColorTokens.light.primary`).
const _saffron = Color(0xFFD17B2C);

/// True iff the keyed ring container paints a saffron (primary) border — the
/// picker wraps every selectable cell in a ring container keyed `*_ring`; the
/// border is saffron when selected and transparent otherwise, so layout never
/// shifts.
bool hasSaffronRing(WidgetTester tester, Finder ringFinder) {
  final container = tester.widget<Container>(ringFinder);
  final deco = container.decoration as BoxDecoration?;
  final border = deco?.border;
  if (border is! Border) return false;
  return border.top.color == _saffron && border.top.width > 0;
}

void main() {

  group('GroupStampPicker — emits immutable record copies', () {
    testWidgets('tapping a symbol emits (glyph: id, inkIndex: unchanged)', (
      tester,
    ) async {
      GroupStampSelection? emitted;
      await pumpPicker(
        tester,
        name: 'Salalah Crew',
        value: (glyph: null, inkIndex: 3),
        onChanged: (v) => emitted = v,
      );

      await tester.tap(find.byKey(const Key('stampSym_tent')));
      await tester.pump();

      expect(emitted, isNotNull);
      expect(emitted!.glyph, 'tent');
      expect(emitted!.inkIndex, 3, reason: 'inkIndex must be carried through');
    });

    testWidgets('tapping the monogram cell emits (glyph: null, inkIndex: unchanged)', (
      tester,
    ) async {
      GroupStampSelection? emitted;
      await pumpPicker(
        tester,
        name: 'Salalah Crew',
        value: (glyph: 'tent', inkIndex: 2),
        onChanged: (v) => emitted = v,
      );

      await tester.tap(find.byKey(const Key('stampSym_monogram')));
      await tester.pump();

      expect(emitted, isNotNull);
      expect(emitted!.glyph, isNull, reason: 'monogram clears the symbol');
      expect(emitted!.inkIndex, 2);
    });

    testWidgets('tapping an ink swatch emits a non-null inkIndex', (
      tester,
    ) async {
      GroupStampSelection? emitted;
      await pumpPicker(
        tester,
        name: 'Salalah Crew',
        value: (glyph: 'tent', inkIndex: null),
        onChanged: (v) => emitted = v,
      );

      await tester.tap(find.byKey(const Key('stampInk_4')));
      await tester.pump();

      expect(emitted, isNotNull);
      expect(emitted!.inkIndex, isNotNull, reason: 'ink pick is always a real index');
      expect(emitted!.inkIndex, 4);
      expect(emitted!.glyph, 'tent', reason: 'glyph carried through');
    });

    testWidgets('does not mutate the incoming value record', (tester) async {
      const incoming = (glyph: 'wave', inkIndex: 1);
      await pumpPicker(
        tester,
        name: 'Crew',
        value: incoming,
        onChanged: (_) {},
      );

      await tester.tap(find.byKey(const Key('stampInk_5')));
      await tester.pump();

      // Records are value types; this just documents intent — the incoming
      // const is unaffected by any emit.
      expect(incoming.glyph, 'wave');
      expect(incoming.inkIndex, 1);
    });
  });

  group('GroupStampPicker — hero', () {
    testWidgets('renders a live hero GroupGlyph even with nothing chosen', (
      tester,
    ) async {
      await pumpPicker(
        tester,
        name: 'Salalah Crew',
        value: (glyph: null, inkIndex: null),
        onChanged: (_) {},
      );

      // The hero is the size-80 GroupGlyph; there is also one GroupGlyph-free
      // monogram cell + symbol icons, so assert the hero specifically by size.
      final heroes = tester
          .widgetList<GroupGlyph>(find.byType(GroupGlyph))
          .where((g) => g.size >= 64);
      expect(heroes, hasLength(1), reason: 'one large live hero');
      expect(heroes.first.name, 'Salalah Crew');
      expect(heroes.first.glyph, isNull);
      expect(heroes.first.inkIndex, isNull);
    });

    testWidgets('empty name + nothing chosen renders without crashing', (
      tester,
    ) async {
      await pumpPicker(
        tester,
        name: '',
        value: (glyph: null, inkIndex: null),
        onChanged: (_) {},
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(GroupStampPicker), findsOneWidget);
      // The hero's monogram fallback ('·') is rendered by GroupGlyph.
      expect(find.byType(GroupGlyph), findsWidgets);
    });
  });

  group('GroupStampPicker — selection ring follows state', () {
    testWidgets('inkIndex == null → NO swatch is ringed', (tester) async {
      await pumpPicker(
        tester,
        name: 'Crew',
        value: (glyph: null, inkIndex: null),
        onChanged: (_) {},
      );

      for (var i = 0; i < 6; i++) {
        expect(
          hasSaffronRing(tester, find.byKey(Key('stampInk_${i}_ring'))),
          isFalse,
          reason: 'swatch $i must not be ringed when inkIndex is null',
        );
      }
    });

    testWidgets('inkIndex == 2 → only the index-2 swatch is ringed', (
      tester,
    ) async {
      await pumpPicker(
        tester,
        name: 'Crew',
        value: (glyph: null, inkIndex: 2),
        onChanged: (_) {},
      );

      for (var i = 0; i < 6; i++) {
        final ringed = hasSaffronRing(
          tester,
          find.byKey(Key('stampInk_${i}_ring')),
        );
        expect(ringed, i == 2, reason: 'only swatch 2 ringed; checked $i');
      }
    });

    testWidgets('glyph == null → monogram cell ringed, tent cell not', (
      tester,
    ) async {
      await pumpPicker(
        tester,
        name: 'Crew',
        value: (glyph: null, inkIndex: 0),
        onChanged: (_) {},
      );

      expect(
        hasSaffronRing(tester, find.byKey(const Key('stampSym_monogram_ring'))),
        isTrue,
      );
      expect(
        hasSaffronRing(tester, find.byKey(const Key('stampSym_tent_ring'))),
        isFalse,
      );
    });

    testWidgets('glyph == tent → tent cell ringed, monogram not', (
      tester,
    ) async {
      await pumpPicker(
        tester,
        name: 'Crew',
        value: (glyph: 'tent', inkIndex: 0),
        onChanged: (_) {},
      );

      expect(
        hasSaffronRing(tester, find.byKey(const Key('stampSym_tent_ring'))),
        isTrue,
      );
      expect(
        hasSaffronRing(tester, find.byKey(const Key('stampSym_monogram_ring'))),
        isFalse,
      );
    });
  });

  group('GroupStampPicker — showHero', () {
    testWidgets('showHero: false drops the internal hero, keeps ink + grid', (
      tester,
    ) async {
      await pumpPicker(
        tester,
        name: 'Crew',
        value: (glyph: 'tent', inkIndex: 1),
        onChanged: (_) {},
        showHero: false,
      );

      // No internal hero GroupGlyph — the edit sheet renders its own above.
      expect(find.byType(GroupGlyph), findsNothing);
      // Ink swatches + symbol grid (incl. monogram) still render.
      for (var i = 0; i < 6; i++) {
        expect(find.byKey(Key('stampInk_$i')), findsOneWidget);
      }
      expect(find.byKey(const Key('stampSym_monogram')), findsOneWidget);
      expect(find.byKey(const Key('stampSym_tent')), findsOneWidget);
    });

    testWidgets('default (showHero: true) still renders the internal hero', (
      tester,
    ) async {
      await pumpPicker(
        tester,
        name: 'Crew',
        value: (glyph: 'tent', inkIndex: 1),
        onChanged: (_) {},
      );

      final heroes = tester
          .widgetList<GroupGlyph>(find.byType(GroupGlyph))
          .where((g) => g.size >= 64);
      expect(heroes, hasLength(1), reason: 'internal hero present by default');
    });
  });

  group('GroupStampPicker — completeness', () {
    testWidgets('renders all 6 ink swatches and all 12 symbol cells + monogram', (
      tester,
    ) async {
      await pumpPicker(
        tester,
        name: 'Crew',
        value: (glyph: null, inkIndex: null),
        onChanged: (_) {},
      );

      for (var i = 0; i < 6; i++) {
        expect(find.byKey(Key('stampInk_$i')), findsOneWidget);
      }
      expect(find.byKey(const Key('stampSym_monogram')), findsOneWidget);
      for (final id in kGroupGlyphIds) {
        expect(
          find.byKey(Key('stampSym_$id')),
          findsOneWidget,
          reason: 'symbol cell for $id',
        );
      }
    });
  });
}
