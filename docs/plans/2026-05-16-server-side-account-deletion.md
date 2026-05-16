# Task: Server-side account deletion cascade

## Context
Rihla v1.2 in-app account deletion is client-side only. `lib/features/auth/services/data_deletion_service.dart:27-56` calls `FirebaseAuth.currentUser.delete()` directly, which trips Firebase's `requires-recent-login` for any user who linked their email more than a few minutes ago — the dominant failure mode in production. The service comment itself flags the server cascade as "follow-up sprint" TODO; `CLAUDE.md` and `AGENTS.md` already document the cascade as if it exists.

Codex reviewed two design questions and locked the following:
1. **Separate callable**, not reusing `cleanupAnonUidArtifacts`. That callable replaces UIDs; deletion removes them. Different semantics.
2. **Scrub identity, keep financial fact** for authored expenses/settlements. Balances are derived from rows — hard-deleting would silently rewrite group history for surviving members. Per-group **tombstone participant IDs** rewrite identity references without breaking math. Google Play permits retention under "shared records" legitimate-interest carve-out, but the privacy/delete-data copy must disclose it.

Reference implementation pattern: `functions/src/callables/cleanupAnonUidArtifacts.ts`.

## Goal
A `deleteAccount` callable that:
- Authenticates via `request.auth.uid` only (never accepts client-supplied UID).
- Synchronously cascades all of the deleted user's PII and identity references across Firestore.
- Deletes FCM token, join-attempt rate-limit doc, and the Auth user record (admin SDK, no recent-login constraint).
- Returns a structured result the client can show to the user.

Client behavior post-callable:
- Wipe local SQLite cache.
- Sign out Firebase Auth.
- Let the router land the user on `/home` (the redirect from `/` already targets `/home`; onboarding is **intentionally not in the route tree** — see `app_router.dart:99-100` and `app_routes.dart` — do not redirect to `/onboarding`). On next app open `_AuthGate` will mint a fresh anonymous UID.
- Drop the `requires-recent-login` branch from `DeletionResult` — admin SDK never produces it.

## Constraints

### Functions (TypeScript)
- Node 20, Firebase admin SDK, existing `onCall` / `enforceAppCheck: true` pattern.
- Use `FieldValue.serverTimestamp()` for any timestamps written.
- Max 500 writes per Firestore batch — chunk if necessary.
- **Tombstone strategy** (revised after codex review): tombstone IS the member doc — do **not** introduce a parallel `tombstones/` subcollection. For each affected group:
  - Generate `tombstoneId = "deleted-<8 char base36 random>"` (per-group, prevents collisions).
  - Write `groups/{gid}/members/{tombstoneId}` with `{ id: tombstoneId, userId: tombstoneId, displayName: "Deleted member", joinedAt: <original member joinedAt or group createdAt/server timestamp fallback>, role: "MEMBER", isTombstone: true }`. **Do not store the original display name anywhere** — that's PII. Do not preserve `CREATOR` on tombstones; creator status moves through the transfer rule below.
  - Delete the original `groups/{gid}/members/{uid}`.
  - Rewrite `groups/{gid}.memberIds`: replace UID with tombstoneId (not remove). This keeps `groupMembersProvider` returning the participant so `groupBalancesProvider` (`group_balance_provider.dart:122-186` — builds participant list **only** from `groupMembersProvider`) still includes them in balance math.
- **Group creator transfer**: if `group.createdBy == uid`, transfer to the oldest remaining **non-tombstone, non-deleted** member (`joinedAt` ascending in `members/`). If no real member remains, the group has no surviving members → group gets soft-deleted (see orphan handling below) and `createdBy` becomes `deleted-user`.
- `deleted-user` (literal string) is the sentinel for `createdBy` fields on expenses, settlements, and orphaned groups.
- For per-event iteration: visit **all** events (including soft-deleted) so PII is fully scrubbed. `cleanupAnonUidArtifacts` skipped soft-deleted events because identity preservation didn't matter for migration; deletion needs the opposite.
- For expenses and settlements: scrub identity regardless of `isDeleted` state — PII must go.
- **Receipt objects in Storage**: out of scope. `expense.receiptUrl` is plumbed in the model and `expense_service.dart` but no Storage upload flow has shipped (`ocr_service.dart:33-41` confirms receipts are "temporarily unavailable"). Nulling the field is sufficient for forward compatibility. If/when receipts ship, a separate Storage cleanup pass must be added — flag in the callable's header comment.
- Idempotent: re-running on a UID that's already been processed (no longer in any `memberIds`) is a no-op that returns `{ groupsProcessed: 0, ... }`.
- Order: Firestore cascade first, FCM/joinAttempts next, `getAuth().deleteUser()` LAST. If Auth delete fails after Firestore cascade succeeds, return a structured error with all completed steps for audit — do not crash.

