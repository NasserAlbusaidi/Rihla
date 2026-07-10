import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/shared/widgets/cover_art.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/repaint_boundary_finder.dart';

import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/features/auth/providers/auth_provider.dart';
import 'package:safar/features/events/models/event_model.dart'
    show Event, EventModules, EventType;
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/events/utils/event_display.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/groups/keys/group_keys.dart';
import 'package:safar/features/groups/models/group_activity_log_model.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/screens/group_detail_screen.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/shared/widgets/r_amount.dart';
import 'package:safar/shared/widgets/skeleton_loader.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _groupId = 'group-1';

final _testGroup = Group(
  id: _groupId,
  name: 'Adventure Crew',
  inviteCode: 'ABC123',
  createdBy: 'uid-creator',
  memberIds: const ['uid-creator', 'uid-member'],
  currency: 'OMR',
  createdAt: DateTime(2026, 1, 1),
);

final _testMembers = [
  GroupMember(
    id: 'mem-1',
    groupId: _groupId,
    userId: 'uid-creator',
    displayName: 'Alice',
    role: 'CREATOR',
    joinedAt: DateTime(2026, 1, 1),
  ),
  GroupMember(
    id: 'mem-2',
    groupId: _groupId,
    userId: 'uid-member',
    displayName: 'Bob',
    role: 'MEMBER',
    joinedAt: DateTime(2026, 1, 2),
  ),
];

/// GroupBalances with totalSpent > 0 (expenses exist).
final _balancesWithExpenses = (
  balances: <String, List<UserBalance>>{
    'OMR': [
      UserBalance(
        participantId: 'uid-creator',
        displayName: 'Alice',
        totalPaid: Decimal.parse('30.000'),
        totalOwed: Decimal.parse('15.000'),
        netBalance: Decimal.parse('15.000'),
      ),
      UserBalance(
        participantId: 'uid-member',
        displayName: 'Bob',
        totalPaid: Decimal.parse('0.000'),
        totalOwed: Decimal.parse('15.000'),
        netBalance: Decimal.parse('-15.000'),
      ),
    ],
  },
  totalSpent: <String, Decimal>{'OMR': Decimal.parse('30.000')},
  eventCount: 1,
  perEventBreakdown: <String, Map<String, Map<String, Decimal>>>{
    'uid-creator': {
      'event-1': {'OMR': Decimal.parse('15.000')},
    },
    'uid-member': {
      'event-1': {'OMR': Decimal.parse('-15.000')},
    },
  },
  memberNames: <String, String>{'uid-creator': 'Alice', 'uid-member': 'Bob'},
  memberRawNames: <String, String>{},
);

