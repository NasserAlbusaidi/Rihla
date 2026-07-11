import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/keys/group_keys.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/screens/group_settle_up_screen.dart';
import 'package:safar/features/groups/services/group_settlement_service.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/ledger/services/settlement_service.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

import '../../helpers/recording_functions_service.dart';

// #1106: unlike the #719 revalidation tests, these use the REAL
// groupBalancesProvider — the convergence window must be modeled honestly
// through per-event family overrides (a never-emitting stream = a stream
// whose FIRST snapshot hasn't been delivered), per the *_offline_412_test
// never-completing discipline.

const _groupId = 'grp-1';

Group _group() => Group(
  id: _groupId,
  name: 'Test Crew',
  inviteCode: 'TST123',
  createdBy: 'alice',
  memberIds: const ['alice', 'bob'],
  currency: 'OMR',
  createdAt: DateTime(2026, 1, 1),
);

Event _event(String id) => Event(
  id: id,
  name: 'Event $id',
  type: EventType.trip,
  groupId: _groupId,
  createdBy: 'alice',
  participantIds: const ['alice', 'bob'],
  participantNames: const {'alice': 'Alice', 'bob': 'Bob'},
  modules: const EventModules(),
  startDate: DateTime(2026, 3, 15),
  createdAt: DateTime(2026, 3, 10),
);

GroupMember _member(String uid, String name) => GroupMember(
  id: uid,
  groupId: _groupId,
  userId: uid,
  displayName: name,
  role: 'MEMBER',
  joinedAt: DateTime(2026, 1, 1),
);

/// Alice paid 20.000 OMR in [eventId], equal split with Bob → Bob owes 10.000.
Expense _expense(String eventId) => Expense(
  id: 'exp-$eventId',
  tripId: eventId,
  payerParticipantId: 'alice',
  amount: Decimal.parse('20.000'),
  scope: ExpenseScope.global,
  createdAt: DateTime(2026, 3, 12),
);

Future<int> _eventSettlementCount(
  FakeFirebaseFirestore fake,
  String eventId,
) async {
  final snap = await fake
      .collection('groups')
      .doc(_groupId)
      .collection('events')
      .doc(eventId)
      .collection('settlements')
      .get();
  return snap.docs.length;
}

Future<int> _groupSettlementCount(FakeFirebaseFirestore fake) async {
  final snap = await fake
      .collection('groups')
      .doc(_groupId)
      .collection('settlements')
      .get();
  return snap.docs.length;
}

Widget _app(List<Override> overrides) => ProviderScope(
  overrides: overrides,
  child: MediaQuery(
    data: const MediaQueryData(disableAnimations: true),
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const GroupSettleUpScreen(groupId: _groupId),
    ),
  ),
);

List<Override> _baseOverrides({
  required Stream<List<Event>> events,
  required FakeFirebaseFirestore fake,
  RecordingFunctionsService? functions,
}) => [
  groupDetailProvider(_groupId).overrideWith((_) => Stream.value(_group())),
  groupEventsProvider(_groupId).overrideWith((_) => events),
  groupMembersProvider(_groupId).overrideWith(
    (_) => Stream.value([_member('alice', 'Alice'), _member('bob', 'Bob')]),
  ),
  groupSettlementsProvider(
    _groupId,
  ).overrideWith((_) => Stream.value(const <Settlement>[])),
  eventExpensesProvider((
    groupId: _groupId,
    eventId: 'event-1',
  )).overrideWith((_) => Stream.value([_expense('event-1')])),
  eventSettlementsProvider((
    groupId: _groupId,
    eventId: 'event-1',
  )).overrideWith((_) => Stream.value(const <Settlement>[])),
  currentUserIdProvider.overrideWithValue('bob'),
  settlementServiceProvider.overrideWithValue(
    SettlementService.withFirestore(fake, functionsService: functions),
  ),
  groupSettlementServiceProvider.overrideWithValue(
    GroupSettlementService.withFirestore(fake, functionsService: functions),
  ),
];

