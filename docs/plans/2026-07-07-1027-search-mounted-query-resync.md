# #1027 — Mounted Search screen ignores a new `?q=` deep-link query

**Issue:** `search: mounted screen ignores new q deep-link query` (P3, ios, qa).
**Branch:** `fix/1027-search-mounted-query-resync` (worktree `Rihla-1027`, from `origin/main`).

## Problem

`/search?q=…` seeds the field on **cold** entry but not when Search is **already mounted**.
Opening `rihla:///search?q=one` on top of a live `/search` leaves the field blank and the
pre-query guidance showing.

## Root cause (verified against source, not memory)

**How `/search?q=…` reaches go_router (corrected — NOT `deep_link_service.dart`).**
`DeepLinkService.openJoinLink` (`deep_link_service.dart`) routes **only JOIN links** — a
`rihla:///search?q=…` URI fails `parseJoinLink` (host ≠ `join`) and is dropped, never routed. No
`lib/` code produces a `/search?q=…` location either (the in-app search button does
`context.push('/search')` — bare, no query — `home_screen.dart:580`). The URL reaches the router via
the **platform native deep-link path**: go_router's default `routeInformationProvider` receives the
OS-delivered `rihla:///search?q=…` and applies `/search?q=…` through `setNewRoutePath`. This is
**empirically confirmed by the issue's own QA evidence** — the cold-open `search-query-one-cold.png`
screenshot shows the field seeded with `one`, which no `lib/` path could produce.
(Native deep-linking is on because Flutter ≥3.24 defaults it on: Android turns it off explicitly
[`AndroidManifest.xml:20` `flutter_deeplinking_enabled=false`], iOS leaves `FlutterDeepLinkingEnabled`
absent → enabled. This contradicts the "off by default" rationale in CLAUDE.md #369 /
`ios_deep_linking_guard_test.dart` — flagged as a separate follow-up, out of scope for this fix.)

**Why the mounted screen drops the new query.**
- Route: `app_router.dart:493-499` → `pageBuilder` builds
  `CustomTransitionPage(key: state.pageKey, child: SearchScreen(query: state.uri.queryParameters['q']))`.
- GoRouter **13.2.5** derives a `GoRoute`'s `pageKey` from the matched **path pattern**, not the
  query string: `match.dart:229` → `pageKey: ValueKey<String>(newMatchedPath)` where
  `newMatchedPath = concatenatePaths(matchedPath, route.path)` (= `/search`). Query params are
  absent from the key.
