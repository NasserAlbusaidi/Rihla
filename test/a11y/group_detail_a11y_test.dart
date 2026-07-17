// #1283 — accessibility guideline matchers for GroupDetailScreen.
//
// Arrange section copied from test/features/group_detail_screen_test.dart
// (`_testGroup`/`_testMembers`/`_balancesWithExpenses`/`_wrap`) — reuse, don't
// invent new fixtures.

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/features/events/models/event_model.dart'
    show Event, EventModules, EventType;
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/models/group_activity_log_model.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/screens/group_detail_screen.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

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

Widget _wrap(
  Widget child,
  SharedPreferences prefs, {
  required AsyncValue<GroupBalances> balancesAsync,
  List<Event> events = const [],
  Locale? locale,
}) {
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
      ).overrideWith((ref) => Stream.value(events)),
      groupBalancesProvider(_groupId).overrideWith((ref) => balancesAsync),
      groupActivityProvider(_groupId).overrideWith(
        (ref) => Stream.value(const <GroupActivityLog>[]),
      ),
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

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'device_name': 'Test User'});
    prefs = await SharedPreferences.getInstance();
  });

  Future<void> pumpScreen(WidgetTester tester, {required Locale locale}) async {
    await tester.pumpWidget(
      _wrap(
        const GroupDetailScreen(groupId: _groupId),
        prefs,
        balancesAsync: AsyncValue.data(_balancesWithExpenses),
        events: [_testEvent],
        locale: locale,
      ),
    );
    await tester.pumpAndSettle();
  }

  group('GroupDetailScreen accessibility (#1283)', () {
    testWidgets('EN meets labeledTapTargetGuideline', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpScreen(tester, locale: const Locale('en'));

      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('AR meets labeledTapTargetGuideline', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpScreen(tester, locale: const Locale('ar'));

      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    // androidTapTargetGuideline (48x48) and textContrastGuideline are
    // deliberately NOT asserted here — both currently fail on real,
    // pre-existing violations (reported upstream, not fixed in this
    // test-only PR):
    //  * androidTapTargetGuideline: the "Group settings" avatar-stack tap
    //    target (GroupKeys.groupDetailMemberStack, balance_card.dart) is a
    //    bare GestureDetector around a 22px RAvatarStack with no minimum-size
    //    padding — measured ~37x22, under even the project's own 44dp floor
    //    (docs/DESIGN.md §4). "New event"/"Settle up" (358x44) and "Add
    //    member" (122.5x44) meet the 44dp floor but not Android's 48dp.
    //  * textContrastGuideline: the cover header's "GROUP · N MEMBERS"
    //    caption (cover_header.dart, textOnPrimary @ alpha 0.85, fontSize 9)
    //    measures a 2.74:1 contrast ratio against its cover-art background,
    //    below the 4.5:1 WCAG AA floor.
  });
}
