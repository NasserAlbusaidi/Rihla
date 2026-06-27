# Issue #368 — Android Play Install Referrer invite prefill

**Date:** 2026-06-27
**Issue:** #368 — `feat(invite): deferred invites (Android) — Play Install Referrer capture -> pre-filled /join`
**Branch:** `feat/368-install-referrer`
**Base verified:** `77b7c96b` (`v1.6.3`, `origin/main`)
**Gate category:** routing + join write-path adjacency -> fresh-context Gate REQUIRED before production code.
**ADR:** `docs/adr/ADR-0005-android-install-referrer-invites.md`

## Goal

Complete the missing Android consumer for deferred invites: when a not-yet-installed
user opens `https://rihla-safar.web.app/join/<CODE>`, installs from Play, then
first launches Rihla, the app reads the Play Install Referrer once, extracts
`code=<CODE>`, and routes to the existing `/join/<CODE>` screen.

This must be **prefill only**. The referrer is untrusted and attacker-controlled,
so it never joins a group silently. The user lands on the existing join screen,
sees the code, enters/keeps their display name, and confirms. The server-side
join callable remains the authority.

## Current state verified

| Surface | Status |
|---|---|
| Hosted sender | `hosting/join.html` validates `^[A-Z0-9]{6}$` and appends `&referrer=${encodeURIComponent('code=' + code)}` to the Play URL, so the browser URL carries `referrer=code%3DABC123`. |
| Installed-user deep links | `DeepLinkService.parseJoinLink` normalizes custom-scheme and Hosting URLs to `/join/<CODE>`. |
| Join route | `AppRoutes.joinInvite = '/join/:code'` passes `initialInviteCode` into `JoinGroupScreen`. |
| Join prefill | `JoinGroupScreen.initState` sets `_codeController.value` directly. Manual typing still auto-submits at 6 chars via `onChanged`, but route prefill does not trigger `onChanged`, so no callable runs until the user taps the CTA or edits the field. |
| Existing dedupe | `DeepLinkService` dedupes normalized join paths with `_seenKeys`. |
| Native bridge | `MainActivity.kt` currently has only the cache-isolation method channel. No install-referrer channel exists. |
| Gradle | `android/app/build.gradle.kts` has no `com.android.installreferrer` dependency. |

## Stale ADR correction

The issue body/comment from 2026-06-20 says to reuse the old #441 anonymous
join reject. That is stale after #648. Current safety is:

- `joinGroupByInviteCode` keeps `enforceAppCheck: true`.
- The join callable still rate-limits attempts at 5/hour per UID.
- The install referrer only navigates to `/join/<CODE>`.
- `JoinGroupScreen` pre-fills the code with a programmatic controller
  assignment. Its six-character auto-submit is tied to user-edit `onChanged`,
  not the initial route parameter assignment.
- Route prefill must not call `joinGroupByInviteCode`, `listUnclaimedShadows`,
  `requestClaimShadow`, `listMyClaimRequests`, create a local pending intent, or
  perform any write/read-write side effect. Those paths remain behind existing
  explicit join-screen user actions.
- The user still confirms, and the callable validates the invite code and name.

Do not reintroduce an anonymous-join gate for this issue.

## Product behavior

1. First launch after Play install asks Android Play for the install referrer.
2. If no referrer, unsupported Play Store, non-Android platform, native error, or
   invalid payload: do nothing.
3. If the referrer contains one valid `code` matching `^[A-Z0-9]{6}$`: normalize
   to uppercase and route once to `/join/<CODE>`.
4. If the app was already launched by a recognized explicit Rihla link, that
   current link wins over the stored Play referrer. Recognized explicit links
   for this arbitration are:
   - invite joins accepted by `DeepLinkService.parseJoinLink`
   - `rihla://auth-link?...` email-link fallback URLs
   - Firebase auth continue URLs matching
     `AuthEmailLinkConfig.looksLikeEmailAuthLink`
   - Firebase Auth URLs accepted by
     `FirebaseConfig.auth.isSignInWithEmailLink`
5. After a valid referrer has been handled, it is consumed so later app launches
   do not keep forcing the user back to the join screen.

## Ordering decision

Install-referrer routing should be part of the same cold-start join-link story,
not a separate navigation channel.

Preferred shape:

- Keep `DeepLinkService` as the join-link normalization and dedupe owner.
- Add an install-referrer helper/service that converts raw Play referrer payloads
  into a normalized target path `/join/<CODE>` and routes with `router.go`
  directly. Do **not** route the Play referrer through `DeepLinkService`'s
  explicit-link dedupe set; otherwise the referrer could poison runtime
  re-opening of the same real invite link in this process.
