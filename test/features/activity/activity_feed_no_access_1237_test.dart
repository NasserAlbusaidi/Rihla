import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/activity/keys/activity_keys.dart';
import 'package:safar/features/activity/screens/activity_feed_screen.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// #1237 — the activity panel mirrors the #358/#1207 pattern: a permission-denied
/// `eventDetailProvider` listen renders the terminal `NoAccessView` (Home CTA, no
/// Retry) instead of the generic, retryable `_ErrorView`. A non-permission error
/// keeps the retryable state.
void main() {
  const groupId = 'group-1';
  const eventId = 'event-1';
  const eventKey = (groupId: groupId, eventId: eventId);

  FirebaseException denied() =>
      FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');

  // The screen's initState `_loadPage` reads activityServiceProvider inside a
  // try/catch; without Firebase it throws [core/no-app] and is swallowed —
  // harmless on the error / null-event paths this test exercises, so only
  // eventDetailProvider needs overriding.
  Future<void> pump(
    WidgetTester tester,
    Stream<Event?> Function() eventStreamFactory,
  ) async {
    final router = GoRouter(
      initialLocation: '/activity',
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, _) => const Scaffold(body: Text('Home')),
        ),
        GoRoute(
          path: '/activity',
          builder: (_, _) => const Scaffold(
            body: ActivityFeedScreen(groupId: groupId, eventId: eventId),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          eventDetailProvider(eventKey).overrideWith((_) => eventStreamFactory()),
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

  testWidgets('permission-denied event load shows no-access, hides error view', (
    tester,
  ) async {
    await pump(tester, () => Stream<Event?>.error(denied()));

    expect(find.text('You no longer have access'), findsOneWidget);
    expect(find.textContaining('no longer a member'), findsOneWidget);
    expect(find.text('Back home'), findsOneWidget);
    // Terminal — the retryable _ErrorView is gone.
    expect(find.byKey(ActivityKeys.errorView), findsNothing);
  });

  testWidgets('no-access Home CTA navigates to /home', (tester) async {
    await pump(tester, () => Stream<Event?>.error(denied()));

    await tester.tap(find.text('Back home'));
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets(
    'non-permission error keeps the retryable _ErrorView; Retry re-subscribes',
    (tester) async {
      var listenCount = 0;
      await pump(tester, () {
        listenCount++;
        return listenCount == 1
            ? Stream<Event?>.error(Exception('transient blip'))
            : Stream<Event?>.value(null);
      });

      expect(find.byKey(ActivityKeys.errorView), findsOneWidget);
      expect(find.text('You no longer have access'), findsNothing);

      await tester.tap(find.text('Reload'));
      await tester.pumpAndSettle();

      expect(listenCount, 2);
      expect(find.byKey(ActivityKeys.errorView), findsNothing);
      // event == null on the healed listen → _NotFoundView.
      expect(find.text('This event no longer exists'), findsOneWidget);
    },
  );
}
