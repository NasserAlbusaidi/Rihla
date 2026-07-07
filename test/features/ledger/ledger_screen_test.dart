import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/ledger/keys/ledger_keys.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/ledger/screens/ledger_screen.dart';
import 'package:safar/features/ledger/widgets/ledger_category_strip.dart';
import 'package:safar/features/ledger/widgets/ledger_roster_strip.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:safar/shared/widgets/cover_art.dart';
import 'package:safar/shared/widgets/offline_banner.dart';

/// The ledger timeline panel (#758; panel-only since #915 — the full-chrome
/// mode and its hero died with PR-5 §4's route consolidation; the settled
/// gate / per-currency balance behaviors are pinned at their surviving home,
/// the hub's balance block, in event_command_center_test.dart).
void main() {
  const groupId = 'g1';
  const eventId = 'e1';
  const eventRef = (groupId: groupId, eventId: eventId);

  final event = Event(
    id: eventId,
    groupId: groupId,
    name: 'Beach Trip',
    type: EventType.trip,
    createdBy: 'uid-a',
    participantIds: const ['uid-a', 'uid-b'],
    participantNames: const {'uid-a': 'Alice', 'uid-b': 'Bob'},
    modules: const EventModules(),
    createdAt: DateTime(2026, 1, 10),
  );

  Expense expense({
    required String id,
    required String payer,
    required String amount,
    String currency = 'OMR',
  }) {
    return Expense(
      id: id,
      tripId: eventId,
      payerParticipantId: payer,
      amount: Decimal.parse(amount),
      description: 'Item $id',
      scope: ExpenseScope.global,
      currency: currency,
      createdAt: DateTime(2026, 1, 10),
    );
  }

  List<Override> overridesFor({
    required Event effectiveEvent,
    required List<Expense> expenses,
    String? currentUserId = 'uid-a',
    Stream<List<GroupMember>>? membersStream,
  }) {
    final groupMembers = [
      for (final uid in effectiveEvent.participantIds)
        GroupMember(
          id: uid,
          groupId: groupId,
          userId: uid,
          displayName: effectiveEvent.participantNames[uid] ?? uid,
          role: uid == effectiveEvent.createdBy ? 'CREATOR' : 'MEMBER',
          joinedAt: effectiveEvent.createdAt,
        ),
    ];
    return [
      groupDetailProvider(groupId).overrideWith(
        (ref) => Stream.value(
          Group(
            id: groupId,
            name: 'Trip',
            inviteCode: 'ABC123',
            createdBy: 'uid-a',
            memberIds: const ['uid-a', 'uid-b'],
            currency: 'OMR',
            createdAt: DateTime(2026),
          ),
        ),
      ),
      currentUserIdProvider.overrideWithValue(currentUserId),
      eventDetailProvider(
        eventRef,
      ).overrideWith((ref) => Stream.value(effectiveEvent)),
      eventExpensesProvider(
        eventRef,
      ).overrideWith((ref) => Stream.value(expenses)),
      eventSettlementsProvider(
        eventRef,
      ).overrideWith((ref) => Stream.value(const <Settlement>[])),
      groupMembersProvider(
        groupId,
      ).overrideWith((ref) => membersStream ?? Stream.value(groupMembers)),
    ];
  }

  group('#758 panel (tab content inside the tabbed event view)', () {
    Widget buildEmbedded({required List<Expense> expenses}) {
      return ProviderScope(
        overrides: overridesFor(effectiveEvent: event, expenses: expenses),
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: LedgerScreen(groupId: groupId, eventId: eventId),
          ),
        ),
      );
    }

    testWidgets('renders the timeline without cover/hero/CTA chrome', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildEmbedded(
          expenses: [expense(id: 'e1', payer: 'uid-a', amount: '10.000')],
        ),
      );
      await tester.pump();

      // Timeline content + inline category chips render…
      expect(find.text('Item e1'), findsOneWidget);
      expect(find.byType(LedgerCategoryStrip), findsOneWidget);
      // …but the shell-owned chrome does not: no cover header, no offline
      // banner (the tabbed shell owns both), no nested Scaffold.
      expect(find.byType(CoverArt), findsNothing);
      expect(find.byType(OfflineBanner), findsNothing);
      expect(
        find.descendant(
          of: find.byType(LedgerScreen),
          matching: find.byType(Scaffold),
        ),
        findsNothing,
      );
    });

    testWidgets(
      'PR-5 §4: roster strip survives embedding — its per-person tap is the '
      'only in-app producer of ledger/settle-up?memberId= once the '
      'full-chrome ledger route stops routing',
      (tester) async {
        await tester.pumpWidget(
          buildEmbedded(
            expenses: [expense(id: 'e1', payer: 'uid-a', amount: '10.000')],
          ),
        );
        await tester.pump();

        expect(find.byType(LedgerRosterStrip), findsOneWidget);
      },
    );

    testWidgets('roster renders one chip per (person, non-zero bucket) with '
        'its own currency precision (#382 PR-5)', (tester) async {
      // Alice owes Bob 5 OMR and 15 USD.
      await tester.pumpWidget(
        buildEmbedded(
          expenses: [
            expense(id: 'e-omr', payer: 'uid-b', amount: '10.000'),
            expense(
              id: 'e-usd',
              payer: 'uid-b',
              amount: '30.00',
              currency: 'USD',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // #998: chips show Bob's OWN standing — the group owes him in both
      // buckets → two positive chips, each formatted at its bucket's precision.
      expect(find.text('+5.000'), findsOneWidget);
      expect(find.text('+15.00'), findsOneWidget);
    });
  });

  group('timeline interactions (folded from ledger_screen_overflow_test, '
      '#915)', () {
    Widget buildPanelRoute({
      Event? eventOverride,
      List<Expense> expenses = const <Expense>[],
      String? currentUserId = 'uid-a',
    }) {
      final effectiveEvent = eventOverride ?? event;
      final router = GoRouter(
        initialLocation: '/group/$groupId/event/$eventId/ledger',
        routes: [
          GoRoute(
            path: '/group/:gid/event/:eid/ledger',
            builder: (context, state) => Scaffold(
              body: LedgerScreen(
                groupId: state.pathParameters['gid']!,
                eventId: state.pathParameters['eid']!,
              ),
            ),
            routes: [
              GoRoute(
                path: 'edit/:expId',
                builder: (context, state) => Scaffold(
                  body: Text(
                    'Edit expense route:${state.pathParameters['expId']}',
                  ),
                ),
              ),
            ],
          ),
        ],
      );

      return ProviderScope(
        overrides: overridesFor(
          effectiveEvent: effectiveEvent,
          expenses: expenses,
          currentUserId: currentUserId,
        ),
        child: MaterialApp.router(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      );
    }

    testWidgets('expense row tap navigates to edit expense route', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildPanelRoute(
          expenses: [expense(id: 'expense-1', payer: 'uid-a', amount: '3.000')],
        ),
      );
      await tester.pumpAndSettle();

      final row = find.byKey(LedgerKeys.expenseCard('expense-1'));
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pumpAndSettle();

      expect(find.text('Edit expense route:expense-1'), findsOneWidget);
    });

    testWidgets('uses the signed-in member for the day-card perspective', (
      tester,
    ) async {
      final twoMemberEvent = event.copyWith(
        participantIds: const ['uid-payer', 'uid-debtor'],
        participantNames: const {'uid-payer': 'Mona', 'uid-debtor': 'Nasser'},
      );
      await tester.pumpWidget(
        buildPanelRoute(
          eventOverride: twoMemberEvent,
          expenses: [
            Expense(
              id: 'expense-1',
              tripId: eventId,
              payerParticipantId: 'uid-payer',
              amount: Decimal.parse('3.000'),
              description: 'Coffee',
              scope: ExpenseScope.global,
              createdAt: DateTime(2026, 1, 10),
            ),
          ],
          currentUserId: 'uid-debtor',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Mona paid · split 2 ways'), findsOneWidget);
    });
  });

  // #1030: ledgerViewProvider folds groupMembersProvider — a members hard
  // error re-shapes the #249 universe, so the balances tab and roster strip
  // would render wrong per-member nets as clean. The screen's data-error
  // gate must cover the members stream like the money streams.
  testWidgets(
    '#1030: members hard error → ledger data-error state, not a members-less '
    'roster',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: overridesFor(
            effectiveEvent: event,
            expenses: [expense(id: 'x1', payer: 'uid-a', amount: '10.000')],
            membersStream:
                Stream<List<GroupMember>>.error(StateError('members failed')),
          ),
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(
              body: LedgerScreen(groupId: groupId, eventId: eventId),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text("Couldn't load ledger"), findsOneWidget);
      expect(find.text('Item x1'), findsNothing);
      // Drain plain (non-frame) timers pumpAndSettle can't advance.
      await tester.pump(const Duration(seconds: 5));
    },
  );
}
