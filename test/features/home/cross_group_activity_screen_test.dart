import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:decimal/decimal.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/keys/shared_keys.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/groups/models/group_activity_log_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/services/group_activity_service.dart';
import 'package:safar/features/home/providers/cross_group_activity_pager.dart';
import 'package:safar/features/home/screens/cross_group_activity_screen.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:safar/shared/widgets/paper_backdrop.dart';
import 'package:safar/shared/widgets/r_amount.dart';
import 'package:safar/shared/widgets/skeleton_loader.dart';

// ---------------------------------------------------------------------------
// Fixtures + helpers
// ---------------------------------------------------------------------------

Group _group(String id, String name, {String currency = 'OMR'}) => Group(
  id: id,
  name: name,
  inviteCode: 'INV${id.toUpperCase()}',
  createdBy: 'uid0',
  memberIds: const ['uid0'],
  currency: currency,
  createdAt: DateTime(2026, 1, 1),
);

GroupActivityLog _activity(
  String id,
  String actorName,
  String description, {
  String type = 'event_created',
  Map<String, dynamic> metadata = const {},
  DateTime? at,
}) => GroupActivityLog(
  id: id,
  type: type,
  actorId: 'uid0',
  actorName: actorName,
  description: description,
  metadata: metadata,
  timestamp: at ?? DateTime(2026, 3, 28),
);

Future<void> _seed(
  FakeFirebaseFirestore db,
  String groupId,
  List<GroupActivityLog> logs,
) async {
  for (final a in logs) {
    await db
        .collection('groups')
        .doc(groupId)
        .collection('activity')
        .doc(a.id)
        .set({
          'id': a.id,
          'type': a.type,
          'actorId': a.actorId,
          'actorName': a.actorName,
          'description': a.description,
          'metadata': a.metadata,
          'timestamp': a.timestamp.toUtc().toIso8601String(),
        });
  }
}

/// Fails every fetch — models a total load failure.
class _ThrowingService extends GroupActivityService {
  _ThrowingService() : super.withFirestore(FakeFirebaseFirestore());
  @override
  Future<QuerySnapshot<Map<String, dynamic>>> fetchActivityPageRaw(
    String groupId, {
    DocumentSnapshot? startAfter,
    int limit = 50,
  }) async => throw Exception('boom');
}

/// Fails only for [failGroupId]; other groups read from the fake normally.
class _SelectiveThrowService extends GroupActivityService {
  _SelectiveThrowService(super.db, this.failGroupId) : super.withFirestore();
  final String failGroupId;
  @override
  Future<QuerySnapshot<Map<String, dynamic>>> fetchActivityPageRaw(
    String groupId, {
    DocumentSnapshot? startAfter,
    int limit = 50,
  }) async {
    if (groupId == failGroupId) throw Exception('boom for $failGroupId');
    return super.fetchActivityPageRaw(
      groupId,
      startAfter: startAfter,
      limit: limit,
    );
  }
}

/// Holds its first fetch until [gate] completes — models an in-flight load so
/// the skeleton is observable.
class _PendingService extends GroupActivityService {
  _PendingService(super.db) : super.withFirestore();
  final Completer<void> gate = Completer<void>();
  @override
  Future<QuerySnapshot<Map<String, dynamic>>> fetchActivityPageRaw(
    String groupId, {
    DocumentSnapshot? startAfter,
    int limit = 50,
  }) async {
    if (!gate.isCompleted) await gate.future;
    return super.fetchActivityPageRaw(
      groupId,
      startAfter: startAfter,
      limit: limit,
    );
  }
}

/// PR4: resolves normally on the FIRST fetch (the constructor's `_reload`),
/// then hangs on [gate] on every subsequent fetch (a `loadMore()` pass) —
/// models "page 1 is visible, page 2 is in flight" so the footer's
/// `isLoadingMore` branch is observable with non-empty entries.
class _PendingAfterFirstService extends GroupActivityService {
  _PendingAfterFirstService(super.db) : super.withFirestore();
  final Completer<void> gate = Completer<void>();
  int _calls = 0;
  @override
  Future<QuerySnapshot<Map<String, dynamic>>> fetchActivityPageRaw(
    String groupId, {
    DocumentSnapshot? startAfter,
    int limit = 50,
  }) async {
    _calls++;
    if (_calls > 1) await gate.future;
    return super.fetchActivityPageRaw(
      groupId,
      startAfter: startAfter,
      limit: limit,
    );
  }
}

