# Anonymous Auth and Account Recovery (durable-credential architecture)

**Status:** rewritten 2026-06-11 for epic #441. This supersedes the email-link
RECOVER design this doc previously described; the decision record is
`docs/plans/2026-06-11-durable-credential-recovery-rearchitecture.md`.

The one-line architecture: **money data stays keyed to the first-launch
anonymous UID forever.** A one-tap Google `linkWithCredential` is required
before the first valuable write (group create/join), which makes that UID
durable with zero migration. Recovery on a new device is
`signInWithCredential` → same UID → everything loads. There is no cross-UID
merge anywhere in the system.

---

## 1. The problem this solves

Rihla signs every user in anonymously on first launch — zero-friction browse,
no login wall. But an anonymous UID lives only in device keystore: lose the
phone, reinstall, or hit an auth-state wipe and the UID — and every ledger
row keyed to it — is unreachable.

The v1.2 answer was email-link recovery with a server-side merge: sign into
the previously-linked account (a NEW UID on this device) and have a 691-LOC
callable (`cleanupAnonUidArtifacts`) rewrite every reference to the retiring
anon UID — `payerParticipantId`, `splitDistribution` keys, `participantIds`,
`memberIds`, settlement parties, member docs. That cross-UID swap was the
project's deepest bug class: #213 (transient token error treated as
corruption → data orphaned), #216 (ledger partition on partial migration),
#414 (link-failure auto-fallback orphaned the shell), #427 (merge
reachability). Every incident traced to the same root: **money data born
under a throwaway UID, rescued later by a rewrite.**

\#441 deletes the rescue by deleting the need: the UID becomes durable
*before* it owns anything.

## 2. The architecture (four shipped pieces)

| Piece | PR | What it does |
|---|---|---|
| Google link foundation | PR1 #443 | `google_sign_in` 7.x (Credential Manager sheet), `linkGoogleToCurrentUser()` — same-UID `linkWithCredential`, `serverClientId` via `config.json` |
| The gate | PR2 #444 | Inside `GroupService.createGroup`/`joinGroup` (service-level, so offline-queued batches can't bypass it) + **server enforcement**: rules `request.auth.token.firebase.sign_in_provider != 'anonymous'` on group/inviteCode create, anon-reject in `joinGroupByInviteCode`. `fcm_tokens` writes gated `!isAnonymous` so the pre-gate shell stays empty |
| Google restore | PR3 #447 | Home empty-state CTA → `restoreWithGoogle()`: credential first (cancel-safe), FCM token removal, full cache-isolation protocol (engage → flush → dirty-mark → `signInWithCredential` → guaranteed restart). Discards the provably-empty anon shell |
| Email fallback | PR4 #449 | `sendRecoveryLink` kept; `restoreWithEmailLink()` replaced the old `completeRecovery` — same discard-shell protocol via `signInWithEmailLink`, **no merge**, op-state cleared in `finally`. `MergeOnRecoverDialog` deleted. Secondary "Restore with email instead" entry under the Google CTA |

PR5 (this change) deleted the merge engine the first four made unreachable:
the `cleanupAnonUidArtifacts` callable + its test, the
`recoveryCleanupIntents` rules block + TTL fieldOverride, and the client
wrapper (`CleanupOutcome`).

## 3. Why the shell-discard is safe

- **Post-gate, an anonymous UID cannot own money data.** The gate is
  server-enforced (rules + callable), not a client promise — an ungated or
  malicious client gets `PERMISSION_DENIED` on group create/join.
- **The two pre-gate anon writes are handled:** `fcm_tokens/{uid}` is gated
  on `!isAnonymous` (and removed pre-swap in both restore paths, because
  owner-only rules make it un-deletable after the UID changes);
  `recoveryCleanupIntents` no longer exists.
- **A populated device is necessarily credentialed**, and swapping away from
  a credentialed account loses nothing — its data stays server-side under
  its own UID, recoverable by signing back into it.
- Both restore entries render only on the zero-group home empty state.

## 4. What stayed (and why)

