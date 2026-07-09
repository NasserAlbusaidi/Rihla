import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/keys/group_keys.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/screens/group_detail_screen.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const groupId = 'group-1';

  final testGroup = Group(
    id: groupId,
    name: 'Adventure Crew',
    inviteCode: 'ABC123',
    createdBy: 'uid-creator',
    memberIds: const ['uid-creator', 'uid-member'],
    createdAt: DateTime(2026, 1, 1),
  );

  final members = [
    GroupMember(
      id: 'member-1',
      groupId: groupId,
      userId: 'uid-creator',
      displayName: 'Alice',
      role: 'CREATOR',
      joinedAt: DateTime(2026, 1, 1),
    ),
    GroupMember(
      id: 'member-2',
      groupId: groupId,
      userId: 'uid-member',
      displayName: 'Bob',
      role: 'MEMBER',
      joinedAt: DateTime(2026, 1, 2),
    ),
  ];

  final balances = (
    balances: <String, List<UserBalance>>{
      'OMR': [
        UserBalance(
          participantId: 'uid-creator',
          displayName: 'Alice',
          totalPaid: Decimal.zero,
          totalOwed: Decimal.zero,
          netBalance: Decimal.zero,
        ),
        UserBalance(
          participantId: 'uid-member',
          displayName: 'Bob',
          totalPaid: Decimal.zero,
          totalOwed: Decimal.zero,
          netBalance: Decimal.zero,
        ),
      ],
    },
    totalSpent: <String, Decimal>{'OMR': Decimal.zero},
    eventCount: 0,
    perEventBreakdown: <String, Map<String, Map<String, Decimal>>>{},
    memberNames: <String, String>{'uid-creator': 'Alice', 'uid-member': 'Bob'},
    memberRawNames: <String, String>{},
  );

  Future<GoRouter> pumpGroupDetail(
    WidgetTester tester, {
    String? initialLocation,
  }) async {
    SharedPreferences.setMockInitialValues({'device_name': 'Alice'});
    final prefs = await SharedPreferences.getInstance();
    final router = GoRouter(
      initialLocation: initialLocation ?? '/group/$groupId',
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, _) => const Scaffold(body: Text('Home')),
        ),
        GoRoute(
          path: '/group/:gid',
          builder: (_, state) =>
              GroupDetailScreen(groupId: state.pathParameters['gid']!),
          routes: [
            GoRoute(
              path: 'create-event',
              builder: (_, state) => Scaffold(
                body: Text('CreateEvent:${state.pathParameters['gid']}'),
              ),
            ),
            GoRoute(
              path: 'settle-up',
              builder: (_, state) => Scaffold(
                body: Text('GroupSettleUp:${state.pathParameters['gid']}'),
              ),
            ),
            GoRoute(
              path: 'settings',
              builder: (_, state) => Scaffold(
                body: Text('GroupSettings:${state.pathParameters['gid']}'),
              ),
            ),
            GoRoute(
              path: 'activity',
              builder: (_, state) => Scaffold(
                body: Text('GroupActivity:${state.pathParameters['gid']}'),
              ),
            ),
          ],
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
          ).overrideWith((ref) => Stream.value(testGroup)),
          groupMembersProvider(
            groupId,
          ).overrideWith((ref) => Stream.value(members)),
          groupEventsProvider(
            groupId,
          ).overrideWith((ref) => Stream.value(const [])),
          groupBalancesProvider(
            groupId,
          ).overrideWith((ref) => AsyncValue.data(balances)),
          groupActivityProvider(
            groupId,
          ).overrideWith((ref) => Stream.value(const [])),
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
    return router;
  }

  group('GroupDetailScreen navigation', () {
    testWidgets('hero New event CTA routes to create-event (single entry)', (
      tester,
    ) async {
      await pumpGroupDetail(tester);

      // #486: exactly one "New event" entry — the hero CTA. The events section
      // header no longer duplicates the action.
      expect(find.text('New event'), findsOneWidget);
      await tester.tap(find.text('New event'));
      await tester.pumpAndSettle();

      expect(find.text('CreateEvent:$groupId'), findsOneWidget);
    });

    testWidgets('settle-up CTA routes to group settle-up', (tester) async {
      await pumpGroupDetail(tester);

      await tester.tap(find.byKey(GroupKeys.settleUpCta));
      await tester.pumpAndSettle();

      expect(find.text('GroupSettleUp:$groupId'), findsOneWidget);
    });

    testWidgets('overflow settings item routes to group settings', (
      tester,
    ) async {
      await pumpGroupDetail(tester);

      await tester.tap(find.byTooltip('Group options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Group settings'));
      await tester.pumpAndSettle();

      expect(find.text('GroupSettings:$groupId'), findsOneWidget);
    });

    testWidgets('overflow activity item routes to group activity', (
      tester,
    ) async {
      await pumpGroupDetail(tester);

      await tester.tap(find.byTooltip('Group options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Activity'));
      await tester.pumpAndSettle();

      expect(find.text('GroupActivity:$groupId'), findsOneWidget);
    });

    testWidgets('blocked system pop from direct entry routes home', (
      tester,
    ) async {
      await pumpGroupDetail(tester);

      expect(find.byKey(GroupKeys.detailScreen), findsOneWidget);

      final popScope = tester.widget<PopScope>(
        find.byWidgetPredicate((widget) => widget is PopScope),
      );
      popScope.onPopInvokedWithResult!(false, null);
      await tester.pumpAndSettle();

      expect(find.text('Home'), findsOneWidget);
      expect(find.byKey(GroupKeys.detailScreen), findsNothing);
    });

    testWidgets('blocked system pop from pushed group detail pops to home', (
      tester,
    ) async {
      final router = await pumpGroupDetail(tester, initialLocation: '/home');

      unawaited(router.push('/group/$groupId'));
      await tester.pumpAndSettle();

      expect(find.byKey(GroupKeys.detailScreen), findsOneWidget);

      final popScope = tester.widget<PopScope>(
        find.byWidgetPredicate((widget) => widget is PopScope),
      );
      popScope.onPopInvokedWithResult!(false, null);
      await tester.pumpAndSettle();

      expect(find.text('Home'), findsOneWidget);
      expect(find.byKey(GroupKeys.detailScreen), findsNothing);
    });

    testWidgets('cover back button pops to home from pushed group detail', (
      tester,
    ) async {
      final router = await pumpGroupDetail(tester, initialLocation: '/home');

      unawaited(router.push('/group/$groupId'));
      await tester.pumpAndSettle();

      expect(find.byKey(GroupKeys.detailScreen), findsOneWidget);

      await tester.tap(find.byIcon(Iconsax.arrow_left).first);
      await tester.pumpAndSettle();

      expect(find.text('Home'), findsOneWidget);
      expect(find.byKey(GroupKeys.detailScreen), findsNothing);
    });

    testWidgets('#1067 cover back button exposes localized semantic label', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      addTearDown(handle.dispose);
      await pumpGroupDetail(tester);

      final l10n = AppLocalizations.of(
        tester.element(find.byKey(GroupKeys.detailScreen)),
      );
      expect(find.bySemanticsLabel(l10n.commonBack), findsOneWidget);
    });

    testWidgets('cover header controls expose 48dp hit targets', (
      tester,
    ) async {
      await pumpGroupDetail(tester);

      final backTargets = find.ancestor(
        of: find.byIcon(Iconsax.arrow_left).first,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is SizedBox && widget.width == 48 && widget.height == 48,
        ),
      );
      final overflowTargets = find.ancestor(
        of: find.byTooltip('Group options'),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is SizedBox && widget.width == 48 && widget.height == 48,
        ),
      );

      expect(backTargets, findsAtLeastNWidgets(1));
      expect(overflowTargets, findsAtLeastNWidgets(1));
      expect(tester.getSize(backTargets.first), const Size(48, 48));
      expect(tester.getSize(overflowTargets.first), const Size(48, 48));
    });
  });
}
