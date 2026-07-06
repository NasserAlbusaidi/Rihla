import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:safar/core/services/money_serializer.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/activity/keys/activity_keys.dart';
import 'package:safar/features/activity/screens/activity_feed_screen.dart';
import 'package:safar/features/activity/services/activity_service.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:safar/shared/widgets/paper_backdrop.dart';
import 'package:safar/shared/widgets/r_amount.dart';
import 'package:safar/shared/widgets/skeleton_loader.dart';

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

/// Never resolves the first page, holding the screen in its first-page
/// loading state so the loading skeleton stays on screen.
class _NeverCompletingActivityService extends ActivityService {
  _NeverCompletingActivityService(super.db) : super.withFirestore();
  @override
  Future<QuerySnapshot<Map<String, dynamic>>> fetchActivityPageRaw(
    String groupId,
    String eventId, {
    DocumentSnapshot? startAfter,
    int limit = 50,
  }) => Completer<QuerySnapshot<Map<String, dynamic>>>().future;
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
                  builder: (c, s) => Scaffold(
                    body: ActivityFeedScreen(
                      groupId: s.pathParameters['gid']!,
                      eventId: s.pathParameters['eid']!,
                    ),
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
    ); // NOT pumpAndSettle: the footer skeleton shimmer is infinite
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
    // footer skeleton shimmer is an infinite animation, so pumpAndSettle would
    // hang. The
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
    // Page-boundary day-merge uses the same groupByDay(_activities) path; widget-level
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

