import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconsax/iconsax.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/activity/utils/expense_audit_diff.dart';
import 'package:safar/features/activity/widgets/expense_audit_detail.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:safar/shared/widgets/r_amount.dart';

/// PR 3 (#248) — the presentational widget rendering money before/after under a
/// MONEY activity row.
void main() {
  Map<String, dynamic> snap({
    int amountFils = 10500,
    String currency = 'OMR',
    String? payer = 'p1',
    String? description = 'Dinner',
  }) => {
    'amountFils': amountFils,
    'currency': currency,
    'payerParticipantId': payer,
    'description': description,
  };

  Future<void> pump(
    WidgetTester tester, {
    required ExpenseAuditDiff diff,
    required String eventType,
    Map<String, String> participantNames = const {},
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ExpenseAuditDetail(
            diff: diff,
            eventType: eventType,
            participantNames: participantNames,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Finder richContaining(String s) =>
      find.textContaining(s, findRichText: true);

  testWidgets('UPDATE amount change renders before → after, currency once', (
    tester,
  ) async {
    await pump(
      tester,
      eventType: 'UPDATE',
      diff: ExpenseAuditDiff.fromMetadata({
        'before': snap(amountFils: 10500),
        'after': snap(amountFils: 12500),
      }),
    );
    expect(richContaining('10.500'), findsOneWidget);
    expect(richContaining('12.500'), findsOneWidget);
    expect(richContaining('OMR'), findsOneWidget); // shown once (same currency)
    expect(find.byIcon(Iconsax.arrow_right), findsOneWidget);
  });

  testWidgets('UPDATE description change renders both texts', (tester) async {
    await pump(
      tester,
      eventType: 'UPDATE',
      diff: ExpenseAuditDiff.fromMetadata({
        'before': snap(description: 'Dinner'),
        'after': snap(description: 'Late dinner'),
      }),
    );
    expect(find.text('Dinner'), findsOneWidget);
    expect(find.text('Late dinner'), findsOneWidget);
  });

  testWidgets('UPDATE payer change resolves names + shows label', (
    tester,
  ) async {
    await pump(
      tester,
      eventType: 'UPDATE',
      participantNames: const {'p1': 'Bob', 'p2': 'Alice'},
      diff: ExpenseAuditDiff.fromMetadata({
        'before': snap(payer: 'p1'),
        'after': snap(payer: 'p2'),
      }),
    );
    expect(richContaining('Bob'), findsOneWidget);
    expect(richContaining('Alice'), findsOneWidget);
    expect(richContaining('Payer'), findsOneWidget);
  });

  testWidgets('unknown payer id falls back to "Someone"', (tester) async {
    await pump(
      tester,
      eventType: 'UPDATE',
      participantNames: const {'p1': 'Bob'}, // p2 absent
      diff: ExpenseAuditDiff.fromMetadata({
        'before': snap(payer: 'p1'),
        'after': snap(payer: 'p2-unknown'),
      }),
    );
    expect(richContaining('Bob'), findsOneWidget);
    expect(richContaining('Someone'), findsOneWidget);
  });

  testWidgets('CREATE renders nothing — the row shows a trailing amount instead', (
    tester,
  ) async {
    // #490 D-g: CREATE/DELETE summaries moved to ActivityRow.trailingAmount;
    // this widget is narrowed to UPDATE-with-field-change only.
    await pump(
      tester,
      eventType: 'CREATE',
      diff: ExpenseAuditDiff.fromMetadata({
        'before': null,
        'after': snap(amountFils: 8000, description: 'Lunch'),
      }),
    );
    expect(find.byType(RAmount), findsNothing);
    expect(tester.getSize(find.byType(ExpenseAuditDetail)), Size.zero);
  });

  testWidgets('DELETE renders nothing — the row shows a muted trailing amount instead', (
    tester,
  ) async {
    await pump(
      tester,
      eventType: 'DELETE',
      diff: ExpenseAuditDiff.fromMetadata({
        'before': snap(amountFils: 3500, description: 'Taxi'),
        'after': snap(amountFils: 3500, description: 'Taxi'),
      }),
    );
    expect(find.byType(RAmount), findsNothing);
    expect(tester.getSize(find.byType(ExpenseAuditDetail)), Size.zero);
  });

  testWidgets(
    'UPDATE with no money-field change renders nothing (row trailing amount covers it)',
    (tester) async {
      // e.g. a split-only edit: before == after money snapshot.
      await pump(
        tester,
        eventType: 'UPDATE',
        diff: ExpenseAuditDiff.fromMetadata({
          'before': snap(amountFils: 5000, description: 'Coffee'),
          'after': snap(amountFils: 5000, description: 'Coffee'),
        }),
      );
      expect(find.byType(RAmount), findsNothing);
      expect(tester.getSize(find.byType(ExpenseAuditDetail)), Size.zero);
    },
  );

  testWidgets('legacy/empty metadata renders nothing', (tester) async {
    await pump(
      tester,
      eventType: 'CREATE',
      diff: ExpenseAuditDiff.fromMetadata(<String, dynamic>{}),
    );
    expect(find.byType(RAmount), findsNothing);
    expect(tester.getSize(find.byType(ExpenseAuditDetail)), Size.zero);
  });
}
