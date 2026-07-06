# #996 — Smart-forward back-stack fix (parent+leaf double push)

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** After a §2 smart-forward into the sole open event's hub, Back must land on the group overview (then the origin surface) — restoring the only path to `+ New event`, Add member, invite/share, and group settings for 1-open-event groups.

**Architecture:** At the two smart-forward sites, push the `/group/:gid` ancestor imperatively BEFORE pushing the hub, so the imperative stack is `[origin…, GroupDetail, EventHub]`. No route-tree change, no redirect, no new screen.

**Tech Stack:** Flutter, go_router 13 (imperative push), existing flat-router test harnesses.

---

## Problem (verified live on device, v1.8.0 build 33)

`docs/plans/2026-07-05-falaj-pr5-ia-spec.md` §2 shipped on the assumption:

> Forwarding to `/group/:gid/event/:eid` (nested) means GoRouter materializes the `/group/:gid` ancestor, so `canPop()==true` at the hub and the hub's bare `if(canPop())pop()` reaches the group overview.

**The materialization claim is false for imperative `context.push`.** go_router pushes ONLY the leaf page (`ImperativeRouteMatch`); ancestors materialize on `go`/location-based navigation, not on push. Verified on a Pixel 9 Pro XL: home row → hub → back → **home**. The §2 test plan asserted the pushed *location* only, never post-forward *back* behavior — and both test harnesses use FLAT mini-routers (hub as a top-level route), which cannot express ancestor semantics, so nothing could have caught it.

