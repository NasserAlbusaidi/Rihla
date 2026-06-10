# Anonymous Auth and Account Recovery

Design rationale for Rihla's identity model. Explains **why** the app
ships with no sign-up screen, why email-link recovery is opt-in,
why a UID change wipes the local cache, and why we need a server-side
`cleanupAnonUidArtifacts` callable.

For the implementation reference (what the callable does, error codes,
client wrappers), see [CLOUD-FUNCTIONS.md](./CLOUD-FUNCTIONS.md). For
the product-side behaviour catalog, see
[PRODUCT.md § Identity & Auth](./PRODUCT.md).

---

## 1. The problem

A group expense splitter needs to identify "who paid for what" to
calculate balances. Conventional apps solve this with a sign-up screen:
email + password, OAuth, or magic link. Every conventional approach
introduces a wall before the first useful interaction.

For Rihla's wedge — friends settling up a trip — the wall is the
expensive part. The user is already mid-conversation about money.
Asking them to create an account before they can record a single
expense is the most common abandonment point in apps of this shape.

We wanted the **time-to-first-expense to be zero seconds**. No
sign-up, no email confirmation, no password. The first launch should
just work.

That goal sets up a tension:

- **No sign-up** means we have no durable identifier across devices or
  reinstalls.
- **Settling money** means we need *some* persistent identity inside
  groups, otherwise members can't recover from losing their phone.

The recovery system exists to resolve this tension *for the users who
need it* without imposing the cost on the users who don't.

---

## 2. The approach

Three layered mechanisms, each opt-in past the previous one:

```
┌─────────────────────────────────────────────────────────┐
│  Layer 1: anonymous Firebase Auth                       │
│  — First launch creates an anon UID. Persisted on the   │
│  device. No sign-up. This is the default identity.      │
└─────────────────────────────────────────────────────────┘
                            │
                            │ user opts in via Profile → Link email
                            ▼
┌─────────────────────────────────────────────────────────┐
│  Layer 2: email-link recovery                           │
│  — Anon UID is linked to an email. The same UID can     │
│  now be restored on a fresh install via email-link      │
│  sign-in. No password.                                  │
└─────────────────────────────────────────────────────────┘
                            │
                            │ user lost their phone / reinstalled
                            ▼
┌─────────────────────────────────────────────────────────┐
│  Layer 3: recovery flow                                 │
│  — On the new device, the user enters their email.      │
│  Firebase sends a sign-in link. Tapping the link        │
│  produces a *different* UID than the original anon      │
│  session ever had. We rebind groups to the recovered    │
│  UID via the cleanupAnonUidArtifacts callable.          │
└─────────────────────────────────────────────────────────┘
```

The opt-in stages map onto a single principle: **start with zero
friction; let the user buy more durability when they care**. Users who
never link an email never face a single auth dialog. Users who do link
get cross-device recovery.

---

## 3. Why anonymous Firebase Auth?

Three options were on the table when this was designed:

1. **No auth at all** — Identify the user by a locally-generated UUID
   stored in `SharedPreferences`. Cheapest path.
2. **Anonymous Firebase Auth** — UID assigned by Firebase, persisted
   in the platform Keychain/Keystore by the SDK.
3. **Sign-up screen** — Email/password or OAuth on first launch.

We picked **(2)**. The reasoning:

| Concern | (1) Local UUID | (2) Anon Firebase | (3) Sign-up |
|---------|----------------|-------------------|-------------|
| Time-to-first-expense | 0s | 0s (silent) | 60s+ |
| Survives app uninstall | ❌ | ❌ | ✅ |
| Works with Firestore Security Rules | ❌ (rules need `request.auth.uid`) | ✅ | ✅ |
| Upgradeable to a linked identity later | Hard | ✅ (linkWithCredential) | n/a |
| Backend abuse surface | Open | Token-gated | Token-gated |

Option (1) loses immediately because Firestore Security Rules need a
real `request.auth.uid` to evaluate ownership predicates (B1) and
group-membership checks. We'd have to either ship a vacuous rule set
or invent a custom auth layer.

Option (3) loses because the wall before the first interaction is
exactly the cost we're trying to avoid.

Option (2) gives us the best of both: real `request.auth.uid` for the
rules, no user-visible friction, and a documented upgrade path
(`User.linkWithCredential`) when the user later opts into recovery.

The trade-off: a Firebase anon UID is tied to the device's Auth state.
Wipe the app, reinstall, or move to a new phone, and the UID is gone —
along with access to any groups it was a member of. **Layer 2 exists
specifically to fix this for users who care.**

