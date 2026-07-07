import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/auth/providers/auth_provider.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/home/keys/home_keys.dart';
import 'package:safar/features/home/providers/dashboard_providers.dart';
import 'package:safar/features/home/screens/home_screen.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/settings/keys/profile_keys.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:safar/l10n/generated/app_localizations_en.dart';

// ---------------------------------------------------------------------------
// #818 Wave 4 PR A — home first-run identity polish:
//  4.1 set-name chip beside the "?" avatar (deviceName empty)
//  4.2 "Been here before?" caption above the empty-state restore CTAs
//  4.3 persistent one-line guest-account caption under the greeting strip
// ---------------------------------------------------------------------------

Group _makeGroup(String id, String name, {int memberCount = 2}) => Group(
  id: id,
  name: name,
  inviteCode: 'ABC123',
  createdBy: 'user1',
  memberIds: List.generate(memberCount, (i) => 'uid$i'),
  currency: 'OMR',
  createdAt: DateTime(2026, 1, 1),
);

List<Override> _loadedOverrides() => [
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
];

List<Override> _emptyOverrides() => [
  userGroupsProvider.overrideWith((ref) => Stream.value([])),
  crossGroupHomeBalanceProvider.overrideWith(
    (ref) => const AsyncValue.data((
      balance: (
        byCurrency: <CurrencyBalance>[],
        groupCount: 0,
        isLoading: false,
      ),
      partial: false,
    )),
  ),
  crossGroupActivityProvider.overrideWith((ref) => const AsyncValue.data([])),
  groupBalancesProvider.overrideWith(
    (ref, groupId) => const AsyncValue.loading(),
  ),
  groupEventsProvider.overrideWith((ref, groupId) => Stream.value([])),
  currentUserIdProvider.overrideWithValue('test-user-id'),
];

Widget _buildTestApp({
  required List<Override> overrides,
  required SharedPreferences prefs,
  bool isDurable = true,
}) {
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/home', builder: (ctx, state) => const HomeScreen()),
      GoRoute(
        path: '/create-group',
        builder: (ctx, state) =>
            const Scaffold(body: Text('CreateGroupScreen')),
      ),
      GoRoute(
        path: '/join-group',
        builder: (ctx, state) => const Scaffold(body: Text('JoinGroupScreen')),
      ),
      GoRoute(
        path: '/profile',
        builder: (ctx, state) => const Scaffold(body: Text('ProfileScreen')),
      ),
      GoRoute(
        path: '/activity',
        builder: (ctx, state) => const Scaffold(body: Text('ActivityScreen')),
      ),
      GoRoute(
        path: '/recover',
        builder: (ctx, state) => const Scaffold(body: Text('RecoverScreenStub')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      linkedEmailProvider.overrideWithValue('secured@example.com'),
      isDurableUserProvider.overrideWithValue(isDurable),
      // #104/#466: home reads the once-balance variants directly.
      groupBalancesOnceProvider.overrideWith(
        (ref, gid) => ref.watch(groupBalancesProvider(gid)).maybeWhen(
              data: (d) => (balances: d, failedEventIds: const <String>{}, groupSettlementsFailed: false),
              orElse: () => Completer<GroupBalancesOnce>().future,
            ),
      ),
      ...overrides,
    ],
    child: MaterialApp.router(
      theme: AppTheme.lightTheme,
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  group('4.1 — set-name chip', () {
    testWidgets('visible when deviceName is empty', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(overrides: _loadedOverrides(), prefs: prefs),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(HomeKeys.setNameChip), findsOneWidget);
      // #1010: the label is the shortened copy that fits left of the centred
      // wordmark at 402pt without ellipsis.
      expect(find.text('Set name'), findsOneWidget);
    });

    testWidgets('absent once a name is set', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(overrides: _loadedOverrides(), prefs: prefs),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(HomeKeys.setNameChip), findsOneWidget);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(HomeScreen)),
      );
      await container.read(settingsProvider.notifier).setDeviceName('Nasser');
      await tester.pumpAndSettle();

      expect(find.byKey(HomeKeys.setNameChip), findsNothing);
    });

    testWidgets('tap opens the edit-name sheet', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(overrides: _loadedOverrides(), prefs: prefs),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(HomeKeys.setNameChip));
      await tester.pumpAndSettle();

      expect(find.byKey(ProfileKeys.nameTextField), findsOneWidget);
    });
  });

  group('4.2 — restore-section caption', () {
    testWidgets('renders above the restore CTAs in the empty state', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTestApp(overrides: _emptyOverrides(), prefs: prefs),
      );
      await tester.pumpAndSettle();

      final l10n = AppLocalizationsEn();
      expect(
        find.text(l10n.homeRestoreSectionCaption.toUpperCase()),
        findsOneWidget,
      );
    });
  });

  group('4.3 — guest-account caption', () {
    testWidgets('visible for an anonymous user', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          overrides: _loadedOverrides(),
          prefs: prefs,
          isDurable: false,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(HomeKeys.guestAccountCaption), findsOneWidget);
    });

    testWidgets('absent for a durable user', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          overrides: _loadedOverrides(),
          prefs: prefs,
          isDurable: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(HomeKeys.guestAccountCaption), findsNothing);
    });
  });
}
