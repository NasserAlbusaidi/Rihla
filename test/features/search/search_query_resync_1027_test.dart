import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/search/keys/search_keys.dart';
import 'package:safar/features/search/screens/search_screen.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// #1027 — a `/search?q=…` deep link that lands on the ALREADY-MOUNTED search
/// screen must reseed the field + results. GoRouter reuses the page (its
/// `pageKey` is path-based, query-blind), so the screen is reconciled in place
/// via `didUpdateWidget` rather than remounted — the resync has to live there.
const _uid = 'test-user-id';

Group _makeGroup(String id, String name) => Group(
  id: id,
  name: name,
  inviteCode: 'ABC123',
  createdBy: _uid,
  memberIds: const [_uid],
  currency: 'OMR',
  createdAt: DateTime(2026, 1, 1),
);

Event _makeEvent({
  required String id,
  required String groupId,
  required String name,
}) => Event(
  id: id,
  name: name,
  type: EventType.trip,
  groupId: groupId,
  createdBy: _uid,
  participantIds: const [_uid],
  participantNames: const {_uid: 'Traveler'},
  modules: const EventModules(),
  createdAt: DateTime(2026, 1, 2),
);

List<Override> _baseOverrides({
  required List<Group> groups,
  Map<String, List<Event>> eventsByGroup = const {},
}) => [
  currentUserIdProvider.overrideWithValue(_uid),
  userGroupsProvider.overrideWith((ref) => Stream.value(groups)),
  for (final group in groups)
    groupEventsProvider(group.id).overrideWith(
      (ref) => Stream.value(eventsByGroup[group.id] ?? const <Event>[]),
    ),
];

Widget _app(Widget home, List<Override> overrides) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(
    theme: AppTheme.lightTheme,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  ),
);

String _fieldText(WidgetTester tester) =>
    tester.widget<TextField>(find.byKey(SearchKeys.field)).controller!.text;

/// Rebuildable harness so a test can push a new (or identical) `query` prop into
/// a mounted [SearchScreen] deterministically — mirrors GoRouter reconciling the
/// same page with a fresh `SearchScreen(query: …)`.
class _Rebuilder extends StatefulWidget {
  const _Rebuilder({required this.initialQuery});
  final String? initialQuery;
  @override
  State<_Rebuilder> createState() => _RebuilderState();
}

class _RebuilderState extends State<_Rebuilder> {
  late String? _q = widget.initialQuery;
  void pushQuery(String? q) => setState(() => _q = q);
  @override
  Widget build(BuildContext context) => SearchScreen(query: _q);
}

void main() {
  testWidgets(
    '#1027: a new /search?q= deep link on the MOUNTED screen reseeds field + results',
    (tester) async {
      final group = _makeGroup('g1', 'Desert Crew');
      // Prod page shape (app_router.dart): pageBuilder + CustomTransitionPage
      // keyed by the path-based state.pageKey — the reconcile-in-place mechanism
      // under test.
      final router = GoRouter(
        initialLocation: '/search',
        routes: [
          GoRoute(
            path: '/search',
            pageBuilder: (_, state) => CustomTransitionPage(
              key: state.pageKey,
              child: SearchScreen(query: state.uri.queryParameters['q']),
              transitionsBuilder: (_, _, _, child) => child,
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: _baseOverrides(
            groups: [group],
            eventsByGroup: {
              'g1': [_makeEvent(id: 'e1', groupId: 'g1', name: 'Wadi Shab Trip')],
            },
          ),
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: router,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Mounted with no query: blank field, no result yet.
      expect(_fieldText(tester), isEmpty);
      expect(find.text('Wadi Shab Trip'), findsNothing);

      // A new deep link lands on the already-mounted screen (go = replace; the
      // path-based pageKey keeps the same page → reconcile-in-place).
      router.go('/search?q=Wadi');
      await tester.pumpAndSettle();

      expect(_fieldText(tester), 'Wadi');
      expect(find.text('Wadi Shab Trip'), findsOneWidget);
    },
  );

  testWidgets(
    '#1027 guard: a rebuild re-supplying the SAME query does not clobber typing',
    (tester) async {
      final group = _makeGroup('g1', 'Desert Crew');
      const harness = _Rebuilder(initialQuery: 'Desert');

      await tester.pumpWidget(_app(harness, _baseOverrides(groups: [group])));
      await tester.pumpAndSettle();
      expect(_fieldText(tester), 'Desert');

      // User keeps typing (URL is NOT updated per keystroke by design).
      await tester.enterText(find.byKey(SearchKeys.field), 'Desert Crew');
      await tester.pumpAndSettle();
      expect(_fieldText(tester), 'Desert Crew');

      // Parent rebuilds with the SAME route query — must not overwrite typing.
      final state = tester.state<_RebuilderState>(find.byType(_Rebuilder));
      state.pushQuery('Desert');
      await tester.pumpAndSettle();

      expect(_fieldText(tester), 'Desert Crew');
    },
  );

  testWidgets(
    '#1027 guard: a genuinely changed query on the mounted screen reseeds',
    (tester) async {
      final group = _makeGroup('g1', 'Desert Crew');
      const harness = _Rebuilder(initialQuery: 'Desert');

      await tester.pumpWidget(_app(harness, _baseOverrides(groups: [group])));
      await tester.pumpAndSettle();
      expect(_fieldText(tester), 'Desert');

      final state = tester.state<_RebuilderState>(find.byType(_Rebuilder));
      state.pushQuery('Alps');
      await tester.pumpAndSettle();

      expect(_fieldText(tester), 'Alps');
    },
  );
}
