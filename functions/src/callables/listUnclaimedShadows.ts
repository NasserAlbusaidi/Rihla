import { getFirestore, DocumentData } from 'firebase-admin/firestore';
import { onCall, HttpsError, CallableRequest } from 'firebase-functions/v2/https';
import '../admin';
import { normalizeInviteCode, resolveGroupIdByInviteCode } from './shared/inviteCode';

// #278 claim/merge PR9 — pre-join discovery. A real (durable) person, BEFORE
// joining, lists the group's claimable placeholder ("shadow") members so the join
// screen can offer "is one of these you?". The members subcollection is read-gated
// (firestore.rules), so this MUST be a callable. No membership gate (D8 — the
// caller is pre-join). Returns ONLY {shadowMemberId, displayName} for genuinely
// claimable shadows — never a real member's identity, never balances. The
// claimable predicate is IDENTICAL to requestClaimShadow's (isShadow &&
// !isTombstone && userId ∈ memberIds), so a listed shadow is always requestable.

export interface ListUnclaimedShadowsInput {
  inviteCode: string;
}

export interface UnclaimedShadow {
  shadowMemberId: string;
  displayName: string;
}

export interface ListUnclaimedShadowsOutput {
  shadows: UnclaimedShadow[];
}

function getMemberIds(groupData: DocumentData): string[] {
  return Array.isArray(groupData.memberIds)
    ? groupData.memberIds.filter((m): m is string => typeof m === 'string')
    : [];
}

export const listUnclaimedShadows = onCall<ListUnclaimedShadowsInput, Promise<ListUnclaimedShadowsOutput>>(
  { enforceAppCheck: true },
  async (request: CallableRequest<ListUnclaimedShadowsInput>) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign-in required.');
    }
    // D6: claiming adopts a real identity → a durable account is required.
    if (request.auth.token?.firebase?.sign_in_provider === 'anonymous') {
      throw new HttpsError(
        'permission-denied',
        'A linked (non-anonymous) account is required.',
      );
    }

    const code = normalizeInviteCode(request.data?.inviteCode);
    const db = getFirestore();
    const groupId = await resolveGroupIdByInviteCode(db, code); // not-found for a bad code
    const groupRef = db.doc(`groups/${groupId}`);
    const groupSnap = await groupRef.get();
    if (!groupSnap.exists) {
      throw new HttpsError('not-found', 'Group not found.');
    }
    const groupData = groupSnap.data() ?? {};
    if (groupData.isDeleted === true || groupData.deletingInProgress === true) {
      throw new HttpsError('not-found', 'Group not found.');
    }

    const memberIds = getMemberIds(groupData);
    // Same claimable predicate as requestClaimShadow:97-101 — applied across every
    // shadow doc. A tombstoned shadow or one whose userId is no longer in memberIds
    // (a half-retired relic) is excluded, so every returned shadow is requestable.
    const snap = await groupRef
      .collection('members')
      .where('isShadow', '==', true)
      .get();

    const shadows: UnclaimedShadow[] = snap.docs
      .map((doc) => doc.data())
      .filter(
        (m) =>
          m.isTombstone !== true
          && typeof m.userId === 'string'
          && memberIds.includes(m.userId),
      )
      .map((m) => ({
        shadowMemberId: m.userId as string,
        displayName: typeof m.displayName === 'string' ? m.displayName : 'Member',
      }));

    return { shadows };
  },
);
