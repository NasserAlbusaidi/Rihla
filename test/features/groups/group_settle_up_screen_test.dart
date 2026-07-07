import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/shared/widgets/skeleton_loader.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/connectivity_provider.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/services/firebase_functions_service.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/screens/group_settle_up_screen.dart';
import 'package:safar/features/groups/keys/group_keys.dart';
import 'package:safar/features/groups/services/group_activity_service.dart';
import 'package:safar/features/groups/services/group_settlement_service.dart';
import 'package:safar/features/groups/widgets/group_settlement_tile.dart';
import 'package:safar/features/ledger/keys/ledger_keys.dart';
import 'package:safar/features/ledger/models/correct_settlement_result.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

class _MockFunctionsService extends Mock implements FirebaseFunctionsService {}

/// Widget tests for GroupSettleUpScreen — single-page wireframe layout.
///
/// Layout (Hi_GroupSettle): italic headline (carries the transfer count) →
/// total chip → optimized transfer cards → "Each person's net" → inline
/// payment history. The redundant transfer-count chip was removed in #158.

const _groupId = 'grp-1';

final _testGroup = Group(
  id: _groupId,
  name: 'Test Crew',
  inviteCode: 'TST123',
  createdBy: 'uid-alice',
  memberIds: const ['uid-alice', 'uid-bob'],
  currency: 'OMR',
  createdAt: DateTime(2026, 1, 1),
);

final _testEvent = Event(
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

/// Two-person GroupBalances: Bob owes Alice 7.750 OMR.
final _balancesOwed = (
  balances: <String, List<UserBalance>>{
    'OMR': [
      UserBalance(
        participantId: 'uid-alice',
        displayName: 'Alice',
        totalPaid: Decimal.parse('15.500'),
        totalOwed: Decimal.parse('7.750'),
        netBalance: Decimal.parse('7.750'),
      ),
      UserBalance(
        participantId: 'uid-bob',
        displayName: 'Bob',
        totalPaid: Decimal.parse('0.000'),
        totalOwed: Decimal.parse('7.750'),
        netBalance: Decimal.parse('-7.750'),
      ),
    ],
  },
  totalSpent: <String, Decimal>{'OMR': Decimal.parse('15.500')},
  eventCount: 2,
  perEventBreakdown: <String, Map<String, Map<String, Decimal>>>{
    'uid-alice': {
      'event-1': {'OMR': Decimal.parse('7.750')},
    },
    'uid-bob': {
      'event-1': {'OMR': Decimal.parse('-7.750')},
    },
  },
  memberNames: <String, String>{'uid-alice': 'Alice', 'uid-bob': 'Bob'},
  memberRawNames: <String, String>{'uid-alice': 'Alice', 'uid-bob': 'Bob'},
);

/// #382 PR-1: the same debt denominated in a FOREIGN (non-group) currency
/// bucket — pins that the recorded settlement carries the BUCKET currency,
/// never the group currency.
final _balancesOwedAed = (
  balances: <String, List<UserBalance>>{
    'AED': [
      UserBalance(
        participantId: 'uid-alice',
        displayName: 'Alice',
        totalPaid: Decimal.parse('15.50'),
        totalOwed: Decimal.parse('7.75'),
        netBalance: Decimal.parse('7.75'),
      ),
      UserBalance(
        participantId: 'uid-bob',
        displayName: 'Bob',
        totalPaid: Decimal.parse('0.00'),
        totalOwed: Decimal.parse('7.75'),
        netBalance: Decimal.parse('-7.75'),
      ),
    ],
  },
  totalSpent: <String, Decimal>{'AED': Decimal.parse('15.50')},
  eventCount: 1,
  perEventBreakdown: <String, Map<String, Map<String, Decimal>>>{},
  memberNames: <String, String>{'uid-alice': 'Alice', 'uid-bob': 'Bob'},
  memberRawNames: <String, String>{'uid-alice': 'Alice', 'uid-bob': 'Bob'},
);

/// All-settled GroupBalances.
final _balancesSettled = (
  balances: <String, List<UserBalance>>{
    'OMR': [
      UserBalance(
        participantId: 'uid-alice',
        displayName: 'Alice',
        totalPaid: Decimal.zero,
        totalOwed: Decimal.zero,
        netBalance: Decimal.zero,
      ),
      UserBalance(
        participantId: 'uid-bob',
        displayName: 'Bob',
        totalPaid: Decimal.zero,
        totalOwed: Decimal.zero,
        netBalance: Decimal.zero,
      ),
    ],
  },
  totalSpent: <String, Decimal>{'OMR': Decimal.zero},
  eventCount: 0,
  perEventBreakdown: <String, Map<String, Map<String, Decimal>>>{},
  memberNames: <String, String>{'uid-alice': 'Alice', 'uid-bob': 'Bob'},
  memberRawNames: <String, String>{'uid-alice': 'Alice', 'uid-bob': 'Bob'},
);

/// #382 PR-5 Task 13: two same-direction buckets — Bob owes Alice in BOTH
/// OMR and USD. The optimizer runs per bucket, so (me=Bob ↔ Alice) spans two
/// buckets → one stepped "settle all" card whose tap walks one record sheet
/// per bucket.
final _balancesTwoBucket = (
  balances: <String, List<UserBalance>>{
    'OMR': [
      UserBalance(
        participantId: 'uid-alice',
        displayName: 'Alice',
        totalPaid: Decimal.parse('20.000'),
        totalOwed: Decimal.parse('10.000'),
        netBalance: Decimal.parse('10.000'),
      ),
      UserBalance(
        participantId: 'uid-bob',
        displayName: 'Bob',
        totalPaid: Decimal.parse('0.000'),
        totalOwed: Decimal.parse('10.000'),
        netBalance: Decimal.parse('-10.000'),
      ),
    ],
    'USD': [
      UserBalance(
        participantId: 'uid-alice',
        displayName: 'Alice',
        totalPaid: Decimal.parse('40.00'),
        totalOwed: Decimal.parse('20.00'),
        netBalance: Decimal.parse('20.00'),
      ),
      UserBalance(
        participantId: 'uid-bob',
        displayName: 'Bob',
        totalPaid: Decimal.parse('0.00'),
        totalOwed: Decimal.parse('20.00'),
        netBalance: Decimal.parse('-20.00'),
      ),
    ],
  },
  totalSpent: <String, Decimal>{
    'OMR': Decimal.parse('20.000'),
    'USD': Decimal.parse('40.00'),
  },
  eventCount: 2,
  perEventBreakdown: <String, Map<String, Map<String, Decimal>>>{},
  memberNames: <String, String>{'uid-alice': 'Alice', 'uid-bob': 'Bob'},
  memberRawNames: <String, String>{'uid-alice': 'Alice', 'uid-bob': 'Bob'},
);

final _testSettlement1 = Settlement(
  id: 'stl-1',
  tripId: _groupId,
  payerParticipantId: 'uid-bob',
  recipientParticipantId: 'uid-alice',
  amount: Decimal.parse('5.000'),
  settledAt: DateTime(2026, 3, 20),
  payerName: 'Bob',
  recipientName: 'Alice',
  scope: 'group',
  groupId: _groupId,
);

final _testSettlement2 = Settlement(
  id: 'stl-2',
  tripId: _groupId,
  payerParticipantId: 'uid-alice',
  recipientParticipantId: 'uid-bob',
  amount: Decimal.parse('3.000'),
  settledAt: DateTime(2026, 3, 25),
  payerName: 'Alice',
  recipientName: 'Bob',
  scope: 'group',
  groupId: _groupId,
);

Widget _wrap(
  Widget child, {
  required AsyncValue<GroupBalances> balancesAsync,
  List<Event>? events,
  List<Settlement>? settlements,
  String? currentUid,
  List<Override> extraOverrides = const [],
}) {
  return ProviderScope(
    overrides: [
      groupDetailProvider(
        _groupId,
      ).overrideWith((_) => Stream.value(_testGroup)),
      groupBalancesProvider(_groupId).overrideWith((_) => balancesAsync),
      groupSettlementsProvider(
        _groupId,
      ).overrideWith((_) => Stream.value(settlements ?? [])),
      groupEventsProvider(
        _groupId,
      ).overrideWith((_) => Stream.value(events ?? [])),
      currentUserIdProvider.overrideWithValue(currentUid),
      ...extraOverrides,
    ],
    child: MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    ),
  );
}

