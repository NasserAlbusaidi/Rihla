# #469 prevention — same-device hard-block of anon-shell delete

**Issue:** #469 (P1, privacy). `deleteAccount` deletes the *current session*'s uid. When the session is an anonymous shell but a durable Google/email account exists under a different uid, the delete removes the empty shell and the durable account + data survive ("Connect with Google" signs straight back in). #546 already shipped the **disclosure** mitigation (identity-honest "delete guest session" dialog). This is the **prevention remainder**: hard-block the anon-shell delete when a durable account was established on this device, routing the user to sign in to it first.

**Direction:** settled in the #469 re-scope — same-device hard-block (NOT "make durable delete removable"). The block is the slice that lets #469 fully close.

**Gate category:** auth/deletion. Mandatory fresh-context Gate before implementation.

## Why the session is anon at delete time (the issue's open question)

Resolved by #546: the bug is **exclusively the anonymous case** — a durable session already deletes correctly (the server deletes `request.auth.uid`, which IS the durable uid for a durable session). The session is an anon shell when: sign-out re-mints a fresh anon (`signOutCurrentDevice` keeps the durable account alive), a post-restart shell, or a session/durable-uid split. The prevention is robust to ALL of these: it keys off `isAnonymous && (a durable account was established on this device)`, not the specific cause.

## Server is already correct — no server code change

`deleteAccount.ts` revokes refresh tokens (`:682`) and `getAuth().deleteUser(request.auth.uid)` (`:779`); `deleteUser` removes the entire Auth user **including all providerData**. For a durable session `request.auth.uid` is the durable uid, so deleting a Google/email-linked user removes the Auth user + its providers. The acceptance box "deleting a linked user removes the Auth user + providers" is therefore a **test-only lock** (Jest), not a code change → **no backend deploy for #469**.

## The marker (device-local, persistent) — set by OBSERVING durability

