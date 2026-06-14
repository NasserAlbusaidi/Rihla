import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/models/split_mode.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/services/pre_settlement_review.dart';
import 'package:safar/features/ledger/widgets/pre_settlement_review_sheet.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// #204 — the pre-settlement review sheet renders grouped counts + the top
/// review-worthy expenses, is non-blocking (Continue dismisses), and routes via
/// callbacks (Review / per-item tap).

Expense _exp({
  required String id,
  String? description,
  String amount = '5.000',
  ExpenseScope scope = ExpenseScope.global,
  SplitMode? splitMode = SplitMode.equally,
}) => Expense(
  id: id,
  tripId: 'event-1',
  payerParticipantId: 'uid-a',
  amount: Decimal.parse(amount),
  scope: scope,
  splitMode: splitMode,
  createdAt: DateTime(2026, 6, 1),
  description: description ?? id,
);

Widget _host({
  required List<ReviewFlag> flags,
  void Function(Expense)? onTapExpense,
  VoidCallback? onReviewAll,
}) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => showPreSettlementReviewSheet(
              context,
              flags: flags,
              onTapExpense: onTapExpense ?? (_) {},
              onReviewAll: onReviewAll ?? () {},
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders title, grouped counts, and dismisses on Continue', (
    tester,
  ) async {
    final flags = detectReviewWorthyExpenses([
      _exp(id: 'a', description: 'Breakfast', splitMode: SplitMode.exact),
      _exp(id: 'b', description: 'Coke', scope: ExpenseScope.personal),
    ]);

    await tester.pumpWidget(_host(flags: flags));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byKey(PreSettleReviewKeys.sheet), findsOneWidget);
    expect(find.text('Before you settle'), findsOneWidget);
    expect(find.text('1 exact split'), findsOneWidget);
    expect(find.text('1 personal expense'), findsOneWidget);
    expect(find.text('Breakfast'), findsOneWidget);

    await tester.tap(find.byKey(PreSettleReviewKeys.continueButton));
    await tester.pumpAndSettle();
    expect(find.byKey(PreSettleReviewKeys.sheet), findsNothing);
  });

  testWidgets('Review expenses fires onReviewAll and closes', (tester) async {
    var reviewed = false;
    final flags = detectReviewWorthyExpenses([
      _exp(id: 'a', splitMode: SplitMode.exact),
      _exp(id: 'b'),
    ]);

    await tester.pumpWidget(_host(flags: flags, onReviewAll: () => reviewed = true));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(PreSettleReviewKeys.reviewButton));
    await tester.pumpAndSettle();

    expect(reviewed, isTrue);
    expect(find.byKey(PreSettleReviewKeys.sheet), findsNothing);
  });

  testWidgets('tapping an item fires onTapExpense with that expense', (
    tester,
  ) async {
    Expense? tapped;
    final flags = detectReviewWorthyExpenses([
      _exp(id: 'villa', description: 'Villa', amount: '120.000'),
      _exp(id: 'coffee', description: 'Coffee', amount: '2.000'),
      _exp(id: 'snack', description: 'Snack', amount: '3.000'),
    ]);

    await tester.pumpWidget(_host(flags: flags, onTapExpense: (e) => tapped = e));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Villa'));
    await tester.pumpAndSettle();

    expect(tapped?.id, 'villa');
    expect(find.byKey(PreSettleReviewKeys.sheet), findsNothing);
  });
}
