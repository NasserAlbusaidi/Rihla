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

// #753 — the group-screen settle-up history REGROUPS a groupSettleUpId-tagged
// set into ONE logical row (total = Σ of the originals) carrying the atomic
// logical-correct affordance; once corrected the row hides the button. The event
// screen (no onCorrectLogical) keeps PR1 per-doc rendering.

const String note = 'Correction of a recorded payment'; // en sentinel

Widget _host(Widget body) => ProviderScope(
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

Settlement _tagged(
  String id, {
  required String x,
  required String amount,
  String? settlementNote,
  DateTime? at,
  String payer = 'uid-sara',
  String recipient = 'uid-ahmed',
}) =>
    Settlement(
      id: id,
      tripId: 'event-1',
      payerParticipantId: payer,
      recipientParticipantId: recipient,
      amount: Decimal.parse(amount),
      currency: 'OMR',
      settledAt: at ?? DateTime(2026, 6, 29),
      payerName: 'Sara',
      recipientName: 'Ahmed',
      note: settlementNote,
      groupSettleUpId: x,
    );

SettleUpPageBody _body({
  required List<Settlement> settlements,
  void Function(String groupSettleUpId)? onCorrectLogical,
  void Function(Settlement settlement)? onCorrect,
}) =>
    SettleUpPageBody(
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
              totalPaid: Decimal.zero,
              totalOwed: Decimal.zero,
              netBalance: Decimal.zero,
            ),
            UserBalance(
              participantId: 'uid-sara',
              displayName: 'Sara',
              totalPaid: Decimal.zero,
              totalOwed: Decimal.zero,
              netBalance: Decimal.zero,
            ),
          ],
        ),
      ],
      rawNames: const {'uid-ahmed': 'Ahmed', 'uid-sara': 'Sara'},
      settlementsAsync: AsyncValue.data(settlements),
      currentUid: 'uid-ahmed',
      tileKeys: const {},
      onRecord: ({
        required settlement,
        required fromRawName,
        required toRawName,
        required fromUserId,
        required toUserId,
        required suggestedAmount,
        required String currency,
      }) {},
      onCorrect: onCorrect,
      onCorrectLogical: onCorrectLogical,
    );

void main() {
  testWidgets('a tagged multi-doc set renders ONE row with the total + button',
      (tester) async {
    String? correctedId;
    await tester.pumpWidget(
      _host(
        _body(
          settlements: [
            _tagged('e1', x: 'X', amount: '3.000'),
            _tagged('e2', x: 'X', amount: '4.000'),
          ],
          onCorrectLogical: (id) => correctedId = id,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Regrouped: one row at the total (3+4), NOT the per-event slices.
    // #1201: the history row's amount is RAmount (fragmented RichText spans),
    // so exact/substring text finders must traverse RichText — including the
    // absence assertions, or a regression rendering these values via RichText
    // would silently pass the plain finder.
    expect(find.textContaining('OMR 7.000', findRichText: true), findsOneWidget);
    expect(find.textContaining('OMR 3.000', findRichText: true), findsNothing);
    expect(find.textContaining('OMR 4.000', findRichText: true), findsNothing);

    final button = find.byKey(GroupKeys.settleUpCorrectButton);
    expect(button, findsOneWidget);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    // Confirm dialog shows the logical total.
    expect(
      find.textContaining('OMR 7.000', findRichText: true),
      findsWidgets,
    );
    await tester.tap(find.text('Record correction'));
    await tester.pumpAndSettle();

    expect(correctedId, 'X');
  });

  testWidgets('a corrected tagged set shows one row, NO correct button',
      (tester) async {
    await tester.pumpWidget(
      _host(
        _body(
          settlements: [
            _tagged('e1', x: 'X', amount: '5.000'),
            _tagged('e1-rev',
                x: 'X',
                amount: '5.000',
                settlementNote: note,
                payer: 'uid-ahmed',
                recipient: 'uid-sara',
                at: DateTime(2026, 6, 30)),
          ],
          onCorrectLogical: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(GroupKeys.settleUpCorrectButton), findsNothing,
        reason: 'idempotency: a corrected logical row hides the affordance');
    expect(find.text('Correction'), findsOneWidget);
    expect(
      find.textContaining('OMR 5.000', findRichText: true),
      findsOneWidget,
      reason: 'one regrouped row at the original total',
    );
  });

  testWidgets('event-screen path (no onCorrectLogical) does NOT regroup',
      (tester) async {
    await tester.pumpWidget(
      _host(
        _body(
          settlements: [
            _tagged('e1', x: 'X', amount: '3.000'),
            _tagged('e2', x: 'X', amount: '2.000'),
          ],
          // onCorrectLogical null → PR1 per-doc rendering; tagged docs keep
          // their single-doc correct button HIDDEN.
          onCorrect: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('OMR 3.000', findRichText: true), findsOneWidget);
    expect(find.textContaining('OMR 2.000', findRichText: true), findsOneWidget);
    expect(
      find.textContaining('OMR 6.000', findRichText: true),
      findsNothing,
      reason: 'no regroup',
    );
    expect(find.byKey(GroupKeys.settleUpCorrectButton), findsNothing,
        reason: 'tagged docs keep the PR1 single-doc hide-guard');
  });
}
