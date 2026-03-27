import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

/// Build a minimal [Expense] for testing.
Expense _makeExpense({
  required String id,
  required String tripId,
  required String payerParticipantId,
  required Decimal amount,
}) {
  return Expense(
    id: id,
    tripId: tripId,
    payerParticipantId: payerParticipantId,
    amount: amount,
    scope: ExpenseScope.global,
    createdAt: DateTime(2026, 1, 1),
  );
}

/// Build a minimal [Settlement] for testing.
Settlement _makeSettlement({
  required String id,
  required String tripId,
  required String payerParticipantId,
  required String recipientParticipantId,
  required Decimal amount,
}) {
  return Settlement(
    id: id,
    tripId: tripId,
    payerParticipantId: payerParticipantId,
    recipientParticipantId: recipientParticipantId,
    amount: amount,
    settledAt: DateTime(2026, 1, 2),
    scope: 'event',
  );
}

/// Build a minimal [Event] for testing.
Event _makeEvent({
  required String id,
  required String groupId,
  List<String>? participantIds,
  Map<String, String>? participantNames,
}) {
  return Event(
    id: id,
    name: 'Event $id',
    type: EventType.trip,
    groupId: groupId,
    createdBy: 'uid-1',
    participantIds: participantIds ?? [],
    participantNames: participantNames ?? {},
    modules: const EventModules(),
    createdAt: DateTime(2026, 1, 1),
  );
}

