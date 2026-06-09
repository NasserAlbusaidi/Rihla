import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/core/theme/error_widgets.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/screens/group_detail_screen.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #358 — when Firestore denies the group read (the user was removed from /
/// lost access to the group), the screen must show a friendly "no access"
/// empty state instead of a generic retry error, and must NOT leak the raw
/// Firebase error string.
void main() {
  const groupId = 'group-1';

  Future<void> pumpWithGroupStream(
    WidgetTester tester,
    Stream<Group?> groupStream,
  ) async {
    SharedPreferences.setMockInitialValues({'device_name': 'Alice'});
    final prefs = await SharedPreferences.getInstance();
    final router = GoRouter(
      initialLocation: '/group/$groupId',
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, _) => const Scaffold(body: Text('Home')),
        ),
        GoRoute(
          path: '/group/:gid',
          builder: (_, state) =>
              GroupDetailScreen(groupId: state.pathParameters['gid']!),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          currentUserIdProvider.overrideWithValue('uid-creator'),
          groupDetailProvider(groupId).overrideWith((ref) => groupStream),
        ],
        child: MaterialApp.router(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'permission-denied group read shows no-access state, hides raw error',
    (tester) async {
      final denied = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message: 'Missing or insufficient permissions.',
      );

      await pumpWithGroupStream(tester, Stream<Group?>.error(denied));

      expect(find.text('You no longer have access'), findsOneWidget);
      expect(
        find.textContaining('no longer a member'),
        findsOneWidget,
      );
      // Raw Firebase error must never surface to the user.
      expect(find.textContaining('permission-denied'), findsNothing);
      expect(find.textContaining('insufficient permissions'), findsNothing);
      // The no-access state is terminal — no Retry affordance (retrying a
      // denied read just re-denies).
      expect(find.text('Retry'), findsNothing);
      // It routes home, not retry.
      expect(find.text('Back home'), findsOneWidget);
    },
  );

  testWidgets(
    'non-permission error adopts NetworkErrorWidget with a retry CTA',
    (tester) async {
      await pumpWithGroupStream(
        tester,
        Stream<Group?>.error(Exception('transient network blip')),
      );

      // #358 — the generic error site now uses the shared NetworkErrorWidget
      // (adoption of the previously-orphaned primitive) instead of a
      // hand-rolled EmptyStateView error variant.
      expect(find.byType(NetworkErrorWidget), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('You no longer have access'), findsNothing);
    },
  );
}
