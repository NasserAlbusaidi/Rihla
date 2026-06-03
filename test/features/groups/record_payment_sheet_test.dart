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
// dismiss) and performs NO validation. That contract — never exercised in
// isolation — is what these tests pin, including the deliberate absence of
// validation (so the caller stays responsible for it).
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

  Future<void> tapMarkPaid(WidgetTester tester) =>
      tester.tap(find.byKey(GroupKeys.markAsPaidButton));

  testWidgets('confirm returns the seeded amount, empty note, cash by default', (
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
    expect(result.method, PaymentMethod.cash);
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

  testWidgets('selecting a payment method flows into the result', (
    tester,
  ) async {
    final result = await openAndReturn(
      tester,
      currency: 'OMR',
      suggestedAmount: Decimal.parse('7.750'),
      act: (t) async {
        await t.tap(find.text('Bank'));
        await t.pump();
        await tapMarkPaid(t);
      },
    );

    expect(result!.method, PaymentMethod.bank);
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
}
