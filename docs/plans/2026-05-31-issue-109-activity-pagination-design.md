# Design — #109: bound the event activity feed with cursor pagination

**Date:** 2026-05-31 · **Issue:** #109 (P3, perf/tech-debt) · **Status:** approved, pre-implementation

## Problem (verified against `main` @ `170b9d0`)

`ActivityFeedScreen` watches `eventActivityProvider` → `ActivityService.watchActivityLogs`, which
does `eventSubcollection(groupId, eventId, 'activity_logs').orderBy('createdAt', descending: true).snapshots()`
with **no `.limit()`** (`lib/features/activity/services/activity_service.dart:37`). Every expense
create writes an `activity_logs` doc (`ExpenseService._addExpenseCreatedActivity`), so the
subcollection grows unbounded for long-lived events and the **entire** set re-materialises on every
change. The group-level feed already caps reads (`watchRecentActivity` `.limit(5)`,
`fetchActivityPage` `.limit(50)`); the event-level feed has neither bound nor a load-more affordance.

Severity is genuinely P3: the screen is pushed on-demand (`/group/:gid/event/:eid/activity`), the
listener lives only while it's on the stack, and `ListView.builder` virtualises rendering — so the
cost is Firestore **reads/memory**, not jank.

**Sole consumer:** `ActivityFeedScreen` is the *only* reader of `eventActivityProvider` /
`watchActivityLogs` in `lib/` (grep-verified). How we bound the feed is therefore a self-contained
change with no other callers to migrate.

## Decision

**Approach A — port the proven group-level cursor-pagination pattern to the event level.**
Mirror `GroupActivityScreen` / `GroupActivityService.fetchActivityPageRaw`: a stateful screen that
cursor-fetches **50 per page** on scroll (prefetch within 200 px of the bottom), accumulating into an
in-memory list and day-grouping over the whole accumulation on each build.

Locked knobs:
- **Page size 50**, matching the group feed (D-34).
- **No filter chips.** The event feed has none today; the group feed's All/Settlements/Events/Members
  chips are group-specific. YAGNI.
- **No `where('category', …)` / no composite index.** The MONEY-only server filter is explicitly
  optional in the issue and is deferred until a MONEY-only view actually ships.
- **Re-enter to update (not pull-to-refresh).** See reactivity note below.

### Rejected alternatives
- **B — hybrid: live `.limit(50)` stream + cursor "load older" below.** Keeps the recent window
  live but requires merging a reactive stream window with a static older-pages list, boundary
  dedup, and day-grouping across both. Complexity not justified for a P3 historical log.
- **C — bare `.limit(50)` on the stream, no pagination.** Silently truncates the feed at 50 with no
  way to see older entries. Explicitly rejected by the issue ("no silent truncation").

### Reactivity trade-off (accepted)
Today the feed is **live** (`.snapshots()`): a co-traveler's new activity appears automatically while
you watch. Approach A is a one-shot `Future` fetch — no open listener — so new activity written while
the screen is mounted won't appear until you **re-enter** the screen (which re-fetches page 1). This
is accepted: the event *ledger* is the live surface users watch; the activity feed is a historical
record; and the **group** feed already behaves non-reactively, so this makes the two consistent rather
than introducing a new oddity. Pull-to-refresh (`RefreshIndicator`, already used in `home_screen` and
`group_detail_screen`) was considered and deliberately skipped to keep the screen clean.

## Step 0 — de-risk before building (do this first)

The whole approach assumes `fake_cloud_firestore` correctly supports
`.orderBy(…).limit(…).startAfterDocument(cursor).get()` **cursor chaining across pages**. The
existing `test/unit/group_activity_service_test.dart` only ever fetches **page 1** — it never passes
`startAfter`, so multi-page cursoring with the fake is **unproven** in this repo. Before building the
screen, write the service-level multi-page test (seed > 100 logs, fetch page 1, then page 2 with
`startAfter: page1.docs.last`, assert non-overlapping IDs). If the fake can't cursor, the test
strategy changes (emulator-backed test, or assert pagination at the screen level differently) — better
to learn that in 15 minutes than after the screen is built.

## Design

