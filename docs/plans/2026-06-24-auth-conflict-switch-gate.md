# Auth Conflict Switch Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `rihla-run-the-gate` before treating this as releasable. This plan is for a narrowly scoped auth cross-UID swap fix.

**Goal:** Ensure the Google link-conflict "switch to that account" path cannot false-empty an anonymous shell and call the irreversible cross-UID Google restore while the outgoing Firebase user is unresolved.

**Architecture:** Reuse the existing `outgoingShellProvablyEmpty` guard for the durable credential sheet conflict path. The sheet should derive switch visibility from the same guard used at the actual swap boundary, and `_switchAccount` must re-check the guard immediately before `PendingGateIntent.save` and `AuthRecoveryService.restoreWithGoogle(credential:)`.

**Tech Stack:** Flutter, Riverpod, Firebase Auth, existing auth providers in `lib/features/auth/`, widget tests with `flutter_test` and `mocktail`.

---

## Scope

Modify only:

- `lib/features/auth/widgets/durable_credential_sheet.dart`
- `test/features/auth/durable_credential_sheet_conflict_test.dart`

Do not change:

- `lib/features/auth/widgets/google_restore_action.dart`
- `lib/features/auth/providers/auth_email_link_bootstrap_provider.dart`
- `lib/features/groups/providers/group_provider.dart`
- `security/firestore.rules`
- `functions/src/**`

## Live Code Claims Verified While Writing

- `triggerGoogleRestore` already gates Google restore with `outgoingShellProvablyEmpty(readUser: firebaseUserProvider.future, readGroups: userGroupsProvider.future, timeout: shellEmptinessGateTimeoutProvider)`.
- `auth_email_link_bootstrap_provider.dart` already gates email recovery restore with the same helper before `restoreWithEmailLink`.
- `durable_credential_sheet.dart` has the missing conflict path: `_switchAccount` calls `restoreWithGoogle(credential: conflict.credential)` after optional `PendingGateIntent.save`.
- `userGroupsProvider` returns `Stream.value([])` when `firebaseUserProvider.valueOrNull?.uid == null`; this is the false-empty race the shared helper is designed to avoid.
- `outgoingShellProvablyEmpty` awaits `readUser()` first, then `readGroups()`, and catches timeout/error into `false`.

## Callsite Classification

- `showDurableCredentialSheet(...)`: BOTH. It is display/UI, but a conflict state can lead to the OUTBOUND `_switchAccount` path.
- `_continueWithGoogle`: OUTBOUND. Calls `AuthRecoveryService.linkGoogleToCurrentUser()` and refreshes the token on success.
- Conflict state rendering in `build`: BOTH. It displays either loading, dead-end, or switch controls; the switch control feeds the OUTBOUND restore path, so it must use the same guard.
- `_switchAccount`: OUTBOUND. It can write `PendingGateIntent` into `SharedPreferences` and calls `AuthRecoveryService.restoreWithGoogle(credential:)`, which swaps Firebase auth state, marks Firestore persistence dirty, and restarts.
- `triggerGoogleRestore`: OUTBOUND sibling path, already guarded and not modified.
- Email recovery bootstrap recover branch: OUTBOUND sibling path, already guarded and not modified.

## Required Behavior

1. When a Google link conflict occurs, the sheet must not read `userGroupsProvider` directly to decide whether to show the switch offer.
2. The conflict state must use `outgoingShellProvablyEmpty` with:
   - `readUser: () => ref.read(firebaseUserProvider.future)`
   - `readGroups: () => ref.read(userGroupsProvider.future)`
   - `timeout: ref.read(shellEmptinessGateTimeoutProvider)`
3. While the guard is pending, show the existing conflict loading UI (`Key('durableGate.conflictLoading')`).
4. If the guard resolves `true`, show the existing switch offer UI (`Key('durableGate.switch')`).
5. If the guard resolves `false`, errors, or times out, show `durableGateConflict` dead-end copy and do not show the switch button.
6. `_switchAccount` must re-run the same `outgoingShellProvablyEmpty` guard immediately before `PendingGateIntent.save` and `restoreWithGoogle(credential:)`.
7. If the `_switchAccount` re-check returns `false`, the method must not save a pending intent and must not call `restoreWithGoogle`.
8. Existing behavior must remain:
   - Empty resolved shell shows the switch offer.
   - Pressing switch persists `PendingGateIntent` before `restoreWithGoogle`.
   - Populated shell shows dead-end copy.
   - Groups error shows dead-end copy.
   - Unresolved/loading shell shows progress until timeout or resolution.
   - `provider-already-linked` still pops `true`.
   - Pre-isolation restore failure still resets to generic durable gate error.

## Test Plan

Add a regression to `test/features/auth/durable_credential_sheet_conflict_test.dart` that does not override `userGroupsProvider` directly.

The regression setup:

