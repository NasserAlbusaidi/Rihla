# #1192 — go_router 13.2.5 → 14.8.1 Upgrade Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Upgrade go_router `^13.2.0` → `^14.8.1` so the delegate's `popRoute()` consults `PopScope` on sole-route stacks, restoring the two PopScope-bearing #243 cold-entry back guards (`/group/:gid`, `/search`) — and unblocking the #1188/#1191 shell guard — on the device back channel. (Unguarded top-level routes keep standard exit-on-back; see fact 7.)

**Architecture:** Dependency bump + one RED-first regression test pinning the popRoute channel end-to-end. No app code changes expected — the app-side guards are already correct; go_router 13's delegate short-circuits below them.

**Tech Stack:** Flutter 3.41.5 / Dart SDK ^3.10.1, go_router, flutter_test (`tester.binding.handlePopRoute()`), mocked `SystemChannels.platform`.

**Spec:** this document. Gate-category: routing (back guards). Gate result: **round 1 clean** (rubric 0 P1/0 P2/2 P3; orthogonal adversary 0 P1/2 P2/2 P3), 2026-07-12; all P2/P3 resolutions folded in below.

---

## Verified facts (all re-checked against source this session, 2026-07-12)

1. **The hole (go_router 13.2.5, installed source read at `~/.pub-cache/hosted/pub.dev/go_router-13.2.5/lib/src/delegate.dart:54`):** `popRoute()` nulls the root navigator when `!state.canPop()` (sole route), the shell-walker never matches (no GoRouter ShellRoutes in this app — `BottomNavShell` is not router-driven), `onExit` is unused repo-wide (grep: zero hits in `lib/` + `test/`), so it returns `false` → `WidgetsBinding.handlePopRoute` → `SystemNavigator.pop()` → app exits. `PopScope` is never consulted.
2. **The fix (14.8.1 source, fetched and read):** `popRoute()` → `_findCurrentNavigator()` takes `navigatorKey.currentState` **without** the canPop null-out, then `await state.maybePop()` unconditionally → `maybePop` reads the top route's `popDisposition` → `PopScope(canPop:false)` yields `doNotPop` → `onPopInvokedWithResult(false, …)` fires, `maybePop` returns `true`, no exit. Fix landed in **14.6.1** ("Fixed `PopScope`… not handled properly in the Root routes"); 14.8.1 is the last 14.x and adds canPop hardening for empty match lists.
3. **Only breaking change in the 13.2.5→14.8.1 span:** 14.0.0 — `GoRouteData.onExit` gains a `GoRouterState` param. Repo has **zero** `GoRouteData` / `go_router_builder` / `onExit` / `RouteMatchList` / `optionURLReflectsImperativeAPIs` / `topRoute` usage (grepped `lib/`, `test/`, `pubspec.yaml`). Not affected. **Implementation addendum (2026-07-12): 14.0.0 also changed `RouteConfiguration.findMatch(String)` → `findMatch(Uri)` — undocumented in the CHANGELOG, verified by reading `configuration.dart` in both installed versions. Repo impact: 4 call sites in `test/unit/app_router_test.dart` (test-only, internal-API usage), adapted mechanically with `Uri.parse(...)`; assertions unchanged. No lib/ impact (grep: `findMatch` appears nowhere in lib/).**
4. **SDK floor:** 14.6.3 requires Flutter ≥3.22 / Dart ≥3.4. We are on Flutter 3.41.5 / SDK `^3.10.1`. Satisfied.
5. **No transitive dependents:** `dart pub deps -s compact | grep go_router` → only the direct dependency. No version-solve conflict possible from other packages.
6. **Predictive back is OFF on device:** `android:enableOnBackInvokedCallback` absent from `AndroidManifest.xml` → real Android back-presses arrive **exclusively** via the legacy `popRoute` MethodChannel → the hole is live on every device back on a sole route. This is the #1188 QA sighting ("Back from group-detail exited app") and it means PR #1191's shell `PopScope` guard is **inert on-device until this upgrade lands** (its own test comment documents the channel gap — it drives `popDisposition` directly and avoids `handlePopRoute` because 13.x can't pass it).
7. **Affected app surfaces (exhaustive, from grep `PopScope` in `lib/`):**
   - `lib/features/groups/screens/group_detail_screen.dart:65` — `canPop:false` → pop-or-`go('/home')`. Sole-route cold entry (deep link `/group/:gid`): **13.x exits app / 14.x goes home.** The headline fix.
   - `lib/features/search/screens/search_screen.dart:93` — identical shape, `/search` top-level.
   - `lib/features/home/widgets/bottom_nav_shell.dart` (PR #1191, in flight) — `canPop:false` double-back-to-exit guard on `/home` (always sole). 14.x activates it on the device channel.
   - `lib/features/ledger/widgets/expense_editor_body.dart:1113` — `canPop: !_isDirty` dirty guard on **nested** routes (`go`-materialized ancestors ⇒ never sole) → root navigator `canPop()` is true on both versions → behavior unchanged.
   - Unguarded top-level routes (`/splash`, `/create-group`, `/join`, `/join/:code`, `/profile`, `/activity`, `/recover` — enumerated from `app_router.dart:172-511`): no `PopScope` ⇒ sole-route `maybePop` reads `popDisposition == bubble` ⇒ returns false ⇒ same exit path as 13.x. **No behavior change for unguarded screens.**
8. **Other behavioral deltas in the span (assessed, low risk, covered by full suite):** 14.2.5 fixes Android back popping pages in the wrong order — a ShellRoute-only code path; this app has zero go_router ShellRoutes, so it's a no-op here (note: the #996 pins drive imperative `router.pop()`, not the device channel — cite them as pop-semantics coverage, not device-back proof); 14.2.6 fixes `replace`/`pushReplacement` URI when only one match (3 call sites: `lib/features/home/widgets/add_expense_target_sheet.dart:69`, `create_group_screen.dart:255`, `join_group_screen.dart:170,289` — correctness improvement; the cold join→`pushReplacement`→sole `group_detail` path was traced by the Gate adversary: post-join back correctly goes `/home`); 14.7.0 adds URI fragment support (join links carry no fragments); 14.7.1 makes a state getter non-nullable (additive).
8b. **Redirect machinery verified unchanged:** `configuration.dart` `_getRouteLevelRedirect` diffed 13.2.5 vs 14.8.1 — identical index-0 walk, `state.uri == matchList.uri` in both; 14.8.1 only pre-filters to redirect-bearing routes (equivalent). The `app_router.dart:84-89` ancestor-redirect behavior (the `endsWith('/ledger')` guard) is preserved. Its comment names "go_router 13.2.5" — refresh that prose to record re-verification against 14.8.1 (comment-only edit, in scope).
9. **Why not 15/16/17 (latest is 17.3.0):** 15.0.0 makes URLs case-sensitive (breaking — touches deep-link matching), 16.0.0 bundles `GoRouteData` breaking changes, 17.0.0 changes shell-route observer notification. Zero additional value for #1192; each is a separate decision with its own regression surface. Smallest-risk close = last 14.x. One PR, one concern.
10. **No existing test encodes the buggy behavior:** grep `handlePopRoute|SystemNavigator` in `test/` on main → zero hits.

## Merge-order contract (updated after PR #1191's auto-merge review, 2026-07-12)

**This upgrade merges FIRST.** PR #1191 is BLOCKED by its own fresh-context review ([P1]: on 13.2.5 the shell `PopScope` guard never fires on the device popRoute channel — same mechanism as this spec's fact 1 — and its tests hand-call the handler instead of driving `tester.binding.handlePopRoute()`). #1191 gets reworked ON TOP of this upgrade: rebase, switch its test drive to the real channel, refresh RED evidence, new `/automerge` round. Therefore **Task 5 is expected to be SKIPPED** (it applies only in the unlikely case #1191 merged first); note the #1191 rework as a follow-up in this PR's body. Do NOT edit #1191's branch from this PR.

---

### Task 1: RED regression test — popRoute channel on a sole guarded route

**Files:**
- Create: `test/features/groups/group_detail_back_navigation_test.dart` (live convention `*_navigation_test.dart`)

**Step 1: Write the failing test.** Mount the real `GroupDetailScreen` as the **initial** (sole) route and drive the real engine channel. **The mount is load-bearing (Gate finding): `tester.binding.handlePopRoute()` reaches `GoRouterDelegate.popRoute()` ONLY through the `RootBackButtonDispatcher` that `MaterialApp.router(routerConfig: …)` installs.** Any other mount (e.g. a bare `Navigator`) makes `handlePopRoute` consult the `PopScope` directly and go GREEN on 13.2.5 too — a vacuous RED. Copy the harness shape from `test/features/groups/group_detail_navigation_test.dart:148-152`:

```dart
// Overrides: copy the minimal set from an existing GroupDetailScreen widget
// test in test/features/groups/ (groupDetailProvider, groupMembersProvider,
// groupBalancesProvider, groupEventsProvider, groupActivityProvider,
// sharedPreferencesProvider, auth/user providers). Router:
final router = GoRouter(
  initialLocation: '/group/g1',
  routes: [
    GoRoute(path: '/home', builder: (_, _) => const Placeholder()),
    GoRoute(
      path: '/group/:gid',
      builder: (_, state) =>
          GroupDetailScreen(groupId: state.pathParameters['gid']!),
    ),
  ],
);
// MANDATORY mount — routerConfig installs the RootBackButtonDispatcher:
await tester.pumpWidget(
  ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      theme: AppTheme.lightTheme,
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  ),
);
```

Record exits by mocking `SystemChannels.platform` (collect `MethodCall`s where `method == 'SystemNavigator.pop'`), then:

```dart
await tester.binding.handlePopRoute();   // the real device back channel
await tester.pumpAndSettle();
// #1192 contract: the guard must win — no exit, back lands on /home.
expect(popCalls, isEmpty);
expect(router.routerDelegate.currentConfiguration.uri.path, '/home');
```

Two testWidgets: the sole-route cold-entry case above, and a pushed-stack control (`push` the detail on top of `/home`, back pops to `/home`, no exit) proving nested behavior is unchanged.

**Step 2: Run it, verify it fails for the right reason.**

Run: `flutter test test/features/groups/group_detail_back_navigation_test.dart`
Expected: FAIL — `popCalls` has 1 recorded `SystemNavigator.pop` and location is still `/group/g1` (app would have exited; `PopScope` handler never fired). **Save this output verbatim — it is the PR's RED evidence.** The control test should already pass on 13.2.5.

**Step 3: Commit the RED test** (test-first history): `test(routing): pin sole-route back guard on the popRoute channel (#1192)`.

### Task 2: The upgrade

**Files:**
- Modify: `pubspec.yaml:40` — `go_router: ^13.2.0` → `go_router: ^14.8.1`
- Modify: `pubspec.lock` (via pub, never by hand)

**Step 1:** Edit the constraint; run `flutter pub get`. Verify `pubspec.lock` shows `go_router … 14.8.1`.

**Step 2:** Sanity-read the installed source: `~/.pub-cache/hosted/pub.dev/go_router-14.8.1/lib/src/delegate.dart` — `popRoute()` must call `state.maybePop()` via `_findCurrentNavigator()` with no canPop short-circuit.

### Task 3: GREEN

Run: `flutter test test/features/groups/group_detail_back_navigation_test.dart`
Expected: PASS (both tests). If the sole-route test still fails, STOP — re-read the resolved version and the delegate source before touching anything else.

### Task 4: Full verification

- Refresh the version-named comment at `app_router.dart:84-89`: keep the behavioral claim, update the prose to "verified on go_router 14.8.1 (was 13.2.5)" per fact 8b. Comment-only; no logic change.
- `flutter analyze` → clean (watch for new deprecation warnings from 14.x APIs; none expected).
- `flutter test` → full suite green. Pay attention to: `test/unit/app_router_test.dart`, every `*_navigation_test.dart`, #996 push-semantics pins (imperative-pop coverage), #666 dual-mode back tests, expense-editor dirty-guard tests.
- `bash tool/check_theme_purity.sh` (not implicated, but new-file rule).
- Any failure = reconcile per this spec's fact table; if a failure contradicts fact 7/8, STOP and re-open the spec (Gate re-run) rather than patching the test.

### Task 5 (conditional — only if PR #1191 is already merged into the base):

**Files:**
- Modify: `test/features/home/bottom_nav_shell_back_test.dart` — the drive-note comment ("go_router's legacy popRoute() returns handled:false for a first/root route… so that path can't exercise a root-shell guard") is stale under 14.x. Update it, and add ONE test driving `tester.binding.handlePopRoute()` against the shell: first back → exit snackbar visible, `popCalls` empty — the end-to-end device-channel pin for the #1188 guard.
- Do not otherwise touch #1191's tests; their `popDisposition` drive stays valid as the predictive-back-channel mirror.

### Task 6: Commit + PR

```bash
git checkout -b fix/1192-gorouter-14-upgrade
git add -A && git commit   # fix(routing): upgrade go_router to 14.8.1 — popRoute honors PopScope on sole routes (#1192)
# commit BODY must contain: Closes #1192  (squash auto-close reads the commit body)
git push -u origin fix/1192-gorouter-14-upgrade
gh pr create …            # body: summary + Spec: docs/plans/2026-07-12-1192-gorouter-14-upgrade.md + test plan + verbatim RED output
```

No AI attribution. PR routes through `/automerge` (Gate-category: routing ⇒ fresh-context review + refuter). Never raw-merge.

## Out of scope (named follow-ups, not bundled)

- go_router 15/16/17 major hops (case-sensitivity decision needed first).
- Enabling Android predictive back (`enableOnBackInvokedCallback`) — separate UX decision; would add a second live back channel.
- Removing/reworking #1191's guard — it stays; the upgrade activates it.
