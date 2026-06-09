# #357 — surface the dead `syncing` state as "Saved — will sync"

**Date:** 2026-06-09 · **Branch:** `feat/offline-saved-syncing-357` · **Gate:** EXEMPT
(no money math / `firestore.rules` / Functions auth / routing tree / schema field — pure
connectivity-UI state + a post-write signal).

## Problem
`ConnectivityNotifier` defines a third state `syncing` (`setSyncing()`) that **nothing sets
and nothing renders** — `OfflineBanner` only checks `== offline`. After a user saves an
expense/settlement **while offline**, the Firestore SDK queues the write locally and replays
it on reconnect, but the UI gives no "it's saved, it'll sync" reassurance.

## Scope (this PR)
Make the dead `syncing` state **live + rendered + triggered + tested**.

- **AC1 (rendering + trigger):** `OfflineBanner` renders `syncing` → "Saved — will sync"; the
  state is set after a successful write **iff currently offline**.
- **AC3:** no custom cache/queue (SDK replays); tests cover the `syncing → online` transition.

**Deferred → `Refs #357` (issue stays open, re-scoped):**
- **AC2** — mount `OfflineBanner` on the *compose* screens (add/edit expense, settle-up).
  Materially larger test blast radius: the add/edit body is the shared `ExpenseEditorBody`,
  pulling in many `pumpAndSettle`-heavy ledger suites. AC1's value already lands because the
  compose screens **pop to** ledger / home / event-command-center, which already mount the
  banner — so "Saved — will sync" is visible there. group-settle pops to group-detail (no
  banner) → that one surface waits for AC2.

## Design — the `syncing` lifecycle
- **Set:** after a write the SDK has accepted locally, **only when `state == offline`** —
  `ConnectivityNotifier.noteLocalWrite()` (no-op when online/syncing). Gating on offline keeps
  online writes from flashing the banner (they commit immediately; the existing success
  snackbar/dialog covers them).
- **Clear:** the existing periodic probe (60s + on-resume `checkConnectivity`) already moves
  `syncing → online` (replay done) or `syncing → offline` (still offline). **No new timer** →
  no probe/timer race. The affordance is therefore transient (shows until the next probe or
  reconnect). The `syncing → online` path is the AC3 regression test.

## Changes

### Prod
1. `lib/core/providers/connectivity_provider.dart`
   - `noteLocalWrite()` — `if (state == offline) state = syncing;`.
   - Test seam: `ConnectivityNotifier({ConnectivityProbe?, bool startPeriodicChecks = true})`;
     guard `if (startPeriodicChecks) _startPeriodicCheck();`. Mirrors the existing injectable
     `ConnectivityProbe` seam. Lets write-screen tests use a **timer-free** notifier so their
     `pumpAndSettle` doesn't hang (the documented ConnectivityNotifier-never-settles trap).
2. `lib/shared/widgets/offline_banner.dart` — switch on `status`: `offline` (existing),
   `syncing` → "Saved — will sync" (distinct icon `Iconsax.cloud_add`/tick + success/info
   color, its own key), `online` → `SizedBox.shrink`.
3. `lib/l10n/app_en.arb` + `app_ar.arb` — `bannerSavedWillSync` (+ regenerate).
4. Trigger `ref.read(connectivityProvider.notifier).noteLocalWrite()` at the 5 write-success
   points (capture the notifier before `await` where the screen may dispose, like the
   `ledgerRevision` bumps):
   - `add_expense_screen.dart:73`, `edit_expense_screen.dart:141` (update) & `:173` (delete),
   - `settle_up_screen.dart:364` (event settle), `group_settle_up_screen.dart:415` (group settle).

### Tests
5. `connectivity_provider` unit: `offline → noteLocalWrite → syncing`;
   `online → noteLocalWrite → online` (gate); `syncing → checkConnectivity(probe=true) → online`
   (**AC3**); `startPeriodicChecks:false` schedules no timer.
6. `offline_banner_test`: `syncing` renders "Saved — will sync" (EN + AR), single `pump()`
   (never `pumpAndSettle` — periodic timer).
7. Write-screen suites: add a **timer-free** `connectivityProvider` override
   (`ConnectivityNotifier(startPeriodicChecks:false)`) to each centralized `ProviderScope`
   helper so the new submit-time read doesn't hang. One screen-level proof
   (settle_up, offline override) that an offline submit flips global state to `syncing`.

## Verify
- `flutter analyze` clean · new unit + banner tests RED→GREEN · full ledger/groups/shared
  suites green · `flutter gen-l10n` clean.
