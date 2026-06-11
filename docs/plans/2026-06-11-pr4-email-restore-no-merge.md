# #441 PR4 — Slim email fallback: no-merge `restoreWithEmailLink` Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the merge-based `completeRecovery` with a no-merge `restoreWithEmailLink` discard-shell swap (mirroring PR3's `restoreWithGoogle`), delete the `MergeOnRecoverDialog` semantics, and restore a reachable email-fallback entry on the home empty state.

**Architecture:** `AuthRecoveryService` loses its client half of the merge engine (cleanup intents, `cleanupAnonUidArtifacts` wiring, inline retry, Sentry breadcrumb recorder) and gains `restoreWithEmailLink`, which runs the identical isolation protocol as `restoreWithGoogle` — FCM-token removal → engageIsolation → flush → dirty-mark → `signInWithEmailLink` → guaranteed restart — with the email path's extra op-state handshake cleared in `finally`. The deep-link bootstrap's `opRecover` branch repoints to the new method. The send-side screens (`RecoverScreen`/`RecoverPendingScreen`) survive as the slim fallback UI, minus the merge-consent dialog.

**Tech Stack:** Flutter / Riverpod 2.x, firebase_auth email-link, mocktail, SharedPreferences mock.

**Parent:** `docs/plans/2026-06-11-durable-credential-recovery-rearchitecture.md` (PR4 row). Epic #441.

---

## Why no-merge is safe (the load-bearing argument)

- Post-PR2, the gate (client `GroupService.createGroup`/`joinGroup` + rules `sign_in_provider != 'anonymous'` + callable anon-reject, all LIVE in prod since `20689860`) guarantees an anonymous UID can never own or join a group. The anon shell that `signInWithEmailLink` discards is **provably empty of money data**.
- The two pre-gate shell writes: `fcm_tokens/{uid}` is removed pre-swap (same as PR3 — owner-only rules at `security/firestore.rules` make it un-deletable after the UID changes); `recoveryCleanupIntents/{oldUid}` is no longer written at all (this PR deletes the writer).
- A POPULATED device is necessarily credentialed (post-gate invariant), and an email-restore swap on it loses nothing server-side: the data stays keyed to the credentialed UID, recoverable by signing back into it. The legacy case (pre-gate anon-populated device) is accepted under the standing "no real users yet" decision — same acceptance PR3 shipped with.
- Therefore `MergeOnRecoverDialog` ("we'll move this phone's data into the restored account") describes machinery that no longer runs; keeping it would be a false promise. It is deleted, not repointed.

## Verification principles run (against live code, this worktree = origin/main @ 057f79f8)

