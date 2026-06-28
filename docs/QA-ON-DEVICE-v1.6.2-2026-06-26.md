# Rihla v1.6.2 On-Device QA Findings

Date: 2026-06-26, Asia/Muscat  
Devices: Samsung SM-G770F, Android 13, 1080x2400 @ 420 dpi; Google Pixel 9 Pro XL, Android 16, 1344x2992 @ 480 dpi  
Build under test: `1.6.2+26`, commit `d7545beb3be690924527acc1098fb7c456fac49f` (`v1.6.2`)  
Local APK: `build/app/outputs/flutter-apk/app-release.apk`  
Local APK SHA-256: `9006ef610b99aee368ade41a64f8dfc14ec365b09602fd1621543becd3eaa5bd`  
Play install: `Rihla: Split Bills & Settle Up (Beta)`, `versionName=1.6.2`, `versionCode=26`, `installerPackageName=com.android.vending`  
Evidence folder: `docs/qa-evidence/v1.6.2-device-qa/`

## Scope And Result

This was a physical Android QA pass against both a freshly built local release APK and the Play Store beta install of the same `1.6.2+26` package. It covered first launch, create/join entry points, profile/account backup, notification permission handling, language/RTL, offline banner behavior, email-recovery validation, and the reachable parts of the v1.6.2 changelog.

Result: **App Check / anonymous join passes on a clean Play Integrity device, while two Samsung-raised UX bugs reproduce on Pixel.** The earlier Samsung App Check failures are not valid release-blocker evidence because that phone is an ineligible integrity surface: verified boot is `orange`, bootloader state is `unlocked`, and Magisk/Hide My Root are installed. Server-side checks logged to #679 found the App Check provider, APIs, SHA-256 registrations, and Android app identity healthy. On a Play-installed Pixel 9 Pro XL with green verified boot and a locked bootloader, clearing app data created a fresh anonymous app state; `D6BWJA` first reached group logic and rejected `Nasser` as already used, then succeeded with unique display name `PixelQA` and landed in group `Camedy` with `GROUP · 4 MEMBERS`. That means the callable was reached and App Check did not block the clean-device Play artifact. The same Pixel production session also reproduced the create-group validation persistence bug, reproduced the weak offline event-settings feedback, passed production event creation, passed an exact-split expense save/read-back with `OMR 1.234`, and narrowed Activity behavior to entry-point-specific results.

## Debug Emulator-Backed Addendum

To avoid touching a real Google account or production data, I temporarily ran a debug `1.6.2+26` build on the same Samsung device against local Firebase Auth, Firestore, and Functions emulators. The app needed a debug-only cleartext allowance for the laptop LAN IP; without it, Firebase Auth failed at startup with `Cleartext HTTP traffic to 192.168.100.55 not permitted`. After that harness issue was resolved, `tool/seed_demo.js` seeded one group, one event, four members, six expenses, one settlement, and activity rows under the phone's anonymous emulator UID.

Additional evidence: `43-debug-emulator-seeded-home.png` through `72-debug-group-delete-confirmation-tap2.png`.

Covered successfully in the emulator-backed pass:
- Home showed the seeded group, active journey, net balance, recent activity, and backup nudge.
- Group detail showed balance, event list, people balances, and group actions.
- Event command center and ledger showed totals, member balances, settlement row, expense rows, filters, and sticky Add expense / Settle up actions.
- Expense edit opened from a ledger row and showed amount, category, payer, participant scope, split mode, event/date, and delete affordance.
- Exact split UI was reachable from the `How` selector and showed per-person exact amount inputs plus OMR total/remainder labels.
- Settle Up produced optimized transfers and the current-user `Mark received` action.
- Cross-group Activity rendered settlement, member, and event entries with working filter chips visible.
- Group settings rendered invite code `KHAR26`, copy/QR/share actions, member management, OMR default currency, and danger-zone actions.

