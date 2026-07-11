import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { getMessaging, Message } from 'firebase-admin/messaging';
import { logger } from 'firebase-functions/v2';
import { createHash } from 'crypto';
import '../admin';
import { Locale, normalizeLocale } from './strings';

export interface NotificationCopy {
  title: string;
  body: string;
}

/** Builds the localized copy for one recipient's stored locale. */
export type CopyBuilder = (locale: Locale) => NotificationCopy;

export interface SendToUidsOptions {
  dedupeKey?: string;
  /**
   * #1141 membership fence. When set to a group id, targets are intersected
   * with a FRESH read of groups/{gid}.memberIds immediately before delivery;
   * lookup failure (missing doc, absent/non-array field, read error) sends
   * NOTHING — never the committed recipient list. Pass it wherever the
   * recipient contract is "current group member"; omit it for deliberate
   * cross-membership sends (claim-decision Branch B).
   * The unavoidable residue: a member who leaves after this read but before
   * FCM fan-out still receives the push — revocation and delivery cannot be
   * atomic. The fence shrinks the window from commit→send to read→send.
   */
  requireCurrentMembershipOf?: string;
}

// FCM error codes that mean the token is permanently dead → prune it so the
// fcm_tokens collection self-cleans. `invalid-argument` is included because a
// malformed/garbage token row produces it and is equally unrecoverable.
const PRUNABLE_ERROR_CODES = new Set<string>([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
  'messaging/invalid-argument',
]);
const NOTIFICATION_DELIVERY_TTL_MS = 90 * 24 * 60 * 60 * 1000;

interface TokenRecord {
  uid: string;
  token: string;
  locale: Locale;
}

// #1141 — fresh membership read for the fence. null = lookup failed or the
// group/field is unusable; callers treat null as "send nothing" (fail-closed).
async function currentMemberIds(gid: string): Promise<Set<string> | null> {
  try {
    const snap = await getFirestore().doc(`groups/${gid}`).get();
    if (!snap.exists) return null;
    const ids = snap.data()?.memberIds;
    if (!Array.isArray(ids)) return null;
    return new Set(ids.filter((v): v is string => typeof v === 'string'));
  } catch (error) {
    logger.warn('fcm membership fence lookup failed', { gid, error: String(error) });
    return null;
  }
}

async function claimDeliveryMarker(
  dedupeKey: string | undefined,
  data: Record<string, string>,
): Promise<boolean> {
  const key = typeof dedupeKey === 'string' ? dedupeKey.trim() : '';
  if (key.length === 0) return true;

  try {
    const db = getFirestore();
    const deliveryId = createHash('sha256').update(key).digest('hex');
    const markerRef = db.doc(`notificationDeliveries/${deliveryId}`);
    return await db.runTransaction(async (tx) => {
      const existing = await tx.get(markerRef);
      if (existing.exists) return false;
      const now = Timestamp.now();
      tx.create(markerRef, {
        key,
        data,
        createdAt: now,
        expiresAt: Timestamp.fromMillis(now.toMillis() + NOTIFICATION_DELIVERY_TTL_MS),
      });
      return true;
    });
  } catch (error) {
    logger.warn('fcm delivery marker failed', {
      dedupeKey: key,
      error: String(error),
    });
    return false;
  }
}

/**
 * Sends a localized push to each uid that has a stored FCM token.
 *
 * - Dedups uids and drops empties; reads `fcm_tokens/{uid}`; skips any uid with
 *   no/empty token (shadow members, opted-out users) silently.
 * - One per-token [Message] localized via `build(locale)` so each recipient gets
 *   their own language; `data` (all string values, FCM requirement) drives the
 *   client tap route.
 * - `sendEach` is per-message, so one dead token never fails the batch. Dead
 *   tokens (not-registered / invalid) are pruned from Firestore.
 * - NEVER throws: this runs from fire-after-commit triggers and a committed join;
 *   a notification failure must not surface as an operation failure.
 */
export async function sendToUids(
  uids: string[],
  build: CopyBuilder,
  data: Record<string, string>,
  options: SendToUidsOptions = {},
): Promise<void> {
  try {
    const db = getFirestore();
    let uniqueUids = [
      ...new Set(uids.filter((u) => typeof u === 'string' && u.length > 0)),
    ];

    // #1141 membership fence: intersect targets with a FRESH memberIds read
    // BEFORE the marker claim. A lookup failure sends nothing (fail-closed);
    // a refused/empty send must not burn the dedupe key, so a duplicate trigger
    // invocation (the only redelivery path — no notifier sets retry) can still
    // deliver to eligible recipients later.
    const fenceGid =
      typeof options.requireCurrentMembershipOf === 'string'
        ? options.requireCurrentMembershipOf.trim()
        : '';
    if (fenceGid.length > 0) {
      const members = await currentMemberIds(fenceGid);
      if (members === null) {
        logger.warn('fcm membership fence refused send', { gid: fenceGid });
        return;
      }
      uniqueUids = uniqueUids.filter((uid) => members.has(uid));
    }
    if (uniqueUids.length === 0) return;

    if (!(await claimDeliveryMarker(options.dedupeKey, data))) return;

    const snaps = await Promise.all(
      uniqueUids.map((uid) => db.doc(`fcm_tokens/${uid}`).get()),
    );

    const records: TokenRecord[] = [];
    snaps.forEach((snap, i) => {
      const tokenData = snap.data();
      const token = tokenData?.token;
      if (typeof token === 'string' && token.length > 0) {
        records.push({
          uid: uniqueUids[i],
          token,
          locale: normalizeLocale(tokenData?.locale),
        });
      }
    });

    if (records.length === 0) return;

    const messages: Message[] = records.map((r) => {
      const copy = build(r.locale);
      return {
        token: r.token,
        notification: { title: copy.title, body: copy.body },
        data,
        android: { priority: 'high' as const },
      };
    });

    const response = await getMessaging().sendEach(messages);

    const pruneUids: string[] = [];
    response.responses.forEach((resp, idx) => {
      if (resp.success) return;
      const code = resp.error?.code;
      if (code && PRUNABLE_ERROR_CODES.has(code)) {
        pruneUids.push(records[idx].uid);
      } else {
        logger.warn('fcm message failed', { uid: records[idx].uid, code });
      }
    });

    if (pruneUids.length > 0) {
      await Promise.all(
        pruneUids.map((uid) =>
          db
            .doc(`fcm_tokens/${uid}`)
            .delete()
            .catch((e) =>
              logger.warn('fcm token prune failed', { uid, error: String(e) }),
            ),
        ),
      );
    }
  } catch (error) {
    logger.warn('fcm send aborted', { error: String(error) });
  }
}
