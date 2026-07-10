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
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:safar/core/providers/connectivity_provider.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/services/firebase_functions_service.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safar/shared/widgets/offline_banner.dart';
import 'package:safar/shared/widgets/skeleton_loader.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/keys/group_keys.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/widgets/group_settlement_tile.dart';
import 'package:safar/features/groups/widgets/settle_up_page_body.dart';
import 'package:safar/core/models/split_mode.dart';
import 'package:safar/features/ledger/keys/ledger_keys.dart';
import 'package:safar/features/ledger/models/correct_settlement_result.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/ledger/widgets/pre_settlement_review_sheet.dart';
import 'package:safar/features/groups/services/group_activity_service.dart';
import 'package:safar/features/ledger/screens/settle_up_screen.dart';
import 'package:safar/features/ledger/services/settlement_service.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

class _MockSettlementService extends Mock implements SettlementService {}

class _MockFunctionsService extends Mock implements FirebaseFunctionsService {}

class _MockUrlLauncher extends Mock
    with MockPlatformInterfaceMixin
    implements UrlLauncherPlatform {}

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
    bool embedded = false,
    String? preSelectedMemberId,
    List<GroupMember>? groupMembers,
    Stream<List<GroupMember>>? groupMembersStream,
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
      groupMembersProvider(
        groupId,
      ).overrideWith(
        (ref) => groupMembersStream ?? Stream.value(groupMembers ?? const []),
      ),
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
      // #831: the record path fire-and-forgets an event_settlement activity
      // row; back it with the same fake so tests can assert on
      // groups/{gid}/activity (an unoverridden service throws [core/no-app]
      // into its swallowing catchError → false-empty collection).
      groupActivityServiceProvider.overrideWithValue(
        GroupActivityService.withFirestore(fakeDb),
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
                // #818 Wave 5.3: recap route stub — the real route is nested
                // under /group/:gid in app_router.dart, but this flat stub is
                // enough to prove the CTA pushes the right path.
                GoRoute(
                  path: '/group/:gid/event/:eid/recap',
                  builder: (_, state) => Scaffold(
                    body: Text('Recap:${state.pathParameters['eid']}'),
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
            home: embedded
                ? Scaffold(
                    body: SettleUpScreen(
                      groupId: groupId,
                      eventId: eventId,
                      preSelectedMemberId: preSelectedMemberId,
                      embedded: true,
                    ),
                  )
                : SettleUpScreen(
                    groupId: groupId,
                    eventId: eventId,
                    preSelectedMemberId: preSelectedMemberId,
                  ),
          );

    return ProviderScope(overrides: overrides, child: child);
  }

  // ── #758: embedded mode (tab panel inside the tabbed event view) ─────────

  testWidgets('#758 embedded mode renders the body without its own chrome', (
    tester,
  ) async {
    final fakeDb = FakeFirebaseFirestore();
    await tester.pumpWidget(buildScreen(fakeDb, embedded: true));
    await tester.pumpAndSettle();

    // Settle content renders…
    expect(find.byType(SettleUpPageBody), findsOneWidget);
    // …but no top bar (title + back), no offline banner, no nested Scaffold —
    // the tabbed shell owns all chrome.
    final l10n = AppLocalizations.of(
      tester.element(find.byType(SettleUpPageBody)),
    );
    expect(find.text(l10n.settleUpTitle), findsNothing);
    expect(find.byIcon(Iconsax.arrow_left_2), findsNothing);
    expect(find.byType(OfflineBanner), findsNothing);
    expect(
      find.descendant(
        of: find.byType(SettleUpScreen),
        matching: find.byType(Scaffold),
      ),
      findsNothing,
    );
  });

  testWidgets(
    '#789→#1078 embedded mode uses the default gutter — the workspace FAB '
    'no longer overlays the Settle up tab, so no clearance is reserved',
    (tester) async {
      final fakeDb = FakeFirebaseFirestore();
      await tester.pumpWidget(buildScreen(fakeDb, embedded: true));
      await tester.pumpAndSettle();

      final body = tester.widget<SettleUpPageBody>(
        find.byType(SettleUpPageBody),
      );
      expect(body.bottomInset, 24);
    },
  );

  testWidgets('#789 standalone mode keeps the default bottom gutter', (
    tester,
  ) async {
    final fakeDb = FakeFirebaseFirestore();
    await tester.pumpWidget(buildScreen(fakeDb));
    await tester.pumpAndSettle();

    final body = tester.widget<SettleUpPageBody>(
      find.byType(SettleUpPageBody),
    );
    expect(body.bottomInset, 24);
  });

  // #818 Wave 5.3: nav-only CTA from standalone settle-up to the existing
  // recap route (export stays owned by the recap screen). Scope: standalone
  // event settle-up ONLY — no group entry (Trip Receipt is event-scoped,
  // #704 open), no embedded entry (the Recap tab sits in the same tab strip).
  group('#818 Wave 5.3: recap CTA', () {
    testWidgets(
      'standalone shows the recap CTA and navigates to the recap route',
      (tester) async {
        final fakeDb = FakeFirebaseFirestore();

        await tester.pumpWidget(buildScreen(fakeDb, router: true));
        await tester.pumpAndSettle();

        expect(find.byKey(LedgerKeys.settleUpRecapCta), findsOneWidget);

        await tester.ensureVisible(find.byKey(LedgerKeys.settleUpRecapCta));
        await tester.tap(find.byKey(LedgerKeys.settleUpRecapCta));
        await tester.pumpAndSettle();

        expect(find.text('Recap:event-1'), findsOneWidget);
      },
    );

    testWidgets('embedded hides the recap CTA', (tester) async {
      final fakeDb = FakeFirebaseFirestore();

      await tester.pumpWidget(buildScreen(fakeDb, embedded: true));
      await tester.pumpAndSettle();

      expect(find.byKey(LedgerKeys.settleUpRecapCta), findsNothing);
    });

    testWidgets('empty ledger hides the recap CTA', (tester) async {
      final fakeDb = FakeFirebaseFirestore();

      await tester.pumpWidget(
        buildScreen(fakeDb, expensesStream: Stream.value(const <Expense>[])),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(LedgerKeys.settleUpRecapCta), findsNothing);
    });
  });

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

    await tester.tap(find.text('Go home'));
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
    '#1030: members HARD error → loud balances error view, no basis, no sheet',
    (tester) async {
      // Re-scopes the old #204 fallback pin: with no members value the #249
      // universe cannot be built — rendering suggestions would be WRONG money
      // (departed recipients dropped), so the screen goes loud and no settle
      // write is reachable at all, which dominates "warn but allow".
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
          groupMembersStream: Stream.error(StateError('members failed')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text("Couldn't load balances."), findsOneWidget);
      expect(find.byKey(PreSettleReviewKeys.sheet), findsNothing);
    },
  );

  testWidgets(
    '#1030 (#204/#898 preserved): members STALE-VALUED error → basis renders, '
    'sheet still shows warnings',
    (tester) async {
      final fakeDb = FakeFirebaseFirestore();
      final members = StreamController<List<GroupMember>>();
      addTearDown(members.close);
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
          groupMembersStream: members.stream,
        ),
      );
      members.add(const []); // value first…
      await tester.pump();
      members.addError(StateError('members failed')); // …then stale-valued
      await tester.pumpAndSettle();

      expect(find.byKey(PreSettleReviewKeys.sheet), findsOneWidget);
      expect(find.text('Exact split'), findsOneWidget);
      expect(find.text("Couldn't load balances."), findsNothing);
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

  testWidgets(
    '#204: an expense paid by a DEPARTED member surfaces "Payer left"',
    (tester) async {
      final fakeDb = FakeFirebaseFirestore();

      // "gone" was a participant when they paid (so they remain in the
      // event roster) but has since LEFT the group (hard-delete → absent from
      // the live roster). Correct wiring diffs the payer against active event
      // participants who are still live group members → flags it.
      final eventWithDeparted = Event(
        id: eventId,
        groupId: groupId,
        name: 'Beach Trip',
        type: EventType.trip,
        createdBy: 'alice',
        participantIds: const ['alice', 'bob', 'gone'],
        participantNames: const {'alice': 'Alice', 'bob': 'Bob', 'gone': 'Zaid'},
        modules: const EventModules(),
        createdAt: DateTime(2026, 5, 16),
      );
      // A single plain global/equal expense paid by the departed member → the
      // ONLY review reason is payerNotInParticipants, so the sheet's very
      // presence is the discriminator.
      final departedPayerExpense = [
        Expense(
          id: 'e-gone',
          tripId: eventId,
          payerParticipantId: 'gone',
          amount: Decimal.parse('20.000'),
          description: 'Taxi',
          scope: ExpenseScope.global,
          createdAt: DateTime(2026, 5, 16),
          createdBy: 'gone',
        ),
      ];
      // Live roster: alice + bob only. "gone" is absent (hard-deleted on leave).
      final liveMembers = [
        GroupMember(
          id: 'm-alice',
          groupId: groupId,
          userId: 'alice',
          displayName: 'Alice',
          role: 'CREATOR',
          joinedAt: DateTime(2026, 5, 16),
        ),
        GroupMember(
          id: 'm-bob',
          groupId: groupId,
          userId: 'bob',
          displayName: 'Bob',
          role: 'MEMBER',
          joinedAt: DateTime(2026, 5, 16),
        ),
      ];

      await tester.pumpWidget(
        buildScreen(
          fakeDb,
          eventStream: Stream.value(eventWithDeparted),
          expensesStream: Stream.value(departedPayerExpense),
          groupMembers: liveMembers,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(PreSettleReviewKeys.sheet), findsOneWidget);
      expect(find.text('Payer left'), findsOneWidget);
      expect(find.text('1 paid by someone who left'), findsOneWidget);
    },
  );

  testWidgets(
    '#204: an event-removed payer surfaces "Payer left" even if still live in the group',
    (tester) async {
      final fakeDb = FakeFirebaseFirestore();

      // "gone" is still a live group member, but an event admin removed them
      // from this event after they paid. A live-member-only active set misses
      // this; the event participant set must participate in the detector input.
      final eventAfterRemoval = Event(
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
      final removedPayerExpense = [
        Expense(
          id: 'e-removed',
          tripId: eventId,
          payerParticipantId: 'gone',
          amount: Decimal.parse('20.000'),
          description: 'Taxi',
          scope: ExpenseScope.global,
          createdAt: DateTime(2026, 5, 16),
          createdBy: 'gone',
        ),
      ];
      final liveMembers = [
        GroupMember(
          id: 'm-alice',
          groupId: groupId,
          userId: 'alice',
          displayName: 'Alice',
          role: 'CREATOR',
          joinedAt: DateTime(2026, 5, 16),
        ),
        GroupMember(
          id: 'm-bob',
          groupId: groupId,
          userId: 'bob',
          displayName: 'Bob',
          role: 'MEMBER',
          joinedAt: DateTime(2026, 5, 16),
        ),
        GroupMember(
          id: 'm-gone',
          groupId: groupId,
          userId: 'gone',
          displayName: 'Zaid',
          role: 'MEMBER',
          joinedAt: DateTime(2026, 5, 16),
        ),
      ];

      await tester.pumpWidget(
        buildScreen(
          fakeDb,
          eventStream: Stream.value(eventAfterRemoval),
          expensesStream: Stream.value(removedPayerExpense),
          groupMembers: liveMembers,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(PreSettleReviewKeys.sheet), findsOneWidget);
      expect(find.text('Payer left'), findsOneWidget);
      expect(find.text('1 paid by someone who left'), findsOneWidget);
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

  testWidgets(
    'settlements hard error → loud error view; Retry heals once the stream '
    'recovers (#1028)',
    (tester) async {
      final fakeDb = FakeFirebaseFirestore();
      final settlements = StreamController<List<Settlement>>.broadcast();
      addTearDown(settlements.close);

      await tester.pumpWidget(
        buildScreen(fakeDb, settlementsStream: settlements.stream),
      );
      await tester.pump();
      settlements.addError(StateError('settlements failed'));
      await tester.pumpAndSettle();

      expect(find.text("Couldn't load balances."), findsOneWidget);

      // Retry must invalidate the SETTLEMENTS stream too — the broadcast
      // controller accepts the re-subscription and serves data this time.
      await tester.tap(find.text('Retry'));
      await tester.pump();
      settlements.add(const <Settlement>[]);
      await tester.pumpAndSettle();

      expect(find.text("Couldn't load balances."), findsNothing);
    },
  );

  testWidgets(
    'settlements loading with valued expenses → skeleton, not a zero-fold '
    'basis (#1028)',
    (tester) async {
      final fakeDb = FakeFirebaseFirestore();
      final controller = StreamController<List<Settlement>>();
      addTearDown(controller.close);

      await tester.pumpWidget(
        buildScreen(fakeDb, settlementsStream: controller.stream),
      );
      // Pump past event/group/expenses stream resolution (bounded — the
      // settlements skeleton is a Skeletonizer and never settles).
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      // The whole body must be the skeleton — a rendered SettleUpPageBody
      // here means the basis was computed against a zero-folded settlements
      // stream (the #1028 bug).
      expect(find.byType(SkeletonLoader), findsOneWidget);
      expect(find.byType(SettleUpPageBody), findsNothing);
      expect(find.text("Couldn't load balances."), findsNothing);
    },
  );

  testWidgets(
    '#1030: members loading with valued money streams → skeleton, not a '
    'members-less #249 universe',
    (tester) async {
      final fakeDb = FakeFirebaseFirestore();
      final members = StreamController<List<GroupMember>>();
      addTearDown(members.close);

      await tester.pumpWidget(
        buildScreen(fakeDb, groupMembersStream: members.stream),
      );
      // Pump past event/group/expenses/settlements resolution — members stays
      // pending, so the first-value window must be the skeleton, never a
      // zero-folded #249 universe (WRONG money on this OUTBOUND basis).
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(find.byType(SkeletonLoader), findsOneWidget);
      expect(find.byType(SettleUpPageBody), findsNothing);
      expect(find.text("Couldn't load balances."), findsNothing);
    },
  );

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
    '#831: recording an event settlement writes ONE event_settlement activity '
    'row with the direction+event metadata contract',
    (tester) async {
      final fakeDb = FakeFirebaseFirestore();

      await tester.pumpWidget(buildScreen(fakeDb));
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(GroupKeys.settleUpRecordPaymentButton),
      );
      await tester.tap(find.byKey(GroupKeys.settleUpRecordPaymentButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(GroupKeys.markAsPaidButton));
      await tester.pumpAndSettle();

      final activity = await fakeDb
          .collection('groups')
          .doc(groupId)
          .collection('activity')
          .get();

      // The Dinner (20.000 OMR, alice paid, global split) leaves bob owing
      // alice 10.000 — the record sheet's suggested transfer.
      expect(activity.docs, hasLength(1));
      final data = activity.docs.first.data();
      expect(data['type'], 'event_settlement');
      expect(data['actorId'], 'bob');
      expect(data['metadata'], {
        'amountFils': 10000, // OMR scale 1000 → 10.000
        'currency': 'OMR',
        'fromUserId': 'bob',
        'toUserId': 'alice',
        'fromName': 'Bob',
        'toName': 'Alice',
        'eventId': eventId,
        'eventName': 'Beach Trip',
      });
    },
  );

  testWidgets(
    '#831/#283/#889: correcting a recorded payment invokes the '
    'correctSettlement(scope: event) callable with the original id + '
    'sentinel note, and NO event_settlement activity row is written',
    (tester) async {
      final fakeDb = FakeFirebaseFirestore();
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
          eventScopeWrites: 1,
          groupScopeWrites: 0,
          repaired: false,
          noop: false,
          shouldBumpLedgerRevision: true,
        ),
      );

      final recorded = Settlement(
        id: 'settlement-1',
        tripId: eventId,
        payerParticipantId: 'bob',
        recipientParticipantId: 'alice',
        payerName: 'Bob',
        recipientName: 'Alice',
        amount: Decimal.parse('10.000'),
        currency: 'OMR',
        createdBy: 'bob',
        settledAt: DateTime(2026, 5, 17),
      );

      final overrides = [
        firebaseFunctionsServiceProvider.overrideWithValue(functionsService),
      ];
      await tester.pumpWidget(
        buildScreen(
          fakeDb,
          currentUid: 'bob',
          settlementsStream: Stream.value([recorded]),
          extraOverrides: overrides,
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SettleUpScreen)),
      );

      await tester.ensureVisible(find.byKey(GroupKeys.settleUpCorrectButton));
      await tester.tap(find.byKey(GroupKeys.settleUpCorrectButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Record correction'));
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      verify(
        () => functionsService.correctSettlement(
          groupId: groupId,
          scope: 'event',
          eventId: eventId,
          settlementId: 'settlement-1',
          correctionNote: l10n.settleUpCorrectionNote,
        ),
      ).called(1);

      // #104/#889: shouldBumpLedgerRevision: true → the home one-shot must see
      // the new event reverse.
      expect(container.read(ledgerRevisionProvider), 1);

      // The mocked callable writes NOTHING to the fake client DB — the
      // reverse is a server (Admin SDK) write, invisible to the client here.
      final settlements = await fakeDb
          .collection('groups')
          .doc(groupId)
          .collection('events')
          .doc(eventId)
          .collection('settlements')
          .get();
      expect(settlements.docs, isEmpty);

      // …and the feed must not show a reversal as a fresh payment (#283) —
      // the callable path writes no client activity row either.
      final activity = await fakeDb
          .collection('groups')
          .doc(groupId)
          .collection('activity')
          .get();
      expect(activity.docs, isEmpty);
    },
  );

  testWidgets(
    '#889: a legacy no-op result (shouldBumpLedgerRevision: false) does NOT '
    'bump ledgerRevisionProvider',
    (tester) async {
      final fakeDb = FakeFirebaseFirestore();
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
          groupScopeWrites: 0,
          repaired: false,
          noop: true,
          shouldBumpLedgerRevision: false,
        ),
      );

      final recorded = Settlement(
        id: 'settlement-1',
        tripId: eventId,
        payerParticipantId: 'bob',
        recipientParticipantId: 'alice',
        payerName: 'Bob',
        recipientName: 'Alice',
        amount: Decimal.parse('10.000'),
        currency: 'OMR',
        createdBy: 'bob',
        settledAt: DateTime(2026, 5, 17),
      );

      await tester.pumpWidget(
        buildScreen(
          fakeDb,
          currentUid: 'bob',
          settlementsStream: Stream.value([recorded]),
          extraOverrides: [
            firebaseFunctionsServiceProvider.overrideWithValue(
              functionsService,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SettleUpScreen)),
      );

      await tester.ensureVisible(find.byKey(GroupKeys.settleUpCorrectButton));
      await tester.tap(find.byKey(GroupKeys.settleUpCorrectButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Record correction'));
      await tester.pumpAndSettle();

      expect(container.read(ledgerRevisionProvider), 0);
    },
  );

  testWidgets(
    '#889: an offline/failed correction shows the write-error copy and '
    'writes nothing — never the queued/will-sync success copy',
    (tester) async {
      final fakeDb = FakeFirebaseFirestore();
      final functionsService = _MockFunctionsService();
      when(
        () => functionsService.correctSettlement(
          groupId: any(named: 'groupId'),
          scope: any(named: 'scope'),
          eventId: any(named: 'eventId'),
          settlementId: any(named: 'settlementId'),
          correctionNote: any(named: 'correctionNote'),
        ),
      ).thenThrow(Exception('offline'));

      final recorded = Settlement(
        id: 'settlement-1',
        tripId: eventId,
        payerParticipantId: 'bob',
        recipientParticipantId: 'alice',
        payerName: 'Bob',
        recipientName: 'Alice',
        amount: Decimal.parse('10.000'),
        currency: 'OMR',
        createdBy: 'bob',
        settledAt: DateTime(2026, 5, 17),
      );

      await tester.pumpWidget(
        buildScreen(
          fakeDb,
          currentUid: 'bob',
          settlementsStream: Stream.value([recorded]),
          extraOverrides: [
            firebaseFunctionsServiceProvider.overrideWithValue(
              functionsService,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SettleUpScreen)),
      );

      await tester.ensureVisible(find.byKey(GroupKeys.settleUpCorrectButton));
      await tester.tap(find.byKey(GroupKeys.settleUpCorrectButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Record correction'));
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l10n.settleUpRecordFailedGeneric), findsOneWidget);
      expect(find.text(l10n.settleUpRecordedWillSync), findsNothing);
      expect(find.text(l10n.settleUpRecorded), findsNothing);
      expect(container.read(ledgerRevisionProvider), 0);

      final settlements = await fakeDb
          .collection('groups')
          .doc(groupId)
          .collection('events')
          .doc(eventId)
          .collection('settlements')
          .get();
      expect(settlements.docs, isEmpty);
    },
  );

  testWidgets(
    '#595: an event PARTICIPANT who is neither payer nor recipient can record '
    'the transfer; direction follows the transfer, createdBy follows the writer',
    (tester) async {
      final fakeDb = FakeFirebaseFirestore();

      // Carol is an event participant (write-eligible) but has zero balance —
      // the Dinner is split only between Alice & Bob — so the sole transfer is
      // bob→alice and Carol is a pure third party to it (an organizer settling
      // on the group's behalf).
      final eventWithCarol = Event(
        id: eventId,
        groupId: groupId,
        name: 'Beach Trip',
        type: EventType.trip,
        createdBy: 'alice',
        participantIds: const ['alice', 'bob', 'carol'],
        participantNames: const {
          'alice': 'Alice',
          'bob': 'Bob',
          'carol': 'Carol',
        },
        modules: const EventModules(),
        createdAt: DateTime(2026, 5, 16),
      );
      final aliceBobExpense = [
        Expense(
          id: 'expense-1',
          tripId: eventId,
          payerParticipantId: 'alice',
          amount: Decimal.parse('20.000'),
          description: 'Dinner',
          scope: ExpenseScope.custom,
          customSplitParticipants: const ['alice', 'bob'],
          createdAt: DateTime(2026, 5, 16),
          createdBy: 'alice',
        ),
      ];

      await tester.pumpWidget(
        buildScreen(
          fakeDb,
          currentUid: 'carol',
          eventStream: Stream.value(eventWithCarol),
          expensesStream: Stream.value(aliceBobExpense),
        ),
      );
      await tester.pumpAndSettle();

      // The custom-participant split is "review-worthy" (#204) → the
      // non-blocking pre-settlement review sheet pops on entry. Dismiss it (as a
      // real user would) so its modal barrier doesn't intercept the tile tap.
      await tester.tap(find.byKey(PreSettleReviewKeys.continueButton));
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(GroupKeys.settleUpRecordPaymentButton),
      );
      await tester.tap(find.byKey(GroupKeys.settleUpRecordPaymentButton));
      await tester.pumpAndSettle();
      // Neutral third-party framing, not "you paid".
      expect(find.text('Record this payment?'), findsOneWidget);
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
      // Direction follows the optimal transfer, NOT who tapped.
      expect(snap.docs.first.data()['payerParticipantId'], equals('bob'));
      expect(snap.docs.first.data()['recipientParticipantId'], equals('alice'));
      // createdBy is the writer (Carol) — identity is orthogonal to direction.
      expect(snap.docs.first.data()['createdBy'], equals('carol'));
      // #367: settle-on-behalf (currentUid is NEITHER party) never nudges —
      // the gate is currentUid == fromUserId, not merely != toUserId. This is
      // the third-party case that distinguishes the two formulations.
      expect(find.byKey(GroupKeys.settleNotifySheet), findsNothing);
    },
  );

  testWidgets(
    '#595: a group member who is NOT an event participant sees NO Record button '
    '(the event create rule would permission-deny their write)',
    (tester) async {
      final fakeDb = FakeFirebaseFirestore();

      // Carol can READ this event (group-member read) but is not in
      // event.participantIds (alice/bob), so isEventParticipant would reject her
      // settlement write. The affordance must be suppressed for her.
      await tester.pumpWidget(buildScreen(fakeDb, currentUid: 'carol'));
      await tester.pumpAndSettle();

      // The transfer tile still renders…
      expect(find.byType(GroupSettlementTile), findsOneWidget);
      // …but with no Record button for a non-participant viewer.
      expect(
        find.byKey(GroupKeys.settleUpRecordPaymentButton),
        findsNothing,
      );
    },
  );

  testWidgets(
    '#598: a non-participant viewer sees NO "correct this payment" button on a '
    'recorded-payment row (the offsetting write would also permission-deny), '
    'while the row itself still renders',
    (tester) async {
      final fakeDb = FakeFirebaseFirestore();

      // A payment is already on record (bob → alice). Carol can READ this event
      // (group-member read) but isn't in event.participantIds, so an offsetting
      // correction (#283) would be permission-denied — exactly like a forward
      // Record. The correction affordance must be suppressed for her too;
      // #595 only gated the forward path, leaving this asymmetry.
      final recorded = Settlement(
        id: 'settlement-1',
        tripId: eventId,
        payerParticipantId: 'bob',
        recipientParticipantId: 'alice',
        payerName: 'Bob',
        recipientName: 'Alice',
        amount: Decimal.parse('10.000'),
        currency: 'OMR',
        createdBy: 'bob',
        settledAt: DateTime(2026, 5, 17),
      );

      await tester.pumpWidget(
        buildScreen(
          fakeDb,
          currentUid: 'carol',
          settlementsStream: Stream.value([recorded]),
        ),
      );
      await tester.pumpAndSettle();

      // The history row renders — its always-on share button proves it…
      expect(find.byKey(GroupKeys.settleUpShareReceiptButton), findsOneWidget);
      // …but the correction affordance is gone for a non-participant.
      expect(find.byKey(GroupKeys.settleUpCorrectButton), findsNothing);
    },
  );

  testWidgets(
    '#598: an event participant still sees the "correct this payment" button '
    '(the gate is selective, not a blanket removal)',
    (tester) async {
      final fakeDb = FakeFirebaseFirestore();

      final recorded = Settlement(
        id: 'settlement-1',
        tripId: eventId,
        payerParticipantId: 'bob',
        recipientParticipantId: 'alice',
        payerName: 'Bob',
        recipientName: 'Alice',
        amount: Decimal.parse('10.000'),
        currency: 'OMR',
        createdBy: 'bob',
        settledAt: DateTime(2026, 5, 17),
      );

      // Bob is in event.participantIds → write-eligible → the correction
      // affordance stays wired for him.
      await tester.pumpWidget(
        buildScreen(
          fakeDb,
          currentUid: 'bob',
          settlementsStream: Stream.value([recorded]),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(GroupKeys.settleUpCorrectButton), findsOneWidget);
    },
  );

  // Actor policy: the Correct affordance is per-settlement — visible only to
  // a party (payer/recipient) of that settlement or the group creator, on top
  // of the #598 participant gate. The correctSettlement callable enforces the
  // same policy server-side; hiding here kills the accidental case.
  group('actor policy (creator-or-party)', () {
    final threeWay = Event(
      id: eventId,
      groupId: groupId,
      name: 'Beach Trip',
      type: EventType.trip,
      createdBy: 'alice',
      participantIds: const ['alice', 'bob', 'dana'],
      participantNames: const {
        'alice': 'Alice',
        'bob': 'Bob',
        'dana': 'Dana',
      },
      modules: const EventModules(),
      createdAt: DateTime(2026, 5, 16),
    );

    Settlement recorded({String payer = 'bob', String recipient = 'alice'}) =>
        Settlement(
          id: 'settlement-1',
          tripId: eventId,
          payerParticipantId: payer,
          recipientParticipantId: recipient,
          payerName: payer,
          recipientName: recipient,
          amount: Decimal.parse('10.000'),
          currency: 'OMR',
          createdBy: 'bob',
          settledAt: DateTime(2026, 5, 17),
        );

    testWidgets(
      'a participant who is neither party nor group creator sees NO correct '
      'button',
      (tester) async {
        final fakeDb = FakeFirebaseFirestore();

        // Dana is an event participant (the #598 write-eligibility gate
        // passes for her) but is not a party to bob→alice and not the group
        // creator (bob in this fixture) — the affordance must be hidden.
        await tester.pumpWidget(
          buildScreen(
            fakeDb,
            currentUid: 'dana',
            eventStream: Stream.value(threeWay),
            settlementsStream: Stream.value([recorded()]),
          ),
        );
        await tester.pumpAndSettle();

        // The history row renders…
        expect(
          find.byKey(GroupKeys.settleUpShareReceiptButton),
          findsOneWidget,
        );
        // …but Dana gets no correct affordance.
        expect(find.byKey(GroupKeys.settleUpCorrectButton), findsNothing);
      },
    );

    testWidgets(
      'a party who is NOT the group creator still sees the correct button',
      (tester) async {
        final fakeDb = FakeFirebaseFirestore();

        // Alice is the recipient of bob→alice; the group creator is bob.
        await tester.pumpWidget(
          buildScreen(
            fakeDb,
            currentUid: 'alice',
            settlementsStream: Stream.value([recorded()]),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(GroupKeys.settleUpCorrectButton), findsOneWidget);
      },
    );

    testWidgets(
      'the group creator sees the correct button on a settlement they are '
      'not a party to',
      (tester) async {
        final fakeDb = FakeFirebaseFirestore();

        // Bob is the group creator AND an event participant (the kept #598
        // gate requires participation), but not a party to alice→dana.
        await tester.pumpWidget(
          buildScreen(
            fakeDb,
            currentUid: 'bob',
            eventStream: Stream.value(threeWay),
            settlementsStream: Stream.value(
              [recorded(payer: 'alice', recipient: 'dana')],
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(GroupKeys.settleUpCorrectButton), findsOneWidget);
      },
    );
  });

  // #889: the solo Correct button gate moves to marker/bounded-legacy —
  // display (the accent/tag on :983-984) stays note-based and is untouched.
  group('#889 solo Correct-button write-affordance hide', () {
    testWidgets('a MARKED settlement hides the Correct button', (
      tester,
    ) async {
      final fakeDb = FakeFirebaseFirestore();
      final marked = Settlement(
        id: 'settlement-1',
        tripId: eventId,
        payerParticipantId: 'alice',
        recipientParticipantId: 'bob',
        payerName: 'Alice',
        recipientName: 'Bob',
        amount: Decimal.parse('10.000'),
        currency: 'OMR',
        createdBy: 'bob',
        settledAt: DateTime(2026, 5, 17),
        note: 'Correction of a recorded payment',
        correctionOfSettlementId: 'orig-1',
      );

      await tester.pumpWidget(
        buildScreen(
          fakeDb,
          currentUid: 'bob',
          settlementsStream: Stream.value([marked]),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(GroupKeys.settleUpCorrectButton), findsNothing);
    });

    testWidgets(
      'a bounded-legacy (pre-#889 note-only, exact inverse) correction '
      'hides the Correct button on its SOURCE row',
      (tester) async {
        final fakeDb = FakeFirebaseFirestore();
        // Source is index 0 (the newest tile) so it carries the keyed button.
        final source = Settlement(
          id: 'settlement-1',
          tripId: eventId,
          payerParticipantId: 'bob',
          recipientParticipantId: 'alice',
          payerName: 'Bob',
          recipientName: 'Alice',
          amount: Decimal.parse('10.000'),
          currency: 'OMR',
          createdBy: 'bob',
          settledAt: DateTime(2026, 5, 18),
        );
        final legacyReverse = Settlement(
          id: 'settlement-1-rev',
          tripId: eventId,
          payerParticipantId: 'alice',
          recipientParticipantId: 'bob',
          payerName: 'Alice',
          recipientName: 'Bob',
          amount: Decimal.parse('10.000'),
          currency: 'OMR',
          createdBy: 'alice',
          settledAt: DateTime(2026, 5, 17),
          note: 'Correction of a recorded payment',
        );

        await tester.pumpWidget(
          buildScreen(
            fakeDb,
            currentUid: 'bob',
            settlementsStream: Stream.value([source, legacyReverse]),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(GroupKeys.settleUpCorrectButton), findsNothing);
      },
    );

    testWidgets(
      'a sentinel-note settlement with NO exact inverse source stays '
      'correctable (coincidental sentinel text is not proof of a correction)',
      (tester) async {
        final fakeDb = FakeFirebaseFirestore();
        final coincidental = Settlement(
          id: 'settlement-1',
          tripId: eventId,
          payerParticipantId: 'bob',
          recipientParticipantId: 'alice',
          payerName: 'Bob',
          recipientName: 'Alice',
          amount: Decimal.parse('10.000'),
          currency: 'OMR',
          createdBy: 'bob',
          settledAt: DateTime(2026, 5, 17),
          note: 'Correction of a recorded payment',
        );

        await tester.pumpWidget(
          buildScreen(
            fakeDb,
            currentUid: 'bob',
            settlementsStream: Stream.value([coincidental]),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(GroupKeys.settleUpCorrectButton), findsOneWidget);
      },
    );
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
          id: any(named: 'id'),
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

  testWidgets('#530: ambiguous European amount is rejected, not silently '
      'coerced to the suggested amount', (tester) async {
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
    // Pasted European grouping (dot thousands + comma decimal). The old code
    // truncated this to 1.23; the regression here is the SILENT fallback to the
    // suggested amount once the normalizer refuses to guess.
    await tester.enterText(find.byType(TextFormField), '1.234,56');
    await tester.ensureVisible(find.byKey(GroupKeys.markAsPaidButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(GroupKeys.markAsPaidButton));
    await tester.pumpAndSettle();

    expect(find.text('Please enter a valid amount'), findsOneWidget);

    final snap = await fakeDb
        .collection('groups')
        .doc(groupId)
        .collection('events')
        .doc(eventId)
        .collection('settlements')
        .get();
    expect(
      snap.docs,
      isEmpty,
      reason: 'a rejected amount must not write a settlement',
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
    // #367 honesty guard: a FAILED write must not offer to tell the creditor
    // "I've sent you …" — the gate is outcome.kind == recorded.
    expect(find.byKey(GroupKeys.settleNotifySheet), findsNothing);
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
    // #367 honesty guard: a permission-denied write must not nudge.
    expect(find.byKey(GroupKeys.settleNotifySheet), findsNothing);
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

  // #367: after the DEBTOR records a payment they made on the single-tile path,
  // a post-record nudge offers to notify the creditor over WhatsApp. Gated to
  // the paying perspective + single-tile path — creditor-records (#282),
  // settle-on-behalf (#595), and the stepped walk never nudge.
  group('#367 WhatsApp settle notify', () {
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

    testWidgets(
      'debtor single-tile record offers the nudge with the EVENT-scoped, '
      'past-tense message (for {event} in {group})',
      (tester) async {
        final fakeDb = FakeFirebaseFirestore();

        // Default currentUid = bob, who owes alice 10.000 → bob is the debtor.
        await tester.pumpWidget(buildScreen(fakeDb));
        await tester.pumpAndSettle();

        await tester.ensureVisible(
          find.byKey(GroupKeys.settleUpRecordPaymentButton),
        );
        await tester.tap(find.byKey(GroupKeys.settleUpRecordPaymentButton));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(GroupKeys.markAsPaidButton));
        await tester.pumpAndSettle();

        expect(find.byKey(GroupKeys.settleNotifySheet), findsOneWidget);
        // Past tense, recipient = the creditor (Alice), event AND group named.
        expect(
          find.textContaining("Hey Alice, I've sent you OMR 10.000 for "
              'Beach Trip in Trip.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'tapping WhatsApp launches a numberless whatsapp://send carrying the '
      'message; never falls back when WhatsApp is installed',
      (tester) async {
        registerFallbackValue(const LaunchOptions());
        final launcher = _MockUrlLauncher();
        UrlLauncherPlatform.instance = launcher;
        when(() => launcher.canLaunch(any())).thenAnswer((_) async => true);
        when(
          () => launcher.launchUrl(any(), any()),
        ).thenAnswer((_) async => true);

        final fakeDb = FakeFirebaseFirestore();
        await tester.pumpWidget(buildScreen(fakeDb));
        await tester.pumpAndSettle();

        await tester.ensureVisible(
          find.byKey(GroupKeys.settleUpRecordPaymentButton),
        );
        await tester.tap(find.byKey(GroupKeys.settleUpRecordPaymentButton));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(GroupKeys.markAsPaidButton));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(GroupKeys.settleNotifyWhatsAppButton));
        await tester.pumpAndSettle();

        final launched = verify(
          () => launcher.launchUrl(captureAny(), any()),
        ).captured.single as String;
        expect(launched, startsWith('whatsapp://send?text='));
        expect(Uri.decodeQueryComponent(launched), contains('Beach Trip'));
      },
    );

    testWidgets('Not now dismisses the nudge without launching WhatsApp', (
      tester,
    ) async {
      registerFallbackValue(const LaunchOptions());
      final launcher = _MockUrlLauncher();
      UrlLauncherPlatform.instance = launcher;
      when(() => launcher.canLaunch(any())).thenAnswer((_) async => true);
      when(
        () => launcher.launchUrl(any(), any()),
      ).thenAnswer((_) async => true);

      final fakeDb = FakeFirebaseFirestore();
      await tester.pumpWidget(buildScreen(fakeDb));
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(GroupKeys.settleUpRecordPaymentButton),
      );
      await tester.tap(find.byKey(GroupKeys.settleUpRecordPaymentButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(GroupKeys.markAsPaidButton));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(GroupKeys.settleNotifyNotNowButton));
      await tester.pumpAndSettle();

      expect(find.byKey(GroupKeys.settleNotifySheet), findsNothing);
      verifyNever(() => launcher.launchUrl(any(), any()));
    });

    testWidgets('#282: the CREDITOR recording a received payment sees NO nudge', (
      tester,
    ) async {
      final fakeDb = FakeFirebaseFirestore();

      // Alice is the creditor (bob owes her). She records the receipt — the
      // debtor-only nudge must not appear for her.
      await tester.pumpWidget(buildScreen(fakeDb, currentUid: 'alice'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(GroupKeys.settleUpRecordPaymentButton),
      );
      await tester.tap(find.byKey(GroupKeys.settleUpRecordPaymentButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(GroupKeys.markAsPaidButton));
      await tester.pumpAndSettle();

      expect(find.byKey(GroupKeys.settleNotifySheet), findsNothing);
    });

    testWidgets(
      'a stepped multi-currency walk does NOT nudge (single-tile only)',
      (tester) async {
        final fakeDb = FakeFirebaseFirestore();

        // Bob (debtor) owes alice across OMR + USD → one stepped card.
        await tester.pumpWidget(
          buildScreen(fakeDb, expensesStream: Stream.value(twoBucketExpenses)),
        );
        await tester.pumpAndSettle();

        final card = find.byKey(const ValueKey('settle-stepped-alice'));
        await tester.ensureVisible(card);
        await tester.tap(card);
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(GroupKeys.markAsPaidButton));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(GroupKeys.markAsPaidButton));
        await tester.pumpAndSettle();

        // Aggregate summary snackbar, never the per-step WhatsApp nudge.
        expect(find.byKey(GroupKeys.settleNotifySheet), findsNothing);
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
    required String id,
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
    required String id,
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
  }) {
    throw StateError('write failed');
  }
}

class _DeniedSettlementService extends SettlementService {
  _DeniedSettlementService() : super.withFirestore(FakeFirebaseFirestore());

  @override
  Future<Settlement> addSettlement({
    required String id,
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
  }) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
      message: 'Missing or insufficient permissions.',
    );
  }
}
