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
import 'package:safar/features/home/providers/dashboard_providers.dart';
import 'package:safar/features/home/screens/home_screen.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:safar/shared/widgets/wordmark_logo.dart';

// ---------------------------------------------------------------------------
// #991 — the top-bar "Rihla" wordmark must sit on the bar's true geometric
// centre regardless of the asymmetric flanking clusters (avatar + optional
// set-name chip on the start side vs search + bell on the end side), in BOTH
// text directions. The old Row-with-Spacers layout centred it in the
// *leftover* space, so the wider cluster pushed it off-centre — measured at
// ~14 logical px right in LTR with the set-name chip visible (simulator
// screenshot, 2026-07-06).
//
// Tolerance is ±3 logical px: the bar's own padding is deliberately
// asymmetric (EdgeInsetsDirectional.fromSTEB(20, 6, 16, 0)), which biases the
// padded-area centre by 2px — invisible, accepted. The Falaj-fork flourish is
// start-aligned under the word by design (WordmarkLogo crossAxisAlignment:
// start — the signature mark), so only the composite widget's centre is
// asserted, not the flourish's.
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
];

Future<void> _pumpHome(
  WidgetTester tester, {
  required String deviceName,
  required Locale locale,
}) async {
  SharedPreferences.setMockInitialValues({
    if (deviceName.isNotEmpty) 'settings_device_name': deviceName,
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
  const size = Size(402, 874); // iPhone 17 Pro logical points
  const tolerance = 3.0;

  Future<void> expectCentered(
    WidgetTester tester, {
    required String deviceName,
    required Locale locale,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpHome(tester, deviceName: deviceName, locale: locale);

    final wordmark = find.byType(WordmarkLogo);
    expect(wordmark, findsOneWidget);
    final dx = tester.getCenter(wordmark).dx;
    expect(
      (dx - size.width / 2).abs(),
      lessThanOrEqualTo(tolerance),
      reason:
          'wordmark centre $dx vs screen centre ${size.width / 2} '
          '(locale=$locale, deviceName="$deviceName") — the flanking '
          'clusters must not push the mark off the geometric centre (#991)',
    );
  }

  testWidgets('LTR, set-name chip visible (empty deviceName)', (tester) async {
    await expectCentered(tester, deviceName: '', locale: const Locale('en'));
  });

  testWidgets('LTR, name set (no chip)', (tester) async {
    await expectCentered(
      tester,
      deviceName: 'Nasser',
      locale: const Locale('en'),
    );
  });

  testWidgets('RTL, set-name chip visible (empty deviceName)', (tester) async {
    await expectCentered(tester, deviceName: '', locale: const Locale('ar'));
  });

  testWidgets('RTL, name set (no chip)', (tester) async {
    await expectCentered(
      tester,
      deviceName: 'ناصر',
      locale: const Locale('ar'),
    );
  });
}
