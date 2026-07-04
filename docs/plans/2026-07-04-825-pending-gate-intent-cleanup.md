# Retire PendingGateIntent / GateIntentReplay (#825)

**Spec status:** v4 — current implementation spec. **Base:** `origin/main` at
`e743b22a`. **Tracking:** #825, issue comment `4880133005`. **Scope:**
retired marker/replay cleanup plus the anonymous push-token persistence correction
exposed by that cleanup.

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
     `resolveDeepLinks` -> `consumeInstallReferrer` ->
     `clearLegacyAuthMarkers` -> `activateAppBootstrap` ->
     `runInitialNotificationSync`
   - preserve `joinAlreadyRouted` behavior for initial notification routing:
     deep-link or install-referrer join routing still disables initial FCM routing

3a. Add one-release cleanup for the legacy prefs marker without reintroducing
    replay/prefill:
   - add `lib/features/auth/services/legacy_auth_marker_cleanup.dart`
   - the only retained legacy contract is the prefs key
     `auth.pendingGateIntent`
   - cold start calls `LegacyAuthMarkerCleanup.clear(prefs)` after explicit
     link/referrer arbitration and before `activateAppBootstrap`
   - cleanup is guarded; a prefs failure is reported through `onStepError` and
     cannot suppress bootstrap or notifications
   - no marker JSON is decoded, no `/create-group` navigation is replayed, and
     no form fields are prefilled. The old marker was best-effort form recovery:
     the original `PendingGateIntent.save` comment explicitly treated losing it
     as "a re-typed form, never the flow." Replaying it would keep the orphan
     behavior #825 is retiring.

3b. Keep push notifications honest for anonymous group owners:
   - remove the anonymous-user skip in `NotificationService._saveToken`
   - remove the anonymous-user skip in token-refresh handling
   - both write paths are OUTBOUND persistence boundaries:
     `NotificationService._saveToken` and `_onTokenRefresh` write
     `fcm_tokens/{uid}` with keys `user_id`, `token`, `platform`, `locale`, and
     `updated_at`
   - named readers/rules: Cloud Functions push delivery reads
     `fcm_tokens/{uid}` in `functions/src/notifications/fcmSender.ts`, and
     `security/firestore.rules` protects the document with
     `request.auth.uid == userId`
   - leave Firestore rules owner-keyed (`fcm_tokens/{uid}` requires
     `request.auth.uid == uid`), which already permits anonymous owners without
     allowing cross-user token writes
   - this changes runtime push delivery for anonymous recipients: existing Cloud
     Functions senders that call `sendToUids` can now deliver member-join, expense,
     event, settlement, and claim notifications to anonymous users who explicitly
     opted into push
   - update notification tests/comments that assumed anonymous token writes were
     suppressed by the old create/join gate invariant

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
   - Historical test comments may mention the removed create-time exception, but there is
     no live class or thrower to delete.

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
   - `docs/adr/ADR-0005-android-install-referrer-invites.md:94`: remove the obsolete
     deferred-invite-vs-retired-marker interaction
   - `docs/REAL-DEVICE-QA.md`: update RD-10/RD-12 so real-device QA no longer expects
     create/join replay after optional account linking or conflict switching
   - `docs/ACCOUNT-RECOVERY.md`: rewrite the safety model to current #648/#818
     reality. Anonymous users can create/join and own money data; restore/switch
     safety comes from the shared empty-shell guard, not from assuming an anon
     shell is empty by construction.
   - current code comments and l10n metadata that still describe a create/join
     durable gate should now describe optional account-link prompts and
     post-#818 anonymous ownership.

7. Tests:
   - Update `test/unit/cold_start_coordinator_test.dart` expected call sequences and
     test names to remove the replay step while keeping deep-link/referrer/bootstrap/
     notification behavior pinned. Add explicit tests that the legacy marker is
     cleared and that cleanup failure still allows bootstrap + notifications.
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

- No Firestore rules or Cloud Functions implementation changes beyond comment cleanup.
  Existing Cloud Functions push delivery reaches opted-in anonymous recipients because
  client token persistence now writes `fcm_tokens/{uid}` for anonymous UIDs.
