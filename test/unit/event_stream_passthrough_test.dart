import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/ledger/services/expense_service.dart';
import 'package:safar/features/ledger/services/settlement_service.dart';

class _MockExpenseService extends Mock implements ExpenseService {}

class _MockSettlementService extends Mock implements SettlementService {}

/// Issue #50: the SQLite side-write was removed, so [eventExpensesProvider] /
/// [eventSettlementsProvider] now pass the Firestore service stream straight
/// through. These tests override the SERVICE providers (not the stream
/// providers) so they exercise the default provider implementation that the
/// removal changed — the gap Gate Round 2 flagged.
void main() {
  const eventRef = (groupId: 'g1', eventId: 'e1');

  Future<void> pump() => Future<void>.delayed(Duration.zero);

  test('eventExpensesProvider emits the service stream unchanged', () async {
    final expenses = [
      Expense(
        id: 'exp-1',
        tripId: 'e1',
        payerParticipantId: 'uid-1',
        amount: Decimal.parse('10.500'),
        scope: ExpenseScope.global,
        createdAt: DateTime(2026, 1, 1),
      ),
    ];
    final service = _MockExpenseService();
    when(() => service.watchExpenses('g1', 'e1'))
        .thenAnswer((_) => Stream.value(expenses));

    final container = ProviderContainer(
      overrides: [expenseServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);
    container.listen(eventExpensesProvider(eventRef), (_, _) {},
        fireImmediately: true);
    await pump();

    final result = container.read(eventExpensesProvider(eventRef));
    expect(result, isA<AsyncData<List<Expense>>>());
    expect(result.value, same(expenses));
    verify(() => service.watchExpenses('g1', 'e1')).called(1);
  });

  test('eventSettlementsProvider emits the service stream unchanged', () async {
    final settlements = [
      Settlement(
        id: 'set-1',
        tripId: 'e1',
        payerParticipantId: 'uid-1',
        recipientParticipantId: 'uid-2',
        amount: Decimal.parse('3.000'),
        settledAt: DateTime(2026, 1, 2),
        scope: 'event',
      ),
    ];
    final service = _MockSettlementService();
    when(() => service.watchSettlements('g1', 'e1'))
        .thenAnswer((_) => Stream.value(settlements));

    final container = ProviderContainer(
      overrides: [settlementServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);
    container.listen(eventSettlementsProvider(eventRef), (_, _) {},
        fireImmediately: true);
    await pump();

    final result = container.read(eventSettlementsProvider(eventRef));
    expect(result, isA<AsyncData<List<Settlement>>>());
    expect(result.value, same(settlements));
    verify(() => service.watchSettlements('g1', 'e1')).called(1);
  });
}