Composed with #245 (every new group auto-seeds ONE open event named after the group), every fresh group:
- always opens as its seeded event (home row `home_screen.dart:207`, search group results `search_results.dart:145` — same §2 contract; the journeys ticket pushes the hub directly too),
- has an unreachable group overview — the sole home of `+ New event` (`group_detail_screen.dart:218/:322` are the only two entries to `/group/:gid/create-event`), Add member, invite/share, settings, insights,
- therefore can never gain a second event: the trap is permanent. (The one exception: the post-create share prompt's `pushReplacement('/group/${group.id}')`.)

## Decision D1 — parent+leaf double push, NOT `context.go`, NOT a hub breadcrumb

At each smart-forward site, replace the single leaf push with:

```dart
context.push('/group/$gid');
context.push('/group/$gid/event/${soleEvent.eventId}');
```

- **vs `go(hubPath)`:** `go` swaps the whole stack — from home it discards the shell (scroll lost, acceptable) but from **search it destroys the search screen and its query**; back from the overview would exit to `/home` via the GroupDetail PopScope instead of returning to results. Double push preserves the origin surface under the stack for BOTH callers: back walks hub → overview → origin.
- **vs hub breadcrumb affordance:** additive UI (l10n, design sign-off) and back would STILL skip the overview — fixes reachability, not the broken contract. Rejected as scope.
- The forward still lands on the hub in one tap (friction #2 win intact); the overview is a back-press away, exactly the contract §2 claimed.

## Fix sites (exhaustive — `soleEvent` greps to exactly these two files in `lib/`)

1. `lib/features/home/screens/home_screen.dart:207` — home groups-list row.
2. `lib/features/search/widgets/search_results.dart:145` — search group-result row (forwards "via the #900 §2 smart-forward CONTRACT verbatim" per its own comment; must stay in lockstep).

The `else` branches (multi/zero open events → single `push('/group/$gid')`) are UNTOUCHED. The journeys-ticket hub push (`home_screen.dart:805`) and event search-result push (`search_results.dart:173`) are event-INTENT taps, not group taps — untouched (documented non-goal; after this fix the group row/result provides the overview path).

## Back-chain verification (all read from code, worktree @72ce1830)

- Hub back button: `event_command_center.dart:223` — `if (GoRouter.of(context).canPop()) pop()`. With `[…, GroupDetail, EventHub]`, pop → GroupDetail. ✓
- GroupDetail: `group_detail_screen.dart:65-73` — `PopScope(canPop: false, onPopInvokedWithResult: … router.canPop() ? router.pop() : router.go('/home'))`. Mid-stack, `canPop()==true` → pop → origin (home shell state / search results preserved). Cold deep-link to `/group/:gid` unchanged (sole page → `go('/home')`, #243). ✓
- No `PopScope` added anywhere; hub stays nested; `appRouteRedirect` untouched; no `state.extra`/`goNamed`/`Navigator.push`; both pushed locations remain path-encoded and cold-linkable (deep-link inventory byte-stable).

## Callsite classification

`openByGroup`/`allResolved` reads: INBOUND (decide-only), unchanged. The two pushes: OUTBOUND navigation, path-encoded. No data write path, no money, no schema, no rules — Gate category is **routing** only.

## Known accepted edges

- Double-tap on a row already stacks duplicate pushes today (2 hubs); after the fix a double-tap stacks 2×(overview+hub). Same failure class, same recovery (extra backs). No debounce added (YAGNI; none exists today).
- The intermediate GroupDetail page mounts beneath the hub at forward time — one extra widget build with live providers the overview would run anyway on back. The forward transition visually plays only the top (hub) page.
- Predictive-back on GroupDetail is already non-animated app-wide (`PopScope(canPop:false)`, #243 accepted).

## Test plan (regression tests FIRST — RED before the fix)

Extend the two existing §2 suites in place (flat harnesses express imperative-stack order faithfully — identical semantics to the real nested tree for pushes):

1. `test/features/home/home_group_row_navigation_test.dart` — new case **(f)**: sole-open-event forward, then ONE `router.pop()` → `GroupOverview:g1` visible, `EventHub:` absent; a second pop → back on `HomeScreen`. Requires `_buildApp` to expose its `GoRouter` (return-record or out-param refactor of the helper — test-only change). New case **(g)**: two-open-events tap (else branch) still lands on overview with NO hub beneath — one pop returns straight to `HomeScreen` (guards against double-pushing the else branch).
2. `test/features/search/search_navigation_test.dart` — same pair for the group-result forward: pop from hub → `GroupOverview:g1`; pop again → back on the SEARCH screen with the query preserved (asserts the `go`-alternative would have been a regression).

RED expectation before the fix: (f)/search-(f) fail with pop landing on `HomeScreen`/search directly (no `GroupOverview:g1`). (g) cases pass before AND after (behavior guard).

Full gates: `flutter analyze` clean; `flutter test test/features/home/ test/features/search/`; full `flutter test` before PR.

---

## Gate round 1 — PASS (rubric 0 P1/0 P2/3 P3; adversary 0 P1/1 P2/2 P3) — union folded in

- **[P2·adversary] Nested-harness variant:** the flat `_buildApp` harness can't prove the double push composes to exactly 3 pages under the production NESTED tree. Add one nested-router back-chain test (marker builders, `/group/:gid` with child `event/:eid`, HomeScreen at `/home`): tap → hub, pop → overview marker, pop → home. Defense-in-depth against a go_router patch-version change in ancestor semantics — the exact blind-spot class that produced #996.
- **[P3·rubric] Label fix:** existing home cases are (a)–(d) + a separately-titled cold-deep-link test (no "(e)"); new cases are labelled (e), (f), (g-nested) accordingly.
- **[P3·rubric] Stale comment:** `event_command_center.dart:221-222` claims "ancestors are materialized on any nav" — the exact false premise behind #996. Task 3 corrects it (back reaches the overview because the ancestor is imperatively pushed, not materialized).
- **[P3·rubric] Line drift:** journeys-ticket push is `home_screen.dart:797-799` (not :805).
- **[P3·adversary] Intentional single-push comments:** annotate the journeys-ticket (`home_screen.dart:797-799`) and event-search-result (`search_results.dart:173`) pushes as DELIBERATELY single-push (event-intent taps; back returns to origin) so a later reader doesn't "fix" them into double-push.
- **[P3·adversary] Why case (a) still passes:** post-fix the overview page sits offstage beneath the opaque hub; `find.text` skips offstage by default, so `findsNothing` still holds. Stated here so an implementer doesn't "repair" a correct test.

## Task 1: RED tests — home row back-chain

**Files:** Modify `test/features/home/home_group_row_navigation_test.dart`

1. Refactor `_buildApp` → returns `({Widget app, GoRouter router})` (or accept a `GoRouter` built by a new `_buildRouter()`); update existing call sites mechanically.
2. Add case (f) and case (g) as specified above.
3. Run: `flutter test test/features/home/home_group_row_navigation_test.dart` → (f) FAILS (pop lands on HomeScreen), (g) PASSES, (a)–(e) PASS.

## Task 2: RED tests — search result back-chain

**Files:** Modify `test/features/search/search_navigation_test.dart` (helper already returns the router).

1. Add the forward-then-pop pair.
2. Run: `flutter test test/features/search/search_navigation_test.dart` → new forward-pop case FAILS, rest PASS. Capture RED output for the PR body.

## Task 3: Fix both sites (GREEN)

**Files:** Modify `lib/features/home/screens/home_screen.dart:207`, `lib/features/search/widgets/search_results.dart:145`

Insert `context.push('/group/$gid');` immediately before the existing hub push at each site (comment: ancestor push so Back reaches the overview — #996; go_router imperative push does NOT materialize ancestors).

Run: both test files → ALL PASS. Then `flutter analyze` and `bash tool/check_theme_purity.sh` (touched lib/ widgets), then full `flutter test`.

## Task 4: Commit + PR

Single commit: `fix(nav): push /group/:gid ancestor on smart-forward so Back reaches the group overview` — body carries `Closes #996` (full delivery) + RED evidence. PR through `/automerge` (Gate-category: routing).
