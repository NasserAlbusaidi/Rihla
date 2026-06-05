# Real-Device QA

Last prepared: 2026-05-31 (first-production-release QA). Matrix completion is
tracked as release blocker #40.

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

Current status (2026-05-31): Android device QA is **in progress** and the gate
is **not yet satisfied**. Run evidence is captured locally under `qa_evidence/`
(gitignored — not committed to the repo): a 2026-05-29 Pixel 9 Pro XL session and
2026-05-31 two-device (RD-04) and Arabic-RTL (RD-09) captures. RD-09 is blocked
by #126 (the Arabic back-arrow points the wrong way). iOS cells stay
`Deferred — v1.2 Android-only`. Do not set `RIHLA_REAL_DEVICE_QA_READY=yes`
until RD-01..RD-09 are recorded and #126 is resolved — completion is tracked as
release blocker #40. The matrix Android cells are intentionally left unfilled
here rather than transcribed from local-only evidence.

Use two physical Android devices for the Android-only gate. RD-04 must prove
cross-device ledger identity without relying on the deferred iOS path.

For raw device details, run:

```bash
flutter devices
```

## Run Commands

To print the current branch, commit, audit doc, Android artifact hashes,
install commands, Firebase deploy handoff, open blockers, and final release
audit command from this checkout, run:

```bash
bash tool/print_release_wakeup_handoff.sh rihla-safar
```

For final release evidence, complete the Firebase backend deploy and
production-state verification handoff before recording the physical-device QA
matrix. The QA rows should prove the app against the production Firebase
backend for this same branch commit, not an older deployed backend.

For the Android QA slice only, run:

```bash
bash tool/print_android_qa_handoff.sh
```

For the Android-only wake-up QA pass, prefer the release APK built from the
current PR head so the matrix exercises the same app artifact listed in the PR
handoff and blocker issue. If artifacts are missing or the checkout changed
since the last build, rebuild the current head first:

```bash
flutter build apk --release --dart-define-from-file=config.json --android-skip-build-dependency-validation
flutter build appbundle --release --obfuscate --split-debug-info=./build/app/outputs/symbols --dart-define-from-file=config.json --android-skip-build-dependency-validation
```

Connect two physical Android devices, then install the APK on both:

```bash
adb devices
adb -s <android-device-id-1> install -r build/app/outputs/flutter-apk/app-release.apk
adb -s <android-device-id-2> install -r build/app/outputs/flutter-apk/app-release.apk
```

If the Play testing track is the source of truth for a given pass, install the
AAB-delivered build from Play instead and record the track/build in each
evidence cell.

Use one terminal per device:

```bash
flutter run -d <ios-device-id> --dart-define-from-file=config.json
flutter run -d <android-device-id> --dart-define-from-file=config.json
```

Use `flutter run` when you need logs while reproducing a failure. For a closer
release check, install iOS through Xcode or TestFlight. Record which build path
was used.

## Test Matrix

Record each result as Pass, Fail, or Blocked with the device model, OS version,
build source, and Firebase project. In the default full iOS + Android gate, both
iOS and Android cells must start with `Pass`. In Android-only mode, iOS cells
may start with `Deferred` and Android cells must start with `Pass`. Evidence
cell must contain a concrete artifact such as a group ID, invite code,
screenshot filename, or Firestore document path. Evidence cell must also
include build traceability: commit SHA, APK/AAB SHA-256, Play track/build
number, or the relevant output from `tool/print_android_qa_handoff.sh`.
Generic words like `build` or `artifact` are not enough by themselves.

