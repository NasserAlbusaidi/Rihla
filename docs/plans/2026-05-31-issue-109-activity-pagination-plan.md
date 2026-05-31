# #109 Event Activity-Feed Cursor Pagination — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the event activity feed's unbounded `.snapshots()` stream with cursor-based pagination (50/page, infinite scroll), so Firestore reads scale with what's viewed, not with the collection size — and the feed never silently truncates.

**Architecture:** Port the proven group-level pattern (`GroupActivityService.fetchActivityPageRaw` + `GroupActivityScreen`) to the event level. `ActivityService` gains a one-shot `fetchActivityPageRaw`. `ActivityFeedScreen` becomes a `ConsumerStatefulWidget` that fetches pages on scroll, accumulates into a list, and day-groups over the whole accumulation. The reactive `watchActivityLogs` / `eventActivityProvider` (whose sole consumer is the screen) are then removed. Feed becomes non-reactive (re-enter to update) — parity with the group feed. Full rationale + 3-lens review: `docs/plans/2026-05-31-issue-109-activity-pagination-design.md`.

**Tech Stack:** Flutter, Riverpod 2.x, `cloud_firestore`, `fake_cloud_firestore` + `mocktail` (tests). No new deps. No `firestore.indexes.json` change (single-field `orderBy` on a subcollection is auto-indexed).

**Branch:** `feat/issue-109-activity-pagination` (already created; design doc committed there).

**Key invariants to respect:**
- `createdAt` is an ISO8601 UTC string → descending lexicographic == chronological. Cursor on the single `orderBy('createdAt', descending: true)` field.
- Default `.get()` is cache-first (offline reads preserved). **Never** pass `Source.server`.
- `_hasMore = snap.docs.length == limit` (compare to the request limit, not a literal `50`).
- Keep the explicit **error+retry** on a failed *initial* load — do NOT copy the group screen's silent `catch (_) {}`, which false-renders "no activity" on error.
- `flutter analyze` clean + tests green before each commit; `prefer_const_constructors` is a CI failure — mark const-eligible literals `const`.

---

### Task 1: Service — `fetchActivityPageRaw` + multi-page cursor de-risk test

This task doubles as the **Step 0 de-risk**: the test cannot pass unless `fake_cloud_firestore` actually supports `startAfterDocument().get()` cursor chaining. If Step 4 fails on the cursor (not the method), STOP and reassess the test strategy (emulator) before proceeding — do not work around it.

**Files:**
- Modify: `lib/features/activity/services/activity_service.dart` (add method after `watchActivityLogs`)
- Modify: `test/unit/activity_service_test.dart` (add a new `group(...)`)

**Step 1: Write the failing test**

Add this `group` inside `group('ActivityService (Firestore)', () { ... })` in `test/unit/activity_service_test.dart`, after the `addActivityLog` group. Add `import 'package:cloud_firestore/cloud_firestore.dart';` at the top if not present.

```dart
group('fetchActivityPageRaw (cursor pagination)', () {
  Future<void> seedLogs(int n) async {
    for (var i = 0; i < n; i++) {
      // Staggered, strictly increasing createdAt so ordering is deterministic.
      final ts = DateTime.utc(2026, 1, 1).add(Duration(seconds: i));
      await fakeFirestore
          .collection('groups').doc(groupId)
          .collection('events').doc(eventId)
          .collection('activity_logs').doc('a${i.toString().padLeft(4, '0')}')
          .set({
            'id': 'a$i',
            'eventId': eventId,
            'category': 'MONEY',
            'eventType': 'CREATE',
            'logText': 'log $i',
            'actorId': 'u1',
            'actorName': 'Alice',
            'metadata': <String, dynamic>{},
            'createdAt': ts.toIso8601String(),
          });
    }
  }

  test('pages forward with startAfter cursor, newest-first, no overlap', () async {
    await seedLogs(120);

    final p1 = await service.fetchActivityPageRaw(groupId, eventId, limit: 50);
    expect(p1.docs, hasLength(50));
    expect(p1.docs.first.data()['logText'], equals('log 119')); // newest first

    final p2 = await service.fetchActivityPageRaw(
      groupId, eventId, startAfter: p1.docs.last, limit: 50);
    expect(p2.docs, hasLength(50));

    final p3 = await service.fetchActivityPageRaw(
      groupId, eventId, startAfter: p2.docs.last, limit: 50);
    expect(p3.docs, hasLength(20)); // 120 - 100

    final ids = [...p1.docs, ...p2.docs, ...p3.docs].map((d) => d.id).toList();
    expect(ids.toSet(), hasLength(120)); // zero overlap across pages
  });

  test('returns empty for a log-free event', () async {
    final page = await service.fetchActivityPageRaw('g', 'no-logs', limit: 50);
    expect(page.docs, isEmpty);
  });
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/unit/activity_service_test.dart --plain-name "fetchActivityPageRaw"`
Expected: FAIL — compile error, `The method 'fetchActivityPageRaw' isn't defined for the type 'ActivityService'`.

