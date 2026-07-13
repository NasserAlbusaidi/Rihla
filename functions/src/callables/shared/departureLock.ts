import { FieldValue, Timestamp } from 'firebase-admin/firestore';
import type { DocumentReference, Firestore } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';

// Deliberately NOT groupNetBalance.timestampMillis: several callable tests
// jest.mock that whole module (memberRemovalDeleteLockRace.test.ts stubs it
// to `{ recomputeNet }` only), which would leave an import from it undefined
// here. The lock fields are always Admin-SDK-written Timestamps, so a local
// instanceof suffices.
function lockedAtMillis(value: unknown): number | null {
  return value instanceof Timestamp ? value.toMillis() : null;
}

// #1144: the departure fence. leaveGroup/removeMember previously ran their
// recomputeNet zero-check with NO lock held, so any balance-input write
// committing between the recompute and the membership transaction departed a
// member at non-zero. The fence mirrors deleteGroup's lock discipline
// (deleteGroup.ts acquireDeleteGroupLock / clearDeleteGroupLockForFailure):
// acquire transactionally → recompute UNDER the lock (rules'
// groupAllowsClientWrites freezes client writes; every oracle-input Admin
// writer honors the flag inside its own write transaction) → mutate and clear
// in ONE final transaction that first verifies the lock is still ours.
//
// Error-code contract (#1144 + #1209/#1211) — leaveGroup / removeMember /
// deleteGroup surface a freeze under exactly three codes, and the client maps
// each to a distinct outcome (group_danger_section.dart /
// group_members_section.dart):
//   - not-found → the group is GONE (isDeleted, or a delete in flight that ends
//     in gone) → client goes home ("nothing to do").
//   - aborted → a TRANSIENT freeze: departure-lock contention, a lost/reaped
//     lock, OR a bounded concurrent claim / account-deletion after which the
//     group survives and the caller stays a member → client shows the retry
//     copy (groupMembershipChangeInProgress), no Sentry.
//   - failed-precondition → a REAL precondition (unsettled balance, #1144 R1
//     universe-only) → client shows the "settle up before leaving/deleting"
//     snackbar.
// NEVER throw failed-precondition for a transient freeze or a lock race: a
// square user would be told they owe money. NEVER throw not-found for a
// transient claim/account-deletion freeze: the leaver would be told they left
// while they are still a member (#1211).

export interface DepartureLock {
  lockedAtMs: number;
  lockedBy: string;
}

// #1209/#1211: the shared terminal-vs-transient quiesce classifier. leaveGroup /
// removeMember (pre-check AND in-tx re-check) and acquireDepartureLock below all
// make the SAME not-found/aborted decision — this puts it in ONE place instead
// of triplicating it, and makes the (single-threaded-emulator-unreachable) in-tx
// re-check a thin `if (freeze) throw freeze` dispatch over a unit-tested helper.
// Returns the HttpsError to throw, or null when the group is writable on this
// axis. Deliberately does NOT classify `departureInProgress`: that flag is the
// departure-lock CONTENTION signal (its own message, thrown separately in
// acquireDepartureLock) and is folded into deleteGroup's own transient check —
// both evaluated AFTER this classifier.
//   - isDeleted / deletingInProgress → TERMINAL (group gone / ending gone) →
//     not-found (client goes home).
//   - claimingInProgress / accountDeletionInProgress → TRANSIENT (bounded op,
//     group survives, caller still a member) → aborted (client retry copy).
export function quiesceFreezeError(
  group: Record<string, unknown>,
): HttpsError | null {
  if (group.isDeleted === true || group.deletingInProgress === true) {
    return new HttpsError('not-found', 'Group not found.');
  }
  if (
    group.claimingInProgress === true
    || group.accountDeletionInProgress === true
  ) {
    return new HttpsError(
      'aborted',
      'Another operation is in progress. Try again.',
    );
  }
  return null;
}

export async function acquireDepartureLock(
  db: Firestore,
  groupRef: DocumentReference,
  uid: string,
): Promise<DepartureLock> {
  return db.runTransaction(async (tx) => {
    const groupSnap = await tx.get(groupRef);
    if (!groupSnap.exists) {
      throw new HttpsError('not-found', 'Group not found.');
    }
    const group = groupSnap.data() ?? {};
    // #1211: terminal (not-found) vs transient (aborted) freeze via the shared
    // classifier (Admin SDK bypasses rules, so this honors the same write-lock
    // as firestore.rules). Normally shielded by the callers' pre-checks; kept
    // here so the shared lock enforces the contract on any future caller.
    const freeze = quiesceFreezeError(group);
    if (freeze) throw freeze;
    if (group.departureInProgress === true) {
      throw new HttpsError(
        'aborted',
        'Another membership change is in progress. Try again.',
      );
    }
    const now = Timestamp.now();
    tx.update(groupRef, {
      departureInProgress: true,
      departureLockedAt: now,
      departureLockedBy: uid,
      updatedAt: now,
    });
    return { lockedAtMs: now.toMillis(), lockedBy: uid };
  });
}

// Verifies (inside the caller's transaction) that the lock is still OURS —
// the reaper may have reclaimed a stale lock mid-flight, after which the
// recompute basis can no longer be trusted.
export function assertDepartureLockHeld(
  group: Record<string, unknown>,
  lock: DepartureLock,
): void {
  if (
    group.departureInProgress !== true
    || group.departureLockedBy !== lock.lockedBy
    || lockedAtMillis(group.departureLockedAt) !== lock.lockedAtMs
  ) {
    throw new HttpsError(
      'aborted',
      'The membership change lock was lost. Try again.',
    );
  }
}

// Field map that releases the lock; spread into the same tx.update that
// commits the membership mutation so release is atomic with it.
export function departureLockClearFields(): Record<string, unknown> {
  return {
    departureInProgress: false,
    departureLockedAt: FieldValue.delete(),
    departureLockedBy: FieldValue.delete(),
  };
}

// Failure-path release: only the invocation that created the lock may clear
// it (mirrors clearDeleteGroupLockForFailure — clearing a peer's live lock
// would re-open client writes mid-departure). Stale locks from a dead
// invocation are reclaimed by departureLockReaper, never by an in-band
// observer. Best-effort: a clear that itself fails leaves the reaper as the
// backstop.
export async function clearDepartureLockForFailure(
  groupRef: DocumentReference,
  lock: DepartureLock,
): Promise<void> {
  await groupRef.firestore.runTransaction(async (tx) => {
    const groupSnap = await tx.get(groupRef);
    const group = groupSnap.data() ?? {};
    if (
      group.departureInProgress !== true
      || group.departureLockedBy !== lock.lockedBy
      || lockedAtMillis(group.departureLockedAt) !== lock.lockedAtMs
    ) {
      return;
    }
    tx.update(groupRef, departureLockClearFields());
  });
}
