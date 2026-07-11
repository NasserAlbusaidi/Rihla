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
// Error-code contract: lock contention and a lost/reaped lock throw
// `aborted`, NEVER `failed-precondition` — the client maps any
// failed-precondition from these callables to the "settle up before leaving"
// snackbar (group_danger_section.dart / group_members_section.dart), so a
// square user losing a lock race would be told they owe money.

export interface DepartureLock {
  lockedAtMs: number;
  lockedBy: string;
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
    // Same four-flag quiesce honor as the callers' pre-checks (Admin SDK
    // bypasses rules): soft-deleted or otherwise-locked groups are
    // indistinguishable from missing groups on this path.
    if (
      group.isDeleted === true
      || group.deletingInProgress === true
      || group.claimingInProgress === true
      || group.accountDeletionInProgress === true
    ) {
      throw new HttpsError('not-found', 'Group not found.');
    }
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
