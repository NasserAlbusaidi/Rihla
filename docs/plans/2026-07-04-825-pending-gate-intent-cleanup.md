# Retire PendingGateIntent / GateIntentReplay (#825)

**Spec status:** v2 — pending rubric Gate review; adversary Gate round 1 returned
0 P1 / 0 P2 / 3 P3 and the P3 doc/comment scope is folded in below. **Base:**
`origin/main` at `e743b22a`. **Tracking:** #825, issue comment `4880133005`.
**Scope:** cleanup-only follow-up to
`docs/plans/2026-07-03-remove-anon-create-gate.md`.

## Intent

After #818 removed the durable credential gate from create-group submission, no lib/
caller constructs or passes a `PendingGateIntent` into
`showDurableCredentialSheet`. The remaining marker/replay/prefill path is now
orphaned:

- `showDurableCredentialSheet` still accepts `PendingGateIntent? intent` and passes it
  into `_DurableCredentialSheet` (`lib/features/auth/widgets/durable_credential_sheet.dart:35-51`).
- The conflict-switch path still persists that optional marker before
  `restoreWithGoogle` (`durable_credential_sheet.dart:152-158`).
- `PendingGateIntent` still defines the `auth.pendingGateIntent` prefs payload and TTL
  (`lib/features/auth/services/pending_gate_intent.dart:20-106`).
- `GateIntentReplay.maybeReplay` still navigates to `/create-group` from a marker
  (`lib/features/auth/services/gate_intent_replay.dart:10-33`).
- `main.dart` still wires replay into the cold-start coordinator
  (`lib/main.dart:29`, `lib/main.dart:226-231`).
- `CreateGroupScreen` still consumes a marker during `initState`
  (`lib/features/groups/screens/create_group_screen.dart:22`, `71-99`).

`rg -n "PendingGateIntent|GateIntentReplay|showDurableCredentialSheet\\(" lib test -S`
shows every remaining `PendingGateIntent.create/save/read` production path is either
this orphaned plumbing or tests for it. Current production sheet callers are bare:
`create_group_screen.dart:419`, `account_backup_nudge.dart:116`, and
`profile_screen.dart:539,1181`.

## Required Changes

1. Delete the orphan marker/replay services:
   - delete `lib/features/auth/services/pending_gate_intent.dart`
   - delete `lib/features/auth/services/gate_intent_replay.dart`
   - delete their direct unit tests: `test/unit/pending_gate_intent_test.dart` and
     `test/unit/gate_intent_replay_test.dart`

2. Simplify the durable credential sheet without changing conflict safety:
   - remove the `pending_gate_intent.dart` import
   - change `showDurableCredentialSheet(BuildContext context, { PendingGateIntent? intent })`
     to `showDurableCredentialSheet(BuildContext context)`
   - remove `_DurableCredentialSheet.intent` and the marker-persist block in
     `_switchAccount`
   - keep `_outgoingShellEmpty()`, `_conflictShellEmpty(...)`, and
     `restoreWithGoogle(credential: conflict.credential)` unchanged
   - update the top comment: the sheet is an optional account-link surface now, not a
     pending create/join replay surface

3. Remove cold-start replay from app startup:
   - remove `features/auth/services/gate_intent_replay.dart` from `lib/main.dart`
   - remove the `replayGateIntent` callback parameter from
     `runColdStartCoordinator`
   - remove the guarded replay step from `runColdStartCoordinator`
   - update the cold-start coordinator comment that currently names gate-intent replay
   - preserve ordering and error isolation for the remaining steps:
     `resolveDeepLinks` -> `consumeInstallReferrer` -> `activateAppBootstrap` ->
     `runInitialNotificationSync`
   - preserve `joinAlreadyRouted` behavior for initial notification routing:
     deep-link or install-referrer join routing still disables initial FCM routing

4. Remove create-screen marker prefill:
   - remove the `pending_gate_intent.dart` import
   - remove `initState()` if it only calls `_consumePendingGateIntent()`
   - remove `_consumePendingGateIntent()`
   - update stale comments mentioning `PendingGateIntent`, especially the trip-stamp
     comment at `create_group_screen.dart:59-62` and the #840 link-account CTA comment
     at `create_group_screen.dart:408-413`
   - do not change the #840 bare `showDurableCredentialSheet(context)` CTA behavior

5. Keep `durable_credential_exception.dart`.
   - Live code shows this file now contains `GoogleLinkConflictException`, still used by
     `AuthRecoveryService`, the durable sheet, and tests.
   - `rg -n "DurableCredentialRequiredException" lib test -S` returns no live class or
     thrower to delete.