- So `/search` and `/search?q=one` produce the **identical** `ValueKey('/search')`. When go_router
  applies `/search?q=one` onto the mounted `/search` (`setNewRoutePath`, a replace — whether driven
  by the platform's `routeInformationProvider` for a warm deep link, or an in-app `router.go`), the
  Navigator **reuses the existing page slot** → Flutter reconciles `SearchScreen` in place →
  `didUpdateWidget` fires with the new `widget.query`.
- `_SearchScreenState` (`search_screen.dart:38-95`) has **no `didUpdateWidget`**. `initState`
  reads `widget.query` **once**; the new query is dropped. → the bug.

(Cold entry works because a fresh `initState` reads the seeded query — this is what the QA screenshot
shows. A *pushed* `/search?q=…` would also work — imperative pushes get a unique pageKey → fresh
mount — but nothing pushes a query. Only the replace/reconcile onto a mounted screen with the stable
path-based pageKey loses the query, which is exactly the warm external deep-link the issue reports.)

## Fix

Add `didUpdateWidget` to `_SearchScreenState` that resyncs `_query` + the controller **only when
the route query itself changed** (`oldWidget.query != widget.query`) — never merely when it differs
from the user-typed `_query`. That distinction is the load-bearing guard: a naive
`widget.query != _query` check would clobber in-progress typing every time the parent rebuilt the
screen with an unchanged query.

```dart
@override
void didUpdateWidget(covariant SearchScreen oldWidget) {
  super.didUpdateWidget(oldWidget);
  final incoming = (widget.query ?? '').trim();
  // Resync ONLY when the ROUTE's own query changed (a new /search?q=… landed on
  // the mounted screen — go_router reconciles in place, pageKey is path-based).
  // A parent rebuild that re-supplies the SAME query must never overwrite what
  // the user has since typed, so the guard compares oldWidget.query, not _query.
  if (incoming == (oldWidget.query ?? '').trim()) return;
  _query = incoming;
  _controller.value = TextEditingValue(
    text: incoming,
    selection: TextSelection.collapsed(offset: incoming.length),
  );
}
```

Notes:
- The single `oldWidget.query != widget.query` guard is what prevents the typing-clobber: on a
  spurious rebuild the route query is unchanged → early return → typed text survives. (An earlier
  draft added a second `incoming == _query` short-circuit for cursor-nicety; dropped — it left a
  cosmetic trailing-space edge and the one guard already fully covers the clobber case.)
- `_query = incoming` **before** touching the controller, so the controller's `_onQueryChanged`
  listener sees `next == _query` and does not re-enter `setState` during `didUpdateWidget`.
- No `setState` needed: `didUpdateWidget` is always followed by `build()`, which re-reads `_query`
  into `SearchResults(query: _query)`.
- Semantics = "reflect the route query." A new bare `/search` (empty `q`) after a populated one
  clears the field — the route says empty, the screen reflects empty. That path only fires on a
  genuine navigation (guarded by `oldWidget.query != widget.query`), never on a spurious rebuild.

Single-file change: `lib/features/search/screens/search_screen.dart`. No router, rules, money, or
schema surface touched.

## Classification for the Gate

Touches deep-link-driven behavior (a Gate-listed surface) — run the fresh-context Gate before
implementing even though the diff is one lifecycle method.

## Verification principles (applied)

1. **Callsite classification.** `widget.query` is INBOUND display-only (seeds a `TextEditingController`
   / a display `_query`); it is never persisted. The only writer of `?q=` is the URL, set by
   navigation. No OUTBOUND/write path.
2. **Concrete claims vs code.** `pageKey` derivation read from `go_router-13.2.5/lib/src/match.dart:229`;
   route wiring from `app_router.dart:493-499`; `SearchScreen` lifecycle from `search_screen.dart:38-95`.
   The routing of `/search?q=…` is the **native platform deep-link path** (go_router
   `routeInformationProvider` → `setNewRoutePath`), **not** `deep_link_service.dart` (join-only —
   verified: `openJoinLink`/`parseJoinLink` reject non-`join` hosts). Reachability of the whole
   scenario is anchored on the issue's QA cold-open screenshot, not on a `lib/` citation. All
   verified in-worktree.
3. **One read-path per write-path.** The only reader of the resynced `_query` is
   `SearchResults(query: _query)` (`search_screen.dart:88`) and the controller-bound `TextField`
   (`search_screen.dart:145-147`). Both get the new value from the post-`didUpdateWidget` build.
4. **Fields from the type.** `SearchScreen` has one field: `final String? query`. No others.
5. **Data contract.** `didUpdateWidget(covariant SearchScreen oldWidget)`. Compares
   `(widget.query ?? '').trim()` vs `(oldWidget.query ?? '').trim()`. Writes `_query` (String) and
   `_controller.value` (TextEditingValue with collapsed selection at end).
6. **Arithmetic.** N/A (no money).
7. **Adversarial / orthogonal axis (identity of *when* to sync, not *what*).** Axis-B example: user
   types after a seed, then the parent rebuilds with the **same** query → the typed text must
   survive (guard returns early). This is the failure mode a same-axis "does it reseed?" test would
   miss.

## Test plan (RED → GREEN)

`test/features/search/search_query_resync_1027_test.dart`:

1. **Primary regression (drives the exact prod reconcile).** Router built with the **prod page
   shape** — `pageBuilder` → `CustomTransitionPage(key: state.pageKey, …)`, mirroring
   `app_router.dart`. Cold-open `/search` (blank field), then apply `/search?q=Wadi` on the mounted
   screen via `router.go`. `router.go` routes through the identical `setNewRoutePath` that the
   platform `routeInformationProvider` uses for a warm deep link, so the in-place reconcile is the
   same one prod hits — the platform trigger is not separately simulable in a widget test, but the
   reconcile it causes is. Assert the field now shows `Wadi` and a `Wadi Shab Trip` result renders.
   RED before the fix (field stays blank), GREEN after.
2. **Guard — no clobber (deterministic widget harness).** Mount `SearchScreen(query: 'Desert')`
   inside a rebuildable harness; `enterText` to `'Desert Crew'`; force a parent rebuild with the
   **same** `'Desert'` query. Assert the field still shows `'Desert Crew'` (a naive check would
   reset it to `'Desert'`).
3. **Guard — genuine change reseeds via harness.** Same harness; rebuild with a **different** query
   `'Alps'`. Assert the field shows `'Alps'`.

## Out of scope

- No change to the router/route tree/back-guards/deep-link parsing.
- Full expense search (Option C, deferred).
```
