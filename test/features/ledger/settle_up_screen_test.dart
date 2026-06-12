import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/core/providers/connectivity_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/shared/widgets/offline_banner.dart';
import 'package:safar/shared/widgets/skeleton_loader.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/keys/group_keys.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/widgets/group_settlement_tile.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/ledger/screens/settle_up_screen.dart';
import 'package:safar/features/ledger/services/settlement_service.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

class _MockSettlementService extends Mock implements SettlementService {}

void main() {
  const groupId = 'group-1';
  const eventId = 'event-1';
  const eventRef = (groupId: groupId, eventId: eventId);

  final event = Event(
    id: eventId,
    groupId: groupId,
    name: 'Beach Trip',
    type: EventType.trip,
    createdBy: 'alice',
    participantIds: const ['alice', 'bob'],
    participantNames: const {'alice': 'Alice', 'bob': 'Bob'},
    modules: const EventModules(),
    createdAt: DateTime(2026, 5, 16),
  );

  final expenses = [
    Expense(
      id: 'expense-1',
      tripId: eventId,
      payerParticipantId: 'alice',
      amount: Decimal.parse('20.000'),
      description: 'Dinner',
      scope: ExpenseScope.global,
      createdAt: DateTime(2026, 5, 16),
      createdBy: 'alice',
    ),
  ];

  Widget buildScreen(
    FakeFirebaseFirestore fakeDb, {
    Locale? locale,
    String? currentUid = 'bob',
    Stream<Event?>? eventStream,
    Stream<List<Expense>>? expensesStream,
    Stream<List<Settlement>>? settlementsStream,
    SettlementService? settlementService,
    bool router = false,
    String? preSelectedMemberId,
    List<Override> extraOverrides = const [],
  }) {
    final overrides = [
      currentUserIdProvider.overrideWithValue(currentUid),
      eventDetailProvider(
        eventRef,
      ).overrideWith((ref) => eventStream ?? Stream.value(event)),
      eventExpensesProvider(
        eventRef,
      ).overrideWith((ref) => expensesStream ?? Stream.value(expenses)),
      eventSettlementsProvider(eventRef).overrideWith(
        (ref) => settlementsStream ?? Stream.value(const <Settlement>[]),
      ),
      groupMembersProvider(groupId).overrideWith((ref) => Stream.value([])),
      // #261: SettleUpScreen now gates on the group resolving to read its
      // currency. Override groupDetailProvider (it otherwise binds real
      // Firestore) or the screen hangs on the loader. createdBy is a literal,
      // NOT the nullable currentUid param (Group.createdBy is non-null).
      groupDetailProvider(groupId).overrideWith(
        (ref) => Stream.value(
          Group(
            id: groupId,
            name: 'Trip',
            inviteCode: 'ABC123',
            createdBy: 'bob',
            memberIds: const [],
            currency: 'OMR',
            createdAt: DateTime(2026),
          ),
        ),
      ),
      settlementServiceProvider.overrideWithValue(
        settlementService ?? SettlementService.withFirestore(fakeDb),
      ),
      ...extraOverrides,
    ];

    final child = router
        ? MaterialApp.router(
            theme: AppTheme.lightTheme,
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: GoRouter(
              initialLocation:
                  '/group/$groupId/event/$eventId/ledger/settle-up',
              routes: [
                GoRoute(
                  path: '/home',
                  builder: (_, _) => const Scaffold(body: Text('Home')),
                ),
                GoRoute(
                  path: '/group/:gid/event/:eid/ledger',
                  builder: (_, state) => Scaffold(
                    body: Text('Ledger:${state.pathParameters['eid']}'),
                  ),
                ),
                GoRoute(
                  path: '/group/:gid/event/:eid/ledger/settle-up',
                  builder: (_, state) => SettleUpScreen(
                    groupId: state.pathParameters['gid']!,
                    eventId: state.pathParameters['eid']!,
                  ),
                ),
              ],
            ),
          )
        : MaterialApp(
            theme: AppTheme.lightTheme,
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: SettleUpScreen(
              groupId: groupId,
              eventId: eventId,
              preSelectedMemberId: preSelectedMemberId,
            ),
          );

    return ProviderScope(overrides: overrides, child: child);
  }

  testWidgets('shows loading state while event is loading', (tester) async {
    final fakeDb = FakeFirebaseFirestore();
    final controller = StreamController<Event?>();
    addTearDown(controller.close);

    await tester.pumpWidget(
      buildScreen(fakeDb, eventStream: controller.stream),
    );
    await tester.pump();

    expect(find.byType(SkeletonLoader), findsOneWidget); // #355
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('missing event state routes home', (tester) async {
    final fakeDb = FakeFirebaseFirestore();

    await tester.pumpWidget(
      buildScreen(
        fakeDb,
        eventStream: Stream<Event?>.value(null),
        router: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('This event no longer exists'), findsOneWidget);

    await tester.tap(find.text('Go Home'));
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('shows loading state while expenses are loading', (tester) async {
    final fakeDb = FakeFirebaseFirestore();
    final controller = StreamController<List<Expense>>();
    addTearDown(controller.close);

    await tester.pumpWidget(
      buildScreen(fakeDb, expensesStream: controller.stream),
    );
    await tester.pump();

    expect(find.byType(SkeletonLoader), findsOneWidget); // #355
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('expense error state retry stays on error UI', (tester) async {
    final fakeDb = FakeFirebaseFirestore();

    await tester.pumpWidget(
      buildScreen(
        fakeDb,
        expensesStream: Stream<List<Expense>>.error(StateError('load failed')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text("Couldn't load balances."), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't load balances."), findsOneWidget);
  });

  testWidgets('direct-entry back button routes to event ledger', (
    tester,
  ) async {
    final fakeDb = FakeFirebaseFirestore();

    await tester.pumpWidget(buildScreen(fakeDb, router: true));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Iconsax.arrow_left_2));
    await tester.pumpAndSettle();

    expect(find.text('Ledger:event-1'), findsOneWidget);
  });

  testWidgets('records settlement with resolved participant names', (
    tester,
  ) async {
    final fakeDb = FakeFirebaseFirestore();

    await tester.pumpWidget(buildScreen(fakeDb));
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(GroupKeys.settleUpRecordPaymentButton),
    );
    await tester.tap(find.byKey(GroupKeys.settleUpRecordPaymentButton));
    await tester.pumpAndSettle();

    expect(find.byKey(GroupKeys.settleUpRecordSheetTitle), findsOneWidget);

    await tester.tap(find.byKey(GroupKeys.markAsPaidButton));
    await tester.pumpAndSettle();

    final snap = await fakeDb
        .collection('groups')
        .doc(groupId)
        .collection('events')
        .doc(eventId)
        .collection('settlements')
        .get();

    expect(snap.docs, hasLength(1));
    expect(snap.docs.first.data()['payerParticipantId'], equals('bob'));
    expect(snap.docs.first.data()['recipientParticipantId'], equals('alice'));
    expect(snap.docs.first.data()['payerName'], equals('Bob'));
    expect(snap.docs.first.data()['recipientName'], equals('Alice'));
    expect(find.byType(OfflineBanner), findsOneWidget);
  });

  testWidgets(
    '#357: an offline settlement flips connectivity to syncing '
    '("Saved — will sync")',
    (tester) async {
      final fakeDb = FakeFirebaseFirestore();
      // Timer-free notifier seeded offline; the write should set it to syncing.
      // Riverpod owns the overridden instance and disposes it on teardown, so
      // no addTearDown here (that would double-dispose).
      final connectivity = ConnectivityNotifier(startPeriodicChecks: false)
        ..setOffline();

      await tester.pumpWidget(
        buildScreen(
          fakeDb,
          extraOverrides: [
            connectivityProvider.overrideWith((ref) => connectivity),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(GroupKeys.settleUpRecordPaymentButton),
      );
      await tester.tap(find.byKey(GroupKeys.settleUpRecordPaymentButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(GroupKeys.markAsPaidButton));
      await tester.pumpAndSettle();

      expect(connectivity.state, ConnectivityStatus.syncing);
    },
  );

  testWidgets(
    '#412: an offline settlement whose write never acks still confirms '
    'within bounded time',
    (tester) async {
      registerFallbackValue(Decimal.zero);
      final fakeDb = FakeFirebaseFirestore();
      // Real offline behavior: addSettlement's Firestore set() future stays
      // pending until reconnect — FakeFirebaseFirestore can't model this.
      final service = _MockSettlementService();
      when(
        () => service.addSettlement(
          groupId: any(named: 'groupId'),
          eventId: any(named: 'eventId'),
          payerParticipantId: any(named: 'payerParticipantId'),
          recipientParticipantId: any(named: 'recipientParticipantId'),
          payerName: any(named: 'payerName'),
          recipientName: any(named: 'recipientName'),
          amount: any(named: 'amount'),
          currency: any(named: 'currency'),
          createdBy: any(named: 'createdBy'),
          note: any(named: 'note'),
        ),
      ).thenAnswer((_) => Completer<Settlement>().future);

      final connectivity = ConnectivityNotifier(startPeriodicChecks: false)
        ..setOffline();

      await tester.pumpWidget(
        buildScreen(
          fakeDb,
          settlementService: service,
          extraOverrides: [
            connectivityProvider.overrideWith((ref) => connectivity),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(SettleUpScreen)),
      );

      await tester.ensureVisible(
        find.byKey(GroupKeys.settleUpRecordPaymentButton),
      );
      await tester.tap(find.byKey(GroupKeys.settleUpRecordPaymentButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(GroupKeys.markAsPaidButton));
      await tester.pump();
      // Past kWriteAckTimeout — fixed pumps only (never pumpAndSettle while
      // racing; the snackbar entrance also needs a frame).
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        find.text('Settlement recorded — will sync when online.'),
        findsOneWidget,
      );
      expect(container.read(ledgerRevisionProvider), 1); // #104 bump fired
      expect(connectivity.state, ConnectivityStatus.syncing);
    },
  );

  testWidgets(
    '#282: creditor records a received payment — payer=debtor, '
    'recipient=creditor, createdBy=creditor',
    (tester) async {
      final fakeDb = FakeFirebaseFirestore();

      // Alice paid the 20.000 dinner; Bob owes her 10.000 → Alice is the
      // creditor. She records that Bob repaid her in cash.
      await tester.pumpWidget(buildScreen(fakeDb, currentUid: 'alice'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(GroupKeys.settleUpRecordPaymentButton),
      );
      await tester.tap(find.byKey(GroupKeys.settleUpRecordPaymentButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(GroupKeys.markAsPaidButton));
      await tester.pumpAndSettle();

      final snap = await fakeDb
          .collection('groups')
          .doc(groupId)
          .collection('events')
          .doc(eventId)
          .collection('settlements')
          .get();

      expect(snap.docs, hasLength(1));
      // Direction is fixed by the debt, not by who tapped record.
      expect(snap.docs.first.data()['payerParticipantId'], equals('bob'));
      expect(snap.docs.first.data()['recipientParticipantId'], equals('alice'));
      // The actor (creditor) is the audited author.
      expect(snap.docs.first.data()['createdBy'], equals('alice'));
    },
  );

  testWidgets('zero settlement amount shows validation snackbar', (
    tester,
  ) async {
    final fakeDb = FakeFirebaseFirestore();

    await tester.pumpWidget(buildScreen(fakeDb));
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

    expect(find.text('Amount must be greater than zero'), findsOneWidget);
  });

  testWidgets('too-large settlement amount shows outstanding snackbar', (
    tester,
  ) async {
    final fakeDb = FakeFirebaseFirestore();

    await tester.pumpWidget(buildScreen(fakeDb));
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(GroupKeys.settleUpRecordPaymentButton),
    );
    await tester.tap(find.byKey(GroupKeys.settleUpRecordPaymentButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tap to edit amount'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '11.000');
    await tester.ensureVisible(find.byKey(GroupKeys.markAsPaidButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(GroupKeys.markAsPaidButton));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Amount cannot exceed the outstanding balance'),
      findsOneWidget,
    );
  });

  testWidgets('unknown write failure shows the generic message, not network (#360)', (
    tester,
  ) async {
    final fakeDb = FakeFirebaseFirestore();

    await tester.pumpWidget(
      buildScreen(fakeDb, settlementService: _FailingSettlementService()),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(GroupKeys.settleUpRecordPaymentButton),
    );
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
  });

  testWidgets('permission-denied shows the not-allowed message, not network (#360)', (
    tester,
  ) async {
    final fakeDb = FakeFirebaseFirestore();

    await tester.pumpWidget(
      buildScreen(fakeDb, settlementService: _DeniedSettlementService()),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(GroupKeys.settleUpRecordPaymentButton),
    );
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
  });

  testWidgets(
    '#382 PR-5: preSelectedMemberId highlights the matching tile',
    (tester) async {
      final fakeDb = FakeFirebaseFirestore();

      // Bob owes Alice 10.000 — one tile; alice is the toUserId party.
      await tester.pumpWidget(
        buildScreen(fakeDb, preSelectedMemberId: 'alice'),
      );
      await tester.pumpAndSettle();

      final tile = tester.widget<GroupSettlementTile>(
        find.byType(GroupSettlementTile),
      );
      expect(tile.isHighlighted, isTrue);
    },
  );

  testWidgets('back arrow is mirrored under Arabic RTL (#126)', (tester) async {
    final fakeDb = FakeFirebaseFirestore();

    await tester.pumpWidget(buildScreen(fakeDb, locale: const Locale('ar')));
    await tester.pumpAndSettle();

    expect(find.byIcon(Iconsax.arrow_left_2), findsOneWidget);
    final mirrored = tester
        .widgetList<Transform>(
          find.ancestor(
            of: find.byIcon(Iconsax.arrow_left_2),
            matching: find.byType(Transform),
          ),
        )
        .any((t) => t.transform.getRow(0).x == -1.0);
    expect(mirrored, isTrue);
  });
}

class _FailingSettlementService extends SettlementService {
  _FailingSettlementService() : super.withFirestore(FakeFirebaseFirestore());

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
  }) {
    throw StateError('write failed');
  }
}

class _DeniedSettlementService extends SettlementService {
  _DeniedSettlementService() : super.withFirestore(FakeFirebaseFirestore());

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
  }) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
      message: 'Missing or insufficient permissions.',
    );
  }
}
