# Task: Review v1.2.0+15 scope before implementation

## Context

Rihla v1.2.0+14 is on Play "first" closed-test track with 3 post-launch bugs fixed on branch `fix/post-launch-qa-v1.2` (6 commits ahead of `main`, not yet shipped). Before bumping to +15 and shipping, four "adjacent gaps" were scoped by parallel research agents. **You are reviewing the proposed scope and findings, not implementing yet.** Read each section, sanity-check the recommendations against the actual codebase, and report back: what's wrong, what's missing, what's over-scoped, what risk we're underestimating.

Project conventions in `CLAUDE.md` at repo root (terse, GoRouter declarative, `decimal` for money, `context.colors`/`context.spacing` for styling, no Navigator.push / no goNamed / no state.extra, soft-delete pattern, append-only settlements, `MoneySerializer` only at Firestore boundary).

## What's already shipped on the fix branch (do NOT re-review)

Commits on `fix/post-launch-qa-v1.2`:
- `b12c6d6` chore: capture bugs + temp App Check disable
- `35963c0` docs: Codex delegation spec for +14 fixes
- `7f76ff3` fix(qa): group detail back button + event settlement names
- `054ff16` fix(functions): re-enable App Check on joinGroupByInviteCode
- `b793eb6` fix(auth): currentUserIdProvider follows Firebase Auth swaps
- `4be4355` docs(qa): mark +14 bugs resolved on fix branch

Bugs already fixed (not in scope for this review):
1. Android back button on `/group/:gid` (PopScope + 48dp hit target)
2. Event settlements showing "Someone paid Someone" (service now persists payerName/recipientName)
3. Post-recovery "Could not identify your participant record" (`currentUserIdProvider` reactive on auth)

## Four gaps under review

Each gap has a **proposed verdict** below. Tell us where the verdict is wrong.

---

### Gap 1: Join-doesn't-sync-events — **proposed verdict: SHIP IN +15**

**Symptom:** User joins group via invite code AFTER an event exists. They're added to `group.memberIds` but NOT to `event.participantIds`. They see the event, cannot add expenses (surfaces as "Could not identify your participant record"). Observed on group "Meow", event "Dad".

**Proposed fix (from scoping agent):**
- Server-side. Extend `functions/src/callables/joinGroupByInviteCode.ts` to fan-out the joiner's UID + displayName into every non-deleted event's `participantIds` / `participantNames` within the same Admin-SDK transaction.
- Pattern: read events outside tx via `groupRef.collection('events').where('isDeleted','==',false).get()`, then re-read each inside the tx along with member doc, write all in one tx.
- Skip soft-deleted events (`isDeleted == true`).
- Idempotent on re-join (use `arrayUnion`).
- Effort: ~half day, ~40–60 LOC source + ~120 LOC Jest + ~80 LOC Flutter integration test.
- One-shot Node admin backfill script for already-affected production groups (~50 LOC, throwaway).

**Claimed reasoning vs client-side:** A client-side "join an event from event detail page" fix needs a rules loosening (today `validEventLightUpdate` requires `requesterIsParticipant()` — a non-participant cannot add themselves). Server fan-out keeps rules untouched.

