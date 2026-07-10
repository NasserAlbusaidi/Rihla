# Post-Deletion Auth Durability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:test-driven-development and superpowers:verification-before-completion. Execute inline in the assigned worktree because the delegation brief explicitly forbids subagents.

**Goal:** Prevent a server-deleted Firebase user from surviving the forced restart when the first local `signOut()` fails, without changing #213's rule that ordinary restored-session token failures always keep the session.

**Architecture:** After the delete callable returns successfully, persist the deleted UID in a dedicated device-local `SharedPreferences` marker before the restart protocol begins. On the next cold boot, reconcile that marker before token verification: only an exact restored-UID match is known to be the already-deleted account, so retry local `signOut()`, mint a fresh anonymous session, and force the existing cache barrier; absent or mismatched markers preserve the restored session and leave `recoverRestoredSessionIfNeeded` unchanged.

**Tech Stack:** Flutter/Dart, Firebase Auth, `shared_preferences`, `firebase_auth_mocks`, `flutter_test`

## Global Constraints

- Never modify `security/firestore.rules`, `functions/**`, or `**/models/**.dart`.
- Never branch on token-check error codes in `recoverRestoredSessionIfNeeded`; all ordinary token-check failures continue returning `false` without signing out (#213).
- The marker is written only after the delete callable confirms the server cascade succeeded.
- A matching marker is the only new path allowed to discard a restored session.
- If the boot-time retry `signOut()` throws, leave the marker intact and let `ensureAnonymousSession()` fail closed so `_AuthGate` shows Retry; never mount the app under the deleted UID.
- No Firestore document shape changes, no routing changes, no UI/l10n changes, and no new dependency.

---

### Task 1: Prove and fix post-deletion auth durability

**Files:**
- Create: `lib/core/services/post_deletion_auth_barrier.dart`
- Modify: `lib/features/auth/services/data_deletion_service.dart:73-96`
- Modify: `lib/core/config/firebase_config.dart:79-127`
- Test: `test/integration/firebase_auth_test.dart`
- Test: `test/unit/data_deletion_service_test.dart`

**Interfaces:**
- Produces: `const String kExpectedDeletedUidKey = 'auth.expectedDeletedUid'`
- Produces: `Future<void> markExpectedDeletedUid(SharedPreferences prefs, String uid)`
- Produces: `Future<bool> reconcilePostDeletionAuthSession({required SharedPreferences prefs, required String? restoredUid, required Future<void> Function() signOut})`
- Consumes: `DataDeletionService.deleteAccount()` records `user.uid` only after `_deleteAccountCallable()` succeeds.
- Consumes: `FirebaseConfig.ensureAnonymousSession()` calls the reconciler only on cold-boot (`runCacheBarrier == true`) before restored-session token verification.
- Return contract: the reconciler returns `true` only after an exact UID match and successful local `signOut()`; the caller then runs `_signInAnonymously()` and the cache barrier with `forceClear: true`.
- Failure contract: a matching-marker `signOut()` exception propagates with the marker still present; absent/mismatched markers never call `signOut()`, and a stale marker is removed.

- [x] **Step 1: Write the failing cold-boot regressions**

Add a `MockFirebaseAuth` test double that counts `signOut()` / anonymous sign-in, swaps its `mockUser` to a fresh UID only after the deletion-recovery sign-out, and can throw from that sign-out. Add two tests to `test/integration/firebase_auth_test.dart` using the literal marker key so the pre-fix suite compiles:

```dart
class _PostDeletionMockFirebaseAuth extends MockFirebaseAuth {
  _PostDeletionMockFirebaseAuth({this.failSignOut = false})
    : super(
        signedIn: true,
        mockUser: MockUser(
          uid: 'deleted-uid',
          isAnonymous: false,
          email: 'deleted@example.com',
        ),
      );

  final bool failSignOut;
  int signOuts = 0;
  int anonSignIns = 0;

  @override
  Future<void> signOut() async {
    signOuts++;
    if (failSignOut) throw StateError('signOut failed');
    await super.signOut();
  }

  @override
  Future<UserCredential> signInAnonymously() {
    anonSignIns++;
    mockUser = MockUser(uid: 'fresh-uid', isAnonymous: true);
    return super.signInAnonymously();
  }
}

test('server-confirmed deletion marker clears a restored deleted uid (#1100)', () async {
  SharedPreferences.setMockInitialValues(const <String, Object>{
    'auth.expectedDeletedUid': 'deleted-uid',
  });
  final prefs = await SharedPreferences.getInstance();
  final auth = _PostDeletionMockFirebaseAuth();
  final gate = _RecordingCacheGate();

  await FirebaseConfig.ensureAnonymousSession(
    authOverride: auth,
    prefs: prefs,
    cacheGate: gate,
  );

  expect(auth.signOuts, 1, reason: 'the deleted restored uid must be cleared');
  expect(auth.anonSignIns, 1);
  expect(auth.currentUser?.uid, 'fresh-uid');
  expect(prefs.getString('auth.expectedDeletedUid'), isNull);
  expect(gate.clearCount, 1);
});
```

The default `runCacheBarrier: true` is load-bearing because reconciliation is intentionally cold-boot-only. The companion failure test uses `_PostDeletionMockFirebaseAuth(failSignOut: true)`, expects `ensureAnonymousSession()` to throw `StateError`, and then asserts `signOuts == 1`, `anonSignIns == 0`, `currentUser.uid == 'deleted-uid'`, the marker is still present, and the cache gate has not run.

- [x] **Step 2: Run the regression test and save exact RED evidence**

Run:

```bash
flutter test test/integration/firebase_auth_test.dart --plain-name 'server-confirmed deletion marker clears a restored deleted uid (#1100)'
```

Expected pre-fix result: FAIL on `auth.signOuts` (`Expected: <1>`, `Actual: <0>`) because current `ensureAnonymousSession()` ignores the marker and silently accepts the restored deleted UID.

- [x] **Step 3: Add deletion-side marker tests before production code**

Extend `test/unit/data_deletion_service_test.dart` so the successful path reads `auth.expectedDeletedUid == 'uid-1'` inside the mocked `signOut()`, the existing sign-out-failure path asserts the marker survives through restart, and callable-failure paths assert the marker is absent.

- [x] **Step 4: Implement the marker helper**

Create `lib/core/services/post_deletion_auth_barrier.dart` with the exact interfaces above. `markExpectedDeletedUid` awaits `prefs.setString`. `reconcilePostDeletionAuthSession` reads the marker, clears absent/mismatch residue without signing out, and for an exact match awaits `signOut()` before removing the marker and returning `true`; removal must remain after `signOut()` so a local failure is retryable.

```dart
import 'package:shared_preferences/shared_preferences.dart';

const String kExpectedDeletedUidKey = 'auth.expectedDeletedUid';

Future<void> markExpectedDeletedUid(
  SharedPreferences prefs,
  String uid,
) async {
  final persisted = await prefs.setString(kExpectedDeletedUidKey, uid);
  if (!persisted) {
    throw StateError('Failed to persist the post-deletion auth marker');
  }
}

Future<bool> reconcilePostDeletionAuthSession({
  required SharedPreferences prefs,
  required String? restoredUid,
  required Future<void> Function() signOut,
}) async {
  final expectedUid = prefs.getString(kExpectedDeletedUidKey);
  if (expectedUid == null) return false;
  if (restoredUid != expectedUid) {
    await prefs.remove(kExpectedDeletedUidKey);
    return false;
  }

  await signOut();
  await prefs.remove(kExpectedDeletedUidKey);
  return true;
}
```

- [x] **Step 5: Write the marker after confirmed server deletion**

In `DataDeletionService.deleteAccount()`, after `_deleteAccountCallable()` succeeds and before cache isolation/restart, call:

```dart
await markExpectedDeletedUid(_prefs, user.uid);
```

Update the stale comment that currently claims cold boot always re-mints a fresh anonymous user regardless of local `signOut()` durability.

- [x] **Step 6: Reconcile before restored-token verification**

In `FirebaseConfig.ensureAnonymousSession()`, resolve prefs only for cold-boot barrier runs, call `reconcilePostDeletionAuthSession` with `restoredUser?.uid`, and set `swapped = true` only when it returns true. On `swapped`, await `_signInAnonymously(authInstance)` and skip `recoverRestoredSessionIfNeeded`; otherwise preserve the current restored/no-session branches exactly. Pass the already-resolved prefs into `_runCacheBarrier` so the matching-marker path forces a cache clear before the app mounts.

```dart
var swapped = false;
SharedPreferences? resolvedPrefs;
final restoredUser = await authInstance.authStateChanges().first;
if (runCacheBarrier) {
  resolvedPrefs = prefs ?? await SharedPreferences.getInstance();
  swapped = await reconcilePostDeletionAuthSession(
    prefs: resolvedPrefs,
    restoredUid: restoredUser?.uid,
    signOut: authInstance.signOut,
  );
}

if (swapped) {
  await _signInAnonymously(authInstance);
} else if (restoredUser != null) {
  unawaited(
    recoverRestoredSessionIfNeeded(
      verifyToken: () => verifyTokenOverride != null
          ? verifyTokenOverride(restoredUser)
          : restoredUser.getIdToken().then((_) {}),
    ),
  );
} else {
  await _signInAnonymously(authInstance);
}
```

- [x] **Step 7: Run focused GREEN verification**

Run:

```bash
flutter test test/integration/firebase_auth_test.dart test/unit/data_deletion_service_test.dart test/unit/firebase_config_cache_barrier_test.dart
```

Expected: all tests pass, including the existing #213 `internal-error`, `network-request-failed`, and hung-token checks plus the new exact-marker success/fail-closed cases.

- [x] **Step 8: Run full verification**

Run:

```bash
dart format --output=none --set-exit-if-changed lib/core/services/post_deletion_auth_barrier.dart lib/core/config/firebase_config.dart lib/features/auth/services/data_deletion_service.dart
flutter test
flutter analyze
```

Expected: formatter exit 0, full suite exit 0, analyzer reports `No issues found!`.

- [x] **Step 9: Review scope and commit**

Run `git diff --check`, `git diff --stat origin/main...HEAD` (after commit), `git diff --name-only origin/main...HEAD`, and inspect the complete diff. Confirm no forbidden paths, no `recoverRestoredSessionIfNeeded` behavior change, and only the plan, marker helper, two auth services, and two targeted tests changed. Commit conventionally with final body:

```text
fix(auth): recover deleted sessions after restart

Closes #1100
```

## Verification Principles Self-Review

1. **Callsites classified:** marker writer is OUTBOUND in `DataDeletionService`; boot reconciler is INBOUND-to-auth-side-effect in `ensureAnonymousSession`; no other reader/writer exists.
2. **Claims checked against code:** server confirmation is `_deleteAccountCallable()` returning at `data_deletion_service.dart:59-71`; restored session branching is `firebase_config.dart:93-118`; #213 verifier is `firebase_config.dart:184-211` and remains untouched.
3. **Read path traced:** `auth.expectedDeletedUid` is written after server success, read before app mount on the next `ensureAnonymousSession`, then cleared on proven teardown/mismatch.
4. **Fields enumerated:** the marker is one string UID, not JSON; there are no optional fields or versions to deserialize.
5. **Contract explicit:** exact key, writer, reader, match/mismatch, success/failure, and return semantics are listed above.
6. **Arithmetic decomposition:** not applicable; no money path is touched.
7. **Orthogonal axis:** existing #213 transient/hung token tests prove ordinary restored sessions remain non-destructive while the new tests prove only server-confirmed deletion markers can trigger sign-out.

## Review Provenance

Issue #1100's supplied contract was already verified against live code by a fresh-context verifier and three independent refuters, and it explicitly approves the scoped expected-post-delete marker approach. This worktree's delegation forbids spawning subagents, so implementation stays within that reviewed design rather than launching an additional Gate pair.
