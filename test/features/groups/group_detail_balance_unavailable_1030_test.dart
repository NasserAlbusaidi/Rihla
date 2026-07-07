import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/screens/group_detail_screen.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #1030 — a hard-errored members stream makes `groupBalancesProvider` loud;
/// the group-detail balance card must render an honest "Couldn't load
/// balances." caption, NEVER the affirmative false "all settled" that an
/// empty `balanceLines` fold produced (the Gate R1 adversary's [P2]).
void main() {
  const groupId = 'group-1';

  final group = Group(
    id: groupId,
    name: 'Trip',
    inviteCode: 'AAAAAA',
    createdBy: 'uid-creator',
    memberIds: const ['uid-creator'],
    createdAt: DateTime(2025, 1, 1),
  );

  Future<void> pump(WidgetTester tester, List<Override> extra) async {
    SharedPreferences.setMockInitialValues({'device_name': 'Alice'});
    final prefs = await SharedPreferences.getInstance();
    final router = GoRouter(
      initialLocation: '/group/$groupId',
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, _) => const Scaffold(body: Text('Home')),
        ),
        GoRoute(
          path: '/group/:gid',
          builder: (_, state) =>
              GroupDetailScreen(groupId: state.pathParameters['gid']!),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          currentUserIdProvider.overrideWithValue('uid-creator'),
          groupDetailProvider(
            groupId,
          ).overrideWith((ref) => Stream.value(group)),
          ...extra,
        ],
        child: MaterialApp.router(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pump(); // subcollection streams settle
  }

  testWidgets(
    '#1030: balances hard error → card shows unavailable, never "all settled"',
    (tester) async {
      // NON-permission error: the #574 staging retry (_isPermissionDenied)
      // must never enter the frame — this is the terminal-honesty path.
      await pump(tester, [
        groupEventsProvider(
          groupId,
        ).overrideWith((ref) => Stream.value(const <Event>[])),
        groupMembersProvider(groupId).overrideWith(
          (ref) => Stream<List<GroupMember>>.error(StateError('members died')),
        ),
        groupSettlementsProvider(
          groupId,
        ).overrideWith((ref) => Stream.value(const <Settlement>[])),
      ]);
      // Drain the card's flutter_animate entrance timers.
      await tester.pumpAndSettle();

      expect(find.textContaining("Couldn't load balances."), findsOneWidget);
      expect(find.textContaining('all settled'), findsNothing);
    },
  );

  testWidgets(
    '#1030 pin: healthy empty group still shows the settled caption',
    (tester) async {
      await pump(tester, [
        groupEventsProvider(
          groupId,
        ).overrideWith((ref) => Stream.value(const <Event>[])),
        groupMembersProvider(groupId).overrideWith(
          (ref) => Stream.value([
            GroupMember(
              id: 'uid-creator',
              groupId: groupId,
              userId: 'uid-creator',
              displayName: 'Alice',
              role: 'MEMBER',
              joinedAt: DateTime(2025, 1, 1),
            ),
          ]),
        ),
        groupSettlementsProvider(
          groupId,
        ).overrideWith((ref) => Stream.value(const <Settlement>[])),
      ]);
      // Drain the card's flutter_animate entrance timers.
      await tester.pumpAndSettle();

      expect(find.textContaining('all settled'), findsOneWidget);
      expect(find.textContaining("Couldn't load balances."), findsNothing);
    },
  );
}