New SharedPreferences key `auth.durableAccountEstablished` (bool). Key + helper fns in a new shared file `lib/features/auth/services/durable_account_marker.dart` (mirrors `recovery_outcome.dart`'s helper style): `markDurableAccountEstablished(prefs)` (guarded, idempotent — no-op if already true), `durableAccountEstablished(prefs) → bool`, `clearDurableAccountEstablished(prefs)`. Single source of truth imported by the setter provider, the deletion service, and the read site.

**SET via observe-durability, NOT enumerated establish-events** (Gate P1 fix): enumerating link/restore methods misses paths — the Google in-place force-refresh lives in the widget (`durable_credential_sheet.dart`), and its `provider-already-linked` success branch never re-enters `linkGoogleToCurrentUser`. Instead, a dedicated provider observes the auth state and marks durability wherever it actually appears:

```dart
// lib/features/auth/providers/durable_account_marker_provider.dart
final durableAccountMarkerProvider = Provider<void>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  ref.listen<AsyncValue<User?>>(authUserChangesProvider, (_, next) {
    final user = next.valueOrNull;
    if (user != null && !user.isAnonymous) {
      unawaited(markDurableAccountEstablished(prefs));
    }
  }, fireImmediately: true);   // fireImmediately catches a durable-at-boot session
});
```
Watched by `appBootstrapProvider` (alongside `recoveryOutcomeNoticeProvider`). This captures EVERY durable session however reached — in-place link (service or widget already-linked branch), restore swap, or a durable session restored at boot — so there is no missed-path hole.

- **CLEAR** on a successful `deleteAccount` in `data_deletion_service.dart`. **Exact placement (Gate P2 fix):** `await clearDurableAccountEstablished(_prefs)` at the TOP of the success block, immediately after the `'Deletion: server cascade completed'` log and BEFORE `engageIsolation()` — so it always runs (not inside the `try` whose `signOut()` could throw and skip it) and is awaited before the `finally`'s `restart()` kills the process (`MainActivity.restartApp` flushes QueuedWork, but await + pre-restart placement is the contract, not luck). Unconditional clear is safe: after the block lands, `deleteAccount` is reached only by durable users (marker set → clear) or genuine guests (no marker → no-op).
- NOT touched by `signOutCurrentDevice` — sign-out keeps the durable account alive, so the marker must persist so the next fresh-anon delete is still gated.

## Client block — informed-escape (decided 2026-06-17)

In `profile_screen.dart` `_AccountCard._deleteAccount`:
```
isAnonymous = authUserChangesProvider.isAnonymous
durableExists = durableAccountEstablished(ref.read(sharedPreferencesProvider))  // direct prefs read, not a cached Provider
if (isAnonymous && durableExists) {
  final choice = await DurableShellDeleteDialog.show(context);
  if (choice == DurableShellDeleteChoice.deleteGuest && context.mounted) {
    await _runDeletion(context, ref);   // explicit, informed escape
  }
  return;   // signIn / cancel → no deletion (Connect with Google tile is on-screen)
}
... existing #546 path (DeleteAccountDialog.show(isAnonymous: ...))
```
`DurableShellDeleteDialog` (new) returns an enum `{ signIn, deleteGuest, cancel }`:
- **primary "Sign in to my account"** → dismiss, no deletion (the `Connect with Google` tile is always rendered for anon — `profile_screen.dart:1154`, gated on `isAnonymous` only, NOT `showRestore` — so it is reachable even when the shell has groups; this resolves the Gate P2 dead-end);
- **secondary "Delete just this guest session"** → proceed with the #546 deletion of the shell (explicit, informed — no silent survival);
- **Cancel** → dismiss.

Copy references only "Connect with Google" (always visible), NOT "Recover account" (hidden when the shell has groups). No routing change.

## Known limitation (named, not a bug)

The marker is device-local prefs. An **app reinstall** wipes prefs → the device has no marker and a fresh anon → a delete then removes the fresh anon while the durable account survives (the original #469 shape, post-reinstall). This falls back to the #546 **disclosure** (the dialog still fires honest copy for any anon session), so it is never silent. Server-side detection of "a durable account exists for this person" from a fresh anon shell is infeasible (no identifier without re-auth). Accepted scope: same-device prevention + disclosure fallback.

## Tests (RED→GREEN)

1. **Client (regression, the #469 box)** — extend `test/features/auth/delete_account_tile_test.dart`: with an anon session AND `auth.durableAccountEstablished=true` in mock prefs, tapping Delete shows `DurableShellDeleteDialog` and `deleteAccount` is NOT called on "Sign in"/Cancel; IS called only via "Delete just this guest session". RED today: it shows the plain delete dialog and (on confirm) calls deleteAccount. Also assert: anon WITHOUT marker → unchanged #546 path; durable session → unchanged normal path.
2. **Marker SET (unit)** — `durableAccountMarkerProvider`: a ProviderContainer overriding `authUserChangesProvider` (emit a non-anon `User`) + `sharedPreferencesProvider` → `durableAccountEstablished(prefs)` becomes true; an anon emission leaves it false. fireImmediately covers durable-at-boot.
3. **Marker CLEAR (unit)** — `data_deletion_service` removes `durableAccountEstablished` on a successful `deleteAccount` (extend the existing service test harness).
4. **Server (Jest, lock)** — `functions/test/callables/deleteAccount.test.ts`: a user with a linked **password** provider that OWNS a live group → `deleteAccount` → assert `getAuth().getUser(uid)` throws `auth/user-not-found` (durable Auth user removed) AND the group is scrubbed. `deleteUser` removes the entire Auth user regardless of provider count, so a password-provider user suffices to lock "a durable-with-data account is fully removed" (a `google.com` federated provider needs `importUsers`, which the harness doesn't use — out of scope; the lock is the deletion, not the provider type). Test-only; no server change.

## l10n

New ARB keys for the block dialog (title/body/dismiss) in `app_en.arb` + `app_ar.arb` (RTL). Regenerate.

## Out of scope

- Reinstall / cross-device durable detection (named limitation; disclosure covers it).
- Any server cascade change (server already correct).
- Routing changes (block dialog is informational).

## Sequence

spec → **Gate** → server Jest RED-ish (assert durable delete) → client RED (block not present) → marker unit RED → implement marker + block + dialog + l10n → GREEN → analyze + Dart tests + scoped emulator deleteAccount test → `/automerge` (Gate-category: review+refute). **No deploy** (test-only server, client-only behavior).
