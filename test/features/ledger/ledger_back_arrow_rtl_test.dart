import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/ledger/screens/ledger_screen.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// Regression for #126: the LedgerScreen back button used a bare
/// `Iconsax.arrow_left`, so it pointed ← in Arabic. It must show the mirrored
/// glyph (`arrow_right`) under RTL. The back button is the only directional
/// arrow on the resting ledger view, so byIcon targets it uniquely.
void main() {
  const groupId = 'g1';
  const eventId = 'e1';
  const eventRef = (groupId: groupId, eventId: eventId);

  final event = Event(
    id: eventId,
    groupId: groupId,
    name: 'Beach Trip',
    type: EventType.trip,
    createdBy: 'uid-creator',
    participantIds: const ['uid-creator'],
    participantNames: const {'uid-creator': 'Alice'},
    modules: const EventModules(),
    createdAt: DateTime(2026, 1, 10),
  );

  Widget buildLedger({Locale? locale}) {
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
              createdBy: 'creator',
              memberIds: const [],
              currency: 'OMR',
              createdAt: DateTime(2026),
            ),
          ),
        ),
        currentUserIdProvider.overrideWithValue('uid-creator'),
        eventDetailProvider(eventRef).overrideWith((ref) => Stream.value(event)),
        eventExpensesProvider(
          eventRef,
        ).overrideWith((ref) => Stream.value(const [])),
        eventSettlementsProvider(
          eventRef,
        ).overrideWith((ref) => Stream.value(const <Settlement>[])),
        groupMembersProvider(
          groupId,
        ).overrideWith((ref) => Stream.value(groupMembers)),
      ],
      child: MaterialApp.router(
        theme: AppTheme.lightTheme,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    );
  }

  testWidgets('back arrow is mirrored (arrow_right) under Arabic RTL', (
    tester,
  ) async {
    await tester.pumpWidget(buildLedger(locale: const Locale('ar')));
    await tester.pumpAndSettle();

    expect(find.byIcon(Iconsax.arrow_right), findsOneWidget);
    expect(find.byIcon(Iconsax.arrow_left), findsNothing);
  });

  testWidgets('back arrow stays arrow_left under English LTR', (tester) async {
    await tester.pumpWidget(buildLedger(locale: const Locale('en')));
    await tester.pumpAndSettle();

    expect(find.byIcon(Iconsax.arrow_left), findsOneWidget);
    expect(find.byIcon(Iconsax.arrow_right), findsNothing);
  });
}
