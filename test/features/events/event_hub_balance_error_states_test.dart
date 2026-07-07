import 'package:decimal/decimal.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/keys/event_keys.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/events/screens/event_command_center.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:safar/shared/widgets/r_amount.dart';

/// #1028 — the hub balance header must never render a false-clean state
/// ("Nothing to settle yet" / "All settled" / wrong nets) while a source
/// stream is hard-errored or has no first value. Healthy-path states are
/// pinned by event_command_center_test.dart.
void main() {
  FirebaseException denied() =>
      FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');

  testWidgets(
    'expenses stream error → Balance unavailable, never Nothing to settle yet',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          event: _event(),
          expensesStream: Stream<List<Expense>>.error(denied()),
          settlementsStream: Stream.value(const <Settlement>[]),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(EventKeys.balanceHeaderUnavailable), findsOneWidget);
      expect(find.text('Nothing to settle yet'), findsNothing);
      expect(find.text('All settled'), findsNothing);
    },
  );

  testWidgets(
    'settlements stream error with valued expenses → unavailable, '
    'wrong nets suppressed',
    (tester) async {
      // ledgerViewProvider folds the errored settlements stream to [] and
      // computes uid-1's net from the expense alone (-2.500) — a WRONG
      // number the header must not render.
      final expense = _expense(
        id: 'x1',
        payer: 'uid-2',
        amount: Decimal.parse('5.000'),
      );

      await tester.pumpWidget(
        _wrap(
          event: _event(),
          expensesStream: Stream.value([expense]),
          settlementsStream: Stream<List<Settlement>>.error(denied()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(EventKeys.balanceHeaderUnavailable), findsOneWidget);
      expect(find.text('YOU OWE'), findsNothing);
      expect(find.text('YOU ARE OWED'), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(EventKeys.balanceHeader),
          matching: find.byType(RAmount),
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'streams never emit → pending skeleton, never Nothing to settle yet',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          event: _event(),
          expensesStream: const Stream.empty(),
          settlementsStream: const Stream.empty(),
        ),
      );
      // Skeletonizer never settles — bounded pumps, NOT pumpAndSettle
      // (pattern: home_group_row_balance_states_997_test.dart).
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(find.byKey(EventKeys.balanceHeaderPending), findsOneWidget);
      expect(find.text('Nothing to settle yet'), findsNothing);
      expect(find.text('All settled'), findsNothing);
    },
  );

  testWidgets(
    '#1030: members-only stream error → unavailable, wrong universe nets '
    'suppressed',
    (tester) async {
      // ledgerViewProvider folds the errored MEMBERS stream to [] — the #249
      // universe then drops departed recipients and the header would render
      // wrong nets as clean. Money streams are healthy on purpose: only the
      // members leg trips the gate.
      final expense = _expense(
        id: 'x1',
        payer: 'uid-2',
        amount: Decimal.parse('5.000'),
      );

      await tester.pumpWidget(
        _wrap(
          event: _event(),
          expensesStream: Stream.value([expense]),
          settlementsStream: Stream.value(const <Settlement>[]),
          membersStream: Stream<List<GroupMember>>.error(denied()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(EventKeys.balanceHeaderUnavailable), findsOneWidget);
      expect(find.text('YOU OWE'), findsNothing);
      expect(find.text('YOU ARE OWED'), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(EventKeys.balanceHeader),
          matching: find.byType(RAmount),
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    '#1030: members stream never emits → pending, never a clean header',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          event: _event(),
          expensesStream: Stream.value(const <Expense>[]),
          settlementsStream: Stream.value(const <Settlement>[]),
          membersStream: const Stream.empty(),
        ),
      );
      // Skeletonizer never settles — bounded pumps, NOT pumpAndSettle.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(find.byKey(EventKeys.balanceHeaderPending), findsOneWidget);
      expect(find.text('Nothing to settle yet'), findsNothing);
      expect(find.text('All settled'), findsNothing);
    },
  );

  testWidgets('healthy empty streams unchanged → Nothing to settle yet', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        event: _event(),
        expensesStream: Stream.value(const <Expense>[]),
        settlementsStream: Stream.value(const <Settlement>[]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nothing to settle yet'), findsOneWidget);
    expect(find.byKey(EventKeys.balanceHeaderUnavailable), findsNothing);
    expect(find.byKey(EventKeys.balanceHeaderPending), findsNothing);
  });
}

// ───────────────────────────── Helpers

Widget _wrap({
  required Event event,
  required Stream<List<Expense>> expensesStream,
  required Stream<List<Settlement>> settlementsStream,
  Stream<List<GroupMember>>? membersStream,
}) {
  final eventRef = (groupId: event.groupId, eventId: event.id);
  return ProviderScope(
    overrides: [
      currentUserIdProvider.overrideWithValue('uid-1'),
      eventDetailProvider(
        eventRef,
      ).overrideWith((_) => Stream<Event?>.value(event)),
      groupDetailProvider(
        event.groupId,
      ).overrideWith((_) => Stream<Group?>.value(_group)),
      eventExpensesProvider(eventRef).overrideWith((_) => expensesStream),
      eventSettlementsProvider(
        eventRef,
      ).overrideWith((_) => settlementsStream),
      groupMembersProvider(event.groupId).overrideWith(
        (_) =>
            membersStream ??
            Stream.value([
              _realMember('uid-1', 'Mona'),
              _realMember('uid-2', 'Nasser'),
            ]),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: EventCommandCenter(groupId: event.groupId, eventId: event.id),
    ),
  );
}

Event _event() {
  return Event(
    id: 'event-1',
    name: 'Marrakech',
    type: EventType.trip,
    groupId: 'group-1',
    createdBy: 'uid-1',
    participantIds: const ['uid-1', 'uid-2'],
    participantNames: const {'uid-1': 'Mona', 'uid-2': 'Nasser'},
    modules: const EventModules(),
    startDate: DateTime(2026, 1, 1),
    endDate: DateTime(2026, 1, 3),
    createdAt: DateTime(2026, 1, 1),
  );
}

Expense _expense({
  required String id,
  required String payer,
  required Decimal amount,
}) {
  return Expense(
    id: id,
    tripId: 'event-1',
    payerParticipantId: payer,
    amount: amount,
    scope: ExpenseScope.global,
    createdAt: DateTime(2026, 1, 2),
    createdBy: payer,
    currency: 'OMR',
  );
}

GroupMember _realMember(String uid, String name) => GroupMember(
  id: 'doc-$uid',
  groupId: 'group-1',
  userId: uid,
  displayName: name,
  role: 'member',
  joinedAt: DateTime(2026, 1, 1),
);

final _group = Group(
  id: 'group-1',
  name: 'Friends',
  inviteCode: 'ABC123',
  createdBy: 'uid-1',
  memberIds: const ['uid-1', 'uid-2'],
  createdAt: DateTime(2026, 1, 1),
);
