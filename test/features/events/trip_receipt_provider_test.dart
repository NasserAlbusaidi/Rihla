import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:safar/features/activity/models/activity_log_model.dart';
import 'package:safar/features/activity/services/activity_service.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/models/trip_receipt.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/events/providers/trip_receipt_provider.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';

class _MockActivityService extends Mock implements ActivityService {}

void main() {
  const ref = (groupId: 'g1', eventId: 'e1');

  ActivityLog log(String id, String type) => ActivityLog(
        id: id,
        tripId: 'e1',
        category: 'MONEY',
        eventType: type,
        logText: '',
        metadata: const {},
        createdAt: DateTime.utc(2026, 1, 1),
      );

  group('tripReceiptAuditProvider — coverage mapping + filter', () {
    late _MockActivityService mock;
    ProviderContainer container() {
      final c = ProviderContainer(
        overrides: [activityServiceProvider.overrideWithValue(mock)],
      );
      addTearDown(c.dispose);
      return c;
    }

    setUp(() => mock = _MockActivityService());

    Future<void> stub({
      required List<ActivityLog> logs,
      bool capHit = false,
      bool fromCacheEmpty = false,
    }) async {
      when(() => mock.fetchAllEventAuditLogs(any(), any(),
              cap: any(named: 'cap')))
          .thenAnswer((_) async =>
              (logs: logs, capHit: capHit, fromCacheEmpty: fromCacheEmpty));
    }

    test('clean → complete; CREATE filtered out, UPDATE/DELETE kept', () async {
      await stub(logs: [log('a', 'CREATE'), log('b', 'UPDATE'), log('c', 'DELETE')]);
      final res = await container().read(tripReceiptAuditProvider(ref).future);
      expect(res.coverage, AuditCoverage.complete);
      expect(res.corrections.map((l) => l.id), ['b', 'c']);
    });

    test('capHit → capped', () async {
      await stub(logs: [log('b', 'UPDATE')], capHit: true);
      final res = await container().read(tripReceiptAuditProvider(ref).future);
      expect(res.coverage, AuditCoverage.capped);
    });

    test('fromCacheEmpty → unverifiedOffline', () async {
      await stub(logs: const [], fromCacheEmpty: true);
      final res = await container().read(tripReceiptAuditProvider(ref).future);
      expect(res.coverage, AuditCoverage.unverifiedOffline);
    });

    test('fetch throws → unavailable (non-fatal, empty corrections)', () async {
      when(() => mock.fetchAllEventAuditLogs(any(), any(),
          cap: any(named: 'cap'))).thenThrow(Exception('boom'));
      final res = await container().read(tripReceiptAuditProvider(ref).future);
      expect(res.coverage, AuditCoverage.unavailable);
      expect(res.corrections, isEmpty);
    });
  });

  group('tripReceiptProvider — honest async gating', () {
    Event event({List<String> ids = const ['p1', 'p2']}) => Event(
          id: 'e1',
          name: 'Camp',
          type: EventType.camping,
          groupId: 'g1',
          createdBy: 'p1',
          participantIds: ids,
          participantNames: const {'p1': 'Ahmed', 'p2': 'Sara'},
          modules: const EventModules(),
          createdAt: DateTime.utc(2026, 1, 1),
        );

    Expense expense() => Expense(
          id: 'x1',
          tripId: 'e1',
          payerParticipantId: 'p1',
          amount: Decimal.parse('10.000'),
          scope: ExpenseScope.global,
          createdAt: DateTime.utc(2026, 1, 2),
          currency: 'OMR',
        );

    List<Override> overrides({
      Stream<Event?>? eventStream,
      Stream<List<Expense>>? expensesStream,
      Stream<List<GroupMember>>? membersStream,
    }) =>
        [
          eventDetailProvider.overrideWith(
              (r, a) => eventStream ?? Stream.value(event())),
          eventExpensesProvider.overrideWith(
              (r, a) => expensesStream ?? Stream.value([expense()])),
          eventSettlementsProvider.overrideWith(
              (r, a) => Stream.value(const <Settlement>[])),
          groupMembersProvider.overrideWith(
              (r, a) => membersStream ?? Stream.value(const <GroupMember>[])),
          tripReceiptAuditProvider.overrideWith((r, a) async =>
              (corrections: const <ActivityLog>[], coverage: AuditCoverage.complete)),
        ];

    test('all inputs data → AsyncData with the built receipt', () async {
      final c = ProviderContainer(overrides: overrides());
      addTearDown(c.dispose);
      // force the streams + audit future to resolve
      await c.read(eventExpensesProvider(ref).future);
      await c.read(eventSettlementsProvider(ref).future);
      await c.read(groupMembersProvider('g1').future);
      await c.read(tripReceiptAuditProvider(ref).future);
      await c.read(eventDetailProvider(ref).future);

      final result = c.read(tripReceiptProvider(ref));
      expect(result, isA<AsyncData<TripReceipt>>());
      expect(result.value!.expenses, hasLength(1));
    });

    test('one input still loading → AsyncLoading (no false-empty)', () async {
      // expenses never resolve while everything else is ready
      final c = ProviderContainer(
        overrides: overrides(
          expensesStream: Stream<List<Expense>>.fromFuture(
              Completer<List<Expense>>().future),
        ),
      );
      addTearDown(c.dispose);
      await c.read(eventSettlementsProvider(ref).future);
      await c.read(groupMembersProvider('g1').future);
      await c.read(tripReceiptAuditProvider(ref).future);
      await c.read(eventDetailProvider(ref).future);

      expect(c.read(tripReceiptProvider(ref)), isA<AsyncLoading>());
    });

    test('event doc null → AsyncLoading (no false-complete empty receipt)', () async {
      final c = ProviderContainer(
        overrides: overrides(eventStream: Stream<Event?>.value(null)),
      );
      addTearDown(c.dispose);
      await c.read(eventExpensesProvider(ref).future);
      await c.read(eventSettlementsProvider(ref).future);
      await c.read(groupMembersProvider('g1').future);
      await c.read(tripReceiptAuditProvider(ref).future);
      await c.read(eventDetailProvider(ref).future);

      expect(c.read(tripReceiptProvider(ref)), isA<AsyncLoading>());
    });

    test('required input error → AsyncError', () async {
      final c = ProviderContainer(
        overrides: overrides(
          expensesStream: Stream<List<Expense>>.error(Exception('read failed')),
        ),
      );
      addTearDown(c.dispose);
      await c.read(eventSettlementsProvider(ref).future);
      await c.read(groupMembersProvider('g1').future);
      await c.read(tripReceiptAuditProvider(ref).future);
      await c.read(eventDetailProvider(ref).future);
      // force the errored stream to surface (awaiting its future throws)
      try {
        await c.read(eventExpensesProvider(ref).future);
      } catch (_) {}

      expect(c.read(tripReceiptProvider(ref)), isA<AsyncError>());
    });

    test(
        '#1030 pin: members hard error → AsyncError (no members-less export); '
        'the gate predates #1030 — this pins it', () async {
      final c = ProviderContainer(
        overrides: overrides(
          membersStream:
              Stream<List<GroupMember>>.error(Exception('members failed')),
        ),
      );
      addTearDown(c.dispose);
      await c.read(eventSettlementsProvider(ref).future);
      await c.read(tripReceiptAuditProvider(ref).future);
      await c.read(eventDetailProvider(ref).future);
      await c.read(eventExpensesProvider(ref).future);
      try {
        await c.read(groupMembersProvider('g1').future);
      } catch (_) {}

      expect(c.read(tripReceiptProvider(ref)), isA<AsyncError>());
    });
  });
}
