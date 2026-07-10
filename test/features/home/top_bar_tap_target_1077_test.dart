import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/auth/providers/auth_provider.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/home/providers/activity_unread_provider.dart';
import 'package:safar/features/home/keys/home_keys.dart';
import 'package:safar/features/home/providers/dashboard_providers.dart';
import 'package:safar/features/home/screens/home_screen.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:safar/shared/widgets/r_avatar.dart';

// ---------------------------------------------------------------------------
// #1077 — home top-bar tap targets. The search/activity _IconCircles were
// hardcoded 40×40 and the profile avatar was a bare 36×36 GestureDetector,
// all under the DESIGN.md §4 44dp floor; the avatar also lacked a button
// role. The visuals stay compact (20px glyphs, 36px avatar) — only the hit
// regions grow. The home "New group" SectionHeader action pins the shared
// section_header.dart fix at a live call site.
// ---------------------------------------------------------------------------

Group _makeGroup(String id, String name) => Group(
  id: id,
  name: name,
  inviteCode: 'ABC123',
  createdBy: 'user1',
  memberIds: const ['uid0', 'uid1'],
  currency: 'OMR',
  createdAt: DateTime(2026, 1, 1),
);

List<Override> _overrides() => [
  userGroupsProvider.overrideWith(
    (ref) => Stream.value([_makeGroup('g1', 'Desert Crew')]),
  ),
  crossGroupHomeBalanceProvider.overrideWith(
    (ref) => const AsyncValue.data((
      balance: (
        byCurrency: <CurrencyBalance>[],
        groupCount: 1,
        isLoading: false,
      ),
      partial: false,
    )),
  ),
  crossGroupActivityProvider.overrideWith((ref) => const AsyncValue.data([])),
  groupBalancesProvider.overrideWith(
    (ref, groupId) => const AsyncValue.data((
      balances: <String, List<UserBalance>>{},
      totalSpent: <String, Decimal>{},
      eventCount: 0,
      perEventBreakdown: <String, Map<String, Map<String, Decimal>>>{},
      memberNames: <String, String>{},
      memberRawNames: <String, String>{},
    )),
  ),
  groupEventsProvider.overrideWith((ref, groupId) => Stream.value([])),
  currentUserIdProvider.overrideWithValue('test-user-id'),
  activityUnreadProvider.overrideWithValue(false),
];

Future<void> _pumpHome(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({
    'settings_device_name': 'Nasser',
  });
  final prefs = await SharedPreferences.getInstance();

  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/home', builder: (ctx, state) => const HomeScreen()),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        linkedEmailProvider.overrideWithValue('secured@example.com'),
        isDurableUserProvider.overrideWithValue(true),
        ..._overrides(),
      ],
      child: MaterialApp.router(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  const size = Size(402, 874);

  Future<void> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpHome(tester);
  }

  testWidgets('search and activity _IconCircles meet the 44dp floor with '
      '20px glyphs', (tester) async {
    await pump(tester);

    for (final key in [HomeKeys.searchButton, HomeKeys.activityBell]) {
      final box = tester.getSize(find.byKey(key));
      expect(
        box.width,
        greaterThanOrEqualTo(44),
        reason: '$key width ${box.width}',
      );
      expect(
        box.height,
        greaterThanOrEqualTo(44),
        reason: '$key height ${box.height}',
      );
    }

    final glyph = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(HomeKeys.searchButton),
        matching: find.byIcon(Iconsax.search_normal),
      ),
    );
    expect(glyph.size, 20);
  });

  testWidgets('profile avatar gets a 44dp hit box around the 36px visual', (
    tester,
  ) async {
    await pump(tester);

    final hitBox = tester.getSize(find.byKey(HomeKeys.profileAvatar));
    expect(hitBox.width, greaterThanOrEqualTo(44));
    expect(hitBox.height, greaterThanOrEqualTo(44));

    final avatar = tester.getSize(
      find.descendant(
        of: find.byKey(HomeKeys.profileAvatar),
        matching: find.byType(RAvatar),
      ),
    );
    expect(avatar, const Size(36, 36));
  });

  testWidgets('profile avatar exposes a button role', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester);

    final node = tester.getSemantics(find.byKey(HomeKeys.profileAvatar));
    expect(node.flagsCollection.isButton, isTrue);
    handle.dispose();
  });

  testWidgets('home "New group" header action meets the 44dp floor (#1077 '
      'SectionHeader call site)', (tester) async {
    await pump(tester);

    final action = tester.getSize(find.byKey(HomeKeys.createGroupFab));
    expect(action.height, greaterThanOrEqualTo(44));
  });
}
