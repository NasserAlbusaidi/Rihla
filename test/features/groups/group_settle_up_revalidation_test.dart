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
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/screens/group_settle_up_screen.dart';
import 'package:safar/features/groups/services/group_settlement_service.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/ledger/services/settlement_service.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

// #719: the live balances feeding the screen, mutated mid-test to model another
// device paying while the record sheet is open.
final _testBalances = StateProvider<GroupBalances>((_) => _balances('10.000'));

const _groupId = 'grp-1';

Group _group() => Group(
  id: _groupId,
  name: 'Test Crew',
  inviteCode: 'TST123',
  createdBy: 'uid-alice',
  memberIds: const ['uid-alice', 'uid-bob'],
  currency: 'OMR',
  createdAt: DateTime(2026, 1, 1),
);

final _event1 = Event(
  id: 'event-1',
  name: 'Camping Weekend',
  type: EventType.camping,
  groupId: _groupId,
  createdBy: 'uid-alice',
  participantIds: const ['uid-alice', 'uid-bob'],
  participantNames: const {'uid-alice': 'Alice', 'uid-bob': 'Bob'},
  modules: const EventModules(),
  startDate: DateTime(2026, 3, 15),
  createdAt: DateTime(2026, 3, 10),
);

/// Bob owes Alice [net] OMR, all in event-1.
GroupBalances _balances(String net) => (
  balances: <String, List<UserBalance>>{
    'OMR': [
      UserBalance(
        participantId: 'uid-alice',
        displayName: 'Alice',
        totalPaid: Decimal.parse(net),
        totalOwed: Decimal.zero,
        netBalance: Decimal.parse(net),
      ),
      UserBalance(
        participantId: 'uid-bob',
        displayName: 'Bob',
        totalPaid: Decimal.zero,
        totalOwed: Decimal.parse(net),
        netBalance: -Decimal.parse(net),
      ),
    ],
  },
  totalSpent: <String, Decimal>{'OMR': Decimal.parse(net)},
  eventCount: 1,
  perEventBreakdown: <String, Map<String, Map<String, Decimal>>>{
    'uid-alice': {
      'event-1': {'OMR': Decimal.parse(net)},
    },
    'uid-bob': {
      'event-1': {'OMR': -Decimal.parse(net)},
    },
  },
  memberNames: <String, String>{'uid-alice': 'Alice', 'uid-bob': 'Bob'},
  memberRawNames: <String, String>{'uid-alice': 'Alice', 'uid-bob': 'Bob'},
);

// #929: the decompose write is now ONE atomic WriteBatch staged by
// GroupSettlementService, so event legs no longer flow through
// SettlementService.addSettlement. These tests use REAL services on ONE shared
// FakeFirebaseFirestore and count the persisted docs.
Future<int> _eventSettlementCount(FakeFirebaseFirestore fake) async {
  final snap = await fake
      .collection('groups')
      .doc(_groupId)
      .collection('events')
      .doc('event-1')
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

void main() {
  testWidgets(
    '#719: outstanding shrinks while the record sheet is open → block with '
    'review-again, no settlement written',
    (tester) async {
      final fake = FakeFirebaseFirestore();
      final eventService = SettlementService.withFirestore(fake);
      final groupService = GroupSettlementService.withFirestore(fake);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            groupDetailProvider(
              _groupId,
            ).overrideWith((_) => Stream.value(_group())),
            groupBalancesProvider(
              _groupId,
            ).overrideWith((ref) => AsyncValue.data(ref.watch(_testBalances))),
            groupSettlementsProvider(
              _groupId,
            ).overrideWith((_) => Stream.value(const <Settlement>[])),
            groupEventsProvider(
              _groupId,
            ).overrideWith((_) => Stream.value([_event1])),
            currentUserIdProvider.overrideWithValue('uid-bob'),
            settlementServiceProvider.overrideWithValue(eventService),
            groupSettlementServiceProvider.overrideWithValue(groupService),
          ],
          child: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const GroupSettleUpScreen(groupId: _groupId),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(GroupSettleUpScreen)),
      );

      // Open the record sheet — captures the suggested amount of 10.000 OMR.
      await tester.tap(find.byKey(GroupKeys.settleUpRecordPaymentButton));
      await tester.pumpAndSettle();

      // Another device pays Alice down to 2.000 while the sheet is open.
      container.read(_testBalances.notifier).state = _balances('2.000');
      await tester.pump();

      // Confirm the full (now-stale) 10.000 amount.
      await tester.tap(find.byKey(GroupKeys.markAsPaidButton));
      await tester.pumpAndSettle();

      // Blocked: the review-again message shows the FRESH outstanding (2.000)…
      expect(find.textContaining('Balance changed'), findsOneWidget);
      expect(find.textContaining('2.000'), findsWidgets);
      // …and nothing was written.
      expect(await _eventSettlementCount(fake), 0);
      expect(await _groupSettlementCount(fake), 0);
    },
  );

  testWidgets('#719: unchanged balance records normally (no false block)', (
    tester,
  ) async {
    final fake = FakeFirebaseFirestore();
    final eventService = SettlementService.withFirestore(fake);
    final groupService = GroupSettlementService.withFirestore(fake);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          groupDetailProvider(
            _groupId,
          ).overrideWith((_) => Stream.value(_group())),
          groupBalancesProvider(
            _groupId,
          ).overrideWith((ref) => AsyncValue.data(ref.watch(_testBalances))),
          groupSettlementsProvider(
            _groupId,
          ).overrideWith((_) => Stream.value(const <Settlement>[])),
          groupEventsProvider(
            _groupId,
          ).overrideWith((_) => Stream.value([_event1])),
          currentUserIdProvider.overrideWithValue('uid-bob'),
          settlementServiceProvider.overrideWithValue(eventService),
          groupSettlementServiceProvider.overrideWithValue(groupService),
        ],
        child: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const GroupSettleUpScreen(groupId: _groupId),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(GroupKeys.settleUpRecordPaymentButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(GroupKeys.markAsPaidButton));
    await tester.pumpAndSettle();

    // No staleness → the single-event write lands, no review-again block.
    expect(find.textContaining('Balance changed'), findsNothing);
    expect(await _eventSettlementCount(fake), 1);
  });
}