---

## 4. Why email-link, not password?

Firebase supports many sign-in methods. We picked email-link
specifically and deliberately:

| Method | Pros | Cons |
|--------|------|------|
| Email + password | Familiar | Password reset flow, breach surface, 2 forms |
| **Email link (magic link)** | One field, no password | Requires email round-trip |
| Phone (SMS) | Fast | SMS costs $, country support varies |
| Google / Apple OAuth | One tap | Vendor lock-in, account-linking edge cases, app review hurdles |

The argument for email-link:

- **One input.** The user types an email and submits. No password to
  invent or remember. No "Forgot password?" path to maintain.
- **Built-in second factor.** Possession of the email account *is*
  the auth proof. There's no separate password to phish.
- **Cross-device works for free.** The link in the email is just a
  URL with a one-time token; tapping it on any device produces a
  signed-in session.
- **No SMS cost or geo limitations.**
- **Firebase ships the primitives** (`sendSignInLinkToEmail`,
  `signInWithEmailLink`, `linkWithCredential`).

The trade-off: email round-trip latency. Recovery takes minutes, not
seconds. For the use case — restoring access after a phone is lost or
replaced — this is fine. We are not on a hot path.

---

## 5. The link/recover distinction

Once an email is involved, there are two distinct flows. They use the
same Firebase primitive (`sendSignInLinkToEmail`) but the *meaning* of
tapping the link differs:

| Flow | Trigger | Effect on UID | Implementation |
|------|---------|---------------|----------------|
| **Link** | User is signed in (anonymously). They want to attach an email for future recovery. | UID is **preserved** — the anon UID gains an email credential. | `User.linkWithCredential(...)` |
| **Recover** | User has a new install (no UID yet, or a fresh anon UID they want to discard). They have a previously-linked email. | UID **changes** — sign in as the linked user; the previous anon UID is abandoned. | `FirebaseAuth.signInWithEmailLink(...)` |

The bootstrap listener (`auth_email_link_bootstrap_provider.dart`)
needs to know which flow the user is in when they tap the link,
because the same `mailto:` URL would otherwise be ambiguous.

The solution: `AuthRecoveryService` writes the in-flight operation
kind to `SharedPreferences` at send-time:

```dart
// lib/features/auth/services/auth_recovery_service.dart
static const String opLink = 'link';
static const String opRecover = 'recover';
```

When the link is tapped, the bootstrap reads the flag and dispatches
to the correct completion path. The flag is cleared after success.

---

## 6. The UID-change problem (FR-CACHE-1) — sealed (#68)

When the recovery flow runs, the active Firebase UID changes from the
anon `oldUid` to the recovered `newUid`. Any data the client read under
`oldUid` that lingers in a local cache could be served to the new user —
a cross-UID leak:

> *"User A signs out, user B installs on the same device, signs in with
> their email. A provider reads stale rows cached against A's groups.
> User B sees A's groups."*

This is the **FR-CACHE-1** invariant.