- No money math, `MoneySerializer`, `BalanceCalculator`, settlement, or ledger changes.
- No route tree changes. `/create-group` remains a normal route; only orphan replay
  navigation is removed.
- No replay migration for legacy `auth.pendingGateIntent` values. Cold start only
  clears the key. A user who updated mid-marker may need to retype a create form;
  that is the original failure mode of a best-effort marker write and is not data
  loss. Keeping navigation/prefill replay would preserve the machinery #825
  explicitly removes.
- No change to `AuthRecoveryService.restoreWithGoogle` semantics.
- No change to shell-emptiness checks. Conflict-switch must still never resolve by
  signing out the anon user, and must still require `outgoingShellProvablyEmpty`.
- No change to the email-link restore data-loss guard. A blocked recover still clears
  stale recovery handshakes; only comments/tests lose the deleted replay rationale.
- No change to the create-screen link-account CTA introduced after #818/#840.

## Self-Check Against the 7 Gate Principles

1. **Shared read/write paths:** The prefs write being deleted is
   `PendingGateIntent.save` to `auth.pendingGateIntent`; no remaining production reader
   exists after deleting `PendingGateIntent.read` and `GateIntentReplay`. A new
   cleanup-only writer removes that legacy key during cold start. The newly restored
   notification write paths are `NotificationService._saveToken` and `_onTokenRefresh`;
   both persist `fcm_tokens/{uid}` with `user_id`, `token`, `platform`, `locale`, and
   `updated_at`.
2. **Concrete claims verified:** File and line claims above were checked against
   `origin/main` `e743b22a` with `nl -ba` and scoped `rg`.
3. **Read path per write path:** Deleted write path is marker persistence in
   `_switchAccount`; deleted read paths are `GateIntentReplay.maybeReplay` and
   `CreateGroupScreen._consumePendingGateIntent`. New cleanup write path is
   `LegacyAuthMarkerCleanup.clear` -> `SharedPreferences.remove`; its reader is
   absence checks in the focused cold-start test and no runtime consumer. New anonymous
   notification writes are read by `functions/src/notifications/fcmSender.ts`, while
   `security/firestore.rules` keeps the write owner-keyed.
4. **Fields from type:** `PendingGateIntent` carries `type`, `groupName`,
   `displayName`, `currencyCode`, and `atMillis`; the whole type is deleted, not
   partially migrated.
5. **Data contracts:** The removed prefs key is `auth.pendingGateIntent`; the cold-start
   callback signature removed is
   `Future<void> Function({required bool skipNavigation}) replayGateIntent`. The
   replacement cleanup callback is `Future<void> Function()? clearLegacyAuthMarkers`.
6. **Arithmetic:** Not applicable; no aggregate or money calculation is touched.
7. **Orthogonal axis:** Identity/lifecycle is the risk axis. The spec keeps
   `outgoingShellProvablyEmpty`, `restoreWithGoogle(credential:)`, and blocked recover
   clearing intact. Upgrade-time stale markers are cleared defensively, while
   replay/prefill stays deleted.

## Acceptance

- `rg -n "PendingGateIntent|GateIntentReplay|pending_gate_intent|gate_intent_replay" lib test -S`
  returns no matches except the intentional one-release legacy cleanup comment
  naming the retired flow.
- `rg -n "create/join gate|join/create gate|create-only|GateIntentReplay|pendingGateIntent|gate-intent" lib test docs/ACCOUNT-RECOVERY.md docs/adr/ADR-0005-android-install-referrer-invites.md docs/REAL-DEVICE-QA.md -S`
  returns no stale live-code/test/doc comments, except the literal legacy prefs
  key in `legacy_auth_marker_cleanup.dart` and its focused test.
- `rg -n "before the create/join proceeds|intent persistence|resumes and completes" docs/REAL-DEVICE-QA.md -S`
  returns no matches.
- `flutter analyze` passes.
- Targeted tests pass:
  - `flutter test test/unit/cold_start_coordinator_test.dart`
  - `flutter test test/unit/notification_service_anon_gate_test.dart`
  - `flutter test test/features/auth/durable_credential_sheet_conflict_test.dart`
  - preserved join prefill test file
- Full `flutter test` passes.
