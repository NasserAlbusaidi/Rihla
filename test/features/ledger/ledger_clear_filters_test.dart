import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:safar/core/keys/shared_keys.dart';
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

/// #358 — the category-empty ledger state must offer a "Clear filters" CTA
/// that resets the active category filter and brings the expenses back.
void main() {
  const groupId = 'g1';
  const eventId = 'e1';
  const eventRef = (groupId: groupId, eventId: eventId);

  final event = Event(
    id: eventId,
    groupId: groupId,
    name: 'Beach Trip',
    type: EventType.trip,
    createdBy: 'uid-sara',
    participantIds: const ['uid-sara'],
    participantNames: const {'uid-sara': 'Sara'},
    modules: const EventModules(),
    createdAt: DateTime(2026, 1, 10),
  );

  // One expense, categorised as Food (bucket 1).
  final foodExpense = Expense(
    id: 'x1',
    tripId: eventId,
    payerParticipantId: 'uid-sara',
    amount: Decimal.parse('30.000'),
    scope: ExpenseScope.global,
    createdAt: DateTime(2026, 1, 11),
    createdBy: 'uid-sara',
    currency: 'OMR',
    categoryName: 'Food',
  );

  Future<void> pumpLedger(WidgetTester tester) async {
    final members = [
      GroupMember(
        id: 'uid-sara',
        groupId: groupId,
        userId: 'uid-sara',
        displayName: 'Sara',
        role: 'CREATOR',
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
                memberIds: const ['uid-sara'],
                currency: 'OMR',
                createdAt: DateTime(2026),
              ),
            ),
          ),
          currentUserIdProvider.overrideWithValue('uid-sara'),
          eventDetailProvider(eventRef).overrideWith((ref) => Stream.value(event)),
          eventExpensesProvider(
            eventRef,
          ).overrideWith((ref) => Stream.value([foodExpense])),
          eventSettlementsProvider(
            eventRef,
          ).overrideWith((ref) => Stream.value(const <Settlement>[])),
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

  testWidgets(
    'category-empty state shows Clear filters CTA that resets the filter',
    (tester) async {
      await pumpLedger(tester);

      // Sanity: the Food expense is visible with no filter.
      expect(find.text('Food'), findsWidgets);
      expect(find.text('Nothing in this category'), findsNothing);

      // Apply a category filter that matches no expense (Lodging = bucket 2)
      // via the strip's public callback — exactly what tapping a chip does.
      final strip = tester.widget<LedgerCategoryStrip>(
        find.byType(LedgerCategoryStrip),
      );
      strip.onChange(2);
      await tester.pumpAndSettle();

      // Category-empty state + Clear filters CTA appear.
      expect(find.text('Nothing in this category'), findsOneWidget);
      expect(find.text('Clear filters'), findsOneWidget);

      // Tapping Clear filters resets the filter — expenses come back, empty
      // state and CTA disappear.
      final clearCta = find.byKey(SharedKeys.emptyStateCtaButton);
      await tester.ensureVisible(clearCta);
      await tester.pumpAndSettle();
      await tester.tap(clearCta);
      await tester.pumpAndSettle();

      expect(find.text('Nothing in this category'), findsNothing);
      expect(find.text('Clear filters'), findsNothing);
    },
  );
}
