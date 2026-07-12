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
import 'package:safar/shared/widgets/r_amount.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #1078 — the shell's add-expense FAB occluded the last group row's trailing
/// balance/status at the REST scroll position (evidence: FAB [330,696][386,752]
/// vs row [20,706][382,768] at ordinary scale). The original fix reserved a
/// fixed action lane BELOW the scroll viewport (an outer `Padding` shrinking
/// the `Viewport` itself) so the FAB floated entirely outside the list.
///
/// #1166 replaced that outer Padding with a trailing in-scroll spacer: the
/// outer-Padding shape made the reserved lane a permanent CLIP line 88px
/// above the true screen edge — invisible at rest (`bottomNavBackground ==
/// scaffoldBackground`) but reading as an opaque bar swallowing content while
/// scrolling. See `home_fab_lane_clipping_1166_test.dart` for that
/// regression's own coverage.
///
/// This file now pins what #1166 DELIBERATELY preserves vs DELIBERATELY
/// trades away from the original #1078 guarantee:
///  - PRESERVED: once scrolled fully into view, the last group row's trailing
///    balance still clears the FAB (a trailing spacer sliver — sized to
///    [kHomeFabLaneClearance] — guarantees this: at max scroll extent the row
///    sits exactly that far above the true bottom edge).
///  - TRADED AWAY: the old "FAB can never geometrically overlap the scroll
///    viewport" invariant, and the at-rest occlusion guard for a list
///    SHORTER than the viewport — a trailing spacer cannot move a row pinned
///    by the content above it (the reason #1078 didn't use one), so a short
///    list may still rest with its last row under the FAB. This is ordinary
///    floating-FAB-over-content behaviour, not the #1166 occluding-shelf bug
///    (which corrupted SCROLLING, not just resting, content) — and #1166's
///    proposed fix explicitly accepted this trade-off.
void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  // #1166: multiple groups (not #1078's original single group) so the list
  // is genuinely taller than the viewport at every scale/locale combo below —
  // otherwise "scroll to the end" would be a no-op and the preserved
  // clear-the-FAB guarantee would go untested.
  List<Group> makeGroups() => List.generate(
    5,
    (i) => Group(
      id: 'g$i',
      name: 'QA Smoke Group $i',
      inviteCode: 'ABC12$i',
      createdBy: 'user1',
      memberIds: const ['uid0', 'uid1'],
      currency: 'OMR',
      createdAt: DateTime(2026, 1, 1),
    ),
  );

  Future<void> pumpDashboard(
    WidgetTester tester, {
    required double scale,
    required Locale locale,
  }) async {
    // iPhone-16-Pro-like logical size — matches the audit evidence device.
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
          userGroupsProvider.overrideWith(
            (ref) => Stream.value(makeGroups()),
          ),
          crossGroupHomeBalanceProvider.overrideWith(
            (ref) => const AsyncValue.data((
              balance: (
                byCurrency: <CurrencyBalance>[],
                groupCount: 5,
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
          locale: locale,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    // Bounded pumps only: ConnectivityNotifier owns a periodic timer.
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
  }

  /// The part of [rect] actually visible inside [viewport] (Rect.intersect
  /// returns a negative-size rect when disjoint — normalize to null).
  Rect? visiblePart(Rect rect, Rect viewport) {
    final clipped = rect.intersect(viewport);
    return (clipped.width <= 0 || clipped.height <= 0) ? null : clipped;
  }

  /// The #1078 guarantee #1166 preserves: once the dashboard is scrolled all
  /// the way to its end, the last group row's trailing balance must be fully
  /// visible and clear of the FAB — at every scale and text direction.
  Future<void> expectScrollClearance(
    WidgetTester tester, {
    required double scale,
    required Locale locale,
  }) async {
    await pumpDashboard(tester, scale: scale, locale: locale);

    final fabRect = tester.getRect(find.byKey(HomeKeys.addExpenseFab));
    final viewportRect = tester.getRect(find.byType(CustomScrollView));

    Rect trailingRect() {
      final row = find
          .ancestor(
            of: find.text('QA Smoke Group 4', skipOffstage: false),
            matching: find.byType(InkWell, skipOffstage: false),
          )
          .first;
      return tester.getRect(
        find
            .descendant(
              of: row,
              matching: find.byType(RAmount, skipOffstage: false),
            )
            .first,
      );
    }

    // Small drag steps: a paginated/estimated-height list's maxScrollExtent
    // can shrink as off-screen rows are disposed/re-estimated.
    for (var i = 0; i < 20; i++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 600));

    final settledTrailing = visiblePart(trailingRect(), viewportRect);
    expect(
      settledTrailing,
      isNotNull,
      reason:
          'last group row trailing must be reachable by scrolling '
          '(scale=$scale, locale=$locale)',
    );
    expect(
      settledTrailing!.overlaps(fabRect),
      isFalse,
      reason:
          'last group row trailing $settledTrailing must clear the FAB '
          '$fabRect at full scroll (scale=$scale, locale=$locale)',
    );
  }

  testWidgets(
    '1.0x LTR: last group row clears the FAB once scrolled fully into view',
    (tester) async {
      await expectScrollClearance(
        tester,
        scale: 1.0,
        locale: const Locale('en'),
      );
    },
  );

  testWidgets(
    '1.5x LTR: last group row clears the FAB once scrolled fully into view',
    (tester) async {
      await expectScrollClearance(
        tester,
        scale: 1.5,
        locale: const Locale('en'),
      );
    },
  );

  testWidgets(
    '1.0x RTL: last group row clears the FAB once scrolled fully into view',
    (tester) async {
      await expectScrollClearance(
        tester,
        scale: 1.0,
        locale: const Locale('ar'),
      );
    },
  );

  testWidgets(
    '1.5x RTL: last group row clears the FAB once scrolled fully into view',
    (tester) async {
      await expectScrollClearance(
        tester,
        scale: 1.5,
        locale: const Locale('ar'),
      );
    },
  );
}