class _RecordingGroupSettlementService extends GroupSettlementService {
  _RecordingGroupSettlementService({
    this.throwOnAdd = false,
    this.errorToThrow,
    this.neverAck = false,
  }) : super.withFirestore(FakeFirebaseFirestore());

  final bool throwOnAdd;

  /// #412: when true, [addGroupSettlement] records the call but its future
  /// never completes — the real SDK's offline behavior (server ack only
  /// arrives on reconnect), which FakeFirebaseFirestore cannot model.
  final bool neverAck;

  /// When set, [addGroupSettlement] throws this exact error (e.g. a
  /// [FirebaseException] with a specific code) so #360's error mapping can be
  /// exercised per cause.
  final Object? errorToThrow;
  final addCalls =
      <
        ({
          String groupId,
          String payerParticipantId,
          String recipientParticipantId,
          Decimal amount,
          String createdBy,
          String currency,
          String? note,
          String? payerName,
          String? recipientName,
        })
      >[];

  @override
  Future<Settlement> addGroupSettlement({
    required String groupId,
    required String payerParticipantId,
    required String recipientParticipantId,
    required Decimal amount,
    required String createdBy,
    String currency = 'OMR',
    String? note,
    String? payerName,
    String? recipientName,
    String? groupSettleUpId,
  }) async {
    if (errorToThrow != null) {
      throw errorToThrow!;
    }
    if (throwOnAdd) {
      throw StateError('write failed');
    }
    addCalls.add((
      groupId: groupId,
      payerParticipantId: payerParticipantId,
      recipientParticipantId: recipientParticipantId,
      amount: amount,
      createdBy: createdBy,
      currency: currency,
      note: note,
      payerName: payerName,
      recipientName: recipientName,
    ));
    if (neverAck) {
      return Completer<Settlement>().future;
    }
    return Settlement(
      id: 'recorded-${addCalls.length}',
      tripId: groupId,
      payerParticipantId: payerParticipantId,
      recipientParticipantId: recipientParticipantId,
      amount: amount,
      settledAt: DateTime(2026, 4, 1),
      payerName: payerName,
      recipientName: recipientName,
      scope: 'group',
      groupId: groupId,
    );
  }
}

class _RecordingGroupActivityService extends GroupActivityService {
  _RecordingGroupActivityService()
    : super.withFirestore(FakeFirebaseFirestore());

  final logCalls =
      <
        ({
          String groupId,
          String type,
          String actorId,
          String actorName,
          String description,
          Map<String, dynamic>? metadata,
        })
      >[];

  @override
  void logGroupEvent({
    required String groupId,
    required String type,
    required String actorId,
    required String actorName,
    required String description,
    Map<String, dynamic>? metadata,
  }) {
    logCalls.add((
      groupId: groupId,
      type: type,
      actorId: actorId,
      actorName: actorName,
      description: description,
      metadata: metadata,
    ));
  }
}