### Service — `ActivityService` (`lib/features/activity/services/activity_service.dart`)
- **Add** `fetchActivityPageRaw(String groupId, String eventId, {DocumentSnapshot? startAfter, int limit = 50})`
  returning `Future<QuerySnapshot<Map<String, dynamic>>>`, mirroring
  `GroupActivityService.fetchActivityPageRaw`:
  ```
  var query = eventSubcollection(groupId, eventId, 'activity_logs')
      .orderBy('createdAt', descending: true)
      .limit(limit);
  if (startAfter != null) query = query.startAfterDocument(startAfter);
  return query.get();
  ```
  (Return the raw `QuerySnapshot` so the **screen** reads `docs.last` as the next cursor and maps docs
  to `ActivityLog` itself — the service does **not** map. Same split the group screen/service use
  (`group_activity_screen.dart:90-95`).)
- **Remove** `watchActivityLogs` and the `eventActivityProvider` `StreamProvider` (sole consumer is
  the screen, which no longer uses them). Removing them keeps the dead-stream out of the tree
  (project dead-code hygiene). Their tests are migrated to cover `fetchActivityPageRaw` (below).

**Ordering / index:** `createdAt` is stored as a `DateTime.now().toUtc().toIso8601String()` string
(`addActivityLog`), so descending lexicographic order is correct chronological order, and
`startAfterDocument` cursors correctly on the single `orderBy` field. A single-field `orderBy` on a
fixed subcollection path needs **no composite index** (the current `.snapshots()` query already runs
indexless; `firestore.indexes.json` has no `activity_logs` entry). No index change.

**Offline (no regression):** persistence is on (`firebase_config.dart`: `persistenceEnabled`,
`CACHE_SIZE_UNLIMITED`). The default `GetOptions` on `.get()` is cache-first-then-server, so an
offline open still returns cached activity — same offline reachability the `.snapshots()` stream gave.
Do **not** pass `Source.server` (that would break offline viewing).

### Screen — `ActivityFeedScreen` (`lib/features/activity/screens/activity_feed_screen.dart`)
Convert `ConsumerWidget` → `ConsumerStatefulWidget`, porting `_GroupActivityScreenState` mechanics:
- State: `final List<ActivityLog> _activities`, `DocumentSnapshot? _lastDocument`, `bool _hasMore = true`,
  `bool _isLoadingMore = false`, `bool _initialError = false`, `late ScrollController _scrollController`.
- `initState`: create controller with `_onScroll` listener, call `_loadPage()`. `dispose`: dispose controller.
- `_onScroll`: if `pixels >= maxScrollExtent - 200 && _hasMore && !_isLoadingMore` → `_loadPage()`.
- `_loadPage()`: guard on `_isLoadingMore || !_hasMore`; `setState(_isLoadingMore = true)`; call
  `fetchActivityPageRaw(groupId, eventId, startAfter: _lastDocument, limit: kPageSize)`; map docs →
  `ActivityLog`; on success `setState`: append, `_lastDocument = snap.docs.last` (only if non-empty),
  `_hasMore = snap.docs.length == kPageSize` (compare to the **request limit**, not a hardcoded `50`,
  so the bound can't silently drift). `kPageSize = 50`.
  - *Exact-multiple behavior (accepted):* when the total is an exact multiple of `kPageSize`, the last
    full page leaves `_hasMore == true`, so one extra fetch runs that returns 0 docs → `_hasMore`
    becomes false and the footer spinner clears. One wasted empty read + a brief footer flash; this
    matches the shipped group-screen behavior and is acceptable for a P3 feed.
- **Error handling (deliberate deviation from the group template):** the group screen swallows load
  errors silently, which renders the "no activity" empty state on a *failed* first load — a bug we do
  **not** copy. Exact logic:
  ```
  } catch (_) {
    if (!mounted) return;
    final isInitial = _activities.isEmpty;
    setState(() { if (isInitial) _initialError = true; _isLoadingMore = false; });
  }
  ```
  In `build`: `if (_initialError && _activities.isEmpty) return _ErrorView(onRetry: () { setState(() => _initialError = false); _loadPage(); });`. This preserves today's explicit error+retry (which
  otherwise disappears with the StreamProvider). A failure on a *subsequent* page just stops the
  spinner and keeps the already-loaded rows (no crash, no false-empty).
