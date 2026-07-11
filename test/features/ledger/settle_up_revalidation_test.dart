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
import 'package:safar/features/ledger/models/record_settlement_result.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/ledger/screens/settle_up_screen.dart';
import 'package:safar/features/ledger/services/settlement_service.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

// #773: the live event settlements feeding the screen, mutated mid-test to model
// another device paying while the record sheet is open. The event screen has no
// precomputed balances provider (build() AND the revalidation helper recompute
// from the raw expense/settlement streams), so we mutate the SETTLEMENTS stream —
// not a balances object as the #719 group test does.
final _testSettlements = StateProvider<List<Settlement>>((_) => const []);

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

// Alice pays 10.000 OMR split equally → Bob owes Alice 5.000 → the optimizer
// suggests Bob → Alice 5.000.
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

/// Records each [addSettlement] call so the test can assert nothing was written.
class _RecordingEventSettlementService extends SettlementService {
  _RecordingEventSettlementService()
    : super.withFirestore(FakeFirebaseFirestore());

  int addCalls = 0;

  @override
  Future<RecordSettlementResult> addSettlement({
    required String groupId,
    required String eventId,
    required String payerParticipantId,
    required String recipientParticipantId,
    required Decimal amount,
    required String currency,
    required int observedPairEpoch,
    String? payerName,
    String? recipientName,
    String? note,
  }) async {
    addCalls++;
    return const RecordSettlementResult(
      alreadyRecorded: false,
      eventScopeWrites: 1,
      groupScopeWrites: 0,
      shouldBumpLedgerRevision: true,
      settledAt: '2026-04-01T00:00:00.000Z',
    );
  }
}

Widget _app(_RecordingEventSettlementService service, SharedPreferences prefs) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      currentUserIdProvider.overrideWithValue('uid-bob'),
      eventDetailProvider(
        _eventRef,
      ).overrideWith((_) => Stream.value(_event)),
      // Load-bearing: the 10.000 expense is what makes Bob owe 5.000, so the
      // record tile renders with a 5.000 suggestion. Without it the screen is
      // empty and the test would go RED for the wrong reason.
      eventExpensesProvider(
        _eventRef,
      ).overrideWith((_) => Stream.value(_expenses())),
      // The mutable stream: build() AND the revalidation helper read it, so
      // adding a settlement here models another device paying mid-sheet.
      eventSettlementsProvider(
        _eventRef,
      ).overrideWith((ref) => Stream.value(ref.watch(_testSettlements))),
      groupMembersProvider(
        _groupId,
      ).overrideWith((_) => Stream.value(_members())),
      groupDetailProvider(
        _groupId,
      ).overrideWith((_) => Stream.value(_group())),
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
  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    // Each test starts from a clean (no-settlements) ledger.
    addTearDown(() => prefs.clear());
  });

  testWidgets(
    '#773: event outstanding shrinks while the record sheet is open → block '
    'with review-again, no settlement written',
    (tester) async {
      final service = _RecordingEventSettlementService();

      await tester.pumpWidget(_app(service, prefs));
      // Reset the shared StateProvider for this test before settling.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SettleUpScreen)),
      );
      container.read(_testSettlements.notifier).state = const [];
      await tester.pumpAndSettle();

      // Open the record sheet — captures the suggested 5.000 OMR.
      await tester.ensureVisible(
        find.byKey(GroupKeys.settleUpRecordPaymentButton),
      );
      await tester.tap(find.byKey(GroupKeys.settleUpRecordPaymentButton));
      await tester.pumpAndSettle();
      expect(find.byKey(GroupKeys.settleUpRecordSheetTitle), findsOneWidget);

      // Another device records Bob → Alice 4.000 while the sheet is open:
      // Bob's net moves to -1.000, Alice's to +1.000 → outstanding 1.000.
      container.read(_testSettlements.notifier).state = [
        Settlement(
          id: 'other-device',
          tripId: _eventId,
          payerParticipantId: 'uid-bob',
          recipientParticipantId: 'uid-alice',
          amount: Decimal.parse('4.000'),
          currency: 'OMR',
          createdBy: 'uid-bob',
          settledAt: DateTime(2026, 3, 20),
        ),
      ];
      await tester.pump();

      // Confirm the full (now-stale) 5.000 amount.
      await tester.tap(find.byKey(GroupKeys.markAsPaidButton));
      await tester.pumpAndSettle();

      // Blocked: the review-again message shows the FRESH outstanding (1.000)…
      expect(find.textContaining('Balance changed'), findsOneWidget);
      expect(find.textContaining('1.000'), findsWidgets);
      // …and nothing was written through the screen.
      expect(service.addCalls, 0);
    },
  );

  testWidgets(
    '#773: unchanged event balance records normally (no false block)',
    (tester) async {
      final service = _RecordingEventSettlementService();

      await tester.pumpWidget(_app(service, prefs));
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SettleUpScreen)),
      );
      container.read(_testSettlements.notifier).state = const [];
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(GroupKeys.settleUpRecordPaymentButton),
      );
      await tester.tap(find.byKey(GroupKeys.settleUpRecordPaymentButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(GroupKeys.markAsPaidButton));
      await tester.pumpAndSettle();

      // No staleness → the write lands, no review-again block.
      expect(find.textContaining('Balance changed'), findsNothing);
      expect(service.addCalls, 1);
    },
  );
}
