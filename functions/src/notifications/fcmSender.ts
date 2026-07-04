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
    if (!(await claimDeliveryMarker(options.dedupeKey, data))) return;

    const db = getFirestore();
    const uniqueUids = [
      ...new Set(uids.filter((u) => typeof u === 'string' && u.length > 0)),
    ];
    if (uniqueUids.length === 0) return;

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