- **Anonymous-first launch.** Zero-friction browse is untouched; the gate
  fires at the first create/join (the #288/#352 natural-moment pattern).
- **The email LINK half** (`linkEmailToCurrentUser`/`completeEmailLink`) —
  same-UID by construction, never caused a bug. Email remains the fallback
  credential so Google-loss ≠ permanent lockout (D3).
- **The cache-isolation stack** (#45/#68: `CacheUidBarrier`,
  `FirestoreCacheGate`, the in-session overlay + true restart) — **MUST-KEEP**.
  Restores and sign-outs are still cross-UID swaps on the *device*, and the
  stack is what keeps UID A's cached money out of UID B's session.
- **`signOutCurrentDevice`**, account deletion (`deleteAccount` callable),
  and the #213 invariant: `recoverRestoredSessionIfNeeded` never discards a
  session on a token-check failure.
- **`RecoverScreen` / `RecoverPendingScreen`** — kept as the slim email
  fallback UI (enter email → link sent → tap → no-merge swap). The epic's
  original inventory listed them deletable; PR4 corrected that — without
  them a new device has no way to request a sign-in link.

## 5. Failure modes that remain (accepted)

- **Anon user who never passes the gate loses data on device loss.** Same as
  every browse-only session; by construction they own no groups.
- **Google account loss** → restore via the email fallback (if set up) or
  nothing. D3 keeps both credentials possible; neither is mandatory after
  the gate fires once.
- **Conflict on link** (`credential-already-in-use` / `email-already-in-use`
  — one-account-per-email can surface either; the service wraps both in
  `GoogleLinkConflictException` carrying the failed credential): the gate
  sheet offers "Switch account" → `restoreWithGoogle(credential: reused)` +
  forced restart, but ONLY when the live group count proves the current
  shell empty — a populated shell (legacy pre-gate anon) gets the dead-end
  "use a different account" copy instead (#428). The caller's in-flight
  create/join form is persisted (`PendingGateIntent`) before the restore and
  replayed on the post-restart boot. Never auto-resolved by signing the anon
  user out (#414's lesson, now structural).

## 6. Files at a glance

| File | Role |
|------|------|
| `lib/features/auth/services/auth_recovery_service.dart` | `linkEmailToCurrentUser` / `completeEmailLink` / `linkGoogleToCurrentUser` / `restoreWithGoogle` / `restoreWithEmailLink` / `signOutCurrentDevice` + pending-email & in-flight-op handoff |
| `lib/features/auth/services/google_sign_in_gateway.dart` | google_sign_in 7.x wrapper (initialize-once, credential factory) |
| `lib/features/auth/services/data_deletion_service.dart` | Wraps the `deleteAccount` callable for the Profile delete flow (deletion teardown is a cross-UID swap; #68 isolation applies) |
| `lib/core/services/cache_uid_barrier.dart`, `firestore_cache_gate.dart`, `cache_isolation_controller.dart` | The shipped cross-UID barrier: cold-start identity reconcile + `clearPersistence`, in-session isolation overlay, native restart channel (#68) |
| `lib/features/auth/services/auth_email_link_config.dart` | Centralised `ActionCodeSettings` (URL, package name, Play / iOS metadata) |
| `lib/features/auth/providers/auth_email_link_bootstrap_provider.dart` | Deep-link receive side: `opLink` → `completeEmailLink`, `opRecover` → `restoreWithEmailLink` |
| `lib/features/auth/widgets/google_restore_action.dart` | Home-CTA trigger for `restoreWithGoogle` (cancel-silent) |
| `lib/features/auth/screens/link_email_screen.dart` / `link_email_sent_screen.dart` | Profile → Link email form + post-send screen |
| `lib/features/auth/screens/recover_screen.dart` / `recover_pending_screen.dart` | Email-fallback send side |
| `lib/main.dart` (`_AuthGateState.initState`) | `FirebaseConfig.ensureAnonymousSession()` — establishes the first UID (cold-boot `CacheUidBarrier` runs inside it) |
| `functions/src/callables/joinGroupByInviteCode.ts` | Server-side anon-reject on join |
| `functions/src/callables/deleteAccount.ts` | Server-side cascade delete |
| `security/firestore.rules` | `isDurableSignIn()` gate on group/inviteCode create + owner/member invariants per UID |

## 7. History

The deleted merge-engine design (anon shell merged into the restored account
via bearer-secret cleanup intents + server rewrite) and its incident trail
(#213/#216/#414/#427) are preserved in git history (this file before
2026-06-11, `cleanupAnonUidArtifacts.ts` at `057f79f8`) and in
`docs/plans/2026-06-11-durable-credential-recovery-rearchitecture.md`, which
records why every alternative (keep hardening the swap, login wall, seed
phrases, group-anchored rejoin) was rejected.

## 8. Related docs

- `docs/plans/2026-06-11-durable-credential-recovery-rearchitecture.md` — the decision record
- `docs/plans/2026-06-11-pr4-email-restore-no-merge.md` / `2026-06-11-pr5-delete-merge-engine.md` — the last two implementation specs
- [SECURITY-RULES.md](./SECURITY-RULES.md) — rules by collection
- [CLOUD-FUNCTIONS.md](./CLOUD-FUNCTIONS.md) — the surviving Functions inventory
- [ARCHITECTURE.md](./ARCHITECTURE.md) — system context
- [PRODUCT.md § Identity & Auth](./PRODUCT.md) — user-facing summary
