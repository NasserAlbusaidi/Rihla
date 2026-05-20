# Real-Device QA

Last prepared: 2026-05-20 (`codex/release-hardening-1-0`, PR #39)

This checklist covers the release QA that cannot be proven by unit, widget, or
emulator tests. Run it on physical iOS and Android devices against the
production Firebase project unless a test explicitly says otherwise. The gate
script fails until the matrix rows are recorded as passing for both platforms
with concrete evidence.

## v1.2 Android-Only Soft Defer

v1.2 launches Android-only on Google Play. iOS is soft-deferred to follow
within weeks of Android Production. To run the matrix in Android-only mode,
export `RIHLA_SKIP_IOS_QA=yes` before invoking the gate script:

```bash
RIHLA_SKIP_IOS_QA=yes bash tool/check_real_device_qa_gate.sh
```

Under that flag:

- The gate accepts iOS device absence as INFO instead of FAIL.
- Matrix iOS cells must read `Pass ...` or `Deferred ...` — empty cells
  still fail.
- "Two devices" tests (RD-04 in particular) are exercised with two physical
  Android devices in Android-only mode.

To reactivate the full iOS gate when iOS ships, unset `RIHLA_SKIP_IOS_QA`
and replace `Deferred ...` cells with `Pass ...` plus concrete iOS
evidence.

## Device Gate

Start here:

```bash
bash tool/check_real_device_qa_gate.sh
```

Pass criteria (default — full iOS + Android gate):

- At least one physical iOS device is listed.
- At least one physical Android device is listed.
- `config.json` has `USE_FIREBASE_EMULATOR` set to `false` or omitted.
- Firebase platform files are present:
  - `android/app/google-services.json`
  - `ios/Runner/GoogleService-Info.plist`
- Every RD-01 through RD-09 row below has an iOS result starting with `Pass`,
  an Android result starting with `Pass`, and evidence that replaces the
  placeholder text.

Pass criteria (with `RIHLA_SKIP_IOS_QA=yes` — v1.2 Android-only):

- At least two physical Android devices are listed so RD-04 can prove
  cross-device ledger identity without iOS.
- iOS device absence reported as INFO.
- `config.json` and Firebase platform files as above.
- Every RD-01 through RD-09 row has an Android result starting with `Pass`,
  an iOS result starting with `Pass` or `Deferred`, and concrete Android
  evidence in the Evidence cell.

Current local status from 2026-05-20: blocked for Android. Running
`RIHLA_SKIP_IOS_QA=yes bash tool/check_real_device_qa_gate.sh` found no
physical Android device, accepted iOS absence as a v1.2 Android-only defer, and
reported RD-01 through RD-09 missing Android pass results plus concrete
evidence. The matrix is filled with `Deferred — v1.2 Android-only` for iOS; the
Android column and evidence still need a real run on connected Android devices.

Use two physical Android devices for the Android-only gate. RD-04 must prove
cross-device ledger identity without relying on the deferred iOS path.

For raw device details, run:

```bash
flutter devices
```

## Run Commands

Use one terminal per device:

```bash
flutter run -d <ios-device-id> --dart-define-from-file=config.json
flutter run -d <android-device-id> --dart-define-from-file=config.json
```

For a closer release check, install the built Android AAB through the Play
testing track and install iOS through Xcode or TestFlight. Record which build
path was used.

## Test Matrix

Record each result as Pass, Fail, or Blocked with the device model, OS version,
build source, and Firebase project. In the default full iOS + Android gate, both
iOS and Android cells must start with `Pass`. In Android-only mode, iOS cells
may start with `Deferred` and Android cells must start with `Pass`. Evidence
cell must contain a concrete artifact such as a group ID, invite code,
screenshot filename, or Firestore document path.

| ID | Area | iOS | Android | Evidence |
|---|---|---|---|---|
| RD-01 | Create group | Deferred — v1.2 Android-only |  | Group ID or screenshot |
| RD-02 | Join group by invite code | Deferred — v1.2 Android-only |  | Invite code and joined member name |
| RD-03 | Delete group | Deferred — v1.2 Android-only |  | Group no longer appears on both devices |
| RD-04 | Two-device ledger identity | Deferred — v1.2 Android-only |  | Screenshots from both devices |
| RD-05 | Decimal expense input | Deferred — v1.2 Android-only |  | Keyboard screenshot and saved amount |
| RD-06 | Offline and reconnect | Deferred — v1.2 Android-only |  | Before/after screenshots |
| RD-07 | Notification opt-in | Deferred — v1.2 Android-only |  | `fcm_tokens/{uid}` exists |
| RD-08 | Notification opt-out | Deferred — v1.2 Android-only |  | `fcm_tokens/{uid}` removed |
| RD-09 | Arabic RTL golden path | Deferred — v1.2 Android-only |  | Arabic RTL screenshots and golden-path log |

## RD-01: Create Group

1. Fresh install the app or clear app data.
2. Open the app and set a clear device name, for example `Alice iOS`.
3. Create a group named `QA <date>`.
4. Add at least two member names: `Alice` and `Bob`.
5. Select `Alice` as the current device's member name.

Pass criteria:

- The group appears on Home.
- The group detail screen opens without permission errors.
- The member list shows the creator and the second unclaimed member.

## RD-02: Join Group By Invite Code

1. On the creator device, open the group invite flow and copy the six-character code.
2. On the second device, set a different device name, for example `Bob Android`.
3. Open Join Group, enter the invite code, and continue.
4. Pick the unclaimed `Bob` member name.

Pass criteria:

- The second device joins without `permission-denied` or `unavailable`.
- Both devices show the same group.
- `Bob` is marked as claimed by the second device.

## RD-03: Delete Group

1. Keep both devices in the same QA group.
2. On the creator device, delete the group from group settings.
3. Return both devices to Home.

Pass criteria:

- The creator sees a successful delete or return-to-home flow.
- The group disappears from Home on both devices after refresh.
- Opening stale group details does not show a permission error loop.

## RD-04: Two-Device Ledger Identity

1. In the shared group, create an event with both members selected.
2. On Alice's device, add an expense:
   - Title: `QA coffee`
   - Amount: `1.500`
   - Currency: `OMR`
   - Paid by: `Alice`
   - Split: all participants
3. Open the event ledger and group settle-up view on both devices.

Pass criteria:

- Alice's device shows Bob owes Alice `0.750 OMR`.
- Bob's device shows Bob owes Alice `0.750 OMR`.
- Alice's device does not show Alice owing herself or owing Bob for this expense.
- The payer label stays `Alice` on both devices.

## RD-05: Decimal Expense Input

1. On each device, open Add Expense.
2. Focus the amount field.
3. Check the keyboard or custom keypad.
4. Enter `1.500` and save an expense.

Pass criteria:

- A decimal separator is available on the input surface.
- `1.500 OMR` is accepted and saved.
- The ledger displays three decimal places.

## RD-06: Offline And Reconnect

1. Open the QA group while online.
2. Enable airplane mode or disconnect network.
3. Navigate Home, group detail, event ledger, and activity.
4. Reconnect.

Pass criteria:

- Cached data remains visible where expected.
- Offline UI does not become a permanent false-offline state after reconnect.
- Firestore-backed screens refresh after reconnect.

## RD-07: Notification Opt-In

1. Open Profile.
2. Enable push notifications.
3. Accept the OS permission prompt.
4. Inspect Firestore for `fcm_tokens/{currentUid}`.

Pass criteria:

- The in-app toggle stays enabled.
- Notification status is enabled.
- Firestore has a token document for the current anonymous UID.

## RD-08: Notification Opt-Out

1. Start from RD-07's enabled state.
2. Disable push notifications in Profile.
3. Inspect Firestore for `fcm_tokens/{currentUid}`.

Pass criteria:

- The in-app toggle stays disabled.
- The token document for the current anonymous UID is removed.
- Reopening the app does not recreate the token while the setting is off.

## RD-09: Arabic RTL Golden Path

Run this after the Arabic localization PR stack lands on the build under test.

1. Install a production-Firebase build on a physical Android device.
2. Switch the app language to Arabic from Profile, or start from a fresh
   install whose settings are already seeded to Arabic.
3. Walk the same core flow as `integration_test/golden_path_arabic_test.dart`:
   Home, Activity tab, Profile tab, create group, create event, add expense,
   and ledger.
4. Capture screenshots for Home, Activity, Group Detail, Event Type Picker,
   Create Event, Add Expense, and Ledger.
5. While navigating, watch route motion, back arrows, row chevrons, the Rihla
   wordmark flourish, route mark artwork, loading shimmer direction, and step
   dots.

Pass criteria:

- Home bottom navigation, Activity, Profile, Groups, Events, and Ledger render
  Arabic copy with no English UI islands except brand text, stored names,
  invite codes, URLs, currency codes, and free-form user content.
- Directional controls point the right way in RTL; custom-drawn marks do not
  read backwards.
- Shared-axis transitions feel spatially correct in RTL: forward navigation
  enters from the start edge and back navigation returns toward the end edge.
- Invite codes, URLs, and currency codes remain visually LTR and readable.
- The Arabic golden-path integration log completes without render exceptions
  on the same build.

## Resolved on `fix/post-launch-qa-v1.2`

Three bugs found in the v1.2.0+14 closed-test session on 2026-05-16. All fixed and confirmed on a debug build (Pixel 9 Pro XL, Android 16) before being committed. Branch not yet shipped to Play.

### 1. Group detail back button does nothing on Android — RESOLVED

**Symptom:** Tapping the on-screen ← arrow on `/group/:gid` had no effect on Android; user was stranded on the group screen. iOS Simulator unaffected. Hit-test math wasn't off (button visually present, gap clear), but the live Android build was specifically broken — likely Android 15+ edge-to-edge / predictive-back interaction with the small `_PaperIconButton` (36×36 below Material 48dp).

**Fix (commit `7f76ff3`):** Wrapped `_PaperIconButton` in a 48×48 hit-target while keeping the 36×36 visual circle. Wrapped `GroupDetailScreen` in `PopScope(canPop: false, ...)` so Android system back / predictive back always routes via `router.canPop() ? pop() : go('/home')`. Tests assert both the PopScope fallback and the 48dp tap region.

### 2. Event-level settlements showed "Someone paid Someone" — RESOLVED

**Root cause:** `SettlementService.addSettlement` wrote participant IDs but not `payerName` / `recipientName`. The UI fell back to `settlement.payerName ?? 'Someone'`. Group-level settlements worked because `GroupSettlementService.addGroupSettlement` persists the names.

**Fix (commit `7f76ff3`):** Added optional `payerName` / `recipientName` params to `addSettlement` and persisted them to Firestore (mirroring the group service shape). Event settle-up screen threads `fromName` / `toName` from `_handleSettlement` through `_recordSettlement` to the service. Settlements written before the fix continue to render "Someone" via the model fallback — no backfill.

### 3. Post-recovery: "Could not identify your participant record" — RESOLVED

**Symptom:** After completing email-link recovery (Firebase Auth swapped from temp anonymous UID to email-linked UID), attempting to create an expense in any group/event surfaced "Could not identify your participant record." Force-stopping the app and reopening worked around it.

**Root cause:** `currentUserIdProvider` was a plain Riverpod `Provider` that read `FirebaseConfig.currentUser?.uid` once and cached. With no `ref.watch` dependency, it never re-evaluated when Firebase Auth swapped users. `UidChangeListener` wiped SQLite but Riverpod state retained the pre-swap UID. Downstream `currentEventParticipantProvider` looked up the stale UID against the new `event.participantIds`, missed, and surfaced the generic "no participant" error.

**Fix (commit `b793eb6`):** `currentUserIdProvider` now does `ref.watch(authStateProvider).valueOrNull?.uid`, so the UID follows every Firebase Auth state change. Regression test in `test/unit/current_user_id_provider_test.dart` simulates the recovery swap (anon → recovered) explicitly.

## Also shipped in v1.2.0+15

- **Join-event-sync (Gap 1) — RESOLVED.** `joinGroupByInviteCode` now fans the joining UID + displayName into every non-deleted event's `participantIds` / `participantNames` inside the same Admin transaction. Idempotent on re-join (heals already-affected stale state). Production backfill ran 2026-05-16 against 2 groups / 2 events / 3 UIDs via `tool/backfill_join_event_sync.js`.
- **Anon-UID cleanup at recovery (Gap 3 server-safe) — RESOLVED.** `cleanupAnonUidArtifacts` runs fire-and-forget after a successful `signInWithEmailLink`, but only after the retiring anon UID has created a one-time `recoveryCleanupIntents/{oldUid}` secret. Per group: replaces or removes the old anon UID in `memberIds`, copies the member doc, reassigns `createdBy` on group/event/expense docs (NOT settlements), rewrites event `participantIds` / `participantNames`. Then deletes the anon Firebase Auth user, orphan `fcm_tokens/{oldUid}`, `joinAttempts/{oldUid}`, and the consumed cleanup intent. Recovery itself succeeds regardless of cleanup outcome; failures land in a Sentry breadcrumb with no PII.

## Follow-ups for v1.2.0+16

- **Former-member UI rendering for dormant anon-UID creators.** The post-recovery cleanup only fires when a user actually recovers via email link. Anon UIDs that created events in past sessions and were never recovered remain as `createdBy` on those events + retain real historical expense / settlement attribution. Confirmed on production for one orphan UID across 5 events in group `78cb99b0…` (event creator + 1 expense as payer + 1 settlement as payer — NOT safe to delete via the participant cleanup script). The "ghost member" rendering in settle-up is technically correct. Fix is UI-level: mark `participantIds` entries whose UID is no longer in `group.memberIds` as "former member" rather than deleting their data. Touch points likely: `groupBalancesProvider`, settle-up sheet, ledger participant labels.
- **RD-QA release gate.** `tool/release.sh` runs the consolidated audit after
  creating the release commit and before creating or pushing a tag. That audit
  invokes `tool/check_release_readiness.sh`, which invokes this matrix gate and
  the GitHub release-governance gate. The Android column and evidence cells for
  RD-01..RD-09 must therefore be filled with concrete physical-device evidence
  before the release tag can be cut through the repo helper. The GitHub Actions
  Play upload still has its own repository-variable guard, including the
  commit-bound `RIHLA_RELEASE_APPROVED_SHA`, as a final tag/workflow safeguard.

## Adjacent gaps still deferred

- **Stale `participantNames`:** Event docs cache display names at creation time and don't refresh when a member renames themselves. Observed on "Janel shams" where the user's name reads "Mohammed" instead of "Nasser". Cosmetic — identity / balance math keys off UIDs, never names. Fix would extend `propagateDisplayName` to fan out into participated events + loosen `validEventLightUpdate` to allow `participantNames.{request.auth.uid}` self-update. Scope: ~3 hours when picked up.