Offline event-settings result (#670): while Wi-Fi was disabled, I changed the event name from `Salalah Khareef Trip` to `Salalah Khareef Trip QA` and tapped Save. Flutter logs showed Firestore `WriteStream` failures while offline, then the emulator document later contained `name: "Salalah Khareef Trip QA"` after Wi-Fi returned. The event header and Home card reflected the new name. Data persistence passed, but the settings screen stayed in place without a clear queued/saved success state, so the UX is weaker than the data behavior.

## Setup Evidence

- The phone initially had `com.safar.safar` `versionName=1.5.0`, `versionCode=22`.
- `adb install -r build/app/outputs/flutter-apk/app-release.apk` failed with `INSTALL_FAILED_UPDATE_INCOMPATIBLE` because the existing app signature did not match the new APK.
- I uninstalled only `com.safar.safar`, installed the built `1.6.2` APK fresh, and confirmed `versionName=1.6.2`, `versionCode=26`.
- I later uninstalled the sideloaded APK and installed `Rihla: Split Bills & Settle Up (Beta)` from Google Play. Package metadata confirmed `versionName=1.6.2`, `versionCode=26`, `installerPackageName=com.android.vending`, and no `DEBUGGABLE` flag.
- After the user clarified the real invite code was `D6BWJA`, I cleared Rihla app data and retested from a fresh Play-installed state.
- After #679 was updated with healthy server-side App Check checks, I cleared app data again and reran the Play-installed `D6BWJA` test. It still failed with `403 App attestation failed`.
- Device integrity caveat: `ro.boot.verifiedbootstate=orange`, `ro.boot.flash.locked=0`, `ro.boot.vbmeta.device_state=unlocked`, and installed packages include `com.topjohnwu.magisk` and `com.amphoras.hidemyroot`.
- I then connected a Google Pixel 9 Pro XL running Android 16. Its package metadata showed the same Play-installed `versionName=1.6.2`, `versionCode=26`, `installerPackageName=com.android.vending`, and no `DEBUGGABLE` flag.
- Pixel integrity checks were clean: `ro.boot.verifiedbootstate=green`, `ro.boot.flash.locked=1`, and `ro.boot.vbmeta.device_state=locked`.
- I cleared only Rihla app data on the Pixel to remove the existing local Firebase anonymous session/cache, then launched from a fresh empty Groups state.
- Pixel retest with invite code `D6BWJA` and display name `Nasser` reached business logic and returned `That name's already used in this group. Please pick a different name.`
- Pixel retest with the same invite code and unique display name `PixelQA` succeeded and landed on group `Camedy` with `GROUP · 4 MEMBERS`.
- In the joined production group, Pixel reproduced the create-form validation bug with valid text `PixelQAGroup` while `Name can't be empty.` remained visible.
- Pixel created production event `PixelQAEvent`, then edited it offline to `PixelQAEventOffline`. Firestore logged `UNAVAILABLE` / `Unable to resolve host firestore.googleapis.com` while offline; after network restoration, the event title persisted as `PixelQAEventOffline`.
- Pixel saved production expense `PixelExact` for `OMR 1.234` with exact split amounts `0.111`, `0.222`, `0.333`, and `0.568`; the success screen and ledger/event read-back preserved `OMR 1.234` and the expected balances.
- Pixel event-scoped Activity opened from the event and Android Back returned to the ledger. The visible bottom Activity tab also rendered. External `/activity` intents were still not a verified app route: HTTPS did not resolve, and `rihla:///activity` did not navigate to Activity.
- Battery started at 2% and reached 19% during the first Pixel pass. Wi-Fi, data, and airplane mode were restored after the offline pass.

## High Priority Findings

### 1. App Check blocker not reproduced on clean Pixel; anonymous join succeeds

Evidence: Samsung failure screenshots/logs: `88-play-install-real-code-filled-d6.png`, `92-play-install-real-code-d6-logcat.txt`, `98-play-install-fresh-d6-logcat.txt`, `105-play-install-post-679-d6-logcat.txt`. Pixel clean-device screenshots/logs: `106-pixel-play-fresh-after-clear.png`, `107-pixel-play-fresh-after-wait.png`, `113-pixel-play-join-screen-correct.png`, `114-pixel-play-join-d6-filled.png`, `118-pixel-play-join-d6-logcat.txt`, `119-pixel-play-join-d6-pixelqa-filled.png`, `120-pixel-play-join-d6-pixelqa-before-submit.png`, `121-pixel-play-join-d6-pixelqa-submit-0-7s.png`, `123-pixel-play-join-d6-pixelqa-submit-8-2s.png`, `123-pixel-play-join-d6-pixelqa-window.xml`, `123-pixel-play-join-d6-pixelqa-logcat.txt`.

Severity: no longer a release sign-off blocker after clean-device retest. The Samsung remains invalid for production App Check QA.

Samsung result:
1. Play-installed `1.6.2+26`, `installerPackageName=com.android.vending`, no `DEBUGGABLE` flag.
2. Cleared Rihla app data.
3. Entered corrected real invite code `D6BWJA`.
4. Submitted as anonymous user.

Samsung actual: the app showed `Please sign in and try again.` Fresh logcat showed `Error returned from API. code: 403 body: App attestation failed`, then `Too many attempts.`

Samsung device-integrity evidence from ADB: `ro.boot.verifiedbootstate=orange`, `ro.boot.flash.locked=0`, `ro.boot.vbmeta.device_state=unlocked`; installed packages include `com.topjohnwu.magisk` and `com.amphoras.hidemyroot`. This device should not be used as a production Play Integrity sign-off surface.

Pixel clean-device result:
1. Connected Google Pixel 9 Pro XL, Android 16.
2. Verified Play-installed package: `versionName=1.6.2`, `versionCode=26`, `installerPackageName=com.android.vending`, no `DEBUGGABLE` flag.
3. Verified clean integrity state: `ro.boot.verifiedbootstate=green`, `ro.boot.flash.locked=1`, `ro.boot.vbmeta.device_state=locked`.
4. Cleared only Rihla app data to remove the previous local anonymous session/cache.
5. Opened Join Group from a fresh empty Groups state.
6. Entered `Nasser` and `D6BWJA`; submit returned `That name's already used in this group. Please pick a different name.`
7. Replaced the name with `PixelQA`, kept `D6BWJA`, and submitted.

Pixel actual: the app navigated into group `Camedy`; UIAutomator reported `GROUP · 4 MEMBERS`, member initials `N`, `M`, `H`, `P`, and the group detail surface. The scoped Pixel submit log has no App Check attestation failure or `403` entry.

Code review explains why this is decisive:
- `functions/src/callables/joinGroupByInviteCode.ts:222` sets `enforceAppCheck: true`, so App Check must pass before the callable runs.
- `functions/src/callables/joinGroupByInviteCode.ts:224-233` only rejects missing auth and explicitly documents that anonymous users may join.
- `lib/features/groups/providers/group_provider.dart:301-304` documents `NO durable gate on join`.
- `lib/main.dart:66-68` passes `useDebugAppCheck: !kReleaseMode || _useFirebaseEmulator`.
- `lib/core/config/firebase_config.dart:44-47` uses `AndroidPlayIntegrityProvider` for release mode.

Interpretation: #679 is not reproduced on a clean locked Pixel with the Play beta artifact. The Samsung 403s are best classified as invalid-device App Check failures, not a production App Check configuration failure and not an anonymous-join regression. The remaining useful issue is UX copy: `Please sign in and try again.` is misleading when App Check rejects an ineligible device.

### 2. Create-form validation error stays visible after correction

Evidence: Samsung `05-create-submit-validation.png`, `06-create-name-filled.png`; Pixel production `126-pixel-create-group-start.png`, `127-pixel-create-group-form.png`, `128-pixel-create-group-empty-error.png`, `129-pixel-create-group-error-after-correction.png`, `129-pixel-create-group-error-after-correction-window.xml`.

Steps:
1. Open Create Group.
2. Submit with empty name.
3. Enter a valid group name into the name field.

Actual: the red error text `Name can't be empty.` remained visible while the field contained valid text. On Pixel, UIAutomator captured `text="PixelQAGroup"` and nested content description `Name can't be empty.` in the same field.

Impact: moderate UX friction. The user can continue, but the form looks like it still rejects a valid value.

### 3. Remaining durable-account production QA still needs a test-account pass

Not yet covered on the release / Play beta artifact:
- Create real group and invite code.
- Durable Google link/recover/account-switch flows.
- Itemized split edit/read-back and settlement flows.
- Group delete and delete-lock recovery.
- Two-device identity and notification delivery.

Reason: anonymous join, production event creation, production event settings, and production exact split are now verified on the clean Pixel Play install. The remaining flows require selecting a durable Google/email account, deleting shared production objects, or exercising multi-device identity/notifications. Those should use a dedicated test Google account and test group.

## Medium Priority Findings

### 4. App Check rejection surfaces misleading sign-in copy

Evidence: `80-real-invite-submit-4-5s.png`, `80-real-invite-submit-logcat.txt`, `98-play-install-fresh-d6-submit-8-6s.png`, `98-play-install-fresh-d6-logcat.txt`

When Play Integrity/App Check attestation failed on the sideloaded release APK and on the compromised Samsung Play-installed artifact, the user-facing message was `Please sign in and try again.` That copy matches the callable `unauthenticated` mapping, but it is misleading when the effective cause is device attestation rather than missing user auth. This can send QA and users toward the wrong fix.

### 5. Offline event-settings save has weak feedback

Evidence: emulator-backed `60-debug-event-settings-wifi-off-before-edit.png`, `61-debug-event-settings-offline-title-edited.png`, `62-debug-event-settings-offline-save-result.png`, `64-debug-event-settings-after-reconnect.png`, `65-debug-event-title-after-offline-save.png`; Pixel production `137-pixel-event-settings-name-edited-online.png`, `138-pixel-connectivity-after-disable.txt`, `138-pixel-event-settings-offline-before-save.png`, `139-pixel-event-settings-offline-save-0-7s.png`, `140-pixel-event-settings-offline-save-3-7s.png`, `141-pixel-event-settings-offline-save-8-7s.png`, `141-pixel-event-settings-offline-save-window.xml`, `141-pixel-event-settings-offline-save-logcat.txt`, `142-pixel-connectivity-restored-state.txt`, `143-pixel-event-title-after-offline-save.png`, `143-pixel-event-title-after-offline-save-window.xml`.

The offline event-settings write did persist after reconnect, but the screen stayed on the edit form while offline and did not give an obvious queued/saved state. On Pixel production, the event name edit to `PixelQAEventOffline` was made while Firestore logged `UNAVAILABLE` against `firestore.googleapis.com`; after network restoration, the event title persisted as `PixelQAEventOffline`. This is not data loss, but it leaves the user unsure whether tapping Save worked.

## What Passed Or Looked Healthy

### First launch and empty Groups state

Evidence: `01-first-launch.png`

The first-run state is clear: primary actions are Create Group and Join Group, restore options are visible, and bottom navigation is understandable. The value prop is short and appropriate for the product.

### Create group form and durable-account gate

Evidence: `02-create-group-gate.png`, `07-create-submit-gate-or-result.png`, `08-create-not-now.png`

The stamp picker renders correctly, with ink swatches, symbol grid, and monogram fallback. Valid submit as an anonymous user shows the `Keep your money safe` durable-account sheet. `Not now` returns to the form and does not create a group.

UX note: the user can fill the entire form before learning that Google backup is required for creation. This is defensible, but it is a business-friction point.

### Join group screen

Evidence: `10-join-group.png`

The join screen itself is understandable: name field, prominent 6-character code field, reassurance copy, and disabled-looking submit state before required input.

### Anonymous production join on clean Pixel

Evidence: `113-pixel-play-join-screen-correct.png`, `114-pixel-play-join-d6-filled.png`, `118-pixel-play-join-d6-submit-8-6s.png`, `119-pixel-play-join-d6-pixelqa-filled.png`, `120-pixel-play-join-d6-pixelqa-before-submit.png`, `123-pixel-play-join-d6-pixelqa-submit-8-2s.png`, `123-pixel-play-join-d6-pixelqa-window.xml`

After clearing app data on a Play-installed Pixel 9 Pro XL, the corrected invite code `D6BWJA` reached server-side group logic. `Nasser` was rejected because that name was already used; changing only the display name to `PixelQA` succeeded and opened group `Camedy` with four members. This verifies the anonymous join path on the clean production artifact.

### Production event creation and exact split on clean Pixel

Evidence: `131-pixel-camedy-before-event.png`, `132-pixel-create-event-start.png`, `133-pixel-create-event-filled.png`, `135-pixel-create-event-submit-4s.png`, `135-pixel-create-event-submit-window.xml`, `144-pixel-add-expense-start.png`, `145-pixel-add-expense-basic-filled.png`, `146-pixel-expense-how-customise.png`, `147-pixel-expense-exact-mode.png`, `148-pixel-expense-exact-filled.png`, `149-pixel-expense-exact-applied.png`, `151-pixel-add-expense-submit-3-8s.png`, `151-pixel-add-expense-submit-window.xml`, `152-pixel-ledger-after-exact-expense.png`, `152-pixel-ledger-after-exact-expense-window.xml`, `154-pixel-ledger-list-open.png`, `154-pixel-ledger-list-open-window.xml`.

Pixel created event `PixelQAEvent` in production group `Camedy`, selected all four participants, and later renamed it to `PixelQAEventOffline`. It then saved `PixelExact` for `OMR 1.234` in category `Food & Dining`, with exact split amounts `Nasser=0.111`, `Mohammed=0.222`, `Hatim=0.333`, and `PixelQA=0.568`. The success screen showed `Expense Saved`, `SYNCED TO CLOUD`, and `OMR 1.234`. Event and ledger read-back showed `PixelExact`, `OMR 1.234`, debtor rows for `OMR 0.111`, `OMR 0.222`, `OMR 0.333`, and Pixel net `+OMR 0.666`.

### Activity navigation on clean Pixel

Evidence: `156-pixel-event-activity-log.png`, `156-pixel-event-activity-log-window.xml`, `157-pixel-event-activity-back-result.png`, `157-pixel-event-activity-back-result-window.xml`, `158-pixel-https-activity-intent-output.txt`, `158-pixel-https-activity-intent-result.png`, `159-pixel-rihla-activity-intent-output.txt`, `159-pixel-rihla-activity-intent-result.png`, `162-pixel-relaunch-rihla.png`, `163-pixel-activity-tab-real.png`, `163-pixel-activity-tab-real-window.xml`, `164-pixel-activity-tab-back-result.png`.

Event-scoped Activity passed: the event Activity log showed `PixelQA added a money entry`, `PixelExact`, and `OMR 1.234`; Android Back returned to the ledger. The visible bottom Activity tab also passed: it rendered the cross-group Activity screen with filters and `Camedy` entries. Android Back from that bottom-nav tab exited to the launcher/search surface, which is expected tab-root behavior. External route behavior remains unverified/failing: `https://rihla-safar.web.app/activity` did not resolve to the app, and `rihla:///activity` was delivered to the running app but did not route to Activity.

### Profile / account backup

Evidence: `21-profile-anonymous.png`, `22-profile-backup-sheet.png`

Anonymous profile state is clear: `Not backed up`, zero groups/spend stats, backup card, QR/handle chips, and the same durable-account sheet from the backup card.

### Notification permission handling

Evidence: `23-notifications-toggle.png`, `24-notifications-denied-state.png`

Tapping Notifications surfaced the Android runtime permission prompt. After choosing `Don't allow`, the in-app row stayed off and changed to `Enable in device Settings`, which is honest and avoids falsely claiming notifications are enabled.

### Language and RTL

Evidence: `25-language-sheet.png`, `26-profile-arabic-rtl.png`, `28-offline-groups-arabic.png`

The language sheet is clear. Arabic RTL layout on Profile and Groups is coherent: nav order flips, text alignment is right-to-left, directional icons move appropriately, and mixed LTR tokens like `QR` and `@nasser` remain readable.

### Offline banner on reachable screen

Evidence: `31-offline-create-arabic.png`

After airplane mode and a resume/connectivity update, Create Group showed an offline banner: the Arabic copy indicated offline status and later sync. The banner is visible and appropriately placed.

### Email recovery local validation

Evidence: `34-email-restore-entry.png`, `35-email-restore-invalid.png`

The email recovery screen is reachable. Invalid input `bad` shows a clear inline error: `That doesn't look like an email.`

## v1.6.2 Changelog Coverage

| v1.6.2 item | Device result |
|---|---|
| Anonymous join / #648 behavior | Passed on clean Play-installed Pixel 9 Pro XL. `D6BWJA` first returned a real group/name collision for `Nasser`, proving the callable was reached, then joined successfully with unique name `PixelQA`. Samsung App Check failures are invalid-device evidence, not a production blocker. |
| #662 Account-switch group-orphan guard | Not run. Requires selecting a Google account and exercising conflict/swap. Skipped to avoid touching a real account. |
| #670 Offline event-settings writes | Data path passed in both emulator-backed Samsung and Play-installed Pixel production passes. Pixel edited `PixelQAEvent` to `PixelQAEventOffline` while Firestore logged offline `UNAVAILABLE`, then the title persisted after reconnect. UX caveat reproduced: no clear queued/saved feedback while offline. |
| #671 Offline account restore | Not fully run. Email recovery screen and validation were checked; real restore was skipped to avoid sending/using real credentials. |
| #672/#673 Self-healing group-delete locks | Still not fully run. Group settings danger zone was visible in emulator-backed pass, but I did not confirm deletion. The visible Delete button did not open a confirmation from my coordinate taps, so lock recovery remains unverified. |
| #674 Exact-split currency | Passed on Play-installed Pixel production artifact. Saved `PixelExact` for `OMR 1.234` with exact amounts `0.111`, `0.222`, `0.333`, and `0.568`; success and ledger/event read-back preserved `OMR 1.234` and the expected balances, including Pixel net `+OMR 0.666`. |
| #666 Activity back navigation | Event-scoped Activity back passed on Pixel: Activity log opened and Android Back returned to ledger. Visible bottom Activity tab rendered and Back exited to launcher/search, as expected for a tab root. External `/activity` entry remains unverified/failing: HTTPS did not resolve to the app, and `rihla:///activity` did not route to Activity. |

## UX / Business Notes

- The strongest first-run path is Join Group, and it passed on the clean Play-installed Pixel. The earlier Samsung App Check failure is still useful as a device-eligibility warning, but it should not block release sign-off by itself.
- The create flow looks polished but asks for durable identity only after the form is complete. If the business goal is low-friction activation, consider surfacing the requirement earlier or making the sheet explain why the entered work is preserved.
- The backup messaging is consistent across Home/Profile/Create and communicates risk without sounding destructive.
- Notification denial state is well handled and avoids the silent-failure confusion older notification work tried to prevent.
- Arabic/RTL is strong on the screens tested.

## Accessibility Risks From Screenshots

- Several secondary labels use low-contrast muted text on a dark textured background. It looks on-brand, but should be checked with actual contrast tooling, especially Arabic secondary copy and disabled/secondary buttons.
- The large invite-code input and major CTAs have strong target sizes.
- Icon-only controls such as the profile share icon, bell, QR chip, and edit pencil need semantic labels verified with TalkBack; screenshots alone cannot prove that.
- Keyboard and focus order were not audited with TalkBack or hardware keyboard.

## Device Cleanup

- Airplane mode restored to off.
- Wi-Fi/data restored after the Pixel offline test; airplane mode state was `0`, and `ping 8.8.8.8` succeeded.
- App language restored to English.
- Notification permission was reset to not granted with user-set/user-fixed flags cleared where Android allowed it.
- The temporary debug/emulator build was uninstalled after the addendum pass.
- The sideloaded release APK was removed.
- The Play-installed app remains `versionName=1.6.2`, `versionCode=26`, `installerPackageName=com.android.vending`; package flags did not include `DEBUGGABLE`.
- I cleared Rihla app data on the Pixel before the clean-device retest. After the successful retest, the Pixel now has a fresh anonymous Rihla session joined to group `Camedy` as `PixelQA`, plus production QA data: event `PixelQAEventOffline` and expense `PixelExact` for `OMR 1.234`.
- Old local `1.5.0` app data, sideloaded release data, and emulator-only debug data were removed during uninstall/reinstall or app-data clear operations.

## Recommended Next Pass

The clean-device App Check / anonymous-join pass is complete, and #679 was updated as not reproduced on the locked Pixel. The Pixel production retest also covered the Samsung failures that could be tested without a durable account. Exclude the Samsung from production App Check sign-off. Then run the remaining production smoke with a dedicated test Google account:

1. Durable Google link/restore using a test Google account.
2. Account-switch group-orphan guard.
3. Itemized expense edit/read-back and settlement flows.
4. Group delete / member remove during delete-lock scenarios.
5. Activity cold-route back behavior from the actual notification/deep-link entry point.
