# Fix #414 — link-conflict auto-swap orphans the anon account

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** "Back up your account" with an email already bound to another account must surface an error and leave the anon session (and its data) intact — never silently swap accounts.

**Architecture:** Two changes, one concern. (1) `authEmailLinkBootstrapProvider` stops auto-falling-back from a failed LINK to a destructive `completeRecovery` — conflict codes route to the existing `_humanize` error surface. (2) `completeRecovery` stops calling `_auth.signOut()` before `signInWithEmailLink` — success implicitly replaces the session; failure now leaves the current user signed in. Recovery into another account remains possible only via `RecoverScreen`'s explicit, populated-device-confirmed flow.

**Tech Stack:** Flutter / Riverpod / firebase_auth / mocktail. Tests are pure unit tests (no Firebase init needed — service is constructor-injected, provider is override-injected).

**Issue:** #414 (P0 launch blocker, data loss). **Gate-category:** yes — auth deep-link handling, #213-class data-loss surface.

**Gate record:** R1 (2026-06-09, fresh-context Opus): **0 P1 / 0 P2 / 4 P3** — stop condition met. Reviewer independently verified `signInWithEmailLink` failure semantics against installed firebase_auth 6.3.0 source (`firebase_auth-6.3.0/lib/src/firebase_auth.dart:602-616` — rethrows without touching the session), the 2-caller claim, the same-UID dirty-marker cold-boot path (`cache_uid_barrier.dart:57-64` — harmless refetch), and the orthogonal identity/time axes. P3s (line/name drifts) folded into this spec.

---

## Verified facts (all re-checked against code 2026-06-09)

- The fallback lives at `lib/features/auth/providers/auth_email_link_bootstrap_provider.dart:162-199` (`shouldFallback` on `email-already-in-use` / `credential-already-in-use` / `provider-already-linked` while `op == opLink` → `service.completeRecovery(link)`).
- `completeRecovery` (`lib/features/auth/services/auth_recovery_service.dart:255-355`): `signOut()` at `:310` runs **before** `signInWithEmailLink` at `:311`; the `finally` (`:345-354`) always clears op-state and restarts. Email links are single-use — the preceding `linkWithCredential` attempt consumes the `oobCode`, so the fallback's `signInWithEmailLink` throws on a dead link **after** the anon session is already gone → cold boot mints a fresh empty anon → original anon orphaned (no email ⇒ unrecoverable).
- `completeRecovery` has exactly **2 callers**, both in the bootstrap provider (`:152` legit opRecover dispatch, `:177` the fallback). `pendingEmailLinkProvider` consumers (`profile_screen.dart:258` banner → routes to `/recover`; `recover_pending_screen.dart:132` hint) never call it.
- `RecoverScreen._confirmIfDevicePopulated` (`recover_screen.dart:47-67`) is the explicit consent gate (dialog + deliberate sign-out **before** sending the recovery link) — by `completeRecovery` time on the explicit path, the current user is already a fresh/empty anon or null, so removing the service-level `signOut()` does not change explicit-flow semantics.
- The May-22 removal of this exact fallback (`c1098811` "Stop automatic recovery fallback on link conflict") was **never merged** — it exists only on `codex/auth-release-hardening-*` branches. Main has always had the fallback. (The codex branch also added an `authEmailLinkConflictProvider`; we are NOT resurrecting it — YAGNI for the P0. Richer conflict UI = optional follow-up issue.)
- `docs/ACCOUNT-RECOVERY.md` §9 already documents the intended design ("`completeEmailLink` throws on conflicts, and the recover screen surfaces the error... no in-app conflict-resolution UI"). The code drifted from the doc; this fix restores the documented contract. No doc change needed.
- Tests pinning the OLD behavior (must be rewritten, not patched around):
  - `test/unit/auth_email_link_bootstrap_test.dart:207-375` — group `'link → recover auto-fallback'`.
  - `test/unit/auth_recovery_service_test.dart` — `:270` (verifyInOrder w/ signOut), `:299` (calls list w/ `'signOut'`), `:347` (`dirtyAtSignOut` hook), `:376` (events `['engage','signOut','restart']` on failed sign-in), `:501` (`verify(signOut).called(1)`).
  - `auth_recovery_service_restart_guarantee_test.dart:47` and `auth_recovery_service_inflight_op_test.dart:46` only **stub** `signOut` — stubs may stay (mocktail ignores unused stubs).