/// Pump the event loop multiple times to resolve cascaded stream providers.
///
/// StreamProvider.family with Stream.value delivers asynchronously.
/// Using Future.delayed(Duration.zero) yields to the event loop (not just
/// the microtask queue) which is required for Riverpod stream delivery
/// per Phase 5 convention (STATE.md).
Future<void> _pumpAsync() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  // ---------------------------------------------------------------------------
  // eventExpensesProvider isolation tests
  // ---------------------------------------------------------------------------

  group('eventExpensesProvider', () {
    const groupId = 'grp-1';
    const eventId = 'evt-1';
    const eventRef = (groupId: groupId, eventId: eventId);

    test('emits expense list from stream override', () async {
      final testExpenses = [
        _makeExpense(
          id: 'exp-1',
          tripId: eventId,
          payerParticipantId: 'uid-1',
          amount: Decimal.parse('10.500'),
        ),
        _makeExpense(
          id: 'exp-2',
          tripId: eventId,
          payerParticipantId: 'uid-2',
          amount: Decimal.parse('5.000'),
        ),
      ];

      final container = ProviderContainer(
        overrides: [
          eventExpensesProvider(eventRef).overrideWith(
            (_) => Stream.value(testExpenses),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.listen(
        eventExpensesProvider(eventRef),
        (_, __) {},
        fireImmediately: true,
      );
      await _pumpAsync();

      final result = container.read(eventExpensesProvider(eventRef));
      expect(result, isA<AsyncData<List<Expense>>>());
      expect(result.value, equals(testExpenses));
      expect(result.value, hasLength(2));
    });

    test('emits empty list when no expenses exist', () async {
      final container = ProviderContainer(
        overrides: [
          eventExpensesProvider(eventRef).overrideWith(
            (_) => Stream.value(<Expense>[]),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.listen(
        eventExpensesProvider(eventRef),
        (_, __) {},
        fireImmediately: true,
      );
      await _pumpAsync();

      final result = container.read(eventExpensesProvider(eventRef));
      expect(result, isA<AsyncData<List<Expense>>>());
      expect(result.value, isEmpty);
    });

    test('returns AsyncLoading before stream emits', () {
      final controller = StreamController<List<Expense>>.broadcast();

      final container = ProviderContainer(
        overrides: [
          eventExpensesProvider(eventRef).overrideWith(
            (_) => controller.stream,
          ),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(controller.close);

      // Synchronous read before stream emits — must be loading
      final result = container.read(eventExpensesProvider(eventRef));
      expect(result, isA<AsyncLoading<List<Expense>>>());
    });

    test('isolates different event keys independently', () async {
      const ref1 = (groupId: groupId, eventId: 'evt-a');
      const ref2 = (groupId: groupId, eventId: 'evt-b');

      final expensesA = [
        _makeExpense(
          id: 'exp-a',
          tripId: 'evt-a',
          payerParticipantId: 'uid-1',
          amount: Decimal.parse('20.000'),
        ),
      ];
      final expensesB = [
        _makeExpense(
          id: 'exp-b1',
          tripId: 'evt-b',
          payerParticipantId: 'uid-2',
          amount: Decimal.parse('30.000'),
        ),
        _makeExpense(
          id: 'exp-b2',
          tripId: 'evt-b',
          payerParticipantId: 'uid-3',
          amount: Decimal.parse('10.000'),
        ),
      ];

      final container = ProviderContainer(
        overrides: [
          eventExpensesProvider(ref1).overrideWith(
            (_) => Stream.value(expensesA),
          ),
          eventExpensesProvider(ref2).overrideWith(
            (_) => Stream.value(expensesB),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.listen(eventExpensesProvider(ref1), (_, __) {}, fireImmediately: true);
      container.listen(eventExpensesProvider(ref2), (_, __) {}, fireImmediately: true);
      await _pumpAsync();

      final resultA = container.read(eventExpensesProvider(ref1));
      final resultB = container.read(eventExpensesProvider(ref2));

      expect(resultA.value, hasLength(1));
      expect(resultA.value!.first.id, equals('exp-a'));
      expect(resultB.value, hasLength(2));
    });
  });

  // ---------------------------------------------------------------------------
  // groupEventsProvider isolation tests
  // ---------------------------------------------------------------------------

  group('groupEventsProvider', () {
    const groupId = 'grp-1';

    test('emits event list from stream override', () async {
      final testEvents = [
        _makeEvent(
          id: 'evt-1',
          groupId: groupId,
          participantIds: ['uid-1', 'uid-2'],
        ),
        _makeEvent(
          id: 'evt-2',
          groupId: groupId,
          participantIds: ['uid-1'],
        ),
      ];

      final container = ProviderContainer(
        overrides: [
          groupEventsProvider(groupId).overrideWith(
            (_) => Stream.value(testEvents),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.listen(
        groupEventsProvider(groupId),
        (_, __) {},
        fireImmediately: true,
      );
      await _pumpAsync();

      final result = container.read(groupEventsProvider(groupId));
      expect(result, isA<AsyncData<List<Event>>>());
      expect(result.value, hasLength(2));
      expect(result.value!.first.id, equals('evt-1'));
    });

    test('emits empty list when group has no events', () async {
      final container = ProviderContainer(
        overrides: [
          groupEventsProvider(groupId).overrideWith(
            (_) => Stream.value(<Event>[]),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.listen(
        groupEventsProvider(groupId),
        (_, __) {},
        fireImmediately: true,
      );
      await _pumpAsync();

      final result = container.read(groupEventsProvider(groupId));
      expect(result, isA<AsyncData<List<Event>>>());
      expect(result.value, isEmpty);
    });

    test('different group IDs use independent streams', () async {
      final eventsG1 = [_makeEvent(id: 'evt-g1', groupId: 'grp-1')];
      final eventsG2 = [
        _makeEvent(id: 'evt-g2a', groupId: 'grp-2'),
        _makeEvent(id: 'evt-g2b', groupId: 'grp-2'),
      ];

      final container = ProviderContainer(
        overrides: [
          groupEventsProvider('grp-1').overrideWith(
            (_) => Stream.value(eventsG1),
          ),
          groupEventsProvider('grp-2').overrideWith(
            (_) => Stream.value(eventsG2),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.listen(groupEventsProvider('grp-1'), (_, __) {}, fireImmediately: true);
      container.listen(groupEventsProvider('grp-2'), (_, __) {}, fireImmediately: true);
      await _pumpAsync();

      final result1 = container.read(groupEventsProvider('grp-1'));
      final result2 = container.read(groupEventsProvider('grp-2'));

      expect(result1.value, hasLength(1));
      expect(result2.value, hasLength(2));
    });
  });

  // ---------------------------------------------------------------------------
  // eventSettlementsProvider isolation tests
  // ---------------------------------------------------------------------------

  group('eventSettlementsProvider', () {
    const groupId = 'grp-1';
    const eventId = 'evt-1';
    const eventRef = (groupId: groupId, eventId: eventId);

    test('emits settlement list from stream override', () async {
      final testSettlements = [
        _makeSettlement(
          id: 's1',
          tripId: eventId,
          payerParticipantId: 'uid-2',
          recipientParticipantId: 'uid-1',
          amount: Decimal.parse('10.000'),
        ),
      ];

      final container = ProviderContainer(
        overrides: [
          eventSettlementsProvider(eventRef).overrideWith(
            (_) => Stream.value(testSettlements),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.listen(
        eventSettlementsProvider(eventRef),
        (_, __) {},
        fireImmediately: true,
      );
      await _pumpAsync();

      final result = container.read(eventSettlementsProvider(eventRef));
      expect(result, isA<AsyncData<List<Settlement>>>());
      expect(result.value, hasLength(1));
      expect(result.value!.first.id, equals('s1'));
    });

    test('emits empty list when no settlements exist', () async {
      final container = ProviderContainer(
        overrides: [
          eventSettlementsProvider(eventRef).overrideWith(
            (_) => Stream.value(<Settlement>[]),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.listen(
        eventSettlementsProvider(eventRef),
        (_, __) {},
        fireImmediately: true,
      );
      await _pumpAsync();

      final result = container.read(eventSettlementsProvider(eventRef));
      expect(result, isA<AsyncData<List<Settlement>>>());
      expect(result.value, isEmpty);
    });

    test('multiple settlements for an event all delivered', () async {
      final testSettlements = [
        _makeSettlement(
          id: 's1',
          tripId: eventId,
          payerParticipantId: 'uid-2',
          recipientParticipantId: 'uid-1',
          amount: Decimal.parse('5.000'),
        ),
        _makeSettlement(
          id: 's2',
          tripId: eventId,
          payerParticipantId: 'uid-3',
          recipientParticipantId: 'uid-1',
          amount: Decimal.parse('8.500'),
        ),
        _makeSettlement(
          id: 's3',
          tripId: eventId,
          payerParticipantId: 'uid-3',
          recipientParticipantId: 'uid-2',
          amount: Decimal.parse('2.000'),
        ),
      ];

      final container = ProviderContainer(
        overrides: [
          eventSettlementsProvider(eventRef).overrideWith(
            (_) => Stream.value(testSettlements),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.listen(
        eventSettlementsProvider(eventRef),
        (_, __) {},
        fireImmediately: true,
      );
      await _pumpAsync();

      final result = container.read(eventSettlementsProvider(eventRef));
      expect(result.value, hasLength(3));
      expect(
        result.value!.map((s) => s.id).toList(),
        containsAll(['s1', 's2', 's3']),
      );
    });

    test('returns AsyncLoading before stream emits', () {
      final controller = StreamController<List<Settlement>>.broadcast();

      final container = ProviderContainer(
        overrides: [
          eventSettlementsProvider(eventRef).overrideWith(
            (_) => controller.stream,
          ),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(controller.close);

      final result = container.read(eventSettlementsProvider(eventRef));
      expect(result, isA<AsyncLoading<List<Settlement>>>());
    });
  });
}