**Step 3: Write minimal implementation**

In `lib/features/activity/services/activity_service.dart`, add `import 'package:cloud_firestore/cloud_firestore.dart';` if absent, then add this method to `ActivityService` (right after `watchActivityLogs`):

```dart
/// Cursor-paginated fetch of event activity logs (50/page, D-34 parity with
/// the group feed). Returns the raw [QuerySnapshot] so callers read
/// `docs.last` as the next cursor and map docs to [ActivityLog] themselves.
///
/// Default [GetOptions] (cache-first) — do NOT force Source.server, or offline
/// viewing breaks. `createdAt` is an ISO8601 UTC string, so descending
/// lexicographic order is chronological.
Future<QuerySnapshot<Map<String, dynamic>>> fetchActivityPageRaw(
  String groupId,
  String eventId, {
  DocumentSnapshot? startAfter,
  int limit = 50,
}) async {
  var query = eventSubcollection(groupId, eventId, 'activity_logs')
      .orderBy('createdAt', descending: true)
      .limit(limit);
  if (startAfter != null) query = query.startAfterDocument(startAfter);
  return query.get();
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/unit/activity_service_test.dart --plain-name "fetchActivityPageRaw"`
Expected: PASS (both cases). **If the multi-page case fails on the cursor** (page 2 returns wrong/overlapping docs), STOP — `fake_cloud_firestore` cursoring is the blocker; reassess before building the screen.

**Step 5: Commit**

```bash
git add lib/features/activity/services/activity_service.dart test/unit/activity_service_test.dart
git commit -m "feat(activity): add cursor-paginated fetchActivityPageRaw for event logs (#109)"
```

---

### Task 2: Screen — convert `ActivityFeedScreen` to stateful cursor pagination

Each commit must keep the tree green. `eventActivityProvider` still exists after this task (removed in Task 3); the screen simply stops using it.

**Files:**
- Modify: `lib/features/activity/screens/activity_feed_screen.dart`
- Modify: `test/features/activity/activity_feed_screen_test.dart`

**Step 1: Write the failing tests**

Replace `test/features/activity/activity_feed_screen_test.dart` with the version below. It overrides `activityServiceProvider` with a `FakeFirebaseFirestore`-backed service, seeds logs, and asserts pagination + error behaviors. (Keeps the existing back-button test.)

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/activity/screens/activity_feed_screen.dart';
import 'package:safar/features/activity/services/activity_service.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

