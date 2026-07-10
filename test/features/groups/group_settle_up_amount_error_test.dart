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

// #1080 sibling coverage (group settle-up): a zero amount confirmed on the
// record sheet must surface a PERSISTENT inline error on the sheet's amount
// field — the sheet stays open — instead of popping and flashing a snackbar
// that expires with no recoverable feedback.
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

/// Bob owes Alice 10.000 OMR, all in event-1.
GroupBalances _balances() => (
  balances: <String, List<UserBalance>>{
    'OMR': [
      UserBalance(
        participantId: 'uid-alice',
        displayName: 'Alice',
        totalPaid: Decimal.parse('10.000'),
        totalOwed: Decimal.zero,
        netBalance: Decimal.parse('10.000'),
      ),
      UserBalance(
        participantId: 'uid-bob',
        displayName: 'Bob',
        totalPaid: Decimal.zero,
        totalOwed: Decimal.parse('10.000'),
        netBalance: -Decimal.parse('10.000'),
      ),
    ],
  },
  totalSpent: <String, Decimal>{'OMR': Decimal.parse('10.000')},
  eventCount: 1,
  perEventBreakdown: <String, Map<String, Map<String, Decimal>>>{
    'uid-alice': {
      'event-1': {'OMR': Decimal.parse('10.000')},
    },
    'uid-bob': {
      'event-1': {'OMR': -Decimal.parse('10.000')},
    },
  },
  memberNames: <String, String>{'uid-alice': 'Alice', 'uid-bob': 'Bob'},
  memberRawNames: <String, String>{'uid-alice': 'Alice', 'uid-bob': 'Bob'},
);

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
    '#1080: zero amount keeps the record sheet open with a persistent inline '
    'error past the snackbar lifetime, nothing written',
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
            ).overrideWith((_) => AsyncValue.data(_balances())),
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
      await tester.tap(find.text('Tap to edit amount'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '0');
      await tester.ensureVisible(find.byKey(GroupKeys.markAsPaidButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(GroupKeys.markAsPaidButton));
      await tester.pumpAndSettle();

      // Advance PAST the default 4s snackbar lifetime — the field-associated
      // error must remain (the old snackbar was gone by now).
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();

      expect(find.text('Amount must be greater than zero'), findsOneWidget);
      expect(find.byKey(GroupKeys.settleUpRecordSheetTitle), findsOneWidget);
      expect(await _eventSettlementCount(fake), 0);
      expect(await _groupSettlementCount(fake), 0);
    },
  );
}