/// GroupBalances with totalSpent == 0 (no expenses yet).
final _balancesEmpty = (
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

/// Two-bucket GroupBalances: current user (uid-creator) nets [myOmrNet] in
/// 'OMR' and [myUsdNet] in 'USD'; uid-member mirrors each (#382 PR-5).
GroupBalances _twoBucketBalances({
  required Decimal myOmrNet,
  required Decimal myUsdNet,
}) {
  List<UserBalance> bucket(Decimal myNet) => [
    UserBalance(
      participantId: 'uid-creator',
      displayName: 'Alice',
      totalPaid: myNet > Decimal.zero ? myNet : Decimal.zero,
      totalOwed: myNet < Decimal.zero ? -myNet : Decimal.zero,
      netBalance: myNet,
    ),
    UserBalance(
      participantId: 'uid-member',
      displayName: 'Bob',
      totalPaid: myNet < Decimal.zero ? -myNet : Decimal.zero,
      totalOwed: myNet > Decimal.zero ? myNet : Decimal.zero,
      netBalance: -myNet,
    ),
  ];
  return (
    balances: <String, List<UserBalance>>{
      'OMR': bucket(myOmrNet),
      'USD': bucket(myUsdNet),
    },
    totalSpent: <String, Decimal>{
      'OMR': myOmrNet.abs(),
      'USD': myUsdNet.abs(),
    },
    eventCount: 1,
    perEventBreakdown: const <String, Map<String, Map<String, Decimal>>>{},
    memberNames: <String, String>{'uid-creator': 'Alice', 'uid-member': 'Bob'},
    memberRawNames: <String, String>{},
  );
}

/// Single-event group where the current user's per-event share is exactly
/// [myShares] (currency → net) while the group-bucket balances stay 'OMR'
/// (#382 PR-5).
GroupBalances _eventShareBalances(Map<String, Decimal> myShares) => (
  balances: <String, List<UserBalance>>{
    'OMR': [
      UserBalance(
        participantId: 'uid-creator',
        displayName: 'Alice',
        totalPaid: Decimal.parse('30.000'),
        totalOwed: Decimal.parse('15.000'),
        netBalance: Decimal.parse('15.000'),
      ),
      UserBalance(
        participantId: 'uid-member',
        displayName: 'Bob',
        totalPaid: Decimal.zero,
        totalOwed: Decimal.parse('15.000'),
        netBalance: Decimal.parse('-15.000'),
      ),
    ],
  },
  totalSpent: <String, Decimal>{'OMR': Decimal.parse('30.000')},
  eventCount: 1,
  perEventBreakdown: <String, Map<String, Map<String, Decimal>>>{
    'uid-creator': {'event-1': myShares},
  },
  memberNames: <String, String>{'uid-creator': 'Alice', 'uid-member': 'Bob'},
  memberRawNames: <String, String>{},
);

final _testEvent = Event(
  id: 'event-1',
  groupId: _groupId,
  name: 'Beach Trip',
  type: EventType.trip,
  createdAt: DateTime(2026, 1, 10),
  participantIds: const ['uid-creator', 'uid-member'],
  participantNames: const {'uid-creator': 'Alice', 'uid-member': 'Bob'},
  modules: const EventModules(),
  createdBy: 'uid-creator',
);

final _testActivity = [
  GroupActivityLog(
    id: 'act-1',
    type: 'event_created',
    actorId: 'uid-creator',
    actorName: 'Alice',
    description: 'created an event',
    timestamp: DateTime(2026, 1, 15),
  ),
];

/// Wraps a widget with ProviderScope + MaterialApp.
///
/// Overrides groupDetailProvider, groupMembersProvider, groupEventsProvider,
/// groupBalancesProvider, groupActivityProvider, and currentUserIdProvider to
/// prevent Firestore calls in widget tests.
///
/// [currentUid] defaults to 'uid-creator' so settle-up CTA tests work without
/// a real Firebase Auth instance.
Widget _wrap(
  Widget child,
  SharedPreferences prefs, {
  required AsyncValue<GroupBalances> balancesAsync,
  List<GroupActivityLog> activities = const [],
  List<Event> events = const [],
  String? currentUid = 'uid-creator',
  Locale? locale,
}) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      currentUserIdProvider.overrideWithValue(currentUid),
      groupDetailProvider(
        _groupId,
      ).overrideWith((ref) => Stream.value(_testGroup)),
      groupMembersProvider(
        _groupId,
      ).overrideWith((ref) => Stream.value(_testMembers)),
      groupEventsProvider(
        _groupId,
      ).overrideWith((ref) => Stream.value(events)),
      groupBalancesProvider(_groupId).overrideWith((ref) => balancesAsync),
      groupActivityProvider(
        _groupId,
      ).overrideWith((ref) => Stream.value(activities)),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  );
}

Widget _wrapWithRouter({
  required SharedPreferences prefs,
  required String initialLocation,
}) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/home',
        builder: (_, _) => const Scaffold(body: Text('HomeRoute')),
      ),
      GoRoute(
        path: '/group/:gid',
        builder: (_, state) =>
            GroupDetailScreen(groupId: state.pathParameters['gid']!),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      currentUserIdProvider.overrideWithValue('uid-creator'),
      groupDetailProvider(
        _groupId,
      ).overrideWith((ref) => Stream.value(_testGroup)),
      groupMembersProvider(
        _groupId,
      ).overrideWith((ref) => Stream.value(_testMembers)),
      groupEventsProvider(
        _groupId,
      ).overrideWith((ref) => Stream.value(const [])),
      groupBalancesProvider(
        _groupId,
      ).overrideWith((ref) => const AsyncValue.loading()),
      groupActivityProvider(
        _groupId,
      ).overrideWith((ref) => Stream.value(const [])),
    ],
    child: MaterialApp.router(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  );
}

Finder _textContaining(String value) {
  return find.byWidgetPredicate((widget) {
    if (widget is! Text) return false;
    return (widget.data?.contains(value) ?? false) ||
        (widget.textSpan?.toPlainText().contains(value) ?? false);
  });
}

