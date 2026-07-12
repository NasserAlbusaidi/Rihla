import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/groups/models/group_activity_log_model.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/home/providers/activity_unread_provider.dart';
import 'package:safar/features/home/providers/dashboard_providers.dart';
import 'package:safar/features/home/widgets/bottom_nav_shell.dart';
import 'package:safar/features/home/keys/home_keys.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

CrossGroupActivityEntry _entry(String id, DateTime at) => (
  log: GroupActivityLog(
    id: id,
    type: 'expense_added',
    actorId: 'u',
    actorName: 'A',
    description: 'd',
    timestamp: at,
  ),
  groupName: 'Trip A',
  groupId: 'g1',
  currency: 'OMR',
);

Future<ProviderContainer> _container({
  required List<CrossGroupActivityEntry> entries,
  String? lastSeenIso,
}) async {
  SharedPreferences.setMockInitialValues(
    lastSeenIso == null ? {} : {'activityLastSeenIso': lastSeenIso},
  );
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      crossGroupActivityProvider.overrideWith((ref) => AsyncValue.data(entries)),
    ],
  );
}

void main() {
  group('activityUnreadProvider', () {
    test('empty feed is never unread', () async {
      final c = await _container(entries: []);
      addTearDown(c.dispose);
      expect(c.read(activityUnreadProvider), isFalse);
    });

    test('non-empty feed with no last-seen is unread', () async {
      final c = await _container(entries: [_entry('a', DateTime.utc(2026, 3, 1))]);
      addTearDown(c.dispose);
      expect(c.read(activityUnreadProvider), isTrue);
    });

    test('unread when the newest entry is after last-seen', () async {
      final c = await _container(
        entries: [_entry('a', DateTime.utc(2026, 3, 2))],
        lastSeenIso: DateTime.utc(2026, 3, 1).toIso8601String(),
      );
      addTearDown(c.dispose);
      expect(c.read(activityUnreadProvider), isTrue);
    });

    test('read when the newest entry is at/before last-seen', () async {
      final c = await _container(
        entries: [_entry('a', DateTime.utc(2026, 3, 1))],
        lastSeenIso: DateTime.utc(2026, 3, 2).toIso8601String(),
      );
      addTearDown(c.dispose);
      expect(c.read(activityUnreadProvider), isFalse);
    });

    test('markSeenNow clears unread', () async {
      final c = await _container(entries: [_entry('a', DateTime.utc(2026, 3, 1))]);
      addTearDown(c.dispose);
      expect(c.read(activityUnreadProvider), isTrue);
      await c.read(activitySeenProvider.notifier).markSeenNow();
      expect(c.read(activityUnreadProvider), isFalse);
    });
  });

  group('BottomNavShell unread dot', () {
    testWidgets('shows a dot on the Activity destination when unread, clears '
        'after selecting the tab', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      // #1188: BottomNavShell now mounts a BackButtonListener, which requires a
      // Router ancestor — mount via MaterialApp.router (was classic
      // MaterialApp(home:)). Migration only; every assertion below is unchanged.
      final router = GoRouter(
        initialLocation: '/home',
        routes: [
          GoRoute(
            path: '/home',
            builder: (_, _) => const BottomNavShell(child: Text('Groups tab')),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            // Empty groups hides the add-expense FAB, so the shell builds
            // without pulling in the FAB's Firestore-backed providers.
            userGroupsProvider.overrideWith((ref) => Stream.value(const [])),
            crossGroupActivityProvider.overrideWith(
              (ref) => AsyncValue.data([_entry('a', DateTime.utc(2026, 3, 1))]),
            ),
          ],
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: router,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );
      await tester.pump();

      final badge = tester.widget<Badge>(
        find.byKey(HomeKeys.activityUnreadBadge),
      );
      expect(badge.isLabelVisible, isTrue);

      // Selecting Activity marks it seen. Return to Groups so the Activity
      // destination shows its inactive (badge-wrapped) icon again — the
      // selected destination renders selectedIcon, which has no badge.
      // pumpAndSettle drains the Activity tab's EmptyStateView entrance ticker.
      await tester.tap(find.byKey(HomeKeys.bottomNavActivity));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(HomeKeys.bottomNavGroups));
      await tester.pumpAndSettle();

      final cleared = tester.widget<Badge>(
        find.byKey(HomeKeys.activityUnreadBadge),
      );
      expect(cleared.isLabelVisible, isFalse);
    });

    testWidgets(
      '#818 Wave 5.2: BottomNavTabScope.selectTab(1) clears the dot '
      'exactly like a direct nav-bar tap',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();

        // #1188: BackButtonListener needs a Router ancestor — mount via
        // MaterialApp.router (was classic MaterialApp(home:)). Migration only;
        // every assertion below is unchanged.
        final router = GoRouter(
          initialLocation: '/home',
          routes: [
            GoRoute(
              path: '/home',
              builder: (_, _) => BottomNavShell(
                child: Builder(
                  builder: (context) => TextButton(
                    onPressed: () =>
                        BottomNavTabScope.maybeOf(context)?.selectTab(1),
                    child: const Text('select tab 1'),
                  ),
                ),
              ),
            ),
          ],
        );
        addTearDown(router.dispose);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              userGroupsProvider.overrideWith(
                (ref) => Stream.value(const []),
              ),
              crossGroupActivityProvider.overrideWith(
                (ref) =>
                    AsyncValue.data([_entry('a', DateTime.utc(2026, 3, 1))]),
              ),
            ],
            child: MaterialApp.router(
              theme: AppTheme.lightTheme,
              routerConfig: router,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
            ),
          ),
        );
        await tester.pump();

        final badge = tester.widget<Badge>(
          find.byKey(HomeKeys.activityUnreadBadge),
        );
        expect(badge.isLabelVisible, isTrue);

        await tester.tap(find.text('select tab 1'));
        // Drains the Activity tab's EmptyStateView entrance ticker.
        await tester.pumpAndSettle();

        final navBar = tester.widget<NavigationBar>(
          find.byType(NavigationBar),
        );
        expect(navBar.selectedIndex, 1);

        // Return to Groups so the Activity destination shows its inactive
        // (badge-wrapped) icon again before reading isLabelVisible.
        await tester.tap(find.byKey(HomeKeys.bottomNavGroups));
        await tester.pumpAndSettle();

        final cleared = tester.widget<Badge>(
          find.byKey(HomeKeys.activityUnreadBadge),
        );
        expect(cleared.isLabelVisible, isFalse);
      },
    );
  });
}
