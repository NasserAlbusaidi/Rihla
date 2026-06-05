import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/groups/widgets/group_settlement_tile.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

void main() {
  testWidgets(
    'payer and payee avatars share a uniform border — no redundant ring (#147)',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: GroupSettlementTile(
              fromName: 'Alice',
              toName: 'Bob',
              amount: Decimal.parse('10.000'),
              currency: 'OMR',
              breakdown: const {},
              isYourAction: true,
            ),
          ),
        ),
      );
      await tester.pump();

      // The two avatars are the only circular Containers in the tile.
      final ringColors = tester
          .widgetList<Container>(find.byType(Container))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .where((d) => d.shape == BoxShape.circle && d.border is Border)
          .map((d) => (d.border! as Border).top.color)
          .toList();

      expect(ringColors, hasLength(2));
      // Payer/payee distinction is the background tint + the names row, not a
      // differential ring — both rings are identical now.
      expect(ringColors[0], equals(ringColors[1]));
    },
  );

  testWidgets(
    'direction line keeps the disambiguation discriminator — two same-named '
    'members render "Sam (#aaaa) -> Sam (#bbbb)", never "Sam -> Sam" (#263)',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: GroupSettlementTile(
              fromName: 'Sam (#aaaa)',
              toName: 'Sam (#bbbb)',
              amount: Decimal.parse('5.000'),
              currency: 'OMR',
              breakdown: const {},
              isYourAction: true,
            ),
          ),
        ),
      );
      await tester.pump();

      // The visible direction line is a RichText, so traverse it.
      expect(
        find.textContaining('Sam (#aaaa)', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('Sam (#bbbb)', findRichText: true),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'direction line still compacts a multi-token name to its first token '
    'when no discriminator is present (#263 preserves the #196-era compaction)',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: GroupSettlementTile(
              fromName: 'Sam Smith',
              toName: 'Bob Jones',
              amount: Decimal.parse('5.000'),
              currency: 'OMR',
              breakdown: const {},
              isYourAction: true,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.textContaining('Sam -> Bob', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('Smith', findRichText: true),
        findsNothing,
      );
    },
  );
}
