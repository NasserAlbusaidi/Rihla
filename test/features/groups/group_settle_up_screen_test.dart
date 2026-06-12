import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/shared/widgets/skeleton_loader.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/connectivity_provider.dart';
import 'package:safar/core/providers/settings_provider.dart';
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
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

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
  perEventBreakdown: <String, Map<String, Decimal>>{
    'uid-alice': {'event-1': Decimal.parse('7.750')},
    'uid-bob': {'event-1': Decimal.parse('-7.750')},
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
  perEventBreakdown: <String, Map<String, Decimal>>{},
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
  perEventBreakdown: <String, Map<String, Decimal>>{},
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

      await tester.tap(find.text('Go Home'));
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

        expect(find.text('Settle Up'), findsOneWidget);
        // The count lives in the italic headline ("One transfer, …") …
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
      });
    });

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

      expect(find.text('Settle Up'), findsOneWidget);
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
      expect(find.text('Settle Up'), findsOneWidget);

      await tester.tap(find.byType(GroupSettlementTile));
      await tester.pumpAndSettle();

      expect(find.textContaining('Camping Weekend'), findsOneWidget);
    });

    testWidgets('renders fallback label for unknown long event id', (
      tester,
    ) async {
      const longEventId = 'missing-event-id-123456';
      final balances = (
        balances: _balancesOwed.balances,
        totalSpent: _balancesOwed.totalSpent,
        eventCount: _balancesOwed.eventCount,
        perEventBreakdown: <String, Map<String, Decimal>>{
          'uid-alice': {longEventId: Decimal.parse('7.750')},
          'uid-bob': {longEventId: Decimal.parse('-7.750')},
        },
        memberNames: _balancesOwed.memberNames,
        memberRawNames: _balancesOwed.memberRawNames,
      );

      await tester.pumpWidget(
        _wrap(
          const GroupSettleUpScreen(groupId: _groupId),
          balancesAsync: AsyncValue.data(balances),
          currentUid: 'uid-bob',
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(GroupSettlementTile));
      await tester.pumpAndSettle();

      expect(find.text('Event ...123456'), findsOneWidget);
    });

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
}
