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
import 'package:safar/features/ledger/keys/ledger_keys.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/ledger/screens/ledger_screen.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// #342: the event activity feed route (`/group/:gid/event/:eid/activity`) had
/// no in-app caller, so the #248 audit log it renders was unreachable. The
/// ledger app bar now carries an activity button that navigates to the
/// *event-scoped* feed.
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

  Widget buildLedger() {
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
                // Marker route echoing the path params so the test proves it
                // landed on the EVENT feed with the correct gid/eid.
                GoRoute(
                  path: 'activity',
                  builder: (context, state) => Scaffold(
                    body: Text(
                      'ACTIVITY ${state.pathParameters['gid']}/'
                      '${state.pathParameters['eid']}',
                    ),
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
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    );
  }

  testWidgets('ledger app bar shows an activity button', (tester) async {
    await tester.pumpWidget(buildLedger());
    await tester.pumpAndSettle();

    expect(find.byKey(LedgerKeys.activityButton), findsOneWidget);
    expect(find.byIcon(Iconsax.activity), findsOneWidget);
  });

  testWidgets('tapping activity navigates to the event-scoped feed', (
    tester,
  ) async {
    await tester.pumpWidget(buildLedger());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(LedgerKeys.activityButton));
    await tester.pumpAndSettle();

    expect(find.text('ACTIVITY $groupId/$eventId'), findsOneWidget);
  });
}
