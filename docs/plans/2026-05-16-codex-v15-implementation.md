# Task: Implement v1.2.0+15 scope (Gap 1 + Gap 3 server-safe)

## Context

Rihla v1.2.0+14 is on Play "first" closed-test track. Branch `fix/post-launch-qa-v1.2` (6 commits ahead of main) already contains three +14 bug fixes. Two adjacent gaps were scoped by parallel research agents, then reviewed by you in `docs/plans/2026-05-16-codex-review-response.md`. Your review:

- **Gap 1 (join-doesn't-sync-events): ship in +15.** Simpler than scoping agent proposed.
- **Gap 3 (orphan anon Firebase Auth users): server-safe version only.** The scoping agent's client-side pre-recovery deletion plan was unsafe (data-loss path, rules don't allow it, `createdBy` is functional).

Gap 2 (stale participantNames) defers to +16. Gap 4 (RD-QA matrix) is a separate process decision, not in scope here.

Implement Gap 1 + Gap 3 server-safe per your own review. Conventions in `CLAUDE.md` at repo root (terse, GoRouter declarative, `decimal` for money, `context.colors`/`context.spacing`, no Navigator.push / no goNamed / no state.extra, soft-delete pattern, append-only settlements, `MoneySerializer` only at Firestore boundary, default no comments).

## Branch / commits

- Work on the existing `fix/post-launch-qa-v1.2` branch. Do NOT create a new branch.
- Conventional commits. Keep Gap 1 and Gap 3 as separate commits so they can be reverted independently if needed.

---

## Gap 1: Server-side fan-out in `joinGroupByInviteCode`

### Goal

When a user joins a group via invite code, fan-out their UID + displayName into every non-deleted event's `participantIds` / `participantNames` so they can immediately participate in expenses.

### Files to touch

- `functions/src/callables/joinGroupByInviteCode.ts` — extend the transaction.
- `functions/test/joinGroupByInviteCode.test.ts` (or equivalent existing Jest file) — add cases.
- New: `tool/backfill_join_event_sync.ts` (or `.js`) — one-shot Admin script with `--dry-run`, `--group=<gid>` filter, idempotent writes. Throwaway (NOT a deployed callable).
- Optionally: a Flutter integration test `test/integration/join_then_expense_test.dart` that proves end-to-end.

### Implementation rules (from your own review)

1. **Reads inside the transaction.** Admin SDK supports `tx.get(query)` and locks results. Do all reads (group, member, events query) before any writes.
2. **No batch fallback.** Rihla groups realistically <20 events. Add a defensive `events.size > 400` early-throw if you want, but do not design a second write path.
3. **Idempotent for already-members.** Current callable returns early when `memberIds.includes(uid)` (line 187). Remove that early return path OR run the event fan-out before the early return, so re-joining heals stale state. Re-running must be a no-op if everything is already in sync.
4. **Skip soft-deleted events** (`isDeleted == true`).
5. **`participantNames[uid]`** uses the same normalized `displayName` the callable already validated. Only set if missing or different.
6. **`updatedAt: serverTimestamp()` on each touched event** is fine — events sort by `createdAt` and `EventService.addParticipant` already writes `updatedAt` on participant changes. Keep parity.
7. **No rules changes.** Admin SDK bypasses rules.
8. **`malformedEventData` handling:** if an event doc has a non-array `participantIds` or non-map `participantNames`, throw `failed-precondition` with a clear message and do not write — same shape as `getMemberIds()`.

### Required Jest cases

- New join with 0 events (no event writes).
- New join with N events (each gets UID added + name set).
- Soft-deleted event skipped.
- Already-member re-join heals stale `participantIds` (UID missing from event despite being in `memberIds`).
- Already-member re-join is a no-op when fully in sync (no writes to events).
- Malformed `participantIds` on one event throws and does not partially write others.
- `participantNames[uid]` matches the normalized `displayName` exactly.
- Does NOT touch events in other groups.

### Backfill script (`tool/backfill_join_event_sync.ts`)

- Reads all groups (or one if `--group=<gid>` passed).
- For each group, for each non-deleted event, check whether `event.participantIds` is a subset of `group.memberIds`. If not, log the discrepancy.
- With `--dry-run` (default): print discrepancies only.
- Without `--dry-run` (or with `--commit`): use Admin SDK to fan-out missing UIDs into each event's `participantIds` + `participantNames`, drawing names from `groups/{gid}/members/{uid}.displayName`.
- Idempotent. Re-runnable.
- Logs every write with `groupId`, `eventId`, `addedUids`.
- NOT exported via `functions/src/index.ts`. Lives in `tool/` only.