1. **Callsite classification for `completeRecovery`:** exactly ONE production callsite — `auth_email_link_bootstrap_provider.dart:152` (OUTBOUND: triggers the swap + server merge). Test callsites enumerated in Task 5. `sendRecoveryLink` callsites: `recover_screen.dart:70`, `recover_pending_screen.dart:81` (send-side, unchanged).
2. **Concrete claims re-verified:** `MergeOnRecoverDialog.show` invoked only at `recover_screen.dart:56` (grep). `/recover` push sites: `lib/features/settings/screens/profile_screen.dart:272` only — the home empty-state CTA now calls `triggerGoogleRestore` (`home_screen.dart:318`), so a brand-new device currently has NO UI path to initiate email recovery (the Profile banner requires an already-arrived link). PR4 restores the entry.
3. **Read-path per write-path:** `_setInFlightOp(opRecover)` (write, `sendRecoveryLink`) → read at `bootstrap:148` to dispatch; cleared in the new method's `finally` (same R3 P2-4 boot-loop guard as today). `auth.pendingLinkEmail` (write, `setPendingEmail`) → read at `bootstrap:134` + inside `restoreWithEmailLink`. The `recoveryCleanupIntents/{oldUid}` write is DELETED; its only reader is the server callable, which PR5 deletes — between PR4 and PR5 the callable simply never receives intents (deny-by-default: it no-ops without one; rules block client reads).
4. **Fields enumerated from the type:** `AuthRecoveryService` constructor params after PR4: `auth`, `prefs`, `cacheIsolationController`, `firestore?`, `googleCredentialFactory?`, `removeFcmToken?`. Removed: `cleanupAnonUidArtifacts`, `cleanupIntentFactory`, `recoveryCleanupFailureRecorder`.
5. **Data contracts spelled out:** `restoreWithEmailLink(String emailLink, {String? overrideEmail, Duration pendingWritesTimeout = Duration(seconds: 5)}) → Future<UserCredential>`. Throws `StateError` (no pending email AND no override) BEFORE any side effect; propagates `FirebaseAuthException` from `signInWithEmailLink` AFTER the guaranteed restart is scheduled in `finally`.
6. **Arithmetic decomposition:** N/A — no money math touched. The money-adjacent invariant is shell-emptiness, argued above.
7. **Adversarial pass on an orthogonal axis (identity/time):** the dangerous variant is opRecover state set on device A, link tapped on device B that has a LIVE credentialed user → swap replaces it. Identical exposure exists today with `completeRecovery`; the no-merge variant strictly reduces blast radius (no server rewrite of the old UID's references). The #414/#213 guard is preserved: NO explicit `signOut` anywhere in the new method — a failed `signInWithEmailLink` leaves the current user signed in and the `finally` restart returns to it.

## What PR4 does NOT touch

- `linkEmailToCurrentUser` / `completeEmailLink` (same-UID LINK half — never caused a bug).
- `signOutCurrentDevice`.
- `FirebaseFunctionsService.cleanupAnonUidArtifacts` + `CleanupOutcome` + their tests (server-layer wrapper; PR5 deletes alongside the callable).
- The server callable, rules `recoveryCleanupIntents` block, TTL fieldOverride (PR5).
- `recover_screen.dart` / `recover_pending_screen.dart` structure (kept as the slim fallback UI; only the merge-dialog hook and stale doc comments change).
- Routing tree (`/recover` + `/recover/pending` routes unchanged; the new home CTA pushes an existing path).

---

### Task 1: RED — new unit suite for `restoreWithEmailLink`

**Files:**
- Create: `test/unit/auth_recovery_service_email_restore_test.dart`

Mirror `test/unit/auth_recovery_service_google_restore_test.dart` structurally (`_RecordingController`, event-list ordering, `dirtyAtSwap` probe). Since the merge-engine constructor params are deleted in Task 2, the no-merge pin is structural (the machinery no longer exists); what the tests pin is the protocol ordering and the #414 invariant.

**Step 1: Write the failing tests**

```dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/core/services/cache_isolation_controller.dart';
import 'package:safar/core/services/cache_uid_barrier.dart';
import 'package:safar/features/auth/services/auth_recovery_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

class _MockUserCredential extends Mock implements UserCredential {}

class _MockFirestore extends Mock implements FirebaseFirestore {}

class _RecordingController implements CacheIsolationController {
  _RecordingController(this.events);
  final List<String> events;
  @override
  void engageIsolation() => events.add('engage');
  @override
  Future<void> restart() async => events.add('restart');
}

void main() {
  late _MockFirebaseAuth auth;
  late _MockUser anonUser;
  late _MockFirestore firestore;
  late SharedPreferences prefs;

  const link = 'https://rihla-safar.firebaseapp.com/__/auth/links/continue'
      '?mode=signIn&oobCode=test-oob';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    auth = _MockFirebaseAuth();
    anonUser = _MockUser();
    firestore = _MockFirestore();
    when(() => auth.currentUser).thenReturn(anonUser);
    when(() => auth.signOut()).thenAnswer((_) async {});
    when(() => anonUser.uid).thenReturn('anon-uid-123');
    when(() => anonUser.isAnonymous).thenReturn(true);
    when(firestore.waitForPendingWrites).thenAnswer((_) async {});
  });

  AuthRecoveryService buildService({
    required List<String> events,
    FcmTokenRemover? removeFcmToken,
  }) {
    return AuthRecoveryService(
      auth: auth,
      prefs: prefs,
      firestore: firestore,
      cacheIsolationController: _RecordingController(events),
      removeFcmToken: removeFcmToken,
    );
  }

  group('restoreWithEmailLink (no-merge cross-UID discard-shell swap)', () {
    test(
      'removes the FCM token, engages isolation, marks the cache dirty '
      'BEFORE the swap, signs in with the email link, then restarts — '
      'and clears the op-state',
      () async {
        final events = <String>[];
        final userCredential = _MockUserCredential();
        when(() => userCredential.user).thenReturn(anonUser);

        bool? dirtyAtSwap;
        when(
          () => auth.signInWithEmailLink(
            email: 'saved@example.com',
            emailLink: link,
          ),
        ).thenAnswer((_) async {
          dirtyAtSwap = prefs.getBool(kFirestorePersistenceDirtyKey);
          events.add('signIn');
          return userCredential;
        });

        final service = buildService(
          events: events,
          removeFcmToken: () async => events.add('removeToken'),
        );
        await service.setPendingEmail('saved@example.com');
        await service.sendRecoveryLink('saved@example.com').catchError((_) {});

        // sendRecoveryLink hits the auth mock; stub it.
        // (Stubbed in implementation step — see note below.)

        final result = await service.restoreWithEmailLink(link);

        expect(result, same(userCredential));
        expect(events, ['removeToken', 'engage', 'signIn', 'restart']);
        expect(dirtyAtSwap, isTrue);
        expect(service.readPendingEmail(), isNull);
        expect(service.readInFlightOp(), isNull);
        verifyNever(() => auth.signOut());
      },
    );

    test('restarts AND clears op-state even if the swap throws '
        '(overlay never strands, no boot-loop), and never signs out', () async {
      final events = <String>[];
      when(
        () => auth.signInWithEmailLink(
          email: 'saved@example.com',
          emailLink: link,
        ),
      ).thenAnswer((_) async {
        events.add('signIn');
        throw FirebaseAuthException(code: 'invalid-action-code');
      });

      final service = buildService(
        events: events,
        removeFcmToken: () async => events.add('removeToken'),
      );
      await service.setPendingEmail('saved@example.com');

      await expectLater(
        service.restoreWithEmailLink(link),
        throwsA(isA<FirebaseAuthException>()),
      );
      expect(events, ['removeToken', 'engage', 'signIn', 'restart']);
      expect(service.readPendingEmail(), isNull);
      expect(service.readInFlightOp(), isNull);
      verifyNever(() => auth.signOut());
    });

    test('throws StateError BEFORE any side effect when no pending email '
        'and no override (shell fully intact)', () async {
      final events = <String>[];
      final service = buildService(
        events: events,
        removeFcmToken: () async => events.add('removeToken'),
      );

      await expectLater(
        service.restoreWithEmailLink(link),
        throwsStateError,
      );
      expect(events, isEmpty);
      verifyNever(
        () => auth.signInWithEmailLink(
          email: any(named: 'email'),
          emailLink: any(named: 'emailLink'),
        ),
      );
    });

    test('overrideEmail wins over the persisted pending email', () async {
      final events = <String>[];
      final userCredential = _MockUserCredential();
      when(() => userCredential.user).thenReturn(anonUser);
      when(
        () => auth.signInWithEmailLink(
          email: 'override@example.com',
          emailLink: link,
        ),
      ).thenAnswer((_) async => userCredential);

      final service = buildService(events: events);
      await service.setPendingEmail('saved@example.com');

      await service.restoreWithEmailLink(
        link,
        overrideEmail: 'override@example.com',
      );

      verify(
        () => auth.signInWithEmailLink(
          email: 'override@example.com',
          emailLink: link,
        ),
      ).called(1);
    });

    test('still swaps and restarts when waitForPendingWrites exceeds the '
        'timeout', () async {
      final events = <String>[];
      final userCredential = _MockUserCredential();
      when(() => userCredential.user).thenReturn(anonUser);
      when(
        firestore.waitForPendingWrites,
      ).thenAnswer((_) => Completer<void>().future);
      when(
        () => auth.signInWithEmailLink(
          email: 'saved@example.com',
          emailLink: link,
        ),
      ).thenAnswer((_) async {
        events.add('signIn');
        return userCredential;
      });

      final service = buildService(
        events: events,
        removeFcmToken: () async => events.add('removeToken'),
      );
      await service.setPendingEmail('saved@example.com');

      await service.restoreWithEmailLink(
        link,
        pendingWritesTimeout: const Duration(milliseconds: 50),
      );

      expect(events, ['removeToken', 'engage', 'signIn', 'restart']);
    });
  });
}
```

Note: in the first test, make the inFlightOp-cleared assertion REAL (not vacuous — Gate R2 P3): stub `auth.sendSignInLinkToEmail` (register an `ActionCodeSettings` fallback value) and arm the op-state via a real `sendRecoveryLink` call before the swap, so `readInFlightOp()` is `opRecover` going in and `isNull` coming out.

**Step 2: Run to verify it fails for the right reason**

Run: `flutter test test/unit/auth_recovery_service_email_restore_test.dart`
Expected: COMPILE ERROR — `restoreWithEmailLink` is not defined. Paste the output into the PR body as RED evidence.

### Task 2: GREEN — implement `restoreWithEmailLink`, delete the client merge engine

**Files:**
- Modify: `lib/features/auth/services/auth_recovery_service.dart`

**Step 1: Add the method** (after `restoreWithGoogle`, mirroring its doc style):

```dart
/// Restore the previously-linked account via an email sign-in link, then
/// restart (#441 PR4 — the slim email fallback, D3). Cross-UID
/// discard-shell swap: identical protocol to [restoreWithGoogle], WITHOUT
/// the merge engine — the post-gate anon shell is provably empty (PR2
/// gates `fcm_tokens` writes; this PR deletes the cleanup-intent writer),
/// so there is nothing to migrate and `cleanupAnonUidArtifacts` is never
/// invoked.
///
/// Ordering is load-bearing (see [restoreWithGoogle]); the one addition is
/// the email-path op-state (`pendingLinkEmail` / `inFlightOp`), cleared in
/// the `finally` alongside the guaranteed restart so a dead link can never
/// boot-loop the bootstrap (R3 P2-4). NO explicit signOut: a failed swap
/// MUST leave the current user signed in (#414/#213).
Future<UserCredential> restoreWithEmailLink(
  String emailLink, {
  String? overrideEmail,
  Duration pendingWritesTimeout = const Duration(seconds: 5),
}) async {
  final email = (overrideEmail ?? readPendingEmail())?.trim();
  if (email == null || email.isEmpty) {
    throw StateError(
      'No pending email available to restore — call setPendingEmail '
      'first or pass overrideEmail',
    );
  }

  // Owner-only rules block deleting fcm_tokens/{oldUid} after the UID
  // swaps, and engageIsolation invalidates the notification provider — so
  // remove the token while still signed in as the outgoing UID. Placed
  // before isolation and outside the try/finally: a throw aborts the
  // restore with the shell intact rather than stranding the overlay.
  await _removeFcmToken();

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
    final result = await _auth.signInWithEmailLink(
      email: email,
      emailLink: emailLink,
    );
    FirebaseConfig.log('Restore: restored uid ${result.user?.uid}');
    return result;
  } finally {
    await _safeClearRecoveryOpState();
    await _cacheIsolationController.restart();
  }
}
```

**Step 2: Delete the merge half.** Remove, in the same file:
- `completeRecovery` (whole method) + `_cleanupWithInlineRetry`.
- Typedefs `RecoveryCleanupFailureRecorder`, `CleanupAnonUidArtifacts`, `CleanupIntentFactory`.
- Constructor params + fields `_cleanupAnonUidArtifacts`, `_cleanupIntentFactory`, `_recoveryCleanupFailureRecorder` and their default initializers.
- `buildCleanupIntentPayload`, `_cleanupIntentCollection`, `_cleanupIntentTtl`, `_generateCleanupSecret`, `_secureRandom`, `_recordCleanupFailureBreadcrumb`.
- Now-unused imports: `dart:convert`, `dart:math`, `package:cloud_functions/cloud_functions.dart`, `package:sentry_flutter/sentry_flutter.dart`, `../../../core/services/firebase_functions_service.dart`, `flutter/foundation` (both of its consumers — `@visibleForTesting` at :158 and `Uint8List` at :137 — die with the deletions). Keep `cloud_firestore` (the `_firestore` field), `dart:async`, `shared_preferences`.
- KEEP `_safeClearRecoveryOpState` (now serving `restoreWithEmailLink`).
- Update the class doc comment (drop "spec §4" merge framing; reference the parent plan).

**Step 3: Run the new suite**

Run: `flutter test test/unit/auth_recovery_service_email_restore_test.dart`
Expected: PASS (5/5).

**Step 4: Commit**

```bash
git add lib/features/auth/services/auth_recovery_service.dart test/unit/auth_recovery_service_email_restore_test.dart
git commit -m "feat(auth): restoreWithEmailLink no-merge discard-shell swap; delete client merge engine (#441 PR4)"
```

(The tree is NOT green yet — dependent tests still reference deleted params; that's Tasks 3–5, committed in sequence within the PR branch. Branch-level green is the gate, enforced before push.)

### Task 3: Repoint the bootstrap `opRecover` branch

**Files:**
- Modify: `lib/features/auth/providers/auth_email_link_bootstrap_provider.dart:151-155`
- Modify: `test/unit/auth_email_link_bootstrap_test.dart`

**Step 1: Update the test** — replace **ALL** `completeRecovery` occurrences in the file with `restoreWithEmailLink` (~24 sites incl. `when`/`verify`/`verifyNever` lines and a test-name string at :215; mocktail `Mock implements AuthRecoveryService` picks the renamed method up automatically). Same canned `UserCredential` answers throughout.

**Step 2: Run it** — Expected: FAIL (bootstrap still calls the old name… which no longer compiles after Task 2; in practice Tasks 2-3 land together for compilation — the RED checkpoint is the test naming `restoreWithEmailLink` before the bootstrap change).

**Step 3: Repoint the dispatch:**

```dart
if (op == AuthRecoveryService.opRecover) {
  final result = await service.restoreWithEmailLink(link);
  ...
```

(Success snack + `pendingEmailLinkProvider` reset unchanged.)

**Step 4: Run:** `flutter test test/unit/auth_email_link_bootstrap_test.dart` — Expected: PASS.

**Step 5: Commit** — `git commit -m "feat(auth): bootstrap opRecover dispatches the no-merge email restore (#441 PR4)"`

### Task 4: Delete `MergeOnRecoverDialog`; un-hook `RecoverScreen`

**Files:**
- Delete: `lib/features/auth/widgets/merge_on_recover_dialog.dart`
- Modify: `lib/features/auth/screens/recover_screen.dart` (drop import, `_confirmIfDevicePopulated`, the `_send()` consent step at lines 60-65, the `ref.watch(userGroupsProvider)` at line 128 + its comment, the `group_provider.dart` import, and rewrite the class doc comment lines 17-29 to describe the no-merge fallback)
- Modify: `test/features/auth/recover_screen_test.dart` (delete the populated-device dialog tests at lines 162-218; keep/adjust the no-dirty-marking test 220-248 — it must pass WITHOUT the dialog tap step; fresh-device happy path unchanged)
- Modify: `test/features/auth/confirm_dialogs_test.dart` (remove the MergeOnRecoverDialog table entry at lines 71-76 and the copy test at 124-134)
- Modify: `lib/l10n/app_en.arb` + `lib/l10n/app_ar.arb` (remove `authMergeOnRecoverTitle/Body/Confirm` + their `@` descriptions)
- Modify: `lib/features/auth/README.md` (drop the merge_on_recover_dialog bullet; fix the `completeRecovery` mention in the service bullet → `restoreWithEmailLink`)
- Regen: `flutter gen-l10n`

Steps: delete tests first, run the two test files (RED on missing-symbol is acceptable here since this is a deletion task), apply deletions, `flutter gen-l10n`, re-run both files → PASS, commit `refactor(auth): delete MergeOnRecoverDialog — no merge to consent to (#441 PR4)`.

### Task 5: Sweep remaining constructor callsites + port surviving `completeRecovery` pins

**Files:**
- Delete: `test/unit/auth_recovery_intent_payload_test.dart` — both tests call the deleted `AuthRecoveryService.buildCleanupIntentPayload` (its #170 TTL-payload contract dies with the writer; the rules/TTL consumers go in PR5). [Gate R1 P1]
- Modify: `lib/features/auth/providers/auth_provider.dart:44` — `linkedEmailProvider` doc comment references `[completeRecovery]`; drop the clause (analyzer doc-ref + Task 7 grep guard). [Gate R1 P2]
- Modify: `test/unit/auth_recovery_service_test.dart` — delete the `completeRecovery` group (lines 243-738; its non-merge ordering/op-state pins are superseded by Task 1's suite); drop the 3 removed constructor params from its `buildService`; delete now-unused locals.
- Modify: `test/unit/auth_recovery_service_restart_guarantee_test.dart` — retarget `completeRecovery` → `restoreWithEmailLink`; drop removed params + the now-unused `firebase_functions_service.dart` import (`CleanupOutcome` was only needed by the dropped stub). The pinned guarantee (a throwing prefs `remove` can never skip `restart()`) carries over verbatim.
- Modify: `test/unit/auth_recovery_service_inflight_op_test.dart` — retarget the `completeRecovery clears…` test (lines 124-141) → `restoreWithEmailLink`; drop removed params + the now-unused `firebase_functions_service.dart` import at :6 (its only use, `CleanupOutcome` at :67, dies with the dropped stub). [Gate R2 P2]
- Modify: `test/unit/auth_recovery_service_google_link_test.dart` + `test/unit/auth_recovery_service_google_restore_test.dart` — drop the `cleanupAnonUidArtifacts`/`cleanupIntentFactory` throwing stubs from `buildService` (params no longer exist; the pin is now structural). Keep a one-line comment noting the machinery was deleted in PR4.
- Modify: `test/integration/firebase_auth_test.dart:201` — comment-only fix ("populated-device merge" → "restore swap").

Run: `flutter test test/unit/ test/features/auth/` — Expected: PASS.
Commit: `test(auth): retarget recovery suites at restoreWithEmailLink (#441 PR4)`

### Task 6: Home empty-state email-fallback entry

**Files:**
- Modify: `lib/features/home/screens/home_screen.dart` (below the Google CTA at line 313-327)
- Modify: `lib/l10n/app_en.arb` / `app_ar.arb` — REPLACE the orphaned `homeRecover` key (orphaned by PR3, same surface) with `homeRestoreWithEmail`: EN `"Restore with email instead"`, AR `"الاستعادة عبر البريد الإلكتروني بدلًا من ذلك"`.
- Modify: `test/features/home/home_restore_cta_test.dart` — add a case: tapping `home_empty_recover_email_cta` pushes `/recover` (and does NOT call `restoreWithGoogle`).

**Step 1: Failing test** (router-spy pattern already used in that file). Run → RED (key not found).
**Step 2: Add the button:**

```dart
TextButton(
  key: const Key('home_empty_recover_email_cta'),
  // #441 PR4: slim email fallback (D3). Same safety argument as the
  // Google CTA above — empty state ⇒ zero groups ⇒ the discarded anon
  // shell holds no money data.
  onPressed: () => context.push('/recover'), // string path — home_screen has no AppRoutes import; matches :296/:306 convention [Gate R2 P2]
  child: Text(
    context.l10n.homeRestoreWithEmail,
    style: AppTypography.sans(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: context.colors.textSecondary,
    ),
  ),
),
```

**Step 3: `flutter gen-l10n`; run the file → PASS. Commit** `feat(home): email-fallback restore entry on the empty state (#441 PR4)`

### Task 7: Branch verification

- [ ] `flutter analyze` → clean
- [ ] `flutter test` → full suite green
- [ ] `grep -rn "completeRecovery\|MergeOnRecoverDialog\|authMergeOnRecover\|homeRecover\b\|buildCleanupIntentPayload\|cleanupIntentFactory\|_cleanupWithInlineRetry" lib/ test/` → zero hits (except generated-file regen artifacts; re-run gen-l10n if any)
- [ ] `grep -rn "recoveryCleanupIntents" lib/` → zero hits (writer deleted; server/rules refs live outside `lib/` until PR5)
- [ ] Security checklist (no secrets, no new endpoints, auth path verified by suite)
- [ ] Push, open PR: `Refs #441` (epic stays open for PR5), body carries RED evidence from Task 1 + `Spec:` line pointing at this doc.
- [ ] `/automerge <N>` (Gate-category → fresh-context diff review + refuter).

## Considered and rejected

- **A replacement consent dialog for email restore:** the Google restore (PR3) shipped consent-free from the empty state (zero-group invariant); symmetry + no false "merge" promise. The Profile-banner → RecoverScreen path on a populated device swaps a credentialed account whose data survives server-side.
- **Keeping `completeRecovery` as a deprecated shim:** a live data-loss-capable API with zero callers is exactly the Schrödinger state the contract bans.
- **Deleting RecoverScreen/RecoverPendingScreen now:** they ARE the slim fallback UI (D3 needs a send-side email form); the parent plan's PR5 inventory line listing them as deletable is corrected by this spec — flagged for the PR5 doc rewrite.
