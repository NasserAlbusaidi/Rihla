# Real-Device QA

Last prepared: 2026-05-15

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
- Every RD-01 through RD-08 row below has an iOS result starting with `Pass`,
  an Android result starting with `Pass`, and evidence that replaces the
  placeholder text.

Pass criteria (with `RIHLA_SKIP_IOS_QA=yes` — v1.2 Android-only):

- At least one physical Android device is listed.
- iOS device absence reported as INFO.
- `config.json` and Firebase platform files as above.
- Every RD-01 through RD-08 row has an Android result starting with `Pass`,
  an iOS result starting with `Pass` or `Deferred`, and concrete Android
  evidence in the Evidence cell.

Current local status from 2026-05-15: blocked for Android. The matrix is
filled with `Deferred — v1.2 Android-only` for iOS; the Android column and
evidence still need a real run on a connected Android device.

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
build source, and Firebase project. For release, both iOS and Android cells must
start with `Pass` and the Evidence cell must contain a concrete artifact such as
a group ID, invite code, screenshot filename, or Firestore document path.

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