## Behavior contract after the fix

| Scenario | Before | After |
|---|---|---|
| opLink + conflict code | silent swap attempt → signOut → dead-link sign-in throws → restart → **fresh empty anon, data orphaned** | snackbar "This email is already linked to a Rihla account. Restore from that account instead." Anon session untouched. No restart. |
| opLink + other error | `_humanize` snackbar, session intact | unchanged |
| opRecover + sign-in fails (e.g. expired link) | signOut → throw → restart → fresh anon replaces current session | no signOut → throw → restart → **current session survives** the restart (#213 keep-restored-session). Op-state still cleared, restart still guaranteed (overlay never strands). |
| opRecover + sign-in succeeds | signOut → sign-in → cleanup → restart | sign-in (implicitly replaces session) → cleanup → restart. `oldUid` capture and `result.user?.uid != oldUid` cleanup gate unchanged. |

Claim the Gate must verify: **firebase_auth `signInWithEmailLink` replaces the current user on success and leaves `currentUser` untouched on failure** (no implicit sign-out on a thrown sign-in). Also: any listener relying on an interstitial `authStateChanges` null between old and new user? (Checked: `recover_pending_screen.dart:119` keys off `next != null && next != _initialUid` — works with a direct user→user switch, no interstitial null needed; the always-restart bounds in-session exposure anyway.)

Deliberately NOT in scope: clearing `pendingEmail`/`inFlightOp` on terminal conflict (matches every other terminal error path today; a stale op retries link on next cold start and surfaces a humanized `invalid-action-code` — annoying, not destructive); conflict-resolution UI; `signOutCurrentDevice` (its explicit signOut is its purpose); `markFirestorePersistenceDirty` placement (stays before sign-in — on a failed swap the next cold boot clears the same-uid cache, which is a harmless server refetch).

---

### Task 1: RED — bootstrap provider must not auto-recover on conflict

**Files:**
- Modify: `test/unit/auth_email_link_bootstrap_test.dart:207-375`

**Step 1: Rewrite the `'link → recover auto-fallback'` group**

Replace the whole group with (keep the four still-valid tests inside it — non-fallback code, opRecover no-re-fallback, the two dedupe tests — re-homed as shown):

```dart
  group('link conflict — no auto-recovery (#414)', () {
    for (final code in const [
      'email-already-in-use',
      'credential-already-in-use',
      'provider-already-linked',
    ]) {
      test(
        'opLink failing with $code surfaces the conflict and never calls '
        'completeRecovery',
        () async {
          when(() => service.readPendingEmail()).thenReturn('foo@example.com');
          when(
            () => service.readInFlightOp(),
          ).thenReturn(AuthRecoveryService.opLink);
          when(
            () => service.completeEmailLink(any()),
          ).thenThrow(FirebaseAuthException(code: code));
          await attach();

          uriStream.add(_validAuthLink());
          await pumpEventQueue();

          verify(() => service.completeEmailLink(any())).called(1);
          verifyNever(() => service.completeRecovery(any()));
        },
      );
    }

    test('conflict does not clear a stashed pending link', () async {
      when(() => service.readPendingEmail()).thenReturn('foo@example.com');
      when(
        () => service.readInFlightOp(),
      ).thenReturn(AuthRecoveryService.opLink);
      when(
        () => service.completeEmailLink(any()),
      ).thenThrow(FirebaseAuthException(code: 'email-already-in-use'));
      await attach();

      container.read(pendingEmailLinkProvider.notifier).state =
          'https://stale-link';
      uriStream.add(_validAuthLink());
      await pumpEventQueue();

      // Error paths leave the §4.7 stash alone — only successful completion
      // clears it.
      expect(container.read(pendingEmailLinkProvider), 'https://stale-link');
    });

    // Keep VERBATIM (names and bodies) the two still-valid tests:
    //   'opLink failing with non-fallback code does NOT call completeRecovery'
    //     (:257-275)
    //   'opRecover failing with email-already-in-use does NOT re-fallback'
    //     (:277-297)

    test('conflict error does not crash the stream', () async {
      when(() => service.readPendingEmail()).thenReturn('foo@example.com');
      when(
        () => service.readInFlightOp(),
      ).thenReturn(AuthRecoveryService.opLink);
      when(
        () => service.completeEmailLink(any()),
      ).thenThrow(FirebaseAuthException(code: 'email-already-in-use'));
      await attach();

      uriStream.add(_validAuthLink());
      await pumpEventQueue();

      when(
        () => service.completeEmailLink(any()),
      ).thenAnswer((_) async => _MockUserCredential());
      uriStream.add(_validAuthLink(oobCode: 'NEXT002'));
      await pumpEventQueue();

      verify(() => service.completeEmailLink(any())).called(2);
      verifyNever(() => service.completeRecovery(any()));
    });
  });

  group('cold-start dedupe', () {
    // Move the two dedupe tests here verbatim
    // (:299 'same link emitted by initial + stream…', :325 'different
    // oobCodes are processed independently') — they use opRecover and are
    // independent of the fallback.
  });
```

Delete: the old 3-code fallback loop **including its `for` header** (`:208-234`), `'successful fallback clears pendingEmailLinkProvider'` (`:236-255` — the scenario no longer exists), `'fallback recover failure does not crash the stream'` (`:349-374` — replaced above).

**Step 2: Run to verify RED**

Run: `flutter test test/unit/auth_email_link_bootstrap_test.dart`
Expected: the 3 conflict-code tests + 'conflict does not clear a stashed pending link' + 'conflict error does not crash the stream' FAIL with mocktail "No matching calls… completeRecovery was called" / state mismatch — because the fallback still fires. **Paste this output into the PR body (RED evidence, #329).**

**Step 3: Commit the red tests? No.** Keep RED+GREEN in one commit per repo convention (tree stays green per commit). Proceed to Task 2.

### Task 2: GREEN — remove the fallback

**Files:**
- Modify: `lib/features/auth/providers/auth_email_link_bootstrap_provider.dart:85-100` (doc comment) and `:162-206` (handler)

**Step 1: Replace the `on FirebaseAuthException` block**

Delete `:163-199` (the `shouldFallback` computation and the whole `if (shouldFallback) { … }` block), leaving:

```dart
    } on FirebaseAuthException catch (error, stack) {
      // #414: a LINK that fails with email-already-in-use (and friends) must
      // NEVER auto-fall-back to completeRecovery — that signs the anon
      // account out and orphans its data. Recovery into the other account is
      // an explicit, consented action via RecoverScreen only.
      FirebaseConfig.log(
        'Recovery: $op completion failed (${error.code})',
        error: error,
        stackTrace: stack,
      );
      _showSnack(_humanize(error), isError: true);
    } catch (error, stack) {
```

**Step 2: Update the provider doc comment (case 2, `:90-94`)**

```dart
///   2. `link` op (default; Settings → "Link my email") → attach email to
///      the current anon UID via `linkWithCredential`. If the email is
///      already owned by another account (`email-already-in-use` and
///      friends) the conflict is surfaced as an error and the anon session
///      is left untouched (#414) — never auto-recover here.
```

**Step 3: Run** `flutter test test/unit/auth_email_link_bootstrap_test.dart` → all PASS.

**Step 4: Commit** `fix(auth): never auto-swap accounts on email-link conflict (#414)` — includes the Task-1 test rewrite.

### Task 3: RED — completeRecovery must not signOut before a successful sign-in

**Files:**
- Modify: `test/unit/auth_recovery_service_test.dart` (5 pinned tests)

**Step 1: Rewrite the pins**

1. `:270` `'drains pending writes and signs out anon UID before recovery'` → rename `'drains pending writes before sign-in and never explicitly signs out'`; drop `() => auth.signOut()` from the `verifyInOrder`, add `verifyNever(() => auth.signOut())`.
2. `:299` `'invokes cleanup callable after signInWithEmailLink…'` → remove `'signOut'` from the expected `calls` list (keep the signOut recording stub — it proves non-invocation when absent from the list… better: also add `verifyNever`). Expected list becomes `['engage', 'intent:anon-uid-123', 'waitForPendingWrites', 'signInWithEmailLink', 'cleanup:anon-uid-123:client-secret', 'restart']`.
3. `:347` `'engages isolation first and marks the cache dirty before signOut'` → rename `…before sign-in`; move the `dirtyAtSignOut` capture hook from the `signOut` stub onto the `signInWithEmailLink` stub (`dirtyAtSignIn`).
4. `:376` `'clears op-state and restarts even when signInWithEmailLink fails'` → expected events `['engage', 'restart']` (no `'signOut'`), and add the headline #414 assertion: `verifyNever(() => auth.signOut());` with a comment `// #414: a failed swap must leave the current session signed in`.
5. `:501` `'continues recovery when pending writes exceed the timeout'` → replace `verify(() => auth.signOut()).called(1)` with `verifyNever(() => auth.signOut())`.

**Step 2: Run to verify RED**

Run: `flutter test test/unit/auth_recovery_service_test.dart`
Expected: all five FAIL (signOut IS currently called). **Paste representative output into the PR body.**

### Task 4: GREEN — drop the explicit signOut

**Files:**
- Modify: `lib/features/auth/services/auth_recovery_service.dart:306-314` + method doc `:245-254`

**Step 1: Remove `:310`** and leave a WHY comment:

```dart
      // Durable cross-restart marker: the cold boot clears the cache even if
      // the process dies before restart(). Awaited so it is flushed (§6.4).
      await markFirestorePersistenceDirty(_prefs);

      // No explicit signOut: signInWithEmailLink replaces the current session
      // on success, and on failure (e.g. a consumed single-use link) the
      // current user MUST survive — signing out first is how a no-email anon
      // account gets orphaned (#414, the #213 failure class).
      final result = await _auth.signInWithEmailLink(
        email: email,
        emailLink: emailLink,
      );
```

**Step 2: Update the method doc** (`:245-254`): replace "flush pending writes, mark the on-device Firestore cache dirty BEFORE the auth change, swap" wording — the swap is now the sign-in itself; note that a failed sign-in keeps the current session and the restart returns to it.

**Step 3: Run** `flutter test test/unit/auth_recovery_service_test.dart test/unit/auth_recovery_service_restart_guarantee_test.dart test/unit/auth_recovery_service_inflight_op_test.dart` → all PASS.

**Step 4: Commit** `fix(auth): keep session when recovery sign-in fails (#414)`.

### Task 5: Full verification

- `flutter analyze` → clean.
- `flutter test` → full suite green.
- Grep for survivors: `grep -rn "shouldFallback\|falling back to recover" lib/ test/` → no hits in lib/; no test still pins the fallback.

### Task 6: PR + merge gate

- Branch `fix/414-link-conflict-orphan` from main (work in worktree `../Rihla-414`).
- PR body: `Closes #414`, `Spec: docs/plans/2026-06-09-fix-414-link-conflict-orphan.md`, pasted RED outputs from Tasks 1 & 3, behavior-contract table.
- `/automerge <N>` — treat as **Gate-category** (auth deep-link / data-loss surface) regardless of path-classifier verdict: fresh-context Opus diff review + refuter required.
