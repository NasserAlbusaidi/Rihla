# #1237 — Sibling event-load surfaces get the #358/#1207 no-access state Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Give the three sibling event-load surfaces (ledger, activity feed, recap) the same terminal no-access treatment `EventCommandCenter` got in #1239 (#1207): a Firestore `permission-denied` event listen renders a friendly "no access" state with a Home CTA instead of a generic retry / "not found" view. Simultaneously **extract** the twice-duplicated `_isPermissionDenied` helper and `_NoAccessState` widget into shared primitives (the CLAUDE.md "extract at the 3rd duplication" mandate — this change is the 3rd–5th UI call site).

**Architecture:** Mirror the test-pinned #1239 pattern (`event_command_center.dart:86-94`, itself mirroring `group_detail_screen.dart:96-108`): in each surface's `eventAsync.when(error:)` branch, special-case `permission-denied` → log to Sentry + render a terminal no-access state (no Retry — retrying just re-denies). All other errors keep today's retryable state. `data: event == null` keeps today's not-found state (a deleted event ≠ lost access).

**Tech Stack:** Flutter/Riverpod, `sentry_flutter`, `EmptyStateView`, existing l10n keys (no ARB changes).

**Issue:** #1237 (P3, filed by the #1207 Gate adversary). **Gate category: routing / deep-link landing surface** (same classification as #1239) + a shared extraction that edits two routing surfaces.

---

## Verified context (re-checked against live code 2026-07-14)

### Reachability (traced — determines what's genuine vs. defense-in-depth)
- **Router:** only `EventCommandCenter` (`app_router.dart:349`) and `EventRecapScreen` (`:437`) are directly routed. `LedgerScreen` and `ActivityFeedScreen` are **panels only** — instantiated exclusively inside the hub's `_LazyIndexedStack` (`event_command_center.dart:309`, `:318`), which lives in the hub's `data:` branch. `EventRecapScreen` is used **both** standalone (router, `embedded:false`) and embedded (`:323`, `embedded:true`).
- **The hub shadows the two panels.** All four surfaces watch the SAME `eventDetailProvider(eventRef)`. When it goes `permission-denied`, the hub's `eventAsync.when(error:)` rebuilds to `_NoAccessState` and tears down the whole `_Content` (IndexedStack included) — so a removed member on the hub sees the hub's no-access state; the ledger/activity `eventAsync` error branch is reached only in a transient same-provider frame or a future direct route. **Their fix is consistency + future-proofing (near-dead in prod, covered by tests).**
- **The recap standalone route is genuinely reachable and unshadowed** — a removed member's stale deep link / notification to `/group/:gid/event/:eid/recap` hits `eventDetailProvider` directly. Today it renders `_notFound` → **"Event not found"**, which is misleading (they're not un-found, they're un-authorized). **This is the one real user-facing bug in the set.**

### Current error branches (the exact lines the issue names)
- `ledger_screen.dart:78`: `error: (_, _) => _ErrorState(onRetry: () => ref.invalidate(eventDetailProvider(eventRef)))`. `_ErrorState` (`:516`) = `EmptyStateView(Iconsax.warning_2, ledgerCouldNotLoadEventTitle, ledgerConnectionRetryMessage, commonRetry)`.
- `activity_feed_screen.dart:124`: `error: (_, _) => _ErrorView(onRetry: () => ref.invalidate(eventDetailProvider(eventRef)))`.
- `event_recap_screen.dart:60`: `error: (_, _) => _notFound(context)` → `_wrap(... EmptyStateView(Iconsax.warning_2, eventNotFound, recapEmptyMessage))`.

