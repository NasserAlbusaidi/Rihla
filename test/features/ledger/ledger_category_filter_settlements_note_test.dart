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
import 'package:safar/l10n/generated/app_localizations.dart';

/// #807 — an active category filter structurally hides EVERY settlement row
/// (settlements carry no category). The ledger must say so with a caption
/// instead of silently vanishing them; the caption only appears when there
/// are settlements to hide.
void main() {
  const groupId = 'g1';
  const eventId = 'e1';
  const eventRef = (groupId: groupId, eventId: eventId);
  const noteText =
      "Settlements aren't categorized, so they're hidden while filtering.";

  final event = Event(
    id: eventId,
    groupId: groupId,
    name: 'Beach Trip',
    type: EventType.trip,
    createdBy: 'uid-sara',
    participantIds: const ['uid-sara', 'uid-omar'],
    participantNames: const {'uid-sara': 'Sara', 'uid-omar': 'Omar'},
    modules: const EventModules(),
    createdAt: DateTime(2026, 1, 10),
  );

  final foodExpense = Expense(
    id: 'x1',
    tripId: eventId,
    payerParticipantId: 'uid-sara',
    amount: Decimal.parse('30.000'),
    scope: ExpenseScope.global,
    createdAt: DateTime(2026, 1, 11),
    createdBy: 'uid-sara',
    currency: 'OMR',
    categoryId: 'food',
  );

  final settlement = Settlement(
    id: 's1',
    tripId: eventId,
    payerParticipantId: 'uid-omar',
    recipientParticipantId: 'uid-sara',
    amount: Decimal.parse('5.000'),
    currency: 'OMR',
    settledAt: DateTime(2026, 1, 12),
    createdBy: 'uid-omar',
  );

  Future<void> pumpLedger(
    WidgetTester tester, {
    required List<Settlement> settlements,
  }) async {
    final members = [
      GroupMember(
        id: 'uid-sara',
        groupId: groupId,
        userId: 'uid-sara',
        displayName: 'Sara',
        role: 'CREATOR',
        joinedAt: event.createdAt,
      ),
      GroupMember(
        id: 'uid-omar',
        groupId: groupId,
        userId: 'uid-omar',
        displayName: 'Omar',
        role: 'MEMBER',
        joinedAt: event.createdAt,
      ),
    ];

    final router = GoRouter(
      initialLocation: '/group/$groupId/event/$eventId/ledger',
      routes: [
        GoRoute(
          path: '/group/:gid/event/:eid/ledger',
          builder: (context, state) => LedgerScreen(
            groupId: state.pathParameters['gid']!,
            eventId: state.pathParameters['eid']!,
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          groupDetailProvider(groupId).overrideWith(
            (ref) => Stream.value(
              Group(
                id: groupId,
                name: 'Trip',
                inviteCode: 'ABC123',
                createdBy: 'uid-sara',
                memberIds: const ['uid-sara', 'uid-omar'],
                currency: 'OMR',
                createdAt: DateTime(2026),
              ),
            ),
          ),
          currentUserIdProvider.overrideWithValue('uid-sara'),
          eventDetailProvider(
            eventRef,
          ).overrideWith((ref) => Stream.value(event)),
          eventExpensesProvider(
            eventRef,
          ).overrideWith((ref) => Stream.value([foodExpense])),
          eventSettlementsProvider(
            eventRef,
          ).overrideWith((ref) => Stream.value(settlements)),
          groupMembersProvider(
            groupId,
          ).overrideWith((ref) => Stream.value(members)),
        ],
        child: MaterialApp.router(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  void applyCategoryFilter(WidgetTester tester, int bucket) {
    final strip = tester.widget<LedgerCategoryStrip>(
      find.byType(LedgerCategoryStrip),
    );
    strip.onChange(bucket);
  }

  testWidgets(
    'active category filter with settlements present shows the hidden note',
    (tester) async {
      await pumpLedger(tester, settlements: [settlement]);

      expect(find.text(noteText), findsNothing);

      applyCategoryFilter(tester, 1); // Food — the expense still matches.
      await tester.pumpAndSettle();

      expect(find.text(noteText), findsOneWidget);
    },
  );

  testWidgets('note also shows on the category-empty state', (tester) async {
    await pumpLedger(tester, settlements: [settlement]);

    applyCategoryFilter(tester, 2); // Groceries — nothing matches.
    await tester.pumpAndSettle();

    expect(find.text('Nothing in this category'), findsOneWidget);
    expect(find.text(noteText), findsOneWidget);
  });

  testWidgets('no settlements → no note, even with an active filter', (
    tester,
  ) async {
    await pumpLedger(tester, settlements: const []);

    applyCategoryFilter(tester, 1);
    await tester.pumpAndSettle();

    expect(find.text(noteText), findsNothing);
  });
}