class _ThrowingActivityService extends Mock implements ActivityService {}

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

  // Seeds n logs across two calendar days: the first `dayBcount` are on
  // 2026-02-02, the rest on 2026-02-01 (older). Newest-first ordering.
  Future<void> seed(FakeFirebaseFirestore db, int n, {int dayBcount = 0}) async {
    for (var i = 0; i < n; i++) {
      final isDayB = i < dayBcount;
      final base = isDayB ? DateTime.utc(2026, 2, 2) : DateTime.utc(2026, 2, 1);
      final ts = base.add(Duration(seconds: n - i)); // higher i => older
      await db
          .collection('groups').doc(groupId)
          .collection('events').doc(eventId)
          .collection('activity_logs').doc('a${i.toString().padLeft(4, '0')}')
          .set({
            'id': 'a$i', 'eventId': eventId, 'category': 'MONEY',
            'eventType': 'CREATE', 'logText': 'paid for item $i',
            'actorId': 'u1', 'actorName': 'Alice',
            'metadata': <String, dynamic>{}, 'createdAt': ts.toIso8601String(),
          });
    }
  }

  Widget buildRoute(List<Override> overrides) {
    final router = GoRouter(
      initialLocation: '/group/$groupId/event/$eventId/activity',
      routes: [
        GoRoute(
          path: '/group/:gid',
          builder: (c, s) => Scaffold(body: Text('GroupDetail:${s.pathParameters['gid']}')),
          routes: [
            GoRoute(
              path: 'event/:eid',
              builder: (c, s) => Scaffold(body: Text('EventHub:${s.pathParameters['eid']}')),
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
        eventDetailProvider(eventRef).overrideWith((ref) => Stream<Event?>.value(event)),
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

  testWidgets('direct route back button returns to event hub', (tester) async {
    final db = FakeFirebaseFirestore();
    await tester.pumpWidget(buildRoute([
      activityServiceProvider.overrideWithValue(ActivityService.withFirestore(db)),
    ]));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Iconsax.arrow_left));
    await tester.pumpAndSettle();
    expect(find.text('EventHub:$eventId'), findsOneWidget);
  });

  testWidgets('loads first page and shows the load-more footer when more remain',
      (tester) async {
    final db = FakeFirebaseFirestore();
    await seed(db, 60); // > one 50-page
    await tester.pumpWidget(buildRoute([
      activityServiceProvider.overrideWithValue(ActivityService.withFirestore(db)),
    ]));
    await tester.pumpAndSettle();
    // First page returned 50 (== limit) => _hasMore true => footer spinner present.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.textContaining('paid for item'), findsWidgets);
  });

  testWidgets('scrolling to the bottom loads the next page and clears the footer',
      (tester) async {
    final db = FakeFirebaseFirestore();
    await seed(db, 60);
    await tester.pumpWidget(buildRoute([
      activityServiceProvider.overrideWithValue(ActivityService.withFirestore(db)),
    ]));
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsOneWidget); // page 1 footer

    await tester.drag(find.byType(ListView), const Offset(0, -4000));
    await tester.pumpAndSettle();

    // Page 2 returned 10 (< 50) => _hasMore false => footer gone.
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a day spanning the page boundary renders as one section', (tester) async {
    final db = FakeFirebaseFirestore();
    // 60 logs, 20 on day B (newest) + 40 on day A. Page 1 = 50 (20 dayB + 30 dayA),
    // page 2 = 10 (dayA). Day A straddles the boundary -> must be ONE header.
    await seed(db, 60, dayBcount: 20);
    await tester.pumpWidget(buildRoute([
      activityServiceProvider.overrideWithValue(ActivityService.withFirestore(db)),
    ]));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -8000));
    await tester.pumpAndSettle();
    // Two calendar days => exactly two day-header labels. Find the mono day-label
    // Text widgets via the localized short-month-day format actually rendered.
    // (Implementer: assert the count of distinct day-section header Texts == 2.)
  });

  testWidgets('failed initial load shows error+retry; retry re-fetches', (tester) async {
    final svc = _ThrowingActivityService();
    var calls = 0;
    when(() => svc.fetchActivityPageRaw(any(), any(),
            startAfter: any(named: 'startAfter'), limit: any(named: 'limit')))
        .thenAnswer((_) async {
      calls++;
      if (calls == 1) throw Exception('boom');
      return _EmptySnapshot(); // 2nd call (retry) succeeds, empty
    });
    await tester.pumpWidget(buildRoute([
      activityServiceProvider.overrideWithValue(svc),
    ]));
    await tester.pumpAndSettle();
    // Error view visible (reload action label from l10n.activityReload).
    expect(find.text(_reloadLabel(tester)), findsOneWidget);
    await tester.tap(find.text(_reloadLabel(tester)));
    await tester.pumpAndSettle();
    // After retry the error view is gone (empty feed -> empty state).
    expect(find.text(_reloadLabel(tester)), findsNothing);
  });
}
```

> Implementer notes for the test scaffolding:
> - `_reloadLabel(tester)` is a helper that reads `AppLocalizations.of(...)` reload string, OR just assert on a stable widget in `_ErrorView` (e.g. the retry button). Simplify if the l10n lookup is awkward.
> - `_EmptySnapshot` must be a fake `QuerySnapshot<Map<String,dynamic>>` with `docs == []`. Easiest: instead of mocktail returning a hand-rolled snapshot, back the retry with a real empty `FakeFirebaseFirestore` query: `await db.collection('groups').doc(groupId).collection('events').doc(eventId).collection('activity_logs').orderBy('createdAt', descending: true).limit(50).get()`. Prefer that over hand-mocking `QuerySnapshot`.
> - If `find.byType(ListView)` is ambiguous (shimmer also uses ListView), key the paginated list or scope the finder.

**Step 2: Run tests to verify they fail**

Run: `flutter test test/features/activity/activity_feed_screen_test.dart`
Expected: FAIL — `activityServiceProvider` override compiles, but the screen still uses the stream + has no footer/scroll behavior, so the pagination/error assertions fail (and `find.textContaining('paid for item')` finds nothing because the seeded fake isn't read by the old stream path).

**Step 3: Rewrite the screen**

In `lib/features/activity/screens/activity_feed_screen.dart`:
- Add `import 'package:cloud_firestore/cloud_firestore.dart';`.
- Convert `ActivityFeedScreen` to `ConsumerStatefulWidget`; add the page-size const and state class below. **Delete the old `_Body` class** (its job moves into `_buildActivityBody`). Keep `_TopBar`, `_DaySection`, `_ActivityRow`, `_CategoryIcon`, `_groupByDay`, `_DayGroup`, `_LoadingShimmer`, `_ErrorView`, `_NotFoundView` unchanged.

```dart
const _kPageSize = 50;