  testWidgets(
    'first-page load uses the shared SkeletonLoader — one unified treatment, '
    'no bare spinner or opaque blocks (#488)',
    (tester) async {
      // Event resolves (buildRoute default); the page fetch never completes,
      // so the screen sits in its first-page loading state.
      await tester.pumpWidget(
        buildRoute([
          activityServiceProvider.overrideWithValue(
            _NeverCompletingActivityService(FakeFirebaseFirestore()),
          ),
        ]),
      );
      await tester.pump(); // event data resolves; _loadPage hangs -> loading

      expect(find.byType(SkeletonLoader), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

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

  // ── #490 D-g: glyph adapter, trailing amounts, dot-date ───────────────────

  Future<void> seedTyped(
    FakeFirebaseFirestore db,
    String category,
    String eventType,
  ) async {
    await db
        .collection('groups')
        .doc(groupId)
        .collection('events')
        .doc(eventId)
        .collection('activity_logs')
        .doc('typed-1')
        .set({
          'id': 'typed-1',
          'eventId': eventId,
          'category': category,
          'eventType': eventType,
          'logText': 'did something',
          'actorId': 'u1',
          'actorName': 'Alice',
          'metadata': <String, dynamic>{},
          'createdAt': DateTime.utc(2026, 2, 1).toIso8601String(),
        });
  }

  Future<void> pumpFeed(WidgetTester tester, FakeFirebaseFirestore db) async {
    await tester.pumpWidget(
      buildRoute([
        activityServiceProvider.overrideWithValue(
          ActivityService.withFirestore(db),
        ),
      ]),
    );
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('MONEY/CREATE renders the receipt-add glyph', (tester) async {
    final db = FakeFirebaseFirestore();
    await seedTyped(db, 'MONEY', 'CREATE');
    await pumpFeed(tester, db);
    expect(find.byIcon(Iconsax.receipt_add), findsOneWidget);
  });

  testWidgets('MONEY/UPDATE renders the receipt-edit glyph', (tester) async {
    final db = FakeFirebaseFirestore();
    await seedTyped(db, 'MONEY', 'UPDATE');
    await pumpFeed(tester, db);
    expect(find.byIcon(Iconsax.receipt_edit), findsOneWidget);
  });

  testWidgets('MONEY/DELETE renders the receipt-minus glyph', (tester) async {
    final db = FakeFirebaseFirestore();
    await seedTyped(db, 'MONEY', 'DELETE');
    await pumpFeed(tester, db);
    expect(find.byIcon(Iconsax.receipt_minus), findsOneWidget);
  });

  testWidgets(
    'GEAR/DOCS/unknown categories fall back to the generic glyph '
    '(Phase-39 legacy categories demoted)',
    (tester) async {
      for (final category in ['GEAR', 'DOCS', 'SOMETHING_ELSE']) {
        final db = FakeFirebaseFirestore();
        await seedTyped(db, category, 'CREATE');
        await pumpFeed(tester, db);
        expect(
          find.byIcon(Iconsax.activity),
          findsOneWidget,
          reason: 'category=$category',
        );
      }
    },
  );

  testWidgets(
    'CREATE row shows a trailing amount and drops the old summary line',
    (tester) async {
      final db = FakeFirebaseFirestore();
      await seedAudit(db, 'CREATE', {
        'expenseId': 'exp1',
        'after': {
          'amountFils': 8000,
          'currency': 'OMR',
          'payerParticipantId': 'uid-creator',
          'description': 'Lunch',
          'isDeleted': false,
        },
      });
      await pumpFeed(tester, db);

      final amounts = tester.widgetList<RAmount>(find.byType(RAmount)).toList();
      expect(amounts, hasLength(1));
      expect(amounts.single.value, MoneySerializer.fromSubunits(8000, 'OMR'));
      expect(amounts.single.currency, 'OMR');
      expect(amounts.single.showCurrency, isTrue);
      expect(amounts.single.size, 14);
      // Old "<description>  ·  <amount>" summary line is gone.
      expect(find.text('Lunch  ·  '), findsNothing);
    },
  );

  testWidgets('DELETE row is muted, with the trailing amount at 0.6 opacity', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    await seedAudit(db, 'DELETE', {
      'expenseId': 'exp1',
      'before': {
        'amountFils': 3500,
        'currency': 'OMR',
        'payerParticipantId': 'uid-creator',
        'description': 'Taxi',
        'isDeleted': false,
      },
      'after': {
        'amountFils': 3500,
        'currency': 'OMR',
        'payerParticipantId': 'uid-creator',
        'description': 'Taxi',
        'isDeleted': true,
      },
    });
    await pumpFeed(tester, db);

    expect(find.byType(RAmount), findsOneWidget);
    final opacity = tester.widget<Opacity>(
      find
          .ancestor(of: find.byType(RAmount), matching: find.byType(Opacity))
          .first,
    );
    expect(opacity.opacity, 0.6);
  });

  testWidgets(
    'UPDATE-with-amount-change keeps the audit chip and has no trailing '
    'amount (no duplication)',
    (tester) async {
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
      await pumpFeed(tester, db);

      // Exactly the two chip amounts (before + after) — a third would mean a
      // duplicated trailing amount.
      expect(find.byType(RAmount), findsNWidgets(2));
    },
  );

  testWidgets('day header renders the dot-date suffix for a same-day entry', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    await db
        .collection('groups')
        .doc(groupId)
        .collection('events')
        .doc(eventId)
        .collection('activity_logs')
        .doc('today-1')
        .set({
          'id': 'today-1',
          'eventId': eventId,
          'category': 'MONEY',
          'eventType': 'CREATE',
          'logText': 'paid for item',
          'actorId': 'u1',
          'actorName': 'Actor',
          'metadata': <String, dynamic>{},
          'createdAt': DateTime.now().toIso8601String(),
        });
    await pumpFeed(tester, db);

    final l10n = AppLocalizations.of(
      tester.element(find.byKey(ActivityKeys.feedList)),
    );
    expect(find.text(l10n.timelineToday.toUpperCase()), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is Text && (w.data ?? '').startsWith(' · '),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'error view icon is a warning triangle, not the generic activity icon '
    '(P1)',
    (tester) async {
      final db = FakeFirebaseFirestore();
      final svc = _FailingActivityService(db);
      await tester.pumpWidget(
        buildRoute([activityServiceProvider.overrideWithValue(svc)]),
      );
      // Drains EmptyStateView's flutter_animate ticker (error is a terminal
      // state here, unlike the pagination-footer tests above).
      await tester.pumpAndSettle();
      expect(find.byKey(ActivityKeys.errorView), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(ActivityKeys.errorView),
          matching: find.byIcon(Iconsax.warning_2),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(ActivityKeys.errorView),
          matching: find.byIcon(Iconsax.activity),
        ),
        findsNothing,
      );
    },
  );

  // ── #758: embedded mode (tab panel inside the tabbed event view) ─────────

  testWidgets('#758 embedded mode renders the feed without its own chrome', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    await seed(db, 2);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          eventDetailProvider(
            eventRef,
          ).overrideWith((ref) => Stream<Event?>.value(event)),
          activityServiceProvider.overrideWithValue(
            ActivityService.withFirestore(db),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: ActivityFeedScreen(
              groupId: groupId,
              eventId: eventId,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    // Feed content renders…
    expect(find.textContaining('Actor 0', findRichText: true), findsOneWidget);
    // …but the screen contributes no chrome of its own: no back arrow, no
    // "ACTIVITY" caption, no nested Scaffold (the tabbed shell owns chrome).
    expect(find.byIcon(Iconsax.arrow_left), findsNothing);
    final l10n = AppLocalizations.of(
      tester.element(find.byKey(ActivityKeys.feedList)),
    );
    expect(find.text(l10n.activityCaption), findsNothing);
    expect(
      find.descendant(
        of: find.byType(ActivityFeedScreen),
        matching: find.byType(Scaffold),
      ),
      findsNothing,
    );
  });

  testWidgets('day card is flat + hairline, not raised (#866)', (
    tester,
  ) async {
    // Raised = the app's actionable-surface cue (#807 flat-vs-raised split),
    // but these rows are inert — their content affordance is the inline
    // ExpenseAuditDetail, not a tap target. The day card must carry no
    // shadow and a hairline border instead.
    final db = FakeFirebaseFirestore();
    await seed(db, 2);
    await tester.pumpWidget(
      buildRoute([
        activityServiceProvider.overrideWithValue(
          ActivityService.withFirestore(db),
        ),
      ]),
    );
    await tester.pump(const Duration(seconds: 1));

    final dayPadding = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('activity-day-'),
    );
    expect(dayPadding, findsOneWidget);
    // The card is the only rounded-decoration Container in the section (the
    // header hairline divider Container has no borderRadius).
    final card = tester.widget<Container>(
      find
          .descendant(
            of: dayPadding,
            matching: find.byWidgetPredicate(
              (w) =>
                  w is Container &&
                  w.decoration is BoxDecoration &&
                  (w.decoration as BoxDecoration).borderRadius != null,
            ),
          )
          .first,
    );
    final deco = card.decoration as BoxDecoration;
    expect(deco.boxShadow, isNull);
    expect(deco.border, isNotNull);
  });

  // ── #490 D-c: V2 grain+wash backdrop rollout (PR 5) ───────────────────────

  testWidgets(
    '#758 embedded mode carries NO PaperBackdrop — the tabbed shell owns '
    'chrome there',
    (tester) async {
      final db = FakeFirebaseFirestore();
      await seed(db, 2);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            eventDetailProvider(
              eventRef,
            ).overrideWith((ref) => Stream<Event?>.value(event)),
            activityServiceProvider.overrideWithValue(
              ActivityService.withFirestore(db),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(
              body: ActivityFeedScreen(
                groupId: groupId,
                eventId: eventId,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(PaperBackdrop), findsNothing);
    },
  );
}
