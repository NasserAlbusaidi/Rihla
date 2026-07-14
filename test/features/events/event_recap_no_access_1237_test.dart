import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/events/screens/event_recap_screen.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// #1237 — the standalone recap route (deep-link / notification landing) mirrors
/// the #358/#1207 pattern: a permission-denied event listen renders the terminal
/// `NoAccessView` instead of the misleading "Event not found" (`_notFound`) — a
/// removed member isn't un-found, they're un-authorized. A non-permission error
/// keeps today's not-found state.
void main() {
  const groupId = 'group-1';
  const eventId = 'event-1';
  const eventKey = (groupId: groupId, eventId: eventId);

  FirebaseException denied() =>
      FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');

  Future<void> pump(
    WidgetTester tester,
    Stream<Event?> Function() eventStreamFactory,
  ) async {
    final router = GoRouter(
      initialLocation: '/recap',
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, _) => const Scaffold(body: Text('Home')),
        ),
        GoRoute(
          path: '/recap',
          // Standalone (embedded:false) — owns its own Scaffold.
          builder: (_, _) =>
              const EventRecapScreen(groupId: groupId, eventId: eventId),
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

  testWidgets('permission-denied event load shows no-access, not not-found', (
    tester,
  ) async {
    await pump(tester, () => Stream<Event?>.error(denied()));

    expect(find.text('You no longer have access'), findsOneWidget);
    expect(find.textContaining('no longer a member'), findsOneWidget);
    expect(find.text('Back home'), findsOneWidget);
    // The misleading "Event not found" must NOT show for a removed member.
    expect(find.text('Event not found'), findsNothing);
  });

  testWidgets('no-access Home CTA navigates to /home', (tester) async {
    await pump(tester, () => Stream<Event?>.error(denied()));

    await tester.tap(find.text('Back home'));
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('non-permission error keeps the not-found state, not no-access', (
    tester,
  ) async {
    await pump(tester, () => Stream<Event?>.error(Exception('transient blip')));

    expect(find.text('Event not found'), findsOneWidget);
    expect(find.text('You no longer have access'), findsNothing);
  });
}