- Keep `DeepLinkService` as the AppLinks join-link normalization owner. Its
  `_seenKeys` guard should be scoped to the bounded cold-start duplicate
  emissions from `getInitialLink()` + `uriLinkStream`, not a permanent
  process-wide block for every future explicit invite link.
- Change `DeepLinkService.init(...)` to return a small decision object, e.g.
  `DeepLinkInitialDecision(joinRouted, suppressInstallReferrer)`.
  `joinRouted` reports whether an explicit cold-start join route was opened.
  `suppressInstallReferrer` is true when either a join route opened or a
  caller-injected auth-link predicate recognized the URI. Both values must
  include `getInitialLink()` and a short initial `uriLinkStream` race window
  because `app_links` can surface a cold-start URI through either path. Runtime
  stream opens after that initial window still go through `openJoinLink`, but
  they do not delay bootstrap.
- The initial-link lookup is also bounded: `getInitialLink()` must be raced
  against `initialLinkTimeout`, defaulting to `Duration(milliseconds: 250)`. On
  timeout or error, continue with the stream-window result so install-referrer
  routing and gate replay cannot hang indefinitely.
- Add an injected `bool Function(Uri) suppressInstallReferrerFor` predicate to
  `DeepLinkService.init`, defaulting to false. In production bootstrap, extract
  and reuse an auth-link recognizer that mirrors
  `authEmailLinkBootstrapProvider.handleUri`: extract the private
  `_emailLinkFromUri`/recognition logic into a shared auth-link recognizer used
  by both auth bootstrap and install-referrer arbitration. It unwraps
  `rihla://auth-link?...` when present, then returns true if the link satisfies
  `AuthEmailLinkConfig.looksLikeEmailAuthLink(link)` or
  `FirebaseConfig.auth.isSignInWithEmailLink(link)`. The recognizer only
  suppresses the install referrer; the existing auth bootstrap still handles the
  auth link.
- Do not let a stale Play referrer override a current explicit app/universal
  link. Use `DeepLinkInitialDecision.suppressInstallReferrer`: when true, skip
  install-referrer routing.

`GateIntentReplay` currently runs immediately after an unawaited
`DeepLinkService.init`, so a pending `auth.pendingGateIntent` can clobber a
deferred invite. Fix the contract explicitly:

- Bootstrap should await the cold-start navigation decision inside a post-frame
  async task.
- The `DeepLinkService.init` cold-start decision must wait long enough to catch a
  stream-only initial join link without hanging boot. Use a bounded
  `initialStreamWindow`, defaulting exactly to `Duration(milliseconds: 50)`.
  The decision completes after both `getInitialLink()` resolves and the 50 ms
  stream window elapses, or after the window if `getInitialLink()` errors. Expose
  the same injectable window in tests so the stream-only explicit-link case is
  deterministic.
- Compute `joinAlreadyRouted = deepLinkDecision.joinRouted || installReferrerRouted`.
- Make `GateIntentReplay.maybeReplay` return `Future<void>` and call
  `await GateIntentReplay.maybeReplay(..., skipNavigation: joinAlreadyRouted)`.
  When `skipNavigation` is true because a join won, `GateIntentReplay` must
  `await PendingGateIntent.clear(prefs)` before the recover-op early return and
  instead of leaving the marker to hijack the next launch. Auth-link-only
  suppression of the Play referrer does not set `skipNavigation`.
- Add a test that seeds `auth.pendingGateIntent`, returns a valid install
  referrer, and verifies navigation is `/join/<CODE>` only, not
  `/create-group`, and verifies `PendingGateIntent.read(prefs)` is null so a
  second replay attempt cannot navigate on the next boot.
- Add a test where `getInitialLink()` returns null, `uriLinkStream` emits
  `/join/NEW222` during the initial stream window, and an older install referrer
  contains `OLD111`; expected navigation is `/join/NEW222` only.
- Add a test where `getInitialLink()` returns an auth email link and an older
  install referrer contains `OLD111`; expected result is no `/join/OLD111`.

## Android implementation plan

### Native bridge

- Add `implementation("com.android.installreferrer:installreferrer:2.2")`.
- Add a second method channel in `MainActivity.kt` exactly named
  `com.safar.safar/install_referrer`.
- Expose exactly one method, `getInstallReferrer`.
- Use `InstallReferrerClient.newBuilder(this).build()`.
- On `InstallReferrerResponse.OK`, return
  `client.installReferrer.installReferrer`.
- On `FEATURE_NOT_SUPPORTED`, `SERVICE_UNAVAILABLE`, disconnection, or exception,
  return `null` rather than crashing app bootstrap.
- Always call `endConnection()` exactly once after a connection attempt finishes.
- Because `InstallReferrerClient` completes asynchronously, guard both result
  completion and connection closure:
  - `finish(value)` completes the Flutter `MethodChannel.Result` at most once.
  - `closeClient()` calls `endConnection()` at most once.
  - `onInstallReferrerServiceDisconnected()` returns `null` only if no result
    has completed yet; late disconnects after `OK` are ignored.

