# #1102 Offline Display-Name Reconciliation Implementation Plan

> **For agentic workers:** Execute inline in this dedicated worktree. The task contract forbids subagents. Follow RED -> GREEN and preserve the no-Firebase-app fail-open behavior.

**Goal:** Preserve a user-initiated display-name rename across an offline pre-write read failure, then stage the member-document updates when connectivity returns without waiting for Firestore's server acknowledgement.

**Architecture:** `SettingsService` stores a normalized pending-propagation marker distinct from `settings_device_name`, so the #990 INBOUND-only seed path never becomes an outbound rename. A focused Firestore service performs the existing group/member discovery and returns the batch's server-ack future as staged work; `SettingsNotifier` clears the marker once that future has been obtained, not once it resolves. `appBootstrapProvider` retries the pending marker at initial online boot and on offline/syncing -> online transitions.

**Tech Stack:** Flutter, Riverpod 2.x, SharedPreferences, Cloud Firestore, mocktail, flutter_test.

## Global Constraints

- Do not modify `security/firestore.rules`, `functions/**`, or any `**/models/**.dart` file.
- Keep `setDeviceName` local-first and keep all propagation errors silent.
- Preserve `seedDeviceName` as INBOUND-only: it must not create a pending propagation marker.
- Treat a never-completing Firestore write future as a successfully staged offline write per #412.
- The Firestore write map remains exactly `{'displayName': normalizedName}`.

---

### Task 1: Pin the offline loss with RED

**Files:**
- Create: `test/core/providers/display_name_reconciliation_1102_test.dart`

**Interfaces:**
- Consumes: `SettingsNotifier.setDeviceName`, `SettingsNotifier.propagateDisplayName`, `appBootstrapProvider`, `ConnectivityNotifier`.
- Produces: regression coverage proving the first propagation can fail before staging, the rename intent stays durable, and an online transition starts a second propagation whose server acknowledgement may never complete.

- [x] Write a test double around the existing propagation boundary. Its first call throws an offline-read error; its second call returns `Completer<void>().future` and never acknowledges.
- [x] Start connectivity offline, activate `appBootstrapProvider`, call `setDeviceName('Nasser')`, then transition connectivity online.
- [x] Assert the normalized local name survives, a durable pending marker exists, and propagation is attempted twice without the test waiting for the second acknowledgement.
- [x] Run `flutter test test/core/providers/display_name_reconciliation_1102_test.dart` and save the exact assertion failure showing that reconnect did not retry the pending rename.

### Task 2: Persist and stage the rename intent

**Files:**
- Modify: `lib/core/services/settings_service.dart`
- Create: `lib/core/services/display_name_propagation_service.dart`
- Modify: `lib/core/providers/settings_provider.dart`

**Interfaces:**
- Consumes: normalized user rename and the current Firebase user.
- Produces: `SettingsService.pendingDisplayNamePropagation`, compare-and-clear persistence methods, and `DisplayNamePropagationService.stage(displayName)` returning `Future<({Future<void> ack})?>`.

- [x] Add a SharedPreferences key for pending user-initiated display-name propagation, plus validated read, save, and compare-and-clear operations.
- [x] Move the existing Firestore group/member discovery and unchanged `displayName` update map into `DisplayNamePropagationService.stage`.
- [x] Keep service construction lazy so unit tests without a Firebase app still enter `SettingsNotifier`'s existing catch and fail open.
- [x] In `setDeviceName`, write/replace the pending marker only for a non-empty user rename; clearing the local name cancels any older marker. Leave `seedDeviceName` unchanged.
- [x] In `propagateDisplayName`, await only the discovery/staging result, attach a silent handler to the returned acknowledgement, and compare-and-clear the marker immediately after staging. Read failures and no-app failures leave the marker intact.
- [x] Add `reconcilePendingDisplayName` to retry only the durable marker.

### Task 3: Reconcile on boot/reconnect and turn GREEN

**Files:**
- Modify: `lib/core/providers/app_bootstrap_provider.dart`
- Modify: `test/core/providers/display_name_reconciliation_1102_test.dart`

**Interfaces:**
- Consumes: `connectivityProvider` state and `SettingsNotifier.reconcilePendingDisplayName`.
- Produces: one initial-online attempt and one attempt per non-online -> online transition.

- [x] Add a `fireImmediately` connectivity listener to `appBootstrapProvider`; ignore offline/syncing and repeated online states.
- [x] Use an injected mocked propagation service in the regression test. The first staging call throws; the reconnect call returns a never-completing acknowledgement.
- [x] Assert the marker remains after the first failure, clears once the second batch is staged, and the acknowledgement is still incomplete.
- [x] Add a no-Firebase-app assertion showing the rename completes locally and the marker remains available for a later real-app reconciliation.
- [x] Run the focused test until GREEN, then run `flutter test test/unit/settings_notifier_test.dart test/core/providers/app_bootstrap_wiring_test.dart`.

### Task 4: Verify and publish

**Files:**
- Review: every file in `git diff origin/main...HEAD`.

- [x] Run `flutter test`.
- [x] Run `flutter analyze`.
- [x] Confirm `git diff --name-only origin/main...HEAD` contains no forbidden or unrelated file.
- [x] Confirm the unchanged write map against `security/firestore.rules` `validSelfDisplayNameUpdate` lines 1043-1049 and cite it in the PR body.
- [ ] Commit conventionally with final body `Closes #1102`.
- [ ] Push `fix/1102-offline-display-name` and create the PR with summary, `Closes #1102`, exact commands/results, and verbatim RED output.

## Verification Principles

1. **Callsites:** `setDeviceName` and `propagateDisplayName` are OUTBOUND; `seedDeviceName` is INBOUND-only; reconciliation consumes only the OUTBOUND pending marker.
2. **Code evidence:** the current loss is the two awaited queries before `batch.commit()` in `settings_provider.dart`; the app currently has no propagation retry callsite.
3. **Read after write:** group/member streams read the updated `groups/{gid}/members/{memberId}.displayName` field.
4. **Fields:** no app model or Firestore field changes; the only new shape is a private local SharedPreferences marker.
5. **Contract:** pending value is a normalized, valid display-name string; successful staging writes only `displayName`; compare-and-clear prevents an older attempt from erasing a newer rename.
6. **Arithmetic:** not applicable.
7. **Orthogonal axis:** exercise #990 seed isolation and #412 never-ack behavior in addition to the offline read-failure axis.

## Self-Review

- Spec coverage: offline read failure, durable retry, no-app fail-open, #990 seed isolation, and #412 never-ack are each assigned to an implementation step and assertion.
- Placeholder scan: no deferred implementation or verification step remains.
- Type consistency: the staged result carries only `ack`; the notifier owns pending-marker clearing and the bootstrap owns retry timing.
