# iOS Sign in with Apple (App Store 4.8 fix) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Issue:** #1256 (P0, release-blocker) — iOS submission rejected 2026-07-15 under Guideline 4.8.0 Design: Login Services.

**Goal:** Add Sign in with Apple as a coequal link/restore provider next to Google on iOS (and wire the mandatory 5.1.1(v) Apple-token revocation into account deletion), so the resubmission clears 4.8 without removing Google.

**Architecture:** Mirror the Google provider pair exactly. A new `AppleSignInGateway` obtains a two-phase credential (interactive Apple sheet FIRST, Firebase swap later) via the `sign_in_with_apple` package; `AuthRecoveryService` gains `linkAppleToCurrentUser()` / `restoreWithApple()` following the byte-identical cross-UID protocol (`fcm-token removal → engageIsolation → flush → dirty-mark → signInWithCredential → outcome write → guaranteed restart`), reusing `outgoingShellProvablyEmpty` unchanged. The durable-credential sheet and every launcher surface offer Apple at ≥ Google prominence on iOS only; Android is byte-identical to today. Account deletion best-effort revokes the Apple token (fresh authorization code → `FirebaseAuth.revokeTokenWithAuthorizationCode`) before the server cascade.

**Tech Stack:** Flutter, `firebase_auth` 6.3.0 (installed), `sign_in_with_apple` ^7.0.1 (new — pinned to the version whose source was verified on disk; the published 8.1.0 is a deliberate follow-up upgrade, not part of this change), `crypto` (promoted from transitive), Riverpod 2.x, mocktail.

**Not touched:** `security/firestore.rules`, `functions/**`, `BalanceCalculator`/money, `app_router.dart` (no new routes — the sheet gains a button, not a screen), Firestore schema. Android surfaces and `google_sign_in` flows unchanged.

---

## Verification log (all claims re-checked against code this session, 2026-07-15)

Every claim below was verified by direct Read/grep in this session — none is carried from memory or agent citation.

