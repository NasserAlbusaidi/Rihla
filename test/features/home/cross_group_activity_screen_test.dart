import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import 'package:safar/features/groups/models/group_activity_log_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/home/providers/dashboard_providers.dart';
import 'package:safar/features/home/screens/cross_group_activity_screen.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:safar/shared/widgets/r_amount.dart';
import 'package:safar/shared/widgets/skeleton_loader.dart';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

GroupActivityLog _makeActivity(
  String id,
  String actorName,
  String description, {
  String type = 'event_created',
  Map<String, dynamic> metadata = const {},
}) => GroupActivityLog(
  id: id,
  type: type,
  actorId: 'uid0',
  actorName: actorName,
  description: description,
  metadata: metadata,
  timestamp: DateTime(2026, 3, 28),
);

CrossGroupActivityEntry _makeEntry(
  GroupActivityLog log,
  String groupName,
  String groupId, {
  String currency = 'OMR',
}) => (log: log, groupName: groupName, groupId: groupId, currency: currency);

Widget _buildTestApp(Widget widget, {List<Override> overrides = const []}) {
  final router = GoRouter(
    initialLocation: '/activity',
    routes: [
      GoRoute(path: '/activity', builder: (ctx, state) => widget),
      GoRoute(
        path: '/group/:id',
        builder: (ctx, state) =>
            Scaffold(body: Text('GroupDetail:${state.pathParameters['id']}')),
      ),
    ],
  );

  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  );
}

