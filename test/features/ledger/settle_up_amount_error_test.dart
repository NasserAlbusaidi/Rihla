import 'package:decimal/decimal.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/keys/group_keys.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/ledger/screens/settle_up_screen.dart';
import 'package:safar/features/ledger/services/settlement_service.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

// #1080 sibling coverage (event settle-up): a zero amount confirmed on the
// record sheet must surface a PERSISTENT inline error on the sheet's amount
// field — the sheet stays open — instead of popping and flashing a snackbar
// that expires with no recoverable feedback.
const _groupId = 'grp-1';
const _eventId = 'event-1';
const _eventRef = (groupId: _groupId, eventId: _eventId);

Group _group() => Group(
  id: _groupId,
  name: 'Test Crew',
  inviteCode: 'TST123',
  createdBy: 'uid-alice',
  memberIds: const ['uid-alice', 'uid-bob'],
  currency: 'OMR',
  createdAt: DateTime(2026, 1, 1),
);

final _event = Event(
  id: _eventId,
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

List<GroupMember> _members() => [
  GroupMember(
    id: 'uid-alice',
    groupId: _groupId,
    userId: 'uid-alice',
    displayName: 'Alice',
    role: 'member',
    joinedAt: DateTime(2026, 1, 1),
  ),
  GroupMember(
    id: 'uid-bob',
    groupId: _groupId,
    userId: 'uid-bob',
    displayName: 'Bob',
    role: 'member',
    joinedAt: DateTime(2026, 1, 1),
  ),
];

// Alice pays 10.000 OMR split equally → Bob owes Alice 5.000.
List<Expense> _expenses() => [
  Expense(
    id: 'expense-1',
    tripId: _eventId,
    payerParticipantId: 'uid-alice',
    amount: Decimal.parse('10.000'),
    description: 'Dinner',
    scope: ExpenseScope.global,
    currency: 'OMR',
    createdAt: DateTime(2026, 3, 16),
    createdBy: 'uid-alice',
  ),
];

class _RecordingEventSettlementService extends SettlementService {
  _RecordingEventSettlementService()
    : super.withFirestore(FakeFirebaseFirestore());

  int addCalls = 0;

  @override
  Future<Settlement> addSettlement({
    required String groupId,
    required String eventId,
    required String payerParticipantId,
    required String recipientParticipantId,
    required Decimal amount,
    required String createdBy,
    String currency = 'OMR',
    String? payerName,
    String? recipientName,
    String? note,
    String? groupSettleUpId,
  }) async {
    addCalls++;
    return Settlement(
      id: 'evt-set-$addCalls',
      tripId: eventId,
      payerParticipantId: payerParticipantId,
      recipientParticipantId: recipientParticipantId,
      amount: amount,
      currency: currency,
      createdBy: createdBy,
      settledAt: DateTime(2026, 4, 1),
    );
  }
}

Widget _app(_RecordingEventSettlementService service, SharedPreferences prefs) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      currentUserIdProvider.overrideWithValue('uid-bob'),
      eventDetailProvider(_eventRef).overrideWith((_) => Stream.value(_event)),
      eventExpensesProvider(
        _eventRef,
      ).overrideWith((_) => Stream.value(_expenses())),
      eventSettlementsProvider(
        _eventRef,
      ).overrideWith((_) => Stream.value(const <Settlement>[])),
      groupMembersProvider(
        _groupId,
      ).overrideWith((_) => Stream.value(_members())),
      groupDetailProvider(_groupId).overrideWith((_) => Stream.value(_group())),
      settlementServiceProvider.overrideWithValue(service),
    ],
    child: MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SettleUpScreen(groupId: _groupId, eventId: _eventId),
      ),
    ),
  );
}

void main() {
  testWidgets(
    '#1080: zero amount keeps the record sheet open with a persistent inline '
    'error past the snackbar lifetime, nothing written',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = _RecordingEventSettlementService();

      await tester.pumpWidget(_app(service, prefs));
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(GroupKeys.settleUpRecordPaymentButton),
      );
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
      expect(service.addCalls, 0);
    },
  );
}
