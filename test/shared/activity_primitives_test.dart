import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconsax/iconsax.dart';

import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:safar/shared/widgets/activity_glyph.dart';
import 'package:safar/shared/widgets/activity_row.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('ActivityCategoryIcon', () {
    testWidgets('maps expenseAdded to the receipt_add icon', (tester) async {
      await _pump(
        tester,
        const ActivityCategoryIcon(glyph: ActivityGlyph.expenseAdded),
      );
      expect(find.byIcon(Iconsax.receipt_add), findsOneWidget);
    });

    testWidgets('maps settlement to the wallet_3 icon', (tester) async {
      await _pump(
        tester,
        const ActivityCategoryIcon(glyph: ActivityGlyph.settlement),
      );
      expect(find.byIcon(Iconsax.wallet_3), findsOneWidget);
    });

    testWidgets('maps generic to the activity icon', (tester) async {
      await _pump(
        tester,
        const ActivityCategoryIcon(glyph: ActivityGlyph.generic),
      );
      expect(find.byIcon(Iconsax.activity), findsOneWidget);
    });

    testWidgets('tile corner radius uses the radiusSmall token (8dp)', (
      tester,
    ) async {
      await _pump(
        tester,
        const ActivityCategoryIcon(glyph: ActivityGlyph.generic),
      );
      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(ActivityCategoryIcon),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = container.decoration! as BoxDecoration;
      final radius = decoration.borderRadius! as BorderRadius;
      expect(radius.topLeft.x, 8);
    });

    testWidgets('settlement tile has no border', (tester) async {
      await _pump(
        tester,
        const ActivityCategoryIcon(glyph: ActivityGlyph.settlement),
      );
      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(ActivityCategoryIcon),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.border, isNull);
    });

    testWidgets('expenseEdited tile has a border', (tester) async {
      await _pump(
        tester,
        const ActivityCategoryIcon(glyph: ActivityGlyph.expenseEdited),
      );
      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(ActivityCategoryIcon),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.border, isNotNull);
    });
  });

  group('ActivityRow', () {
    testWidgets('renders actor and description as rich text', (
      tester,
    ) async {
      await _pump(
        tester,
        ActivityRow(
          glyph: ActivityGlyph.expenseAdded,
          actorName: 'Alice',
          description: 'added Dinner',
          timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
        ),
      );
      expect(find.textContaining('Alice', findRichText: true), findsOneWidget);
      expect(
        find.textContaining('added Dinner', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('renders group chip only when groupName is given', (
      tester,
    ) async {
      await _pump(
        tester,
        ActivityRow(
          glyph: ActivityGlyph.expenseAdded,
          actorName: 'Alice',
          description: 'added Dinner',
          timestamp: DateTime.now(),
        ),
      );
      expect(find.text('Beach Trip'), findsNothing);

      await _pump(
        tester,
        ActivityRow(
          glyph: ActivityGlyph.expenseAdded,
          actorName: 'Alice',
          description: 'added Dinner',
          timestamp: DateTime.now(),
          groupName: 'Beach Trip',
        ),
      );
      expect(find.text('Beach Trip'), findsOneWidget);
    });

    testWidgets('renders the trailingAmount slot when provided', (
      tester,
    ) async {
      await _pump(
        tester,
        ActivityRow(
          glyph: ActivityGlyph.expenseAdded,
          actorName: 'Alice',
          description: 'added Dinner',
          timestamp: DateTime.now(),
          trailingAmount: const Text('OMR 12.500', key: ValueKey('amt')),
        ),
      );
      expect(find.byKey(const ValueKey('amt')), findsOneWidget);
    });

    testWidgets('muted wraps trailingAmount in Opacity(.6)', (tester) async {
      await _pump(
        tester,
        ActivityRow(
          glyph: ActivityGlyph.expenseAdded,
          actorName: 'Alice',
          description: 'added Dinner',
          timestamp: DateTime.now(),
          muted: true,
          trailingAmount: const Text('OMR 12.500', key: ValueKey('amt')),
        ),
      );
      final opacity = tester.widget<Opacity>(
        find
            .ancestor(
              of: find.byKey(const ValueKey('amt')),
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(opacity.opacity, 0.6);
    });

    testWidgets('renders the detail slot when provided', (tester) async {
      await _pump(
        tester,
        ActivityRow(
          glyph: ActivityGlyph.expenseEdited,
          actorName: 'Bob',
          description: 'edited Dinner',
          timestamp: DateTime.now(),
          detail: const Text('was 12.000 → now 15.000', key: ValueKey('d')),
        ),
      );
      expect(find.byKey(const ValueKey('d')), findsOneWidget);
    });

    testWidgets('onTap fires when the row is tapped', (tester) async {
      var tapped = false;
      await _pump(
        tester,
        ActivityRow(
          glyph: ActivityGlyph.expenseAdded,
          actorName: 'Alice',
          description: 'added Dinner',
          timestamp: DateTime.now(),
          onTap: () => tapped = true,
        ),
      );
      await tester.tap(find.byType(ActivityRow));
      expect(tapped, isTrue);
    });

    testWidgets('renders a divider hairline when divider is true', (
      tester,
    ) async {
      await _pump(
        tester,
        ActivityRow(
          glyph: ActivityGlyph.expenseAdded,
          actorName: 'Alice',
          description: 'added Dinner',
          timestamp: DateTime.now(),
          divider: true,
        ),
      );
      final dividerContainers = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(ActivityRow),
              matching: find.byType(Container),
            ),
          )
          .where((c) => c.color != null);
      expect(dividerContainers, isNotEmpty);
    });

    testWidgets('omits the divider hairline when divider is false', (
      tester,
    ) async {
      await _pump(
        tester,
        ActivityRow(
          glyph: ActivityGlyph.expenseAdded,
          actorName: 'Alice',
          description: 'added Dinner',
          timestamp: DateTime.now(),
        ),
      );
      final dividerContainers = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(ActivityRow),
              matching: find.byType(Container),
            ),
          )
          .where((c) => c.color != null);
      expect(dividerContainers, isEmpty);
    });
  });
}
