import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/keys/group_keys.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/screens/group_detail_screen.dart';
import 'package:safar/features/groups/screens/group_settings_screen.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Stub group used across tests.
final _testGroup = Group(
  id: 'group-1',
  name: 'Adventure Crew',
  inviteCode: 'ABC123',
  createdBy: 'uid-creator',
  memberIds: const ['uid-creator', 'uid-member'],
  currency: 'OMR',
  createdAt: DateTime(2026, 1, 1),
);

/// Stub member list — two members.
final _testMembers = [
  GroupMember(
    id: 'mem-1',
    groupId: 'group-1',
    userId: 'uid-creator',
    displayName: 'Alice',
    role: 'CREATOR',
    joinedAt: DateTime(2026, 1, 1),
  ),
  GroupMember(
    id: 'mem-2',
    groupId: 'group-1',
    userId: 'uid-member',
    displayName: 'Bob',
    role: 'MEMBER',
    joinedAt: DateTime(2026, 1, 2),
  ),
];

/// Balances stub with non-zero balance — Alice is owed money by Bob.
///
/// Used for the balance toggle and settle-up navigation tests.
/// totalSpent > 0 so the balance hero is rendered (D-19).
final _membersWithBalances = (
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
    'uid-creator': {
      'evt-1': {'OMR': Decimal.parse('15.000')},
    },
    'uid-member': {
      'evt-1': {'OMR': Decimal.parse('-15.000')},
    },
  },
  memberNames: <String, String>{'uid-creator': 'Alice', 'uid-member': 'Bob'},
  memberRawNames: <String, String>{},
);

/// Balances stub with two zero-balance members (no expenses yet).
///
/// groupBalancesProvider now drives the Members & Balances section.
/// Even with no expenses, we supply the two members with zero balances
/// so the members & balances section renders both names.
final _membersWithZeroBalance = (
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

/// Wraps a widget in ProviderScope + MaterialApp with shared test overrides.
///
/// Also overrides [groupEventsProvider] so GroupDetailScreen does not attempt
/// to open a real Firestore stream.
/// Overrides [groupBalancesProvider], [groupActivityProvider], and
/// [currentUserIdProvider] for the Phase 20 redesigned GroupDetailScreen.
Widget _wrap(Widget child, SharedPreferences prefs) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      currentUserIdProvider.overrideWithValue('uid-creator'),
      groupDetailProvider(
        'group-1',
      ).overrideWith((ref) => Stream.value(_testGroup)),
      groupMembersProvider(
        'group-1',
      ).overrideWith((ref) => Stream.value(_testMembers)),
      groupEventsProvider(
        'group-1',
      ).overrideWith((ref) => Stream.value(const [])),
      groupBalancesProvider(
        'group-1',
      ).overrideWith((ref) => AsyncValue.data(_membersWithZeroBalance)),
      groupActivityProvider(
        'group-1',
      ).overrideWith((ref) => Stream.value(const [])),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  );
}

