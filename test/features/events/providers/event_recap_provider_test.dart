import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/models/event_recap.dart';
import 'package:safar/features/events/models/spending_snapshot.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/events/providers/event_recap_provider.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/ledger/providers/ledger_view_provider.dart';

/// Slice 6 of #202 — the provider's freeze branch: a closed event with a
/// `spendingSnapshot` serves frozen spending while settlement stays live.
void main() {
  const eventRef = (groupId: 'g1', eventId: 'e1');
  Decimal d(String s) => Decimal.parse(s);

  UserBalance ub(String id, String paid, String owed, String net) =>
      UserBalance(
        participantId: id,
        displayName: id,
        totalPaid: d(paid),
        totalOwed: d(owed),
        netBalance: d(net),
      );

  // Frozen at close: total 100, 2 people, a paid 100, a/b each owed 50.
  SpendingSnapshot frozen() => SpendingSnapshot.fromMap(const {
        'v': 1,
        'participantCount': 2,
        'expenseCount': 1,
        'totals': {'OMR': 100000},
        'biggest': {
          'OMR': {'id': 'e1', 'amt': 100000, 'payer': 'a'}
        },
        'payers': {
          'OMR': [
            {'id': 'a', 'amt': 100000}
          ]
        },
        'categories': {
          'OMR': [
            {'cat': 'food', 'amt': 100000}
          ]
        },
        'owed': {
          'OMR': {'a': 50000, 'b': 50000}
        },
      });

  Event evt({bool closed = false, SpendingSnapshot? snap}) => Event(
        id: 'e1',
        name: 'Trip',
        type: EventType.trip,
        groupId: 'g1',
        createdBy: 'a',
        participantIds: const ['a', 'b'],
        participantNames: const {'a': 'A', 'b': 'B'},
        modules: const EventModules(),
        createdAt: DateTime(2026, 1, 1),
        isClosed: closed,
        spendingSnapshot: snap,
      );

  // LIVE view: total DRIFTED to 999; balances now SETTLED (both net 0).
  LedgerView liveView() => (
        participants: const [],
        balances: {
          'OMR': [ub('a', '100', '50', '0'), ub('b', '0', '50', '0')],
        },
        eventTotal: {'OMR': d('999')},
        rosterDisplayNames: const {},
        expensePayerDisplayNames: const {},
        settlementDisplayNames: const {},
        owedByExpenseId: const {},
      );

  ProviderContainer containerFor(Event event) {
    final c = ProviderContainer(overrides: [
      eventDetailProvider(eventRef).overrideWith((ref) => Stream.value(event)),
      ledgerViewProvider(eventRef).overrideWithValue(liveView()),
      eventExpensesProvider(eventRef)
          .overrideWith((ref) => Stream.value(const <Expense>[])),
      currentUserIdProvider.overrideWithValue('a'),
    ]);
    return c;
  }

  Future<EventRecap> recapFor(Event event) async {
    final c = containerFor(event);
    addTearDown(c.dispose);
    await c.read(eventDetailProvider(eventRef).future); // settle the stream
    return c.read(eventRecapProvider(eventRef));
  }

  test('open event → LIVE recap (total from live view = 999)', () async {
    final r = await recapFor(evt());
    expect(r.totalSpentByCurrency['OMR'], d('999'));
  });

  test('closed + snapshot → FROZEN spending (100) + LIVE settlement (settled)',
      () async {
    final r = await recapFor(evt(closed: true, snap: frozen()));
    expect(r.totalSpentByCurrency['OMR'], d('100')); // frozen, not the live 999
    expect(r.participantCount, 2);
    expect(r.userPaidByCurrency['OMR'], d('100')); // frozen
    expect(r.userShareByCurrency['OMR'], d('50')); // frozen
    expect(r.payerTotalsByCurrency['OMR']!.first.amount, d('100')); // frozen
    expect(r.userNetByCurrency['OMR'], d('0')); // LIVE
    expect(r.isSettledByCurrency['OMR'], isTrue); // LIVE (settled post-close)
  });

  test('closed WITHOUT snapshot → LIVE recap (legacy/empty close, unchanged)',
      () async {
    final r = await recapFor(evt(closed: true, snap: null));
    expect(r.totalSpentByCurrency['OMR'], d('999')); // live
  });
}
