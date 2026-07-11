import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/groups/keys/group_keys.dart';
import 'package:safar/features/groups/widgets/all_settled_state.dart';
import 'package:safar/features/groups/widgets/settle_up_page_body.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// #1149 surface (b)+(d): settle-up suggestions naming a leave/remove-departed
/// party are pruned from the TILE list (rules would deny the write) while the
/// headline/summary/balances keep the UNPRUNED truth (R1 money is real), and
/// the Correct affordance hides when a recorded settlement's party left.
/// Ghosts (deleteAccount tombstones) are IN memberIds and stay offerable.
void main() {
  const bob = 'bob';
  const departed = 'uid-departed';
  const ghost = 'deleted-ghost1';

  Map<String, dynamic> pair(String from, String to, String amount) => {
    'fromUserId': from,
    'toUserId': to,
    'fromUserName': from,
    'toUserName': to,
    'amount': Decimal.parse(amount),
  };

  group('filterDepartedSuggestions (pure)', () {
    test('prunes a departed pair, keeps a ghost pair, counts hidden', () {
      final input = [pair(bob, departed, '4.000'), pair(bob, ghost, '2.000')];
      final out = filterDepartedSuggestions(input, {bob, ghost});
      expect(out.kept, hasLength(1));
      expect(out.kept.single['toUserId'], ghost);
      expect(out.hiddenCount, 1);
    });

    test('null memberIds set → unchanged, nothing hidden (fail-open)', () {
      final input = [pair(bob, departed, '4.000')];
      final out = filterDepartedSuggestions(input, null);
      expect(out.kept, same(input));
      expect(out.hiddenCount, 0);
    });

    test('EMPTY memberIds set fails open too — a real group is never '
        'memberless, empty means malformed/fixture data', () {
      final input = [pair(bob, departed, '4.000')];
      final out = filterDepartedSuggestions(input, const {});
      expect(out.kept, same(input));
      expect(out.hiddenCount, 0);
    });
  });

  Widget wrap(Widget child) => ProviderScope(
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Scaffold(body: child),
      ),
    ),
  );

  SettleUpPageBody body({
    required List<Map<String, dynamic>> suggestions,
    Set<String>? currentMemberIds,
    List<Settlement> history = const [],
    void Function(Settlement)? onCorrect,
  }) => SettleUpPageBody(
    scope: SettleScope.group,
    subjectName: 'Camp',
    buckets: [
      (
        currency: 'OMR',
        optimalSettlements: suggestions,
        balances: [
          UserBalance(
            participantId: departed,
            displayName: 'Aisha (former member)',
            totalPaid: Decimal.parse('30.000'),
            totalOwed: Decimal.parse('10.000'),
            netBalance: Decimal.parse('20.000'),
          ),
        ],
      ),
    ],
    rawNames: const {bob: 'Bob', departed: 'Aisha', ghost: 'Deleted member'},
    settlementsAsync: AsyncValue.data(history),
    currentUid: bob,
    currentMemberIds: currentMemberIds,
    tileKeys: <int, GlobalKey>{},
    onCorrect: onCorrect,
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
  );

  Settlement recorded({required String recipient}) => Settlement(
    id: 'sd1',
    tripId: 'event-1',
    payerParticipantId: bob,
    recipientParticipantId: recipient,
    amount: Decimal.parse('4.000'),
    currency: 'OMR',
    settledAt: DateTime(2026, 7, 1),
  );

  testWidgets(
    'departed sole suggestion: tile pruned, counted note shown, headline/'
    'balances keep the unpruned truth, never "All settled"',
    (tester) async {
      await tester.pumpWidget(
        wrap(
          body(
            suggestions: [pair(bob, departed, '4.000')],
            currentMemberIds: const {bob, ghost},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(GroupKeys.settleUpRecordPaymentButton),
        findsNothing,
      );
      expect(
        find.text(
          '1 suggestion involving a former member is hidden — '
          'that transfer can no longer be recorded.',
        ),
        findsOneWidget,
      );
      // Unpruned aggregates: headline still counts the departed pair and the
      // R1 balance row stays visible — pruning must never claim settled.
      expect(find.textContaining('One transfer'), findsOneWidget);
      expect(find.text('Aisha (former member)'), findsOneWidget);
      expect(find.byType(AllSettledState), findsNothing);
    },
  );

  testWidgets('ghost pair stays offerable, no note', (tester) async {
    await tester.pumpWidget(
      wrap(
        body(
          suggestions: [pair(bob, ghost, '2.000')],
          currentMemberIds: const {bob, ghost},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(GroupKeys.settleUpRecordPaymentButton), findsOneWidget);
    expect(find.textContaining('former members are hidden'), findsNothing);
    expect(find.textContaining('is hidden'), findsNothing);
  });

  testWidgets('null currentMemberIds fails open: tile kept, no note', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(body(suggestions: [pair(bob, departed, '4.000')])),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(GroupKeys.settleUpRecordPaymentButton), findsOneWidget);
    expect(find.textContaining('is hidden'), findsNothing);
  });

  testWidgets('Correct hides on a departed-party settlement', (tester) async {
    await tester.pumpWidget(
      wrap(
        body(
          suggestions: const [],
          currentMemberIds: const {bob, ghost},
          history: [recorded(recipient: departed)],
          onCorrect: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(GroupKeys.settleUpCorrectButton), findsNothing);
  });

  testWidgets('Correct stays on a ghost-party settlement', (tester) async {
    await tester.pumpWidget(
      wrap(
        body(
          suggestions: const [],
          currentMemberIds: const {bob, ghost},
          history: [recorded(recipient: ghost)],
          onCorrect: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(GroupKeys.settleUpCorrectButton), findsOneWidget);
  });
}