- Reuse the existing event-specific presentation **untouched**: `_TopBar`, `_DaySection`,
  `_ActivityRow`, `_CategoryIcon` (MONEY/GEAR/DOCS), `_groupByDay`, `_LoadingShimmer`, `EmptyStateView`.
- **List + footer ownership:** the current stateless `_Body` (which builds its own `ListView`) is
  retired; the `ListView.builder` moves **into** a State method (it needs `_scrollController`,
  `_activities`, `_hasMore`) — mirroring `GroupActivityScreen._buildBody`. `itemCount = days.length +
  (_hasMore ? 1 : 0)`; the item at index `days.length` is a trailing `CircularProgressIndicator`;
  all other indices render `_DaySection`. Initial load (`_isLoadingMore && _activities.isEmpty`) shows
  `_LoadingShimmer`; loaded-but-empty shows the `EmptyStateView`.
- The event **title** keeps watching `eventDetailProvider(eventRef)` reactively (a separate, cheap
  provider) — only the activity *log* loses reactivity.

**Day-grouping across page boundaries:** `_groupByDay` runs over the **entire** accumulated
`_activities` list on every build (not per-page), so a day that straddles a page boundary (e.g. the
tail of "MAY 30" continuing into page 2) merges into a single day section automatically. The
`startAfterDocument` cursor guarantees pages don't overlap, so no dedup is required.

## Testing (RED → GREEN)

- **[Step 0 / de-risk] Multi-page cursor test** (`test/unit/activity_service_test.dart`,
  FakeFirebaseFirestore): seed > 100 logs; fetch page 1 (`limit: 50`) → assert exactly 50 docs in
  `createdAt`-desc order; fetch page 2 with `startAfter: page1.docs.last` → assert the next 50 with
  **zero ID overlap**; fetch a third page to confirm cursor chaining; assert a final short page sets
  the stop condition. **This proves `fake_cloud_firestore` cursors before any screen work** — if it
  fails here, switch to an emulator-backed test before building. Returns empty for a log-free event.
  Replaces the removed `watchActivityLogs` cases.
- **Screen widget test** (`test/features/activity/activity_feed_screen_test.dart` — mirror
  `test/features/groups/group_activity_screen_test.dart`): override `activityServiceProvider` with a
  `FakeFirebaseFirestore`-backed `ActivityService.withFirestore`; seed > 50 logs; pump; assert the
  first page renders + the `_hasMore` footer spinner shows; `drag` the `ListView` to the bottom and
  `pumpAndSettle`; assert page-2 rows appear (no duplicates). Add a forced-failure case (throwing
  service) asserting the **error+retry view** on a failed initial load and that retry re-fetches. The
  existing minimal back-button test stays; the `eventActivityProvider` override is removed (gone).
- **Day-merge across the page boundary:** seed so one calendar day straddles the 50-doc boundary
  (e.g. 30 on 2026-05-30 + 30 on 2026-05-31); after page 2 loads, assert the boundary day renders as
  **one** `_DaySection`, not two — proving `_groupByDay` runs over the whole accumulated list.
- `flutter analyze` clean; full activity test dirs green. **Coverage:** the removed `watchActivityLogs`
  stream tests (~80 lines across `test/unit/activity_service_test.dart` +
  `test/features/activity/activity_service_test.dart`) are offset by the new pagination tests — run
  `flutter test --coverage && lcov --summary coverage/lcov.info` after implementation and confirm the
  80 % gate holds before opening the PR.

## Out of scope / follow-ups
- MONEY-only server filter + `(category, createdAt)` composite index — deferred (issue: optional).
- Pull-to-refresh — skipped (re-enter covers the rare live-update case).
- Live reactivity on the event feed — intentionally dropped (parity with group feed).

## Files touched
- `lib/features/activity/services/activity_service.dart` (add `fetchActivityPageRaw`; remove
  `watchActivityLogs` + `eventActivityProvider`)
- `lib/features/activity/screens/activity_feed_screen.dart` (Consumer → ConsumerStateful + pagination)
- `test/unit/activity_service_test.dart`, `test/features/activity/activity_service_test.dart`,
  `test/features/activity/activity_feed_screen_test.dart` (migrate stream tests → pagination tests)