/// Minimal overrides to prevent unrelated providers from throwing.
List<Override> _baseOverrides({
  required AsyncValue<List<CrossGroupActivityEntry>> activityOverride,
}) => [
  crossGroupActivityProvider.overrideWith((ref) => activityOverride),
  userGroupsProvider.overrideWith((ref) => Stream.value([])),
  crossGroupHomeBalanceProvider.overrideWith(
    (ref) => const AsyncValue.data((
      balance: (
        byCurrency: <CurrencyBalance>[],
        groupCount: 0,
        isLoading: false,
      ),
      partial: false,
    )),
  ),
  groupBalancesProvider.overrideWith(
    (ref, groupId) => const AsyncValue.data((
      balances: <String, List<UserBalance>>{},
      totalSpent: <String, Decimal>{},
      eventCount: 0,
      perEventBreakdown: <String, Map<String, Map<String, Decimal>>>{},
      memberNames: <String, String>{},
      memberRawNames: <String, String>{},
    )),
  ),
  currentUserIdProvider.overrideWithValue('test-user-id'),
];

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('CrossGroupActivityScreen', () {
    testWidgets('shows "Activity" title', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          const CrossGroupActivityScreen(),
          overrides: _baseOverrides(
            activityOverride: const AsyncValue.data([]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Activity'), findsOneWidget);
    });

    testWidgets('shows empty state when no activity', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          const CrossGroupActivityScreen(),
          overrides: _baseOverrides(
            activityOverride: const AsyncValue.data([]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No activity yet'), findsOneWidget);
    });

    testWidgets('shows a skeleton (not a blank screen) while loading (#488)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTestApp(
          const CrossGroupActivityScreen(),
          overrides: _baseOverrides(
            activityOverride: const AsyncValue.loading(),
          ),
        ),
      );
      // One frame only — the skeleton shimmer never settles, so pumpAndSettle
      // would hang.
      await tester.pump();

      expect(find.byType(SkeletonLoader), findsOneWidget);
    });

    testWidgets('shows activity entries with group name', (tester) async {
      final log1 = _makeActivity('a1', 'Alice', 'created an event');
      final log2 = _makeActivity(
        'a2',
        'Bob',
        'joined the group',
        type: 'member_joined',
      );

      final entries = [
        _makeEntry(log1, 'Trip A', 'g1'),
        _makeEntry(log2, 'Trip B', 'g2'),
      ];

      await tester.pumpWidget(
        _buildTestApp(
          const CrossGroupActivityScreen(),
          overrides: _baseOverrides(activityOverride: AsyncValue.data(entries)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Trip A'), findsOneWidget);
      expect(find.text('Trip B'), findsOneWidget);
      expect(find.textContaining('created an event'), findsOneWidget);
      expect(find.textContaining('joined the group'), findsOneWidget);
    });

    testWidgets(
      'settlement entry uses the wallet glyph (#160) in a top-aligned row '
      '(#159)',
      (tester) async {
        final log = _makeActivity(
          's1',
          'Alice',
          'recorded a settlement',
          type: 'group_settlement',
        );

        await tester.pumpWidget(
          _buildTestApp(
            const CrossGroupActivityScreen(),
            overrides: _baseOverrides(
              activityOverride: AsyncValue.data([
                _makeEntry(log, 'Trip A', 'g1'),
              ]),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // #160: money glyph, not a bare chevron.
        expect(find.byIcon(Iconsax.wallet_3), findsOneWidget);
        expect(find.byIcon(Iconsax.arrow_right_3), findsNothing);

        // #159: the icon's row top-aligns so it pins to the first line.
        final row = tester.widget<Row>(
          find
              .ancestor(
                of: find.byIcon(Iconsax.wallet_3),
                matching: find.byType(Row),
              )
              .first,
        );
        expect(row.crossAxisAlignment, CrossAxisAlignment.start);
      },
    );

    testWidgets(
      'settlement amount stored as a stringified Decimal renders (#380) — '
      'the cross-group feed must not drop the string-encoded `amount` that '
      'GroupSettleUpScreen.logGroupEvent writes',
      (tester) async {
        // GroupSettleUpScreen writes metadata: {'amount': amount.toString()},
        // i.e. a stringified Decimal — NOT a num. The old `is num` coercion
        // dropped it, so the row rendered no amount at all.
        final log = _makeActivity(
          's1',
          'Alice',
          'recorded a settlement',
          type: 'group_settlement',
          metadata: const {'amount': '12.5'},
        );

        await tester.pumpWidget(
          _buildTestApp(
            const CrossGroupActivityScreen(),
            overrides: _baseOverrides(
              activityOverride: AsyncValue.data([
                _makeEntry(log, 'Trip A', 'g1'),
              ]),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final amounts = tester
            .widgetList<RAmount>(find.byType(RAmount))
            .toList();
        expect(amounts, hasLength(1));
        // Parsed straight from the string, no double round-trip / forced 3dp.
        expect(amounts.single.value, Decimal.parse('12.5'));
      },
    );

    testWidgets(
      'string-encoded amount on a USD group renders at 2dp precision (#380)',
      (tester) async {
        final log = _makeActivity(
          's2',
          'Bob',
          'recorded a settlement',
          type: 'group_settlement',
          metadata: const {'amount': '20.25'},
        );

        await tester.pumpWidget(
          _buildTestApp(
            const CrossGroupActivityScreen(),
            overrides: _baseOverrides(
              activityOverride: AsyncValue.data([
                _makeEntry(log, 'USD Trip', 'g9', currency: 'USD'),
              ]),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final amounts = tester
            .widgetList<RAmount>(find.byType(RAmount))
            .toList();
        expect(amounts, hasLength(1));
        expect(amounts.single.value, Decimal.parse('20.25'));
        expect(amounts.single.currency, 'USD');
      },
    );

    testWidgets(
      'metadata.currency wins over the entry (group) currency; legacy rows '
      'fall back (#382 PR-4)',
      (tester) async {
        final stamped = _makeActivity(
          's3',
          'Alice',
          'recorded a settlement',
          type: 'group_settlement',
          metadata: const {'amount': '20.25', 'currency': 'USD'},
        );
        final legacy = _makeActivity(
          's4',
          'Bob',
          'recorded a settlement',
          type: 'group_settlement',
          metadata: const {'amount': '7.750'},
        );

        await tester.pumpWidget(
          _buildTestApp(
            const CrossGroupActivityScreen(),
            overrides: _baseOverrides(
              activityOverride: AsyncValue.data([
                _makeEntry(stamped, 'Oman Trip', 'g1'), // entry currency OMR
                _makeEntry(legacy, 'Oman Trip', 'g1'),
              ]),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final amounts = tester
            .widgetList<RAmount>(find.byType(RAmount))
            .toList();
        expect(amounts, hasLength(2));
        expect(amounts.map((a) => a.currency), containsAll(['USD', 'OMR']));
      },
    );

    testWidgets('shows error state on error', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          const CrossGroupActivityScreen(),
          overrides: _baseOverrides(
            activityOverride: AsyncValue.error(
              Exception('Network error'),
              StackTrace.empty,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Could not load activity'), findsOneWidget);
    });

    testWidgets('back button pops route', (tester) async {
      // Build with a preceding route so we can verify a pop happens.
      final router = GoRouter(
        initialLocation: '/home',
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
            builder: (ctx, state) => ProviderScope(
              overrides: _baseOverrides(
                activityOverride: const AsyncValue.data([]),
              ),
              child: const CrossGroupActivityScreen(),
            ),
          ),
          GoRoute(
            path: '/group/:id',
            builder: (ctx, state) => Scaffold(
              body: Text('GroupDetail:${state.pathParameters['id']}'),
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: _baseOverrides(
            activityOverride: const AsyncValue.data([]),
          ),
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to /activity
      await tester.tap(find.text('Go to Activity'));
      await tester.pumpAndSettle();

      // Verify we are on the activity screen
      expect(find.text('Activity'), findsOneWidget);

      // Tap back button
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      // Should be back on home screen
      expect(find.text('Go to Activity'), findsOneWidget);
      expect(find.text('Activity'), findsNothing);
    });
  });
}