- Override `firebaseUserProvider` with a `StreamController<User?>` that does not emit.
- Override `groupServiceProvider` with a mock whose `watchUserGroups(any())` would return a populated group if queried.
- Override `shellEmptinessGateTimeoutProvider` to `50ms`.
- Trigger the Google link conflict.
- Pump past the timeout.
- Assert:
  - `Key('durableGate.switch')` is absent.
  - `durableGateConflict` is visible.
  - `restoreWithGoogle(credential:)` is never called.

Add a second regression for the actual swap boundary, not only switch visibility:

- Override `firebaseUserProvider` with a resolved anonymous `MockUser`.
- Override `groupServiceProvider` with a mock whose `watchUserGroups(any())` returns a controllable `StreamController<List<Group>>`.
- Trigger the Google link conflict.
- Emit `[]` from the groups stream so the switch offer renders.
- Before tapping `Key('durableGate.switch')`, emit `[_group()]` from the same groups stream.
- Tap the switch button.
- Assert:
  - `AuthRecoveryService.restoreWithGoogle()` with omitted credential is never called.
  - `AuthRecoveryService.restoreWithGoogle(credential: any(named: 'credential'))` is never called.
  - `PendingGateIntent.read(prefs) == null`, proving `_switchAccount` did not persist the replay marker before blocking.

Keep the existing direct-`userGroupsProvider` tests for the legacy resolved states, but give that harness a settled `firebaseUserProvider` so the new helper can complete.

## Verification Commands

Run the RED test before implementation:

```bash
flutter test test/features/auth/durable_credential_sheet_conflict_test.dart --plain-name "conflict + unresolved user does not false-empty into a switch offer"
```

Expected pre-fix failure: it finds `Key('durableGate.switch')` even though the user stream has not emitted.

Run after implementation:

```bash
flutter test test/features/auth/durable_credential_sheet_conflict_test.dart
flutter analyze --no-fatal-infos
bash tool/check_theme_purity.sh
flutter test test/features/auth test/features/home/account_backup_nudge_test.dart test/features/settings/profile_account_card_test.dart test/features/groups/durable_gate_wiring_test.dart test/features/groups/create_join_group_test.dart test/unit/auth_email_link_bootstrap_test.dart test/unit/auth_recovery_service_test.dart test/unit/auth_recovery_service_google_restore_test.dart test/unit/auth_recovery_service_email_restore_test.dart test/unit/auth_recovery_service_google_link_test.dart test/unit/auth_recovery_service_restart_guarantee_test.dart test/unit/auth_recovery_service_inflight_op_test.dart test/unit/auth_recovery_service_outcome_marker_test.dart test/unit/gate_intent_replay_test.dart test/unit/cache_uid_barrier_test.dart test/unit/firestore_cache_gate_test.dart test/unit/cache_isolation_controller_test.dart test/unit/firebase_config_cache_barrier_test.dart test/integration/firebase_auth_test.dart
```

## Seven-Point Verification Pass

1. **Callsites classified:** see "Callsite Classification." All conflict UI paths are treated as BOTH because they can expose an OUTBOUND swap button.
2. **Concrete claims verified against code:** grep targets are `restoreWithGoogle`, `outgoingShellProvablyEmpty`, `userGroupsProvider`, `firebaseUserProvider`, `PendingGateIntent.save`, and `shellEmptinessGateTimeoutProvider`.
3. **Read-path per write-path:** `PendingGateIntent.save` writes JSON at `SharedPreferences` key `auth.pendingGateIntent`. Its exact keys are `v`, `type`, `groupName`, `displayName`, `currencyCode`, and `atMillis`. The marker is read by `GateIntentReplay` for navigation replay and by `CreateGroupScreen._consumePendingGateIntent()` for one-shot form prefill/clear. Auth/cache writes inside `restoreWithGoogle` are read by the cold-start auth gate and cache barrier. `restoreWithGoogle` also writes `RecoveryOutcome` JSON at `SharedPreferences` key `auth.recoveryOutcome`; the read path is `recoveryOutcomeNoticeProvider` → `surfaceRecoveryOutcome` → `readAndClearRecoveryOutcome`. This fix does not change any data shape.
4. **Fields from type:** no model/schema fields are added, removed, migrated, or scrubbed.
5. **Data contracts:** exact function signatures are `outgoingShellProvablyEmpty({required Future<User?> Function() readUser, required Future<List<Group>> Function() readGroups, required Duration timeout})`, `PendingGateIntent.save(SharedPreferences prefs, PendingGateIntent intent)`, `PendingGateIntent.read(SharedPreferences prefs)`, `PendingGateIntent.clear(SharedPreferences prefs)`, and `restoreWithGoogle({AuthCredential? credential, Duration pendingWritesTimeout = ...})`.
6. **Arithmetic:** none.
7. **Orthogonal axis:** the regression is not a normal empty-vs-populated group test. It exercises the identity/time axis: unresolved auth user with a group service that would return populated data if the UID were known. The required outcome is fail-safe block, not switch visibility.