Android's own guidance says the referrer is only available for installs from
Google Play, the app should invoke the API during the first launch, and the
client connection must be closed after retrieval.

### Dart service

Create a small service, likely `lib/core/services/install_referrer_service.dart`:

- Inject the native read function for tests.
- Inject an `isAndroid` predicate/default platform seam. Production uses
  `!kIsWeb && defaultTargetPlatform == TargetPlatform.android`; tests force
  Android for valid-route cases and force non-Android for the no-op case.
- Read the raw referrer from the method channel.
- The Dart read seam is `Future<String?> Function()`; production calls
  `const MethodChannel('com.safar.safar/install_referrer')
      .invokeMethod<String>('getInstallReferrer')`.
- Parse the raw referrer as a query-string payload, never as an absolute URI.
  Reject absolute URI payloads (`http://...`, `https://...`, `rihla://...`) even
  if their query contains `code`, so retired-host URLs cannot be smuggled
  through this path.
- Use this deterministic parsing algorithm:
  1. Try parsing the raw query string and read `code` via `queryParametersAll`.
  2. Accept only exactly one `code` value. Reject duplicate `code` keys, even if
     the values match.
  3. If exactly one code is not present and the raw string contains percent
     escapes, decode once with `Uri.decodeQueryComponent(raw)` inside
     `try/catch`; malformed percent escapes are a silent no-op. Parse the
     decoded string using the same query-string-only and exactly-one-code rules.
  4. Trim and uppercase the final `code`.
  5. Ignore unrelated extra params; reject only when the normalized code is
     missing or fails `^[A-Z0-9]{6}$`.
  Tests must cover `code=ABC123`, `code%3DABC123`, `utm_source=x&code=ABC123`,
  `code=ABC123&utm_source=x`, absolute URI rejection, malformed `%` no-op, and
  duplicate rejection for both `code=ABC123&code=DEF456` and
  `code=ABC123&code=ABC123`.
- Normalize with the same invite-code rule as deep links.
- Persist one-shot consumed state in `SharedPreferences` after a valid code is
  either successfully routed or intentionally consumed without routing because a
  current explicit auth/join link suppressed the Play referrer:
  - key: `installReferrerInviteConsumedCode`
  - value: normalized code, e.g. `ABC123`
  If the same code is seen again, no-op. If an invalid payload is seen, do not
  persist anything.
- Treat malformed payloads as no-op. The referrer is not a trust signal.
- Expose `consumeDeferredInvite(...)` or equivalent with a `route` boolean:
  `route: true` reads/parses/routes/consumes, and `route: false`
  reads/parses/consumes without navigation for explicit-link suppression. It
  returns whether it routed, so suppressed consumption returns false.
- Bound the native referrer read with `nativeReadTimeout`, defaulting to
  `Duration(milliseconds: 750)`. On timeout, return false and write nothing so
  the cold-start coordinator cannot block gate replay, app bootstrap, or
  notification sync indefinitely.
- Return `true` only when a valid referrer caused
  `router.go('/join/<CODE>')` to run. Return `false` for no referrer, invalid
  referrer, already-consumed code, native errors, unsupported platform, and
  suppressed consumption.

### Cold-start coordinator

Replace the current split startup ordering with one ordered coordinator in
`_SafarAppState.initState` after the cache-isolation early return:

1. Capture `router` and `prefs`.
2. Do **not** activate `appBootstrapProvider` from `SafarApp.build` before this
   coordinator completes. Move the `ref.watch(appBootstrapProvider)` activation
   out of `build`; activate it after install-referrer arbitration so
   `authEmailLinkBootstrapProvider` cannot process an auth link and restart the
   app before a valid suppressed referrer is consumed.
3. In an async bootstrap navigation helper:
   - `final deepLinkDecision = await DeepLinkService.instance.init(
       router,
       suppressInstallReferrerFor: isRecognizedAuthLink,
       initialStreamWindow: const Duration(milliseconds: 50),
       initialLinkTimeout: const Duration(milliseconds: 250),
     );`
   - `final installReferrerRouted = await InstallReferrerService.instance
       .consumeDeferredInvite(
           router,
           prefs,
           DeepLinkService.instance,
           route: !deepLinkDecision.suppressInstallReferrer,
         );`
     A suppressed valid referrer is consumed without routing so it cannot route
     on the next cold boot.
   - `await GateIntentReplay.maybeReplay(
       prefs,
       router.go,
       skipNavigation: deepLinkDecision.joinRouted || installReferrerRouted,
     );`
   - Activate `appBootstrapProvider` after the above awaited steps, so auth
     email-link handling starts only after any valid suppressed Play referrer has
     been consumed.
   - Run the eager boot-time notification sync after invite/gate arbitration.
     Add a `handleInitialMessage` parameter (or equivalent) so
     `kickInitialNotificationSync` / `NotificationService.initialize` can still
     save tokens and attach notification listeners while skipping
     `_handleInitialMessage()` when `joinAlreadyRouted` is true. Background or
     foreground notification taps after startup still route normally.

