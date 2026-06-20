import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/groups/widgets/group_settlement_tile.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:safar/shared/widgets/r_avatar.dart';

void main() {
  testWidgets(
    'payer and payee both render the shared RAvatar — deterministic per-person '
    'color, not a hand-rolled tint (#490, DEC-3)',
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

      // Both avatars are the shared RAvatar (name only, no hue override — DEC-3),
      // replacing the prior hand-rolled saffron/cardSoft tint circles.
      final avatars = tester.widgetList<RAvatar>(find.byType(RAvatar)).toList();
      expect(avatars, hasLength(2));
      expect(avatars.map((a) => a.name), containsAll(['Alice', 'Bob']));
      expect(avatars.every((a) => a.hue == null), isTrue);
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