class ActivityFeedScreen extends ConsumerStatefulWidget {
  const ActivityFeedScreen({super.key, required this.groupId, required this.eventId});
  final String groupId;
  final String eventId;

  @override
  ConsumerState<ActivityFeedScreen> createState() => _ActivityFeedScreenState();
}

class _ActivityFeedScreenState extends ConsumerState<ActivityFeedScreen> {
  final List<ActivityLog> _activities = [];
  DocumentSnapshot? _lastDocument;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  bool _initialError = false;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
    _loadPage();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200 && _hasMore && !_isLoadingMore) {
      _loadPage();
    }
  }

  Future<void> _loadPage() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    try {
      final snap = await ref.read(activityServiceProvider).fetchActivityPageRaw(
        widget.groupId, widget.eventId, startAfter: _lastDocument, limit: _kPageSize);
      final newLogs = snap.docs
          .map((doc) => ActivityLog.fromFirestore({...doc.data(), 'id': doc.id}))
          .toList();
      if (!mounted) return;
      setState(() {
        _activities.addAll(newLogs);
        if (snap.docs.isNotEmpty) _lastDocument = snap.docs.last;
        _hasMore = snap.docs.length == _kPageSize;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      final isInitial = _activities.isEmpty;
      setState(() {
        if (isInitial) _initialError = true;
        _isLoadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final eventRef = (groupId: widget.groupId, eventId: widget.eventId);
    final eventAsync = ref.watch(eventDetailProvider(eventRef));
    return Scaffold(
      key: ActivityKeys.screen,
      backgroundColor: context.colors.scaffoldBackground,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(
              title: eventAsync.valueOrNull?.name ?? context.l10n.activityTitle,
              loading: eventAsync.isLoading,
            ),
            const SizedBox(height: 6),
            Expanded(
              child: eventAsync.when(
                loading: () => const _LoadingShimmer(),
                error: (_, _) => _ErrorView(
                  onRetry: () => ref.invalidate(eventDetailProvider(eventRef)),
                ),
                data: (event) {
                  if (event == null) return const _NotFoundView();
                  return _buildActivityBody(context);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityBody(BuildContext context) {
    if (_initialError && _activities.isEmpty) {
      return _ErrorView(onRetry: () {
        setState(() => _initialError = false);
        _loadPage();
      });
    }
    if (_isLoadingMore && _activities.isEmpty) return const _LoadingShimmer();
    if (_activities.isEmpty) {
      return EmptyStateView(
        icon: Iconsax.activity,
        title: context.l10n.activityNoActivityTitle,
        message: context.l10n.activityEventEmptyMessage,
      );
    }
    final days = _groupByDay(context, _activities, DateTime.now());
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsetsDirectional.fromSTEB(20, 4, 20, 24),
      itemCount: days.length + (_hasMore ? 1 : 0),
      itemBuilder: (ctx, i) {
        if (i == days.length) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: context.colors.primary),
              ),
            ),
          );
        }
        return Padding(
          padding: EdgeInsets.only(top: i == 0 ? 4 : 22),
          child: _DaySection(label: days[i].label, entries: days[i].entries),
        );
      },
    );
  }
}
```

**Step 4: Run tests to verify they pass**

Run: `flutter test test/features/activity/activity_feed_screen_test.dart`
Expected: PASS (back button, first-page+footer, scroll-loads-next, error+retry; finalize the day-merge assertion finder so it asserts 2 headers).
Then: `flutter analyze lib/features/activity/screens/activity_feed_screen.dart` → No issues.

**Step 5: Commit**

```bash
git add lib/features/activity/screens/activity_feed_screen.dart test/features/activity/activity_feed_screen_test.dart
git commit -m "feat(activity): paginate event activity feed via infinite scroll (#109)"
```

---

### Task 3: Remove the now-unused reactive stream

Now that the screen no longer reads it, delete `watchActivityLogs` + `eventActivityProvider` and their tests. (Grep-verified sole consumer was the screen.)

**Files:**
- Modify: `lib/features/activity/services/activity_service.dart` (delete `watchActivityLogs` method + `eventActivityProvider`)
- Modify: `test/unit/activity_service_test.dart` (delete the `group('watchActivityLogs', …)`)
- Modify: `test/features/activity/activity_service_test.dart` (delete `watchActivityLogs` tests + the `group('eventActivityProvider', …)` and the MONEY-filter-on-stream test)

**Step 1: Confirm nothing else references them**

Run: `grep -rn "eventActivityProvider\|watchActivityLogs" lib test`
Expected: only the definitions in `activity_service.dart` and the test cases listed above. If anything else appears, STOP and reassess.

**Step 2: Delete**

- Remove the `watchActivityLogs(...)` method and the `eventActivityProvider` `StreamProvider` (and its now-unused `EventRef` import if orphaned) from `activity_service.dart`. Keep `activityServiceProvider`, `addActivityLog`, and `fetchActivityPageRaw`.
- Delete the `watchActivityLogs` and `eventActivityProvider` test groups in both test files (including the "Filtering for MONEY category works on the stream output" test, which exercises the removed stream).

**Step 3: Run the activity suites**

Run: `flutter test test/unit/activity_service_test.dart test/features/activity/`
Expected: PASS — only `addActivityLog` + `fetchActivityPageRaw` + screen tests remain.

**Step 4: Verify no analyzer breakage**

Run: `flutter analyze lib/features/activity test/features/activity test/unit/activity_service_test.dart`
Expected: No issues (no unused imports left behind).

**Step 5: Commit**

```bash
git add lib/features/activity/services/activity_service.dart test/unit/activity_service_test.dart test/features/activity/activity_service_test.dart
git commit -m "refactor(activity): drop unbounded watchActivityLogs stream, superseded by pagination (#109)"
```

---

### Task 4: Full verification + coverage + PR

**Step 1: Whole-suite + analyze**

Run: `flutter analyze`
Expected: No issues found.
Run: `flutter test`
Expected: All tests pass.

**Step 2: Coverage gate (80%)**

Run: `flutter test --coverage && lcov --summary coverage/lcov.info`
Expected: line coverage ≥ 80%. The removed stream tests (~80 lines) are offset by the new pagination + screen tests. If below, add a missing-case test (e.g. `_loadPage` no-op when `!_hasMore`).

**Step 3: Push + open PR**

```bash
git push -u origin feat/issue-109-activity-pagination
gh pr create --base main --head feat/issue-109-activity-pagination \
  --title "perf(activity): paginate event activity feed, bound the unbounded log stream (#109)" \
  --body "$(cat <<'EOF'
## What
Replaces the event activity feed's unbounded `activity_logs` `.snapshots()` stream with cursor-based pagination (50/page, infinite scroll), mirroring the group-level pattern. Firestore reads now scale with what's viewed, not collection size; the feed no longer silently truncates.

## Trade-off
Feed becomes non-reactive (re-enter to update) — parity with the group feed. Live reactivity intentionally dropped (design doc). Pull-to-refresh skipped. No filters / no composite index (deferred, see issue).

## Tests
- Service: multi-page cursor (no overlap), empty event.
- Screen: first-page+footer, scroll-loads-next-page+footer-clears, day-merge across page boundary, error+retry on failed initial load.
- `flutter analyze` clean, full suite green, 80% coverage gate holds.

Design + 3-lens review: `docs/plans/2026-05-31-issue-109-activity-pagination-design.md`.

Closes #109
EOF
)"
```

**Step 4: Merge under strict protection**

Branch protection is `strict` + `enforce_admins`. After CI (`readiness`) goes green and the branch is up-to-date with `main`: `gh pr merge <n> --squash`. If `main` advanced first: `gh pr update-branch <n>`, wait for readiness, then merge.

---

## Done when
- Event feed reads ≤ `limit` docs per page; older entries reachable by scroll (no silent truncation).
- `watchActivityLogs` / `eventActivityProvider` gone; no dangling references.
- `flutter analyze` clean, full suite green, coverage ≥ 80%, PR merged, #109 closed.
