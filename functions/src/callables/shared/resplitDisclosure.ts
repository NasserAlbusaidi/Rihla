import { createHash } from 'crypto';
import { DocumentData, DocumentReference, Firestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { expenseSplitsOverUniverse } from '../groupNetBalance';

// #1059 stage 2 — roster-change re-split disclosure.
//
// Fanning a member into an event's participantIds silently re-divides every
// live expense that equal-splits over the participant universe at read time
// (global / legacy sub_group / custom-with-empty-list scope, no stored
// distribution). Both fan-in callables (joinGroupByInviteCode, addShadowMember)
// call detectResplitEvents AFTER their membership transaction commits and, when
// ≥1 fanned-in event actually re-splits, write ONE `member_resplit` row to
// groups/{gid}/activity.
//
// Deliberate properties:
//  - POST-commit, lock-free: the row is not an oracle input (recomputeNet never
//    reads activity), so no quiesce flag applies. Only failure mode is a LOST
//    row — never a fabricated one (membership is already committed).
//  - Occasion-keyed deterministic id: resplit_<memberId>_<sha256(sorted
//    affected event ids)[:12]>. Distinct disclosure occasions (e.g. a rejoin
//    fanned into events created during the departure window) get distinct
//    rows; a raced duplicate of the SAME occasion dedups via .create().
//  - description is a PREDICATE — every feed surface renders one paragraph as
//    `actorName + ' ' + description` (activity_row.dart), and it is the
//    old-client fallback text (new clients localize from metadata).

export interface FanInEventCapture {
  ref: DocumentReference;
  eventId: string;
  eventName: string;
}

export interface ResplitDetection {
  count: number;
  /** Sorted — feeds the occasion hash. */
  affectedEventIds: string[];
  /** Non-null iff count == 1 AND the event name is a non-empty string —
   * eventId/eventName metadata and the single-event copy travel together so
   * text and tap target can never disagree. */
  single: { eventId: string; eventName: string } | null;
}

export async function detectResplitEvents(
  events: FanInEventCapture[],
): Promise<ResplitDetection> {
  const flags = await Promise.all(
    events.map(async (ev) => {
      const snap = await ev.ref
        .collection('expenses')
        .where('isDeleted', '==', false)
        .select('splitMode', 'splitDistribution', 'scope', 'customSplitParticipants', 'payerParticipantId')
        .get();
      return snap.docs.some((d) => expenseSplitsOverUniverse(d.data() as DocumentData));
    }),
  );
  const affected = events.filter((_, i) => flags[i]);
  const one = affected.length === 1 ? affected[0] : null;
  return {
    count: affected.length,
    affectedEventIds: affected.map((ev) => ev.eventId).sort(),
    single:
      one != null && one.eventName.length > 0
        ? { eventId: one.eventId, eventName: one.eventName }
        : null,
  };
}

export interface ResplitActivityArgs {
  memberId: string;
  memberName: string;
  actorId: string;
  actorName: string;
  memberAction: 'added' | 'joined';
  detection: ResplitDetection;
}

export async function writeResplitActivity(
  db: Firestore,
  groupId: string,
  args: ResplitActivityArgs,
): Promise<void> {
  const { count, single, affectedEventIds } = args.detection;
  if (count === 0) return;
  const occHash = createHash('sha256')
    .update(affectedEventIds.join(','))
    .digest('hex')
    .slice(0, 12);
  const activityId = `resplit_${args.memberId}_${occHash}`;
  // The count variant can fire with count == 1 when the sole event's name is
  // malformed (legacy/Admin docs only) — keep the grammar honest.
  const eventsPhrase = count === 1 ? '1 event' : `${count} events`;
  const description =
    args.memberAction === 'joined'
      ? single != null
        ? `joined ${single.eventName} — equal splits recalculated`
        : `joined ${eventsPhrase} — equal splits recalculated`
      : single != null
        ? `added ${args.memberName} to ${single.eventName} — equal splits recalculated`
        : `added ${args.memberName} to ${eventsPhrase} — equal splits recalculated`;
  try {
    await db
      .collection('groups')
      .doc(groupId)
      .collection('activity')
      .doc(activityId)
      .create({
        id: activityId,
        type: 'member_resplit',
        actorId: args.actorId,
        actorName: args.actorName,
        description,
        metadata: {
          memberAction: args.memberAction,
          memberName: args.memberName,
          affectedEventCount: count,
          ...(single != null ? { eventId: single.eventId, eventName: single.eventName } : {}),
        },
        // ISO STRING ONLY (#1140): every reader orders by this client string;
        // a Firestore Timestamp type-buckets apart in orderBy.
        timestamp: new Date().toISOString(),
      });
  } catch (error) {
    // Post-commit cosmetic row: a failure (incl. already-exists on a raced
    // duplicate of the SAME occasion) must never surface as a join/add
    // failure — the lost-row degrade IS the pre-#1059 status quo for that
    // one occurrence.
    logger.warn('resplit activity row not written', {
      groupId,
      memberId: args.memberId,
      error: String(error),
    });
  }
}
