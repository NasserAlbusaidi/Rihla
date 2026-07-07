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

// ---------------------------------------------------------------------------
// The top-bar search and activity buttons are identical 40×40 _IconCircles in
// one Row, so their glyphs must share a vertical centre-line. When the unread
// dot is visible, Material's Badge wraps its child in a Stack whose default
// alignment is topStart — inside the tight 40×40 box that pinned the activity
// glyph to the top-start corner, ~10px up-start of the (badge-less) search
// glyph. Observed on-device 2026-07-07.
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

List<Override> _overrides({required bool unread}) => [
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
  activityUnreadProvider.overrideWithValue(unread),
];

Future<void> _pumpHome(
  WidgetTester tester, {
  required bool unread,
  Locale locale = const Locale('en'),
}) async {
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
        ..._overrides(unread: unread),
      ],
      child: MaterialApp.router(
        theme: AppTheme.lightTheme,
        locale: locale,
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

  Future<void> expectAligned(
    WidgetTester tester, {
    required bool unread,
    Locale locale = const Locale('en'),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpHome(tester, unread: unread, locale: locale);

    // The bottom-nav History tab also renders Iconsax.activity — scope both
    // glyph lookups to their top-bar buttons.
    final search = tester.getCenter(
      find.descendant(
        of: find.byKey(HomeKeys.searchButton),
        matching: find.byIcon(Iconsax.search_normal),
      ),
    );
    final activity = tester.getCenter(
      find.descendant(
        of: find.byKey(HomeKeys.activityBell),
        matching: find.byIcon(Iconsax.activity),
      ),
    );
    expect(
      (search.dy - activity.dy).abs(),
      lessThanOrEqualTo(0.5),
      reason:
          'search glyph centre ${search.dy} vs activity glyph centre '
          '${activity.dy} (unread=$unread, locale=$locale) — the two '
          '_IconCircle glyphs must share the top-bar centre-line',
    );
  }

  testWidgets('glyphs aligned with unread dot hidden', (tester) async {
    await expectAligned(tester, unread: false);
  });

  testWidgets('glyphs aligned with unread dot visible', (tester) async {
    await expectAligned(tester, unread: true);
  });

  testWidgets('glyphs aligned with unread dot visible in RTL', (tester) async {
    await expectAligned(tester, unread: true, locale: const Locale('ar'));
  });
}
