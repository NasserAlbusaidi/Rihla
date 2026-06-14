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
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safar/shared/widgets/offline_banner.dart';
import 'package:safar/shared/widgets/skeleton_loader.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/keys/group_keys.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/widgets/group_settlement_tile.dart';
import 'package:safar/core/models/split_mode.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/ledger/widgets/pre_settlement_review_sheet.dart';
import 'package:safar/features/ledger/screens/settle_up_screen.dart';
import 'package:safar/features/ledger/services/settlement_service.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

class _MockSettlementService extends Mock implements SettlementService {}

void main() {
  const groupId = 'group-1';
  const eventId = 'event-1';
  const eventRef = (groupId: groupId, eventId: eventId);

  // The ≥2-bucket settle-up body renders the one-time currencies-don't-net
  // explainer (#382 PR-5), a ConsumerWidget reading settingsProvider — so every
  // app-booting test here must override sharedPreferencesProvider.
  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

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
      sharedPreferencesProvider.overrideWithValue(prefs),
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

  testWidgets(
    '#204: pre-settlement review sheet appears on entry with a review-worthy expense',
    (tester) async {
      final fakeDb = FakeFirebaseFirestore();
      await tester.pumpWidget(
        buildScreen(
          fakeDb,
          expensesStream: Stream.value([
            Expense(
              id: 'e1',
              tripId: eventId,
              payerParticipantId: 'alice',
              amount: Decimal.parse('20.000'),
              description: 'Dinner',
              scope: ExpenseScope.global,
              splitMode: SplitMode.exact,
              createdAt: DateTime(2026, 5, 16),
              createdBy: 'alice',
            ),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(PreSettleReviewKeys.sheet), findsOneWidget);
      expect(find.text('Before you settle'), findsOneWidget);
    },
  );

  testWidgets(
    '#204: no review sheet when all expenses are ordinary equal splits',
    (tester) async {
      final fakeDb = FakeFirebaseFirestore();
      await tester.pumpWidget(buildScreen(fakeDb)); // default: 1 global equal
      await tester.pumpAndSettle();

      expect(find.byKey(PreSettleReviewKeys.sheet), findsNothing);
    },
  );

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

  // #382 PR-5 Task 12: stepped walk on the event settle-up screen. A
  // counterparty owing across two currency buckets surfaces one stepped card;
  // tapping it walks one record sheet per bucket (each its own independent
  // write), suppressing per-step success snackbars and emitting ONE final
  // summary snackbar.
  group('#382 PR-5: stepped settle walk', () {
    // Two same-direction buckets (bob owes alice in OMR + USD): alice paid one
    // expense in each currency, so bob is the payer in both buckets.
    final twoBucketExpenses = [
      Expense(
        id: 'expense-omr',
        tripId: eventId,
        payerParticipantId: 'alice',
        amount: Decimal.parse('20.000'),
        currency: 'OMR',
        description: 'Dinner',
        scope: ExpenseScope.global,
        createdAt: DateTime(2026, 5, 16),
        createdBy: 'alice',
      ),
      Expense(
        id: 'expense-usd',
        tripId: eventId,
        payerParticipantId: 'alice',
        amount: Decimal.parse('80.00'),
        currency: 'USD',
        description: 'Hotel',
        scope: ExpenseScope.global,
        createdAt: DateTime(2026, 5, 16),
        createdBy: 'alice',
      ),
    ];

    // Mixed-direction buckets (orthogonal axis — identity/direction): bob owes
    // alice OMR (bob = payer → "Mark paid"), alice owes bob USD (bob =
    // recipient → "Mark received"). Two #282 framings within one walk.
    final mixedDirectionExpenses = [
      Expense(
        id: 'expense-omr',
        tripId: eventId,
        payerParticipantId: 'alice',
        amount: Decimal.parse('20.000'),
        currency: 'OMR',
        description: 'Dinner',
        scope: ExpenseScope.global,
        createdAt: DateTime(2026, 5, 16),
        createdBy: 'alice',
      ),
      Expense(
        id: 'expense-usd',
        tripId: eventId,
        payerParticipantId: 'bob',
        amount: Decimal.parse('80.00'),
        currency: 'USD',
        description: 'Hotel',
        scope: ExpenseScope.global,
        createdAt: DateTime(2026, 5, 16),
        createdBy: 'bob',
      ),
    ];

    testWidgets(
      'happy walk: two writes (OMR then USD), two bumps, one final snackbar, '
      'no per-step success snackbar',
      (tester) async {
        registerFallbackValue(Decimal.zero);
        final fakeDb = FakeFirebaseFirestore();
        final service = _RecordingSettlementService();

        await tester.pumpWidget(
          buildScreen(
            fakeDb,
            settlementService: service,
            expensesStream: Stream.value(twoBucketExpenses),
          ),
        );
        await tester.pumpAndSettle();

        final container = ProviderScope.containerOf(
          tester.element(find.byType(SettleUpScreen)),
        );

        final card = find.byKey(const ValueKey('settle-stepped-alice'));
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

        expect(service.calls, hasLength(2));
        expect(service.calls[0].currency, 'OMR');
        expect(service.calls[1].currency, 'USD');
        // Two independent #104 bumps.
        expect(container.read(ledgerRevisionProvider), 2);
        // One final summary snackbar; no per-step "Settlement recorded.".
        expect(find.text('Settlement recorded.'), findsNothing);
        expect(find.text('Recorded 2 payments.'), findsOneWidget);
      },
    );

    testWidgets('cancel at step 2: one write, partial final snackbar', (
      tester,
    ) async {
      registerFallbackValue(Decimal.zero);
      final fakeDb = FakeFirebaseFirestore();
      final service = _RecordingSettlementService();

      await tester.pumpWidget(
        buildScreen(
          fakeDb,
          settlementService: service,
          expensesStream: Stream.value(twoBucketExpenses),
        ),
      );
      await tester.pumpAndSettle();

      final card = find.byKey(const ValueKey('settle-stepped-alice'));
      await tester.ensureVisible(card);
      await tester.tap(card);
      await tester.pumpAndSettle();

      // Confirm step 1, cancel step 2 ("Not yet").
      await tester.tap(find.byKey(GroupKeys.markAsPaidButton));
      await tester.pumpAndSettle();
      expect(find.text('2 of 2'), findsOneWidget);
      await tester.tap(find.byKey(GroupKeys.notNowButton));
      await tester.pumpAndSettle();

      expect(service.calls, hasLength(1));
      expect(find.text('Recorded 1 of 2 payments.'), findsOneWidget);
    });

    testWidgets(
      'write error at step 2: one write, error snackbar, partial snackbar, '
      'walk stopped',
      (tester) async {
        registerFallbackValue(Decimal.zero);
        final fakeDb = FakeFirebaseFirestore();
        final service = _RecordingSettlementService(throwOnCall: 2);

        await tester.pumpWidget(
          buildScreen(
            fakeDb,
            settlementService: service,
            expensesStream: Stream.value(twoBucketExpenses),
          ),
        );
        await tester.pumpAndSettle();

        final card = find.byKey(const ValueKey('settle-stepped-alice'));
        await tester.ensureVisible(card);
        await tester.tap(card);
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(GroupKeys.markAsPaidButton));
        await tester.pumpAndSettle();
        expect(find.text('2 of 2'), findsOneWidget);
        await tester.tap(find.byKey(GroupKeys.markAsPaidButton));
        await tester.pumpAndSettle();

        expect(service.calls, hasLength(2));
        // #360 error snackbar shows first (L4 — errors stay loud per step).
        expect(
          find.text("Couldn't record settlement. Please try again."),
          findsOneWidget,
        );
        // No further sheet pushed — the walk stopped.
        expect(find.byKey(GroupKeys.settleUpRecordSheetTitle), findsNothing);

        // The final partial summary is queued behind the error snackbar; let
        // the error auto-dismiss so the summary surfaces (L3).
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        expect(find.text('Recorded 1 of 2 payments.'), findsOneWidget);
      },
    );

    testWidgets(
      'mixed-direction walk: step 1 "Mark paid", step 2 "Mark received"; '
      'each write preserves its bucket payer/recipient direction',
      (tester) async {
        registerFallbackValue(Decimal.zero);
        final fakeDb = FakeFirebaseFirestore();
        final service = _RecordingSettlementService();

        await tester.pumpWidget(
          buildScreen(
            fakeDb,
            settlementService: service,
            expensesStream: Stream.value(mixedDirectionExpenses),
          ),
        );
        await tester.pumpAndSettle();

        final card = find.byKey(const ValueKey('settle-stepped-alice'));
        await tester.ensureVisible(card);
        await tester.tap(card);
        await tester.pumpAndSettle();

        // Step 1 (OMR): bob owes alice → "Mark this paid?".
        expect(find.text('Mark this paid?'), findsOneWidget);
        await tester.tap(find.byKey(GroupKeys.markAsPaidButton));
        await tester.pumpAndSettle();

        // Step 2 (USD): #282 flips — alice owes bob → "Mark this received?".
        expect(find.text('Mark this received?'), findsOneWidget);
        await tester.tap(find.byKey(GroupKeys.markAsPaidButton));
        await tester.pumpAndSettle();

        expect(service.calls, hasLength(2));
        // OMR step: bob is payer, alice recipient.
        expect(service.calls[0].currency, 'OMR');
        expect(service.calls[0].payerParticipantId, 'bob');
        expect(service.calls[0].recipientParticipantId, 'alice');
        // USD step: direction reverses (alice owes bob).
        expect(service.calls[1].currency, 'USD');
        expect(service.calls[1].payerParticipantId, 'alice');
        expect(service.calls[1].recipientParticipantId, 'bob');
      },
    );
  });
}

/// Records each [addSettlement] call so a stepped walk can be asserted, and
/// returns a deserialized [Settlement] (the acked path). [throwOnCall] (1-based)
/// makes that call throw to exercise the per-step error stop.
class _RecordingSettlementService extends SettlementService {
  _RecordingSettlementService({this.throwOnCall})
    : super.withFirestore(FakeFirebaseFirestore());

  final int? throwOnCall;
  final List<({
    String payerParticipantId,
    String recipientParticipantId,
    String currency,
    Decimal amount,
  })>
  calls = [];

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
  }) async {
    calls.add((
      payerParticipantId: payerParticipantId,
      recipientParticipantId: recipientParticipantId,
      currency: currency,
      amount: amount,
    ));
    if (throwOnCall != null && calls.length == throwOnCall) {
      throw StateError('write failed');
    }
    return Settlement(
      id: 'settlement-${calls.length}',
      tripId: eventId,
      payerParticipantId: payerParticipantId,
      recipientParticipantId: recipientParticipantId,
      amount: amount,
      currency: currency,
      createdBy: createdBy,
      settledAt: DateTime(2026, 5, 16),
    );
  }
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