Widget _wrapWithGroupStream(Stream<Group?> groupStream) {
  final router = GoRouter(
    initialLocation: '/group/$_groupId/settle-up',
    routes: [
      GoRoute(
        path: '/home',
        builder: (_, _) => const Scaffold(body: Text('Home')),
      ),
      GoRoute(
        path: '/group/:gid/settle-up',
        builder: (_, state) =>
            GroupSettleUpScreen(groupId: state.pathParameters['gid']!),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      groupDetailProvider(_groupId).overrideWith((_) => groupStream),
      groupBalancesProvider(
        _groupId,
      ).overrideWith((_) => AsyncValue.data(_balancesOwed)),
      groupSettlementsProvider(
        _groupId,
      ).overrideWith((_) => Stream.value(const <Settlement>[])),
      groupEventsProvider(
        _groupId,
      ).overrideWith((_) => Stream.value(const <Event>[])),
      currentUserIdProvider.overrideWithValue('uid-bob'),
    ],
    child: MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: MaterialApp.router(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
}

void main() {
  group('GroupSettleUpScreen', () {
    testWidgets('shows loading indicator while group is loading', (
      tester,
    ) async {
      final controller = StreamController<Group?>();
      addTearDown(controller.close);

      await tester.pumpWidget(_wrapWithGroupStream(controller.stream));
      await tester.pump();

      expect(find.byType(SkeletonLoader), findsOneWidget); // #355
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('missing group empty state routes home', (tester) async {
      await tester.pumpWidget(_wrapWithGroupStream(Stream<Group?>.value(null)));
      await tester.pumpAndSettle();

      expect(find.text('This group is no longer available'), findsOneWidget);
      expect(
        find.text('You may have been removed. Tap below to go back home.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Go home'));
      await tester.pumpAndSettle();

      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets(
      'shows screen title and the transfer count in the headline, not a '
      'redundant chip (#158)',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            const GroupSettleUpScreen(groupId: _groupId),
            balancesAsync: AsyncValue.data(_balancesOwed),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Settle up'), findsOneWidget);
        // The count lives in the italic headline ("One transfer\nuntil …") …
        expect(find.textContaining('One transfer'), findsOneWidget);
        // … and no longer in a separate summary pill (#158).
        expect(find.text('1 transfer'), findsNothing);
      },
    );

    testWidgets('renders italic headline and "total" chip', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GroupSettleUpScreen(groupId: _groupId),
          balancesAsync: AsyncValue.data(_balancesOwed),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining("everyone's even"), findsOneWidget);
      expect(find.textContaining('total'), findsOneWidget);
    });

    testWidgets('#244: shows incomplete-balance banner when an event read failed',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GroupSettleUpScreen(groupId: _groupId),
          balancesAsync: AsyncValue.data(_balancesOwed),
          extraOverrides: [
            groupFailedEventIdsProvider(
              _groupId,
            ).overrideWithValue(const {'event-x'}),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('may be incomplete'), findsOneWidget);
    });

    testWidgets('#244: no banner when all event reads succeed', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GroupSettleUpScreen(groupId: _groupId),
          balancesAsync: AsyncValue.data(_balancesOwed),
          // groupFailedEventIdsProvider not overridden → real provider over the
          // (empty) events list returns {} → no banner.
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('may be incomplete'), findsNothing);
    });

    testWidgets('renders settlement tile in unified list', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GroupSettleUpScreen(groupId: _groupId),
          balancesAsync: AsyncValue.data(_balancesOwed),
          currentUid: 'uid-bob',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(GroupSettlementTile), findsOneWidget);
    });

    testWidgets('Mark paid button visible when current user is the debtor', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const GroupSettleUpScreen(groupId: _groupId),
          balancesAsync: AsyncValue.data(_balancesOwed),
          currentUid: 'uid-bob',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Mark paid'), findsOneWidget);
    });

    testWidgets('#282: creditor sees a "Mark received" record button', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const GroupSettleUpScreen(groupId: _groupId),
          balancesAsync: AsyncValue.data(_balancesOwed),
          currentUid: 'uid-alice', // Alice is owed by Bob → creditor
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(GroupKeys.settleUpRecordPaymentButton), findsOneWidget);
      // The creditor's affordance is framed as "received", not "paid".
      expect(find.text('Mark received'), findsOneWidget);
      expect(find.text('Mark paid'), findsNothing);
    });

    testWidgets(
      '#595: a third party (neither payer nor recipient) sees a neutral '
      '"Record" button',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            const GroupSettleUpScreen(groupId: _groupId),
            balancesAsync: AsyncValue.data(_balancesOwed),
            // Carol is neither the debtor (Bob) nor the creditor (Alice) of the
            // bob→alice transfer — an organizer recording on the group's behalf.
            currentUid: 'uid-carol',
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(GroupKeys.settleUpRecordPaymentButton),
          findsOneWidget,
        );
        // Neutral framing — neither the debtor nor the creditor label.
        expect(find.text('Record'), findsOneWidget);
        expect(find.text('Mark paid'), findsNothing);
        expect(find.text('Mark received'), findsNothing);
      },
    );

    testWidgets(
      '#282: creditor recording keeps payer=debtor, recipient=creditor',
      (tester) async {
        final settlementService = _RecordingGroupSettlementService();
        final activityService = _RecordingGroupActivityService();

        await tester.pumpWidget(
          _wrap(
            const GroupSettleUpScreen(groupId: _groupId),
            balancesAsync: AsyncValue.data(_balancesOwed),
            currentUid: 'uid-alice', // creditor records the received payment
            extraOverrides: [
              groupSettlementServiceProvider.overrideWithValue(
                settlementService,
              ),
              groupActivityServiceProvider.overrideWithValue(activityService),
            ],
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(GroupKeys.settleUpRecordPaymentButton));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(GroupKeys.markAsPaidButton));
        await tester.pumpAndSettle();

        // Direction follows the optimal transfer, not who tapped: Bob (debtor)
        // pays Alice (creditor), even though Alice recorded it.
        expect(settlementService.addCalls, hasLength(1));
        expect(settlementService.addCalls.single.payerParticipantId, 'uid-bob');
        expect(
          settlementService.addCalls.single.recipientParticipantId,
          'uid-alice',
        );
        expect(settlementService.addCalls.single.amount, Decimal.parse('7.750'));
      },
    );

    testWidgets(
      '#283/#889: correcting a history payment invokes '
      'correctSettlement(scope: group) with the original id + sentinel '
      'note (no activity log, no bump — group settlements are live-watched)',
      (tester) async {
        final activityService = _RecordingGroupActivityService();
        final functionsService = _MockFunctionsService();
        when(
          () => functionsService.correctSettlement(
            groupId: any(named: 'groupId'),
            scope: any(named: 'scope'),
            eventId: any(named: 'eventId'),
            settlementId: any(named: 'settlementId'),
            correctionNote: any(named: 'correctionNote'),
          ),
        ).thenAnswer(
          (_) async => const CorrectSettlementResult(
            eventScopeWrites: 0,
            groupScopeWrites: 1,
            repaired: false,
            noop: false,
            shouldBumpLedgerRevision: false,
          ),
        );

        // History: Bob paid Alice 7.750 (a group settlement).
        final original = Settlement(
          id: 'gs1',
          tripId: _groupId,
          payerParticipantId: 'uid-bob',
          recipientParticipantId: 'uid-alice',
          amount: Decimal.parse('7.750'),
          settledAt: DateTime(2026, 4, 1),
          payerName: 'Bob',
          recipientName: 'Alice',
          scope: 'group',
          groupId: _groupId,
        );

        await tester.pumpWidget(
          _wrap(
            const GroupSettleUpScreen(groupId: _groupId),
            balancesAsync: AsyncValue.data(_balancesOwed),
            settlements: [original],
            currentUid: 'uid-alice',
            extraOverrides: [
              groupActivityServiceProvider.overrideWithValue(activityService),
              firebaseFunctionsServiceProvider.overrideWithValue(
                functionsService,
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        final container = ProviderScope.containerOf(
          tester.element(find.byType(GroupSettleUpScreen)),
        );

        final correctButton = find.byKey(GroupKeys.settleUpCorrectButton);
        await tester.ensureVisible(correctButton);
        await tester.tap(correctButton);
        await tester.pumpAndSettle();

        // Confirm the correction.
        await tester.tap(find.text('Record correction'));
        await tester.pumpAndSettle();

        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        verify(
          () => functionsService.correctSettlement(
            groupId: _groupId,
            scope: 'group',
            eventId: null,
            settlementId: 'gs1',
            correctionNote: l10n.settleUpCorrectionNote,
          ),
        ).called(1);

        // A correction must NOT appear in the activity feed as a fresh payment.
        expect(
          activityService.logCalls.where((c) => c.type == 'group_settlement'),
          isEmpty,
        );
        // Standalone group-only correction never bumps — group settlements
        // are live-watched (groupSettlementsProvider).
        expect(container.read(ledgerRevisionProvider), 0);
      },
    );

    testWidgets('GROUP TOTAL PENDING shows 7.750 OMR', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GroupSettleUpScreen(groupId: _groupId),
          balancesAsync: AsyncValue.data(_balancesOwed),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('7.750'), findsWidgets);
    });

    testWidgets('inline history shows past settlements', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GroupSettleUpScreen(groupId: _groupId),
          balancesAsync: AsyncValue.data(_balancesOwed),
          settlements: [_testSettlement1, _testSettlement2],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Payment history'), findsOneWidget);
      // History tiles render RichText spans — the substring lives in a span.
      expect(find.textContaining('paid', findRichText: true), findsWidgets);
      // #818 Wave 5.3: the recap CTA is a standalone-event-settle-up-only
      // affordance (receipt is event-scoped, #704 open) — the group screen
      // never wires the `footer` param, so it must never appear here.
      expect(find.byKey(LedgerKeys.settleUpRecapCta), findsNothing);
    });

    testWidgets('history section omitted when no settlements', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GroupSettleUpScreen(groupId: _groupId),
          balancesAsync: AsyncValue.data(_balancesOwed),
          settlements: const [],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Payment history'), findsNothing);
    });

    testWidgets('all settled state shows when no settlements and no history', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const GroupSettleUpScreen(groupId: _groupId),
          balancesAsync: AsyncValue.data(_balancesSettled),
          settlements: const [],
        ),
      );
      await tester.pump();

      expect(find.text('All settled up'), findsOneWidget);
    });

    testWidgets('all-settled state shows "Everyone is square" body text', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const GroupSettleUpScreen(groupId: _groupId),
          balancesAsync: AsyncValue.data(_balancesSettled),
          settlements: const [],
        ),
      );
      await tester.pump();

      expect(
        find.text('Everyone is square. No outstanding amounts.'),
        findsOneWidget,
      );
    });

    testWidgets('shows loading indicator while balances are loading', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const GroupSettleUpScreen(groupId: _groupId),
          balancesAsync: const AsyncValue.loading(),
        ),
      );
      await tester.pump();

      expect(find.byType(SkeletonLoader), findsOneWidget); // #355
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('shows error state with Retry button on balance fetch error', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const GroupSettleUpScreen(groupId: _groupId),
          balancesAsync: AsyncValue.error(
            Exception('Network error'),
            StackTrace.current,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pump();

      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('Mark paid opens record payment sheet', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GroupSettleUpScreen(groupId: _groupId),
          balancesAsync: AsyncValue.data(_balancesOwed),
          currentUid: 'uid-bob',
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mark paid'));
      await tester.pumpAndSettle();

      expect(find.byKey(GroupKeys.markAsPaidButton), findsOneWidget);
      expect(find.byKey(GroupKeys.notNowButton), findsOneWidget);
    });

    testWidgets('Not Now button dismisses bottom sheet', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GroupSettleUpScreen(groupId: _groupId),
          balancesAsync: AsyncValue.data(_balancesOwed),
          currentUid: 'uid-bob',
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mark paid'));
      await tester.pumpAndSettle();

      expect(find.byKey(GroupKeys.notNowButton), findsOneWidget);

      await tester.tap(find.byKey(GroupKeys.notNowButton));
      await tester.pumpAndSettle();

      expect(find.byKey(GroupKeys.notNowButton), findsNothing);
    });

    testWidgets('recording a payment writes settlement and activity log', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'settings_device_name': 'Bobby'});
      final prefs = await SharedPreferences.getInstance();
      final settlementService = _RecordingGroupSettlementService();
      final activityService = _RecordingGroupActivityService();

      await tester.pumpWidget(
        _wrap(
          const GroupSettleUpScreen(groupId: _groupId),
          balancesAsync: AsyncValue.data(_balancesOwed),
          currentUid: 'uid-bob',
          extraOverrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            groupSettlementServiceProvider.overrideWithValue(settlementService),
            groupActivityServiceProvider.overrideWithValue(activityService),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(GroupKeys.settleUpRecordPaymentButton));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'bank receipt');
      await tester.tap(find.byKey(GroupKeys.markAsPaidButton));
      await tester.pumpAndSettle();

      expect(find.text('Settlement recorded.'), findsOneWidget);
      expect(settlementService.addCalls, hasLength(1));
      expect(settlementService.addCalls.single.groupId, _groupId);
      expect(settlementService.addCalls.single.payerParticipantId, 'uid-bob');
      expect(
        settlementService.addCalls.single.recipientParticipantId,
        'uid-alice',
      );
      expect(settlementService.addCalls.single.amount, Decimal.parse('7.750'));
      expect(settlementService.addCalls.single.createdBy, 'uid-bob');
      expect(settlementService.addCalls.single.note, 'bank receipt');
      expect(activityService.logCalls, hasLength(1));
      expect(activityService.logCalls.single.type, 'group_settlement');
      expect(activityService.logCalls.single.actorName, 'Bobby');
      expect(activityService.logCalls.single.metadata, {
        'amount': '7.75',
        'recipientId': 'uid-alice',
        'currency': 'OMR',
        'fromUserId': 'uid-bob',
        'toUserId': 'uid-alice',
        'fromName': 'Bob',
        'toName': 'Alice',
      });
    });

    testWidgets(
      '#367: a debtor group-level record offers the WhatsApp nudge with a '
      'GROUP-scoped message (for {group} only — never an event name)',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'settings_device_name': 'Bobby',
        });
        final prefs = await SharedPreferences.getInstance();
        final settlementService = _RecordingGroupSettlementService();
        final activityService = _RecordingGroupActivityService();

        await tester.pumpWidget(
          _wrap(
            const GroupSettleUpScreen(groupId: _groupId),
            balancesAsync: AsyncValue.data(_balancesOwed),
            currentUid: 'uid-bob', // bob owes alice → debtor
            extraOverrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              groupSettlementServiceProvider.overrideWithValue(
                settlementService,
              ),
              groupActivityServiceProvider.overrideWithValue(activityService),
            ],
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(GroupKeys.settleUpRecordPaymentButton));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(GroupKeys.markAsPaidButton));
        await tester.pumpAndSettle();

        expect(find.byKey(GroupKeys.settleNotifySheet), findsOneWidget);
        final preview = tester.widget<Text>(
          find.descendant(
            of: find.byKey(GroupKeys.settleNotifyMessagePreview),
            matching: find.byType(Text),
          ),
        );
        // Group scope spans events → names only the group, no "{event} in".
        expect(preview.data, "Hey Alice, I've sent you OMR 7.750 for Test Crew.");
      },
    );

    testWidgets(
      '#367: the CREDITOR recording a group-level receipt sees NO nudge', (
        tester,
      ) async {
        final settlementService = _RecordingGroupSettlementService();
        final activityService = _RecordingGroupActivityService();

        await tester.pumpWidget(
          _wrap(
            const GroupSettleUpScreen(groupId: _groupId),
            balancesAsync: AsyncValue.data(_balancesOwed),
            currentUid: 'uid-alice', // alice is owed → creditor
            extraOverrides: [
              groupSettlementServiceProvider.overrideWithValue(
                settlementService,
              ),
              groupActivityServiceProvider.overrideWithValue(activityService),
            ],
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(GroupKeys.settleUpRecordPaymentButton));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(GroupKeys.markAsPaidButton));
        await tester.pumpAndSettle();

        expect(find.byKey(GroupKeys.settleNotifySheet), findsNothing);
      },
    );

    testWidgets(
      'recorded settlement carries the BUCKET currency, not group.currency '
      '(#382 PR-1)',
      (tester) async {
        // The group is OMR, but the outstanding debt lives in an AED bucket —
        // the write must be denominated in AED (mislabeling it OMR was the
        // pre-bucketing behavior for foreign-currency data).
        SharedPreferences.setMockInitialValues({
          'settings_device_name': 'Bobby',
        });
        final prefs = await SharedPreferences.getInstance();
        final settlementService = _RecordingGroupSettlementService();
        final activityService = _RecordingGroupActivityService();

        await tester.pumpWidget(
          _wrap(
            const GroupSettleUpScreen(groupId: _groupId),
            balancesAsync: AsyncValue.data(_balancesOwedAed),
            currentUid: 'uid-bob',
            extraOverrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              groupSettlementServiceProvider.overrideWithValue(
                settlementService,
              ),
              groupActivityServiceProvider.overrideWithValue(activityService),
            ],
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(GroupKeys.settleUpRecordPaymentButton));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(GroupKeys.markAsPaidButton));
        await tester.pumpAndSettle();

        expect(settlementService.addCalls, hasLength(1));
        expect(settlementService.addCalls.single.currency, 'AED');
        expect(
          settlementService.addCalls.single.amount,
          Decimal.parse('7.75'),
        );
      },
    );

    testWidgets(
      '#412: an offline group settlement whose write never acks still '
      'confirms, logs activity, and does NOT bump the ledger revision',
      (tester) async {
        final settlementService = _RecordingGroupSettlementService(
          neverAck: true,
        );
        final activityService = _RecordingGroupActivityService();
        final connectivity = ConnectivityNotifier(startPeriodicChecks: false)
          ..setOffline();

        await tester.pumpWidget(
          _wrap(
            const GroupSettleUpScreen(groupId: _groupId),
            balancesAsync: AsyncValue.data(_balancesOwed),
            currentUid: 'uid-bob',
            extraOverrides: [
              connectivityProvider.overrideWith((ref) => connectivity),
              groupSettlementServiceProvider.overrideWithValue(
                settlementService,
              ),
              groupActivityServiceProvider.overrideWithValue(activityService),
            ],
          ),
        );
        await tester.pumpAndSettle();

        final container = ProviderScope.containerOf(
          tester.element(find.byType(GroupSettleUpScreen)),
        );

        await tester.tap(find.byKey(GroupKeys.settleUpRecordPaymentButton));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(GroupKeys.markAsPaidButton));
        await tester.pump();
        // Past kWriteAckTimeout — fixed pumps only (never pumpAndSettle while
        // a write future is deliberately left pending).
        await tester.pump(const Duration(seconds: 6));
        await tester.pump(const Duration(milliseconds: 500));

        expect(
          find.text('Settlement recorded — will sync when online.'),
          findsOneWidget,
        );
        expect(connectivity.state, ConnectivityStatus.syncing);
        // The settlement write was handed to the SDK queue…
        expect(settlementService.addCalls, hasLength(1));
        // …and the activity entry was ALSO queued — before #412 it sat after
        // the hung await and was lost if the app died mid-hang.
        expect(activityService.logCalls, hasLength(1));
        // Group settlements are live-watched (groupSettlementsProvider) — the
        // one-shot home revision must NOT be bumped (CLAUDE.md invariant).
        expect(container.read(ledgerRevisionProvider), 0);
      },
    );

    testWidgets('recording zero amount shows validation snackbar', (
      tester,
    ) async {
      final settlementService = _RecordingGroupSettlementService();
      final activityService = _RecordingGroupActivityService();

      await tester.pumpWidget(
        _wrap(
          const GroupSettleUpScreen(groupId: _groupId),
          balancesAsync: AsyncValue.data(_balancesOwed),
          currentUid: 'uid-bob',
          extraOverrides: [
            groupSettlementServiceProvider.overrideWithValue(settlementService),
            groupActivityServiceProvider.overrideWithValue(activityService),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(GroupKeys.settleUpRecordPaymentButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tap to edit amount'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '0');
      // #351 microcopy made the sheet taller; scroll the confirm button into
      // view (it can sit below the 800x600 test fold once the editor expands).
      await tester.ensureVisible(find.byKey(GroupKeys.markAsPaidButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(GroupKeys.markAsPaidButton));
      await tester.pumpAndSettle();

      expect(find.text('Amount must be greater than zero'), findsOneWidget);
      expect(settlementService.addCalls, isEmpty);
      expect(activityService.logCalls, isEmpty);
    });

    testWidgets('recording too much shows outstanding amount snackbar', (
      tester,
    ) async {
      final settlementService = _RecordingGroupSettlementService();
      final activityService = _RecordingGroupActivityService();

      await tester.pumpWidget(
        _wrap(
          const GroupSettleUpScreen(groupId: _groupId),
          balancesAsync: AsyncValue.data(_balancesOwed),
          currentUid: 'uid-bob',
          extraOverrides: [
            groupSettlementServiceProvider.overrideWithValue(settlementService),
            groupActivityServiceProvider.overrideWithValue(activityService),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(GroupKeys.settleUpRecordPaymentButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tap to edit amount'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '8.000');
      // #351 microcopy made the sheet taller; scroll the confirm button into
      // view (it can sit below the 800x600 test fold once the editor expands).
      await tester.ensureVisible(find.byKey(GroupKeys.markAsPaidButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(GroupKeys.markAsPaidButton));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Amount cannot exceed the outstanding balance'),
        findsOneWidget,
      );
      expect(settlementService.addCalls, isEmpty);
      expect(activityService.logCalls, isEmpty);
    });

    testWidgets('#530: ambiguous European amount is rejected, not silently '
        'coerced to the suggested amount', (tester) async {
      final settlementService = _RecordingGroupSettlementService();
      final activityService = _RecordingGroupActivityService();

      await tester.pumpWidget(
        _wrap(
          const GroupSettleUpScreen(groupId: _groupId),
          balancesAsync: AsyncValue.data(_balancesOwed),
          currentUid: 'uid-bob',
          extraOverrides: [
            groupSettlementServiceProvider.overrideWithValue(settlementService),
            groupActivityServiceProvider.overrideWithValue(activityService),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(GroupKeys.settleUpRecordPaymentButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tap to edit amount'));
      await tester.pumpAndSettle();
      // Pasted European grouping (dot thousands + comma decimal). The regression
      // guarded here is the SILENT fallback to the suggested amount once the
      // normalizer refuses to guess — it must reject, not record 7.750.
      await tester.enterText(find.byType(TextFormField), '1.234,56');
      await tester.ensureVisible(find.byKey(GroupKeys.markAsPaidButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(GroupKeys.markAsPaidButton));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a valid amount'), findsOneWidget);
      expect(settlementService.addCalls, isEmpty);
      expect(activityService.logCalls, isEmpty);
    });

    testWidgets('unknown service failure shows the generic message, not network (#360)', (
      tester,
    ) async {
      final settlementService = _RecordingGroupSettlementService(
        throwOnAdd: true,
      );
      final activityService = _RecordingGroupActivityService();

      await tester.pumpWidget(
        _wrap(
          const GroupSettleUpScreen(groupId: _groupId),
          balancesAsync: AsyncValue.data(_balancesOwed),
          currentUid: 'uid-bob',
          extraOverrides: [
            groupSettlementServiceProvider.overrideWithValue(settlementService),
            groupActivityServiceProvider.overrideWithValue(activityService),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(GroupKeys.settleUpRecordPaymentButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(GroupKeys.markAsPaidButton));
      await tester.pumpAndSettle();

      expect(
        find.text("Couldn't record settlement. Please try again."),
        findsOneWidget,
      );
      expect(
        find.text(
          "Couldn't record settlement. Check your connection and try again.",
        ),
        findsNothing,
      );
      expect(activityService.logCalls, isEmpty);
      // #367 honesty guard: a FAILED write must not nudge.
      expect(find.byKey(GroupKeys.settleNotifySheet), findsNothing);
    });

    testWidgets('permission-denied shows the not-allowed message, not network (#360)', (
      tester,
    ) async {
      final settlementService = _RecordingGroupSettlementService(
        errorToThrow: FirebaseException(
          plugin: 'cloud_firestore',
          code: 'permission-denied',
          message: 'Missing or insufficient permissions.',
        ),
      );
      final activityService = _RecordingGroupActivityService();

      await tester.pumpWidget(
        _wrap(
          const GroupSettleUpScreen(groupId: _groupId),
          balancesAsync: AsyncValue.data(_balancesOwed),
          currentUid: 'uid-bob',
          extraOverrides: [
            groupSettlementServiceProvider.overrideWithValue(settlementService),
            groupActivityServiceProvider.overrideWithValue(activityService),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(GroupKeys.settleUpRecordPaymentButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(GroupKeys.markAsPaidButton));
      await tester.pumpAndSettle();

      expect(
        find.text(
          "This settlement wasn't allowed. Please check the details and try again.",
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          "Couldn't record settlement. Check your connection and try again.",
        ),
        findsNothing,
      );
      expect(activityService.logCalls, isEmpty);
      // #367 honesty guard: a permission-denied write must not nudge.
      expect(find.byKey(GroupKeys.settleNotifySheet), findsNothing);
    });

    testWidgets('renders with preSelectedMemberId without crashing', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const GroupSettleUpScreen(
            groupId: _groupId,
            preSelectedMemberId: 'uid-bob',
          ),
          balancesAsync: AsyncValue.data(_balancesOwed),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Settle up'), findsOneWidget);
    });

    testWidgets('renders per-event breakdown context', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GroupSettleUpScreen(groupId: _groupId),
          balancesAsync: AsyncValue.data(_balancesOwed),
          events: [_testEvent],
          currentUid: 'uid-bob',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(GroupSettlementTile), findsOneWidget);
      expect(find.text('Settle up'), findsOneWidget);

      await tester.tap(find.byType(GroupSettlementTile));
      await tester.pumpAndSettle();

      expect(find.textContaining('Camping Weekend'), findsOneWidget);
    });

    testWidgets(
      'a breakdown entry whose event is not in the events list folds into the '
      '"Across events" residual row (#752 — display matches the write, which '
      'cannot target an off-list event)',
      (tester) async {
        const orphanEventId = 'missing-event-id-123456';
        final balances = (
          balances: _balancesOwed.balances,
          totalSpent: _balancesOwed.totalSpent,
          eventCount: _balancesOwed.eventCount,
          perEventBreakdown: <String, Map<String, Map<String, Decimal>>>{
            'uid-alice': {
              orphanEventId: {'OMR': Decimal.parse('7.750')},
            },
            'uid-bob': {
              orphanEventId: {'OMR': Decimal.parse('-7.750')},
            },
          },
          memberNames: _balancesOwed.memberNames,
          memberRawNames: _balancesOwed.memberRawNames,
        );

        await tester.pumpWidget(
          _wrap(
            const GroupSettleUpScreen(groupId: _groupId),
            balancesAsync: AsyncValue.data(balances),
            // events intentionally omitted → orphanEventId not in eventOrder.
            currentUid: 'uid-bob',
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byType(GroupSettlementTile));
        await tester.pumpAndSettle();

        // The orphan event is NOT rendered as a per-event row…
        expect(find.text('Event ...123456'), findsNothing);
        // …it folds into the cross-event residual.
        expect(find.text('Across events'), findsOneWidget);
      },
    );

    testWidgets('truncates long event names in breakdown labels', (
      tester,
    ) async {
      final longNameEvent = Event(
        id: 'event-1',
        name: 'A very long event name that should truncate',
        type: EventType.trip,
        groupId: _groupId,
        createdBy: 'uid-alice',
        participantIds: const ['uid-alice', 'uid-bob'],
        participantNames: const {'uid-alice': 'Alice', 'uid-bob': 'Bob'},
        modules: const EventModules(),
        startDate: DateTime(2026, 4, 2),
        createdAt: DateTime(2026, 4, 1),
      );

      await tester.pumpWidget(
        _wrap(
          const GroupSettleUpScreen(groupId: _groupId),
          balancesAsync: AsyncValue.data(_balancesOwed),
          events: [longNameEvent],
          currentUid: 'uid-bob',
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(GroupSettlementTile));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('A very long event name that...'),
        findsOneWidget,
      );
    });
  });

  // #382 PR-5 Task 13: stepped walk on the GROUP settle-up screen. Mirrors the
  // event-screen walk (Task 12) but pins the L6 bump asymmetry — group
  // settlements are live-watched, so the walk must NOT bump ledgerRevision —
  // and that each step logs a group_settlement activity row carrying its
  // BUCKET currency in metadata (the PR-4 stamp, per step).
  group('#382 PR-5: stepped settle walk (group screen)', () {
    testWidgets(
      'happy walk: two addGroupSettlement (OMR then USD), revision stays 0, '
      'two logGroupEvent with per-bucket currency, one final snackbar',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'settings_device_name': 'Bobby',
        });
        final prefs = await SharedPreferences.getInstance();
        final settlementService = _RecordingGroupSettlementService();
        final activityService = _RecordingGroupActivityService();

        await tester.pumpWidget(
          _wrap(
            const GroupSettleUpScreen(groupId: _groupId),
            balancesAsync: AsyncValue.data(_balancesTwoBucket),
            currentUid: 'uid-bob',
            extraOverrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              groupSettlementServiceProvider.overrideWithValue(
                settlementService,
              ),
              groupActivityServiceProvider.overrideWithValue(activityService),
            ],
          ),
        );
        await tester.pumpAndSettle();

        final container = ProviderScope.containerOf(
          tester.element(find.byType(GroupSettleUpScreen)),
        );

        final card = find.byKey(const ValueKey('settle-stepped-uid-alice'));
        await tester.ensureVisible(card);
        await tester.tap(card);
        await tester.pumpAndSettle();

        // Step 1 of 2.
        expect(find.text('1 of 2'), findsOneWidget);
        await tester.tap(find.byKey(GroupKeys.markAsPaidButton));
        await tester.pumpAndSettle();

        // Step 2 of 2 (no final snackbar yet).
        expect(find.text('2 of 2'), findsOneWidget);
        await tester.tap(find.byKey(GroupKeys.markAsPaidButton));
        await tester.pumpAndSettle();

        expect(settlementService.addCalls, hasLength(2));
        expect(settlementService.addCalls[0].currency, 'OMR');
        expect(settlementService.addCalls[1].currency, 'USD');
        // L6: group settlements are live-watched — NO ledgerRevision bump.
        expect(container.read(ledgerRevisionProvider), 0);
        // Each step logs a group_settlement row carrying its BUCKET currency.
        expect(activityService.logCalls, hasLength(2));
        expect(activityService.logCalls[0].type, 'group_settlement');
        expect(activityService.logCalls[0].actorName, 'Bobby');
        expect(activityService.logCalls[0].metadata, {
          'amount': '10',
          'recipientId': 'uid-alice',
          'currency': 'OMR',
          'fromUserId': 'uid-bob',
          'toUserId': 'uid-alice',
          'fromName': 'Bob',
          'toName': 'Alice',
        });
        expect(activityService.logCalls[1].metadata, {
          'amount': '20',
          'recipientId': 'uid-alice',
          'currency': 'USD',
          'fromUserId': 'uid-bob',
          'toUserId': 'uid-alice',
          'fromName': 'Bob',
          'toName': 'Alice',
        });
        // One final summary snackbar; no per-step "Settlement recorded.".
        expect(find.text('Settlement recorded.'), findsNothing);
        expect(find.text('Recorded 2 payments.'), findsOneWidget);
      },
    );

    testWidgets(
      'offline walk: both writes queue, will-sync final snackbar, '
      'connectivity goes syncing, revision stays 0',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'settings_device_name': 'Bobby',
        });
        final prefs = await SharedPreferences.getInstance();
        final settlementService = _RecordingGroupSettlementService(
          neverAck: true,
        );
        final activityService = _RecordingGroupActivityService();
        final connectivity = ConnectivityNotifier(startPeriodicChecks: false)
          ..setOffline();

        await tester.pumpWidget(
          _wrap(
            const GroupSettleUpScreen(groupId: _groupId),
            balancesAsync: AsyncValue.data(_balancesTwoBucket),
            currentUid: 'uid-bob',
            extraOverrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              connectivityProvider.overrideWith((ref) => connectivity),
              groupSettlementServiceProvider.overrideWithValue(
                settlementService,
              ),
              groupActivityServiceProvider.overrideWithValue(activityService),
            ],
          ),
        );
        await tester.pumpAndSettle();

        final container = ProviderScope.containerOf(
          tester.element(find.byType(GroupSettleUpScreen)),
        );

        final card = find.byKey(const ValueKey('settle-stepped-uid-alice'));
        await tester.ensureVisible(card);
        await tester.tap(card);
        await tester.pumpAndSettle();

        // Step 1: confirm. The write never acks — fixed pumps only (never
        // pumpAndSettle while the write future is deliberately pending).
        expect(find.text('1 of 2'), findsOneWidget);
        await tester.tap(find.byKey(GroupKeys.markAsPaidButton));
        await tester.pump();
        await tester.pump(const Duration(seconds: 6));
        await tester.pump(const Duration(milliseconds: 500));

        // Step 2: the next sheet is presented; confirm it too.
        expect(find.text('2 of 2'), findsOneWidget);
        await tester.tap(find.byKey(GroupKeys.markAsPaidButton));
        await tester.pump();
        await tester.pump(const Duration(seconds: 6));
        await tester.pump(const Duration(milliseconds: 500));

        // Both writes were handed to the SDK queue (noteQueuedWrite per step).
        expect(settlementService.addCalls, hasLength(2));
        expect(connectivity.state, ConnectivityStatus.syncing);
        // Both activity rows were ALSO queued (not lost behind the hung await).
        expect(activityService.logCalls, hasLength(2));
        // L6 holds offline too.
        expect(container.read(ledgerRevisionProvider), 0);
        // The final summary reports the queued (will-sync) outcome.
        expect(
          find.text('Recorded 2 payments — will sync when online.'),
          findsOneWidget,
        );
      },
    );
  });
}
