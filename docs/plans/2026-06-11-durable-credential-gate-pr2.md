# Durable-Credential Gate (#441 PR2) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Require a non-anonymous (Google-linked) Firebase user before the first valuable write — group create/join — enforced client-side (typed exception + gate sheet), rules-side (`sign_in_provider != 'anonymous'`), and callable-side (anon-reject in `joinGroupByInviteCode`), plus client-side FCM token-write gating so anon shells stay provably empty.

**Architecture:** A single `DurableCredentialRequiredException` + `isAnonymous` seam in `GroupService` gates `createGroup`/`joinGroup` before any staging (offline-queued batches bypass UI gates — the service gate is the client chokepoint). Screens pre-empt the exception with a blocking Google-link bottom sheet (`ensure → sheet → linkGoogleToCurrentUser → getIdToken(true)`). Server enforcement is independent: a rules predicate on `validGroupCreate` + `inviteCodes` create, and a pre-transaction anon-reject in the join callable. FCM `fcm_tokens` set() sites gate client-side only (rules untouched — the anon connectivity probe reads that doc).

**Tech Stack:** Flutter/Riverpod 2.x, firebase_auth + google_sign_in 7.x (PR1 foundation), Firestore rules, Cloud Functions (TS, Node 22), jest + @firebase/rules-unit-testing, mocktail + FakeFirebaseFirestore.