Widget _app({
  required List<Group> groups,
  required GroupActivityService service,
  required SharedPreferences prefs,
  bool showBack = false,
  String initialLocation = '/activity',
}) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/home',
        builder: (ctx, state) => Scaffold(
          body: ElevatedButton(
            onPressed: () => ctx.push('/activity'),
            child: const Text('Go to Activity'),
          ),
        ),
      ),
      GoRoute(
        path: '/activity',
        builder: (ctx, state) => CrossGroupActivityScreen(showBack: showBack),
      ),
      GoRoute(
        path: '/group/:id',
        builder: (ctx, state) =>
            Scaffold(body: Text('GroupDetail:${state.pathParameters['id']}')),
        // #840 PR-7: nested target routes for per-type History deep-links.
        // The fake harness param is `:id` (NOT the real router's `:gid`) —
        // pushes are literal path strings so this mismatch never reaches prod.
        routes: [
          GoRoute(
            path: 'settle-up',
            builder: (ctx, state) => Scaffold(
              body: Text(
                'GroupSettleUp:${state.pathParameters['id']}'
                '?${state.uri.query}',
              ),
            ),
          ),
          GoRoute(
            path: 'event/:eid',
            builder: (ctx, state) => Scaffold(
              body: Text(
                'EventHub:${state.pathParameters['id']}/'
                '${state.pathParameters['eid']}',
              ),
            ),
            routes: [
              GoRoute(
                path: 'ledger',
                builder: (ctx, state) => Scaffold(
                  body: Text(
                    'EventLedger:${state.pathParameters['id']}/'
                    '${state.pathParameters['eid']}',
                  ),
                ),
              ),
              GoRoute(
                path: 'activity',
                builder: (ctx, state) => Scaffold(
                  body: Text(
                    'EventActivity:${state.pathParameters['id']}/'
                    '${state.pathParameters['eid']}',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      userGroupsProvider.overrideWith((ref) => Stream.value(groups)),
      groupActivityServiceProvider.overrideWith((ref) => service),
      currentUserIdProvider.overrideWithValue('uid0'),
    ],
    child: MaterialApp.router(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  );
}

Finder _richContaining(String text) => find.byWidgetPredicate(
  (w) =>
      w is Text &&
      ((w.data?.contains(text) ?? false) ||
          (w.textSpan?.toPlainText().contains(text) ?? false)),
);

void main() {
  setUpAll(() => SharedPreferences.setMockInitialValues({}));

  Future<SharedPreferences> prefs() => SharedPreferences.getInstance();

  group('CrossGroupActivityScreen (paginated)', () {
    testWidgets('shows "History" title', (tester) async {
      final db = FakeFirebaseFirestore();
      await tester.pumpWidget(
        _app(
          groups: [_group('g1', 'Trip A')],
          service: GroupActivityService.withFirestore(db),
          prefs: await prefs(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('History'), findsOneWidget);
    });

    testWidgets('shows empty state when there is no activity', (tester) async {
      final db = FakeFirebaseFirestore();
      await tester.pumpWidget(
        _app(
          groups: [_group('g1', 'Trip A')],
          service: GroupActivityService.withFirestore(db),
          prefs: await prefs(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No activity yet'), findsOneWidget);
    });

    testWidgets('shows a skeleton while the first load is in flight (#488)', (
      tester,
    ) async {
      final db = FakeFirebaseFirestore();
      await _seed(db, 'g1', [_activity('a1', 'Alice', 'created an event')]);
      final service = _PendingService(db);
      await tester.pumpWidget(
        _app(
          groups: [_group('g1', 'Trip A')],
          service: service,
          prefs: await prefs(),
        ),
      );
      await tester.pump(); // load kicked off, gate not yet open
      expect(find.byType(SkeletonLoader), findsOneWidget);

      service.gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(SkeletonLoader), findsNothing);
    });

    testWidgets('renders entries enriched with their group name', (
      tester,
    ) async {
      final db = FakeFirebaseFirestore();
      await _seed(db, 'g1', [_activity('a1', 'Alice', 'created an event')]);
      await _seed(db, 'g2', [
        _activity('a2', 'Bob', 'joined', type: 'member_joined'),
      ]);
      await tester.pumpWidget(
        _app(
          groups: [_group('g1', 'Trip A'), _group('g2', 'Trip B')],
          service: GroupActivityService.withFirestore(db),
          prefs: await prefs(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Trip A'), findsOneWidget);
      expect(find.text('Trip B'), findsOneWidget);
      expect(_richContaining('created an event'), findsOneWidget);
      expect(_richContaining('joined the group'), findsOneWidget);
    });

    testWidgets('settlement uses the wallet glyph in a top-aligned row', (
      tester,
    ) async {
      final db = FakeFirebaseFirestore();
      await _seed(db, 'g1', [
        _activity(
          's1',
          'Alice',
          'recorded a settlement',
          type: 'group_settlement',
          metadata: const {'amount': '12.5'},
        ),
      ]);
      await tester.pumpWidget(
        _app(
          groups: [_group('g1', 'Trip A')],
          service: GroupActivityService.withFirestore(db),
          prefs: await prefs(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Iconsax.wallet_3), findsOneWidget);
      final amounts = tester.widgetList<RAmount>(find.byType(RAmount)).toList();
      expect(amounts, hasLength(1));
      expect(amounts.single.value, Decimal.parse('12.5'));
    });

    testWidgets('per-doc settlement currency wins over the group currency', (
      tester,
    ) async {
      final db = FakeFirebaseFirestore();
      await _seed(db, 'g1', [
        _activity(
          's1',
          'Alice',
          'recorded a settlement',
          type: 'group_settlement',
          metadata: const {'amount': '20.25', 'currency': 'USD'},
          at: DateTime(2026, 3, 28),
        ),
      ]);
      await tester.pumpWidget(
        _app(
          groups: [_group('g1', 'Oman Trip')], // group currency OMR
          service: GroupActivityService.withFirestore(db),
          prefs: await prefs(),
        ),
      );
      await tester.pumpAndSettle();

      final amounts = tester.widgetList<RAmount>(find.byType(RAmount)).toList();
      expect(amounts.single.currency, 'USD');
    });

    testWidgets('renders a localized expense_* row with amount from amountFils',
        (tester) async {
      final db = FakeFirebaseFirestore();
      await _seed(db, 'g1', [
        _activity(
          'e1',
          'Alice',
          'added Dinner (10.500 OMR)',
          type: 'expense_added',
          metadata: const {
            'expenseId': 'x1',
            'eventId': 'ev1',
            'eventName': 'Beach Trip',
            'amountFils': 10500,
            'currency': 'OMR',
          },
        ),
      ]);
      await tester.pumpWidget(
        _app(
          groups: [_group('g1', 'Trip A')],
          service: GroupActivityService.withFirestore(db),
          prefs: await prefs(),
        ),
      );
      await tester.pumpAndSettle();

      expect(_richContaining('added an expense in Beach Trip'), findsOneWidget);
      expect(find.byIcon(Iconsax.receipt_add), findsOneWidget);
      final amounts = tester.widgetList<RAmount>(find.byType(RAmount)).toList();
      expect(amounts.single.value, Decimal.parse('10.5'));
      expect(amounts.single.currency, 'OMR');
    });

    testWidgets('expense amount renders when Firestore deserializes amountFils '
        'as a double (expense_audit_diff.dart:37 precedent)', (tester) async {
      final db = FakeFirebaseFirestore();
      await _seed(db, 'g1', [
        _activity(
          'e1',
          'Alice',
          'added Dinner (8.000 OMR)',
          type: 'expense_added',
          metadata: const {
            'expenseId': 'x1',
            'eventId': 'ev1',
            'eventName': 'Beach Trip',
            'amountFils': 8000.0,
            'currency': 'OMR',
          },
        ),
      ]);
      await tester.pumpWidget(
        _app(
          groups: [_group('g1', 'Trip A')],
          service: GroupActivityService.withFirestore(db),
          prefs: await prefs(),
        ),
      );
      await tester.pumpAndSettle();

      final amounts = tester.widgetList<RAmount>(find.byType(RAmount)).toList();
      expect(amounts, hasLength(1));
      expect(amounts.single.value, Decimal.parse('8'));
      expect(amounts.single.currency, 'OMR');
    });

    testWidgets('forged non-finite amountFils renders the row without an '
        'amount and without an ErrorWidget (group_settlement metadata is '
        'client-forgeable)', (tester) async {
      final db = FakeFirebaseFirestore();
      await _seed(db, 'g1', [
        _activity(
          's-nan',
          'Mallory',
          'recorded a settlement',
          type: 'group_settlement',
          metadata: const {'amountFils': double.nan, 'currency': 'OMR'},
        ),
      ]);
      await tester.pumpWidget(
        _app(
          groups: [_group('g1', 'Trip A')],
          service: GroupActivityService.withFirestore(db),
          prefs: await prefs(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ErrorWidget), findsNothing);
      expect(_richContaining('recorded a settlement'), findsOneWidget);
      expect(find.byType(RAmount), findsNothing);
    });

    testWidgets('Expenses filter shows only expense_* rows', (tester) async {
      final db = FakeFirebaseFirestore();
      await _seed(db, 'g1', [
        _activity(
          'e1',
          'Alice',
          'added an expense',
          type: 'expense_added',
          metadata: const {
            'eventName': 'Beach Trip',
            'amountFils': 500,
            'currency': 'OMR',
          },
          at: DateTime(2026, 3, 28),
        ),
        _activity(
          's1',
          'Bob',
          'recorded a settlement',
          type: 'group_settlement',
          metadata: const {'amount': '9'},
          at: DateTime(2026, 3, 27),
        ),
      ]);
      await tester.pumpWidget(
        _app(
          groups: [_group('g1', 'Trip A')],
          service: GroupActivityService.withFirestore(db),
          prefs: await prefs(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Expenses'));
      await tester.pumpAndSettle();

      expect(_richContaining('added an expense in Beach Trip'), findsOneWidget);
      expect(_richContaining('recorded a settlement'), findsNothing);
    });

    testWidgets('paginates: a page-2-only row becomes findable after scrolling',
        (tester) async {
      final db = FakeFirebaseFirestore();
      final now = DateTime(2026, 3, 28, 12);
      await _seed(db, 'g1', [
        for (var i = 0; i < 60; i++)
          _activity(
            'a$i',
            'Actor-$i',
            'created an event',
            at: now.subtract(Duration(minutes: i)),
          ),
      ]);
      await tester.pumpWidget(
        _app(
          groups: [_group('g1', 'Trip A')],
          service: GroupActivityService.withFirestore(db),
          prefs: await prefs(),
        ),
      );
      await tester.pumpAndSettle();

      // Actor-55 is on page 2 (entries 50..59) — not present before scrolling.
      final target = find.textContaining('Actor-55', findRichText: true);
      expect(target, findsNothing);

      final scrollable = find.byType(Scrollable).last;
      for (var i = 0; i < 60 && target.evaluate().isEmpty; i++) {
        await tester.drag(scrollable, const Offset(0, -300));
        await tester.pump(const Duration(milliseconds: 80));
      }
      expect(target, findsWidgets);
    });

    testWidgets('pull-to-refresh re-runs the load without error', (
      tester,
    ) async {
      final db = FakeFirebaseFirestore();
      await _seed(db, 'g1', [_activity('a1', 'Alice', 'created an event')]);
      await tester.pumpWidget(
        _app(
          groups: [_group('g1', 'Trip A')],
          service: GroupActivityService.withFirestore(db),
          prefs: await prefs(),
        ),
      );
      await tester.pumpAndSettle();
      expect(_richContaining('created an event'), findsOneWidget);

      await tester.fling(find.byType(RefreshIndicator), const Offset(0, 300), 1000);
      await tester.pumpAndSettle();

      expect(_richContaining('created an event'), findsOneWidget);
    });

    testWidgets('total load failure shows the #488 error view with retry', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          groups: [_group('g1', 'Trip A')],
          service: _ThrowingService(),
          prefs: await prefs(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Could not load activity'), findsOneWidget);
      expect(find.text('No activity yet'), findsNothing);
    });

    testWidgets('partial failure shows a footer notice + retry, plus survivors',
        (tester) async {
      final db = FakeFirebaseFirestore();
      await _seed(db, 'g1', [_activity('a1', 'Alice', 'created an event')]);
      await tester.pumpWidget(
        _app(
          groups: [_group('g1', 'Trip A'), _group('g2', 'Trip B')],
          service: _SelectiveThrowService(db, 'g2'),
          prefs: await prefs(),
        ),
      );
      await tester.pumpAndSettle();

      // The readable group's entry still shows…
      expect(_richContaining('created an event'), findsOneWidget);
      // …with a partial-failure notice.
      expect(find.text("Some activity couldn't load"), findsOneWidget);
    });

    testWidgets('Settlements filter finds a settlement beyond the newest few', (
      tester,
    ) async {
      final db = FakeFirebaseFirestore();
      await _seed(db, 'g1', [
        for (var i = 0; i < 6; i++)
          _activity('e$i', 'Ali', 'created an event', at: DateTime(2026, 3, 20 + i)),
        _activity(
          's-old',
          'Sara-Settler',
          'recorded a settlement',
          type: 'group_settlement',
          metadata: const {'amount': '12.5'},
          at: DateTime(2026, 3, 1),
        ),
      ]);
      await tester.pumpWidget(
        _app(
          groups: [_group('g1', 'Trip A')],
          service: GroupActivityService.withFirestore(db),
          prefs: await prefs(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Settlements'));
      await tester.pumpAndSettle();

      expect(find.text('Nothing matches this filter'), findsNothing);
      expect(
        find.textContaining('Sara-Settler', findRichText: true),
        findsWidgets,
      );
    });

    testWidgets('empty state offers an Add-expense CTA when the user has groups',
        (tester) async {
      final db = FakeFirebaseFirestore();
      await tester.pumpWidget(
        _app(
          groups: [_group('g1', 'Trip A')],
          service: GroupActivityService.withFirestore(db),
          prefs: await prefs(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No activity yet'), findsOneWidget);
      expect(find.byKey(SharedKeys.emptyStateCtaButton), findsOneWidget);
    });

    testWidgets('empty state has NO CTA when the user has zero groups (#807)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          groups: const [],
          service: GroupActivityService.withFirestore(FakeFirebaseFirestore()),
          prefs: await prefs(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No activity yet'), findsOneWidget);
      expect(find.byKey(SharedKeys.emptyStateCtaButton), findsNothing);
    });

    // #840 PR-7: row tap now deep-links per activity type instead of always
    // pushing group detail. `event_created` WITH an eventId now lands on the
    // event hub, not group detail — this is the behavior change the old
    // "uniform push" test used to pin.
    testWidgets(
      'event_created with an eventId routes to the event hub, not group '
      'detail (#840)',
      (tester) async {
        final db = FakeFirebaseFirestore();
        await _seed(db, 'g1', [
          _activity(
            'a1',
            'Alice',
            'created an event',
            type: 'event_created',
            metadata: const {'eventId': 'ev1', 'eventName': 'Beach Trip'},
          ),
        ]);
        await tester.pumpWidget(
          _app(
            groups: [_group('g1', 'Trip A')],
            service: GroupActivityService.withFirestore(db),
            prefs: await prefs(),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(_richContaining('created Beach Trip'));
        await tester.pumpAndSettle();
        expect(find.text('EventHub:g1/ev1'), findsOneWidget);
        expect(find.text('GroupDetail:g1'), findsNothing);
      },
    );
  });

  group('PR4: shared activity chrome (#490)', () {
    testWidgets(
      'group context renders as a bordered tag chip, not a plain text line',
      (tester) async {
        final db = FakeFirebaseFirestore();
        await _seed(db, 'g1', [_activity('a1', 'Alice', 'created an event')]);
        await tester.pumpWidget(
          _app(
            groups: [_group('g1', 'Trip A')],
            service: GroupActivityService.withFirestore(db),
            prefs: await prefs(),
          ),
        );
        await tester.pumpAndSettle();

        final chip = find.ancestor(
          of: find.text('Trip A'),
          matching: find.byWidgetPredicate(
            (w) =>
                w is Container &&
                w.decoration is BoxDecoration &&
                (w.decoration! as BoxDecoration).border != null,
          ),
        );
        expect(chip, findsOneWidget);
      },
    );

    testWidgets('today\'s day header shows the dot-date suffix (D-f)', (
      tester,
    ) async {
      final db = FakeFirebaseFirestore();
      await _seed(db, 'g1', [
        _activity('a1', 'Alice', 'created an event', at: DateTime.now()),
      ]);
      await tester.pumpWidget(
        _app(
          groups: [_group('g1', 'Trip A')],
          service: GroupActivityService.withFirestore(db),
          prefs: await prefs(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('TODAY'), findsOneWidget);
      expect(find.textContaining('·'), findsWidgets);
    });

    testWidgets(
      'loading-more footer renders a skeleton row, not a spinner',
      (tester) async {
        final db = FakeFirebaseFirestore();
        final now = DateTime(2026, 3, 28, 12);
        await _seed(db, 'g1', [
          for (var i = 0; i < kCrossGroupActivityPageSize; i++)
            _activity(
              'a$i',
              'Actor-$i',
              'created an event',
              at: now.subtract(Duration(minutes: i)),
            ),
        ]);
        final service = _PendingAfterFirstService(db);
        await tester.pumpWidget(
          _app(
            groups: [_group('g1', 'Trip A')],
            service: service,
            prefs: await prefs(),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(CircularProgressIndicator), findsNothing);

        final scrollable = find.byType(Scrollable).last;
        for (
          var i = 0;
          i < 30 && find.byType(SkeletonLoader).evaluate().isEmpty;
          i++
        ) {
          await tester.drag(scrollable, const Offset(0, -250));
          await tester.pump();
        }

        expect(find.byType(SkeletonLoader), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);

        service.gate.complete();
        await tester.pumpAndSettle();
      },
    );
  });

  group('PR5: PaperBackdrop rollout (#490 D-c)', () {
    testWidgets(
      'wraps body content in the shared PaperBackdrop — covers both the '
      'bottom-nav tab and the routed /activity entry',
      (tester) async {
        final db = FakeFirebaseFirestore();
        await _seed(db, 'g1', [_activity('a1', 'Alice', 'created an event')]);
        await tester.pumpWidget(
          _app(
            groups: [_group('g1', 'Trip A')],
            service: GroupActivityService.withFirestore(db),
            prefs: await prefs(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(PaperBackdrop), findsOneWidget);
      },
    );
  });

  group('History row deep-links (#840)', () {
    testWidgets('expense_added routes to the event ledger', (tester) async {
      final db = FakeFirebaseFirestore();
      await _seed(db, 'g1', [
        _activity(
          'e1',
          'Alice',
          'added an expense',
          type: 'expense_added',
          metadata: const {
            'eventId': 'ev1',
            'eventName': 'Beach Trip',
            'amountFils': 500,
            'currency': 'OMR',
          },
        ),
      ]);
      await tester.pumpWidget(
        _app(
          groups: [_group('g1', 'Trip A')],
          service: GroupActivityService.withFirestore(db),
          prefs: await prefs(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(_richContaining('added an expense in Beach Trip'));
      await tester.pumpAndSettle();

      expect(find.text('EventLedger:g1/ev1'), findsOneWidget);
    });

    testWidgets('expense_edited routes to the event ledger', (tester) async {
      final db = FakeFirebaseFirestore();
      await _seed(db, 'g1', [
        _activity(
          'e1',
          'Alice',
          'edited an expense',
          type: 'expense_edited',
          metadata: const {
            'eventId': 'ev1',
            'eventName': 'Beach Trip',
            'amountFils': 500,
            'currency': 'OMR',
          },
        ),
      ]);
      await tester.pumpWidget(
        _app(
          groups: [_group('g1', 'Trip A')],
          service: GroupActivityService.withFirestore(db),
          prefs: await prefs(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(_richContaining('edited an expense in Beach Trip'));
      await tester.pumpAndSettle();

      expect(find.text('EventLedger:g1/ev1'), findsOneWidget);
    });

    testWidgets(
      'expense_deleted routes to the event activity feed (audit trail), '
      'not the ledger',
      (tester) async {
        final db = FakeFirebaseFirestore();
        await _seed(db, 'g1', [
          _activity(
            'e1',
            'Alice',
            'deleted an expense',
            type: 'expense_deleted',
            metadata: const {'eventId': 'ev1', 'eventName': 'Beach Trip'},
          ),
        ]);
        await tester.pumpWidget(
          _app(
            groups: [_group('g1', 'Trip A')],
            service: GroupActivityService.withFirestore(db),
            prefs: await prefs(),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(_richContaining('deleted an expense in Beach Trip'));
        await tester.pumpAndSettle();

        expect(find.text('EventActivity:g1/ev1'), findsOneWidget);
      },
    );

    testWidgets(
      'event_deleted routes to group detail (target event is gone)',
      (tester) async {
        final db = FakeFirebaseFirestore();
        await _seed(db, 'g1', [
          _activity(
            'e1',
            'Alice',
            'deleted an event',
            type: 'event_deleted',
            metadata: const {'eventId': 'ev1', 'eventName': 'Beach Trip'},
          ),
        ]);
        await tester.pumpWidget(
          _app(
            groups: [_group('g1', 'Trip A')],
            service: GroupActivityService.withFirestore(db),
            prefs: await prefs(),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(_richContaining('deleted Beach Trip'));
        await tester.pumpAndSettle();

        expect(find.text('GroupDetail:g1'), findsOneWidget);
      },
    );

    testWidgets(
      'group_settlement routes to group settle-up with no query params '
      '(no ?memberId= in v1, even with recipientId in metadata)',
      (tester) async {
        final db = FakeFirebaseFirestore();
        await _seed(db, 'g1', [
          _activity(
            's1',
            'Alice',
            'recorded a settlement',
            type: 'group_settlement',
            metadata: const {
              'amount': '12.5',
              'fromUserId': 'uid0',
              'toUserId': 'uid1',
              'fromName': 'Alice',
              'toName': 'Bob',
              'recipientId': 'uid1',
            },
          ),
        ]);
        await tester.pumpWidget(
          _app(
            groups: [_group('g1', 'Trip A')],
            service: GroupActivityService.withFirestore(db),
            prefs: await prefs(),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Iconsax.wallet_3));
        await tester.pumpAndSettle();

        expect(find.text('GroupSettleUp:g1?'), findsOneWidget);
      },
    );

    testWidgets('member_joined routes to group detail (unchanged)', (
      tester,
    ) async {
      final db = FakeFirebaseFirestore();
      await _seed(db, 'g1', [
        _activity('m1', 'Bob', 'joined', type: 'member_joined'),
      ]);
      await tester.pumpWidget(
        _app(
          groups: [_group('g1', 'Trip A')],
          service: GroupActivityService.withFirestore(db),
          prefs: await prefs(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(_richContaining('joined the group'));
      await tester.pumpAndSettle();

      expect(find.text('GroupDetail:g1'), findsOneWidget);
    });

    testWidgets('member_left routes to group detail (unchanged)', (
      tester,
    ) async {
      final db = FakeFirebaseFirestore();
      await _seed(db, 'g1', [
        _activity('m1', 'Bob', 'left', type: 'member_left'),
      ]);
      await tester.pumpWidget(
        _app(
          groups: [_group('g1', 'Trip A')],
          service: GroupActivityService.withFirestore(db),
          prefs: await prefs(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(_richContaining('left the group'));
      await tester.pumpAndSettle();

      expect(find.text('GroupDetail:g1'), findsOneWidget);
    });

    testWidgets('an unknown/default activity type routes to group detail', (
      tester,
    ) async {
      final db = FakeFirebaseFirestore();
      await _seed(db, 'g1', [
        _activity(
          'z1',
          'Zed',
          'did something weird',
          type: 'something_unrecognized',
        ),
      ]);
      await tester.pumpWidget(
        _app(
          groups: [_group('g1', 'Trip A')],
          service: GroupActivityService.withFirestore(db),
          prefs: await prefs(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(_richContaining('did something weird'));
      await tester.pumpAndSettle();

      expect(find.text('GroupDetail:g1'), findsOneWidget);
    });

    group('forged/absent eventId metadata degrades to group detail, never '
        'an ErrorWidget (#840)', () {
      final forgedValues = <String, Object>{
        'int': 42,
        'bool': true,
        'map': {'x': 1},
        'empty string': '',
      };

      for (final forged in forgedValues.entries) {
        testWidgets(
          'expense_added with eventId as ${forged.key} falls back to group '
          'detail',
          (tester) async {
            final db = FakeFirebaseFirestore();
            await _seed(db, 'g1', [
              _activity(
                'e1',
                'Alice',
                'added an expense',
                type: 'expense_added',
                metadata: {
                  'eventId': forged.value,
                  'eventName': 'Beach Trip',
                  'amountFils': 500,
                  'currency': 'OMR',
                },
              ),
            ]);
            await tester.pumpWidget(
              _app(
                groups: [_group('g1', 'Trip A')],
                service: GroupActivityService.withFirestore(db),
                prefs: await prefs(),
              ),
            );
            await tester.pumpAndSettle();

            await tester.tap(
              _richContaining('added an expense in Beach Trip'),
            );
            await tester.pumpAndSettle();

            expect(find.byType(ErrorWidget), findsNothing);
            expect(find.text('GroupDetail:g1'), findsOneWidget);
          },
        );
      }

      testWidgets(
        'expense_added with an absent eventId falls back to group detail',
        (tester) async {
          final db = FakeFirebaseFirestore();
          await _seed(db, 'g1', [
            _activity(
              'e1',
              'Alice',
              'added an expense',
              type: 'expense_added',
              metadata: const {
                'eventName': 'Beach Trip',
                'amountFils': 500,
                'currency': 'OMR',
              },
            ),
          ]);
          await tester.pumpWidget(
            _app(
              groups: [_group('g1', 'Trip A')],
              service: GroupActivityService.withFirestore(db),
              prefs: await prefs(),
            ),
          );
          await tester.pumpAndSettle();

          await tester.tap(_richContaining('added an expense in Beach Trip'));
          await tester.pumpAndSettle();

          expect(find.byType(ErrorWidget), findsNothing);
          expect(find.text('GroupDetail:g1'), findsOneWidget);
        },
      );
    });
  });

  group('back-affordance (#666)', () {
    testWidgets('cold direct-entry (showBack) back button routes to /home', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          groups: const [],
          service: _ThrowingService(),
          prefs: await prefs(),
          showBack: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Back'), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Go to Activity'), findsOneWidget); // /home
    });

    testWidgets('tab default (showBack:false) shows no back affordance', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          groups: const [],
          service: _ThrowingService(),
          prefs: await prefs(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('History'), findsOneWidget);
      expect(find.byTooltip('Back'), findsNothing);
    });
  });
}
