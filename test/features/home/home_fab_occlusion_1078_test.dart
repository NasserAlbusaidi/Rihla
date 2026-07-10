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
/// vs row [20,706][382,768] at ordinary scale; reproduced here at 1.5x). A
/// trailing spacer can't protect a row pinned by the content above it, so the
/// dashboard reserves a fixed action lane below its scroll viewport instead:
/// the FAB floats entirely outside the list, and no row content can ever sit
/// under it, at any scroll offset, scale, or text direction.
void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  Group makeGroup() => Group(
    id: 'g1',
    name: 'QA Smoke Group',
    inviteCode: 'ABC123',
    createdBy: 'user1',
    memberIds: const ['uid0', 'uid1'],
    currency: 'OMR',
    createdAt: DateTime(2026, 1, 1),
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
            (ref) => Stream.value([makeGroup()]),
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

  Future<void> expectNoRestOcclusion(
    WidgetTester tester, {
    required double scale,
    required Locale locale,
  }) async {
    await pumpDashboard(tester, scale: scale, locale: locale);

    final fabRect = tester.getRect(find.byKey(HomeKeys.addExpenseFab));
    final viewportRect = tester.getRect(find.byType(CustomScrollView));

    // Offstage-inclusive: with the fix the row can sit below the shrunken
    // viewport at rest (clipped, not occluded) — visiblePart handles it.
    Rect trailingRect() {
      final row = find
          .ancestor(
            of: find.text('QA Smoke Group', skipOffstage: false),
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

    // The issue's literal shape: at rest, the visible part of the last group
    // row's trailing balance/status must not intersect the FAB footprint.
    final visibleTrailing = visiblePart(trailingRect(), viewportRect);
    if (visibleTrailing != null) {
      expect(
        visibleTrailing.overlaps(fabRect),
        isFalse,
        reason:
            'last group row trailing $visibleTrailing must not sit under the '
            'FAB $fabRect at rest (scale=$scale, locale=$locale)',
      );
    }

    // Lane contract: the FAB floats entirely below the list viewport, so it
    // cannot occlude ANY scroll content at ANY offset.
    expect(
      fabRect.overlaps(viewportRect),
      isFalse,
      reason:
          'FAB $fabRect must sit outside the dashboard scroll viewport '
          '$viewportRect (scale=$scale, locale=$locale)',
    );

    // Scroll escape: at full scroll the trailing must be fully visible and
    // still clear of the FAB.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pump();
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

  testWidgets('1.0x LTR: FAB never occludes the last group row at rest', (
    tester,
  ) async {
    await expectNoRestOcclusion(
      tester,
      scale: 1.0,
      locale: const Locale('en'),
    );
  });

  testWidgets('1.5x LTR: FAB never occludes the last group row at rest', (
    tester,
  ) async {
    await expectNoRestOcclusion(
      tester,
      scale: 1.5,
      locale: const Locale('en'),
    );
  });

  testWidgets('1.0x RTL: FAB never occludes the last group row at rest', (
    tester,
  ) async {
    await expectNoRestOcclusion(
      tester,
      scale: 1.0,
      locale: const Locale('ar'),
    );
  });

  testWidgets('1.5x RTL: FAB never occludes the last group row at rest', (
    tester,
  ) async {
    await expectNoRestOcclusion(
      tester,
      scale: 1.5,
      locale: const Locale('ar'),
    );
  });
}