The exact async ordering needs tests because current code starts
`DeepLinkService.instance.init(...)` with `unawaited` and immediately runs
`GateIntentReplay`, while `appBootstrapProvider` currently starts auth-link
handling during `build`.

## TDD plan

Write failing tests before production code.

### Unit: install-referrer parsing/one-shot

New `test/unit/install_referrer_service_test.dart`:

- `code=abc123` normalizes to `/join/ABC123`.
- Plain decoded `code=ABC123` parses correctly.
- URL-encoded `code%3DABC123` from the Hosting Play URL parses correctly.
- Missing code, empty code, invalid length, punctuation, retired host payloads,
  and unrelated marketing params are ignored.
- Duplicate `code` keys are rejected.
- Valid referrer routes once; a second invocation with the same preferences does
  not route again.
- Valid suppressed referrer is consumed without routing; a second boot with the
  same referrer is a no-op.
- Native errors and null referrers are no-ops.
- Non-Android platform path is a no-op if the service exposes a platform seam.

### Unit: deep-link/bootstrap ordering

Extend `test/unit/deep_link_service_test.dart` or add a focused bootstrap test:

- A current explicit cold-start join link beats an older install referrer.
- A current explicit auth email link suppresses an older install referrer without
  routing to `/join`, and a valid suppressed referrer is consumed so it cannot
  route on the next boot.
- Auth email-link bootstrap starts only after suppressed referrer consumption,
  so a recovery restart cannot win the race before
  `installReferrerInviteConsumedCode` is written.
- A valid install referrer routes when there is no explicit join link.
- When a valid install referrer routes to `/join/<CODE>`, boot-time notification
  sync does not process an initial FCM tap that would navigate elsewhere.
- Cold-start duplicate normalized targets from `getInitialLink()` +
  `uriLinkStream` are routed once.
- After the bounded cold-start window, re-opening the same explicit invite link
  routes again and is not blocked by a previously consumed install referrer.
- Gate intent replay does not override a valid install-referrer invite when
  `auth.pendingGateIntent` is present, and the skipped marker is cleared.
- Programmatic route prefill does not call `joinGroup`, `listUnclaimedShadows`,
  `requestClaimShadow`, or `listMyClaimRequests`; those remain behind user
  actions.

### Guard: sender and native bridge

Extend `test/unit/auth_link_hosting_files_test.dart`:

- `hosting/join.html` still emits `referrer=${encodeURIComponent('code=' + code)}`.
- Play link still uses package `com.safar.safar`.

Add a focused source guard if no better Android test exists:

- `android/app/build.gradle.kts` declares `com.android.installreferrer:installreferrer`.
- `MainActivity.kt` defines the install-referrer method channel and calls
  `endConnection()`.
- Dart and Kotlin sources both contain the exact channel name
  `com.safar.safar/install_referrer` and method `getInstallReferrer`.
- `main.dart` no longer activates `appBootstrapProvider` in `build` before the
  cold-start coordinator runs.
- Notification initialization has a source-level/test guard for
  `handleInitialMessage: false` (or equivalent) skipping only
  `_handleInitialMessage()`, not token/listener setup.

### Existing tests that must stay green

- `flutter test test/unit/deep_link_service_test.dart`
- `flutter test test/unit/auth_link_hosting_files_test.dart`
- `flutter test test/unit/app_router_test.dart`
- `flutter test test/unit/group_service_durable_gate_test.dart`

## Acceptance

- [ ] Android first launch after Play install consumes a valid referrer and
      one-shot routes to `/join/<CODE>`.
- [ ] Referrer remains prefill-only; no auto-join and no callable invocation
      happens from route prefill.
- [ ] A current explicit app/universal link wins over a stale install referrer.
- [ ] Invalid/missing/native-error referrers are silent no-ops.
- [ ] One-shot behavior prevents repeated forced navigation on later launches.
- [ ] No iOS clipboard path is added.
- [ ] ADR text is corrected: no #441 anonymous reject; safety is App Check,
      throttling, validation, and prefill-only UX.
- [ ] Fresh-context Gate passes before implementation merges.

## Verification caveat

Unit/source tests can prove parsing, one-shot routing, bootstrap ordering, and
the Android bridge shape. Full end-to-end verification needs a Play-delivered
build because the Play Install Referrer API cannot be exercised through a bare
emulator install.
