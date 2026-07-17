import { getFirestore, FieldValue, DocumentData } from 'firebase-admin/firestore';
import { onCall, HttpsError, CallableRequest } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions/v2';
import { randomUUID } from 'crypto';
import '../admin';
import { normalizeRequiredDisplayName } from './shared/displayName';
import { MAX_FAN_IN_EVENTS, applyEventFanIn, collectEventFanIn } from './shared/eventFanIn';
import { nextActiveMemberIds } from './shared/activeMembers';
import { MAX_GROUP_MEMBERS } from './shared/groupLimits';
import { isCurrentMember } from './shared/membership';
import {
  FanInEventCapture,
  detectResplitEvents,
  writeResplitActivity,
} from './shared/resplitDisclosure';

export interface AddShadowMemberInput {
  groupId: string;
  displayName: string;
}

export interface AddShadowMemberOutput {
  memberId: string;
}

// #1282: MAX_GROUP_MEMBERS is shared with joinGroupByInviteCode (one basis,
// no drift between the two roster-growth paths — see shared/groupLimits.ts).
// App Check + the creator-only gate below are the abuse-posture controls
// (#197 — do NOT add per-IP throttling).

function normalizeGroupId(groupId: unknown): string {
  if (typeof groupId !== 'string' || groupId.length === 0 || groupId.includes('/')) {
    throw new HttpsError('invalid-argument', 'groupId must be a valid id.');
  }
  return groupId;
}

function getMemberIds(groupData: DocumentData): string[] {
  const memberIds = groupData.memberIds;
  if (!Array.isArray(memberIds) || memberIds.some((m) => typeof m !== 'string')) {
    throw new HttpsError('failed-precondition', 'Group membership data is malformed.');
  }
  return memberIds;
}

