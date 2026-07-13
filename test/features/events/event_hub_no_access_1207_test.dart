import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/events/screens/event_command_center.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// #1207 — mirror the #358 pattern from `group_detail_screen.dart`: a
/// permission-denied `eventDetailProvider` listen (a removed member / a
/// deleted group) must render a terminal "no access" state with a Home CTA
/// instead of the generic, infinitely-retryable `_ErrorState`.
void main() {
  const groupId = 'group-1';
  const eventId = 'event-1';
  const eventKey = (groupId: groupId, eventId: eventId);

  FirebaseException denied() =>
      FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');

  // Takes a FACTORY (not a bare stream): `ref.invalidate` on Retry re-runs
  // the provider create, so the retry-tap case can count listens and serve a
  // different stream on the second subscription.
  Future<void> pumpWithEventStream(
    WidgetTester tester,
    Stream<Event?> Function() eventStreamFactory,
  ) async {
    final router = GoRouter(
      initialLocation: '/group/$groupId/event/$eventId',
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, _) => const Scaffold(body: Text('Home')),
        ),
        GoRoute(
          path: '/group/:gid/event/:eid',
          builder: (_, state) => EventCommandCenter(
            groupId: state.pathParameters['gid']!,
            eventId: state.pathParameters['eid']!,
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          eventDetailProvider(
            eventKey,
          ).overrideWith((_) => eventStreamFactory()),
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
    'permission-denied event load shows no-access state, hides Retry',
    (tester) async {
      await pumpWithEventStream(tester, () => Stream<Event?>.error(denied()));

      // #358-style copy: reused groupNoAccess* l10n keys (event access IS
      // group membership — no new ARB keys per the spec).
      expect(find.text('You no longer have access'), findsOneWidget);
      expect(
        find.textContaining('no longer a member'),
        findsOneWidget,
      );
      // Terminal — no Retry affordance (retrying a denied read just re-denies).
      expect(find.text('Retry'), findsNothing);
      // Home CTA is present.
      expect(find.text('Back home'), findsOneWidget);
    },
  );

  testWidgets('no-access Home CTA navigates to /home', (tester) async {
    await pumpWithEventStream(tester, () => Stream<Event?>.error(denied()));

    await tester.tap(find.text('Back home'));
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets(
    'non-permission error keeps the retryable _ErrorState, not no-access; '
    'Retry invalidates the provider and re-subscribes',
    (tester) async {
      // First listen errors; the post-Retry listen serves a fresh value
      // (null → _NotFoundState) proving onRetry's ref.invalidate re-ran the
      // provider create and the screen left the error state (the recap
      // screen's "Retry re-subscribes and heals" idiom).
      var listenCount = 0;
      await pumpWithEventStream(tester, () {
        listenCount++;
        return listenCount == 1
            ? Stream<Event?>.error(Exception('transient network blip'))
            : Stream<Event?>.value(null);
      });

      // EVENT hub's generic error uses EmptyStateView + commonRetry (NOT
      // group detail's NetworkErrorWidget — do not assert on that type here).
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('You no longer have access'), findsNothing);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(listenCount, 2);
      expect(find.text('Retry'), findsNothing);
      expect(find.text('Event not found'), findsOneWidget);
    },
  );
}
