import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/activity/keys/activity_keys.dart';
import 'package:safar/features/activity/screens/activity_feed_screen.dart';
import 'package:safar/features/activity/services/activity_service.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:safar/shared/widgets/r_amount.dart';

/// Throws on the first fetch (initial-load error), then delegates to the real
/// fake-backed query so the retry path can be exercised.
class _FailingActivityService extends ActivityService {
  _FailingActivityService(super.db) : super.withFirestore();
  int calls = 0;
  @override
  Future<QuerySnapshot<Map<String, dynamic>>> fetchActivityPageRaw(
    String groupId,
    String eventId, {
    DocumentSnapshot? startAfter,
    int limit = 50,
  }) async {
    calls++;
    if (calls == 1) throw Exception('boom');
    return super.fetchActivityPageRaw(
      groupId,
      eventId,
      startAfter: startAfter,
      limit: limit,
    );
  }
}

void main() {
  const groupId = 'group-1';
  const eventId = 'event-1';
  const eventRef = (groupId: groupId, eventId: eventId);

  final event = Event(
    id: eventId,
    groupId: groupId,
    name: 'Beach Trip',
    type: EventType.trip,
    createdBy: 'uid-creator',
    participantIds: const ['uid-creator'],
    participantNames: const {'uid-creator': 'Alice'},
    modules: const EventModules(),
    createdAt: DateTime(2026, 1, 1),
  );

  // Seeds n logs; the first [dayBcount] go on 2026-02-02 (newest), the rest on
  // 2026-02-01. Newest-first by createdAt. Each row's actorName is unique
  // ('Actor i') because the row renders log.actorName — the raw logText is never
  // displayed for MONEY/CREATE (localizedEventActivityText maps it to a phrase),
  // so actorName is the only per-row identifier visible in the widget tree.
  Future<void> seed(FakeFirebaseFirestore db, int n, {int dayBcount = 0}) async {
    for (var i = 0; i < n; i++) {
      final base = i < dayBcount
          ? DateTime.utc(2026, 2, 2)
          : DateTime.utc(2026, 2, 1);
      final ts = base.add(Duration(seconds: n - i)); // higher i => older
      await db
          .collection('groups')
          .doc(groupId)
          .collection('events')
          .doc(eventId)
          .collection('activity_logs')
          .doc('a${i.toString().padLeft(4, '0')}')
          .set({
            'id': 'a$i',
            'eventId': eventId,
            'category': 'MONEY',
            'eventType': 'CREATE',
            'logText': 'paid for item $i',
            'actorId': 'u1',
            'actorName': 'Actor $i',
            'metadata': <String, dynamic>{},
            'createdAt': ts.toIso8601String(),
          });
    }
  }

  Widget buildRoute(List<Override> overrides) {
    final router = GoRouter(
      initialLocation: '/group/$groupId/event/$eventId/activity',
      routes: [
        GoRoute(
          path: '/group/:gid',
          builder: (c, s) =>
              Scaffold(body: Text('GroupDetail:${s.pathParameters['gid']}')),
          routes: [
            GoRoute(
              path: 'event/:eid',
              builder: (c, s) =>
                  Scaffold(body: Text('EventHub:${s.pathParameters['eid']}')),
              routes: [
                GoRoute(
                  path: 'activity',
                  builder: (c, s) => ActivityFeedScreen(
                    groupId: s.pathParameters['gid']!,
                    eventId: s.pathParameters['eid']!,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    return ProviderScope(
      overrides: [
        eventDetailProvider(
          eventRef,
        ).overrideWith((ref) => Stream<Event?>.value(event)),
        ...overrides,
      ],
      child: MaterialApp.router(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    );
  }

  // Count distinct day sections via the keys applied in itemBuilder.
  int dayHeaderCount() => find
      .byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key as ValueKey<String>).value.startsWith('activity-day-'),
      )
      .evaluate()
      .length;

  testWidgets('direct route back button returns to event hub', (tester) async {
    final db = FakeFirebaseFirestore(); // empty -> no footer spinner
    await tester.pumpWidget(
      buildRoute([
        activityServiceProvider.overrideWithValue(
          ActivityService.withFirestore(db),
        ),
      ]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Iconsax.arrow_left));
    await tester.pumpAndSettle();
    expect(find.text('EventHub:$eventId'), findsOneWidget);
  });

  testWidgets('loads only the first page; later rows are not pre-fetched', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    await seed(db, 60); // > one 50-page
    await tester.pumpWidget(
      buildRoute([
        activityServiceProvider.overrideWithValue(
          ActivityService.withFirestore(db),
        ),
      ]),
    );
    await tester.pump(
      const Duration(seconds: 1),
    ); // NOT pumpAndSettle: footer spinner is infinite
    // Newest row is on-screen at the top after page 1 loads. The actor name is a
    // span inside the row's Text.rich, so match with findRichText.
    expect(find.textContaining('Actor 0', findRichText: true), findsOneWidget);
    // Oldest row lives only in page 2 (rows 50..59) — not fetched until scroll.
    expect(find.textContaining('Actor 59', findRichText: true), findsNothing);
  });

  testWidgets('scrolling to the bottom loads the next page', (tester) async {
    final db = FakeFirebaseFirestore();
    await seed(db, 60);
    await tester.pumpWidget(
      buildRoute([
        activityServiceProvider.overrideWithValue(
          ActivityService.withFirestore(db),
        ),
      ]),
    );
    await tester.pump(const Duration(seconds: 1));
    // The actor name is a span inside the row's Text.rich, so match with findRichText.
    final actor59 = find.textContaining('Actor 59', findRichText: true);
    expect(actor59, findsNothing); // page 2 not yet loaded

    // Scroll down until the page-2 row appears. scrollUntilVisible advances the
    // clock by `duration` (pump, NOT pumpAndSettle) between small drags — the
    // footer spinner is an infinite animation, so pumpAndSettle would hang. The
    // small step keeps the offset from overshooting the lazy list's shrinking
    // maxScrollExtent (a larger single drag pins the position past the end and
    // stalls pagination).
    await tester.scrollUntilVisible(
      actor59,
      300,
      scrollable: find.byType(Scrollable).first,
      duration: const Duration(milliseconds: 300),
      maxScrolls: 60,
    );
    expect(
      actor59,
      findsOneWidget,
    ); // page 2 loaded via scroll -> no silent truncation
  });

  testWidgets('logs across two days render as two day sections', (tester) async {
    final db = FakeFirebaseFirestore();
    // 2 on day B (newest) + 2 on day A -> one page (<50), no footer, no scroll.
    await seed(db, 4, dayBcount: 2);
    await tester.pumpWidget(
      buildRoute([
        activityServiceProvider.overrideWithValue(
          ActivityService.withFirestore(db),
        ),
      ]),
    );
    await tester.pump(const Duration(seconds: 1));
    // Page-boundary day-merge uses the same _groupByDay(_activities) path; widget-level
    // boundary counting is unreliable under ListView virtualization, so grouping
    // correctness is asserted here at single-page scale.
    expect(dayHeaderCount(), 2);
  });

  testWidgets('failed initial load shows error+retry; retry re-fetches', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore(); // empty: retry returns an empty page
    final svc = _FailingActivityService(db);
    await tester.pumpWidget(
      buildRoute([activityServiceProvider.overrideWithValue(svc)]),
    );
    await tester.pump(
      const Duration(seconds: 1),
    ); // initial load throws -> error view
    expect(find.byKey(ActivityKeys.errorView), findsOneWidget);

    // Tap the localized reload action (read l10n from the live element).
    final l10n = AppLocalizations.of(
      tester.element(find.byKey(ActivityKeys.errorView)),
    );
    await tester.tap(find.text(l10n.activityReload));
    // retry -> empty page -> empty state. pumpAndSettle is safe here: the retry
    // resolves to a (spinnerless) empty state, and it also drains EmptyStateView's
    // flutter_animate fadeIn/scale ticker so no Timer is pending at teardown.
    await tester.pumpAndSettle();
    expect(find.byKey(ActivityKeys.errorView), findsNothing);
  });

  // ── #248 PR 3: expense audit before/after rendering ──────────────────────

  Future<void> seedAudit(
    FakeFirebaseFirestore db,
    String eventType,
    Map<String, dynamic> metadata,
  ) async {
    await db
        .collection('groups')
        .doc(groupId)
        .collection('events')
        .doc(eventId)
        .collection('activity_logs')
        .doc('audit-1')
        .set({
          'id': 'audit-1',
          'eventId': eventId,
          'category': 'MONEY',
          'eventType': eventType,
          'logText': 'changed an expense',
          'actorId': 'uid-creator',
          'actorName': 'Alice',
          'metadata': metadata,
          'createdAt': DateTime.utc(2026, 2, 1).toIso8601String(),
        });
  }

  testWidgets('MONEY/UPDATE row renders the before → after amount detail', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    await seedAudit(db, 'UPDATE', {
      'expenseId': 'exp1',
      'before': {
        'amountFils': 10500,
        'currency': 'OMR',
        'payerParticipantId': 'uid-creator',
        'description': 'Dinner',
        'isDeleted': false,
      },
      'after': {
        'amountFils': 12500,
        'currency': 'OMR',
        'payerParticipantId': 'uid-creator',
        'description': 'Dinner',
        'isDeleted': false,
      },
    });
    await tester.pumpWidget(
      buildRoute([
        activityServiceProvider.overrideWithValue(
          ActivityService.withFirestore(db),
        ),
      ]),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('10.500', findRichText: true), findsOneWidget);
    expect(find.textContaining('12.500', findRichText: true), findsOneWidget);
  });

  testWidgets('legacy MONEY row (empty metadata) renders no audit detail', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    await seedAudit(db, 'CREATE', <String, dynamic>{}); // legacy: no before/after
    await tester.pumpWidget(
      buildRoute([
        activityServiceProvider.overrideWithValue(
          ActivityService.withFirestore(db),
        ),
      ]),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(RAmount), findsNothing); // verb line only, no detail
  });
}
