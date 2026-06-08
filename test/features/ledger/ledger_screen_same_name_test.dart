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
import 'package:safar/l10n/generated/app_localizations.dart';

/// #289 — the ledger roster must distinguish two members both named "Ahmed".
void main() {
  const groupId = 'g1';
  const eventId = 'e1';
  const eventRef = (groupId: groupId, eventId: eventId);

  final event = Event(
    id: eventId,
    groupId: groupId,
    name: 'Beach Trip',
    type: EventType.trip,
    createdBy: 'uid-sara-3333',
    participantIds: const ['uid-sara-3333', 'uid-ahmed-aaaa', 'uid-ahmed-bbbb'],
    participantNames: const {
      'uid-sara-3333': 'Sara Said',
      'uid-ahmed-aaaa': 'Ahmed',
      'uid-ahmed-bbbb': 'Ahmed',
    },
    modules: const EventModules(),
    createdAt: DateTime(2026, 1, 10),
  );

  testWidgets('ledger roster disambiguates two members named Ahmed',
      (tester) async {
    final groupMembers = [
      for (final uid in event.participantIds)
        GroupMember(
          id: uid,
          groupId: groupId,
          userId: uid,
          displayName: event.participantNames[uid]!,
          role: 'MEMBER',
          joinedAt: event.createdAt,
        ),
    ];
    final expense = Expense(
      id: 'x1',
      tripId: eventId,
      payerParticipantId: 'uid-ahmed-aaaa',
      amount: Decimal.parse('30.000'),
      scope: ExpenseScope.global,
      createdAt: DateTime(2026, 1, 11),
      createdBy: 'uid-ahmed-aaaa',
      currency: 'OMR',
    );

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
                createdBy: 'creator',
                memberIds: const [],
                currency: 'OMR',
                createdAt: DateTime(2026),
              ),
            ),
          ),
          currentUserIdProvider.overrideWithValue('uid-sara-3333'),
          eventDetailProvider(
            eventRef,
          ).overrideWith((ref) => Stream.value(event)),
          eventExpensesProvider(
            eventRef,
          ).overrideWith((ref) => Stream.value([expense])),
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
      ),
    );
    await tester.pumpAndSettle();

    // Roster collapses to first-name; the discriminator must survive it.
    expect(find.text('Ahmed (#aaaa)'), findsWidgets);
    expect(find.text('Ahmed (#bbbb)'), findsWidgets);
    expect(find.text('Ahmed'), findsNothing);
  });
}