**Spec:** `docs/plans/2026-06-11-durable-credential-recovery-rearchitecture.md` PR2 row + mitigations 1–3, 8.
**Branch:** `feat/durable-credential-gate-441-pr2` (worktree `../Rihla-441-pr2`, stacked on PR1 `fcc4ae86`; PR opens against `main` after PR1 #443 merges).

---

## Scope boundaries (state these to reviewers; they are decisions, not misses)

1. **Restore / conflict resolution is PR3.** A `credential-already-in-use` / `email-already-in-use` conflict in the gate sheet shows an inline message and keeps the anon session — **never signOut** (the #213 data-loss invariant; PR1 dartdoc contract at `auth_recovery_service.dart:264-271`). The "switch to that account" flow is PR3's discard-shell.
2. **Email fallback is PR4.** The gate offers Google only.
3. **Legacy anon members keep membership-gated creates** (events/expenses/settlements — rules `:479`–`:959`). PR2 closes the entry funnel only. No real users exist (standing decision), so no legacy-anon population exists to strand.
4. **`fcm_tokens` rules are untouched.** The combined `allow read, write` (`firestore.rules:171-174`) stays; gating is client-side at the two `set()` sites. Rationale: the connectivity probe reads `fcm_tokens/{uid}` as any signed-in user every 60s (`connectivity_provider.dart:56-73`); rules-gating writes would require splitting the clause for marginal benefit (Admin SDK ignores rules; PR3's discard branch calls `removeToken()` pre-swap regardless).
5. **`recoveryCleanupIntents` is intentionally anon-written** (`firestore.rules:234-253` — the retiring anon UID writes the bearer intent pre-signout). Excluded from any predicate sweep. Deleted wholesale in PR5.
6. **`isDeleted`-style server `ledgerEditPolicy` config:** not built; the gate is one named predicate per surface so PR3+ can wrap it.

## Design decisions

| # | Decision | Why |
|---|---|---|
| G1 | Gate predicate = `User.isAnonymous` (client) / `request.auth.token.firebase.sign_in_provider != 'anonymous'` (server) | NOT the `linkedEmailProvider == null` proxy (`account_backup_nudge.dart:32`) — fine for a nudge, wrong for a money gate. Email-link-recovered users are non-anonymous on both predicates. |
| G2 | Service gate throws typed `DurableCredentialRequiredException` placed at the existing uid guards (`group_provider.dart:104-107` createGroup, `:192-195` joinGroup) — before `db.batch()` at `:120` and before the callable at `:204` | A committed batch replays offline (#412 — `batch.commit()` future resolves on server ack; the screen's 15s `.timeout` does NOT cancel the chain). Typed (not bare `Exception`) per the `DisplayNameTakenException` precedent so screens can map it. |
| G3 | Seam: `withFirestore(... bool Function()? isAnonymous)`; getter short-circuit order: override → (`_currentUserIdOverride != null` → `false`) → try `FirebaseConfig.currentUser?.isAnonymous ?? false` catch `false` | `FirebaseConfig.currentUser` THROWS `[core/no-app]` in unit tests (#390 trap). Injected-uid-implies-durable keeps all existing `withFirestore` tests green; fail-open in catch matches the established pattern — rules are the hard backstop. |
| G4 | Screens pre-gate via `durableCredentialGateProvider.ensure(context)` **after** form validation, **before** `setDeviceName`/loading | Sheet-then-proceed beats throw-then-retry UX. Covers all three join entries (button, 6th-char auto-submit at `join_group_screen.dart:226`, deep-link prefill → manual submit; initState seeding does NOT fire onChanged — verified). |
| G5 | After a successful link: `await user.getIdToken(true)` before returning from the sheet | `linkWithCredential` keeps the UID; the cached ID token can still carry `sign_in_provider='anonymous'` when the rules-gated batch fires immediately after. Force-refresh closes the race (user is necessarily online — they just linked). |
| G6 | After a successful link, if `settings.pushNotificationsEnabled`: `unawaited(notificationService.initialize())` | A user who toggled push on while anon has no token doc (client gate skips the write); without this, their token lands only on next boot — but pushes matter exactly right after the first join. Double-`initialize()` is established behavior (the #288 prompt flow already does it). |
| G7 | Callable reject code = `permission-denied`, thrown after the `!request.auth` check, **before** `assertJoinNotLocked` (`joinGroupByInviteCode.ts:237`) | Pre-tx = outside the catch that feeds `recordFailedJoinAttempt` → no throttle burn (the #279 precedent). NOT `unauthenticated` (the user IS authenticated; reuse would conflate the existing mapping). NOT `failed-precondition` (already used by in-tx failures; client maps on code only — indistinguishable). `permission-denied` is unused in this callable today. |
| G8 | Callable read uses optional chaining: `request.auth.token?.firebase?.sign_in_provider`; missing token ⇒ treated as durable | All 36 existing jest fixtures pass `auth: { uid }` with NO `token` (verified `joinGroupByInviteCode.test.ts:75+`); in prod the verified ID token is always present. Fail-open-on-missing is a test-fixture accommodation — comment this (WHY non-obvious). |
| G9 | Rules helper `isDurableSignIn()` added next to `signedIn()`; appended to `validGroupCreate()` and the `inviteCodes` `allow create` | Default mock token in @firebase/rules-unit-testing is `sign_in_provider: 'custom'` → all existing option-less `authenticatedContext(uid)` tests stay green. Anon tests pass `authenticatedContext(uid, { firebase: { sign_in_provider: 'anonymous' } })`. Group create is allowed WITHOUT the invite doc (rules tests `:275-337` prove lone creates) — the predicate must live in `validGroupCreate`, not rely on batch shape. Member doc needs nothing (separate post-batch write; group can't exist for a blocked anon creator). |
| G10 | Gate sheet is screen-context `showModalBottomSheet` (NOT the #352 navigatorKey gate) returning `Future<bool>`; barrier/drag dismiss = abort (false) | Both call sites own a context. The #352 tri-state/seen-flag does NOT transfer — the gate is auth-state-driven and must re-show every attempt until linked, never a one-shot flag. |
| G11 | Sheet error taxonomy: `GoogleSignInException` (canceled et al.) → silent reset, stay open; `FirebaseAuthException` conflict codes → inline conflict message, stay open, NO signOut; `network-request-failed` → existing `authErrorOffline`; `StateError` (missing `GOOGLE_SERVER_CLIENT_ID` / no idToken) → generic error + Sentry | Mirrors `link_email_screen.dart:80-96` `_humanizeError`. |
| G12 | Golden-path integration tests get an emulator-only fake-Google link step (Auth emulator accepts an unsigned/JSON idToken) before the create tap | `integration_test/golden_path_test.dart` signs in anonymously and creates a group — the gate would break the documented manual QA path. |

## Verification principles report (run while authoring — re-verified against the worktree, not recon citations)

1. **Callsite classification (shared read/write paths):** `fcm_tokens/{uid}` — OUTBOUND writers: `_saveToken` (`notification_service.dart:167-173`), `_onTokenRefresh` (`:186-192`) [gated]; `removeToken` delete `:279` [stays open — cleanup]; INBOUND: connectivity probe read (`connectivity_provider.dart:56-73`) [untouched — rules unchanged]. Server Admin-SDK writers bypass rules [unaffected]. `groups`/`inviteCodes` creates — sole client producer `GroupService.createGroup` (grep: only `create_group_screen.dart:93` calls it); join membership writes are server-side only (callable).
2. **Concrete claims vs code:** guards `group_provider.dart:104-107`/`192-195` ✓ (read); batch `:120-143`, member doc separate `:149-161` ✓; callable auth check + `assertJoinNotLocked` order + catch-wraps-only-tx ✓ (read `joinGroupByInviteCode.ts:218-250`, `:384-394`); `isLookupFailure` = `not-found|failed-precondition` ✓ (`:145-148`); combined fcm rule ✓ (`firestore.rules:171-174`); `validGroupCreate` ✓ (`:266-294`, wired `:330`); inviteCodes create ✓ (`:182-188`); join auto-submit `if (value.length == 6) _joinGroup()` ✓; initState programmatic seed (no onChanged fire) ✓ (`join_group_screen.dart:46-54`); `GOOGLE_SERVER_CLIENT_ID` absent from config.json.example ✓ (read — only SENTRY_DSN, USE_FIREBASE_EMULATOR).
3. **Read-path per write-path:** gated group create → who reads? `userGroupsProvider` (unchanged shape — gate changes WHO may write, not the doc shape). New `lastEditedBy`-style fields: none. `fcm_tokens` skip → read by `fcmSender`/notifiers (server): anon users have no groups → no notification fan-out targets them; post-link re-save (G6) closes the in-session gap.
4. **Fields enumerated from types:** no schema change anywhere (no new Firestore fields). New Dart types: `DurableCredentialRequiredException` (no fields), gate provider. New rules function only.
5. **Data contracts spelled out:** sheet contract `Future<bool> showDurableCredentialSheet(BuildContext)` — true = linked+token-refreshed; gate contract `Future<bool> ensure(BuildContext)` — true = proceed. Callable error contract: code `permission-denied`, client sentinel `'A linked account is required to join.'` mapped in `_joinGroupErrorMessage`, screen substring `'linked account is required'` → l10n `durableCredentialRequired`.
6. **Arithmetic decomposition:** N/A — no money math touched. The gate sits before `BalanceCalculator` ever sees data; split/balance flows unchanged.
7. **Adversarial pass on an orthogonal axis (offline/time):** the gate's weak spot is not the happy path but **offline replay** (gate before `batch.commit()` — G2) and **token staleness** (G5). Also probed identity axis: a user who linked email (LINK half) pre-PR2 is non-anonymous → passes gate without owning Google — correct by design (D3 keeps email path). A user mid-recovery (old flow) swaps UID — gate re-evaluates per attempt via live `currentUser` read, no cached verdict.

---

## Task 1: `DurableCredentialRequiredException` + GroupService gate

**Files:**
- Create: `lib/features/auth/services/durable_credential_exception.dart`
- Modify: `lib/features/groups/providers/group_provider.dart` (~:38-69 seam, :104-107, :192-195)
- Test: `test/unit/group_service_durable_gate_test.dart`

**Step 1: Write the failing test**

```dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/auth/services/durable_credential_exception.dart';
import 'package:safar/features/groups/providers/group_provider.dart';

// Container with real settingsProvider deps mirrors group_service_test.dart's
// existing harness (SharedPreferences mock in setUp).

void main() {
  // ... setUp mirroring test/unit/group_service_test.dart (SharedPreferences.setMockInitialValues({}), container with sharedPreferencesProvider override) ...

  test('createGroup throws DurableCredentialRequiredException for anonymous user and stages no writes', () async {
    final db = FakeFirebaseFirestore();
    final service = GroupService.withFirestore(
      container.read(_refProvider), db,
      currentUserId: 'anon-uid',
      isAnonymous: () => true,
    );
    await expectLater(
      service.createGroup(name: 'Trip', currency: 'OMR'),
      throwsA(isA<DurableCredentialRequiredException>()),
    );
    expect((await db.collection('groups').get()).docs, isEmpty);
    expect((await db.collection('inviteCodes').get()).docs, isEmpty);
  });

  test('joinGroup throws DurableCredentialRequiredException for anonymous user without invoking the callable', () async {
    var callableInvoked = false;
    final service = GroupService.withFirestore(
      container.read(_refProvider), FakeFirebaseFirestore(),
      currentUserId: 'anon-uid',
      isAnonymous: () => true,
      joinGroupCallableOverride: ({required inviteCode, required displayName}) async {
        callableInvoked = true;
        return 'g1';
      },
    );
    await expectLater(
      service.joinGroup(inviteCode: 'ABC234'),
      throwsA(isA<DurableCredentialRequiredException>()),
    );
    expect(callableInvoked, isFalse);
  });

  test('createGroup proceeds when isAnonymous override reports false', () async {
    final db = FakeFirebaseFirestore();
    final service = GroupService.withFirestore(
      container.read(_refProvider), db,
      currentUserId: 'durable-uid',
      isAnonymous: () => false,
    );
    final group = await service.createGroup(name: 'Trip', currency: 'OMR');
    expect((await db.collection('groups').doc(group.id).get()).exists, isTrue);
  });

  test('withFirestore without isAnonymous override defaults to durable (existing tests contract)', () async {
    final db = FakeFirebaseFirestore();
    final service = GroupService.withFirestore(
      container.read(_refProvider), db, currentUserId: 'uid-1',
    );
    final group = await service.createGroup(name: 'Trip', currency: 'OMR');
    expect(group.createdBy, 'uid-1');
  });
}
```

**Step 2:** `flutter test test/unit/group_service_durable_gate_test.dart` → FAIL (no `durable_credential_exception.dart`, no `isAnonymous` param).

**Step 3: Implement.**

`durable_credential_exception.dart`:
```dart
/// Thrown by money-adjacent write paths when the current user is still
/// anonymous (#441 PR2). Screens pre-empt it with the Google gate sheet;
/// reaching this exception means the UI gate was bypassed (offline replay,
/// programmatic call) — the write must not proceed.
class DurableCredentialRequiredException implements Exception {
  const DurableCredentialRequiredException();

  @override
  String toString() => 'A linked account is required for this action.';
}
```

`group_provider.dart`:
- field `final bool Function()? _isAnonymousOverride;`
- prod ctor: `_isAnonymousOverride = null`; `withFirestore` gains `bool Function()? isAnonymous`.
- getter:
```dart
bool get _isCurrentUserAnonymous {
  final override = _isAnonymousOverride;
  if (override != null) return override();
  // Injected test uid implies a durable user; FirebaseConfig.currentUser
  // throws [core/no-app] in unit tests without Firebase (#390).
  if (_currentUserIdOverride != null) return false;
  try {
    return FirebaseConfig.currentUser?.isAnonymous ?? false;
  } catch (_) {
    return false;
  }
}
```
- in `createGroup` after the `uid == null` throw (:107) and in `joinGroup` after (:195):
```dart
if (_isCurrentUserAnonymous) {
  throw const DurableCredentialRequiredException();
}
```

**Step 4:** Re-run new test file → PASS. Run `flutter test test/unit/group_service_test.dart test/features/groups/` → all green (seam default preserves contracts).

**Step 5:** Commit `feat(auth): gate createGroup/joinGroup on a durable (non-anonymous) credential (#441)`.

## Task 2: NotificationService anon gating (FCM shell-emptiness)

**Files:**
- Modify: `lib/core/services/notification_service.dart` (ctor ~:32-53, `_saveToken` :156-178, `_onTokenRefresh` :181-197)
- Test: `test/unit/notification_service_anon_gate_test.dart`

**Step 1: Failing test** (harness mirrors `notification_service_test.dart` — FakeFirebaseFirestore + injected streams):
- `initialize()` with `isAnonymous: () => true` → permission flow runs, **no** `fcm_tokens` doc exists after; status is NOT `NotificationStatus.error` (skip is intentional, not a failure).
- token-refresh event while anon → no doc.
- `removeToken()` while anon → still deletes a pre-seeded doc (cleanup stays open).
- default (no override, `currentUserId` injected) → token written (existing behavior).

**Step 2:** Run → FAIL (no `isAnonymous` param).

**Step 3:** Add `bool Function()? isAnonymous` ctor param → `_isAnonymousOverride`; getter identical in shape to Task 1's (override → `_currentUserIdOverride != null` ⇒ false → try/catch FirebaseConfig). In `_saveToken` after the `userId == null` return and in `_onTokenRefresh` after its null return: `if (_isCurrentUserAnonymous) return;` (silent — no status change).

**Step 4:** New + existing notification tests green (`flutter test test/unit/notification_service_test.dart test/core/providers/app_bootstrap_wiring_test.dart test/unit/notification_prompt_test.dart`).

**Step 5:** Commit `feat(notifications): skip fcm_tokens writes for anonymous users (#441)`.

## Task 3: Gate sheet UI + l10n + `DurableCredentialGate`

**Files:**
- Create: `lib/features/auth/widgets/durable_credential_sheet.dart`
- Create: `lib/features/auth/providers/durable_credential_gate_provider.dart`
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_ar.arb` (+ regenerate gen-l10n via `flutter gen-l10n`)
- Test: `test/features/auth/durable_credential_sheet_test.dart`, `test/unit/durable_credential_gate_test.dart`

**l10n keys (EN + AR, CI-enforced parity):** `durableGateTitle` ("Keep your money safe"), `durableGateBody` (groups & expenses are tied to this account; link Google so it can't be lost with the device), `durableGateContinueGoogle` ("Continue with Google"), `durableGateNotNow` ("Not now"), `durableGateConflict` (account already in use by another Rihla account), `durableGateError` (generic), `durableCredentialRequired` ("Link a Google account to continue."). Reuse existing `authErrorOffline`.

**Step 1: Failing widget test** (mocktail `AuthRecoveryService`; `pumpRihlaApp`-style harness with `sharedPreferencesProvider` + `authRecoveryServiceProvider` overrides):
- renders title + both buttons.
- Continue → `linkGoogleToCurrentUser` called once; mock returns a `UserCredential` whose `user.getIdToken(true)` is verified called (mock User); sheet pops `true`.
- `GoogleSignInException` (canceled) → sheet stays open, no error text, button re-enabled.
- `FirebaseAuthException(code: 'credential-already-in-use')` → inline `durableGateConflict` text, sheet stays open, **`signOut` never called** on the mock auth.
- `FirebaseAuthException(code: 'network-request-failed')` → `authErrorOffline` text.
- "Not now" → pops `false`.

**Step 2:** Run → FAIL (file missing).

**Step 3: Implement sheet** — visual skeleton copied from `_NotificationRationaleSheet` (`notification_rationale_sheet.dart:49-170`): transparent sheet → floating `cardSurface` card, `radiusLarge`, drag handle, 52×52 `saffronTint` badge (`Iconsax.shield_tick`), `AppTypography.sans` title/body, two 52px buttons. Stateful: `_linking` drives an inline 22×22 `CircularProgressIndicator` in the primary button (the `link_email_screen.dart:218-231` pattern) + `_errorText` inline line (`Key('durableGate.error')`). Primary handler:

```dart
Future<void> _continueWithGoogle() async {
  setState(() { _linking = true; _errorText = null; });
  try {
    final result = await ref.read(authRecoveryServiceProvider).linkGoogleToCurrentUser();
    // The cached ID token can still say sign_in_provider=anonymous right
    // after linkWithCredential; the very next write is rules-gated on it.
    await result.user?.getIdToken(true);
    if (mounted) Navigator.of(context).pop(true);
  } on GoogleSignInException {
    if (mounted) setState(() => _linking = false); // canceled/interrupted — silent
  } on FirebaseAuthException catch (e) {
    if (!mounted) return;
    setState(() {
      _linking = false;
      _errorText = switch (e.code) {
        'credential-already-in-use' || 'email-already-in-use' ||
        'provider-already-linked' => context.l10n.durableGateConflict,
        'network-request-failed' => context.l10n.authErrorOffline,
        _ => context.l10n.durableGateError,
      };
    });
  } catch (e, st) {
    unawaited(Sentry.captureException(e, stackTrace: st));
    if (mounted) setState(() { _linking = false; _errorText = context.l10n.durableGateError; });
  }
}
```

`showDurableCredentialSheet(BuildContext) → Future<bool>` returns `result ?? false`.

**Gate provider** (`durable_credential_gate_provider.dart`):
```dart
typedef DurableCredentialSheetPresenter = Future<bool> Function(BuildContext context);

final durableCredentialGateProvider = Provider<DurableCredentialGate>((ref) {
  return DurableCredentialGate(ref);
});

class DurableCredentialGate {
  DurableCredentialGate(this._ref, {bool Function()? isAnonymous, DurableCredentialSheetPresenter? presentSheet})
      : _isAnonymousOverride = isAnonymous,
        _presentSheet = presentSheet ?? showDurableCredentialSheet;

  bool get _needsGate {
    final override = _isAnonymousOverride;
    if (override != null) return override();
    try {
      return FirebaseConfig.currentUser?.isAnonymous ?? false;
    } catch (_) {
      return false; // no-Firebase widget tests; rules are the hard backstop
    }
  }

  /// True ⇒ proceed with the write. Shows the blocking Google sheet for
  /// anonymous users; re-saves the FCM token post-link (the user may have
  /// enabled push while still anonymous — G6).
  Future<bool> ensure(BuildContext context) async {
    if (!_needsGate) return true;
    final linked = await _presentSheet(context);
    if (linked && _ref.read(settingsProvider).pushNotificationsEnabled) {
      unawaited(_ref.read(notificationServiceProvider).initialize());
    }
    return linked;
  }
}
```

Unit test for the gate: non-anon → `ensure` true without presenting; anon + presenter false → false; anon + presenter true → true + `initialize()` called iff push enabled (mock service).

**Step 4:** Tests green; `flutter analyze` clean.
**Step 5:** Commit `feat(auth): durable-credential gate sheet (Google link before first create/join) (#441)`.

## Task 4: Screen wiring + error mapping

**Files:**
- Modify: `lib/features/groups/screens/create_group_screen.dart` (`_createGroup` :68+), `lib/features/groups/screens/join_group_screen.dart` (`_joinGroup` :63+, `_errorMessage` :147-164)
- Modify: `lib/features/groups/providers/group_provider.dart` (`_joinGroupErrorMessage` :233-245)
- Test: extend `test/features/groups/create_join_group_test.dart` (new group) or new `test/features/groups/durable_gate_wiring_test.dart`

**Step 1: Failing widget tests** (mock `GroupService` via `groupServiceProvider` override + fake gate via `durableCredentialGateProvider` override recording `ensure` calls):
- create: anon gate returns false → `createGroup` never called, loading false, still on screen.
- create: gate returns true → `createGroup` called once (prompt wiring untouched — run `notification_prompt_wiring_test.dart` to prove).
- join: typing the 6th code char (auto-submit) consults the gate before `joinGroup`.
- join: gate false → callable path never invoked.
- service-throw defense: `joinGroup` throwing `DurableCredentialRequiredException` → snackbar shows `durableCredentialRequired`, loading reset.

**Step 2:** Run → FAIL.

**Step 3: Implement.**
- `_createGroup` after `validate()`, before loading/`setDeviceName`:
```dart
final gateOk = await ref.read(durableCredentialGateProvider).ensure(context);
if (!gateOk || !mounted) return;
```
- `_joinGroup`: after the name-validation block, before loading/`setDeviceName` (same 3 lines). All three join entries funnel through `_joinGroup` — single insertion covers button, auto-submit, deep-link.
- Typed catch in both screens **before** the generic catch: `on DurableCredentialRequiredException` → reset loading + snackbar `context.l10n.durableCredentialRequired` (defense path; normally unreachable).
- `_joinGroupErrorMessage` add: `'permission-denied' => 'A linked account is required to join.',`
- `_errorMessage` (join screen) add substring map: `'linked account is required'` → `l10n.durableCredentialRequired`.

**Step 4:** New tests green + `flutter test test/features/groups/` full green.
**Step 5:** Commit `feat(groups): wire the durable-credential gate into create/join flows (#441)`.

## Task 5: Rules predicate + rules tests

**Files:**
- Modify: `security/firestore.rules` (helper near `signedIn()` :10-12; `validGroupCreate` :266-294; `inviteCodes` create :182-188)
- Test: `functions/test/firestore-rules-publish-readiness.test.ts` (new describe near the group-create cases :249+)

**Step 0:** `cd functions && npm ci` (worktree has no node_modules). Emulator harness per `docs/TESTING` flow (Java 21).

**Step 1: Failing tests** (new pattern — first `TokenOptions` usage in the suite):
```ts
const anon = testEnv.authenticatedContext('anon-uid', {
  firebase: { sign_in_provider: 'anonymous' },
} as any);
```
- anonymous provider CANNOT create a valid-shaped group (assertFails).
- anonymous provider CANNOT create the inviteCodes doc (batch with group, assertFails).
- `sign_in_provider: 'google.com'` CAN create group + invite batch (assertSucceeds).
- (existing :249-273 'creator can atomically create…' keeps proving the option-less default `'custom'` passes.)

**Step 2:** Run the suite → new cases FAIL (predicate absent), existing green.

**Step 3: Implement** — helper after `signedIn()`:
```
// #441: money data must never be born under a discardable anonymous UID.
function isDurableSignIn() {
  return request.auth.token.firebase.sign_in_provider != 'anonymous';
}
```
Append `&& isDurableSignIn()` to `validGroupCreate()`'s `signedIn()` line and to the `inviteCodes` `allow create` chain.

**Step 4:** Full rules suite green (both rules test files).
**Step 5:** Commit `feat(rules): require a non-anonymous provider for group + inviteCode creation (#441)`.

## Task 6: Callable anon-reject

**Files:**
- Modify: `functions/src/callables/joinGroupByInviteCode.ts` (after :228, before `assertJoinNotLocked` :237; header comment :24-46)
- Test: `functions/test/callables/joinGroupByInviteCode.test.ts`

**Step 1: Failing tests:**
- anon token rejected:
```ts
const request = {
  data: { inviteCode: 'ABC234', displayName: 'Anon' },
  auth: { uid: 'anon-1', token: { firebase: { sign_in_provider: 'anonymous' } } },
} as any;
await expect(wrapped(request)).rejects.toMatchObject({ code: 'permission-denied' });
```
(bare code, no `functions/` prefix — the suite's existing idiom, e.g. the `'unauthenticated'`/`'already-exists'` cases)
- anon reject does NOT create/increment `joinAttempts/anon-1` (read the doc after, expect missing — mirrors the #279 no-burn test :521-528).
- explicit `sign_in_provider: 'google.com'` token joins successfully (happy-path clone).
- existing tokenless fixtures: untouched, suite must stay green (G8 fail-open).

**Step 2:** Run → FAIL.

**Step 3: Implement** after the unauthenticated throw:
```ts
// Tokenless requests are test fixtures; verified callable tokens always
// carry firebase.sign_in_provider in production.
if (request.auth.token?.firebase?.sign_in_provider === 'anonymous') {
  throw new HttpsError(
    'permission-denied',
    'A linked (non-anonymous) account is required to join a group.'
  );
}
```
Update the header threat-model comment: anonymous users can no longer join, so "anon rotation bypasses the per-UID throttle" is closed for this callable (App Check remains the real per-actor control, #197).

**Step 4:** `npm test -- joinGroupByInviteCode` full green; `npm run build` (tsc) clean.
**Step 5:** Commit `feat(functions): reject anonymous-provider joins in joinGroupByInviteCode (#441)`.

## Task 7: Golden path + config example + docs

**Files:**
- Modify: `integration_test/golden_path_test.dart`, `integration_test/golden_path_arabic_test.dart` (fake-Google link step post-anon-sign-in, pre-create)
- Modify: `config.json.example` (add `"GOOGLE_SERVER_CLIENT_ID": ""` — PR1 gap)
- Modify: `docs/ACCOUNT-RECOVERY.md` only if it names create/join as ungated (check; full rewrite is PR5)

**Golden-path link step** (Auth emulator accepts a JSON/unsigned idToken). Anchor: the test reaches the anon session via `app.main()`'s `_AuthGate` (no explicit `signInAnonymously`); insert the link AFTER the home-screen settle wait and BEFORE the create-button tap, when `FirebaseAuth.instance.currentUser` is populated:
```dart
await FirebaseAuth.instance.currentUser!.linkWithCredential(
  GoogleAuthProvider.credential(
    idToken: jsonEncode({
      'sub': 'golden-path-google-sub',
      'email': 'golden@example.com',
      'email_verified': true,
    }),
  ),
);
```
(emulator-only by construction — golden path requires `USE_FIREBASE_EMULATOR`). Manual verification: noted as an acceptance box, not CI.

`integration_test/mixed_currency_guard_test.dart` is deliberately NOT touched: it seeds groups via emulator REST with `Bearer owner` (rules bypassed) and uses its anon session for reads only — the new predicate cannot break it.

**Commit:** `test(integration): link a fake Google credential before the gated create (#441)` + `chore(config): document GOOGLE_SERVER_CLIENT_ID in config.json.example`.

## Task 8: Full verification

- `flutter analyze` → clean.
- `flutter test` → full suite green.
- `cd functions && npm test` → full jest (rules + callables) green under Java 21.
- `git diff fcc4ae86..HEAD --stat` review — one concern only.

## Acceptance checklist (PR body carries `Refs #441` + `Spec:` line)

- [ ] Anonymous user tapping Create/Join sees the Google sheet; linking proceeds with the original action's screen state intact (create form / typed code preserved — sheet overlays, never navigates)
- [ ] Cancel/dismiss aborts cleanly (no loading stuck, no partial writes)
- [ ] Conflict shows message, session intact (no signOut anywhere in the new code)
- [ ] Anon Firestore group/invite create denied by rules (jest evidence)
- [ ] Anon callable join rejected pre-throttle (jest evidence: no joinAttempts doc)
- [ ] FCM token writes skipped while anon; re-saved post-link when push enabled
- [ ] All existing suites green without modification except where behavior intentionally changed (none expected — seams default to durable)
- [ ] RED outputs pasted in PR body (bug-class: new feature — tests-first per contract)
- [ ] Post-merge: deploy ceremony (rules + functions changed) — `pending_deploy.sh` → `deploy-ceremony`
- [ ] Manual: golden-path emulator run with the link step
- [ ] External (unchanged from PR1, fails silently): Google provider enabled in console; SHA-1/256 ×3 incl. Play App Signing key; `GOOGLE_SERVER_CLIENT_ID` in real config.json + CI `CONFIG_JSON` secret