// #278: add a placeholder ("shadow") member by name. A shadow has NO real auth
// uid — its id/userId is a freshly-minted uuid — so a brand-new group is usable
// on the first session (split against it immediately, cash-settle it). Creating
// it requires the Admin SDK because (a) memberIds is server-authoritative
// (firestore.rules:308) and (b) #524 binds a client-created member doc's id to
// the caller's auth.uid (rules:782-783), which a placeholder can never satisfy.
export const addShadowMember = onCall<AddShadowMemberInput, Promise<AddShadowMemberOutput>>(
  { enforceAppCheck: true },
  async (request: CallableRequest<AddShadowMemberInput>) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign-in required.');
    }
    // D6-R (2026-07-06): anonymous creators MAY add shadows — the sandbox is
    // solo until a real account joins. Joining is itself anon-legal (#648 —
    // see joinGroupByInviteCode), so the durable boundary is the CLAIM chain:
    // requestClaimShadow / decideClaimRequest both reject anonymous actors.
    // Abuse posture: enforceAppCheck + the creator-only check below + MAX_GROUP_MEMBERS.
    const uid = request.auth.uid;
    const groupId = normalizeGroupId(request.data?.groupId);
    const displayName = normalizeRequiredDisplayName(request.data?.displayName);
    const db = getFirestore();
    const groupRef = db.doc(`groups/${groupId}`);

    // #1059: captured INSIDE the tx (last-run-wins on retry, the join
    // callable's didJoin pattern) so the post-commit disclosure can see which
    // events the fan-in actually grew and who the acting creator is.
    let fanInCaptures: FanInEventCapture[] = [];
    let creatorName = 'Someone';

    const memberId = await db.runTransaction(async (tx) => {
      const groupSnap = await tx.get(groupRef);
      if (!groupSnap.exists) {
        throw new HttpsError('not-found', 'Group not found.');
      }
      const groupData = groupSnap.data() ?? {};
      // Honor the same write-lock as firestore.rules (the Admin SDK bypasses
      // rules), mirroring joinGroupByInviteCode:286.
      if (
        groupData.isDeleted === true
        || groupData.deletingInProgress === true
        || groupData.claimingInProgress === true
        || groupData.accountDeletionInProgress === true
        // #1144: shadow fan-in writes event participantIds (an oracle input).
        || groupData.departureInProgress === true
      ) {
        throw new HttpsError('not-found', 'Group not found.');
      }
      // #1132: createdBy alone is membership-blind — a departed creator must not
      // retain add-by-name authority.
      if (groupData.createdBy !== uid || !isCurrentMember(groupData, uid)) {
        throw new HttpsError(
          'permission-denied',
          'Only the group creator can add members by name.',
        );
      }

      const memberIds = getMemberIds(groupData);
      if (memberIds.length >= MAX_GROUP_MEMBERS) {
        throw new HttpsError(
          'failed-precondition',
          'This group has reached the maximum number of members.',
        );
      }

      // #279 collision: a shadow name must be unique (case-insensitive, trimmed)
      // across ALL member docs (real + shadow) — duplicate names make roster +
      // settle-up attribution ambiguous, and keeping names unique now keeps the
      // future claim picker unambiguous. Compared by the displayName FIELD.
      const membersSnap = await tx.get(groupRef.collection('members'));
      // #245: the shadow is fanned into every live event below (same contract
      // as joinGroupByInviteCode), so the event count bounds this tx's writes.
      const eventsSnap = await tx.get(groupRef.collection('events'));
      if (eventsSnap.size > MAX_FAN_IN_EVENTS) {
        throw new HttpsError(
          'failed-precondition',
          'Group has too many events to add a member safely.',
        );
      }
      const candidate = displayName.toLowerCase();
      const collides = membersSnap.docs.some((doc) => {
        const existing = doc.get('displayName');
        return typeof existing === 'string' && existing.trim().toLowerCase() === candidate;
      });
      if (collides) {
        throw new HttpsError(
          'already-exists',
          'That name is already taken in this group. Please choose a different name.',
        );
      }

      // The placeholder uuid is BOTH the doc id and the userId (the balance
      // oracle keys on userId). Same 6 fields joinGroupByInviteCode writes
      // (:375-384), with isShadow:true. isTombstone is omitted (defaults false in
      // GroupMember.fromDoc), matching the join write.
      const newId = randomUUID();
      // #1144 R5: shadows ARE active parties — the uuid joins both sets. Must
      // run before the tx writes below (reads-before-writes on the legacy
      // self-heal branch).
      const activeMemberIds = await nextActiveMemberIds(tx, groupRef, groupData, {
        add: newId,
      });
      tx.set(groupRef.collection('members').doc(newId), {
        id: newId,
        userId: newId,
        displayName,
        role: 'MEMBER',
        joinedAt: FieldValue.serverTimestamp(),
        isShadow: true,
      });
      tx.update(groupRef, {
        memberIds: FieldValue.arrayUnion(newId),
        activeMemberIds,
        updatedAt: FieldValue.serverTimestamp(),
      });
      // #245: mirror the join callable — a member absent from an event's
      // participantIds can never be split against there (the expense editor
      // rosters event.participantIds and no client path grows it).
      const fanIn = collectEventFanIn(eventsSnap, newId, displayName);
      // #1059: only updates that GROW participantIds can re-split; a malformed
      // event name maps to '' (forces the count copy, no deep-link metadata).
      const eventNamesById = new Map<string, string>(
        eventsSnap.docs.map((eventSnap) => {
          const name = eventSnap.get('name');
          return [eventSnap.id, typeof name === 'string' ? name.trim() : ''];
        }),
      );
      fanInCaptures = fanIn
        .filter((update) => update.addParticipantId)
        .map((update) => ({
          ref: update.ref,
          eventId: update.ref.id,
          eventName: eventNamesById.get(update.ref.id) ?? '',
        }));
      // #1059 actor: the creator's roster displayName, matched by the userId
      // FIELD (member-doc keying is MIXED — recordSettlement idiom).
      const creatorDoc = membersSnap.docs.find((doc) => doc.get('userId') === uid);
      const rawCreatorName = creatorDoc?.get('displayName');
      creatorName = 'Someone';
      if (typeof rawCreatorName === 'string') {
        try {
          creatorName = normalizeRequiredDisplayName(rawCreatorName);
        } catch {
          creatorName = 'Someone';
        }
      }
      applyEventFanIn(tx, fanIn, newId);
      return newId;
    });

    // #1059 stage 2: post-commit re-split disclosure — membership is already
    // committed, so nothing here may throw out of the callable; a lost row is
    // the accepted degrade (never a fabricated one).
    try {
      const detection = await detectResplitEvents(fanInCaptures);
      await writeResplitActivity(db, groupId, {
        memberId,
        memberName: displayName,
        actorId: uid,
        actorName: creatorName,
        memberAction: 'added',
        detection,
      });
    } catch (error) {
      logger.warn('resplit disclosure failed', { groupId, memberId, error: String(error) });
    }

    logger.info('addShadowMember created', { uid, groupId, memberId });
    return { memberId };
  },
);
