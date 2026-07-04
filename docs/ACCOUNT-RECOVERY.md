# Anonymous Auth and Account Recovery (durable-credential architecture)

**Status:** rewritten 2026-06-11 for epic #441 and updated 2026-07-04 after
#818 removed the create-time durable gate. This supersedes the email-link
RECOVER design this doc previously described; the original decision record is
`docs/plans/2026-06-11-durable-credential-recovery-rearchitecture.md`.

The one-line architecture: **money data stays keyed to the UID that created or
joined it.** First launch still starts with an anonymous UID, and that UID can
own groups. Linking Google/email uses same-UID `linkWithCredential` to make that
UID recoverable with zero migration. Recovery on a new device is
`signInWithCredential` -> same UID -> everything loads. There is no cross-UID
merge anywhere in the system; cross-UID restore/switch paths may discard only a
provably-empty outgoing shell.

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

\#441 deleted the rescue by deleting cross-UID merge. The original create/join
gate that forced durability before ownership was later relaxed: join was
ungated in #648, and create was ungated in #818. That makes the empty-shell
guard, not a server create/join prerequisite, the safety boundary for
restore/switch.

## 2. The architecture (four shipped pieces)

| Piece | PR | What it does |
|---|---|---|
| Google link foundation | PR1 #443 | `google_sign_in` 7.x (Credential Manager sheet), `linkGoogleToCurrentUser()` — same-UID `linkWithCredential`, `serverClientId` via `config.json` |
| Optional account-link prompts | #818 follow-up | `showDurableCredentialSheet()` is now entered from helper surfaces (backup nudge, Profile, create-screen account-link CTA), not a create/join blocker. Same-UID linking makes the current UID durable without moving data. |
| Google restore | PR3 #447 | Home empty-state CTA / Profile restore row → `restoreWithGoogle()`: credential first (cancel-safe), FCM token removal, full cache-isolation protocol (engage → flush → dirty-mark → `signInWithCredential` → guaranteed restart). Allowed only when the outgoing shell is provably empty. |
| Email fallback | PR4 #449 | `sendRecoveryLink` kept; `restoreWithEmailLink()` replaced the old `completeRecovery` — same no-merge cross-UID swap via `signInWithEmailLink`, guarded by the same empty-shell check, op-state cleared in `finally`. `MergeOnRecoverDialog` deleted. |

PR5 (this change) deleted the merge engine the first four made unreachable:
the `cleanupAnonUidArtifacts` callable + its test, the
`recoveryCleanupIntents` rules block + TTL fieldOverride, and the client
wrapper (`CleanupOutcome`).

## 3. Why the shell-discard is safe

- **A populated anonymous UID can own money data. It must not be discarded.**
  The current create/join path allows anonymous ownership; restore/switch safety
  comes from `outgoingShellProvablyEmpty`, not from assuming anon shells are
  empty by construction.
- **Cross-UID restore/switch requires a provably-empty outgoing shell.** Every
  entry point — home empty-state restore (`triggerGoogleRestore`), Profile
  restore, the Google conflict-switch, and the email-recover bootstrap — runs
  the shared `outgoingShellProvablyEmpty` guard at the swap itself and fails
  closed on loading/error. Surface visibility (the zero-group empty state, the
  Profile anon-only rows) is presentation, never the safety boundary (#647). A
  populated shell gets the dead-end copy instead of being signed out or swapped
  away.
- **There is still no merge.** The app never rewrites ledger/member references
  from UID A to UID B. Same-UID link makes UID A durable; cross-UID restore
  signs into UID B only after proving UID A has no groups.
- **Device-local cleanup still matters:** FCM token removal, cache-isolation
  engagement, pending-write flush, dirty-mark, and guaranteed restart remain
  required before any cross-UID swap so the outgoing UID's cached data cannot
  render in the incoming session.

## 4. What stayed (and why)

- **Anonymous-first launch.** Zero-friction browse, create, and join are
  untouched. The durable-credential sheet is a helper/prompt surface, not a
  create/join prerequisite.
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

- **Anon user who never links a credential loses data on device loss.** They may
  own groups; without Google/email, the UID only lives on that device.
- **Google account loss** → restore via the email fallback (if set up) or
  nothing. D3 keeps both credentials possible; neither is mandatory.
- **Conflict on link** (`credential-already-in-use` / `email-already-in-use`
  — one-account-per-email can surface either; the service wraps both in
  `GoogleLinkConflictException` carrying the failed credential): the account-link
  sheet offers "Switch account" → `restoreWithGoogle(credential: reused)` +
  forced restart, but ONLY when the live group count proves the current
  shell empty — a populated shell gets the dead-end
  "use a different account" copy instead (#428). Never auto-resolved by signing
  the anon user out (#414's lesson, now structural).

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
| `lib/features/auth/services/legacy_auth_marker_cleanup.dart` | One-release removal of the retired create-form prefs marker; no replay/prefill |
| `functions/src/callables/joinGroupByInviteCode.ts` | Server-side invite-code join; anonymous callers are allowed, App Check + throttling + entropy contain enumeration |
| `functions/src/callables/deleteAccount.ts` | Server-side cascade delete |
| `security/firestore.rules` | Owner/member invariants per UID; anonymous group/invite-code create is allowed after #818 |

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
