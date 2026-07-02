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
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/ledger/screens/ledger_screen.dart';
import 'package:safar/features/ledger/widgets/ledger_category_strip.dart';
import 'package:safar/features/ledger/widgets/ledger_hero_block.dart';
import 'package:safar/features/ledger/widgets/ledger_roster_strip.dart';
import 'package:safar/features/ledger/widgets/ledger_sticky_cta.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:safar/shared/widgets/cover_art.dart';
import 'package:safar/shared/widgets/offline_banner.dart';

import '../../helpers/repaint_boundary_finder.dart';

/// #382 PR-5 — the ledger renders EVERY currency bucket and the settled gate
/// spans all of them. The money-wrong bug: a user settled in the group bucket
/// but owing in another currency saw "All square." and a dead settle-up CTA.
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

  Widget buildLedger({required List<Expense> expenses}) {
    final groupMembers = [
      for (final uid in event.participantIds)
        GroupMember(
          id: uid,
          groupId: groupId,
          userId: uid,
          displayName: event.participantNames[uid] ?? uid,
          role: uid == event.createdBy ? 'CREATOR' : 'MEMBER',
          joinedAt: event.createdAt,
        ),
    ];
    final router = GoRouter(
      initialLocation: '/group/$groupId/event/$eventId/ledger',
      routes: [
        GoRoute(
          path: '/group/:gid',
          builder: (context, state) => const Scaffold(body: Text('Group')),
          routes: [
            GoRoute(
              path: 'event/:eid',
              builder: (context, state) => const Scaffold(body: Text('Event')),
              routes: [
                GoRoute(
                  path: 'ledger',
                  builder: (context, state) => LedgerScreen(
                    groupId: state.pathParameters['gid']!,
                    eventId: state.pathParameters['eid']!,
                  ),
                  routes: [
                    GoRoute(
                      path: 'settle-up',
                      builder: (context, state) =>
                          const Scaffold(body: Text('Settle up route')),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );

    return ProviderScope(
      overrides: [
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
        currentUserIdProvider.overrideWithValue('uid-a'),
        eventDetailProvider(
          eventRef,
        ).overrideWith((ref) => Stream.value(event)),
        eventExpensesProvider(
          eventRef,
        ).overrideWith((ref) => Stream.value(expenses)),
        eventSettlementsProvider(
          eventRef,
        ).overrideWith((ref) => Stream.value(const <Settlement>[])),
        groupMembersProvider(
          groupId,
        ).overrideWith((ref) => Stream.value(groupMembers)),
      ],
      child: MaterialApp.router(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    );
  }

  group('#758 embedded mode (tab panel inside the tabbed event view)', () {
    Widget buildEmbedded({required List<Expense> expenses}) {
      final groupMembers = [
        for (final uid in event.participantIds)
          GroupMember(
            id: uid,
            groupId: groupId,
            userId: uid,
            displayName: event.participantNames[uid] ?? uid,
            role: uid == event.createdBy ? 'CREATOR' : 'MEMBER',
            joinedAt: event.createdAt,
          ),
      ];
      return ProviderScope(
        overrides: [
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
          currentUserIdProvider.overrideWithValue('uid-a'),
          eventDetailProvider(
            eventRef,
          ).overrideWith((ref) => Stream.value(event)),
          eventExpensesProvider(
            eventRef,
          ).overrideWith((ref) => Stream.value(expenses)),
          eventSettlementsProvider(
            eventRef,
          ).overrideWith((ref) => Stream.value(const <Settlement>[])),
          groupMembersProvider(
            groupId,
          ).overrideWith((ref) => Stream.value(groupMembers)),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: LedgerScreen(
              groupId: groupId,
              eventId: eventId,
              embedded: true,
            ),
          ),
        ),
      );
    }

    testWidgets('renders the timeline without cover/hero/roster/CTA chrome', (
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
      // …but the shell-owned chrome does not: no cover header, no hero
      // statement (balance lives in the tabbed header), no roster strip, no
      // sticky CTA (FAB + Settle tab replace it), no offline banner, no
      // nested Scaffold.
      expect(find.byType(CoverArt), findsNothing);
      expect(find.byType(LedgerHeroStatement), findsNothing);
      expect(find.byType(LedgerRosterStrip), findsNothing);
      expect(find.byType(LedgerStickyCta), findsNothing);
      expect(find.byType(OfflineBanner), findsNothing);
      expect(
        find.descendant(
          of: find.byType(LedgerScreen),
          matching: find.byType(Scaffold),
        ),
        findsNothing,
      );
    });
  });

  group('all-bucket settled gate (#382 PR-5)', () {
    testWidgets(
      'zero group bucket + non-zero USD bucket: hero is NOT settled and '
      'settle-up CTA stays enabled',
      (tester) async {
        // OMR nets cancel (each paid 10, split equally); Alice owes 15 USD.
        await tester.pumpWidget(
          buildLedger(
            expenses: [
              expense(id: 'e-omr-a', payer: 'uid-a', amount: '10.000'),
              expense(id: 'e-omr-b', payer: 'uid-b', amount: '10.000'),
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

        expect(
          find.textContaining('All square', findRichText: true),
          findsNothing,
        );
        expect(
          find.textContaining('You owe', findRichText: true),
          findsOneWidget,
        );
        expect(find.text('−USD'), findsOneWidget);

        await tester.tap(find.text('Settle up'));
        await tester.pumpAndSettle();
        expect(find.text('Settle up route'), findsOneWidget);
      },
    );

    testWidgets('settled in every bucket renders the settled hero', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildLedger(
          expenses: [
            expense(id: 'e-omr-a', payer: 'uid-a', amount: '10.000'),
            expense(id: 'e-omr-b', payer: 'uid-b', amount: '10.000'),
            expense(
              id: 'e-usd-a',
              payer: 'uid-a',
              amount: '10.00',
              currency: 'USD',
            ),
            expense(
              id: 'e-usd-b',
              payer: 'uid-b',
              amount: '10.00',
              currency: 'USD',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('All square', findRichText: true),
        findsOneWidget,
      );
    });
  });

  group('per-currency hero + roster lines (#382 PR-5)', () {
    testWidgets('hero renders one statement line per non-zero bucket', (
      tester,
    ) async {
      // Alice owes Bob 5 OMR and 15 USD.
      await tester.pumpWidget(
        buildLedger(
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

      expect(
        find.textContaining('You owe', findRichText: true),
        findsNWidgets(2),
      );
      expect(find.text('−OMR'), findsOneWidget);
      expect(find.text('−USD'), findsOneWidget);
    });

    testWidgets('roster renders one chip per (person, non-zero bucket) with '
        'its own currency precision', (tester) async {
      await tester.pumpWidget(
        buildLedger(
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

      // Bob is owed in both buckets → two negative chips from Alice's
      // perspective, each formatted at its bucket's precision.
      expect(find.text('−5.000'), findsOneWidget);
      expect(find.text('−15.00'), findsOneWidget);
    });

    testWidgets('#626: event cover art is wrapped in a RepaintBoundary', (
      tester,
    ) async {
      await tester.pumpWidget(buildLedger(expenses: const []));
      await tester.pumpAndSettle();
      expectWrappedInRepaintBoundary(find.byType(CoverArt));
    });
  });
}