### Out of scope for Gap 1

- Don't touch the route tree, Riverpod providers, or the join UI.
- Don't rewrite `createdBy` (that's Gap 3 territory if at all).
- Don't add an event-scoped activity log entry on auto-add (separate gap).

---

## Gap 3 server-safe: post-recovery cleanup callable

### Goal

After a successful email-link recovery, clean up orphan anon UID artifacts via a server-side callable. Recovery must succeed regardless of cleanup outcome. Stranded creator/admin status (per your review's `createdBy` finding) is handled by reassigning ownership server-side.

### Files to touch

- New: `functions/src/callables/cleanupAnonUidArtifacts.ts` — Admin callable.
- `functions/src/index.ts` — export the new callable.
- `lib/features/auth/services/auth_recovery_service.dart` — capture the soon-to-be-orphan UID **before** `signOut()`, then call the new callable **after** `signInWithEmailLink` succeeds.
- `lib/core/services/firebase_functions_service.dart` (or wherever callables are invoked) — add the wrapper.
- `functions/test/cleanupAnonUidArtifacts.test.ts` — Jest.
- `test/features/auth/auth_recovery_service_test.dart` — extend.

### Callable contract

**Input:**
```typescript
{
  oldUid: string;   // the anon UID being retired
}
```

**Behavior (Admin SDK, all writes in a single transaction per group):**

1. Verify `request.auth.uid` (the calling UID) exists and is different from `oldUid`.
2. Verify the calling UID is currently linked from email/password or email-link (auth provider check via Admin SDK). Reject if calling UID is still anonymous.
3. For every group where `group.memberIds` contains `oldUid`:
   - **If `group.memberIds` also contains the calling UID:** the "two of me where both UIDs are in memberIds" case. Remove `oldUid` from `memberIds`, delete `members/{oldUid}` doc. Keep the calling UID's member doc as the survivor.
   - **If `group.memberIds` does NOT contain the calling UID:** the recovered user has not yet been re-added. Replace `oldUid` with calling UID in `memberIds`, copy `members/{oldUid}` → `members/{callingUid}` (preserving `joinedAt`, `role`, `isShadow`), delete `members/{oldUid}`. Do this only if `members/{callingUid}` does not already exist; if it does, prefer the existing doc and just delete the orphan.
4. **Reassign `createdBy`** from `oldUid` → calling UID where the old UID was the creator on:
   - `groups/{gid}.createdBy` (if matched).
   - All non-deleted `groups/{gid}/events/{eid}.createdBy`.
   - All non-deleted `groups/{gid}/events/{eid}/expenses/{xid}.createdBy`.
   - **Do NOT** rewrite `createdBy` on `settlements` (append-only audit trail — skip).
5. Update event `participantIds` / `participantNames`: for each event in groups touched above where `participantIds` contains `oldUid`, replace it with calling UID. Carry over the name from `participantNames[oldUid]` to `participantNames[callingUid]`. Delete the `oldUid` key.
6. Delete the anon Firebase Auth user via `admin.auth().deleteUser(oldUid)`. Tolerate `auth/user-not-found` gracefully (already deleted).
7. Delete the orphan `fcm_tokens/{oldUid}` doc if present.
8. Log every write at `info` with `oldUid`, `newUid`, `groupId`, `actions`.
9. On any per-group failure: log at `error` with the group ID, continue with remaining groups. Return summary.

**Output:**
```typescript
{
  groupsProcessed: number;
  groupsFailed: string[];   // group IDs that errored
  authUserDeleted: boolean;
  fcmTokenDeleted: boolean;
}
```

**Rules / safety:**
- Admin SDK only. Do NOT loosen `firestore.rules`.
- `enforceAppCheck: true` to match the rest of the callable surface.
- Per-group transactions (not one giant transaction across all groups) so a single bad group doesn't block the rest.

### Client wiring (`auth_recovery_service.dart`)

Current sequence (per your review):

```
waitForPendingWrites → signOut → signInWithEmailLink → clear pending state
```

New sequence:

```
capture oldUid = currentUser.uid (must be anonymous, capture BEFORE signOut)
waitForPendingWrites
signOut
signInWithEmailLink   // recovery succeeds here; do not block on cleanup
clear pending state
fire-and-forget: callable.cleanupAnonUidArtifacts({ oldUid })
  on success: log
  on failure: log to Sentry breadcrumb, do NOT surface to user, do NOT throw
```

The cleanup callable is non-blocking. Recovery is considered successful as soon as `signInWithEmailLink` returns.

### Required Jest cases

- Calling UID is anonymous → callable rejects (`failed-precondition`).
- Calling UID == oldUid → callable rejects (`invalid-argument`).
- Group where both UIDs are in `memberIds` → oldUid removed, calling UID retained.
- Group where only oldUid is in `memberIds` → replaced with calling UID, member doc copied.
- `createdBy` rewritten on group, event, expense docs where oldUid was creator.
- `createdBy` on settlements is NOT touched (append-only verification).
- Anon Firebase Auth user is deleted (mock `auth().deleteUser`).
- `auth/user-not-found` on Auth delete returns `authUserDeleted: false` without throwing.
- Per-group failure surfaces in `groupsFailed` but other groups still process.
- `fcm_tokens/{oldUid}` deleted if present, no error if absent.

### Required Flutter tests

- `auth_recovery_service_test.dart`: verify cleanup callable is invoked after `signInWithEmailLink` with the captured anon UID.
- Verify recovery completes successfully even if the cleanup callable throws.
- Verify Sentry breadcrumb redaction (no email PII, follow existing pattern in `data_deletion_service.dart`).

### Out of scope for Gap 3

- Don't ship UI dedup in `GroupMembersSection` — your review showed it's the wrong layer (`groupBalancesProvider` also reads the raw stream). The server-side cleanup makes UI dedup unnecessary.
- Don't add the full `auth.user.onDelete()` trigger — that's v1.2.1 work.
- Don't surface the cleanup outcome in any UI.
- Don't migrate settlements.
- Don't loosen any Firestore rules.

---

## Constraints (both gaps)

- Flutter SDK ^3.10.1, Riverpod 2.x without codegen, GoRouter 13.x declarative.
- `decimal` package for money (not double).
- `context.colors` / `context.spacing` / `context.shadows` for styling. No hardcoded `Color(0xFF…)` outside `lib/core/theme/tokens/`.
- No `Navigator.push`, no `state.extra` for required nav data, no `goNamed`.
- Soft-delete pattern. Settlements append-only.
- Comments default to none. Add a comment ONLY when the WHY is non-obvious.
- Do NOT touch `lib/firebase_options.dart`, `pubspec.yaml` version, any CI files, `security/firestore.rules`, or any dropped feature paths (memories/vault/gear/logistics).
- Functions are TypeScript Node 20. Run `npm run build` in `functions/` to type-check.

## Acceptance criteria

- [ ] `flutter analyze` clean.
- [ ] `flutter test` passes (full suite, 1204+ tests, no regressions).
- [ ] `cd functions && npm test` passes (Jest under Java 21 + Firebase emulator).
- [ ] `cd functions && npm run build` succeeds (TypeScript clean).
- [ ] `bash tool/check_theme_purity.sh` clean.
- [ ] New tests cover every "Required Jest cases" and "Required Flutter tests" bullet above.
- [ ] Coverage gate (70%) not regressed.
- [ ] Two distinct commits on `fix/post-launch-qa-v1.2`:
  - `feat(functions): fan-out joiner into existing event participantIds`
  - `feat(auth): server-side cleanup of anon UID artifacts post-recovery`
- [ ] No files written outside the lists above (other than new test files).
- [ ] Backfill script runs clean with `--dry-run` against the emulator with a seeded affected group.

## Verification commands

```bash
# Static + lint
flutter analyze
bash tool/check_theme_purity.sh

# Targeted Flutter tests
flutter test test/features/auth/
flutter test test/integration/

# Functions tests
cd functions && npm run build && npm test
cd ..

# Full Flutter suite as final gate
flutter test

# Dry-run the backfill against emulator (must be running)
node tool/backfill_join_event_sync.js --dry-run
```

## Open questions you may decide

1. Whether `member doc copy` in the cleanup callable should preserve `joinedAt` from the orphan or set it to `serverTimestamp()` (preserving is more faithful but might break sort order — pick one and document it inline).
2. Whether to add a `cleanupAnonUidArtifactsAdmin` parallel callable for support / one-off ops use. Default: NO — keep surface minimal. Add only if you find a reason.
3. Backfill script: prefer TypeScript with `ts-node` invocation, or plain JS? Pick whichever matches existing `tool/` conventions.

Do NOT ask the orchestrator — make a judgment call and proceed.