### Flutter
- `DataDeletionService.deleteAccount()` calls the new callable via the existing `FirebaseFunctionsService` (already injected into `AuthRecoveryService` — follow that pattern).
- New `DeletionResult` enum: `ok`, `noUser`, `error`. Drop `requiresRecentLogin`.
- On `ok`: call `LocalDatabase.wipeAndReinitialize()` (the same cache-clearing path used by `UidChangeListener`), call `FirebaseAuth.signOut()`, then let GoRouter land the user on `/home`. Do not redirect to `/onboarding`; onboarding is not in the current route tree.
- Dialog copy in `delete_account_dialog.dart` stays as-is. The cascade is real now, so "permanent" is accurate.

### Docs
- Update `data_deletion_service.dart` header comment — drop the "follow-up sprint" TODO, point at the callable.
- `AGENTS.md` line ~162 — codex flagged this as a stale claim. Update to reflect what now exists.
- `CLAUDE.md` "Key Invariants" already accurate; just leave it.
- `/delete-data` legal page text — if the page exists in repo, update the disclosure to mention tombstoning. If only hosted externally, note this as a follow-up TODO in the PR description.

## Files to touch

### Cloud Functions
- `functions/src/callables/deleteAccount.ts` — new callable
- `functions/src/index.ts` — export `deleteAccount`
- `functions/test/callables/deleteAccount.test.ts` — new Jest suite, mirror style of `functions/test/callables/cleanupAnonUidArtifacts.test.ts` (note: tests live under `functions/test/`, **not** `functions/src/.../__tests__/`)

### Flutter (lib)
- `lib/features/auth/services/data_deletion_service.dart` — rewrite to call callable
- `lib/features/settings/screens/profile_screen.dart` — `_deleteAccount` method, snack/result handling
- `lib/features/groups/models/group_member_model.dart` — read `isTombstone` from Firestore member docs so UI can distinguish deleted-member tombstones
- `lib/features/groups/widgets/group_members_section.dart` — do not show remove controls for tombstone members
- `lib/features/auth/widgets/delete_account_dialog.dart` — verify; no copy change expected

### Flutter (test)
- `test/unit/data_deletion_service_test.dart` — update existing suite for callable wiring + post-success cache/auth handling
- `test/features/auth/delete_account_tile_test.dart` — update snack/result handling after `requiresRecentLogin` is removed
- `test/features/groups/group_settings_screen_test.dart` — assert tombstone members cannot be removed from the members list

### Docs
- `AGENTS.md` — line ~162 stale claim
- `data_deletion_service.dart` header — drop the TODO comment