Future<void> _scrollUntilVisible(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    260,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late SharedPreferences prefs;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({'device_name': 'Test User'});
    prefs = await SharedPreferences.getInstance();
  });

  // #486 — one balance truth: the current user's net is owned by the hero and
  // must NOT be restated in the People roster; a single "New event" entry.
  group('#486 one balance truth', () {
    testWidgets(
      'current user net is owned by the hero, not restated in People roster',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            const GroupDetailScreen(groupId: _groupId),
            prefs,
            balancesAsync: AsyncValue.data(_balancesWithExpenses),
          ),
        );
        await tester.pumpAndSettle();

        // The hero (top, in view before scrolling) owns the number.
        expect(find.text('they owe you'), findsOneWidget);
        expect(_textContaining('15.000'), findsWidgets);

        await _scrollUntilVisible(
          tester,
          find.byKey(GroupKeys.membersAndBalancesSection),
        );

        // The self-row exists and is collapsed: no money figure, just a muted
        // "shown above" — magnitude-independent, so Alice's +15.000 and Bob's
        // -15.000 sharing a magnitude can't mask the assertion.
        expect(find.byKey(GroupKeys.selfMemberRow), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(GroupKeys.selfMemberRow),
            matching: find.byType(RAmount),
          ),
          findsNothing,
        );
        expect(find.text('shown above'), findsOneWidget);
      },
    );

    testWidgets('other members still show their net in the People roster', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const GroupDetailScreen(groupId: _groupId),
          prefs,
          balancesAsync: AsyncValue.data(_balancesWithExpenses),
        ),
      );
      await tester.pumpAndSettle();
      await _scrollUntilVisible(
        tester,
        find.byKey(GroupKeys.membersAndBalancesSection),
      );

      final bobRow = find.ancestor(
        of: find.text('Bob'),
        matching: find.byType(Row),
      );
      expect(
        find.descendant(of: bobRow, matching: find.byType(RAmount)),
        findsWidgets,
      );
    });

    testWidgets('the roster section is renamed PEOPLE', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GroupDetailScreen(groupId: _groupId),
          prefs,
          balancesAsync: AsyncValue.data(_balancesWithExpenses),
        ),
      );
      await tester.pumpAndSettle();
      await _scrollUntilVisible(
        tester,
        find.byKey(GroupKeys.membersAndBalancesSection),
      );

      expect(find.text('PEOPLE'), findsOneWidget);
      expect(find.text('MEMBERS'), findsNothing);
    });

    testWidgets('only one New event entry (events header action removed)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const GroupDetailScreen(groupId: _groupId),
          prefs,
          balancesAsync: AsyncValue.data(_balancesWithExpenses),
          events: [_testEvent],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('New event'), findsOneWidget);
    });
  });

  group('GroupDetailScreen current layout', () {
    testWidgets('shows cover header and balance card when balances load', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const GroupDetailScreen(groupId: _groupId),
          prefs,
          balancesAsync: AsyncValue.data(_balancesWithExpenses),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(GroupKeys.detailScreen), findsOneWidget);
      expect(find.text('Adventure Crew'), findsOneWidget);
      expect(find.text('GROUP · 2 MEMBERS'), findsOneWidget);
      expect(find.text('Your balance here'), findsOneWidget);
      expect(_textContaining('15.000'), findsWidgets);
      expect(find.text('they owe you'), findsOneWidget);
      expect(find.byKey(GroupKeys.settleUpCta), findsOneWidget);

      // #626: the header cover art is wrapped in a RepaintBoundary so its
      // procedural raster is cached (header lives in a SliverToBoxAdapter,
      // which inserts no automatic per-child boundary).
      expectWrappedInRepaintBoundary(find.byType(CoverArt));
    });

    testWidgets('direct entry back button routes home when no stack exists', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapWithRouter(prefs: prefs, initialLocation: '/group/$_groupId'),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(GroupKeys.detailScreen), findsOneWidget);

      await tester.tap(find.byIcon(Iconsax.arrow_left).first);
      await tester.pumpAndSettle();

      expect(find.text('HomeRoute'), findsOneWidget);
      expect(find.byKey(GroupKeys.detailScreen), findsNothing);
    });

    testWidgets('zero balance shows all-settled state and settle-up path', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const GroupDetailScreen(groupId: _groupId),
          prefs,
          balancesAsync: AsyncValue.data(_balancesEmpty),
        ),
      );
      await tester.pumpAndSettle();

      expect(_textContaining('0.000'), findsWidgets);
      expect(find.text('all settled'), findsOneWidget);
      expect(find.byKey(GroupKeys.settleUpCta), findsOneWidget);
    });

    testWidgets('shows Members section with balance rows', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GroupDetailScreen(groupId: _groupId),
          prefs,
          balancesAsync: AsyncValue.data(_balancesWithExpenses),
        ),
      );
      await tester.pumpAndSettle();

      await _scrollUntilVisible(
        tester,
        find.byKey(GroupKeys.membersAndBalancesSection),
      );

      expect(find.byKey(GroupKeys.membersAndBalancesSection), findsOneWidget);
      expect(find.text('PEOPLE'), findsOneWidget);

      expect(find.text('Alice'), findsWidgets);
      expect(find.text('Bob'), findsOneWidget);
    });

    testWidgets(
      'members rows render from memberNames when the group has NO money yet '
      '(empty bucket map, #382 PR-1)',
      (tester) async {
        // A zero-money group has no currency buckets at all — the members
        // card must still list everyone (memberNames is the row source).
        final noMoney = (
          balances: const <String, List<UserBalance>>{},
          totalSpent: const <String, Decimal>{},
          eventCount: 0,
          perEventBreakdown: const <String, Map<String, Map<String, Decimal>>>{},
          memberNames: <String, String>{
            'uid-creator': 'Alice',
            'uid-member': 'Bob',
          },
          memberRawNames: <String, String>{},
        );
        await tester.pumpWidget(
          _wrap(
            const GroupDetailScreen(groupId: _groupId),
            prefs,
            balancesAsync: AsyncValue.data(noMoney),
          ),
        );
        await tester.pumpAndSettle();

        await _scrollUntilVisible(
          tester,
          find.byKey(GroupKeys.membersAndBalancesSection),
        );

        expect(find.text('Alice'), findsWidgets);
        expect(find.text('Bob'), findsOneWidget);
      },
    );

    testWidgets('shows current user balance amount when expenses exist', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const GroupDetailScreen(groupId: _groupId),
          prefs,
          balancesAsync: AsyncValue.data(_balancesWithExpenses),
        ),
      );
      await tester.pumpAndSettle();

      expect(_textContaining('15.000'), findsWidgets);
      expect(find.text('they owe you'), findsOneWidget);
    });

    testWidgets('keeps activity out of the inline group detail feed', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const GroupDetailScreen(groupId: _groupId),
          prefs,
          balancesAsync: AsyncValue.data(_balancesEmpty),
          activities: _testActivity,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(GroupKeys.recentActivitySection), findsNothing);
      expect(find.text('created an event'), findsNothing);
    });

    testWidgets('overflow menu exposes settings and activity destinations', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const GroupDetailScreen(groupId: _groupId),
          prefs,
          balancesAsync: AsyncValue.data(_balancesEmpty),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Group options'));
      await tester.pumpAndSettle();

      expect(find.text('Group settings'), findsOneWidget);
      expect(find.text('Activity'), findsOneWidget);
    });

    testWidgets(
      'invite code section is not rendered (D-05 — moved to Phase 29)',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            const GroupDetailScreen(groupId: _groupId),
            prefs,
            balancesAsync: AsyncValue.data(_balancesEmpty),
          ),
        );
        await tester.pumpAndSettle();

        // Invite code section removed from GroupDetailScreen per D-05
        expect(find.byKey(GroupKeys.inviteCodeSection), findsNothing);
      },
    );

    testWidgets('stats grid from the old layout is no longer rendered', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const GroupDetailScreen(groupId: _groupId),
          prefs,
          balancesAsync: AsyncValue.data(_balancesWithExpenses),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(GroupKeys.statsGrid), findsNothing);
      expect(find.byKey(GroupKeys.statYourBalance), findsNothing);
      expect(find.byKey(GroupKeys.statGroupTotal), findsNothing);
      expect(find.byKey(GroupKeys.statActiveMembers), findsNothing);
      expect(find.byKey(GroupKeys.statEvents), findsNothing);
    });

    testWidgets('shows settle-up CTA when balance is non-zero', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GroupDetailScreen(groupId: _groupId),
          prefs,
          balancesAsync: AsyncValue.data(_balancesWithExpenses),
        ),
      );
      await tester.pumpAndSettle();

      // Current user (uid-creator) has netBalance of 15.000 — CTA must appear
      expect(find.byKey(GroupKeys.settleUpCta), findsOneWidget);
    });

    testWidgets('keeps settle-up CTA visible when all balances are zero', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const GroupDetailScreen(groupId: _groupId),
          prefs,
          balancesAsync: AsyncValue.data(_balancesEmpty),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(GroupKeys.settleUpCta), findsOneWidget);
    });

    testWidgets('section order: Events before Members; Activity is overflow', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const GroupDetailScreen(groupId: _groupId),
          prefs,
          balancesAsync: AsyncValue.data(_balancesEmpty),
          activities: _testActivity,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(GroupKeys.eventsSection), findsOneWidget);
      await _scrollUntilVisible(
        tester,
        find.byKey(GroupKeys.membersAndBalancesSection),
      );
      expect(find.byKey(GroupKeys.membersAndBalancesSection), findsOneWidget);
      expect(find.byKey(GroupKeys.recentActivitySection), findsNothing);
    });

    testWidgets('has RefreshIndicator wrapping scrollable content (D-11)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const GroupDetailScreen(groupId: _groupId),
          prefs,
          balancesAsync: AsyncValue.data(_balancesEmpty),
        ),
      );
      await tester.pumpAndSettle();

      // RefreshIndicator must be present in the widget tree
      expect(find.byType(RefreshIndicator), findsOneWidget);
    });

    testWidgets('member sees event creation actions without a FAB', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const GroupDetailScreen(groupId: _groupId),
          prefs,
          balancesAsync: AsyncValue.data(_balancesEmpty),
          currentUid: 'uid-creator',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.text('New event'), findsOneWidget);
      expect(find.text('Create event'), findsOneWidget);
    });

    testWidgets('member can create events through the same group actions', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const GroupDetailScreen(groupId: _groupId),
          prefs,
          balancesAsync: AsyncValue.data(_balancesEmpty),
          currentUid: 'uid-member',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.text('New event'), findsOneWidget);
      expect(find.text('Create event'), findsOneWidget);
    });

    testWidgets('creator sees empty events create action', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GroupDetailScreen(groupId: _groupId),
          prefs,
          balancesAsync: AsyncValue.data(_balancesEmpty),
          currentUid: 'uid-creator',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(GroupKeys.noEventsEmpty), findsOneWidget);
      expect(find.text('Create event'), findsOneWidget);
    });

    testWidgets('member sees empty events create action', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GroupDetailScreen(groupId: _groupId),
          prefs,
          balancesAsync: AsyncValue.data(_balancesEmpty),
          currentUid: 'uid-member',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(GroupKeys.noEventsEmpty), findsOneWidget);
      expect(find.text('Create event'), findsOneWidget);
      expect(
        find.text('Create your first event to start planning together.'),
        findsOneWidget,
      );
    });

    testWidgets('tapping event card navigates to event hub', (tester) async {
      final testEvent = Event(
        id: 'event-1',
        groupId: _groupId,
        name: 'Beach Trip',
        type: EventType.trip,
        createdAt: DateTime(2026, 1, 10),
        participantIds: const ['uid-creator', 'uid-member'],
        participantNames: const {'uid-creator': 'Alice', 'uid-member': 'Bob'},
        modules: const EventModules(),
        createdBy: 'uid-creator',
      );
      final eventRef = (groupId: _groupId, eventId: testEvent.id);
      final navigatedRoutes = <String>[];

      final router = GoRouter(
        initialLocation: '/group/$_groupId',
        routes: [
          GoRoute(
            path: '/group/:gid',
            builder: (context, state) => ProviderScope(
              overrides: [
                sharedPreferencesProvider.overrideWithValue(prefs),
                currentUserIdProvider.overrideWithValue('uid-creator'),
                groupDetailProvider(
                  _groupId,
                ).overrideWith((ref) => Stream.value(_testGroup)),
                groupMembersProvider(
                  _groupId,
                ).overrideWith((ref) => Stream.value(_testMembers)),
                groupEventsProvider(
                  _groupId,
                ).overrideWith((ref) => Stream.value([testEvent])),
                groupBalancesProvider(
                  _groupId,
                ).overrideWith((ref) => AsyncValue.data(_balancesWithExpenses)),
                groupActivityProvider(
                  _groupId,
                ).overrideWith((ref) => Stream.value(const [])),
                eventExpensesProvider(
                  eventRef,
                ).overrideWith((ref) => Stream.value(const [])),
              ],
              child: GroupDetailScreen(groupId: state.pathParameters['gid']!),
            ),
            routes: [
              GoRoute(
                path: 'event/:eid',
                builder: (context, state) {
                  navigatedRoutes.add(
                    '/group/${state.pathParameters['gid']}'
                    '/event/${state.pathParameters['eid']}',
                  );
                  return const Scaffold(body: Text('Event hub'));
                },
                routes: [
                  GoRoute(
                    path: 'ledger',
                    builder: (context, state) {
                      navigatedRoutes.add(
                        '/group/${state.pathParameters['gid']}'
                        '/event/${state.pathParameters['eid']}/ledger',
                      );
                      return const Scaffold(body: Text('Ledger'));
                    },
                  ),
                ],
              ),
            ],
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp.router(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Beach Trip'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Beach Trip'));
      await tester.pumpAndSettle();

      expect(
        navigatedRoutes,
        contains('/group/$_groupId/event/${testEvent.id}'),
      );
    });

    testWidgets(
      'shows inline error with retry button when group fails to load (D-12)',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              currentUserIdProvider.overrideWithValue('uid-creator'),
              groupDetailProvider(
                _groupId,
              ).overrideWith((ref) => Stream.error(Exception('Network error'))),
              groupMembersProvider(
                _groupId,
              ).overrideWith((ref) => Stream.value(_testMembers)),
              groupEventsProvider(
                _groupId,
              ).overrideWith((ref) => Stream.value(const [])),
              groupBalancesProvider(
                _groupId,
              ).overrideWith((ref) => AsyncValue.data(_balancesEmpty)),
              groupActivityProvider(
                _groupId,
              ).overrideWith((ref) => Stream.value(const [])),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const GroupDetailScreen(groupId: _groupId),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Could not load group'), findsOneWidget);
        expect(
          find.text('Check your connection and try again.'),
          findsOneWidget,
        );
        expect(find.text('Retry'), findsOneWidget);
      },
    );

    testWidgets(
      'events section shows a layout-matched skeleton while events load, '
      'not a blank gap (#488)',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              currentUserIdProvider.overrideWithValue('uid-creator'),
              groupDetailProvider(
                _groupId,
              ).overrideWith((ref) => Stream.value(_testGroup)),
              groupMembersProvider(
                _groupId,
              ).overrideWith((ref) => Stream.value(_testMembers)),
              // Never-completing stream keeps groupEventsProvider in
              // AsyncLoading so the events section renders its loading branch.
              groupEventsProvider(_groupId).overrideWith(
                (ref) =>
                    Stream<List<Event>>.fromFuture(Completer<List<Event>>().future),
              ),
              groupBalancesProvider(
                _groupId,
              ).overrideWith((ref) => AsyncValue.data(_balancesEmpty)),
              groupActivityProvider(
                _groupId,
              ).overrideWith((ref) => Stream.value(const [])),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              // Reduce-motion (#349) swaps the infinite shimmer for a static
              // fill, so pumpAndSettle drains the finite balance-card fade
              // without spinning forever on the skeleton ticker.
              home: Builder(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(disableAnimations: true),
                  child: const GroupDetailScreen(groupId: _groupId),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(SkeletonLoader), findsOneWidget);
        // The empty-state must NOT masquerade for the loading state.
        expect(find.byKey(GroupKeys.noEventsEmpty), findsNothing);
      },
    );
  });

  group('Balance card per-currency lines (#382 PR-5)', () {
    testWidgets('zero group-bucket net does not mask a non-zero USD bucket', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const GroupDetailScreen(groupId: _groupId),
          prefs,
          balancesAsync: AsyncValue.data(
            _twoBucketBalances(
              myOmrNet: Decimal.zero,
              myUsdNet: Decimal.parse('-5.00'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('all settled'), findsNothing);
      expect(_textContaining('USD 5.00'), findsWidgets);
      expect(find.text('you owe'), findsOneWidget);
    });

    testWidgets(
      'mixed-sign buckets render one line per currency with no caption',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            const GroupDetailScreen(groupId: _groupId),
            prefs,
            balancesAsync: AsyncValue.data(
              _twoBucketBalances(
                myOmrNet: Decimal.parse('15.000'),
                myUsdNet: Decimal.parse('-5.00'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(_textContaining('OMR 15.000'), findsWidgets);
        expect(_textContaining('USD 5.00'), findsWidgets);
        expect(find.text('they owe you'), findsNothing);
        expect(find.text('you owe'), findsNothing);
        expect(find.text('all settled'), findsNothing);
      },
    );

    testWidgets('uniform-sign buckets keep the tri-state caption', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const GroupDetailScreen(groupId: _groupId),
          prefs,
          balancesAsync: AsyncValue.data(
            _twoBucketBalances(
              myOmrNet: Decimal.parse('15.000'),
              myUsdNet: Decimal.parse('5.00'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(_textContaining('OMR 15.000'), findsWidgets);
      expect(_textContaining('USD 5.00'), findsWidgets);
      expect(find.text('they owe you'), findsOneWidget);
    });
  });

  group('Members + event rows per-currency (#382 PR-5)', () {
    Finder bobRow() =>
        find.ancestor(of: find.text('Bob'), matching: find.byType(Row));

    testWidgets(
      'member row with zero group-bucket net renders the non-zero USD bucket, '
      'not "—"',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            const GroupDetailScreen(groupId: _groupId),
            prefs,
            balancesAsync: AsyncValue.data(
              _twoBucketBalances(
                myOmrNet: Decimal.zero,
                myUsdNet: Decimal.parse('-5.00'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await _scrollUntilVisible(
          tester,
          find.byKey(GroupKeys.membersAndBalancesSection),
        );

        expect(find.text('—'), findsNothing);
        expect(
          find.descendant(of: bobRow(), matching: _textContaining('USD 5.00')),
          findsWidgets,
        );
      },
    );

    testWidgets(
      'member row with two non-zero buckets renders one coded line per '
      'currency, GCC-first',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            const GroupDetailScreen(groupId: _groupId),
            prefs,
            balancesAsync: AsyncValue.data(
              _twoBucketBalances(
                myOmrNet: Decimal.parse('15.000'),
                myUsdNet: Decimal.parse('-5.00'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await _scrollUntilVisible(
          tester,
          find.byKey(GroupKeys.membersAndBalancesSection),
        );

        expect(
          find.descendant(
            of: bobRow(),
            matching: _textContaining('OMR 15.000'),
          ),
          findsWidgets,
        );
        expect(
          find.descendant(of: bobRow(), matching: _textContaining('USD 5.00')),
          findsWidgets,
        );
      },
    );

    testWidgets('event row labels a positive USD net as owed to you', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const GroupDetailScreen(groupId: _groupId),
          prefs,
          balancesAsync: AsyncValue.data(
            _eventShareBalances({'USD': Decimal.parse('10.00')}),
          ),
          events: [_testEvent],
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Beach Trip'));
      await tester.pumpAndSettle();

      expect(_textContaining('USD 10.00'), findsOneWidget);
      expect(find.text('owed to you'), findsOneWidget);
      expect(find.text('your share'), findsNothing);
      expect(find.text('no share'), findsNothing);
    });

    testWidgets('event row labels a negative signed net as you owe', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const GroupDetailScreen(groupId: _groupId),
          prefs,
          balancesAsync: AsyncValue.data(
            _eventShareBalances({'OMR': Decimal.parse('-3.000')}),
          ),
          events: [_testEvent],
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Beach Trip'));
      await tester.pumpAndSettle();

      expect(_textContaining('3.000'), findsOneWidget);
      expect(find.text('you owe'), findsOneWidget);
      expect(find.text('your share'), findsNothing);
    });

    testWidgets(
      'event row with two share buckets renders both, each with its code',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            const GroupDetailScreen(groupId: _groupId),
            prefs,
            balancesAsync: AsyncValue.data(
              _eventShareBalances({
                'OMR': Decimal.parse('-3.000'),
                'USD': Decimal.parse('10.00'),
              }),
            ),
            events: [_testEvent],
          ),
        );
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.text('Beach Trip'));
        await tester.pumpAndSettle();

        expect(_textContaining('OMR 3.000'), findsOneWidget);
        expect(_textContaining('USD 10.00'), findsOneWidget);
        expect(find.text('your balance'), findsOneWidget);
        expect(find.text('your share'), findsNothing);
      },
    );

    testWidgets('event row renders the positive-net caption in Arabic', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const GroupDetailScreen(groupId: _groupId),
          prefs,
          balancesAsync: AsyncValue.data(
            _eventShareBalances({'OMR': Decimal.parse('5.000')}),
          ),
          events: [_testEvent],
          locale: const Locale('ar'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Beach Trip'));
      await tester.pumpAndSettle();

      expect(find.text('مستحق لك'), findsOneWidget);
      expect(find.text('حصتك'), findsNothing);
    });

    testWidgets('event row with no share keeps the "—" + no-share render', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const GroupDetailScreen(groupId: _groupId),
          prefs,
          balancesAsync: AsyncValue.data(
            _eventShareBalances({'OMR': Decimal.zero}),
          ),
          events: [_testEvent],
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Beach Trip'));
      await tester.pumpAndSettle();

      expect(find.text('—'), findsOneWidget);
      expect(find.text('no share'), findsOneWidget);
    });
  });

  // #807 tranche 2.5 — promotions + affordance fixes on the group screen.
  group('#807 promotions and affordances', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    Widget wrapWithRoutes({
      String? currentUid = 'uid-creator',
      List<Event> events = const [],
      AsyncValue<GroupBalances>? balancesAsync,
      bool durable = true,
    }) {
      final router = GoRouter(
        initialLocation: '/group/$_groupId',
        routes: [
          GoRoute(
            path: '/group/:gid',
            builder: (_, state) =>
                GroupDetailScreen(groupId: state.pathParameters['gid']!),
          ),
          GoRoute(
            path: '/group/:gid/activity',
            builder: (_, _) => const Scaffold(body: Text('ActivityRoute')),
          ),
          GoRoute(
            path: '/group/:gid/settings',
            builder: (_, _) => const Scaffold(body: Text('SettingsRoute')),
          ),
        ],
      );
      return ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          currentUserIdProvider.overrideWithValue(currentUid),
          groupDetailProvider(
            _groupId,
          ).overrideWith((ref) => Stream.value(_testGroup)),
          groupMembersProvider(
            _groupId,
          ).overrideWith((ref) => Stream.value(_testMembers)),
          groupEventsProvider(
            _groupId,
          ).overrideWith((ref) => Stream.value(events)),
          groupBalancesProvider(_groupId).overrideWith(
            (ref) => balancesAsync ?? AsyncValue.data(_balancesEmpty),
          ),
          groupActivityProvider(
            _groupId,
          ).overrideWith((ref) => Stream.value(const [])),
          // #818: the add-by-name shortcut is now also gated on durability
          // (addShadowMember hard-rejects anonymous callers server-side).
          isDurableUserProvider.overrideWithValue(durable),
        ],
        child: MaterialApp.router(
          theme: AppTheme.lightTheme,
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      );
    }

    testWidgets('header clock icon routes to the group activity screen', (
      tester,
    ) async {
      await tester.pumpWidget(wrapWithRoutes());
      await tester.pumpAndSettle();

      expect(
        find.byKey(GroupKeys.groupDetailActivityButton),
        findsOneWidget,
      );
      await tester.tap(find.byKey(GroupKeys.groupDetailActivityButton));
      await tester.pumpAndSettle();

      expect(find.text('ActivityRoute'), findsOneWidget);
    });

    testWidgets('creator sees the People add-person action and it opens '
        'AddShadowMemberSheet', (tester) async {
      await tester.pumpWidget(wrapWithRoutes());
      await tester.pumpAndSettle();

      // The People section sits below the fold — build it by scrolling.
      final action = find.byKey(GroupKeys.groupDetailAddPersonAction);
      await tester.scrollUntilVisible(
        action,
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(action, findsOneWidget);
      await tester.tap(action);
      await tester.pumpAndSettle();

      expect(find.byKey(GroupKeys.addPersonInput), findsOneWidget);
    });

    testWidgets('non-creator gets no People add-person action', (
      tester,
    ) async {
      await tester.pumpWidget(wrapWithRoutes(currentUid: 'uid-member'));
      await tester.pumpAndSettle();

      // Build the People section (scroll to its title), then assert the
      // action is absent for a non-creator.
      await tester.scrollUntilVisible(
        find.byKey(GroupKeys.membersAndBalancesSection),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(GroupKeys.groupDetailAddPersonAction),
        findsNothing,
      );
    });

    testWidgets(
      'D6-R: anonymous creator sees the People add-person action',
      (tester) async {
        await tester.pumpWidget(wrapWithRoutes(durable: false));
        await tester.pumpAndSettle();

        // Same creator uid as the durable-creator test, but anonymous — the
        // affordance now shows (addShadowMember accepts anon creators; the
        // durable boundary moved to join/claim).
        await tester.scrollUntilVisible(
          find.byKey(GroupKeys.membersAndBalancesSection),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(GroupKeys.groupDetailAddPersonAction),
          findsOneWidget,
        );
      },
    );

    testWidgets('member avatar stack routes to group settings', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapWithRoutes(balancesAsync: AsyncValue.data(_balancesWithExpenses)),
      );
      await tester.pumpAndSettle();

      final stack = find.byKey(GroupKeys.groupDetailMemberStack);
      expect(stack, findsOneWidget);
      await tester.tap(stack);
      await tester.pumpAndSettle();

      expect(find.text('SettingsRoute'), findsOneWidget);
    });

    testWidgets('dateless event row no longer duplicates the type label as '
        'its subtitle', (tester) async {
      // _testEvent has no start/end date, so pre-#807 the row printed the
      // type label twice (mono chip + subtitle fallback).
      await tester.pumpWidget(
        wrapWithRoutes(
          events: [_testEvent],
          balancesAsync: AsyncValue.data(_balancesWithExpenses),
        ),
      );
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final label = _testEvent.type.localizedShortLabel(l10n);
      await tester.ensureVisible(find.text('Beach Trip'));
      await tester.pumpAndSettle();

      expect(find.text(label), findsOneWidget);
    });
  });
}
