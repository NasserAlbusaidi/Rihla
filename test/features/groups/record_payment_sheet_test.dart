import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/groups/keys/group_keys.dart';
import 'package:safar/features/groups/widgets/record_payment_sheet.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

// #225 — direct contract coverage for RecordPaymentSheet.
//
// The settlement *write path* the issue describes (append-only row, correct
// createdBy, zero/too-large blocked) lives in the SCREENS, not this sheet, and
// is already covered transitively: group_settle_up_screen_test asserts
// `addCalls.single.createdBy == 'uid-bob'` plus the zero / too-large snackbars,
// and settle_up_screen_test mirrors it for the ledger screen. This sheet is a
// pure input collector: it returns a RecordPaymentResult on confirm (or null on
// dismiss) and performs no submit-BLOCKING validation. That contract — never
// exercised in isolation — is what these tests pin. (#220 adds inline free-text
// FEEDBACK on the note field — an errorText hint — but it still never blocks
// confirm; the caller/server stay responsible for enforcement.)
void main() {
  Future<RecordPaymentResult?> openAndReturn(
    WidgetTester tester, {
    required String currency,
    required Decimal suggestedAmount,
    String fromName = 'Bob',
    String toName = 'Alice',
    required Future<void> Function(WidgetTester) act,
  }) async {
    RecordPaymentResult? result;
    var resolved = false;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  key: const Key('open'),
                  onPressed: () async {
                    result = await showRecordPaymentSheet(
                      context,
                      currency: currency,
                      fromName: fromName,
                      toName: toName,
                      suggestedAmount: suggestedAmount,
                    );
                    resolved = true;
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();

    await act(tester);
    await tester.pumpAndSettle();

    expect(resolved, isTrue, reason: 'sheet should have resolved its Future');
    return result;
  }

  Future<void> tapMarkPaid(WidgetTester tester) async {
    // The sheet is a SingleChildScrollView; with the amount editor expanded the
    // confirm button can sit below the 800x600 test fold, so scroll it into
    // view before tapping (a tap on an off-screen widget is a no-op miss).
    await tester.ensureVisible(find.byKey(GroupKeys.markAsPaidButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(GroupKeys.markAsPaidButton));
  }

  testWidgets(
    'banner states recording is immediate, not a notify/confirm promise (#281)',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    key: const Key('open'),
                    onPressed: () => showRecordPaymentSheet(
                      context,
                      currency: 'OMR',
                      fromName: 'Bob',
                      toName: 'Alice',
                      suggestedAmount: Decimal.parse('5.000'),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();

      // The old copy promised a two-party confirmation / notification that does
      // not exist: recording is unilateral and immediate, and there is no
      // `confirmed` field. A user who "waits for confirmation" waits forever.
      expect(find.textContaining('will be notified'), findsNothing);
      expect(find.textContaining('to confirm'), findsNothing);
      // Honest copy: states plainly that the write is immediate.
      expect(find.textContaining('immediately'), findsOneWidget);
    },
  );

  testWidgets('#351: banner says Rihla records but does not move money', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  key: const Key('open'),
                  onPressed: () => showRecordPaymentSheet(
                    context,
                    currency: 'OMR',
                    fromName: 'Bob',
                    toName: 'Alice',
                    suggestedAmount: Decimal.parse('5.000'),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();

    // Rihla is a ledger, not a payment processor — no funds are transferred.
    expect(find.textContaining("doesn't move money"), findsOneWidget);
  });

  testWidgets('confirm returns the seeded amount and empty note', (
    tester,
  ) async {
    final result = await openAndReturn(
      tester,
      currency: 'OMR',
      suggestedAmount: Decimal.parse('7.750'),
      act: tapMarkPaid,
    );

    expect(result, isNotNull);
    expect(result!.amount, '7.750');
    expect(result.note, '');
  });

  testWidgets('Not Now dismisses the sheet and returns null', (tester) async {
    final result = await openAndReturn(
      tester,
      currency: 'OMR',
      suggestedAmount: Decimal.parse('7.750'),
      act: (t) => t.tap(find.byKey(GroupKeys.notNowButton)),
    );

    expect(result, isNull);
  });

  testWidgets('edited amount and entered note flow into the result', (
    tester,
  ) async {
    final result = await openAndReturn(
      tester,
      currency: 'OMR',
      suggestedAmount: Decimal.parse('7.750'),
      act: (t) async {
        // Editor closed → the only TextField is the note.
        await t.enterText(find.byType(TextField), 'dinner');
        await t.pump();
        // Reveal the amount editor and override the suggested amount.
        await t.tap(find.text('Tap to edit amount'));
        await t.pumpAndSettle();
        await t.enterText(find.byType(TextFormField), '5.250');
        await t.pump();
        await tapMarkPaid(t);
      },
    );

    expect(result!.amount, '5.250');
    expect(result.note, 'dinner');
  });

  testWidgets('seeds the amount at the currency decimal scale (JPY → 0dp)', (
    tester,
  ) async {
    final result = await openAndReturn(
      tester,
      currency: 'JPY',
      suggestedAmount: Decimal.parse('1000'),
      act: tapMarkPaid,
    );

    // 0-decimal currency → no spurious '.000' tail.
    expect(result!.amount, '1000');
  });

  testWidgets('#220: an over-length note shows an inline error but still '
      'allows confirm (no client hard-block)', (tester) async {
    final result = await openAndReturn(
      tester,
      currency: 'OMR',
      suggestedAmount: Decimal.parse('7.750'),
      act: (t) async {
        await t.enterText(find.byType(TextField), 'a' * 281);
        await t.pump();
        // Inline feedback instead of an opaque permission-denied.
        expect(
          find.text('Keep it to 280 characters or fewer.'),
          findsOneWidget,
        );
        // The sheet still returns — it never blocks; the server enforces.
        await tapMarkPaid(t);
      },
    );

    expect(result, isNotNull);
  });

  testWidgets('performs no validation — returns a zero amount as typed '
      '(the caller validates)', (tester) async {
    final result = await openAndReturn(
      tester,
      currency: 'OMR',
      suggestedAmount: Decimal.zero,
      act: tapMarkPaid,
    );

    // The sheet does not block zero; settle_up_screen / group_settle_up_screen
    // do. This pins the division of responsibility.
    expect(result, isNotNull);
    expect(result!.amount, '0.000');
  });

  testWidgets('#382 PR-5: stepLabel renders as an overline above the title', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  key: const Key('open'),
                  onPressed: () => showRecordPaymentSheet(
                    context,
                    currency: 'OMR',
                    fromName: 'Bob',
                    toName: 'Alice',
                    suggestedAmount: Decimal.parse('5.000'),
                    stepLabel: '1 of 2',
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(GroupKeys.settleUpRecordSheetStepIndicator),
      findsOneWidget,
    );
    expect(find.text('1 of 2'), findsOneWidget);
  });

  testWidgets(
    '#382 PR-5: no step indicator when stepLabel is absent (single-tile path)',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    key: const Key('open'),
                    onPressed: () => showRecordPaymentSheet(
                      context,
                      currency: 'OMR',
                      fromName: 'Bob',
                      toName: 'Alice',
                      suggestedAmount: Decimal.parse('5.000'),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(GroupKeys.settleUpRecordSheetStepIndicator),
        findsNothing,
      );
    },
  );

  testWidgets('#282: receiving framing reads as "received" and names the payer '
      'in the banner', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  key: const Key('open'),
                  onPressed: () => showRecordPaymentSheet(
                    context,
                    currency: 'OMR',
                    fromName: 'Bob', // payer (debtor)
                    toName: 'Alice', // recipient (creditor) = current user
                    suggestedAmount: Decimal.parse('5.000'),
                    perspective: RecordPaymentPerspective.receiving,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();

    expect(find.text('Mark this received?'), findsOneWidget);
    expect(find.text('Mark received'), findsOneWidget);
    expect(find.text('Mark paid'), findsNothing);
    // Banner names the payer (Bob), not "your payment", and stays immediate.
    expect(
      find.text("This records Bob's payment to you immediately."),
      findsOneWidget,
    );
  });

  testWidgets(
    '#595: third-party "recording" framing is neutral — names BOTH parties, '
    'never "your"/"you"',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    key: const Key('open'),
                    onPressed: () => showRecordPaymentSheet(
                      context,
                      currency: 'OMR',
                      fromName: 'Bob', // payer (debtor)
                      toName: 'Alice', // recipient (creditor)
                      suggestedAmount: Decimal.parse('5.000'),
                      // Current user is neither Bob nor Alice — an organizer
                      // recording on the group's behalf.
                      perspective: RecordPaymentPerspective.recording,
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();

      expect(find.text('Record this payment?'), findsOneWidget);
      expect(find.text('Record'), findsOneWidget);
      // Neither the debtor nor the creditor framing leaks through.
      expect(find.text('Mark this paid?'), findsNothing);
      expect(find.text('Mark this received?'), findsNothing);
      // Banner names BOTH parties — no first/second-person ("your"/"you").
      expect(
        find.text("This records Bob's payment to Alice immediately."),
        findsOneWidget,
      );
    },
  );
}
