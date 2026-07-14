import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/groups/widgets/group_settle_up/settlement_top_bar.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

// Back-guard contract of the extracted SettlementTopBar (#965 code-motion):
// pushed entry -> canPop() -> pop(); sole-route cold entry -> go('/group/:gid').
void main() {
  const groupId = 'g1';

  GoRouter buildRouter({required String initialLocation}) => GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/group/:gid',
        builder: (_, state) =>
            Scaffold(body: Text('Group ${state.pathParameters['gid']}')),
      ),
      // Deliberately a top-level sibling (not a nested child): cold entry
      // must make it the sole stack page so canPop() is false.
      GoRoute(
        path: '/group/:gid/settle-up',
        builder: (_, state) => Scaffold(
          body: SettlementTopBar(groupId: state.pathParameters['gid']!),
        ),
      ),
    ],
  );

  Future<void> pumpBar(WidgetTester tester, GoRouter router) async {
    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppTheme.lightTheme,
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    );
    await tester.pumpAndSettle();
  }

  group('SettlementTopBar back guard', () {
    testWidgets('pushed entry: back pops to the previous page', (tester) async {
      final router = buildRouter(initialLocation: '/group/$groupId');
      addTearDown(router.dispose);
      await pumpBar(tester, router);

      // push()'s Future resolves only when the route is later popped —
      // awaiting it here would block forever (idiom:
      // group_detail_navigation_test.dart).
      unawaited(router.push('/group/$groupId/settle-up'));
      await tester.pumpAndSettle();
      expect(find.byType(SettlementTopBar), findsOneWidget);

      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        '/group/$groupId',
      );
      expect(find.byType(SettlementTopBar), findsNothing);
    });

    testWidgets('sole-route cold entry: back goes to /group/:gid', (
      tester,
    ) async {
      final router = buildRouter(
        initialLocation: '/group/$groupId/settle-up',
      );
      addTearDown(router.dispose);
      await pumpBar(tester, router);
      expect(find.byType(SettlementTopBar), findsOneWidget);

      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        '/group/$groupId',
      );
    });
  });
}
