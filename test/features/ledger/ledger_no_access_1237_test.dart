import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/ledger/screens/ledger_screen.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// #1237 — the ledger panel mirrors the #358/#1207 pattern: a permission-denied
/// `eventDetailProvider` listen (a removed member / a deleted group) renders the
/// terminal `NoAccessView` (Home CTA, no Retry) instead of the generic,
/// infinitely-retryable `_ErrorState`. A non-permission error keeps the
/// retryable state.
void main() {
  const groupId = 'group-1';
  const eventId = 'event-1';
  const eventKey = (groupId: groupId, eventId: eventId);

  FirebaseException denied() =>
      FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');

  // A FACTORY (not a bare stream): `ref.invalidate` on Retry re-runs the
  // provider create, so the retry-tap case can count listens and serve a
  // different stream on the second subscription.
  Future<void> pump(
    WidgetTester tester,
    Stream<Event?> Function() eventStreamFactory,
  ) async {
    final router = GoRouter(
      initialLocation: '/ledger',
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, _) => const Scaffold(body: Text('Home')),
        ),
        GoRoute(
          path: '/ledger',
          builder: (_, _) => const Scaffold(
            body: LedgerScreen(groupId: groupId, eventId: eventId),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          eventDetailProvider(eventKey).overrideWith((_) => eventStreamFactory()),
          // Eagerly watched at build top; unused on the error / null-event
          // paths, overridden so provider-create never touches Firebase.
          eventExpensesProvider(
            eventKey,
          ).overrideWith((_) => Stream<List<Expense>>.value(const [])),
          eventSettlementsProvider(
            eventKey,
          ).overrideWith((_) => Stream<List<Settlement>>.value(const [])),
          groupDetailProvider(groupId).overrideWith((_) => const Stream.empty()),
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

  testWidgets('permission-denied event load shows no-access, hides retry', (
    tester,
  ) async {
    await pump(tester, () => Stream<Event?>.error(denied()));

    expect(find.text('You no longer have access'), findsOneWidget);
    expect(find.textContaining('no longer a member'), findsOneWidget);
    expect(find.text('Back home'), findsOneWidget);
    // Terminal — the retryable _ErrorState ("Could not load event") is gone.
    expect(find.text('Could not load event'), findsNothing);
  });

  testWidgets('no-access Home CTA navigates to /home', (tester) async {
    await pump(tester, () => Stream<Event?>.error(denied()));

    await tester.tap(find.text('Back home'));
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets(
    'non-permission error keeps the retryable _ErrorState; Retry re-subscribes',
    (tester) async {
      // First listen errors generically; the post-Retry listen serves null
      // (→ _NotFoundState) proving onRetry's ref.invalidate re-ran the create
      // and the screen left the error state.
      var listenCount = 0;
      await pump(tester, () {
        listenCount++;
        return listenCount == 1
            ? Stream<Event?>.error(Exception('transient blip'))
            : Stream<Event?>.value(null);
      });

      expect(find.text('Could not load event'), findsOneWidget);
      expect(find.text('You no longer have access'), findsNothing);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(listenCount, 2);
      expect(find.text('Could not load event'), findsNothing);
      // event == null on the healed listen → _NotFoundState.
      expect(find.text('Event not found'), findsOneWidget);
    },
  );
}
