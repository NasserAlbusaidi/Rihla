import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #1166 — the FAB-lane clearance (#1078) was reserved as an OUTER `Padding`
/// wrapping the whole scroll viewport, shrinking it by `kHomeFabLaneClearance`
/// (88px) at the bottom. A `Viewport` clips its children to its own bounds,
/// so that 88px band was a permanent clip line 88px above the true screen
/// edge — invisible at rest (`bottomNavBackground == scaffoldBackground`) but
/// reading as an opaque bar occluding content while scrolling, and making the
/// FAB look attached to the bottom nav instead of floating.
///
/// The fix moves the clearance onto a TRAILING in-scroll spacer sliver so the
/// viewport itself reaches the true bottom edge (content clips only at the
/// real screen edge, never 88px short of it) while preserving the #1078
/// guarantee: once scrolled fully into view, the last group row still clears
/// the FAB.
void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  List<Group> makeGroups() => List.generate(
    6,
    (i) => Group(
      id: 'g$i',
      name: 'Group $i',
      inviteCode: 'ABC12$i',
      createdBy: 'user1',
      memberIds: const ['uid0', 'uid1'],
      currency: 'OMR',
      createdAt: DateTime(2026, 1, 1),
    ),
  );

  Future<void> pumpDashboard(WidgetTester tester) async {
    // iPhone-16-Pro-like logical size — matches the #1078 test's device.
    await tester.binding.setSurfaceSize(const Size(402, 874));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = GoRouter(
      initialLocation: '/home',
      routes: [GoRoute(path: '/home', builder: (_, _) => const HomeScreen())],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          linkedEmailProvider.overrideWithValue('secured@example.com'),
          isDurableUserProvider.overrideWithValue(true),
          userGroupsProvider.overrideWith((ref) => Stream.value(makeGroups())),
          crossGroupHomeBalanceProvider.overrideWith(
            (ref) => const AsyncValue.data((
              balance: (
                byCurrency: <CurrencyBalance>[],
                groupCount: 6,
                isLoading: false,
              ),
              partial: false,
            )),
          ),
          crossGroupActivityProvider.overrideWith(
            (ref) => const AsyncValue.data([]),
          ),
          homeGroupBalanceProvider.overrideWith(
            (ref, gid) => const AsyncValue.data((
              userNet: <String, Decimal>{},
              userPerEventNet: <String, Map<String, Decimal>>{},
              eventCount: 1,
              partial: false,
              fromAggregate: false,
            )),
          ),
          groupEventsProvider.overrideWith((ref, gid) => Stream.value([])),
          currentUserIdProvider.overrideWithValue('uid0'),
        ],
        child: MaterialApp.router(
          theme: AppTheme.lightTheme,
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    // Bounded pumps only: ConnectivityNotifier owns a periodic timer — never
    // pumpAndSettle here.
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets(
    'dashboard scroll viewport reaches the true screen edge, not a FAB-lane '
    'clip line 88px short of it',
    (tester) async {
      await pumpDashboard(tester);

      final viewportRect = tester.getRect(find.byType(CustomScrollView));
      final navBarRect = tester.getRect(find.byType(NavigationBar));

      // The Scaffold already reserves body space above the bottom nav bar —
      // the scroll viewport's true bottom edge is the nav bar's top edge. An
      // outer Padding(bottom: kHomeFabLaneClearance) shrinks the viewport by
      // 88px short of that, which is the reported clip line (#1166).
      expect(
        viewportRect.bottom,
        closeTo(navBarRect.top, 0.5),
        reason:
            'dashboard CustomScrollView must extend to the true screen edge '
            '(navBarRect.top=${navBarRect.top}) — got '
            '${viewportRect.bottom}, i.e. clipped '
            '${navBarRect.top - viewportRect.bottom}px short of it by an '
            'outer FAB-lane Padding',
      );
    },
  );

  testWidgets(
    '#1078 preserved: after scrolling to the end, the last group row clears '
    'the FAB',
    (tester) async {
      await pumpDashboard(tester);

      final fabRect = tester.getRect(find.byKey(HomeKeys.addExpenseFab));

      // Small drag steps: a paginated/estimated-height list's maxScrollExtent
      // can shrink as off-screen rows are disposed/re-estimated.
      for (var i = 0; i < 20; i++) {
        await tester.drag(
          find.byType(CustomScrollView),
          const Offset(0, -300),
        );
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 600));

      final lastRowFinder = find
          .ancestor(
            of: find.text('Group 5', skipOffstage: false),
            matching: find.byType(InkWell, skipOffstage: false),
          )
          .first;
      final lastRowRect = tester.getRect(lastRowFinder);

      expect(
        lastRowRect.overlaps(fabRect),
        isFalse,
        reason:
            'last group row $lastRowRect must clear the FAB $fabRect once '
            'scrolled fully into view (the #1078 guarantee)',
      );
    },
  );
}