| ID | Area | iOS | Android | Evidence |
|---|---|---|---|---|
| RD-01 | Create group | Deferred — v1.2 Android-only | Pass — Pixel 9 Pro XL, Android 16 | Group "QA 2026-06-05" id 00dbec67-4286-4237-bd5e-36c1fd5ff40b; invite HN9TFU; creator Alice; group detail+settings open with no permission errors. Build app-debug.apk d425e954e346, prod rihla-safar |
| RD-02 | Join group by invite code | Deferred — v1.2 Android-only | Pass — Pixel 9 Pro XL + emulator | Joined on 2nd client via enforced joinGroupByInviteCode under live App Check (debug token); code HN9TFU; Bob claimed; both clients show 2 members. Build app-debug.apk d425e954e346 |
| RD-03 | Delete group | Deferred — v1.2 Android-only | Pass — Pixel 9 Pro XL + emulator | Enforced deleteGroup succeeded after settle-to-zero; group disappeared on both clients, no permission loop; prod groups/00dbec67-4286-4237-bd5e-36c1fd5ff40b isDeleted=true deletedAt 2026-06-05T13:56:39Z. Build app-debug.apk d425e954e346 |
| RD-04 | Two-device ledger identity | Deferred — v1.2 Android-only | Pass — Pixel 9 Pro XL + emulator (see note) | Expense "QA coffee" 1.500 OMR paid-by Alice; both clients show Bob owes Alice 0.750, payer label "Alice", no self-owe. 2nd client = Pixel_10_Pro EMULATOR — accepted physical-device deviation. Build app-debug.apk d425e954e346 |
| RD-05 | Decimal expense input | Deferred — v1.2 Android-only | Pass — Pixel 9 Pro XL + emulator | Decimal "." separator present on keypad; 1.500 entered and saved; ledger renders OMR 0.750 / 1.500 at 3dp on both clients. Build app-debug.apk d425e954e346 |
| RD-06 | Offline and reconnect | Deferred — v1.2 Android-only | Pass — Pixel 9 Pro XL | Airplane mode: cached Home/group/event/Activity stayed visible; reconnect refreshed all screens with no stuck false-offline. Build app-debug.apk d425e954e346 |
| RD-07 | Notification opt-in | Deferred — v1.2 Android-only | Pass — Pixel 9 Pro XL | fcm_tokens/EsGOBaZVvYQNXD2u32ad23xN8wP2 created updateTime 2026-06-05T13:36:42Z with token + platform=android + locale=en. Build app-debug.apk d425e954e346 |
| RD-08 | Notification opt-out | Deferred — v1.2 Android-only | Pass — Pixel 9 Pro XL | Same fcm_tokens doc deleted (HTTP 404) on opt-out; not recreated after cold relaunch with toggle off. Build app-debug.apk d425e954e346 |
| RD-09 | Arabic RTL golden path | Deferred — v1.2 Android-only | Pass — Pixel 9 Pro XL | #126 CLOSED; full RTL across Home/Profile/Activity/Group/Event/TypePicker/CreateEvent/AddExpense/Ledger; back arrows point right; invite codes + currency stay LTR. Build app-debug.apk d425e954e346 |

## 2026-06-05 Android-only pass (debug build + App Check debug token)

All nine rows recorded Pass against the production Firebase backend (`rihla-safar`).

- **Build under test:** `app-debug.apk` from `main @ d425e954e3461aedacbc38155bf13e501702fd1d` (pubspec `1.3.2+20`), SHA-256 `2d01ef4ae7c6f931446957a0d38bfd025971cb0ebc1df3de0466bd2fa816f068`.
- **App Check:** debug build → `AndroidDebugProvider`; per-install debug tokens were registered to prod App Check via the management API so the enforced callables (`joinGroupByInviteCode`, `deleteGroup`) could be exercised. Both callables succeeded under live attestation; tokens were deleted from prod afterwards.
- **Devices:** Pixel 9 Pro XL (Android 16, physical) as Alice; **Pixel_10_Pro emulator** (Android 37, Google APIs Play Store) as Bob.
- **RD-04 deviation (accepted):** the two-device row used the emulator as the second client. The cross-device ledger identity verified correctly (both clients showed `Bob owes Alice 0.750`, payer `Alice`, no self-owe), but this is **not** two physical Androids.

**Gate status:** `tool/check_real_device_qa_gate.sh` (with `RIHLA_SKIP_IOS_QA=yes`) still reports FAIL on its hard requirement of **two physical Android devices** (emulators are excluded by design). `RIHLA_REAL_DEVICE_QA_READY` is therefore left **unset** — flip it only after RD-04 is re-confirmed on a second physical Android (or the gate/criteria are amended to accept the emulator for RD-04). Tracked under #40.

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