**Specific questions for review:**
1. Is the "read events outside tx, then re-read in tx" pattern actually necessary in Admin SDK? Or can `groupRef.collection('events').get()` happen inside the transaction directly (Admin SDK has different reads-before-writes semantics than client SDK)?
2. Does Firestore's 500-writes-per-tx limit actually constrain us here, given Rihla groups realistically have <20 events? Is the "guard for >400 and fall back to batch" recommendation overkill for a closed-test launch?
3. Is there a simpler client-side option we're missing? Reread `security/firestore.rules` lines covering `validEventLightUpdate` and confirm a non-participant truly cannot add themselves.
4. Is `updatedAt: serverTimestamp()` write churn a real problem (per agent's "invalidates latest activity sort" landmine)? Cite where events are sorted by `updatedAt`.
5. The backfill script — should it be a one-shot throwaway, or worth keeping as a callable for ops use?

---

### Gap 2: Stale `participantNames` on event docs — **proposed verdict: DEFER to +16**

**Symptom:** When a user renames themselves (Profile → device name → mirrors to `groups/{gid}/members/{uid}.displayName`), existing event docs keep the OLD name in `event.participantNames[uid]`. Observed: event "Janel shams" shows user as "Mohammed" instead of current name "Nasser". Also affects `expense.payerName` and `settlement.payerName` denormalized snapshots.

**Proposed fix (from scoping agent):**
- Extend `propagateDisplayName` in `lib/core/providers/settings_provider.dart:101` to fan-out into events the user participates in.
- Rules diff: light path (`security/firestore.rules:315-333`) currently forbids changing existing `participantNames` values via `changedKeys().size() == 0` constraint. Loosen to allow `participantNames.{request.auth.uid}` self-update only.
- Display fallback in 3 widgets (`expense_card`, `settlement_row`, `ledger_search_sheet`) using `event.participantNames[payerId] ?? expense.payerName` pattern (mirrors existing fallback in `ledger_screen.dart:88`).
- Effort: ~3 hours.

**Claimed reasoning for deferring:** Cosmetic only. Identity/balance math keys off UIDs everywhere. No misattribution risk. Backfill is automatic on first rename after deploy.

**Specific questions for review:**
1. Is the agent right that this is **purely cosmetic** with no functional consequence? Grep for places where `participantNames` is compared, joined, or fed into logic — confirm UIDs really are the only identity key.
2. The rules loosening — is there an attack vector if we allow `participantNames.{request.auth.uid}` self-update? Could a malicious user inject HTML/control chars into other display surfaces?
3. Is the 3-widget fallback patch enough, or are there more sites? Grep for `payerName ?? 'Someone'` and `participantNames[` across the lib.
4. Should this actually ship in +15 alongside Gap 1 (it's only 3 hours)? Or is deferring genuinely safer?

---

### Gap 3: Orphan anonymous Firebase Auth users — **proposed verdict: PARTIAL fix in +15, full cascade in v1.2.1**

**Symptom:** Email-link recovery swaps Firebase Auth UID from anonymous → email-linked. The anon Auth user record is never deleted. Member-list views render both UIDs as separate member docs (same display name) — "two of me". `DataDeletionService.deleteAccount()` only deletes the current UID, so orphan anon Auth users accumulate forever — possible **GDPR compliance gap**.

**Proposed fix (from scoping agent):**

Ship in +15 (~4 hours):
- UI dedup in `lib/features/groups/widgets/group_members_section.dart`: hide member docs whose `userId` is not in `group.memberIds`. (Confirms agent's finding that the section iterates the `members` subcollection with zero dedup.)
- In `AuthRecoveryService.completeRecovery` (`lib/features/auth/services/auth_recovery_service.dart:151-181`): delete the soon-to-be-orphaned anon Auth user record *before* the signOut + signInWithEmailLink swap. Order matters: delete member docs while still signed in as anon (rules permit), then call `user.delete()` on the anon User, then sign in with the email link.

Defer to v1.2.1 (1–2 days):
- Full `auth.user.onDelete()` Cloud Function cascading `memberIds` array removal, `members/{uid}` delete, optional `createdBy` rewrite.
- Called from `cleanupOrphanAnonUid` callable during recovery for historical hygiene.

Defer indefinitely:
- UID rewrite of `createdBy` references. Rules make it immutable (settlements append-only, expenses/events `createdBy` immutable). Risky audit-trail mutation. Balance math doesn't consume `createdBy` so unnecessary.

**Specific questions for review:**
1. Is the agent right that **balance math is UID-list-driven, not createdBy-driven**? Cite `group_balance_provider.dart` and confirm no balance code branches on `createdBy`.
2. The proposed recovery-time anon-Auth-user delete order — is "delete member docs first while anon, then delete anon Auth user, then sign in with email link" actually safe? What happens if the anon Auth user delete fails mid-recovery? Is the user left in an unrecoverable state?
3. The "UI dedup" in `group_members_section.dart` — is hiding doc-where-`userId-not-in-memberIds` the right predicate? What if the doc represents a kicked member who needs to remain visible for historical context?
4. **GDPR concern:** does the privacy policy at `rihla.app/privacy` actually promise full deletion? If so, shipping +15 *without* fixing the orphan-anon-Auth-user gap is potentially non-compliant — should the full cascade be a +15 blocker, not a v1.2.1 item?
5. Is there a "two of me" case the dedup misses (e.g. when both anon UID + email UID are in `memberIds` because of a re-add)?

---

### Gap 4: RD-QA matrix RD-01..08 — **proposed verdict: DEFER, doc hygiene only**

**Symptom:** `docs/REAL-DEVICE-QA.md` matrix has empty Android cells. Release-gate repo vars (`RIHLA_BACKEND_RELEASE_READY`, `RIHLA_APP_CHECK_READY`, `RIHLA_REAL_DEVICE_QA_READY`) are all already `yes`. `release_android.yml` checks only the three repo vars; never invokes the matrix gate script `tool/check_real_device_qa_gate.sh`. So the matrix is doc hygiene, not CI gating.

**Specific question for review:**
1. Is there any *other* path (other workflows, pre-push hooks, the readiness script) where the empty matrix actually blocks something? Read `tool/check_release_readiness.sh` and `.github/workflows/readiness_check.yml` to confirm.

---

## What we want from you (Codex)

**Read each section. For each gap, answer:**
1. Is the proposed verdict (ship-+15 / defer-+16 / partial / doc-only) correct?
2. What did the scoping agent miss?
3. What's the simplest concrete next step (one paragraph)?

**Then a final question:**
- Given current state (3 bugs fixed, App Check re-enabled, debug build verified on device), what's the **minimum viable +15** scope to ship today vs the "right" +15 scope? Argue both sides.

**Output format:**
- Markdown report at `docs/plans/2026-05-16-codex-review-response.md`.
- One section per gap (1–4), one final "MVP vs Right" section.
- Be terse. Cite file:line. No filler, no recap of what we already said.
- Do NOT modify any source files. Read-only. The output doc is the deliverable.

## Files to read (minimum)

- `functions/src/callables/joinGroupByInviteCode.ts`
- `security/firestore.rules` (event light/admin paths, member rename rules, createdBy immutability)
- `lib/core/providers/settings_provider.dart` (propagateDisplayName)
- `lib/features/groups/providers/group_balance_provider.dart` (proof of UID-driven math)
- `lib/features/auth/services/auth_recovery_service.dart` (recovery sequence)
- `lib/features/auth/services/data_deletion_service.dart` (admitted GDPR gap)
- `lib/features/groups/widgets/group_members_section.dart` (dedup site)
- `tool/check_release_readiness.sh`
- `.github/workflows/readiness_check.yml`
- `.github/workflows/release_android.yml`
- Grep for: `participantNames[`, `payerName ?? 'Someone'`, `createdBy` consumers in balance code.

## Out of scope

- Implementing any of these gaps (you're reviewing, not coding).
- Reviewing the already-fixed +14 bugs.
- Auditing test coverage broadly.
- Touching the Stitch design workflow or Memories/Vault/Documents dead code.

## Verification

After writing the response doc, do nothing else. The orchestrator reads your doc, decides what to act on, and may delegate a follow-up implementation task.