void main() {
  testWidgets(
    '#1106 entry gate: cold-entry convergence window (event-2 stream has no '
    'first snapshot) → Record refuses to open the sheet, nothing written',
    (tester) async {
      final fake = FakeFirebaseFirestore();
      final pendingExpenses = StreamController<List<Expense>>();
      addTearDown(pendingExpenses.close);

      await tester.pumpWidget(
        _app([
          ..._baseOverrides(
            events: Stream.value([_event('event-1'), _event('event-2')]),
            fake: fake,
          ),
          eventExpensesProvider((
            groupId: _groupId,
            eventId: 'event-2',
          )).overrideWith((_) => pendingExpenses.stream),
          eventSettlementsProvider((
            groupId: _groupId,
            eventId: 'event-2',
          )).overrideWith((_) => Stream.value(const <Settlement>[])),
        ]),
      );
      await tester.pumpAndSettle();

      // The understated tile (event-1 only) rendered with a live Record CTA.
      expect(find.byKey(GroupKeys.settleUpRecordPaymentButton), findsWidgets);
      await tester.tap(find.byKey(GroupKeys.settleUpRecordPaymentButton));
      await tester.pumpAndSettle();

      // Gate refuses: no record sheet, the still-syncing notice instead…
      expect(find.byKey(GroupKeys.markAsPaidButton), findsNothing);
      expect(find.textContaining('still syncing'), findsOneWidget);
      // …and nothing was written.
      expect(await _eventSettlementCount(fake, 'event-1'), 0);
      expect(await _groupSettlementCount(fake), 0);
    },
  );

  testWidgets(
    '#1106 confirm gate: convergence window OPENS while the sheet is up '
    '(new event arrives, streams unresolved) → confirm blocked, nothing '
    'written',
    (tester) async {
      final fake = FakeFirebaseFirestore();
      // Single-subscription on purpose: the seed list below is added before
      // groupEventsProvider first subscribes (the screen is still on the
      // group-detail skeleton), and only a single-sub controller BUFFERS it —
      // a broadcast controller would drop it and strand the screen loading.
      final eventsController = StreamController<List<Event>>();
      addTearDown(eventsController.close);
      final pendingExpenses = StreamController<List<Expense>>();
      addTearDown(pendingExpenses.close);

      await tester.pumpWidget(
        _app([
          ..._baseOverrides(events: eventsController.stream, fake: fake),
          eventExpensesProvider((
            groupId: _groupId,
            eventId: 'event-2',
          )).overrideWith((_) => pendingExpenses.stream),
          eventSettlementsProvider((
            groupId: _groupId,
            eventId: 'event-2',
          )).overrideWith((_) => Stream.value(const <Settlement>[])),
        ]),
      );
      eventsController.add([_event('event-1')]);
      await tester.pumpAndSettle();

      // Converged basis → the sheet opens normally.
      await tester.tap(find.byKey(GroupKeys.settleUpRecordPaymentButton));
      await tester.pumpAndSettle();
      expect(find.byKey(GroupKeys.markAsPaidButton), findsOneWidget);

      // Another device adds event-2; its money streams have no first snapshot
      // here yet — the balance basis is converging again, under the open sheet.
      eventsController.add([_event('event-1'), _event('event-2')]);
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byKey(GroupKeys.markAsPaidButton));
      await tester.pumpAndSettle();

      // Blocked at confirm: still-syncing notice, zero writes (the #1129
      // callable seam was never invoked — the un-faked service would throw).
      expect(find.textContaining('still syncing'), findsOneWidget);
      expect(await _eventSettlementCount(fake, 'event-1'), 0);
      expect(await _groupSettlementCount(fake), 0);
    },
  );

  testWidgets(
    '#1106 control: converged basis records normally (no false block)',
    (tester) async {
      final fake = FakeFirebaseFirestore();
      final functions = RecordingFunctionsService();

      await tester.pumpWidget(
        _app(
          _baseOverrides(
            events: Stream.value([_event('event-1')]),
            fake: fake,
            functions: functions,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(GroupKeys.settleUpRecordPaymentButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(GroupKeys.markAsPaidButton));
      await tester.pumpAndSettle();

      // The decomposed settle-up goes to the server; no still-syncing block.
      expect(find.textContaining('still syncing'), findsNothing);
      expect(functions.recordSettlementCalls, hasLength(1));
      expect(functions.lastCall['mode'], 'groupSettleUp');
    },
  );
}
