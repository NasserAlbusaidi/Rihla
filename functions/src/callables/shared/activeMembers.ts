import type {
  DocumentData,
  DocumentReference,
  Transaction,
} from 'firebase-admin/firestore';

// #1144 R5: `activeMemberIds` = memberIds MINUS deleteAccount tombstone ids
// (shadow uuids stay in — shadows are legitimate expense parties). Rules gate
// every CREATE-side money/roster surface on it, falling back to memberIds
// when the field is absent (legacy groups). Every roster writer maintains it
// through THIS helper so the semantics can't drift per-writer.
//
// Self-heal: a legacy group (field absent) is seeded from
// `memberIds − tombstone member-doc userIds` on its first roster write —
// no migration script; new groups carry the field from create
// (group_provider.dart + validGroupCreate equality).
//
// NEVER FieldValue.arrayUnion/arrayRemove this field: a FieldValue op on an
// ABSENT field creates it as a one-element (or empty) array, which on a
// legacy group would instantly freeze every other member out of the expense
// gates. Always write the fully-computed array returned here.
//
// Ordering: the absent-field branch issues a tx READ (tombstone query), so
// callers MUST invoke this before their first tx write (Firestore
// reads-before-writes) — put it with the other reads at the top of the tx.

export type ActiveMembersOp =
  | { add: string }
  | { remove: string }
  | { replace: { from: string; to: string } };

export async function nextActiveMemberIds(
  tx: Transaction,
  groupRef: DocumentReference,
  groupData: DocumentData,
  op: ActiveMembersOp,
): Promise<string[]> {
  let base: string[];
  if (Array.isArray(groupData.activeMemberIds)) {
    base = groupData.activeMemberIds.filter(
      (v): v is string => typeof v === 'string',
    );
  } else {
    const memberIds: string[] = Array.isArray(groupData.memberIds)
      ? groupData.memberIds.filter((v): v is string => typeof v === 'string')
      : [];
    const tombstonesSnap = await tx.get(
      groupRef.collection('members').where('isTombstone', '==', true),
    );
    const tombstoneIds = new Set(
      tombstonesSnap.docs
        .map((d) => d.data().userId)
        .filter((v): v is string => typeof v === 'string'),
    );
    base = memberIds.filter((id) => !tombstoneIds.has(id));
  }

  if ('add' in op) {
    return base.includes(op.add) ? base : [...base, op.add];
  }
  if ('remove' in op) {
    return base.filter((id) => id !== op.remove);
  }
  // replace (claim re-key): dedup in case the target uid is somehow already
  // present — the field is a set by contract.
  return [
    ...new Set(base.map((id) => (id === op.replace.from ? op.replace.to : id))),
  ];
}