### Existing duplicates to consolidate
- `group_detail_screen.dart`: private `_isPermissionDenied` (`:1107-1110`, used at `:101` error branch + `:181/:184/:187` #574 staging-denial detection) and `_NoAccessState` (`:1407-1427`). **`FirebaseException` is the ONLY `cloud_firestore` symbol used in this file** (`grep` confirmed) → removing the helper makes `import 'package:cloud_firestore/cloud_firestore.dart';` (`:3`) unused; drop it.
- `event_command_center.dart`: private `_isPermissionDenied` (`:1134`) + `_NoAccessState` (`:1110`), added by #1239. **`FirebaseException` is the ONLY `cloud_firestore` symbol** → drop `import 'package:cloud_firestore/cloud_firestore.dart';` (`:3`). `sentry_flutter` + `dart:async` (`unawaited`) STAY (still used by the migrated error branch).
- A THIRD inline copy lives in `listen_recovery.dart:72` — **out of scope** (it's #997 recovery-loop internals with its own retry semantics, not a no-access UI surface). Noted as an optional follow-up; do NOT touch it here.

### Primitives (verified present)
- l10n: `groupNoAccessTitle` ("You no longer have access"), `groupNoAccessMessage` ("You're no longer a member…"), `groupBackHome` ("Back home") — `app_en.arb:1813/1814/1817`. Reuse; **no ARB keys** (event access IS group membership — the #1239 rationale).
- `EmptyStateView({required icon, required title, required message, actionLabel?, onAction?})` — `empty_state_view.dart:20`.
- `context.spacing` / `context.colors` from `domain_aliases.dart` (`extension AppThemeExtensions on BuildContext`).
- `firebase_core: ^4.6.0` is a direct dep (`FirebaseException` lives here).
- No existing `NoAccessView` / `no_access*` file.
- Existing no-access tests (`group_detail_no_access_test.dart`, `event_hub_no_access_1207_test.dart`) assert on **text** (`'You no longer have access'`, `'Back home'`, `'Retry'`) — private widgets can't be referenced by type — so renaming `_NoAccessState`→`NoAccessView` does NOT break them (verified: no `find.byType(_NoAccessState)`).

## Non-goals (explicit — do NOT expand)
- **The data-provider error paths stay unchanged**: ledger `_DataErrorState` (`:97`, expenses/settlements/members), recap `_dataUnavailable` (`:74`), activity `_loadPage`'s `_initialError` (`:139`). These are separate multi-provider aggregations; #1239 handled only the `eventAsync` branch and the hub converges to no-access anyway. Widening is a distinct follow-up. **Scope = the `eventAsync.when(error:)` branch of each surface, exactly as the issue names.**
- No `listen_recovery.dart` migration (see above).
- No routing / rules / provider / back-guard changes — we add a CTA inside each body only (the back-guard asymmetry #243 is untouched; these panels/routes materialize ancestors via `go`).
- No `SplitMode` / money / schema surface — this is pure display-error routing.

---

### Task 1: Extract the shared primitives (helper + widget)

**Files:**
- Create: `lib/core/utils/firestore_error_utils.dart`
- Create: `lib/shared/widgets/no_access_view.dart`

**Step 1 — helper.** `firestore_error_utils.dart`:
```dart
import 'package:firebase_core/firebase_core.dart';

/// True when [error] is a Firestore `permission-denied` — the caller lost read
/// access (removed from the group / group deleted / un-shared). Such a listen
/// is TERMINAL: retrying just re-denies. Pair with [NoAccessView] (a terminal
/// no-access state, no Retry) instead of a retryable error view.
///
/// Extracted (#1237) from the private copies in group_detail_screen /
/// event_command_center at the 3rd UI duplication.
bool isPermissionDenied(Object error) =>
    error is FirebaseException && error.code == 'permission-denied';
```

**Step 2 — widget.** `no_access_view.dart` (byte-for-byte the body of both existing `_NoAccessState` copies, reusing `groupNoAccess*`):
```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../core/extensions/build_context_l10n.dart';
import '../../core/theme/tokens/domain_aliases.dart';
import 'empty_state_view.dart';

/// Terminal "no access" state (#358/#1207/#1237): a Firestore permission-denied
/// on a group/event read means the caller was removed / lost access. No Retry
/// (retrying just re-denies) — only a Home CTA. Reuses the groupNoAccess* copy
/// (event access IS group membership; no event-specific ARB keys).
class NoAccessView extends StatelessWidget {
  const NoAccessView({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(context.spacing.space24),
          child: EmptyStateView(
            icon: Iconsax.lock,
            title: context.l10n.groupNoAccessTitle,
            message: context.l10n.groupNoAccessMessage,
            actionLabel: context.l10n.groupBackHome,
            onAction: () => GoRouter.of(context).go('/home'),
          ),
        ),
      ),
    );
  }
}
```

**Step 3:** `flutter analyze lib/core/utils/firestore_error_utils.dart lib/shared/widgets/no_access_view.dart` (clean).

### Task 2: Migrate the two existing copies (group_detail, event_command_center)

**Files:** Modify `group_detail_screen.dart`, `event_command_center.dart`.

**group_detail_screen.dart:**
1. Add imports `import '../../../core/utils/firestore_error_utils.dart';` + `import '../../../shared/widgets/no_access_view.dart';`.
2. Delete `import 'package:cloud_firestore/cloud_firestore.dart';` (`:3`) — now unused.
3. `_isPermissionDenied(` → `isPermissionDenied(` at `:101`, `:181`, `:184`, `:187`.
4. `const _NoAccessState()` → `const NoAccessView()` at `:103`.
5. Delete the private `_isPermissionDenied` (`:1107-1110`) and `class _NoAccessState` (`:1407-1427`). Keep `_NotFoundState` (group's, `:1429`).

**event_command_center.dart:**
1. Add the same two imports.
2. Delete `import 'package:cloud_firestore/cloud_firestore.dart';` (`:3`).
3. `_isPermissionDenied(error)` → `isPermissionDenied(error)` (`:89`); `const _NoAccessState()` → `const NoAccessView()` (`:91`). Keep the Sentry + `unawaited` call and `_ErrorState` fallback.
4. Delete the private `_isPermissionDenied` + `class _NoAccessState`.

**Verify:** `flutter analyze lib/features/groups/screens/group_detail_screen.dart lib/features/events/screens/event_command_center.dart` clean (no unused import, no undefined name). Run `flutter test test/features/groups/group_detail_no_access_test.dart test/features/events/event_hub_no_access_1207_test.dart` — **must stay green** (text-based, rename-agnostic) with NO edits; if either goes red, the migration changed rendered text/behavior — stop and reconcile.

### Task 3: RED — the three sibling no-access tests

**Files (create):**
- `test/features/ledger/ledger_no_access_1237_test.dart`
- `test/features/activity/activity_feed_no_access_1237_test.dart`
- `test/features/events/event_recap_no_access_1237_test.dart`

Harness: copy `event_hub_no_access_1207_test.dart`'s router+ProviderScope idiom (a `/home` route → `Text('Home')`, an override-taking factory so Retry can re-listen). Per surface, THREE cases (mirror #1239 exactly):
1. **permission-denied** `eventDetailProvider` override → `find.text('You no longer have access')` present, `find.textContaining('no longer a member')` present, `find.text('Retry')` ABSENT, `find.text('Back home')` present.
2. **Home CTA** → tap `'Back home'` → `pumpAndSettle` → `find.text('Home')` present.
3. **companion non-permission error** (`Exception('blip')`) → the surface's OWN retry state stays: ledger/activity `find.text('Retry')` present; recap `find.text('Event not found')` present (recap's generic error is `_notFound`, no Retry affordance — assert the not-found copy, NOT `Retry`). `find.text('You no longer have access')` ABSENT.

End every case with `pumpAndSettle()` (`EmptyStateView` schedules a `flutter_animate` ticker). Override any provider each target eagerly watches BEFORE its `.when` so provider-create doesn't surface stray state:
- **Ledger** watches `eventDetailProvider`, `eventExpensesProvider`, `eventSettlementsProvider`, `groupDetailProvider` at build top. On the `eventAsync` error path (`:78`) the others aren't *read*, but they're *subscribed* — if their create throws `[core/no-app]` Riverpod captures it as AsyncError (no crash). Override `eventDetailProvider` (the error); add empty-stream/error overrides for the rest only if the pump throws.
- **Recap** (`embedded:false`, the default) watches only `eventDetailProvider` before `.when` — minimal overrides. Assert against the standalone `Scaffold` body.
- **Activity** watches only `eventDetailProvider` before `.when`; `_loadPage` (initState) calls `activityServiceProvider` inside a `try/catch` — a create-throw is swallowed, harmless on the error path.

Run each: `flutter test test/features/<dir>/<file>` — **must fail on assertion 1** (today each renders its retry/not-found copy, not the no-access copy), NOT a compile error. Capture verbatim for the PR body.

### Task 4: GREEN — wire the no-access branch into the three surfaces

For each, change ONLY the `eventAsync.when(error:)` branch to the two-arg form and special-case permission-denied (mirror `event_command_center.dart:86-94`). Add imports: `import 'dart:async';` (unawaited), `import 'package:sentry_flutter/sentry_flutter.dart';`, `import '../../../core/utils/firestore_error_utils.dart';`, `import '../../../shared/widgets/no_access_view.dart';`.

**ledger_screen.dart:78:**
```dart
error: (error, stackTrace) {
  // #1237 / #358: a removed member's event listen is permission-denied
  // forever — retry just re-denies. Terminal no-access state; raw error to
  // Sentry, not the UI. (The hub shadows this panel; kept for consistency.)
  if (isPermissionDenied(error)) {
    unawaited(Sentry.captureException(error, stackTrace: stackTrace));
    return const NoAccessView();
  }
  return _ErrorState(
    onRetry: () => ref.invalidate(eventDetailProvider(eventRef)),
  );
},
```

**activity_feed_screen.dart:124:** same shape, fallback `_ErrorView(onRetry: () => ref.invalidate(eventDetailProvider(eventRef)))`.

**event_recap_screen.dart:60:** same shape, fallback `_notFound(context)`. (Standalone wraps in `Scaffold(body: SafeArea(child: NoAccessView))` — the inner/outer SafeArea nest is a harmless no-op; embedded returns `NoAccessView` directly.)

Run the three RED tests → GREEN. Then `flutter test test/features/ledger/ test/features/activity/ test/features/events/`.

### Task 5: Analyze, theme purity, full suite

- `flutter analyze` — clean (watch for now-unused `cloud_firestore` imports in the two migrated files, and any unused `_ErrorState`/method — none expected).
- `bash tool/check_theme_purity.sh` — new widget uses no hardcoded colors; should pass. Run because two new `lib/` widgets touched.
- `flutter test` — full suite green.

### Task 6: PR

Branch `-u` `fix/1237-sibling-no-access-state`. Commit `fix(routing): sibling event-load surfaces get the #358/#1207 no-access state (#1237)`. PR body: summary + test plan + pasted RED output + `Closes #1237` + `Spec: docs/plans/2026-07-14-0654-1237-sibling-no-access-state.md`. Include the spec file in the branch. Do NOT self-merge (lead runs `/automerge` — Gate-category).

---

## Acceptance
- [ ] `isPermissionDenied` + `NoAccessView` extracted to shared files; both existing private copies deleted; `group_detail`/`event_command_center` migrated (incl. dropped unused `cloud_firestore` imports); their existing no-access tests stay green unedited.
- [ ] Ledger, activity, recap each render lock icon + no-access copy + Home CTA on `permission-denied` event load; NO Retry (test-asserted, 3 files).
- [ ] Home CTA navigates `/home` (test-asserted, 3 files).
- [ ] Non-permission errors keep each surface's existing retry/not-found state (test-asserted).
- [ ] Sentry `captureException` on the denied path of each (mirrors #1239).
- [ ] Recap standalone route no longer shows "Event not found" to a removed member.
- [ ] `flutter analyze` clean; `check_theme_purity.sh` pass; full suite green; diff coverage ≥90%.

## Residual (name in the PR body, do NOT fix here)
- Data-provider `permission-denied` paths (ledger `_DataErrorState`, recap `_dataUnavailable`, activity `_loadPage`) still show generic retry — the hub converges to no-access for the embedded panels, so this is cosmetic-only; a distinct follow-up if evidence warrants.
- `listen_recovery.dart:72` keeps its inline predicate (recovery-loop internals).