| Claim | How verified | Result |
|---|---|---|
| `firebase_auth` resolves 6.3.0 | `pubspec.lock:348-354` | direct main, 6.3.0 |
| `AppleAuthProvider.credentialWithIDToken(idToken, rawNonce, AppleFullPersonName)` exists | `firebase_auth_platform_interface-8.1.8/lib/src/providers/apple_auth.dart:50-60,137-145` | yes; `AppleFullPersonName()` all-optional ctor |
| `FirebaseAuth.revokeTokenWithAuthorizationCode(String)` exists | `firebase_auth-6.3.0/lib/src/firebase_auth.dart:797` | yes |
| Native iOS plugin captures `authorizationCode` on sign-in, link, AND reauth | `FLTFirebaseAuthPlugin.m:418-460` (all three completion branches) → `additional_user_info.dart:35` | **CONFIRMED** — resolved the issue's open question, but NOTE (Gate R2): this native path is informational only; the design (D1/Task 12) reads `authorizationCode` from the `sign_in_with_apple` package credential, never from `additionalUserInfo` |
| Apple cancel surfaces as `FirebaseAuthException(code: 'canceled')` via native path; `SignInWithAppleAuthorizationException(AuthorizationErrorCode.canceled)` via the package | `FLTFirebaseAuthPlugin.m` (ASAuthorizationErrorCanceled → FlutterError 'canceled') + `exception.dart:16-36` conversion; package API | both handled below |
| `sign_in_with_apple` | installed source verified at `~/.pub-cache/.../sign_in_with_apple-7.0.1` (Gate R1+R2) | every API this spec uses exists in the 7.0.1 source on disk: `getAppleIDCredential(scopes:, nonce:)` (sign_in_with_apple.dart:54), `identityToken` nullable, NON-nullable `authorizationCode`, `SignInWithAppleButton` with **nullable `onPressed`** + `style`/`text`/`height` (widgets/sign_in_with_apple_button.dart:12-23), `AuthorizationErrorCode.canceled` (exceptions.dart:114/146). **Pin `^7.0.1`** — 8.1.0 is published but unverified across the major bump (Gate R2 P2) |
| `crypto` already in the tree | `pubspec.lock:236` | transitive — promote to direct |
| Google mirror shapes | `auth_recovery_service.dart` read in full (508 lines): `GoogleCredentialFactory` L18, `isGoogleAccountAlreadyInUse` L42 (code-only, provider-agnostic), `linkGoogleToCurrentUser` L257, `restoreWithGoogle` L302 | template confirmed |
| Conflict exception carries credential (never read `FirebaseAuthException.credential` — nullable, flutterfire #9920) | `durable_credential_exception.dart` read in full | confirmed |
| Sheet structure | `durable_credential_sheet.dart` read in full (468 lines): `_continueWithGoogle`, `_switchAccount`, conflict `FutureBuilder`, keys `durableGate.continue`/`durableGate.switch` | confirmed |
| Shell gate is provider-agnostic | `shell_emptiness_gate.dart` signature (user/groups/probe/timeout thunks only); call pattern in `google_restore_action.dart:27-32` | reused verbatim, no change |
| `RecoveryOutcome` ops | `recovery_outcome.dart:33-35` (`google`/`recover`/`signout`); no whitelist on read; success-toast gate at `recovery_outcome_notice.dart:91-92` | add `opApple` + widen gate |
| Deletion flow | `data_deletion_service.dart` read in full; sole call site `danger_zone_card.dart:62`; `deleteAccount.ts` has zero Apple references (grepped `functions/src`) | client-side revoke slots in before the callable; **no Functions change** |
| Durable marker | `durable_account_marker_provider.dart:26` marks reactively off auth state | provider-agnostic — Apple link flips it for free |
| Launcher surfaces (5) | `home_screen.dart:390-421` (`home_empty_recover_cta` ungated by isAnonymous), `profile_screen.dart` `_AccountCard`, `backup_account_card.dart`, `account_backup_nudge.dart:33-114`, `claim_requests_section.dart:96` | all funnel into the sheet or `triggerGoogleRestore` |
| l10n keys naming Google | `app_en.arb`: `durableGateBody` 2372, `durableGateConflict` 2384, `durableGateConflictSwitchBody` 2392, `profileBackupCardBody` 261, `homeBackupNudgeBody/Cta` 1309-1310; also `signOutContentGoogle` (no-email fallback, `sign_out_confirm_dialog.dart:49-50`) and `deleteGuestSessionContent` | **shared values, no platform variant — never edit them** (Gate R1 P1): Apple-conflict copy dispatches to NEW keys by exception subtype; iOS link-prompt copy selects NEW `*Ios` keys at the call sites; Android strings stay byte-identical |
| iOS signing | `ExportOptions.plist` + `project.pbxproj`: automatic signing, team T2U886CPS5; `Runner.entitlements` currently aps-environment + associated-domains only | entitlement edit auto-regenerates profiles at archive once the capability is enabled on the App ID |
| `googleAccountProvider` / `isDurableUserProvider` | `auth_provider.dart:46-65` | Apple sibling mirrors the providerData scan; `isDurableUserProvider` needs no change |
| ProfileKeys | `profile_keys.dart:40-46` | add `appleAccountTile`, `profileRestoreAppleTile` |

**Callsite classification (verification principle 1):** all new UI surfaces are launchers (OUTBOUND → Firebase Auth mutations: link / signInWithCredential / revoke). `appleAccountProvider` and all copy changes are INBOUND/display-only. No Firestore read/write path changes anywhere; the only persisted-state change is the `RecoveryOutcome` marker gaining a new `op` string value (read one-shot by the boot notice — read-path traced at `recovery_outcome_notice.dart:91`).

---

## Design decisions (rationale that the code can't show)

### D1 — Two-phase credential via `sign_in_with_apple`, NOT `firebase_auth`'s native `signInWithProvider`
FlutterFire's default recommendation (`signInWithProvider`/`linkWithProvider`) fuses the interactive Apple sheet and the auth mutation into ONE call. That breaks two load-bearing properties of this codebase:

1. **Restore ordering.** `restoreWithGoogle`'s doc comment (L284-301) pins: credential obtained interactively FIRST, so a user-cancel throws with the shell fully intact — *no overlay, no swap, no restart*. With `signInWithProvider` the sheet would appear INSIDE the isolation window: cancel → guaranteed restart (UX regression), or worse, the UID swaps before isolation is engaged (the #68 cache-bleed class) if called pre-isolation.
2. **Conflict credential reuse.** The `linkWithProvider` conflict path cannot hand the failed credential to the switch flow — `FirebaseAuthException.credential` is nullable (flutterfire #9920), the exact reason `GoogleLinkConflictException` carries the credential explicitly. Without it, "Switch account" would need a SECOND Apple sheet.

So: `SignInWithApple.getAppleIDCredential(nonce: sha256(rawNonce))` → `AppleAuthProvider.credentialWithIDToken(idToken, rawNonce, AppleFullPersonName())` → the existing `linkWithCredential`/`signInWithCredential` machinery, exactly like Google. Cost: one new dependency + ~15 lines of nonce code (`crypto`). The package's credential also exposes `authorizationCode` directly — used for D5.

### D2 — Sealed conflict-exception hierarchy, `GoogleLinkConflictException` keeps its name
`sealed class LinkConflictException { credential; cause; }` with `GoogleLinkConflictException` / `AppleLinkConflictException` subclasses. The sheet's `_conflict` field widens to the base type and `_switchAccount` dispatches exhaustively by subtype to `restoreWithGoogle`/`restoreWithApple`. Existing throw sites and tests are untouched (the Google subclass keeps its exact shape). A mis-routed Apple conflict into the Google switch path is the #414/#647 wrong-account data-orphan class — the sealed switch makes it a compile error.

### D3 — iOS-only surfaces via `defaultTargetPlatform == TargetPlatform.iOS`
Not `Platform.isIOS` — `defaultTargetPlatform` is overridable in widget tests (`debugDefaultTargetPlatformOverride`), and per the established test convention the override must be reset in the test body before tearDowns run. Android renders byte-identical widget trees to today (pinned by existing tests, which keep passing without platform overrides because the test default platform is android).

### D4 — Apple placement ≥ Google on iOS (the 4.8 parity requirement)
The sheet's iOS layout stacks: **official `SignInWithAppleButton`** (package widget — canonical HIG appearance; black in light theme, white in dark; custom-drawn Apple buttons are a documented review-flag risk) FIRST, then the existing Google primary button at the same height (52), then "Not now". List-row surfaces (home empty state, profile rows) add an Apple text row ABOVE the Google row with identical styling — Apple's HIG accepts plain-text affordances in settings-style lists. A reviewer pattern-matching "third-party login present, is Apple ≥ prominent?" must find yes on every surface.

### D5 — 5.1.1(v) revocation is client-side, best-effort, same build
`deleteAccount()` (client), before the server callable: if `user.providerData` contains `apple.com`, obtain a FRESH Apple authorization (Apple codes are short-lived/single-use — the original link-time code is long dead, and persisting it would buy only a ~5-minute window) via the same gateway, then `_auth.revokeTokenWithAuthorizationCode(code)`. Any failure — user cancels the Apple sheet, offline, Apple error — logs and **proceeds with deletion**: deletion is a user right and is never hostage to an Apple round-trip; Firebase's `deleteUser` drops the provider link regardless, and the residual OAuth grant on Apple's side is removable by the user in Settings. No timeout on the interactive prompt (the user initiated deletion; a cancel is the abort signal). **No Cloud Functions change** — the heavier server-side REST `/auth/revoke` path (stored refresh token + signed JWT) is explicitly rejected as YAGNI; revisit only if Apple review demands non-interactive revocation.

**Accepted risk (state verbatim in the implementation PR body):** best-effort + interactive revocation means a silently failed revoke still deletes the account. What App Review actually exercises is delete → re-sign-in with the same Apple ID → data must be gone — which this design satisfies regardless of revoke outcome (the server cascade is unconditional). The residual exposure is a lingering OAuth grant in the user's Apple ID settings, not data. If a resubmission is nonetheless rejected on 5.1.1(v), the fallback is the server-side stored-refresh-token revoke — a Gate-category Functions/schema change to be spec'd separately.

### D6 — Copy stays accurate per provider and per platform; NO shared-value edits (rewritten after Gate R1 [P1])
The naive fix — neutralizing shared string VALUES — silently changes Android copy while the sheet there remains Google-only, violating the "Android: zero change" boundary (Gate R1 adversary finding). Instead:

1. **Conflict copy dispatches by exception subtype, not platform.** `GoogleLinkConflictException` → existing `durableGateConflict`/`durableGateConflictSwitchBody` (values untouched — still correctly say "Google" for Google conflicts on BOTH platforms). `AppleLinkConflictException` → new `durableGateConflictApple`/`durableGateConflictSwitchBodyApple` ("That Apple ID already belongs to another Rihla account…" / "This Apple ID already has Rihla data. Switch to it? …"). `durableGateConflictTitle` is already provider-neutral — reused.
2. **Link-prompt copy selects an `*Ios` key at the call site** when `defaultTargetPlatform == TargetPlatform.iOS`: `durableGateBodyIos`, `profileBackupCardBodyIos`, `homeBackupNudgeBodyIos`, `homeBackupNudgeCtaIos` (neutral "Link an account…" phrasing, since the iOS sheet offers Apple + Google). Android call sites keep the existing keys — byte-identical strings.
3. **Sign-out dialog (Gate R1 [P2]; path corrected — the reviewer cited a wrong dir):** `lib/features/auth/widgets/sign_out_confirm_dialog.dart:50` falls back to `signOutContentGoogle` whenever `email` is null/empty — an Apple-linked user with a relay-withheld email would be told to sign back in with a Google account they don't have. The dialog is a plain StatelessWidget taking only `email` (verified), so add `this.hasAppleProvider = false` and branch `null || '' => hasAppleProvider ? l10n.signOutContentApple : l10n.signOutContentGoogle`; the caller (`profile_screen.dart` `_signOut`) passes `hasAppleProvider: ref.read(appleAccountProvider) != null`. Android behavior unchanged (provider always null there).
4. **Guest-session delete copy (Gate R1 [P3]; call site verified):** `lib/features/auth/widgets/delete_account_dialog.dart:37` picks `deleteGuestSessionContent` ("Google or email") — on iOS select new `deleteGuestSessionContentIos` ("Any Google, Apple, or email account you've linked…"); Android keeps the existing key. Platform check = `defaultTargetPlatform == TargetPlatform.iOS` via `package:flutter/foundation.dart` inside `build()` (the dialog is a plain StatelessWidget — Gate R2 P3).
5. **Accepted (Gate R2 P3, documented not fixed):** an Apple user whose relay email IS present hits the sign-out dialog's `final linked =>` branch and sees email-based restore advice — Google-parity behavior (D8); relay addresses receive Firebase mail once the D8 domain registration is done, and the user can equally re-Sign-in-with-Apple. No change.

Net: zero existing ARB values change; every new string is a new key in BOTH locales. `generated_l10n_surface_test` and `check_arb_completeness_test` stay green by construction.

### D7 — `RecoveryOutcome.opApple = 'apple'`
The marker's `op` is a free string with no read-side whitelist; the ONLY consumer branching on it is the success-toast gate (`recovery_outcome_notice.dart:91-92`), which must include `opApple` so a successful Apple restore shows the "restored" notice after the forced restart (and the #990 name-seed heal applies identically). No version bump (`v` stays 2 — shape unchanged).

### D8 — Email/private-relay interplay is accepted, not engineered around
A Hide-My-Email Apple link sets `user.email` to a `@privaterelay.appleid.com` address; `linkedEmailProvider` will show it, exactly as a Google link surfaces its email today (behavior parity — the #428 PR-B sign-out guard was widened for precisely this shape). Firebase-sent mail reaches relay addresses only after the sender domain is registered with Apple's private email relay service — that is a **manual config step** (below), not code.

---

## Data contracts (exact — verification principle 5)

```dart
// apple_sign_in_gateway.dart
typedef AppleCredentialBundle = ({AuthCredential credential, String? authorizationCode});
// auth_recovery_service.dart
typedef AppleCredentialFactory = Future<AppleCredentialBundle> Function();
// recovery_outcome.dart
static const String opApple = 'apple';
```

(`authorizationCode` is non-nullable in the package's `AuthorizationCredentialAppleID` — the bundle keeps it `String?` deliberately, a defensive widening across package majors; the null-guard in Task 12 defends OUR seam contract, which test fakes may exercise.)

New widget keys: `durableGate.continueApple`, `home_empty_recover_apple_cta`, `ProfileKeys.appleAccountTile = Key('profile_apple_account_tile')`, `ProfileKeys.profileRestoreAppleTile = Key('profile_restore_apple_tile')`.

New l10n keys (en + ar, both ARBs — **no existing value is edited**, per D6): `durableGateContinueApple` ("Continue with Apple"), `homeRestoreWithApple` ("Restore with Apple"), `restoreAppleFailed` ("Couldn't sign in with Apple. Please try again."), `profileAccountApple` ("Apple"), `profileAccountAppleLinked` ("Linked"), `profileAccountLinkAccount` ("Link an account"), `durableGateConflictApple` ("That Apple ID already belongs to another Rihla account. Switching to it would leave this phone's current groups behind — they're tied to a temporary identity that can't be moved. Resolve them first, then use a different Apple ID."), `durableGateConflictSwitchBodyApple` ("This Apple ID already has Rihla data. Switch to it? This device will continue with that account."), `durableGateBodyIos` ("Your groups and expenses are tied to this account. Link an account so they can't be lost with this device."), `profileBackupCardBodyIos` ("Your trips live only on this phone. Link an account so you never lose them."), `homeBackupNudgeBodyIos` ("Your groups and expenses live only on this phone. Link an account so a new phone, reinstall, or lost device can't erase them."), `homeBackupNudgeCtaIos` ("Link account"), `signOutContentApple` (sign-out body naming "the same Apple ID"), `deleteGuestSessionContentIos` ("Any Google, Apple, or email account you've linked is separate and won't be deleted."). Arabic values keep "Apple" in Latin script per Apple brand rules.

---

## Manual configuration checklist (no code; do BEFORE merging the implementation PR so TestFlight builds work)

1. Apple Developer portal → Certificates, Identifiers & Profiles → App ID `com.nalbusaidi.rihla` → enable **Sign In with Apple** capability.
2. Create a **Services ID** (e.g. `com.nalbusaidi.rihla.signin`) with Return URL `https://rihla-safar.firebaseapp.com/__/auth/handler`. Required even for iOS-only — Firebase validates the token audience server-side.
3. Create a **Sign in with Apple key** (`.p8`), note the Key ID. Store the key in the keychain/password manager — never in the repo.
4. Firebase console → Authentication → Sign-in method → **Apple**: enable; Services ID + Team ID `T2U886CPS5` + Key ID + key contents.
5. Apple Developer portal → Services → Sign in with Apple for Email Communication: register `noreply@rihla-safar.firebaseapp.com` (private-relay mail, D8).
6. No fastlane change: automatic signing regenerates the provisioning profile at next archive once step 1 is done.

---

## Tasks

### Task 0: Dependencies

**Files:** Modify: `pubspec.yaml`

**Step 1:** Add under `dependencies:` — `sign_in_with_apple: ^7.0.1` and `crypto` (caret-pinned to the version the lockfile already holds transitively). **Pin 7.x, not latest** (Gate R2 P2): every API this spec uses was verified against the 7.0.1 source on disk; 8.1.0 is published but UNVERIFIED across the major bump — upgrading is a separate, deliberate follow-up with its own API check, not a side effect of `pub add`.
**Step 2:** `flutter pub get` clean; confirm `pubspec.lock` shows both as `direct main` and `sign_in_with_apple` resolved to 7.x.
**Step 3:** Commit: `chore(deps): add sign_in_with_apple + promote crypto for #1256`

### Task 1: Entitlement + guard test

**Files:** Modify: `ios/Runner/Runner.entitlements` · Create: `test/unit/ios_apple_signin_config_guard_test.dart`

**Step 1 (RED):** Write the guard test (mirror `test/unit/ios_deep_linking_guard_test.dart`'s file-read style):
```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Runner.entitlements carries the Sign in with Apple entitlement (#1256)', () {
    final content = File('ios/Runner/Runner.entitlements').readAsStringSync();
    expect(content, contains('com.apple.developer.applesignin'));
  });
}
```
**Step 2:** `flutter test test/unit/ios_apple_signin_config_guard_test.dart` → FAIL (key absent).
**Step 3 (GREEN):** Add to `ios/Runner/Runner.entitlements` inside the `<dict>`:
```xml
	<key>com.apple.developer.applesignin</key>
	<array>
		<string>Default</string>
	</array>
```
**Step 4:** Re-run → PASS. **Step 5:** Commit: `feat(ios): Sign in with Apple entitlement + config guard (#1256)`

### Task 2: `AppleSignInGateway`

**Files:** Create: `lib/features/auth/services/apple_sign_in_gateway.dart` · Test: `test/unit/apple_sign_in_gateway_test.dart`

Mirror `google_sign_in_gateway.dart`'s thin-adapter shape. Seam: inject the package call as a function so tests never touch platform channels.

```dart
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Credential + the short-lived Apple authorization code from the same
/// authorization. The code is consumed ONLY by the 5.1.1(v) delete-time
/// revocation (`FirebaseAuth.revokeTokenWithAuthorizationCode`) — it is
/// single-use and expires in minutes, so it is never persisted.
typedef AppleCredentialBundle = ({
  AuthCredential credential,
  String? authorizationCode,
});

typedef GetAppleIDCredential =
    Future<AuthorizationCredentialAppleID> Function({
      required List<AppleIDAuthorizationScopes> scopes,
      String? nonce,
    });

/// Thin adapter over sign_in_with_apple (#1256), the Apple sibling of
/// [GoogleSignInGateway]. Two-phase on purpose (D1): the interactive sheet
/// runs HERE, before any isolation/auth mutation, so a user-cancel throws
/// with the anon shell fully intact and the conflict path can reuse the
/// credential without a second sheet.
class AppleSignInGateway {
  AppleSignInGateway({GetAppleIDCredential? getAppleIDCredential, Random? random})
    : _getAppleIDCredential =
          getAppleIDCredential ?? _defaultGetAppleIDCredential,
      _random = random ?? Random.secure();

  static Future<AuthorizationCredentialAppleID> _defaultGetAppleIDCredential({
    required List<AppleIDAuthorizationScopes> scopes,
    String? nonce,
  }) => SignInWithApple.getAppleIDCredential(scopes: scopes, nonce: nonce);

  final GetAppleIDCredential _getAppleIDCredential;
  final Random _random;

  static const _nonceChars =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';

  String _generateRawNonce([int length = 32]) => List.generate(
    length,
    (_) => _nonceChars[_random.nextInt(_nonceChars.length)],
  ).join();

  /// Runs the interactive Apple sheet and returns a Firebase credential ready
  /// for [User.linkWithCredential] / [FirebaseAuth.signInWithCredential],
  /// plus the fresh authorization code for delete-time revocation.
  ///
  /// Anti-replay: Apple receives the SHA-256 of the raw nonce; Firebase
  /// receives the raw nonce and verifies the token's hashed claim matches.
  /// Throws [SignInWithAppleAuthorizationException] (e.g. canceled) from the
  /// sheet; [StateError] when the sheet yields no identityToken.
  Future<AppleCredentialBundle> obtainCredential() async {
    final rawNonce = _generateRawNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();
    final apple = await _getAppleIDCredential(
      scopes: const [AppleIDAuthorizationScopes.email],
      nonce: hashedNonce,
    );
    final idToken = apple.identityToken;
    if (idToken == null || idToken.isEmpty) {
      throw StateError('Apple authorization returned no identityToken');
    }
    return (
      credential: AppleAuthProvider.credentialWithIDToken(
        idToken,
        rawNonce,
        AppleFullPersonName(),
      ),
      authorizationCode: apple.authorizationCode,
    );
  }
}
```

**Tests (write first, watch fail for the right reason — file doesn't exist):**
1. passes SHA-256 hex of a 32-char raw nonce to `getAppleIDCredential` (capture the `nonce:` arg; recompute `sha256(rawNonceUsedInCredential)` from the returned `OAuthCredential.rawNonce` and expect equality — proves raw-vs-hashed wiring, the classic SiwA bug).
2. returned bundle: `credential` is `OAuthCredential` with `providerId == 'apple.com'`, `idToken` == stubbed identityToken; `authorizationCode` passed through.
3. null/empty `identityToken` → `StateError`.
4. `SignInWithAppleAuthorizationException` propagates unchanged.
5. two calls produce different nonces.

Run: `flutter test test/unit/apple_sign_in_gateway_test.dart` → PASS. Commit: `feat(auth): AppleSignInGateway — two-phase Apple credential (#1256)`

### Task 3: Sealed conflict hierarchy

**Files:** Modify: `lib/features/auth/services/durable_credential_exception.dart` · Test: extend `test/unit/auth_recovery_service_google_restore_test.dart` neighbors only if they construct the exception (they construct `GoogleLinkConflictException` — shape unchanged, no edits expected).

```dart
/// Base for durable-credential link conflicts (#1256): the chosen provider
/// account already backs a different Firebase user. Sealed so the sheet's
/// switch dispatch is exhaustive — routing an Apple conflict into the Google
/// restore (or vice versa) is the #414/#647 wrong-account swap class, made a
/// compile error here. Carries the exact credential that failed to link so
/// the switch path never re-prompts — never read
/// [FirebaseAuthException.credential], which can be null (flutterfire #9920).
sealed class LinkConflictException implements Exception {
  const LinkConflictException({required this.credential, required this.cause});
  final AuthCredential credential;
  final FirebaseAuthException cause;
}

class GoogleLinkConflictException extends LinkConflictException {
  const GoogleLinkConflictException({required super.credential, required super.cause});
  @override
  String toString() =>
      'Google account already in use by another Rihla account (${cause.code}).';
}

class AppleLinkConflictException extends LinkConflictException {
  const AppleLinkConflictException({required super.credential, required super.cause});
  @override
  String toString() =>
      'Apple account already in use by another Rihla account (${cause.code}).';
}
```

Run the existing conflict suites: `flutter test test/features/auth/durable_credential_sheet_conflict_test.dart test/unit/auth_recovery_service_google_restore_test.dart` → PASS unchanged. Commit: `refactor(auth): sealed LinkConflictException base + Apple sibling (#1256)`

### Task 4: `RecoveryOutcome.opApple` + boot-notice gate

**Files:** Modify: `lib/features/auth/services/recovery_outcome.dart` (add `static const String opApple = 'apple';` beside L33-35), `lib/features/auth/services/recovery_outcome_notice.dart:91-92` (success-toast gate becomes `op != opGoogle && op != opApple && op != opRecover → return`). Test: extend `test/unit/recovery_outcome_notice_test.dart`.

**RED first:** a test asserting an `op: 'apple', ok: true, expectedUid: matching` marker shows `restoredOk` — fails today (gate returns early). Then GREEN. Also assert the #990 name-seed heal fires for the verified-apple arm (mirror the existing opGoogle case). Commit: `feat(auth): opApple recovery-outcome + boot notice (#1256)`

### Task 5: `AuthRecoveryService.linkAppleToCurrentUser` / `restoreWithApple`

**Files:** Modify: `lib/features/auth/services/auth_recovery_service.dart` · Tests: create `test/unit/auth_recovery_service_apple_test.dart` (mirror the google restore/link test files' fixtures).

Additions (mirror Google line-for-line; same doc-comment obligations):
```dart
typedef AppleCredentialFactory = Future<AppleCredentialBundle> Function();
// ctor: AppleCredentialFactory? appleCredentialFactory  →
//   _appleCredentialFactory = appleCredentialFactory ?? _defaultAppleCredentialFactory;
static final AppleSignInGateway _defaultAppleGateway = AppleSignInGateway();
static Future<AppleCredentialBundle> _defaultAppleCredentialFactory() =>
    _defaultAppleGateway.obtainCredential();

/// Apple sibling of [linkGoogleToCurrentUser] (#1256). Same-UID; conflicts
/// rethrow as [AppleLinkConflictException] carrying the failed credential.
Future<UserCredential> linkAppleToCurrentUser() async {
  final user = _auth.currentUser;
  if (user == null) {
    throw StateError('No current user; ensureAnonymousSession first');
  }
  final bundle = await _appleCredentialFactory();
  try {
    final result = await user.linkWithCredential(bundle.credential);
    FirebaseConfig.log('Recovery: linked Apple to uid ${result.user?.uid}');
    return result;
  } on FirebaseAuthException catch (e) {
    if (isGoogleAccountAlreadyInUse(e)) { // code-only classifier, provider-agnostic (L42)
      throw AppleLinkConflictException(credential: bundle.credential, cause: e);
    }
    rethrow;
  }
}

/// Apple sibling of [restoreWithGoogle] (#1256) — identical protocol and
/// identical load-bearing ordering (see that method's doc comment). The
/// caller must prove the outgoing shell empty first.
Future<UserCredential> restoreWithApple({
  AuthCredential? credential,
  Duration pendingWritesTimeout = const Duration(seconds: 5),
}) async {
  final appleCredential =
      credential ?? (await _appleCredentialFactory()).credential;
  await _removeFcmTokenBestEffort(pendingWritesTimeout);
  _cacheIsolationController.engageIsolation();
  try {
    try {
      final firestore = _firestore ?? FirebaseFirestore.instance;
      await firestore.waitForPendingWrites().timeout(pendingWritesTimeout);
    } on TimeoutException {
      FirebaseConfig.log(
        'Restore: waitForPendingWrites timed out after '
        '${pendingWritesTimeout.inSeconds}s — restoring anyway',
      );
    }
    await markFirestorePersistenceDirty(_prefs);
    final result = await _auth.signInWithCredential(appleCredential);
    FirebaseConfig.log('Restore: restored uid ${result.user?.uid}');
    await writeRecoveryOutcome(_prefs,
        op: RecoveryOutcome.opApple, ok: true, expectedUid: result.user?.uid);
    return result;
  } catch (e) {
    await writeRecoveryOutcome(_prefs,
        op: RecoveryOutcome.opApple, ok: false, code: recoveryOutcomeCodeOf(e));
    rethrow;
  } finally {
    await _cacheIsolationController.restart();
  }
}
```

**Tests (RED each first):** credential obtained BEFORE `engageIsolation` (ordering probe — factory throw must leave isolation un-engaged and no restart called); FCM removal before isolation; success writes `opApple` outcome with expectedUid then restarts; failure writes failed outcome, rethrows, still restarts; NO `signOut` anywhere on the failure path (#414/#213); link conflict rethrows `AppleLinkConflictException` carrying the same credential instance; supplied `credential:` skips the factory (conflict-path reuse — factory must not be called). Commit: `feat(auth): linkApple/restoreWithApple mirroring the Google pair (#1256)`

### Task 6: `appleAccountProvider`

**Files:** Modify: `lib/features/auth/providers/auth_provider.dart` (sibling of `googleAccountProvider` L46, scanning `providerData` for `'apple.com'`, same `({String? email})?` record shape). Test: mirror the googleAccountProvider cases in its existing test file. Commit: `feat(auth): appleAccountProvider (#1256)`

### Task 7: Durable credential sheet — Apple at parity (iOS)

**Files:** Modify: `lib/features/auth/widgets/durable_credential_sheet.dart` · Tests: extend `test/features/auth/durable_credential_sheet_test.dart` + `durable_credential_sheet_conflict_test.dart`.

Changes:
- `_conflict`/`_conflictShellGateOwner` widen to `LinkConflictException?`.
- `_continueWithApple()`: mirrors `_continueWithGoogle` — `linkAppleToCurrentUser()`, token force-refresh, pop(true); `on SignInWithAppleAuthorizationException catch (e)` → if `e.code == AuthorizationErrorCode.canceled` silent reset, else map by connectivity (`ref.read(connectivityProvider) == ConnectivityStatus.offline` — verified: `lib/core/providers/connectivity_provider.dart:30`, `StateNotifierProvider<ConnectivityNotifier, ConnectivityStatus>` → `authErrorOffline`, else `durableGateError` — Gate R1 P3: the Apple sheet's offline failure isn't a `FirebaseAuthException`, so the Google path's `network-request-failed` mapping never fires for it); `on AppleLinkConflictException` → conflict state (same breadcrumb, `category: 'auth.gate'`, code only); `FirebaseAuthException` arm identical to Google's (`provider-already-linked` → success; `'canceled'` → silent reset (native-path defense); `network-request-failed` → `authErrorOffline`).
- Conflict COPY dispatches by subtype (D6) at **all THREE render sites** (Gate R2 P2 — enumerate, don't gesture): (1) `_switchOfferContent` body = `switch (conflict) { GoogleLinkConflictException() => l10n.durableGateConflictSwitchBody, AppleLinkConflictException() => l10n.durableGateConflictSwitchBodyApple }`; (2) the dead-end arm at `build()` (`durable_credential_sheet.dart:199`, `_initialContent(errorText: …)`) picks `durableGateConflict` vs `durableGateConflictApple` from the SAME live `conflict`; (3) the `_errorText = context.l10n.durableGateConflict` assignment inside `_switchAccount` (`durable_credential_sheet.dart:136`, the shell-not-empty-at-switch-time arm) must read the subtype BEFORE `_clearConflict()` runs. Google-conflict rendering is byte-identical to today.
- `_switchAccount()` dispatch:
```dart
await switch (conflict) {
  GoogleLinkConflictException(:final credential) =>
    ref.read(authRecoveryServiceProvider).restoreWithGoogle(credential: credential),
  AppleLinkConflictException(:final credential) =>
    ref.read(authRecoveryServiceProvider).restoreWithApple(credential: credential),
};
```
- `_initialContent` on iOS (`defaultTargetPlatform == TargetPlatform.iOS`): replace the action `Row` with a `Column`: `SignInWithAppleButton(key: Key('durableGate.continueApple'), text: l10n.durableGateContinueApple, height: 52, style: Theme.of(context).brightness == Brightness.dark ? SignInWithAppleButtonStyle.white : SignInWithAppleButtonStyle.black, onPressed: _linking ? null : _continueWithApple)` FIRST (`onPressed` is nullable `VoidCallback?` in the package — verified in the 7.0.1 source, Gate R1), spacing12, Google `_primaryButton` (existing key `durableGate.continue`), spacing8, `_secondaryButton` Not-now. The sheet body picks `durableGateBodyIos` here (D6). **Width note (Gate R1 P3):** `_primaryButton`/`_secondaryButton` fill width only via the old Row's `Expanded` — in the Column wrap each in `SizedBox(width: double.infinity, child: …)` (their `minimumSize: Size.fromHeight(52)` handles height only). Non-iOS: existing Row + `durableGateBody`, byte-identical.

**Tests:** iOS override (`debugDefaultTargetPlatformOverride = TargetPlatform.iOS`, reset in-body before teardown): Apple button present ABOVE Google (compare `tester.getTopLeft` dy), triggers `linkAppleToCurrentUser`; cancel exception → sheet stays, no error text; Apple conflict → switch flows to `restoreWithApple(credential: same instance)`; **Android default: no Apple button, tree unchanged** (existing tests remain green untouched — that absence is itself the assertion). Commit: `feat(auth): Apple option in durable credential sheet, iOS-only (#1256)`

### Task 8: `apple_restore_action.dart`

**Files:** Create: `lib/features/auth/widgets/apple_restore_action.dart` (mirror `google_restore_action.dart` verbatim: same `outgoingShellProvablyEmpty` gate with the same four thunks, `restoreWithApple()`, `on SignInWithAppleAuthorizationException` canceled → silent, else + catch-all → `_snack(context.l10n.restoreAppleFailed)`; blocked-shell → `restoreBlockedHasData`). Test: `test/features/auth/apple_restore_guard_test.dart` mirroring `google_restore_guard_test.dart` (gate blocks on non-empty shell → snack, no restore call; empty shell → restore called; cancel silent). Commit: `feat(auth): triggerAppleRestore with shell-emptiness gate (#1256)`

### Task 9: Home empty-state Apple CTA (iOS)

**Files:** Modify: `lib/features/home/screens/home_screen.dart` `_buildEmpty` (insert before the Google TextButton, iOS-gated):
```dart
if (defaultTargetPlatform == TargetPlatform.iOS)
  TextButton(
    key: const Key('home_empty_recover_apple_cta'),
    // #1256: same discard-shell contract as the Google CTA below — the
    // swap self-gates via outgoingShellProvablyEmpty; visibility is not
    // the safety boundary (#648).
    onPressed: () => triggerAppleRestore(context, ref),
    child: Text(context.l10n.homeRestoreWithApple, style: /* same as Google CTA */),
  ),
```
Test: extend `test/features/home/home_restore_cta_test.dart` — iOS override shows the Apple CTA above Google; default platform hides it. Commit: `feat(home): Restore with Apple CTA on iOS empty state (#1256)`

### Task 9b: Backup nudge + backup card select the iOS copy keys (Gate R2 P1 — D6.2 was declared but unwired)

**Files:** Modify: `lib/features/home/widgets/account_backup_nudge.dart` (body text + CTA label), `lib/features/settings/widgets/profile/backup_account_card.dart` (body text).

Both widgets open `showDurableCredentialSheet` — on iOS the sheet offers Apple + Google, so their Google-worded copy must switch: `defaultTargetPlatform == TargetPlatform.iOS ? l10n.homeBackupNudgeBodyIos : l10n.homeBackupNudgeBody` (same pattern for `homeBackupNudgeCta*` and `profileBackupCardBody*`; `backup_account_card.dart` is a plain StatelessWidget — `defaultTargetPlatform` comes from `package:flutter/foundation.dart`, no ref needed). Titles (`homeBackupNudgeTitle`, `profileBackupCardTitle`) are already provider-neutral — untouched. Without this task the three `*Ios` keys from Task 11 are dead and the iOS nudge CTA reads "Link Google account" next to an Apple-offering sheet — violating the parity acceptance criterion; no dead-key test exists to catch it (`generated_l10n_surface_test` is a hand-curated list, `check_arb_completeness` checks only EN/AR parity).

Test (RED first): extend `test/features/home/account_backup_nudge_test.dart` + the backup-card test — iOS override renders the `*Ios` strings; default platform renders the existing strings byte-identical. Commit: `feat(auth): iOS-neutral backup copy at nudge + card call sites (#1256)`

### Task 10: Profile account card (iOS rows) + sign-out / guest-delete copy

**Files:** Modify: `lib/features/settings/screens/profile_screen.dart` `_AccountCard` + `_signOut`, `lib/features/settings/keys/profile_keys.dart` (+2 keys), `lib/features/auth/widgets/sign_out_confirm_dialog.dart` (D6.3), `lib/features/auth/widgets/delete_account_dialog.dart:37` (D6.4).

- `appleAccountTile` row when `ref.watch(appleAccountProvider) != null` (mirror the Google linked row: shield icon, label `profileAccountApple`, trailing `email ?? profileAccountAppleLinked`, `onTap: null`), iOS-ungated (a linked Apple account should render even if the device were ever non-iOS).
- Link row label: `defaultTargetPlatform == TargetPlatform.iOS ? l10n.profileAccountLinkAccount : l10n.profileAccountLinkGoogle` (same `googleLinkTile` key, same sheet destination). Row remains visible only when `isAnonymous`.
- Inside the existing `if (showRestore)` block, iOS-gated `profileRestoreAppleTile` row ABOVE the Google restore row → `triggerAppleRestore(context, ref)`.
- `_signOut` passes `hasAppleProvider: ref.read(appleAccountProvider) != null` to `SignOutConfirmDialog.show`; the dialog branches per D6.3.
- `delete_account_dialog.dart:37`: `isAnonymous ? (isIOS ? l10n.deleteGuestSessionContentIos : l10n.deleteGuestSessionContent) : l10n.deleteAccountContent` per D6.4.

Test: extend `test/features/settings/profile_account_card_test.dart` (iOS: apple restore row above google row, link row shows neutral label; default platform: no apple rows, Google label unchanged) + sign-out dialog test (hasAppleProvider + null email → Apple copy; default → Google copy unchanged). Commit: `feat(settings): Apple rows + Apple-aware sign-out/delete copy, iOS-only (#1256)`

### Task 11: l10n keys (additive only)

**Files:** Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_ar.arb` — add the 14 new keys from Data contracts (with `@` description blocks matching neighbors) in BOTH locales (Arabic: "المتابعة عبر Apple", "الاستعادة عبر Apple", etc. — keep "Apple" latin per Apple's brand rules). **No existing value changes — D6 forbids shared-value edits (Gate R1 P1).** Run `flutter gen-l10n` and the l10n guard tests — every new key is referenced by Tasks 7-10 or 9b (the three `*Ios` backup-copy keys land in Task 9b — Gate R2 caught them dead when only Tasks 7-10 existed); EN/AR parity satisfied by construction. Commit: `feat(l10n): Sign in with Apple strings (#1256)`

### Task 12: Delete-time Apple token revocation (5.1.1(v))

**Files:** Modify: `lib/features/auth/services/data_deletion_service.dart` · Test: extend its existing test file.

- Ctor gains `AppleCredentialFactory? appleCredentialFactory` (default: the shared `AppleSignInGateway`, mirroring `AuthRecoveryService`); provider wires nothing new (default used in prod).
- At the top of `deleteAccount()`, after the null-user check, BEFORE `_deleteAccountCallable()`:
```dart
await _revokeAppleTokenBestEffort(user);
```
```dart
/// 5.1.1(v): apps offering Sign in with Apple must revoke the user's Apple
/// token on account deletion. Apple authorization codes are single-use and
/// short-lived, so a FRESH interactive authorization is required here — the
/// link-time code is long expired. Best-effort by design: a cancel/offline/
/// Apple failure logs and proceeds; deletion is never hostage to the Apple
/// round-trip (the server cascade + deleteUser still sever the link).
Future<void> _revokeAppleTokenBestEffort(User user) async {
  final hasApple =
      user.providerData.any((p) => p.providerId == 'apple.com');
  if (!hasApple) return;
  try {
    final bundle = await _appleCredentialFactory();
    final code = bundle.authorizationCode;
    if (code == null || code.isEmpty) {
      FirebaseConfig.log('Deletion: Apple revoke skipped (no auth code)');
      return;
    }
    await _auth.revokeTokenWithAuthorizationCode(code);
    FirebaseConfig.log('Deletion: Apple token revoked');
  } catch (error, stack) {
    FirebaseConfig.log('Deletion: Apple revoke failed (non-fatal)',
        error: error, stackTrace: stack);
  }
}
```
**Tests (RED first):** apple.com in providerData → factory called + `revokeTokenWithAuthorizationCode('code')` called BEFORE the callable; no apple provider → neither called; factory throws (cancel) → deletion proceeds to the callable and returns `ok`; null authorizationCode → revoke not called, deletion proceeds. Commit: `feat(auth): revoke Apple token on account deletion — 5.1.1(v) (#1256)`

### Task 13: Full verification

1. `flutter analyze` → clean (watch `prefer_const_constructors`).
2. `flutter test` → full suite green.
3. `bash tool/check_theme_purity.sh` locally (new widget code in `lib/` — CI-only check, run it before pushing; the `SignInWithAppleButton` styling lives in package code, out of scope for the script, and our call sites use only theme lookups).
4. Manual on-device smoke once the portal/console checklist is done — record in the PR body. Must include the exact sequence App Review runs for 5.1.1(v): **link Apple → create data → delete account → re-sign-in with the same Apple ID → verify zero data comes back** (plus: link, conflict-switch, restore, cancel-at-every-prompt leaves the shell intact).

---

## Acceptance criteria

- iOS: Apple offered at ≥ Google prominence on every login-service surface (sheet, home empty state, profile card), and NO surface names Google as the sole option (backup nudge + backup card copy switches per Task 9b); link, conflict-switch, and restore flows work end-to-end; cancel anywhere leaves the anon shell intact with no restart.
- Android: zero behavioral, visual, OR copy change — no shared ARB value is edited; every Android string renders byte-identical (existing tests pass unmodified, and this is now true by construction per D6, not merely untested).
- Account deletion with a linked Apple provider revokes the token (fresh code) and always completes even when revocation fails.
- Boot notice surfaces Apple restore outcomes (`opApple`).
- `flutter analyze` clean, full suite green, theme-purity clean, coverage ≥ 80% maintained.
- Manual config checklist complete before the release build.

## PR strategy

One implementation PR: `feat(auth): Sign in with Apple link/restore + 5.1.1(v) revocation (iOS)` — commit body and PR body both carry `Refs #1256` (NOT `Closes` — the issue stays open until App Review approves the resubmission; squash-merge inherits the commit body, per the #447 lesson). The PR body must state the D5 accepted risk verbatim (best-effort interactive revocation; delete→re-sign-in verified clean). Route through `/automerge` (Gate-category: auth swap surfaces — classifier fails toward gate anyway). Follow-up after store approval: close #1256 with the approval note.

**Gate history:**
- R1 (2026-07-15): rubric 0 P1/1 P2/4 P3; adversary 1 P1/2 P2/3 P3 — union applied (D6 rewritten to zero shared-value edits; sign-out/guest-delete copy branches; version pin; offline mapping; width note; D5 accepted-risk statement).
- R2 (2026-07-15): rubric 0 P1/2 P2/3 P3; adversary 1 P1/1 P2/0 P3 — union applied (Task 9b added: nudge+card wire the `*Ios` keys both reviewers found dead; conflict-copy dispatch enumerated at all 3 render sites; `sign_in_with_apple` pinned `^7.0.1` — 8.x upgrade is a separate verified follow-up; delete-dialog platform check specified; relay-email sign-out advice documented as accepted).

## Rejected alternatives

- **`firebase_auth` native `signInWithProvider`/`linkWithProvider` (no new dep):** rejected — see D1; breaks restore ordering and conflict credential reuse.
- **Server-side REST `/auth/revoke` from `deleteAccount.ts`:** rejected as YAGNI — requires persisting Apple refresh tokens (new schema, new secret management, Gate-category Functions change) to gain only non-interactive revocation; the in-session interactive path suffices for a user-initiated deletion.
- **Removing Google from the iOS build (option B of the 4.8 assessment):** rejected by product decision 2026-07-15 — strands Google-linked cross-platform restores.
- **`SplitMode`-style provider enum threaded through one generic link/restore method:** rejected — the Google and Apple factories return different shapes (bundle vs credential) and the explicit method pair mirrors the existing file's structure; DRY at the cost of the established idiom would fight the codebase.
