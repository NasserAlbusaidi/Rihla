import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/groups/keys/group_keys.dart';
import 'package:safar/features/groups/widgets/settle_up_page_body.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// #283 — a recorded payment in the settle-up history exposes a "correct this"
/// affordance that, after a confirmation dialog, hands the original [Settlement]
/// back to the screen so it can record an offsetting reverse settlement
/// (append-only — the original row stays).

Widget _host(Widget body) {
  return ProviderScope(
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Scaffold(body: body),
      ),
    ),
  );
}

SettleUpPageBody _bodyWithHistory({
  void Function(Settlement settlement)? onCorrect,
  List<Settlement>? settlements,
}) {
  return SettleUpPageBody(
    scope: SettleScope.group,
    subjectName: 'Beach House',
    buckets: [
      (
        currency: 'OMR',
        optimalSettlements: const <Map<String, dynamic>>[],
        balances: [
          UserBalance(
            participantId: 'uid-ahmed',
            displayName: 'Ahmed',
            totalPaid: Decimal.parse('5.000'),
            totalOwed: Decimal.zero,
            netBalance: Decimal.parse('5.000'),
          ),
          UserBalance(
            participantId: 'uid-sara',
            displayName: 'Sara',
            totalPaid: Decimal.zero,
            totalOwed: Decimal.parse('5.000'),
            netBalance: Decimal.parse('-5.000'),
          ),
        ],
      ),
    ],
    rawNames: const {'uid-ahmed': 'Ahmed', 'uid-sara': 'Sara'},
    settlementsAsync: AsyncValue.data(
      settlements ??
          [
            Settlement(
              id: 's1',
              tripId: 'event-1',
              payerParticipantId: 'uid-ahmed',
              recipientParticipantId: 'uid-sara',
              amount: Decimal.parse('5.000'),
              settledAt: DateTime(2026, 6, 7),
              payerName: 'Ahmed',
              recipientName: 'Sara',
            ),
          ],
    ),
    currentUid: 'uid-ahmed',
    tileKeys: const {},
    onRecord:
        ({
          required settlement,
          required fromRawName,
          required toRawName,
          required fromUserId,
          required toUserId,
          required suggestedAmount,
          required String currency,
        }) {},
    onCorrect: onCorrect,
  );
}

void main() {
  testWidgets(
    'a history tile shows a correct affordance that confirms then fires onCorrect',
    (tester) async {
      Settlement? corrected;
      await tester.pumpWidget(
        _host(_bodyWithHistory(onCorrect: (s) => corrected = s)),
      );
      await tester.pumpAndSettle();

      final button = find.byKey(GroupKeys.settleUpCorrectButton);
      expect(button, findsOneWidget);

      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();

      // Confirmation dialog appears before any write.
      expect(find.text('Correct this payment?'), findsOneWidget);
      expect(corrected, isNull, reason: 'must not fire before confirmation');

      await tester.tap(find.text('Record correction'));
      await tester.pumpAndSettle();

      expect(corrected, isNotNull);
      expect(corrected!.id, 's1');
    },
  );

  testWidgets('cancelling the correction dialog does not fire onCorrect', (
    tester,
  ) async {
    Settlement? corrected;
    await tester.pumpWidget(
      _host(_bodyWithHistory(onCorrect: (s) => corrected = s)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(GroupKeys.settleUpCorrectButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(corrected, isNull);
  });

  testWidgets('the correct affordance is hidden when onCorrect is null', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_bodyWithHistory(onCorrect: null)));
    await tester.pumpAndSettle();

    expect(find.byKey(GroupKeys.settleUpCorrectButton), findsNothing);
  });

  // Friction audit tranche 2: for a high-stakes money correction, a
  // tooltip-only icon is invisible on touch — the affordance must carry a
  // visible text label, not rely on icon-shape recognition.
  testWidgets('the correct affordance shows a visible "Correct" label', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_bodyWithHistory(onCorrect: (_) {})));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(GroupKeys.settleUpCorrectButton),
        matching: find.text('Correct'),
      ),
      findsOneWidget,
    );
  });

  // The labelled control is wider than the old 36px icon; the history tile's
  // name column is Expanded+ellipsis but the amount is fixed-width, so guard
  // a narrow phone with long Arabic names against RenderFlex overflow.
  testWidgets(
    'history tile with long names + correct + share fits a 320px screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _host(
          _bodyWithHistory(
            onCorrect: (_) {},
            settlements: [
              Settlement(
                id: 's-long',
                tripId: 'event-1',
                payerParticipantId: 'uid-ahmed',
                recipientParticipantId: 'uid-sara',
                amount: Decimal.parse('12345.678'),
                settledAt: DateTime(2026, 6, 7),
                payerName: 'عبدالرحمن بن عبدالعزيز الهنائي',
                recipientName: 'مريم بنت سليمان البوسعيدية',
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(GroupKeys.settleUpCorrectButton), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  // #567: a reversing correction must read as a CORRECTION in Payment history,
  // not as another (duplicate) payment. The row carries the persisted
  // `settleUpCorrectionNote` sentinel; the tile surfaces it as a "Correction"
  // label + reversal icon. A plain payment row stays unlabelled.
  testWidgets(
    'a correction row is labelled "Correction"; a plain payment is not',
    (tester) async {
      await tester.pumpWidget(
        _host(
          _bodyWithHistory(
            settlements: [
              // Plain payment — Ahmed paid Sara (a normal note).
              Settlement(
                id: 'orig',
                tripId: 'event-1',
                payerParticipantId: 'uid-ahmed',
                recipientParticipantId: 'uid-sara',
                amount: Decimal.parse('5.000'),
                settledAt: DateTime(2026, 6, 7),
                payerName: 'Ahmed',
                recipientName: 'Sara',
                note: 'dinner',
                scope: 'group',
              ),
              // Reversal — recorded via #283 (the offsetting correction).
              Settlement(
                id: 'corr',
                tripId: 'event-1',
                payerParticipantId: 'uid-sara',
                recipientParticipantId: 'uid-ahmed',
                amount: Decimal.parse('5.000'),
                settledAt: DateTime(2026, 6, 8),
                payerName: 'Sara',
                recipientName: 'Ahmed',
                note: 'Correction of a recorded payment',
                scope: 'group',
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Exactly the reversal row carries the label (the plain payment does not).
      expect(find.text('Correction'), findsOneWidget);
      // Both directions still render as receipts (append-only — original stays).
      expect(
        find.textContaining('Ahmed', findRichText: true),
        findsWidgets,
      );
    },
  );
}