6. Clean stale comments/docs tied to replay:
   - `auth_email_link_bootstrap_provider.dart:176-182`: keep clearing a blocked recover
     handshake, but stop saying it exists to unblock `GateIntentReplay`
   - `test/unit/auth_email_link_bootstrap_test.dart:541-543`: rewrite the matching
     stale test comment so it no longer names `GateIntentReplay`
   - `auth_recovery_service.dart:110`: remove the claim that the in-flight op key is
     public for `GateIntentReplay`
   - `app_bootstrap_provider.dart:100-108` and
     `test/core/providers/app_bootstrap_wiring_test.dart:285-290`: replace
     "join/create gate re-saved the token" wording with current optional link surfaces
   - `account_backup_nudge.dart:115` and related test comments: remove create/join gate
     wording; it is now the shared durable-credential sheet
   - `docs/ACCOUNT-RECOVERY.md:101`: remove the obsolete claim that create/join form
     state is persisted as `PendingGateIntent` and replayed after restore
   - `docs/adr/ADR-0005-android-install-referrer-invites.md:94`: remove or mark
     historical the obsolete deferred-invite-vs-`auth.pendingGateIntent` interaction

7. Tests:
   - Update `test/unit/cold_start_coordinator_test.dart` expected call sequences and
     test names to remove the replay step while keeping deep-link/referrer/bootstrap/
     notification behavior pinned.
   - In `test/features/auth/durable_credential_sheet_conflict_test.dart`, remove the
     `PendingGateIntent` import, helper parameters, marker-persistence test, and marker
     assertions. Keep/adjust tests that pin:
     - conflict + empty shell offers switch
     - unresolved/populated/error shell does not switch
     - switch re-check blocks if shell becomes populated after the offer renders
     - switch restores with the failed credential and never signs out
   - Delete or rename `test/features/groups/gate_intent_prefill_test.dart`. Preserve the
     two still-live join pins by moving them into a non-gate-named test file:
     route-supplied `initialInviteCode` prefills the code field, and join name is not
     seeded from settings (#293).

## Explicit Non-Changes

- No Firestore rules or Cloud Functions behavior changes.
- No money math, `MoneySerializer`, `BalanceCalculator`, settlement, or ledger changes.
- No route tree changes. `/create-group` remains a normal route; only orphan replay
  navigation is removed.
- No change to `AuthRecoveryService.restoreWithGoogle` semantics.
- No change to shell-emptiness checks. Conflict-switch must still never resolve by
  signing out the anon user, and must still require `outgoingShellProvablyEmpty`.
- No change to the email-link restore data-loss guard. A blocked recover still clears
  stale recovery handshakes; only comments/tests lose the deleted replay rationale.
- No change to the create-screen link-account CTA introduced after #818/#840.

## Self-Check Against the 7 Gate Principles

1. **Shared read/write paths:** The only prefs write being deleted is
   `PendingGateIntent.save` to `auth.pendingGateIntent`; no remaining production reader
   should exist after deleting `PendingGateIntent.read` and `GateIntentReplay`.
2. **Concrete claims verified:** File and line claims above were checked against
   `origin/main` `e743b22a` with `nl -ba` and scoped `rg`.
3. **Read path per write path:** Deleted write path is marker persistence in
   `_switchAccount`; deleted read paths are `GateIntentReplay.maybeReplay` and
   `CreateGroupScreen._consumePendingGateIntent`.
4. **Fields from type:** `PendingGateIntent` carries `type`, `groupName`,
   `displayName`, `currencyCode`, and `atMillis`; the whole type is deleted, not
   partially migrated.
5. **Data contracts:** The removed prefs key is `auth.pendingGateIntent`; the cold-start
   callback signature removed is
   `Future<void> Function({required bool skipNavigation}) replayGateIntent`.
6. **Arithmetic:** Not applicable; no aggregate or money calculation is touched.
7. **Orthogonal axis:** Identity/lifecycle is the risk axis. The spec keeps
   `outgoingShellProvablyEmpty`, `restoreWithGoogle(credential:)`, and blocked recover
   clearing intact, and only deletes marker replay/prefill.

## Acceptance

- `rg -n "PendingGateIntent|GateIntentReplay|pending_gate_intent|gate_intent_replay" lib test -S`
  returns no matches.
- `rg -n "create/join gate|join/create gate|GateIntentReplay|pendingGateIntent|gate-intent" lib test docs/ACCOUNT-RECOVERY.md docs/adr/ADR-0005-android-install-referrer-invites.md -S`
  returns no stale live-code/test/doc comments.
- `flutter analyze` passes.
- Targeted tests pass:
  - `flutter test test/unit/cold_start_coordinator_test.dart`
  - `flutter test test/features/auth/durable_credential_sheet_conflict_test.dart`
  - preserved join prefill test file
- Full `flutter test` passes.
