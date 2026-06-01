# Spec - #205 soft-delete write locks + deleteGroup quiesce

Issue: #205, follow-up to #190.

## Audit

#190 made group deletion server-authoritative and soft-deletes the group plus events while preserving `memberIds`, event `participantIds`, and append-only money records. That preservation keeps audit reads possible, but it also means stale clients still satisfy the existing rule predicates:

- `validEventCreate` only checks `isGroupMember(groupId)`.
- `validExpenseCreate` and `validEventSettlementCreate` only check `isEventParticipant(groupId, eventId)`.
- `validGroupSettlementCreate`, member writes, and group activity writes only check group membership.
- `deleteGroup` recomputes balances, then later writes `isDeleted:true`; no marker blocks client writes between those phases.
- `joinGroupByInviteCode` uses the Admin SDK, so it bypasses rules and must explicitly reject `deletingInProgress:true` groups during the quiesce window.

## Required Behavior

1. A group with `isDeleted:true` must reject all client writes under `/groups/{gid}` while preserving reads for members.
2. An event with `isDeleted:true` must reject all client writes under that event while preserving reads for group members.
3. `deleteGroup` must quiesce writes before balance recompute by setting a server-only group marker.
4. While the marker is active, client writes under the group must fail even though `isDeleted` is still `false`.
5. If the balance gate fails, the callable must clear the quiesce marker and leave the group active.
6. If the balance gate passes, the callable must finalize `isDeleted:true` and leave a finalized timestamp.

## Design

Use `groups/{gid}.deletingInProgress` as the quiesce marker. The callable sets it with `deleteLockedAt`, `deleteLockedBy`, and `updatedAt` before recomputing balances. Rules treat a group as writable only when:

- `isDeleted` is absent or `false`, and
- `deletingInProgress` is absent or `false`.

Rules treat an event as writable only when the parent group is writable and the event `isDeleted` is absent or `false`.

The callable finalizes by setting `isDeleted:true`, `deletingInProgress:false`, `deleteFinalizedAt`, `deletedAt`, and `updatedAt`. On `FAILED_PRECONDITION`, it clears `deletingInProgress`, `deleteLockedAt`, and `deleteLockedBy` before throwing.

Idempotence: if the creator retries while `deletingInProgress:true`, the callable resumes the delete instead of aborting. During that retry, balance recompute includes events that were already soft-deleted at or after `deleteLockedAt`; this keeps a partially flushed event cascade from making its own group-scope settlement offsets look outstanding.

## Tests

- `functions/test/firestore-rules-publish-readiness.test.ts`
  - soft-deleted group rejects group metadata updates, event creates, member updates, group activity creates, and group settlement creates.
  - soft-deleted event rejects event updates, expense creates, event settlement creates, and event activity creates.
  - `deletingInProgress:true` rejects the same write classes before `isDeleted:true`.
- `functions/test/callables/deleteGroup.test.ts`
  - with a test pause after lock acquisition, `deleteGroup` exposes `deletingInProgress:true` before finalize, then ends with `isDeleted:true` and `deletingInProgress:false`.
  - failed balance gate clears the quiesce marker and keeps `isDeleted:false`.
  - owner retry resumes a quiesced partial finalize and includes events soft-deleted after the lock in the balance fold.
- `functions/test/callables/joinGroupByInviteCode.test.ts`
  - joining a group with `deletingInProgress:true` rejects as `not-found` and performs no member/event fanout writes.
