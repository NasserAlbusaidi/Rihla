import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconsax/iconsax.dart';

import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:safar/shared/widgets/activity_glyph.dart';

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
}