**Status (#68).** The original fix was `UidChangeListener`, which
wiped the SQLite cache (`safar_cache.db`) on UID change. Issue #50
removed the SQLite cache entirely — it provided nothing over Firestore
offline persistence and was itself the home of a separate cross-UID leak
class — so that listener is gone.

The concern then landed on the **Firestore SDK's own on-disk offline
cache** (`persistenceEnabled: true`). That cache is now cleared on
**every** UID swap via a cold-start identity barrier (`CacheUidBarrier`
+ `FirestoreCacheGate` in `lib/core/services/`), plus an in-session
isolation overlay and a true native restart
(`cache_isolation_controller.dart` / the `MainActivity` restart
channel). Because the API only permits `clearPersistence()` before
startup or after `FirebaseFirestore.terminate()`, the clear runs at the
next cold boot; a durable dirty flag (`markFirestorePersistenceDirty`)
makes that clear crash-safe across the restart even if the process dies
mid-swap. FR-CACHE-1 is **enforced on main**. The only residual item is
on-device eviction re-confirmation against a release AAB during RD-QA
(#40) — a verification task, not a code gap.

---

## 7. Why `cleanupAnonUidArtifacts` is a server callable

After recovery, the user's groups still reference `oldUid` in:

- `groups/{gid}.memberIds`
- `groups/{gid}/members/{oldUid}`
- `groups/{gid}/events/{eid}.participantIds`
- `groups/{gid}/events/{eid}.participantNames` (keyed by UID)
- `groups/{gid}/events/{eid}.createdBy` (where the old user created an event)
- `groups/{gid}/events/{eid}/expenses/*.createdBy`

We need to rewrite every one of these to point at `newUid`. The
client cannot do this for three reasons:

1. **Cross-document atomicity.** A single group might have dozens of
   events and hundreds of expenses. A client batch caps at 500
   writes; a single transaction can read 10 documents and write 500.
   A large group would exceed both.
2. **Security rules wouldn't allow it.** The rules grant a member the
   ability to update *their own* member doc's display name and to
   leave the group. They do **not** allow a member to rewrite
   `memberIds`, `createdBy`, or `participantIds` on every doc in the
   group. Granting that broadly would weaken the rules across the
   normal write paths.
3. **The Auth-side delete needs admin privileges.** The old anon UID
   should be deleted from Firebase Auth as part of cleanup so it
   cannot be re-signed-in by anyone holding a stale token. Only the
   Admin SDK can do that.

So the work moves server-side. `cleanupAnonUidArtifacts` runs under
the Admin SDK (`functions/src/admin.ts`), which bypasses Firestore
Security Rules entirely. Per-group transactions stay atomic; auth
deletion happens after the Firestore scrub.

The v1.0 release hardening adds a one-time cleanup intent before that
Admin rewrite is allowed. While still signed in as the retiring anon
UID, the client writes `recoveryCleanupIntents/{oldUid}` with a random
secret. After email-link sign-in, the callable requires the same secret
and rejects missing, expired, or mismatched intents. This prevents a
recovered user from passing an arbitrary visible anon UID and migrating
someone else's group references.

The trade-off: a Cloud Function is one more deploy surface and one
more error mode. The runbook (T2 in `docs/RUNBOOK.md`) calls out the
error-rate tripwire that catches cleanup failures.

The callable is **awaited** by the client (`completeRecovery` holds
the isolation overlay up until it reaches a terminal state, then
restarts — see `auth_recovery_service.dart`). Since #427 the wrapper
also surfaces the callable's structured result (`CleanupOutcome` with
the server's `cascadeFailed` list) and retries a partial migration
once inline, while the 15-minute cleanup intent is still valid — the
server consumes the intent only when every group migrated, so a
structured partial failure provably leaves it in place for the retry.
If the retry still fails, the failure is recorded to Sentry with the
stranded group ids; the user is signed in and functional, but those
groups remain keyed to the old anon UID (the old Auth user is kept,
so the data is recoverable).

The reference implementation is documented in
[CLOUD-FUNCTIONS.md § 2](./CLOUD-FUNCTIONS.md#2-cleanupanonuidartifacts).

---

## 8. Why account deletion is its own callable

A reasonable question: if `cleanupAnonUidArtifacts` already rebinds
UIDs, why not reuse it for deletion (rebind to a sentinel UID)?

The decision (logged 2026-05-16) was to ship `deleteAccount` as a
separate callable because:

1. **Different identity semantics.** Cleanup transfers identity from
   old UID to new UID — both are real people. Deletion replaces the
   identity with a per-group tombstone (`deleted-xxxxxxxx`) so each
   group cannot correlate one deletion across multiple groups by UID.
2. **Different PII handling.** Cleanup keeps the user's display name,
   notes, descriptions — it's the *same person*. Deletion **scrubs**
   `note`, `description`, `receiptUrl` on every expense the user
   touched. Different code path.
3. **Different end state for the auth user.** Cleanup deletes the
   *old* (anon) UID and keeps the *new* UID alive. Deletion deletes
   the only UID.
4. **Audit surface.** A user looking at the activity feed should see
   "Deleted member activity" for a deleted user, not the same name
   they always saw. Activity-log rewriting is deletion-specific.

Trying to fold both into one callable produced enough conditional
branches that the resulting code was harder to review than two
single-purpose callables. The 2026-05-16 decision picks two callables
plus a small amount of shared scaffolding (the `processGroup`
transaction shape, the batch writer).

---

## 9. What we gave up

Honest list of limitations this design accepts:

### "Lose your phone, lose your data" for non-linked users

Users who never link an email and lose their device (or clear app
data) lose access to their groups. This is the price of zero
friction on first launch. The Home screen surfaces a recovery CTA so
the path back exists if they previously linked.

### Account-linking edge cases on the same email

Firebase Auth has subtle behaviour when an email is already linked to
a different user. We rely on Firebase's built-in handling
(`completeEmailLink` throws on conflicts), and the recover screen
surfaces the error to the user. The fallback is the user contacts
support; we have not built an in-app conflict-resolution UI.

### Cleanup is best-effort

If `cleanupAnonUidArtifacts` fails after recovery — terminally, i.e.
after the one inline retry `completeRecovery` performs while the
cleanup intent is still valid (#427) — the user functions but any
group in the server's `cascadeFailed` list stays keyed to the old
anon UID: it vanishes from the restored account's group list and
balances. The failure is loud (Sentry, with the group ids), the old
Auth user is kept so the data is recoverable, but reconciliation
after the 15-minute intent expires needs a future maintenance pass
(see "Known Limitations" in `docs/PRODUCT.md`).

### Anon UID quota is unprotected

There is no captcha on `signInAnonymously`. A bot farm could exhaust
the Firebase anonymous-auth quota for the project. T4 in the runbook
covers the response if this becomes a real problem.

### Email-link delivery depends on email infrastructure

Spam filters, mail-server outages, and user typos can prevent the
link from arriving. We don't have a re-send debounce on the send
button beyond what Firebase enforces server-side. If delivery
becomes an issue at scale, we'd add per-user send throttling.

---

## 10. The flow end-to-end

For reference, here is the sequence of operations during a successful
recovery (user has linked an email previously, lost their phone, and
installed Rihla on a new device):

```
Day 0 (link path, on original device):
  Profile → Link email → enters email
    → AuthRecoveryService.linkEmailToCurrentUser(email)
      → setPendingEmail(email) [persists to SharedPreferences]
      → setInFlightOp('link')
      → Firebase: sendSignInLinkToEmail(email)
  Email arrives → user taps link
    → DeepLinkService routes the URL to AuthEmailLinkBootstrap
      → reads inFlightOp = 'link'
      → AuthRecoveryService.completeEmailLink(emailLink)
        → User.linkWithCredential(EmailAuthProvider.credentialWithLink(...))
        → clearPendingEmail()
        → clearInFlightOp()
  UID UNCHANGED (still original anon UID, now with email credential).

Day N (recover path, on new device):
  First launch creates a fresh anon UID — call it tempUid.
  Home empty state shows "Restore from email" CTA → /recover
    → RecoverScreen → enters email
    → AuthRecoveryService.sendRecoveryLink(email)
      → setPendingEmail(email)
      → setInFlightOp('recover')
      → Firebase: sendSignInLinkToEmail(email)
  Email arrives → user taps link
    → DeepLinkService routes the URL
      → reads inFlightOp = 'recover'
      → AuthRecoveryService.completeRecovery(emailLink)
        → cacheIsolationController.engageIsolation()  -- overlay covers UI until restart
        → create recoveryCleanupIntents/{tempUid} with one-time secret
        → waitForPendingWrites(timeout: 5s)
        → markFirestorePersistenceDirty(prefs)  -- durable cross-restart cache-clear marker
        → FirebaseAuth.signInWithEmailLink(...)  -- signs in as originalUid;
          NO signOut first (#414): the swap IS the sign-in, and on failure
          the current session must survive
        → await cleanupAnonUidArtifacts(oldUid: tempUid, cleanupSecret)
          -- awaited inside the overlay; a partial/thrown result is retried
             ONCE inline while the intent is still valid (#427), terminal
             failures go to Sentry with the stranded group ids
        → returns UserCredential (uid = originalUid)
        → finally: cacheIsolationController.restart()  -- GUARANTEES a true native restart
  Auth stream emits tempUid -> originalUid:
    → Riverpod providers re-evaluate under originalUid → groups appear.
    → (Before the swap, the isolation overlay is engaged and the Firestore
       cache is marked dirty; after sign-in the flow triggers a true native
       restart, and the cold-boot CacheUidBarrier clears the outgoing UID's
       on-device Firestore cache — cross-UID isolation is enforced, #68.)
  Server-side, before the restart returns the user to the app:
    cleanupAnonUidArtifacts callable:
      → For each group containing tempUid (none on a fresh install — but
        on a POPULATED device this is the merge itself):
        rewrite memberIds, members docs, event participant refs,
        expense payer/split keys (money values sum-merged on collision),
        settlement parties, activity actor ids.
      → Delete tempUid from Firebase Auth.
      → Delete fcm_tokens/{tempUid}.
      → Delete joinAttempts/{tempUid} and the consumed cleanup intent.
        (Auth-delete + intent-delete happen ONLY when every group
        migrated — a partial failure keeps both for the inline retry.)
```

### Populated-device recovery is a consented MERGE (#427)

The walkthrough above assumes a fresh device, but `/recover` is also
reachable on a device that already has groups under its anon UID. The
original design (FR-REC-2/3/4, spec §5.2 of the deleted
`docs/design/account-recovery.md`) handled that with a sign-out-first
dialog:

> FR-REC-2: "recovery is refused unless the user confirms the
> sign-out-first dialog" — FR-REC-3: "the prior anon UID is signed
> out and its data discarded" — FR-REC-4: "no migration step is
> required".

All three are **superseded**. Signing out before sending the link was
itself the data-loss bug: anon mint happens only at boot, so by
link-tap time the old UID was either gone (warm app → `oldUid` null →
cleanup skipped) or replaced by a fresh empty anon (cold boot) —
either way the populated UID's data was orphaned. Since #427 the
populated path shows `MergeOnRecoverDialog` ("Restore and merge"),
keeps the anon UID signed in, and lets `completeRecovery` +
`cleanupAnonUidArtifacts` migrate everything under `oldUid → newUid`:
FR-REC-2 → consented merge; FR-REC-3 → migrated, never discarded;
FR-REC-4 → the migration IS the mechanism.

The hand-offs across `SharedPreferences` (`pendingEmail`, `inFlightOp`)
let the flow survive an app restart between sending the link and
tapping it — important because real users tap the link in a different
app (their email client) and only come back to Rihla via the URL
launcher.

---

## 11. Files at a glance

| File | Role |
|------|------|
| `lib/features/auth/services/auth_recovery_service.dart` | Orchestrates link/recover/sign-out. Holds the pending-email + in-flight-op SharedPreferences keys. |
| `lib/features/auth/services/data_deletion_service.dart` | Wraps the `deleteAccount` callable for the Profile delete flow. (Deletion teardown is treated as a cross-UID swap: it engages `CacheIsolationController` and marks the Firestore SDK cache dirty so the cold boot clears it — cross-UID isolation is live, #68. The legacy SQLite-wipe `uid_change_listener.dart` was removed with the SQLite cache in #50.) |
| `lib/core/services/cache_uid_barrier.dart`, `firestore_cache_gate.dart`, `cache_isolation_controller.dart` | The shipped cross-UID barrier: cold-start identity reconcile + `clearPersistence`, in-session isolation overlay, and the native restart channel (#68). |
| `lib/features/auth/services/auth_email_link_config.dart` | Centralised `ActionCodeSettings` (URL, package name, Play / iOS metadata). |
| `lib/features/auth/providers/auth_email_link_bootstrap_provider.dart` | Listens for incoming email links, dispatches to link vs recover. |
| `lib/features/auth/providers/auth_provider.dart` | `authStateProvider`, `currentUserProvider` etc. |
| `lib/features/auth/screens/link_email_screen.dart` | Profile → Link email form. |
| `lib/features/auth/screens/link_email_sent_screen.dart` | Post-send "Check your email" screen. |
| `lib/features/auth/screens/recover_screen.dart` | Home → Recover entry. |
| `lib/features/auth/screens/recover_pending_screen.dart` | Post-send waiting screen on the recover side. |
| `lib/main.dart` (`_AuthGateState.initState`, ~line 125) | `FirebaseConfig.ensureAnonymousSession()` — establishes the first UID (and the cold-boot `CacheUidBarrier` runs inside it). |
| `functions/src/callables/cleanupAnonUidArtifacts.ts` | Server-side UID migration. |
| `functions/src/callables/deleteAccount.ts` | Server-side cascade delete. |
| `security/firestore.rules` | Owner-only and member-only invariants per UID. |

---

## 12. Related docs

- [CLOUD-FUNCTIONS.md](./CLOUD-FUNCTIONS.md) — reference for the two callables this design depends on
- [SECURITY-RULES.md](./SECURITY-RULES.md) — why the rules can't do the cross-doc rewrites these flows need
- [ARCHITECTURE.md § 6 Offline](./ARCHITECTURE.md) — how Firestore offline persistence serves the data flow
- [PRODUCT.md § Identity & Auth](./PRODUCT.md) — user-facing summary
- [RUNBOOK.md § T2 Functions error rate](./RUNBOOK.md) — incident response if the cleanup callable starts failing