/// Wraps GroupDetailScreen with non-zero balance data so stats grid
/// and settle-up features are rendered (Phase 20 redesign).
Widget _wrapWithBalances(Widget child, SharedPreferences prefs) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      currentUserIdProvider.overrideWithValue('uid-creator'),
      groupDetailProvider(
        'group-1',
      ).overrideWith((ref) => Stream.value(_testGroup)),
      groupMembersProvider(
        'group-1',
      ).overrideWith((ref) => Stream.value(_testMembers)),
      groupEventsProvider(
        'group-1',
      ).overrideWith((ref) => Stream.value(const [])),
      groupBalancesProvider(
        'group-1',
      ).overrideWith((ref) => AsyncValue.data(_membersWithBalances)),
      groupActivityProvider(
        'group-1',
      ).overrideWith((ref) => Stream.value(const [])),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
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

  group('Group screens', () {
    // -----------------------------------------------------------------------
    // GroupDetailScreen
    // -----------------------------------------------------------------------
    group('GroupDetailScreen', () {
      testWidgets('shows group name in header', (tester) async {
        await tester.pumpWidget(
          _wrap(const GroupDetailScreen(groupId: 'group-1'), prefs),
        );
        await tester.pumpAndSettle();

        // ModuleHeader renders group.name as the large title text
        expect(find.text('Adventure Crew'), findsWidgets);
      });

      testWidgets('shows active members count in cover header', (tester) async {
        await tester.pumpWidget(
          _wrap(const GroupDetailScreen(groupId: 'group-1'), prefs),
        );
        await tester.pumpAndSettle();

        expect(find.text('GROUP · 2 MEMBERS'), findsOneWidget);
      });

      testWidgets(
        'invite code section is not rendered (D-05 — moved to Phase 29)',
        (tester) async {
          await tester.pumpWidget(
            _wrap(const GroupDetailScreen(groupId: 'group-1'), prefs),
          );
          await tester.pumpAndSettle();

          // Invite code section removed from GroupDetailScreen per D-05
          expect(find.byKey(GroupKeys.inviteCodeSection), findsNothing);
        },
      );

      testWidgets(
        'shows members section with member names from groupMembersProvider',
        (tester) async {
          await tester.pumpWidget(
            _wrap(const GroupDetailScreen(groupId: 'group-1'), prefs),
          );
          await tester.pumpAndSettle();

          await _scrollUntilVisible(
            tester,
            find.byKey(GroupKeys.membersAndBalancesSection),
          );

          expect(
            find.byKey(GroupKeys.membersAndBalancesSection),
            findsOneWidget,
          );
          expect(find.text('MEMBERS'), findsOneWidget);
          expect(find.text('Alice'), findsWidgets);
          expect(find.text('Bob'), findsOneWidget);
        },
      );

      testWidgets('shows "No events yet" empty state when no events exist', (
        tester,
      ) async {
        await tester.pumpWidget(
          _wrap(const GroupDetailScreen(groupId: 'group-1'), prefs),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(GroupKeys.noEventsEmpty), findsOneWidget);
      });

      testWidgets('shows Events section header', (tester) async {
        await tester.pumpWidget(
          _wrap(const GroupDetailScreen(groupId: 'group-1'), prefs),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(GroupKeys.eventsSection), findsOneWidget);
      });

      testWidgets(
        'members section shows signed balances when balances are non-zero',
        (tester) async {
          await tester.pumpWidget(
            _wrapWithBalances(
              const GroupDetailScreen(groupId: 'group-1'),
              prefs,
            ),
          );
          await tester.pumpAndSettle();

          await _scrollUntilVisible(
            tester,
            find.byKey(GroupKeys.membersAndBalancesSection),
          );

          expect(find.text('Alice'), findsWidgets);
          expect(find.text('Bob'), findsOneWidget);
          expect(_textContaining('15.000'), findsWidgets);
        },
      );

      testWidgets('members section shows rows for both zero-balance members', (
        tester,
      ) async {
        await tester.pumpWidget(
          _wrap(const GroupDetailScreen(groupId: 'group-1'), prefs),
        );
        await tester.pumpAndSettle();

        await _scrollUntilVisible(
          tester,
          find.byKey(GroupKeys.membersAndBalancesSection),
        );

        expect(find.text('Alice'), findsWidgets);
        expect(find.text('Bob'), findsOneWidget);
        expect(find.text('—'), findsWidgets);
      });

      testWidgets('balance card shows non-zero user balance', (tester) async {
        await tester.pumpWidget(
          _wrapWithBalances(const GroupDetailScreen(groupId: 'group-1'), prefs),
        );
        await tester.pumpAndSettle();

        expect(find.text('Your balance here'), findsOneWidget);
        expect(_textContaining('15.000'), findsWidgets);
        expect(find.text('they owe you'), findsOneWidget);
      });

      testWidgets('event creation actions are present without a FAB', (
        tester,
      ) async {
        await tester.pumpWidget(
          _wrap(const GroupDetailScreen(groupId: 'group-1'), prefs),
        );
        await tester.pumpAndSettle();

        expect(find.byType(FloatingActionButton), findsNothing);
        expect(find.text('New event'), findsWidgets);
        expect(find.text('Create Event'), findsOneWidget);
      });
    });

    // -----------------------------------------------------------------------
    // GroupSettingsScreen
    // -----------------------------------------------------------------------
    group('GroupSettingsScreen', () {
      testWidgets('shows back button instead of AppBar title', (tester) async {
        await tester.pumpWidget(
          _wrap(const GroupSettingsScreen(groupId: 'group-1'), prefs),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(GroupKeys.settingsBackButton), findsOneWidget);
      });

      testWidgets('shows group name tile with current name (D-15)', (
        tester,
      ) async {
        await tester.pumpWidget(
          _wrap(const GroupSettingsScreen(groupId: 'group-1'), prefs),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(GroupKeys.settingsGroupNameTile), findsOneWidget);
        expect(find.text('Adventure Crew'), findsOneWidget);
      });

      testWidgets('shows invite code tile with copy button', (tester) async {
        await tester.pumpWidget(
          _wrap(const GroupSettingsScreen(groupId: 'group-1'), prefs),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(GroupKeys.settingsInviteCodeTile), findsOneWidget);
        expect(find.text('ABC123'), findsWidgets);
      });
    });
  });
}