## Files NOT to touch
- `pubspec.yaml` — no version bump in this PR
- `lib/firebase_options.dart` — autogenerated
- `security/firestore.rules` — admin SDK bypasses rules; no rule change needed
- `functions/src/callables/cleanupAnonUidArtifacts.ts` — reference only; extract a shared helper only if the duplication is glaring (don't refactor for its own sake)
- `lib/features/auth/services/auth_recovery_service.dart` — unrelated flow
- Any Memories/Vault/Documents/Gear/Logistics code (dropped features per `CLAUDE.md`)
- Goldens — UI doesn't change visually

## Acceptance criteria

### Callable shape and auth
- [ ] `deleteAccount` callable defined with `{ enforceAppCheck: true }`
- [ ] Returns `unauthenticated` HttpsError if `request.auth` is missing
- [ ] Does not accept any input parameters — UID comes from `request.auth.uid`
- [ ] Returns:
  ```ts
  {
    groupsProcessed: number,
    tombstoneIds: string[],          // per-group tombstone IDs, for audit
    expensesScrubbed: number,
    settlementsScrubbed: number,
    activityLogsScrubbed: number,
    membersDeleted: number,
    groupsOrphanedAndSoftDeleted: number,
    fcmTokenDeleted: boolean,
    joinAttemptsDeleted: boolean,
    authUserDeleted: boolean,
  }
  ```

### Per-group cascade
For each group where the deleted user appears in `memberIds`:
- [ ] Generate per-group `tombstoneId = "deleted-<8 char base36>"`
- [ ] Write tombstone member doc at `groups/{gid}/members/{tombstoneId}` with `{ id: tombstoneId, userId: tombstoneId, displayName: "Deleted member", joinedAt: <original joinedAt or safe fallback>, role: "MEMBER", isTombstone: true }` — no original-name retention, and no `CREATOR` role on tombstones
- [ ] Hard-delete the original `groups/{gid}/members/{uid}`
- [ ] Rewrite `groups/{gid}.memberIds`: replace UID with tombstoneId (preserves participant for `groupMembersProvider` → `groupBalancesProvider` chain)
- [ ] Client model reads `isTombstone: true` on the tombstone member, and group settings never exposes member-remove controls for tombstones. Removing a tombstone later would break historical balance math.
- [ ] **Creator transfer**: if `group.createdBy == uid`, find the oldest remaining `members/` doc with `isTombstone != true` and `userId != uid`, set `group.createdBy = thatUser.userId`. If no such member exists, set `group.createdBy = "deleted-user"` and proceed to orphan handling.
- [ ] **Orphan handling**: if the only non-tombstone members are zero (i.e., every remaining member is a tombstone or the group is fully empty), soft-delete the group (`isDeleted: true, deletedAt: serverTimestamp()`). Increment `groupsOrphanedAndSoftDeleted`.

### Per-event cascade (all events, including soft-deleted, in the group)
- [ ] `event.participantIds[]`: replace UID with tombstoneId
- [ ] `event.participantNames{}`: delete UID key, add tombstoneId key with value "Deleted member"
- [ ] If `event.createdBy == uid` → rewrite to `deleted-user`

### Per-expense cascade (all expenses, including soft-deleted, across all events in the group)
- [ ] `expense.createdBy == uid` → `deleted-user`
- [ ] `expense.payerParticipantId == uid` → tombstoneId
- [ ] `expense.customSplitParticipants[]`: replace UID entries with tombstoneId
- [ ] `expense.splitDistribution{}`: rename UID key to tombstoneId, preserve numeric value
- [ ] `expense.receiptUrl` → null (Storage object cleanup is out of scope per Constraints — no shipped upload flow today)
- [ ] `expense.note` → null
- [ ] `expense.description` → null (free-text field, treated as user PII)
- [ ] Increment `expensesScrubbed` counter for each touched row

### Per-settlement cascade (group-scope + event-scope, all states)
- [ ] `settlement.createdBy == uid` → `deleted-user`
- [ ] `settlement.payerParticipantId == uid` → tombstoneId
- [ ] `settlement.recipientParticipantId == uid` → tombstoneId
- [ ] If payer or recipient matched the deleted UID, rewrite the corresponding `payerName` / `recipientName` to "Deleted member"
- [ ] If the deleted UID created, paid, or received the settlement, set `settlement.note` → null because it is free text
- [ ] Increment `settlementsScrubbed` counter

### Per-activity-log cascade (group-scope + event-scope)
Scrub both activity paths: group activity at `groups/{gid}/activity/{activityId}` and event activity at `groups/{gid}/events/{eid}/activity_logs/{activityId}`.

- [ ] `activityLog.actorId == uid` → tombstoneId
- [ ] `activityLog.targetParticipantId == uid` → tombstoneId where that field exists on event activity logs
- [ ] `activityLog.actorName` → "Deleted member" (only when actorId matched)
- [ ] Group activity `description` and event activity `logText`: replace any in-memory original display-name occurrence with "Deleted member"; if the actor matched and the string cannot be safely rewritten, replace with a generic non-PII phrase such as "Deleted member activity".
- [ ] Activity `metadata`: replace string values exactly equal to uid with tombstoneId, and rewrite known user-facing name keys for the deleted user (for example `actorName`, `payerName`, `recipientName`) to "Deleted member".
- [ ] Increment `activityLogsScrubbed` counter

### Global cleanup
- [ ] `fcm_tokens/{uid}` deleted if exists; `fcmTokenDeleted` reflects whether a doc was actually removed
- [ ] `joinAttempts/{uid}` deleted if exists; `joinAttemptsDeleted` reflects same
- [ ] `getAuth().deleteUser(uid)` called LAST; `authUserDeleted: true` on success
- [ ] If Firestore cascade succeeds but Auth delete throws, return a `HttpsError('internal', ...)` with a clear message — partial completion logged

### Client wiring
- [ ] `DataDeletionService.deleteAccount()` invokes the callable
- [ ] On `ok`: wipes local SQLite (existing path via `UidChangeListener` or equivalent), signs out Auth, GoRouter lands user on `/home` (`/onboarding` is **not** a route — do not redirect there; the splash redirect already targets `/home` and `_AuthGate` mints a fresh anon UID on next launch)
- [ ] On `error` / `noUser`: shows the existing `ScaffoldMessenger` snack
- [ ] No `requires-recent-login` code path remains anywhere in `data_deletion_service.dart` or `profile_screen.dart`

### Tests
- [ ] Jest: happy path — user is creator of group A (other members exist), sole member of group B; user is payer on one expense, in custom split of another, recipient of one settlement, actor of two activity logs. Assert tombstone member doc written at `groups/{gid}/members/{tombstoneId}`, `memberIds` array contains tombstoneId, all references rewritten, group B soft-deleted, expense receiptUrl/note/description nulled, settlement payer/recipient display names scrubbed, and activity `actorName`/`description`/`logText`/metadata no longer retain the original display name or UID.
- [ ] Jest: **balance preservation** — after deletion, `groups/{gid}/members/{tombstoneId}` exists with `isTombstone: true` and `displayName: "Deleted member"`. The original member doc is gone. (This is the contract that keeps `groupMembersProvider` → `groupBalancesProvider` working.)
- [ ] Jest: **creator transfer** — if deleted user is `group.createdBy` and other real members exist, `group.createdBy` is reassigned to the oldest non-tombstone remaining member (by `joinedAt`). If no real members remain, `group.createdBy == "deleted-user"` AND group is soft-deleted.
- [ ] Jest: idempotent — running twice produces `groupsProcessed: 0` on second call.
- [ ] Jest: missing auth → `unauthenticated` rejection.
- [ ] Jest: missing App Check (if testable in current emulator setup) → rejection.
- [ ] Jest: soft-deleted expense still has PII (createdBy, payer, splits, receiptUrl, note, description) scrubbed.
- [ ] Jest: no-op when user has no groups (still deletes FCM/joinAttempts/Auth user).
- [ ] Flutter: `test/unit/data_deletion_service_test.dart` verifies callable invocation, success branch wipes cache + signs out, error branch surfaces error result.
- [ ] Flutter: `test/features/auth/delete_account_tile_test.dart` verifies profile snack/result handling with no `requiresRecentLogin` branch.
- [ ] Flutter: `test/features/groups/group_settings_screen_test.dart` verifies tombstone members render as deleted members and have no remove button.
- [ ] `flutter analyze` clean.
- [ ] `flutter test` full suite passes — coverage stays ≥ 70% (current gate).
- [ ] `npm --prefix functions run test:emulator` passes.

## Verification commands

```bash
npm --prefix functions run build
npm --prefix functions run test:emulator
flutter analyze
flutter test
RIHLA_CONFIRM_APP_CHECK_READY=yes bash tool/check_release_readiness.sh
```

`test:emulator` is the right script — `npm test` runs raw Jest without the Firestore/Auth emulator, which the callable's Admin SDK writes require.

## Out of scope
- Pubspec version bump and release tag — separate commit after merge.
- Refactoring `cleanupAnonUidArtifacts` — codex explicitly recommended keeping them separate. Only extract a shared helper if duplication is screaming; otherwise don't.
- Adding a `/delete-data` web page if none exists in repo. If the page is hosted externally (Vercel, Firebase Hosting), note as a follow-up TODO in the PR body but don't block on it.
- A queue/job for partial cascade resume — Rihla scale doesn't need it. Note as a future scaling concern in the callable header comment.
- Re-architecting `AuthRecoveryService`.
- iOS-specific work (iOS launch is soft-deferred).
- Any UI redesign of the delete-account dialog.
